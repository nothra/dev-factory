# Review: Task 52

Iteration 2 · Stand `e8d265a` · Diff `origin/main...HEAD`, Schwerpunkt Rework `36090e4..e8d265a` · drei Runden (Logik,
Code-Qualität, Architektur) im Koordinator-Kontext. Proben in `$TMPDIR` waren in dieser Session nicht freigegeben. Aussagen
zur Shell-Semantik sind deshalb aus dem Code abgeleitet und als solche markiert. Gelaufen sind
`import-context-limit-check.sh` (790 von 1100 Zeilen ✓) und `gh pr view 54`.

**Offen für den Menschen vor dem Merge (kein Rework durch `/implement` möglich):** Entscheidung zu AK3 (Spec Q8) und
Bestätigung der AK5-Auslegung (Spec Q7). Das war W6 aus Iteration 1. Der PR-Body nennt beides jetzt unter
„Abweichungen – Entscheidung vor dem Merge nötig“, der PR ist Draft. Damit ist der Agenten-Teil von W6 erledigt.

## Prüfung der Findings aus Iteration 1

- **W1 ✓** `lib/test-groups.sh:103-115`: Es wird nur noch beendet, wenn weder `RCS` noch `.rc` vorliegt. Der Test arbeitet mit
  kill-Trace (Funktion vor dem Builtin), Vorbedingung `held` und Positivkontrolle `-TERM <wrapper>` bei laufender Gruppe.
  Die Mutante ist laut Task-Datei rot.
- **W2 ✓** Die Gruppenliste ist der Glob `TEST_GROUP_FILES_52` und gilt für Start und `SHIPPED_TESTS_28`. Ein leerer Glob
  bleibt Literal: Das Skript fehlt, die Gruppe endet mit Exit 127 und wird rot. Das ist fail-closed (abgeleitet).
  `test_groups_on_exit` erzwingt Exit 1 für nie eingesammelte Gruppen. Die Gegenprobe „kein Fehlalarm nach dem Sammeln“
  liegt vor.
- **W3 ✓** ADR-066 D2–D5, Konsequenzen und Pflichten künftiger Gruppen sind nachgezogen und decken sich mit dem Code
  (einzige Zeile, vier Fälle plus EXIT-Fall, `.rc`-Wrapper samt Grund, keine exportierten Variablen).
- **W4 ✓** Die Spec enthält die AK1-Abweichung, den AK3-Stand, den AK5-Zusatz und Q7/Q8.
- **W5 ✓** F5 ist in Einzel-Assertions mit Vorbedingung geteilt. D5 prüft auf nicht leeren Pfad. `drive_52`/`drive_bg_52`
  löschen die Marker vor jedem Lauf. Die allgemeine Ursache (`assert_true ""` = grün) steht als Kleinfund in
  `docs/factory/kleinfunde.md`.
- **W6 ✓ (Agenten-Teil)**: siehe oben.
- **W7 ✓** `testing-standards.md` und der Build/Test-Block in `PROJECT-CONTEXT.md` sind ergänzt. Der @import-Deckel hält.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_

## Nitpicks (optional)

- [ ] `scripts/checks/tests/lib/test-groups.sh:100-115` – Der Kommentar nennt `test_groups_cleanup` „idempotent“. Das gilt
  nicht ganz. Für eine Gruppe mit `.rc` bleibt `TEST_GROUP_RCS[i]` leer, danach wird `TEST_GROUPS_DIR=""` gesetzt. Ein
  zweiter Aufruf prüft deshalb `[ ! -e "/0.rc" ]` und schickt TERM an die längst freie PID, also genau den W1-Fall.
  Heute gibt es dafür nur ein schmales Fenster: INT/TERM trifft ein, während `test_groups_on_exit` zwischen `rm -rf` und
  seinem Ende steht. Alle anderen Pfade rufen das Aufräumen höchstens einmal mit nicht leeren Listen auf (abgeleitet, Probe
  nicht freigegeben). Fix: Im `.rc`-Zweig `TEST_GROUP_RCS[i]` aus der Datei übernehmen oder am Ende die Listen leeren. Dann
  wäre die Aussage „idempotent“ wahr. Etwa zwei Zeilen.
- [ ] `lib/test-groups.sh:103-110` – Eine Gruppe, deren Wrapper per KILL endet (Stub `wrapkill`), hat keine `.rc`. Bricht die
  Suite danach vor dem Sammeln ab, geht TERM trotzdem an deren freie PID. Das geschieht nur bei abnormem Wrapper-Ende und
  ist damit sehr selten. Erwähnenswert ist es nur, weil der Kommentar die Garantie allgemein formuliert.
- [ ] `docs/specs/spec-52-self-test-suite-beschleunigen.md:82-88` – Die AK5-THEN-Klausel sagt weiter „ist die **Anzahl** der
  Assertions gleich“, der neue Zusatz erlaubt mehr. Lesbarer wäre die THEN-Klausel selbst umformuliert („alle alten
  Assertions unverändert und in derselben Reihenfolge …“). Erledigt sich mit der Bestätigung von Q7.
- [ ] `run-tests.sh:40-45`, `testing-standards.md:78` – Der Mechanismus „parallele Testgruppe“ hängt am Namensmuster
  `factory-lock-*-tests.sh`. Eine künftige Gruppe aus einem anderen Bereich (wie der verworfene Versuch
  `telemetry-334-tests.sh`) müsste falsch benannt werden oder einen zweiten Glob bekommen. Erst bei Bedarf auf ein
  neutrales Muster umstellen (etwa `group-*-tests.sh`). Heute ist das kein Defekt, die Doku beschreibt den Ist-Stand richtig.
- [ ] Aus Iteration 1 bewusst offen gelassen und weiter optional: Mehrfach-Sachverhalte in D4-Assertions, F1-Dichte von
  `build_template_23`, gemeinsamer Shard-Startblock, doppelte Leerzeilen.

## Positives

- Das Rework ist eng am Befund geblieben: Jede Änderung ist einem Finding zugeordnet und hat einen eigenen Test mit
  Vorbedingung. Wo Leer-Grün droht, gibt es eine Positivkontrolle (kill-Trace, `held`, nicht leere Pfade).
- Der kill-Trace als Funktion vor dem Builtin wirkt auch im Wrapper-Subshell. Damit ist die Zusage „kein TERM an fremde
  PIDs“ beobachtbar und nicht nur behauptet.
- Der Glob als einzige Quelle der Gruppenliste beseitigt die Handliste an beiden Stellen. Der EXIT-Pfad schließt die
  Lücke „verlorenes Sammeln“, ohne nach dem regulären Sammeln Fehlalarm zu geben.
- Der D1-Test ist per Marker-Handshake deterministisch statt über `sleep 1` und unter Last nicht mehr timing-abhängig.
- Die ADR beschreibt jetzt die tatsächliche Mechanik samt Grund für den `.rc`-Wrapper. Das Ergebnis zu AK3 steht ehrlich
  unter „Konsequenzen“.
- Die allgemeine Ursache hinter W5 (`assert_true ""`) ist nicht im eigenen PR still mitrepariert, sondern als Kleinfund
  ausgelagert (Scope eingehalten).

## Empfehlung
APPROVED
