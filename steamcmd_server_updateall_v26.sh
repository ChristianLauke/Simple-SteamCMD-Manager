#!/usr/bin/env bash
# ==============================================================================
# TITEL       : SteamCMD Install/Update Dedicated Server
# BESCHREIBUNG: Skript zur einfacheren Parametrisierung von SteamCMD inkl. Backup/Restore
# AUTOR       : Christian Lauke
# DATUM       : 2026-10-17
# VERSION     : 1.1.0
# USAGE       : ./steamcmd_server_updateall_v26.sh [args]
# ==============================================================================

# Strikte Sicherheitsoptionen
set -o errexit    # Abbrechen bei Fehlern
set -o nounset    # Abbrechen bei ungesetzten Variablen
set -o pipefail   # Abbrechen bei Pipeline-Fehlern
set -o noclobber  # noclobber: Verhindert versehentliches Überschreiben von Dateien mit '>'
set -o noglob     # noglob: Deaktiviert Wildcard-Expansion (*, ?) zur Vermeidung von Injection-Fehlern

# Globale Pfad- und Standard-Konfiguration
readonly BACKUP_DIR='/opt/steam/backups' # Backup Pfad
readonly BACKUP_USE_RSYNC='Y' # Statt eines tgz-archives die Serverfiles mittels rsync spiegeln [Y/n]
readonly BACKUP_VERBOSE='N' # Backupausgabe anzeigen [y/N]
readonly INSTALL_DEFAULT_DIR='/opt/steam/server' # Serverpfad
readonly INSTALL_DEFAULT_PLATFORM='linux' # Server Plattform, wenn Angabe fehlt [linux/windows]
readonly INSTALL_DEFAULT_LOGIN='anonymous' # Steam Login
readonly INSTALL_STEAM_ACCOUNT='' # Steam Login bei Option --use-login

# Definition der standardisierten Return-Codes als Konstanten
readonly RC_SUCCESS=0
readonly RC_INVALID_ARGS=2
readonly RC_GAME_NOT_FOUND=3
readonly RC_WORKSHOP_FAILED=4
readonly RC_USER_ABORT=5
readonly RC_MASS_UPDATE_FAILED=10
readonly RC_STEAM_ACCOUNT_REQUIRED=11

# Laufzeitvariablen initialisieren
VALIDATE=''
TARGET_GAMES_LIST=''
DEBUG_MODE=false
USE_CUSTOM_LOGIN=false
DO_BACKUP=false
DO_RESTORE=false
DO_PURGE=false
errors=0
current_key=''
rc_update_game=0

# Variablen für die Fortschrittsanzeige
readonly TIME_FORMAT='--format=Elapsed real time: %E [hh:mm:ss]'
current_update_index=0
total_updates=0

# Farben definieren (nur wenn die Ausgabe in ein echtes Terminal erfolgt)
if [[ -t 1 ]]; then
    readonly COLOR_RESET='\033[0m'
    readonly COLOR_INFO='\033[1;34m'    # Blau fett
    readonly COLOR_SUCCESS='\033[1;32m' # Grün fett
    readonly COLOR_WARN='\033[1;33m'    # Gelb fett
    readonly COLOR_ERROR='\033[1;31m'   # Rot fett
    readonly COLOR_LINE='\033[0;36m'    # Cyan dünn
else
    readonly COLOR_RESET=''
    readonly COLOR_INFO=''
    readonly COLOR_SUCCESS=''
    readonly COLOR_WARN=''
    readonly COLOR_ERROR=''
    readonly COLOR_LINE=''
fi

