# SteamCMD Server Update & Management Tool (v1.1.0)

Dieses Bash-Skript bietet eine robuste, modulare und sichere Lösung zur automatisierten Verwaltung von Dedicated Game Servern mittels SteamCMD unter Linux. Es wurde mit Fokus auf Zuverlässigkeit, strikte Fehlerbehandlung und einfache Bedienung für Serveradministratoren entwickelt.

## Features

- **Zentrale Konfiguration (`SUPPORTED_GAME_LIST`):** Übersichtliche Verwaltung aller Server (Status `ACTIVE` oder `BACKUP`, Plattform, App-ID, Verzeichnis, Login und Steam-Workshop-IDs) in einer einzigen Steuertabelle.
- **Automatisierte Updates & Workshop-Support:** Aktualisiert Serverdateien sowie konfigurierte Steam-Workshop-Mods und prüft das Log automatisch auf versteckte Workshop-Downloadfehler.
- **Laufzeitschutz:** Erkennt über eine Prozessprüfung (`pgrep`), ob ein Spielserver aktuell läuft, und überspringt diesen bei Updates oder blockiert ein versehentliches Restore.
- **Flexible Backup-Lösung (`rsync` & `tar`):** Unterstützt wahlweise schnelle 1:1-Verzeichnisspiegelungen mittels `rsync` (Standard) oder komprimierte `.tgz`-Archive inkl. Laufzeitmessung (`/usr/bin/time`).
- **Sicheres Restore & Purge:** Wiederherstellung und Löschung von Serververzeichnissen sind durch interaktive Sicherheitsabfragen, einen Exklusivitäts-Check (kein gleichzeitiges Restore mit Backup/Purge) sowie eine Sperre für nicht-interaktive Sitzungen (Cronjob-Schutz) abgesichert.
- **Strikte Bash-Sicherheitsoptionen:** Gehärtet durch `errexit`, `nounset`, `pipefail`, `noclobber` und `noglob`.
- **Validierung & Debug-Modus:** Optionale Konsistenzprüfung der Spieldateien via SteamCMD sowie detailliertes Shell-Tracing (`xtrace`).

## Nutzung

```bash
./steamcmd_server_updateall_v26.sh [OPTIONEN]
```

Wird das Skript ohne `-g` / `--game` aufgerufen, aktualisiert es automatisch alle als `ACTIVE` markierten Spielserver in alphabetischer Reihenfolge.

### Argumente

| Option | Beschreibung |
| :--- | :--- |
| `-v`, `--validate` | Aktiviert die Validierung der Serverdateien in SteamCMD. |
| `-g`, `--game [KEYS]` | Verarbeitet spezifische Spiele, kommagetrennt (z. B. `cs,css,palworld`). |
| `-l`, `--use-login` | Verwendet anstelle von `anonymous` das im Skript hinterlegte Steam-Konto. |
| `-b`, `--backup` | Erstellt vorab eine Datensicherung (`rsync` oder `.tgz`) des Serverpfads. |
| `-r`, `--restore` | Stellt einen Server aus der Datensicherung wieder her (interaktive Abfrage). |
| `-p`, `--purge` | Löscht die Spieldateien des Servers (interaktive Sicherheitsabfrage). |
| `-d`, `--debug` | Aktiviert den detaillierten Shell-Debug-Modus (`xtrace`). |
| `-h`, `--help` | Zeigt die Hilfe und alle unterstützten Spiele-Keys an. |

### Anwendungsbeispiele

```bash
# Alle aktiven Server automatisch aktualisieren (Standard-Modus, z. B. für Cronjobs)
./steamcmd_server_updateall_v26.sh

# Gezieltes Update mit Datei-Validierung für Palworld und Valheim
./steamcmd_server_updateall_v26.sh -g palworld,valheim -v

# Reines Backup für einen bestimmten Server erstellen
./steamcmd_server_updateall_v26.sh -g 7dtd -b

# Backup erstellen und anschließend das Serververzeichnis sauber löschen
./steamcmd_server_updateall_v26.sh -g cs -b -p

# Server aus dem Backup wiederherstellen
./steamcmd_server_updateall_v26.sh -g cs -r
```

## Unterstützte Spiele

### Spiele im automatischen Update (`ACTIVE`)
`7dtd`, `conan`, `enshrouded`, `palworld`, `valheim`, `vrising`

### Weitere unterstützte Spiele (`BACKUP` – Abruf über `-g KEY`)
`ark`, `ark_ascended`, `cs`, `css`, `dayz`, `gmod`, `kf2`, `l4d2`, `mesa`, `perfect_heist2`, `quake`, `rust`, `sotf`, `soulmask`, `windrose`

## Return-Codes (Exit-Status)

| Code | Konstante | Bedeutung |
| :--- | :--- | :--- |
| `0` | `RC_SUCCESS` | Alle Aufgaben erfolgreich abgeschlossen. |
| `2` | `RC_INVALID_ARGS` | Ungültige Argumente oder inkompatible Modus-Kombination (z. B. Restore + Purge). |
| `3` | `RC_GAME_NOT_FOUND` | Angegebener Spiele-Key existiert nicht in `SUPPORTED_GAME_LIST`. |
| `4` | `RC_WORKSHOP_FAILED` | Kritischer Fehler beim Herunterladen eines Steam-Workshop-Items. |
| `5` | `RC_USER_ABORT` | Interaktive Sicherheitsabfrage (Restore/Purge) wurde vom Benutzer abgebrochen. |
| `10` | `RC_MASS_UPDATE_FAILED` | Mindestens ein Server-Update im Standard-Massenmodus ist fehlgeschlagen. |
| `11` | `RC_STEAM_ACCOUNT_REQUIRED` | `--use-login` wurde gewählt, aber `INSTALL_STEAM_ACCOUNT` ist leer. |

## Lizenz

Dieses Projekt ist unter der **MIT-Lizenz** lizenziert. Siehe `LICENSE` für Details.