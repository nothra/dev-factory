# Security Review: Task 49

> Diff `origin/main...HEAD` (Stand `e3951aa`), Fokus: `scripts/lib/tier-select.sh`, `scripts/run-pipeline.sh`,
> `scripts/checks/config-validation-check.sh`, `factory.defaults.yml`. Keine App-Schicht, keine Dependencies,
> keine Secrets im Diff (Pre-Commit-Credential-Check grün).

## Kritische Findings (Blocker)

_keine_

## Wichtige Findings

_keine_

## Hinweise

- [x] [Command-/Glob-Injection] `spec_file_for` übergibt `task_id` als `find -name`-Muster, nie an eine Shell
  oder `eval`. Das Muster ist identisch zum bisherigen Preflight (Zeile vorher: `find … -name "spec-${TASK_ID}-*.md"`);
  Glob-Zeichen in der ID würden höchstens die Treffermenge ändern. Die ID kommt vom lokalen Aufrufer und muss
  zuvor eine existierende `tasks/task-<id>-*.md` finden. Keine neue Angriffsfläche.
- [x] [Config-Werte → Arithmetik] `select_max_turns` vergleicht Werte aus `factory.config.yml` mit `[ -ge ]`.
  `size` wird auf Ziffern geprüft (Fail-Safe `high`). Die Stufen-Grenzen und -Budgets validiert das Gate 4d
  (Integer, `mid.from >= 2`, `high.from > mid.from`, Budgets in `[1, 80]`) und die Werte fließen nie in einen
  `eval`. Ein ungeprüfter, nicht-numerischer Wert (Gate umgangen) lässt `[` mit Fehler zurückkehren und
  fällt auf die Basis zurück – kein Codepfad, kein Fail-open auf ein höheres Budget.
- [x] [Budget-Obergrenze] Die Kostenobergrenze 80 Turns bleibt gate-seitig erzwungen (ADR-009 §6). Der
  Umgebungs-Override `MAX_TURNS` sticht weiterhin ungeprüft; das ist unverändert gegenüber `main` und bewusst
  (lokaler Operator-Schalter), kein Teil dieser Task.
- [x] [Fail-closed] Der Preflight stoppt bei fehlender Spec, fehlendem AK-Abschnitt oder 0 AK mit je eigener
  Meldung und `errors++` – für jeden Modus. Das ist strenger als vorher (Warnung), keine Abschwächung.
- [x] [Freitext in Agentenkontext] Es entsteht kein neuer Ablage-Mechanismus für Agenten-Freitext; die Meldungen
  des Preflights enthalten nur die Task-ID und feste Literale.

## Ergebnis
PASSED