# Zentrale Spielserver-Definition (Name | Status;Platform;AppID;SubDir;Login;WorkshopIDs...)
# Bleiben Platform oder Login leer, greift der Default (linux / anonymous)
declare -A SUPPORTED_GAME_LIST=(
    # aktive Spiele

    # weitere Spiele
    ['7dtd']='ACTIVE;linux;294420;7dtd;anonymous'
    ['ark']='BACKUP;linux;376030;ark;anonymous'
    ['ark_ascended']='BACKUP;linux;2430930;ark_ascended;anonymous'
    ['cs']='BACKUP;linux;90;cs;anonymous'
    ['css']='BACKUP;linux;232330;css;anonymous'
    ['conan']='ACTIVE;linux;443030;conan;anonymous;3725018456 3720948133 3720904511 3720921242 3720326124 3724911120 3748867573'
    ['dayz']='BACKUP;linux;223350;dayz;Chris2480;1559212036 1828439124'
    ['enshrouded']='ACTIVE;windows;2278520;enshrouded;anonymous'
    ['gmod']='BACKUP;linux;4020;gmod;anonymous'
    ['kf2']='BACKUP;linux;232130;kf2;anonymous'
    ['l4d2']='BACKUP;linux;222860;l4d2;anonymous'
    ['mesa']='BACKUP;linux;346680;mesa;anonymous'
    ['palworld']='ACTIVE;linux;2394010;palworld;anonymous'
    ['perfect_heist2']='BACKUP;linux;1964150;perfect_heist2;anonymous'
    ['quake']='BACKUP;linux;349090;quake;anonymous'
    ['rust']='BACKUP;linux;258550;rust;anonymous'
    ['sotf']='BACKUP;windows;2465200;sons_of_the_forest;anonymous'
    ['soulmask']='BACKUP;linux;3017300;soulmask;anonymous'
    ['valheim']='ACTIVE;linux;896660;valheim;anonymous'
    ['vrising']='ACTIVE;windows;1829350;vrising;anonymous'
    ['windrose']='BACKUP;linux;4129620;windrose;anonymous'
)

# Cleanup- und Fehler-Handler für unvorhergesehene Abbrüche
cleanup() {
    local rc_code=${?}
    if [ ${rc_code} -ne 0 ]; then
        echo -e "${COLOR_LINE}--------------------------------------------------${COLOR_RESET}" >&2
        echo -e "${COLOR_ERROR}FEHLER: Das Skript wurde unerwartet mit Code ${rc_code} beendet!${COLOR_RESET}" >&2
        echo -e "${COLOR_LINE}--------------------------------------------------${COLOR_RESET}" >&2
    fi
    exit ${rc_code}
}
trap cleanup EXIT SIGINT SIGTERM

# Hilfe-Anzeige
show_help() {
    local key=''
    echo "Nutzung: ${0} [OPTIONEN]"
    echo ''
    echo 'Optionen:'
    echo '  -v, --validate         Aktiviert die Validierung der Serverdateien in SteamCMD.'
    echo '  -g, --game [KEYS]      Aktualisiert spezifische Spiele, kommagetrennt (z. B. cs,css,palworld).'
    echo '  -l, --use-login        Verwendet anstelle von anonymous das im Skript hinterlegte Steam Konto.'
    echo '  -b, --backup           Erstellt vorab eine Datensicherung des Serverpfads.'
    echo '  -r, --restore          Stellt einen Server aus der Datensicherung wieder her.'
    echo '  -p, --purge            Löscht die Spieldateien (Interaktive Abfrage).'
    echo '  -d, --debug            Aktiviert den detaillierten Shell-Debug-Modus (xtrace).'
    echo '  -h, --help             Zeigt diese Hilfe an.'
    echo ''
    echo -e "${COLOR_INFO}Spiele im automatischen update:${COLOR_RESET}"
    for key in "${!SUPPORTED_GAME_LIST[@]}"; do
        if [[ "${SUPPORTED_GAME_LIST[$key]}" == ACTIVE\;* ]]; then
            echo "  - ${key}"
        fi
    done | sort
    echo ''
    echo -e "${COLOR_WARN}weitere unterstütze Spiele (-g 'KEY[,KEYS]'):${COLOR_RESET}"
    for key in "${!SUPPORTED_GAME_LIST[@]}"; do
        if [[ "${SUPPORTED_GAME_LIST[$key]}" == BACKUP\;* ]]; then
            echo "  - ${key}"
        fi
    done | sort
}

# Prüft, ob ein Server läuft, indem es sucht, ob der Pfad von einem Prozess verwendet wird
is_server_running() {
    local path="${1}"
    # pgrep sucht nach laufenden Prozessen, die diesen Pfad in ihrer Kommandozeile enthalten
    if pgrep -f "${path}(/|$)" > /dev/null 2>&1; then
        return 0 # Läuft
    else
        return 1 # Läuft nicht
    fi
}

