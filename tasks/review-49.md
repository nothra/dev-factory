# Review: Task 49

> Diff `origin/main...HEAD` (16 Dateien, +941/−22), gegen Spec `docs/specs/spec-49-turn-limit-implement.md`
> und Factory-ADR-065. Drei Runden (Logik, Code-Qualität, Architektur) im Orchestrator-Kontext.
> Gegenlauf `scripts/checks/tests/run-tests.sh` im Review: 2443 grün / 0 rot (Exit 0). Die Projekt-Suite lief
> nicht erneut, weil der Aufruf nicht freigegeben war (laut Task-Datei 146 grün / 0 rot).

## Kritische Findings (müssen behoben werden)

_keine_

## Wichtige Findings (sollten behoben werden)

- [ ] [factory.config.yml.example:39, .claude/commands/configure-factory.md] **AK21 ist im Branch noch
  nicht erfüllt.** Das Example nennt weiter `[1, 50]` und beschreibt die Staffelung nicht, `configure-factory.md`
  ebenso. Die Änderung liegt nur als `tasks/patch-49.diff` vor. Vor dem Merge muss ein Mensch den Patch
  anwenden, committen, `tasks/patch-49.diff` entfernen und AK21 abhaken (Guardrail „keine offenen
  Checkboxen → kein Done"). Das ist eine menschliche Aufgabe vor dem Merge, keine Nacharbeit am Code. Der
  Patch-Inhalt wurde gelesen und stimmt mit Spec und ADR-065 überein. `git apply --check` war in dieser
  Session nicht freigegeben, laut Task-Datei ist er grün.

## Nitpicks (optional)

- [ ] [.claude/commands/pipeline.md:13] Die Vorbedingungs-Checkliste lautet „Spec vorhanden:
  `docs/specs/spec-$ARGUMENTS.md`?". Das Muster ist falsch (es fehlt `-*`), und die Liste nennt die neue harte
  Vorbedingung „Abschnitt `## Akzeptanzkriterien` mit mindestens einem AK" (ADR-065 §3) nicht. Es reicht, eine
  Zeile in `tasks/patch-49.diff` zu ergänzen, weil die Datei unter `.claude/**` liegt.
- [ ] [scripts/checks/tests/run-tests.sh:3670] Das Label „#197 AK5 (E2E): großer Proxy (8 AK >= 6) → /implement auf heavy"
  verschweigt, dass die Assertion jetzt auch `max 40 turns` prüft. Das Label behauptet weniger, als der Test
  prüft. Ein Zusatz wie „… und mittlere Turn-Stufe (40)" würde das beheben.
- [ ] [scripts/checks/tests/run-tests.sh:3819-3820] Der Negativfall „mid.from > high.from (vertauschte Stufen)" prüft nur den
  Exit-Code und keine regelspezifische Meldung, anders als die übrigen 4d-Negativfälle. So könnte der Test aus
  einem anderen Fail-Pfad grün sein (Lesson nothra/tch-gastro-services#214). Eine Assertion auf
  „high.from bei 'implement' = 12 muss größer als mid.from (13)" würde das schließen.
- [ ] [scripts/checks/tests/run-tests.sh:3737ff] Die Implementierungs-Hinweise von ADR-065 verlangen für den
  Preflight eine „Mutation je Zweig". Die drei Zweige sind über ursachenspezifische Meldungen und die
  Abwesenheit von `Starte: /implement` belegt, das reicht als Kausalitätsnachweis. Ein ausdrücklicher
  Mutationsbeleg fehlt, wie ihn 4d hat. Das kann `/test` nachziehen.
- [ ] [tasks/patch-49.diff] Bei `factory.config.yml.example` war der Patch-Weg vermutlich unnötig. Die Datei liegt
  nicht unter `.claude/**` und wird in `.claude/settings.json` nicht verweigert, sie ist nur nicht freigegeben. Der
  Wrapper-Weg war damit offen (Lesson nothra/tch-gastro-services#291). Für diese Task ist das ohne Folgen, weil der
  Mensch den Patch ohnehin anwendet.
- [ ] [tasks/telemetry-raw-49-20261106T120257Z.tmp.txt, .coverage-tmp49/] Gitignorete Wegwerf-Artefakte liegen
  noch im Baum (Lesson build-tooling, Wegwerf-Dateien sofort löschen). Vor `/test` oder `/codify` entfernen,
  damit verzeichnisweite Content-Scans nicht daran anschlagen (Lesson nothra/tch-gastro-services#312).

## Positives

- **AK-Abdeckung vollständig belegt:** AK1–AK5 laufen E2E über `--dry-run` gegen die echte
  `factory.defaults.yml` (Lesson nothra/tch-gastro-services#348). AK6 läuft als echter Lauf mit Rework-Stub,
  der genau zwei `/implement`-Starts mit 40 Turns zählt. AK8 läuft zusätzlich ohne `--dry-run` und mit
  Marker-Stub, der belegt, dass `claude` nie aufgerufen wird. AK19 prüft in der Projekt-Suite sowohl das
  E2E-Budget als auch die Abwesenheit von `skills.*`.
- **F4 sauber gelöst:** Preflight, Modell- und Turn-Wahl nutzen alle `spec_file_for`. Die neue
  `LC_ALL=C sort` macht die Wahl bei mehreren Treffern deterministisch, und ein Test belegt, dass
  `measure_size` dieselbe Datei misst.
- **Gate 4d fail-closed mit regelspezifischen Meldungen und Mutationsbeleg.** AK18 und „keine vierte Stufe"
  hängen bewusst an Regel 2 statt an einer Sonderregel, wie in ADR-065 §1 begründet, und sind getestet.
- **Fixture-Helfer `mk_spec_fixture` an einer Stelle** statt 116 Inline-Kopien (Lesson zu doppelten Scaffolds).
  `scaffold_310` bekommt ihn zentral, und ein eigener Test belegt, dass Fehlerszenarien nicht als AK zählen.
- **Präzise Doku-Pflege:** Erweiterungsnotizen in ADR-038/ADR-010, Indexzeile, Breaking-Hinweis mit Migration
  im CHANGELOG, OPERATING-Abschnitt. Der Lib-Kopfkommentar („Vier reine Funktionen") wurde mitgezogen.
- **Geringer Eingriff in `run-pipeline.sh`:** `get_max_turns` bleibt ohne `max_turns_by_size` byte-identisch im
  Verhalten. `MAX_TURNS` sticht weiterhin über `${MAX_TURNS:-…}`, und `run-pipeline.sh` hat keine Einstiegsmodi,
  die `/implement` überspringen und am neuen Stopp unnötig scheitern könnten.

## Empfehlung
APPROVED
