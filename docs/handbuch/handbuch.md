# SPM Stock Watch – Handbuch

*Stock Price Monitoring mit Oracle APEX und LILAM. Technischer Demonstrator, keine Anlageberatung und keine Handelsplattform. Kursdaten können je nach Anbieter, Lizenz und Tarif verzögert oder begrenzt sein.*

---

## 1. Worum es geht

SPM Stock Watch beobachtet Aktienkurse und meldet Auffälligkeiten. Die Anwendung holt regelmäßig Kurse für die Aktien der Watchlist, speichert sie in einer eigenen Kurshistorie und übergibt jeden neuen Kurs an **LILAM**. LILAM prüft die Kurse gegen die eingestellten Regeln und löst Alerts aus, die SPM per E-Mail zustellt.

Gleichzeitig überwacht LILAM die Anwendung selbst: ob Abrufe laufen, wie lange sie dauern, ob Fehler auftreten und ob etwas ausbleibt.

## 2. So funktioniert die Anwendung

### Der Weg eines Kurses

1. **Abruf:** Der Abruf-Job startet im eingestellten Intervall (Standard 15 Minuten) einen Abruflauf. Jeder Lauf ist ein eigener LILAM-Prozess.
2. **Provider:** Für jede aktive Aktie fragt SPM den Kurs beim Provider ab. Das ist entweder Twelve Data (echte Kurse über das Internet) oder der Mock-Provider (simulierte Kurse für Demo und Tests); der Provider wird je Aktie gewählt.
3. **Prüfung:** SPM prüft Antwort, Zahlenformat, Währung und Alter des Kurses. Fehlerhafte Antworten werden protokolliert; der Lauf geht mit der nächsten Aktie weiter.
4. **Speichern:** Neue Kurse landen in der Kurshistorie. Ein Kurs, den es schon gibt, wird nicht doppelt gespeichert.
5. **Messwert an LILAM:** Jeder neu gespeicherte Kurs geht als Messwert an LILAM, je Aktie eine eigene Messreihe.
6. **Regeln:** LILAM vergleicht den Kurs mit den Regeln der Aktie und löst bei Bedarf einen Alert aus.
7. **Zustellung:** Der Zustell-Job verschickt den Alert als E-Mail. Der Abruf selbst wartet nie auf den Mailversand.

### Regeln je Aktie

| Art | Löst aus, wenn … |
| --- | --- |
| **Grenzwert** | der Kurs unter der Untergrenze oder über der Obergrenze liegt |
| **Ausreißer** | der Kurs um mehr als x % vom gleitenden Mittel (EWMA) abweicht, nach oben oder unten |
| **Schweigen** | seit x Sekunden kein neuer Kurs kam, auf Wunsch nur in Handelszeiten |

- **Drosselung:** Nach einem Alert schweigt dieselbe Regel für dieselbe Aktie eine Zeit lang (Standard eine Stunde), auch über mehrere Abrufläufe hinweg.
- **Veröffentlichen:** Änderungen an Regeln wirken erst, wenn sie über „Regeln veröffentlichen“ als neue Version an LILAM übergeben werden.

### Ausreißer: gleitendes Mittel, Warm-up und Alpha

Ein Ausreißer ist ein Kurs, der deutlich von dem abweicht, was die Aktie *gerade* tut. Als Maßstab dient das **gleitende Mittel** (EWMA, exponentiell gewichteter Mittelwert): ein Durchschnitt der bisherigen Kurse, in dem neuere Kurse mehr zählen als ältere. Es folgt dem Kurs, aber verzögert und geglättet. Eine Grenze von 3 % heißt: Liegt ein neuer Kurs mehr als 3 % über (oder unter) diesem Mittel, gibt es einen Alert. Verglichen wird mit dem Mittel *vor* dem neuen Kurs, damit ein Ausreißer seinen eigenen Maßstab nicht verschiebt.