# Funktion zur Erstellung einer Datensicherung (rsync oder tar)
create_backup() {
    local key="${1}"
    local subdir="${2}"
    local full_path="${INSTALL_DEFAULT_DIR}/${subdir}"

    if [ ! -d "${full_path}" ]; then
        echo -e "${COLOR_WARN}WARNUNG: Pfad ${full_path} existiert nicht. Backup für ${key} übersprungen.${COLOR_RESET}"
        return 0
    fi
    
    # Backuppfad anlegen
    mkdir --parent --verbose "${BACKUP_DIR}"
    
    # Logik: Rsync oder Tar wählen
    if [ "${BACKUP_USE_RSYNC^^}" = 'Y' ]; then
        echo -e "${COLOR_INFO}[rsync] Erstelle Datensicherung für ${key}...${COLOR_RESET}"
        # Dynamische Argumente für rsync zusammenbauen
        local target_dir="${BACKUP_DIR}/${subdir}" # Zielverzeichnis für rsync
        local rsync_args=(--archive --delete)
        if [ "${BACKUP_VERBOSE^^}" = 'Y' ]; then
            rsync_args+=(--verbose)
        fi
        # Rsync spiegelt das Verzeichnis (1:1 Kopie)
        if '/usr/bin/time' "${TIME_FORMAT}" rsync "${rsync_args[@]}" "${full_path}/" "${target_dir}/"; then
            echo -e "${COLOR_SUCCESS}SUCCESS: Rsync-Backup für ${key} in ${target_dir} erstellt.${COLOR_RESET}"
            return 0
        else
            echo -e "${COLOR_ERROR}ERROR: Rsync-Backup für ${key} fehlgeschlagen!${COLOR_RESET}" >&2
            return 1
        fi
    else
        echo -e "${COLOR_INFO}[tar] Erstelle Datensicherung für ${key}...${COLOR_RESET}"
        # Dynamische Argumente für tar zusammenbauen
        local sysdate
        sysdate="$(date +%Y-%m-%d)"
        local backup_file="${BACKUP_DIR}/server_${key}_bck${sysdate}.tgz"
        local tar_args=(--gzip --create)
        if [ "${BACKUP_VERBOSE^^}" = 'Y' ]; then
            tar_args+=(--verbose)
        fi
        tar_args+=(--file "${backup_file}" -C "${INSTALL_DEFAULT_DIR}" "${subdir}")
        
        # Deaktiviere noclobber temporär, da tar die Zieldatei neu schreibt/überschreibt
        set +C
        
        # Ausführen des tar-Befehls und prüfen Exit-Codes
        if '/usr/bin/time' "${TIME_FORMAT}" tar "${tar_args[@]}"; then
            echo -e "${COLOR_SUCCESS}SUCCESS: Tar-Backup für ${key} erfolgreich erstellt: ${backup_file}${COLOR_RESET}"
            set -C
            return 0
        else
            echo -e "${COLOR_ERROR}ERROR: Tar-Backup für ${key} fehlgeschlagen!${COLOR_RESET}" >&2
            set -C
            return 1
        fi
    fi
}

