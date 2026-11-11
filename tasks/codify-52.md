## Codify-Report: Task 52

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` (+ Index-Zeile in `PROJECT-CONTEXT.md`): **Parallele Hintergrund-Testgruppen** –
  Status aus Ergebnisdatei statt `wait <pid>`, `kill` nur ohne Ergebnisdatei, nie eingesammelte Gruppe = rot –
  wegen: falsches „Exit 127“ durch PID-Wiederverwendung (Umsetzung) und Kill auf fremde PID (Review W1).
- `docs/factory/lessons/testing.md` (+ Index-Zeile): **Beschleunigung messen vor Schneiden** – CPU-Auslastung und
  Zeit je Abschnitt prüfen, teure Einzelausdrücke zuerst; Zielwert, den der Scope nicht erreicht, eskalieren –
  wegen: AK3-Versuch (sechste Gruppe brachte nichts, 1,3 Kerne genutzt) und `${v//x/}` als größtem Einzelhebel.

### Keine Änderungen nötig
- Spec-/ADR-Drift (W3/W4), Mehrfach-Sachverhalte in Assertions und `assert_true ""` sind durch bestehende Lessons bzw.
  den Kleinfund (im Rework angelegt) abgedeckt; Wegwerf-Sonden lagen diesmal in `$TMPDIR`.
- Kein neuer Check: die Fehlerklassen sind durch Tests in `run-tests.sh` (Mutationsbelege) bereits bewacht.

### Empfehlung für nächste Features
- AK3 (Gesamtsuite ≤ 240 s) bleibt offen und braucht eine Entscheidung vor dem Merge (Q7/Q8): Folge-Issue
  „weniger Prozess-Starts je Assertion“ oder Zielwert je Maschine.
- `tasks/telemetry-raw-52-*.tmp.txt` ist Pipeline-Rohdatei (gitignored); nicht committen.