**Alpha** legt fest, wie stark jeder neue Kurs das Mittel bewegt: neues Mittel = altes Mittel + Alpha × (neuer Kurs − altes Mittel).

| Alpha | Wirkung bei Kursen | Geeignet für |
| --- | --- | --- |
| klein, z. B. 0,1 | Das Mittel ist träge und erinnert sich lange an frühere Kurse. Auch ein langsamer Trend weicht mit der Zeit vom Mittel ab und kann einen Alert auslösen. | ruhige Werte, wenn auch schleichende Bewegungen auffallen sollen |
| groß, z. B. 0,5 | Das Mittel folgt dem Kurs schnell. Nur plötzliche Sprünge zwischen zwei Abrufen fallen auf, Trends nicht. | schwankungsreiche Werte, wenn nur echte Sprünge interessieren |

Beispiel: Das Mittel steht bei 100 EUR, der nächste Kurs ist 110 EUR. Mit Alpha 0,1 steigt das Mittel auf 101, mit Alpha 0,5 auf 105. Kommt danach wieder 110, liegt der Kurs im ersten Fall noch fast 9 % über dem Mittel, im zweiten nur noch knapp 5 %.

**Warm-up** ist die Anzahl Kurse, die LILAM zuerst sammelt, bevor Ausreißer gemeldet werden. In dieser Zeit ist das Mittel der einfache Durchschnitt. Ohne Warm-up würde schon der zweite Kurs einer neuen Aktie mit einem Mittel aus nur einem Kurs verglichen – jede normale Schwankung wäre dann ein „Ausreißer“. Standard sind 3 Kurse; bei einem Abruf alle 15 Minuten entsprechen 5 Kurse gut einer Stunde Anlaufzeit. Das Mittel läuft über Abrufläufe und Neustarts hinweg weiter; das Warm-up gilt nur für eine neue oder zurückgesetzte Aktie.

### Dringlichkeit

Jeder Alert hat eine Dringlichkeit. Sie bestimmt die Farbe der Mail und der Anzeige.

| Dringlichkeit | Bedeutung |
| --- | --- |
| **Kritisch** | Die Überwachung selbst ist gefährdet, es kommen keine Daten mehr. |
| **Alarm** | Eine Schwelle ist verletzt, jetzt hinschauen bzw. handeln. |
| **Warnung** | Auffällig, beobachten. |
| **Hinweis** | Zur Kenntnis. |

| Regel | Dringlichkeit (Standard) |
| --- | --- |
| Kurs unter Untergrenze / über Obergrenze (`SAP-MIN`, `SAP-MAX`) | Alarm |
| Ausreißer nach oben / unten (`SAP-UP`, `SAP-DOWN`) | Warnung |
| Kein neuer Kurs (`SAP-SILENT`) | Warnung |
| Kein Abruflauf, Abruflauf hängt, Abruf-Job gestört | Kritisch |
| Abruflauf fehlgeschlagen, Watchdog oder Zustellung läuft nicht | Alarm |
| Abruflauf nur teilweise erfolgreich, fehlerhafte Symbole | Warnung |
| Abruflauf oder Provider-Aufruf zu langsam | Hinweis |

Die Dringlichkeit der Regeln je Aktie lässt sich im Regel-Formular ändern, die der technischen Regeln ist fest.

### Selbstüberwachung

- **Technische Regeln:** Abruflauf fehlgeschlagen oder nur teilweise erfolgreich, Lauf oder Provider-Aufruf zu langsam, fehlerhafte Aktien in einem Lauf.
- **Watchdog:** Ein eigener Job prüft, ob Signale ausbleiben: kein Abruflauf, ein hängender Lauf, keine neuen Kurse, kein Zustell-Lauf. Außerdem prüft er, ob der Abruf-Job eingeschaltet ist und zuletzt fehlerfrei lief.
- **Gegenseitige Prüfung:** Auch jeder Abruflauf prüft auf ausbleibende Signale. Fällt einer der beiden Jobs aus, meldet das der andere. Fallen beide aus, zeigt das nur noch das Dashboard.