restore_server() {
    local key="${1}"
    local subdir="${2}"
    local source_dir="${BACKUP_DIR}/${subdir}"
    local target_dir="${INSTALL_DEFAULT_DIR}/${subdir}"
    
    # Sicherheitscheck: Läuft der Server?
    if is_server_running "${target_dir}"; then
        echo -e "${COLOR_ERROR}FEHLER: Server '${key}' läuft! Stoppe ihn, bevor du ein Restore durchführst.${COLOR_RESET}" >&2
        return 1
    fi
    
    # Schutz vor nicht-interaktivem Aufruf (z. B. Cronjob)
    if [[ ! -t 0 ]]; then
        echo -e "${COLOR_ERROR}ERROR: Restore ist im non-interaktiven Modus (Cronjob) nicht erlaubt!${COLOR_RESET}" >&2
        return 1
    fi
    
    echo -e "${COLOR_WARN}ACHTUNG: Du bist im Begriff, '${key}' aus dem Backup wiederherzustellen!${COLOR_RESET}"
    echo -e "${COLOR_WARN}Dies überschreibt alle aktuellen Daten in ${target_dir}.${COLOR_RESET}"
    
    local user_response=''
    read -rp 'Wirklich wiederherstellen? [y/N]: ' user_response
    if [[ "${user_response^^}" != "Y" && "${user_response^^}" != "J" ]]; then
        echo -e "${COLOR_INFO}Abbruch durch Benutzer. Restore wurde nicht durchgeführt.${COLOR_RESET}"
        return ${RC_USER_ABORT}
    fi
    
    if [ "${BACKUP_USE_RSYNC^^}" = 'Y' ]; then
        if [ ! -d "${source_dir}" ]; then
            echo -e "${COLOR_ERROR}Kein Rsync-Backup-Verzeichnis (${source_dir}) für ${key} gefunden!${COLOR_RESET}" >&2
            return 1
        fi
        mkdir --parent --verbose "${target_dir}"
        echo -e "${COLOR_INFO}[rsync] Stelle Daten wieder her...${COLOR_RESET}"
        # Dynamische Argumente für rsync zusammenbauen
        local rsync_args=(--archive --delete)
        if [ "${BACKUP_VERBOSE^^}" = 'Y' ]; then
            rsync_args+=(--verbose)
        fi
        '/usr/bin/time' "${TIME_FORMAT}" rsync "${rsync_args[@]}" "${source_dir}/" "${target_dir}/"
    else
        echo -e "${COLOR_INFO}[tar] Suche neustes Archiv für ${key}...${COLOR_RESET}"
        # Findet die neueste .tgz Datei im Backup-Ordner für diesen Server
        local latest_backup=''
        # Temporär Wildcards und pipefail lockern, falls kein Archiv existiert
        set +f +o pipefail
        latest_backup=$(ls -t "${BACKUP_DIR}/server_${key}_bck"*.tgz 2>/dev/null | head -n 1)
        set -f -o pipefail
        
        if [ -z "${latest_backup}" ]; then
            echo -e "${COLOR_ERROR}Kein Backup-Archiv für ${key} gefunden!${COLOR_RESET}" >&2
            return 1
        fi
        mkdir --parent --verbose "${target_dir}"
        echo -e "${COLOR_INFO}Entpacke: ${latest_backup}${COLOR_RESET}"
        # Dynamische Argumente für rsync zusammenbauen
        local tar_args=(--gzip --extract)
        if [ "${BACKUP_VERBOSE^^}" = 'Y' ]; then
            tar_args+=(--verbose)
        fi
        tar_args+=(--file "${latest_backup}" -C "${INSTALL_DEFAULT_DIR}")
        '/usr/bin/time' "${TIME_FORMAT}" tar "${tar_args[@]}"
    fi
    
    echo -e "${COLOR_SUCCESS}SUCCESS: Restore für ${key} abgeschlossen.${COLOR_RESET}"
}

