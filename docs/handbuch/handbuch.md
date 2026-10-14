# SPM Stock Watch – Handbuch

*Stock Price Monitoring mit Oracle APEX und LILAM. Technischer Demonstrator, keine Anlageberatung und keine Handelsplattform. Kursdaten können je nach Anbieter, Lizenz und Tarif verzögert oder begrenzt sein.*

---

## 1. Worum es geht

SPM Stock Watch beobachtet Aktienkurse und meldet Auffälligkeiten. Die Anwendung holt regelmäßig Kurse für die Aktien der Watchlist, speichert sie in einer eigenen Kurshistorie und übergibt jeden neuen Kurs an **LILAM**. LILAM prüft die Kurse gegen die eingestellten Regeln und löst Alerts aus, die SPM per E-Mail zustellt.

Gleichzeitig überwacht LILAM die Anwendung selbst: ob Abrufe laufen, wie lange sie dauern, ob Fehler auftreten und ob etwas ausbleibt.

## 2. So funktioniert die Anwendung

### Der Weg eines Kurses

1. **Abruf:** Der Abruf-Job startet im eingestellten Intervall (Standard 15 Minuten) einen Abruflauf. Jeder Lauf ist ein eigener LILAM-Prozess.
2. **Provider:** Für jede aktive Aktie fragt SPM den Kurs beim Provider ab. Derzeit ist das der Mock-Provider mit simulierten Kursen; ein echter Anbieter folgt.
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

- **Gleitendes Mittel (EWMA):** ein Durchschnitt, der neuere Kurse stärker gewichtet. *Warm-up* legt fest, nach wie vielen Kursen Ausreißer gemeldet werden; *Alpha* bestimmt, wie schnell das Mittel neuen Kursen folgt (klein = ruhig, groß = schnell).
- **Drosselung:** Nach einem Alert schweigt dieselbe Regel für dieselbe Aktie eine Zeit lang (Standard eine Stunde), auch über mehrere Abrufläufe hinweg.
- **Veröffentlichen:** Änderungen an Regeln wirken erst, wenn sie über „Regeln veröffentlichen“ als neue Version an LILAM übergeben werden.

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
- **Letzte Alerts:** Klick auf die Nummer öffnet die Mail-Vorschau

### Watchlist

![Watchlist](img/02_watchlist.jpg)

Alle beobachteten Aktien mit letztem Kurs und Abrufstatus.

- **Neues Symbol:** Aktie hinzufügen
- **Symbol anklicken:** Kursverlauf der Aktie
- **Bearbeiten:** Stammdaten ändern oder die Aktie deaktivieren
- **Abrufstatus:** OK, DUPLICATE (kein neuer Kurs) oder ein Fehler wie TIMEOUT oder HTTP_ERROR

### Instrument bearbeiten

![Instrument bearbeiten](img/03_instrument_bearbeiten.jpg)

Stammdaten einer Aktie. Das Symbol ist die Kennung in SPM und lässt sich nach dem Anlegen nicht mehr ändern. Das Provider-Symbol ist die Bezeichnung beim Anbieter. Kurse in einer anderen Währung als der eingetragenen werden verworfen. Inaktive Aktien werden nicht abgerufen.

### Instrument

![Instrument](img/04_instrument.jpg)

Eine Aktie im Detail: letzter Kurs, Zeit des Kurses beim Anbieter, letzter Abruf und Anzahl gespeicherter Kurse. Der **Kursverlauf** zeigt die letzten 200 Kurse mit Unter- und Obergrenze als gestrichelte Linien; er erscheint ab zwei Kursen. Darunter steht die vollständige Kurshistorie. Die Buttons führen zu Stammdaten und Regeln der Aktie.

### Regeln

![Regeln](img/05_regeln.jpg)

Die Regeln aller Aktien in einer Liste. **Symbol anklicken** öffnet die Regel zum Bearbeiten. **Regeln veröffentlichen** übergibt die aktuelle Fassung als neue Version an LILAM; erst dann wirken Änderungen. Unveränderte Regeln erzeugen keine neue Version.

### Regel bearbeiten

![Regel bearbeiten](img/06_regel_bearbeiten.jpg)

Alle Regeln einer Aktie. Leere Felder bedeuten: diese Regel gibt es nicht. Das Fragezeichen neben einem Feld erklärt es.

- **Unter- und Obergrenze:** feste Grenzen in der Währung der Aktie
- **Ausreißer nach oben und unten:** Abweichung in Prozent vom gleitenden Mittel; dazu Warm-up und Alpha
- **Schweigen nach:** Sekunden ohne neuen Kurs; mit **Zeitfenster** und **Zeitzone** nur zu Handelszeiten, z. B. `[{"days":"MON-FRI","from":"09:00","to":"17:30"}]` mit `Europe/Berlin`
- **Schweregrad:** INFO, WARN, ERROR oder CRITICAL; bestimmt die Farbe der Mail
- **Drosselung:** Mindestabstand zwischen zwei Alerts derselben Regel

### Alerts

![Alerts](img/07_alerts.jpg)

Alle ausgelösten Alerts mit Messwert, gleitendem Mittel, Status und Mail-Zustellung. **PENDING** heißt noch nicht zugestellt, **PROCESSED** zugestellt, **ERROR** Zustellung fehlgeschlagen. Die Nummer anklicken öffnet die Mail-Vorschau.

### Alert

![Alert](img/08_alert.jpg)

Die Mail zum Alert, genau so, wie sie verschickt wurde: Art des Alerts im Kopf (Grenzwert, Ausreißer, Schweigen oder Technik), Schweregrad als Abzeichen, der Messwert hervorgehoben mit Grenze bzw. Abweichung, darunter die Einzelheiten.

### Technisches Monitoring

![Technisches Monitoring](img/09_monitoring.jpg)

Der Blick unter die Haube.

- **Abrufläufe:** jeder Lauf mit Auslöser, Dauer, Status und Zahlen
- **Warnungen und Fehler:** Meldungen aus den LILAM-Protokollen von Abruf, Watchdog und Zustellung
- **LILAM-Prozesse:** jeder Lauf als LILAM-Prozess mit Status und Laufzeit

### Administration

![Administration](img/10_administration.jpg)

Steuerung der Anwendung (nur für berechtigte Benutzer).

- **Jobs:** Zustand, nächster Lauf, letzter Lauf und Fehler
- **Abruf jetzt starten:** ein Abruflauf sofort, unabhängig vom Job
- **Regeln veröffentlichen:** wie auf der Seite Regeln
- **Jobs schalten:** Kursabruf, Watchdog und Zustellung ein- oder ausschalten. Den Watchdog nur zusammen mit dem Kursabruf einschalten, sonst meldet er den ausgeschalteten Abruf als Fehler.

## 4. Gut zu wissen

- **Mock-Provider:** Derzeit sind alle Kurse simuliert und bewegen sich zufällig um 100. Alerts entstehen deshalb nur bei passend eingestellten Regeln.
- **Handelszeiten und Feiertage:** Schweige-Regeln kennen Zeitfenster, aber keine Feiertage. An Feiertagen meldet die Regel unter Umständen Schweigen.
- **Keine Entwarnung:** Kommen Signale nach einem Schweige-Alert wieder, gibt es keine eigene Meldung.
- **Sprache der Listen:** Bedienelemente wie „Actions“ und „Go“ sind englisch, solange in APEX kein deutsches Sprachpaket installiert ist.
