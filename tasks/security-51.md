# Security Review: Task 51

Geprüft: `git diff origin/main...HEAD` (Stand `98e3a3d`) – `scripts/project/checks/factory-suite-gate.sh` (neu),
`factory.config.yml` (`commands.test`), Tests in `scripts/project/tests/run-tests.sh`, Doku/Ownership.

**Threat Surface:** lokales Gate-Skript ohne Netzwerk, ohne Secrets, ohne Fremdeingaben außer Git-Pfadnamen des
eigenen Repos und zwei Env-Variablen (`FACTORY_DIR`, `FACTORY_FORCE_FULL_SUITE`). Die eigentliche Sicherheitsfrage
ist, ob der Skip ein Gate unbemerkt aushebelt.

## Kritische Findings (Blocker)
- keine

## Wichtige Findings
- keine

## Hinweise
- [x] [Gate-Umgehung] Der Skip schwächt nur lokales Feedback. Fail-closed bleibt der Required Check `factory-self-test`
  (`.github/workflows/factory-ci.yml:98-112`), der die Suite direkt und immer aufruft – nicht über `commands.test`.
  Wer `origin/main` lokal verbiegt, kann den Skip erzwingen; das ist dieselbe Klasse wie `--no-verify` (Kern-Kurzregel 1)
  und braucht keine Maßnahme. Geprüft ist auch die Fail-closed-Richtung: fehlende Merge-Base, jeder Git-Fehler
  (je Befehl eigener Exit-Check, keine Prozess-Substitution) und eine leere Änderungsmenge führen zum vollen Lauf;
  die Tests brechen die Messung per `git`-Stub (F3). Keine Maßnahme.
- [x] [Gate-Umgehung] Die ausgelieferte Suite liest `tasks/` und `docs/specs/` des echten Repos nicht (alle Treffer in
  `scripts/checks/tests/run-tests.sh` liegen in Wegwerf-Repos). Bei einem reinen Spec-/Task-Diff geht also kein Guard über
  diese Pfade verloren. `tasks/patch-*.diff` liegt ebenfalls unter `tasks/`; der Patch ändert erst nach `git apply`
  Dateien außerhalb, und dann läuft die Suite. Keine Maßnahme.
- [x] [Command Injection] Keine: alle Expansionen sind gequotet (`"$base"`, `"$SUITE"`, `"$ROOT"`); Pfade werden
  NUL-getrennt gelesen und nur per `case` verglichen, nie ausgeführt oder `eval`t. `pre-push.sh:30` `eval`t
  `commands.test`, aber der Wert ist ein festes Literal aus der eigenen Config, wie bisher. `FACTORY_DIR` ist eine
  vertrauenswürdige Steuer-Variable, wie in allen Gates. Keine Maßnahme.
- [x] [Ausgabe] Der erste Pfad außerhalb wird roh ausgegeben (`printf '%s'`); ein Dateiname mit Steuerzeichen könnte
  Terminal-Escapes auslösen. Die Namen stammen aus dem eigenen Working Tree des Entwicklers bzw. Agenten, eine
  Fremdquelle gibt es nicht. Risiko akzeptiert, unterhalb der Schwelle für ein Issue oder `kleinfunde.md`.
- [x] [Temp-Dateien] `mktemp` legt die Datei mit Modus 0600 an. Sie wird vor `exec` bzw. `exit` gelöscht und enthält nur
  Pfadnamen. Bei einem Abbruch per Signal bleibt sie in `$TMPDIR` liegen; das ist harmlos. Keine Maßnahme.
- [x] [Verdrahtung] Der Wrapper liegt in `scripts/project/checks/`, nicht in `pre-push.d/`, und ist nicht ausführbar
  (Modus 100644). `run_project_checks` startet ihn also kein zweites Mal. Keine Maßnahme.
- [x] [Secrets / Dependencies / Logs] Keine Secrets, keine neuen Abhängigkeiten, keine sensiblen Daten in den Meldungen
  (Grund und ein Pfadname). Die Test-Fixtures nutzen die Dummy-Identität `t@t.com`.

## Ergebnis
PASSED