# Zentrale Update-Funktion mit Return Code Handling
update_game() {
    local key="${1}"
    local data="${2}"
    
    # Splitten der Parameter anhand des Semikolons
    local game_status='' platform='' app_id='' subdir='' login='' workshop_ids=''
    IFS=';' read -r game_status platform app_id subdir login workshop_ids <<< "${data}"
    
    # Fallback-Logik für optionale/leere Werte
    if [ -z "${platform}" ]; then platform="${INSTALL_DEFAULT_PLATFORM}"; fi
    if [ -z "${login}" ]; then login="${INSTALL_DEFAULT_LOGIN}"; fi
    
    # Übersteuerung durch den Schalter -l / --use-login (nur wenn vorher anonymous aktiv war)
    if [ "${USE_CUSTOM_LOGIN}" = true ] && [ "${login}" = "${INSTALL_DEFAULT_LOGIN}" ]; then
        login="${INSTALL_STEAM_ACCOUNT}"
    fi
    
    # Vollständigen Installationspfad zusammensetzen
    local full_install_dir="${INSTALL_DEFAULT_DIR}/${subdir}"
    
    # Inkrementiere den aktuellen Fortschritts-Index
    ((++current_update_index))
    
    # Update-Header ausgeben
    echo -e "${COLOR_LINE}--------------------------------------------------${COLOR_RESET}"
    echo -e "${COLOR_INFO}Starte Update für: ${key} (${current_update_index}/${total_updates})${COLOR_RESET}"
    echo "Plattform: ${platform} | App-ID: ${app_id} | Pfad: ${full_install_dir} | Login: ${login}"
    echo -e "${COLOR_LINE}--------------------------------------------------${COLOR_RESET}"
    
    # Überspringe den aktuellen Server, falls derzeit eine Instanz läuft
    if is_server_running "${full_install_dir}"; then
        echo -e "${COLOR_WARN}Überspringe '${key}': Der Server läuft aktuell! (${full_install_dir})${COLOR_RESET}"
        return 0
    fi
    
    # ==========================================================================
    # PIPELINE-SCHRITT 1: BACKUP, RESTORE UND/ODER LÖSCH-MODUS
    # ==========================================================================
    if [ "${DO_BACKUP}" = true ]; then
        if ! create_backup "${key}" "${subdir}"; then
            return 1
        fi
        
        # Backup-Modus: Wenn NICHT gelöscht und NICHT geupdatet wird, hier beenden
        if [ "${DO_PURGE}" = false ] && [ -z "${VALIDATE}" ] && [ -n "${TARGET_GAMES_LIST}" ]; then
            echo -e "${COLOR_SUCCESS}Reiner Backup-Modus für ${key} abgeschlossen.${COLOR_RESET}"
            return 0
        fi
    fi
    
    if [ "${DO_RESTORE}" = true ]; then
        restore_server "${key}" "${subdir}"
        return ${?} # Nach dem Restore beenden, da sonst das Update startet
    fi
    
    if [ "${DO_PURGE}" = true ]; then
        remove_server "${key}" "${subdir}"
        return ${?}
    fi
    
    # ==========================================================================
    # PIPELINE-SCHRITT 2: STEAMCMD UPDATE-PROZESS
    # ==========================================================================
    # Basis-Argumente für SteamCMD zusammenbauen
    local cmd_args=(
        +@sSteamCmdForcePlatformType "${platform}"
        +force_install_dir "${full_install_dir}"
        +login "${login}"
        +app_update "${app_id}"
    )
    
    # Validierung anhängen falls aktiv
    if [ -n "${VALIDATE}" ]; then
        cmd_args+=("${VALIDATE}")
    fi
    
    # Workshop-Items hinzufügen falls vorhanden
    if [ -n "${workshop_ids}" ]; then
        local workshop_app="${app_id}"
        # Korrektur einiger Workshops vom Server-Workshop auf den Client-Workshop
        case "${key}" in
            dayz)     workshop_app="221100" ;;
            conan)    workshop_app="440900" ;;
            palworld) workshop_app="1623730" ;;
        esac
        
        # Sicherer Split trotz 'set -f'
        local workshop_array=()
        IFS=' ' read -r -a workshop_array <<< "${workshop_ids}"
        
        local workshop_id
        for workshop_id in "${workshop_array[@]}"; do
            cmd_args+=(+workshop_download_item "${workshop_app}" "${workshop_id}")
            if [ -n "${VALIDATE}" ]; then
                cmd_args+=("${VALIDATE}")
            fi
        done
    fi
    
    # SteamCMD beenden
    cmd_args+=(+quit)
    
    # Hilfsvariable für Workshop-Fehlererkennung
    local workshop_failed=false
    
    # Deaktiviere noclobber temporär, damit mktemp-Zuweisung klappt
    set +C
    local tmp_log
    tmp_log=$(mktemp)
    set -C
    
    # Pipefreie Ausführung für absolute set -o pipefail Immunität
    set +e +f +C
    
    # Startet die Überwachung im Hintergrund und schreibt live ins Terminal
    tail -f "${tmp_log}" &
    local tail_pid=${!}
    
    # SteamCMD schreibt direkt in die Datei (ohne Pipe)
    steamcmd "${cmd_args[@]}" > "${tmp_log}" 2>&1
    local rc=${?}
    
    # Beendet die Hintergrund-Überwachung sauber
    kill "${tail_pid}" 2>/dev/null || true
    wait "${tail_pid}" 2>/dev/null || true
    
    # Scan nach Workshop-Fehlern NOCH im geschützten set +e Bereich ausführen,
    # damit ein Nicht-Finden (Grep Exit-Code 1) das Skript nicht zum Absturz bringt.
    if grep -q "ERROR! Download item" "${tmp_log}" || grep -q "ERROR! Failed to get install info" "${tmp_log}"; then
        workshop_failed=true
    fi
    
    # Aufräumen der temporären Datei
    rm -f "${tmp_log}"
    
    # Sicherheitsmodi wieder aktivieren
    set -e -f -C
    
    # Status-Auswertung
    if [ ${rc} -ne 0 ] || [ "${workshop_failed}" = true ]; then
        # Wenn SteamCMD 0 meldet, aber der Workshop fehlschlug, nutzen wir unsere Konstante
        if [ ${rc} -eq 0 ]; then
            rc=${RC_WORKSHOP_FAILED}
            echo -e "${COLOR_ERROR}ERROR: Update für ${key} fehlgeschlagen (Kritischer Workshop-Fehler). Code ${rc}.${COLOR_RESET}" >&2
        else
            # Wenn SteamCMD selbst einen echten Fehler > 0 hatte, geben wir diesen dynamisch aus
            echo -e "${COLOR_ERROR}ERROR: Update für ${key} fehlgeschlagen mit nativem SteamCMD Code ${rc}.${COLOR_RESET}" >&2
        fi
        return ${rc}
    else
        echo -e "${COLOR_SUCCESS}SUCCESS: ${key} erfolgreich aktualisiert.${COLOR_RESET}"
        return ${RC_SUCCESS}
    fi
}