### Die drei Jobs

| Job | Aufgabe | Standard |
| --- | --- | --- |
| Kursabruf | holt die Kurse | alle 15 Minuten |
| Watchdog | prüft auf ausbleibende Signale und den Zustand des Abruf-Jobs | alle 5 Minuten |
| Zustellung | verschickt Alerts per E-Mail | läuft dauerhaft, startet stündlich neu |

Ein- und ausgeschaltet werden sie auf der Seite **Administration**.

## 3. Die Seiten

Das Menü öffnet sich über das Symbol ☰ oben links. Der Button **Startseite** oben rechts führt von jeder Seite zum Dashboard zurück.

**Bedienung der Listen:** *Lupe* – in allen Spalten suchen · *Spaltenkopf anklicken* – sortieren, filtern · *Actions* – Spalten ein- und ausblenden, Filter, Hervorheben, Download.

### Dashboard

![Dashboard](img/01_dashboard.jpg)

Der Überblick auf einen Blick. Die farbige Kante jeder Kachel zeigt den Zustand: grün in Ordnung, orange auffällig, rot Fehler, grau aus.

- **Letzter erfolgreicher Abruf:** wie aktuell die Kurse sind
- **Letzter Lauf:** Ergebnis und Zahlen des letzten Abruflaufs
- **Beobachtete Symbole, Alerts (24 h):** Umfang und Lage
- **Abruf-Job, Watchdog, Zustellung:** an oder aus
- **Letzte Alerts:** Klick auf die Nummer mit dem Briefsymbol öffnet die Mail-Vorschau

### Watchlist

![Watchlist](img/02_watchlist.jpg)

Alle beobachteten Aktien mit letztem Kurs und Abrufstatus.

- **Neues Symbol:** Aktie hinzufügen
- **Symbol mit dem Kurvensymbol anklicken:** Kursverlauf der Aktie mit den Buttons Bearbeiten, Regeln und Historie löschen
- **Bearbeiten:** Stammdaten ändern oder die Aktie deaktivieren
- **Abrufstatus:** OK, DUPLICATE (kein neuer Kurs) oder ein Fehler wie TIMEOUT oder HTTP_ERROR

### Instrument bearbeiten

![Instrument bearbeiten](img/03_instrument_bearbeiten.jpg)

Stammdaten einer Aktie. Das Symbol ist die Kennung in SPM und lässt sich nach dem Anlegen nicht mehr ändern. Das Provider-Symbol ist die Bezeichnung beim Anbieter. Kurse in einer anderen Währung als der eingetragenen werden verworfen. Der Schalter **Aktiv** legt fest, ob die Aktie abgerufen wird; er wirkt wie alle Felder erst mit **Speichern**.

