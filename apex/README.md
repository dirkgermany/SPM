# APEX-Anwendung „SPM Stock Watch“

Anwendung 100 im Workspace `SPM` (APEX 24.2, Universal Theme, Anmeldung mit APEX-Konten des Workspace).

| Datei | Zweck |
| --- | --- |
| `f100.sql` | regulärer APEX-Export (`apex export -applicationid 100 -skipExportDate -expOriginalIds -overwrite-files`); importierbar über App Builder oder SQLcl |
| `build/spm_app_build.sql` | Quelle der Anwendung: baut sie mit dem Hilfspaket `build/spm_apex_builder` auf (Grundlage: von APEX erzeugte leere Anwendung) |

## Importieren

Voraussetzung: SPM ist installiert (`install/install.sql`), insbesondere `spm_apex` und die Sichten aus `install/26_apex_views.sql`.

- **App Builder:** App Builder → Import → `f100.sql`, Parsing-Schema `SPM`.
- **SQLcl**, angemeldet als `SPM`, im Ordner `apex`: `@f100.sql`

In einen anderen Workspace oder unter einer anderen ID vorher `apex_application_install.set_workspace` bzw. `set_application_id` aufrufen.

## Ändern

`build/spm_app_build.sql` anpassen und im Ordner `apex/build` als `SPM` ausführen (`@spm_app_build.sql`); angemeldete Benutzer bleiben angemeldet. Danach `f100.sql` neu exportieren. Änderungen, die im App Builder gemacht werden, gehen beim nächsten Aufbau verloren, solange sie nicht ins Build-Skript übernommen sind.

## Seiten

| Seite | Inhalt |
| --- | --- |
| 1 Dashboard | Aktualität, letzter Lauf, Symbole, Alerts (24 h), Zustand der Jobs; letzte Alerts |
| 2 Watchlist | Symbole; „Neues Symbol“; Link zu Instrument und Bearbeiten |
| 3 Instrument bearbeiten | Formular (`spm_watchlist.save_instrument`) |
| 4 Instrument | Kacheln, Kursverlauf als SVG mit Grenzen, Kurshistorie |
| 5 Regeln | Regeln je Symbol; „Regeln veröffentlichen“ (`spm_rules.publish`) |
| 6 Regel bearbeiten | Grenzwert, Ausreißer (EWMA, Warm-up, Alpha), Schweigen mit Zeitfenstern, Drosselung |
| 7 Alerts | Alerts der SPM-Gruppe mit Messwert und Mail-Status |
| 8 Alert | Mail-Vorschau (`spm_notify.build_message`) |
| 9 Technisches Monitoring | Abrufläufe, Warnungen/Fehler aus LILAM, LILAM-Prozesse |
| 10 Administration | Jobs, Abruf von Hand (In-Session), Regeln veröffentlichen; Berechtigung über `SPM_CONFIG.APEX_ADMIN_USERS` |

Die Seiten lesen nur SPM-Sichten und rufen `spm_apex` auf; die Logik liegt in den SPM-Paketen. Der manuelle Abruf läuft im In-Session-Modus innerhalb eines Requests. Der entkoppelte LILAM-Modus mit Server und Dispatcher folgt für ein späteres APEX-Board.

Bekannt: Bedienelemente der Interactive Reports sind englisch, solange in der APEX-Instanz kein deutsches Sprachpaket installiert ist. Die eingebaute IR-Hilfe ist ausgeblendet (kein Rückweg in die Anwendung).