# Funktion zum sicheren Entfernen eines Serverpfads
remove_server() {
    local key="${1}"
    local subdir="${2}"
    local full_path="${INSTALL_DEFAULT_DIR}/${subdir}"

    if [ ! -d "${full_path}" ]; then
        echo -e "${COLOR_WARN}WARNUNG: Pfad ${full_path} existiert nicht.${COLOR_RESET}"
        return 0
    fi

    # Schutz vor automatisiertem/unbeabsichtigtem Löschen im Cronjob
    if [[ ! -t 0 ]]; then
        echo -e "${COLOR_ERROR}ERROR: Löschen von Verzeichnissen ist im non-interaktiven Modus (Cronjob) nicht erlaubt!${COLOR_RESET}" >&2
        return 1
    fi

    # Interaktive Sicherheitsabfrage im Terminal
    echo -e "${COLOR_WARN}ACHTUNG: Du bist im Begriff, das Verzeichnis für '${key}' komplett zu löschen!${COLOR_RESET}"
    echo -e "${COLOR_WARN}Pfad: ${full_path}${COLOR_RESET}"
    
    local user_response=''
    read -rp 'Möchtest du diesen Serverpfad wirklich unwiderruflich entfernen? [y/N]: ' user_response
    
    if [[ "${user_response^^}" == "Y" ]] || [[ "${user_response^^}" == "J" ]]; then
        echo -e "${COLOR_INFO}Lösche Verzeichnis ${full_path}...${COLOR_RESET}"
        rm -rf "${full_path}"
        echo -e "${COLOR_SUCCESS}SUCCESS: Serververzeichnis für ${key} wurde gelöscht.${COLOR_RESET}"
    else
        echo -e "${COLOR_INFO}Abbruch durch Benutzer. Pfad wurde nicht gelöscht.${COLOR_RESET}"
        return ${RC_USER_ABORT}
    fi
}

# ==============================================================================
# Main
# ==============================================================================			   

# Parsing der Argumente mittels GNU getopt
PARSED_OPTIONS=$(getopt -o vg:lbrpdh --long validate,game:,use-login,backup,restore,purge,debug,help -n "$0" -- "$@") || { show_help; exit ${RC_INVALID_ARGS}; }
eval set -- "${PARSED_OPTIONS}"

while true; do
    case "${1}" in
        -v|--validate)  VALIDATE="validate"; shift ;;
        -g|--game)      TARGET_GAMES_LIST="${2}"; shift 2 ;;
        -l|--use-login) USE_CUSTOM_LOGIN=true; shift ;;
        -b|--backup)    DO_BACKUP=true; shift ;;
        -r|--restore)   DO_RESTORE=true; shift ;;
        -p|--purge)     DO_PURGE=true; shift ;;
        -d|--debug)     DEBUG_MODE=true; shift ;;
        -h|--help)      show_help; exit ${RC_SUCCESS} ;;
        --)             shift; break ;;
        *)              echo -e "${COLOR_ERROR}Interner Fehler beim Parsing!${COLOR_RESET}" >&2; exit ${RC_INVALID_ARGS} ;;
    esac
done

# Account-Abfrage (nur wenn -l/--use-login genutzt wird und noch kein Account hinterlegt wurde)
if [ "${USE_CUSTOM_LOGIN}" = true ] && [ -z "${INSTALL_STEAM_ACCOUNT}" ]; then
    echo -e "${COLOR_WARN}FEHLER: --use-login angefordert, aber INSTALL_STEAM_ACCOUNT ist leer.${COLOR_RESET}" >&2
    echo -e "${COLOR_INFO}LÖSUNG: Bitte bearbeite dieses Skript und trage deinen Account-Namen bei 'INSTALL_STEAM_ACCOUNT' ein.${COLOR_RESET}" >&2
    exit ${RC_STEAM_ACCOUNT_REQUIRED}
