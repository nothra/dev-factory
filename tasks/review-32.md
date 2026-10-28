# Review: Task 32

## Kritische Findings (müssen behoben werden)
- keine

## Wichtige Findings (sollten behoben werden)
- keine

## Nitpicks (optional)
- [ ] scripts/checks/tests/run-tests.sh:8355 – Der Guard-Kommentar nennt seine Blindstelle nicht: er sieht nur Aufrufe mit expliziter Wurzel-Variable (`FACTORY_DIR=<echte Wurzel> bash …`), nicht den Direktaufruf eines Gates der echten Wurzel (`bash "$CHECKS_DIR/pre-push.sh"`, so war der `#149`-Fund). Ein Satz „sieht nicht: Direktaufruf eines Gates/Check-Skripts aus dem echten `$CHECKS_DIR`" macht die Grenze sichtbar (AK5 dokumentiert sie bisher nur in der Task-Datei).
- [ ] scripts/checks/tests/run-tests.sh:8363 – `export FACTORY_DIR=$FACTORY_ROOT` (Zuweisung und Aufruf auf getrennten Zeilen) wird nicht erkannt; im Ist-Stand ohne Treffer, daher nur Hinweis.

## Positives
- RED→GREEN belegt: der erweiterte Guard fand genau den einen alten Treffer, danach grün; Mutationen je Wurzel-Variable, Kontrolle mit Fixture-Wurzel und fail-closed bei unlesbarer Quelle vorhanden.
- Mutant-Zeilen zur Laufzeit gebaut – kein Selbsttreffer (Lesson #319).
- AK1 per Fixture-Lauf in drei Varianten belegt (mit / ohne `PROJECT-CONTEXT.md` / aufgeblähte `CLAUDE.md`: je 1904 grün); zusätzlich fand der Lauf den `#149`-Leser, der im selben PR behoben wurde.
- Realstand-Test nur noch in der Projekt-Suite, mit Breakdown-Ausgabe bei Rot (Mutation belegt); keine Doku-/ADR-Drift (Grep auf Verweise leer).
- Scope eingehalten: kein Eingriff in `import-context-limit-check.sh` oder `MAX_IMPORT_LINES`.

## Empfehlung
APPROVED
