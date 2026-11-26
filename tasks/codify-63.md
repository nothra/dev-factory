## Codify-Report: Task 63

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` + Zeile in `lessons/INDEX.md` – „Pfadlisten aus git nur NUL-getrennt lesen; Sonderzeichen-Pfade gegen echtes git testen“ – wegen: `core.quotepath=false` deckte nur Nicht-ASCII, `awk -F'|'`/`NF == 1` übersprang `|`-Pfade (fail-open), Steuerzeichen in `✗`-Meldungen (Security-Review).
- `docs/factory/lessons/testing.md` + Zeile in `lessons/INDEX.md` – „AK ‚Verhalten unverändert‘ braucht den Vergleichslauf in `/test`“ – wegen: Review-Finding „wichtig“ zu AK8 (Beleg nur per Argument).

### Folge-Arbeit (unterhalb der Schwelle, `docs/factory/kleinfunde.md`)
- Steuerzeichen aus Pfaden erreichen ungefiltert die `✗`-Meldungen (Security-Review)
- Release-Manifest liest Pfade ohne `-z` (Security-Review)
- Leere Null-Zählung in der Erfolgszeile (aus `/implement`)

### Keine Änderungen nötig
Keine neue Guideline- oder CLAUDE.md-Regel: das Muster ist Test-/Skript-spezifisch und als Lesson mit Trigger abgedeckt. Die vier Review-Nitpicks (Temp-Datei ohne Trap, Kommentar-Wortlaut, doppelte `tr`-Kette, Test-Helfer-Duplikat) sind Einzelfälle ohne Muster.

### Empfehlung für nächste Features
- AK8-Byte-Vergleich gegen `main` bei Gelegenheit mit Freigabe nachholen und unter AK8 eintragen.
- Beim Quoting-Wechsel einer Lese-Stelle die Nachbarn mitprüfen (hier `factory-release-manifest.sh`).