fi

# Wenn Debug-Modus aktiv ist, xtrace einschalten
if [ "${DEBUG_MODE}" = true ]; then
    set -x
fi

# Exklusivitäts-Check: Restore ist inkompatibel mit Backup und Purge.
if [ "${DO_RESTORE}" = true ] && ([ "${DO_BACKUP}" = true ] || [ "${DO_PURGE}" = true ]); then
    echo -e "${COLOR_ERROR}FEHLER: Restore kann nicht mit Backup oder Purge kombiniert werden!${COLOR_RESET}" >&2
    exit ${RC_INVALID_ARGS}
fi

# Ablaufsteuerung
if [ -n "${TARGET_GAMES_LIST}" ]; then
    # Kommagetrennte Liste in ein Bash-Array splitten (set +f temporär erlaubt Wort-Splitting am Komma)
    set +f
    IFS=',' read -r -a target_games_array <<< "${TARGET_GAMES_LIST}"
    set -f
    
    total_updates="${#target_games_array[@]}"
    
    if [ "${DO_PURGE}" = true ] && [ "${DO_BACKUP}" = true ]; then
        echo -e "${COLOR_WARN}Starte Backup- UND Lösch-Modus für ${total_updates} ausgewählte(s) Verzeichnis(se)...${COLOR_RESET}"
    elif [ "${DO_PURGE}" = true ]; then
        echo -e "${COLOR_WARN}Starte Lösch-Modus für ${total_updates} ausgewählte(s) Verzeichnis(se)...${COLOR_RESET}"
    elif [ "${DO_BACKUP}" = true ] && [ -z "${VALIDATE}" ]; then
        echo -e "${COLOR_INFO}Starte reinen Backup-Modus für ${total_updates} ausgewählte(s) Verzeichnis(se)...${COLOR_RESET}"
    elif [ "${DO_RESTORE}" = true ]; then
        echo -e "${COLOR_WARN}Starte Restore-Modus für ${total_updates} ausgewählte(s) Verzeichnis(se)...${COLOR_RESET}"
    else
        echo -e "${COLOR_INFO}Starte Aktualisierung von ${total_updates} ausgewählten Servern...${COLOR_RESET}"
    fi
    
    for game_key in "${target_games_array[@]}"; do
        if [ -n "${SUPPORTED_GAME_LIST[$game_key]+Anker}" ]; then
            # Spielunterstützung prüfen, bei unsupporteten Spielen hart abbrechen
            update_game "${game_key}" "${SUPPORTED_GAME_LIST[$game_key]}" || exit ${?}
        else
            echo -e "${COLOR_ERROR}Fehler: Spiel '${game_key}' existiert nicht in der Konfiguration.${COLOR_RESET}" >&2
            exit ${RC_GAME_NOT_FOUND}
        fi
    done
else
    # Standard-Modus: Alle aktiven Spielserver alphabetisch-sortiert aktualisieren
    mapfile -t active_keys < <(
        for key in "${!SUPPORTED_GAME_LIST[@]}"; do
            if [[ "${SUPPORTED_GAME_LIST[$key]}" == ACTIVE\;* ]]; then
                echo "${key}"
            fi
        done | sort
    )
    
    total_updates="${#active_keys[@]}"
    echo -e "${COLOR_INFO}Starte Aktualisierung aller ${total_updates} aktiven Dedicated Server...${COLOR_RESET}"
    
    for current_key in "${active_keys[@]}"; do
        # Fehler in Unterfunktionen ignorieren wir hier für die Gesamtschleife
        set +e
        update_game "${current_key}" "${SUPPORTED_GAME_LIST[${current_key}]}"
        rc_update_game=${?}
        set -e
        
        if [ ${rc_update_game} -ne 0 ]; then
            ((++errors))
        fi
    done
    
    if [ ${errors} -gt 0 ]; then
        echo -e "${COLOR_ERROR}Massen-Update mit ${errors} Fehler(n) beendet.${COLOR_RESET}"
        exit ${RC_MASS_UPDATE_FAILED}
    fi
fi

echo -e "${COLOR_SUCCESS}Alle Aufgaben erfolgreich abgeschlossen.${COLOR_RESET}"
exit ${RC_SUCCESS}

# Last modified 17.10.2026 by Christian Lauke