**Welche Provider-Symbole gibt es bei Twelve Data?** Alle Aktien listet [twelvedata.com/stocks](https://twelvedata.com/stocks). Der Gratistarif liefert nur Aktien, die an US-Börsen gehandelt werden, in USD; deutsche Börsen wie XETRA sind nicht enthalten. Viele ausländische Firmen gibt es dort als ADR, z. B.:

| Aktie | Provider-Symbol | Hinweis |
| --- | --- | --- |
| Apple, Microsoft, Nvidia | `AAPL`, `MSFT`, `NVDA` | US-Börse |
| SAP, ASML | `SAP`, `ASML` | US-Börse |
| Siemens, Allianz, Nestlé | `SIEGY`, `ALIZY`, `NSRGY` | US-Freiverkehr |
| BMW | `BMWKY` | US-Freiverkehr, 1 Papier = 1/3 Aktie |

**Schreibweise:** Ein Provider-Symbol ist entweder nur der Ticker (`AAPL`) oder Ticker und Börse, getrennt durch einen Doppelpunkt (`BMW:XFRA`). Die Börse wird als MIC angegeben, den internationalen vierstelligen Börsencode (ISO 10383), z. B. `XETR` (XETRA), `XFRA` (Frankfurt), `XNYS` (NYSE), `XNAS` (NASDAQ). Ohne Börse wählt Twelve Data die Hauptnotierung; die Börse braucht man nur, wenn derselbe Ticker an mehreren Börsen vorkommt. Der Doppelpunkt ist eine Schreibweise von SPM, nicht von Twelve Data: SPM trennt die Angabe und übergibt Ticker und Börse dem Anbieter getrennt. Für den Gratistarif genügt der Ticker, denn die deutschen Börsen sind dort ohnehin nicht enthalten.

Ob ein Symbol abrufbar ist, zeigt ein Probeabruf, der nichts speichert und 1 Credit je Symbol kostet. In SQL Developer als SPM angemeldet eingeben und mit **F5** („Skript ausführen“) starten:

```
@C:\Users\dirk\Documents\SPM\test\live_twelvedata.sql "NVDA,ASML,NSRGY"
```

`OK` heißt abrufbar (mit Kurs, Währung und Zeit); „available starting with the Grow plan“ heißt nicht im Gratistarif. Eine Aktie, die bisher mit dem Mock-Provider lief, nicht auf Twelve Data umstellen, sondern unter neuem Symbol anlegen (z. B. `SAP.US`): sonst mischen sich simulierte und echte Kurse in einer Reihe.

### Instrument

![Instrument](img/04_instrument.jpg)

Eine Aktie im Detail: letzter Kurs, Zeit des Kurses beim Anbieter, letzter Abruf und Anzahl gespeicherter Kurse. Der **Kursverlauf** zeigt die letzten 200 Kurse mit Unter- und Obergrenze als gestrichelte Linien; er erscheint ab zwei Kursen. Darunter steht die vollständige Kurshistorie. Die Buttons führen zu Stammdaten und Regeln der Aktie.

**Historie löschen** (nur Administration): löscht alle gespeicherten Kurse der Aktie und setzt das gleitende Mittel in LILAM zurück; das Warm-up beginnt mit dem nächsten Kurs neu. Alerts und Protokolle bleiben erhalten. Sinnvoll, wenn eine Aktie den Provider wechselt, z. B. von simulierten zu echten Kursen: sonst erscheint der Sprung zwischen alter und neuer Reihe als Ausreißer. Läuft gerade ein Abruf, meldet SPM das; dann einfach noch einmal versuchen.

### Regeln

![Regeln](img/05_regeln.jpg)

Die Regeln aller Aktien in einer Liste. **Symbol mit dem Schieberegler-Symbol anklicken** öffnet die Regel zum Bearbeiten. **Regeln veröffentlichen** übergibt die aktuelle Fassung als neue Version an LILAM; erst dann wirken Änderungen. Unveränderte Regeln erzeugen keine neue Version.

### Regel bearbeiten

![Regel bearbeiten](img/06_regel_bearbeiten.jpg)

Alle Regeln einer Aktie. Leere Felder bedeuten: diese Regel gibt es nicht. Das Fragezeichen neben einem Feld erklärt es.

- **Unter- und Obergrenze:** feste Grenzen in der Währung der Aktie
- **Ausreißer nach oben und unten:** Abweichung in Prozent vom gleitenden Mittel; dazu Warm-up und Alpha (siehe Abschnitt „Ausreißer“)
- **Schweigen nach:** Sekunden ohne neuen Kurs; mit **Zeitfenster** und **Zeitzone** nur zu Handelszeiten, z. B. `[{"days":"MON-FRI","from":"09:00","to":"17:30"}]` mit `Europe/Berlin`. Die Zeitzone wird aus einer alphabetischen Liste gewählt (Zeitzone der Börse, für US-Werte `America/New_York`)
- **Dringlichkeit:** Hinweis, Warnung, Alarm oder Kritisch; bestimmt die Farbe der Mail (Standard: Grenzwert Alarm, Ausreißer und Schweigen Warnung)
- **Drosselung:** Mindestabstand zwischen zwei Alerts derselben Regel

### Alerts

![Alerts](img/07_alerts.jpg)

Alle ausgelösten Alerts der Kursregeln mit Kurs, gleitendem Mittel, Status und Mail-Zustellung. **PENDING** heißt noch nicht zugestellt, **PROCESSED** zugestellt, **ERROR** Zustellung fehlgeschlagen. Die Nummer mit dem Briefsymbol anklicken öffnet die Mail-Vorschau. Technische Alerts (Regeln `SPM-…`) stehen im Technischen Monitoring.

### Alert

![Alert](img/08_alert.jpg)

Die Mail zum Alert, genau so, wie sie verschickt wurde: Art des Alerts im Kopf (Grenzwert, Ausreißer, Schweigen oder Technik), Dringlichkeit als Abzeichen, der Messwert hervorgehoben mit Grenze bzw. Abweichung, darunter die Einzelheiten. Bei Kurs-Alerts sind das Aktie, Kurs, Regel und Regelset; technische Alerts nennen zusätzlich den LILAM-Prozess und dessen Zähler. **Zurück** führt zu der Seite, von der aus die Mail geöffnet wurde.

### Technisches Monitoring

![Technisches Monitoring](img/09_monitoring.jpg)

Der Blick unter die Haube.

- **Abrufläufe:** jeder Lauf mit Auslöser, Dauer, Status und Zahlen
- **Technische Alerts:** Alerts der Regeln `SPM-…`, z. B. fehlgeschlagener Abruflauf oder schweigender Watchdog
- **Warnungen und Fehler:** Meldungen aus den LILAM-Protokollen von Abruf, Watchdog und Zustellung
- **LILAM-Prozesse:** jeder Lauf als LILAM-Prozess mit Status und Laufzeit

### Administration

![Administration](img/10_administration.jpg)

Steuerung der Anwendung (nur für berechtigte Benutzer).

- **Jobs:** Zustand, nächster Lauf, letzter Lauf und Fehler
- **Abruf jetzt starten:** ein Abruflauf sofort, unabhängig vom Job
- **Regeln veröffentlichen:** wie auf der Seite Regeln
- **Jobs schalten:** je ein Schalter für Kursabruf, Watchdog und Zustellung; er wirkt sofort, ein fehlender Job wird beim Einschalten angelegt. Den Watchdog nur zusammen mit dem Kursabruf einschalten, sonst meldet er den ausgeschalteten Abruf als Fehler.

## 4. Gut zu wissen

- **Twelve Data:** Der Gratistarif erlaubt 800 Abrufe am Tag und 8 pro Minute; das reicht für etwa 8 Aktien im 15-Minuten-Takt rund um die Uhr. Außerhalb der Handelszeit liefert der Anbieter den letzten Kurs erneut, der Abruf zählt dann als DUPLICATE. Werte aus dem US-Freiverkehr kommen oft erst mit einem Tag Verzögerung.
- **Mock-Provider:** Aktien mit dem Mock-Provider erhalten simulierte Kurse. Die Demo-Verläufe erzeugt `demo/simulate_prices.sql` (rund 16 Stunden im 15-Minuten-Takt, mit einem Grenzwert-Alarm bei SAP und Siemens, einem Ausreißer bei Apple und einem Abruffehler bei Microsoft); danach bewegen sich die Kurse zufällig um den letzten Wert.
- **Handelszeiten und Feiertage:** Schweige-Regeln kennen Zeitfenster, aber keine Feiertage. An Feiertagen meldet die Regel unter Umständen Schweigen.
- **Keine Entwarnung:** Kommen Signale nach einem Schweige-Alert wieder, gibt es keine eigene Meldung.
- **Sprache der Listen:** Bedienelemente wie „Actions“ und „Go“ sind englisch, solange in APEX kein deutsches Sprachpaket installiert ist.
