# SteamCMD Server Update & Management Tool (v1.0.0)
Dieses Bash-Skript bietet eine robuste und sichere Lösung zur Automatisierung der Verwaltung von Steam-Spielservern unter Linux. Es wurde mit Fokus auf Zuverlässigkeit, Sicherheit und einfache Bedienung für Serveradministratoren entwickelt.

## Features
- **Automatisierte Updates:** Schnelle Aktualisierung von Steam-Spielservern mittels SteamCMD.
- **Integrierte Backup-Lösung:** Erstellen von `.tgz` Backups der Serververzeichnisse.
- **Sicheres Restore:** Wiederherstellung von Backups mit Schutz vor versehentlichem Überschreiben.
- **Sicherheits-Checks:** Interaktive Abfragen für destruktive Aktionen (z.B. `--purge`) und Exklusivitäts-Prüfungen (z.B. kein gleichzeitiges Backup und Restore).
- **Validierung:** Erzwingt die Überprüfung der Spieldateien auf Konsistenz.
- **Debug-Modus:** Detaillierte Shell-Ausgabe für Administratoren zur Fehlerdiagnose.

## Nutzung
```bash
./steamcmd_server_updateall_v26_V1.0.0.sh [OPTIONEN]
```

### Argumente
| Option | Beschreibung |
| :--- | :--- |
| `-v`, `--validate` | Aktiviert die Validierung der Spieldateien in SteamCMD. |
| `-g`, `--game [KEYS]` | Aktualisiert spezifische Spiele (kommagetrennt). |
| `-l`, `--use-login` | Verwendet das im Skript konfigurierte Steam-Konto. |
| `-b`, `--backup` | Erstellt vorab eine Datensicherung (`.tgz`) des Serverpfads. |
| `-r`, `--restore` | Stellt den Server aus einem Backup wieder her. |
| `-p`, `--purge` | Löscht das Serververzeichnis (interaktive Sicherheitsabfrage). |
| `-d`, `--debug` | Aktiviert den detaillierten Shell-Debug-Modus (xtrace). |
| `-h`, `--help` | Zeigt diese Hilfe an. |

## Unterstützte Spiele
### Aktive Spiele (Update & Wartung)
7dtd, conan, enshrouded, palworld, valheim, vrising
### Backup-Spiele (Zusätzlich unterstützt)
ark, ark_ascended, cs, css, dayz, gmod, kf2, l4d2, mesa, perfect_heist2, quake, rust, sotf, soulmask

## Lizenz
Dieses Projekt ist unter der **MIT-Lizenz** lizenziert. Siehe `LICENSE` für Details.
