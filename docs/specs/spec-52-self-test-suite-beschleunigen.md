# Spec: Self-Test-Suite beschleunigen (`factory-lock-tests.sh`)

## Kontext

Die ausgelieferte Self-Test-Suite `bash scripts/checks/tests/run-tests.sh` braucht lokal auf macOS
**566 s** (~9,5 min) und im CI-Job `factory-self-test` (Linux) **151 s**. Gemessen wurde am
2026-11-05 auf `main` @ b86cfd9. Von den 566 s sind 215 s Systemzeit: Die Tests starten sehr viele
Prozesse (`git init`/`clone`/`push`, `mktemp`, `yq`, `jq`), und das ist auf macOS deutlich teurer
als auf Linux.

**362 von 566 s (64 %)** stammen aus der Testgruppe `scripts/checks/tests/factory-lock-tests.sh`
(Abschnitte Factory-Issue #23, #24, #37). `run-tests.sh` bindet sie am Ende per `source` ein.
Fast jeder Einzeltest und jeder Mutationsbeleg baut dort ein eigenes Wegwerf-Repo auf (Origin,
Klon, Bundle, Push), das kostet jeweils 2–6 s.

Die Suite wird an adoptierende Projekte ausgeliefert. Dort läuft sie in CI, ab dem nächsten
Factory-Update inklusive `factory-lock-tests.sh`, und ihr CI-Lauf wächst um diese Gruppe. Lokal
blockiert die Suite jeden pre-push und jedes Quality-Gate von `run-pipeline.sh`.

**Befund zum Profiling im Issue:** Die Prosa-Guards gegen ADR-063 und OPERATING.md lesen das
Dokument schon heute nur **einmal** ein (`flat_37` → Variable). Ihre Mutanten entstehen per
Parameter-Expansion aus dieser Variable. Die im Issue genannten 7–13 s „pro Prüfung“ sind deshalb
sehr wahrscheinlich ein Artefakt der Messmethode: Ein Zeitstempel je Ausgabezeile schreibt einer
Zeile die gesamte Arbeit **seit der vorigen Ausgabe** zu, hier etwa die vorangehenden
`mut_wf_37`-Aufrufe. Das Profiling dieser Task muss diese Zuordnung vermeiden (siehe AK1).

## Scope

**Inbegriffen:**

- Laufzeitsenkung der Testgruppe `scripts/checks/tests/factory-lock-tests.sh` (Abschnitte #23, #24,
  #37) ohne Abdeckungsverlust.
- Gemeinsame Helfer in `scripts/checks/tests/lib/`, soweit die Testgruppe sie dafür braucht.
- Parallele Ausführung von `factory-lock-tests.sh` neben dem Rest der Suite ist **erlaubt**
  (Entscheidung Q3). Die dafür nötige Verdrahtung in `run-tests.sh` gehört dazu.
- Vorher-/Nachher-Profiling je Abschnitt, lokal (macOS) und im CI-Job `factory-self-test`,
  dokumentiert in der Task-Datei.

**Nicht inbegriffen:**

- Inhaltliche Beschleunigung anderer Abschnitte von `run-tests.sh`, insbesondere der
  run-pipeline-E2E-Tests (nothra/tch-gastro-services#310/#312/#334, Task 314) und #47 `copy_files`
  (Entscheidung Q2). Sie werden höchstens durch die Parallelisierung mittelbar schneller fertig.
- Neue Assertions oder geänderte Prüfinhalte. Was eine Assertion prüft, bleibt gleich.
- Änderungen an den getesteten Skripten (`factory-sync.sh`, `factory-update.sh`, Gates, Workflows).
- Das Überspringen der Suite bei reinen Spec-/Task-Pushes, das ist #51.
- Die Projekt-Suite `scripts/project/tests/run-tests.sh`.

## Begriffe

- **Assertion-Liste:** die Folge der `✓`/`✗`-Zeilen eines Suite-Laufs, ohne Farbcodes und
  Zeitstempel, in Ausgabereihenfolge.
- **Laufzeit:** Wanduhrzeit (`real`) eines vollständigen Laufs von `bash
  scripts/checks/tests/run-tests.sh`, als **Median aus drei Läufen** auf derselben Maschine.
- **Fixture-Muster:** eine Art, Testumgebungen aufzubauen, z. B. „Wegwerf-Welt aus Origin + Klon“
  (`world_23`/`world_24`), „Mutante von `factory-update.sh`“ (`mutant_37`), „Workflow-Mutante“
  (`mut_wf_37`).

## Akzeptanzkriterien

- [ ] **AK1 – Profiling vorher/nachher:** GIVEN der Stand `origin/main` vor der Änderung und der
  fertige Branch, WHEN beide lokal (macOS) und im CI-Job `factory-self-test` gemessen werden, THEN
  enthält die Task-Datei je Stand die Gesamtlaufzeit (Median aus drei Läufen lokal, ein Lauf in CI)
  und die Dauer je Abschnitt von `factory-lock-tests.sh`. Die Messmethode schreibt jedem Abschnitt
  nur die Zeit zwischen seinem Beginn und dem Beginn des nächsten Abschnitts zu, und Methode,
  Maschine und Commit sind angegeben.
- [ ] **AK2 – Testgruppe mindestens halbiert:** GIVEN die Messung aus AK1, WHEN man die Laufzeit
  der Testgruppe `factory-lock-tests.sh` lokal vergleicht, THEN liegt sie bei höchstens **181 s**
  (Ausgangswert 362 s). Bei paralleler Ausführung zählt die Wanduhrzeit der Gruppe in ihrem eigenen
  Prozess.
- [ ] **AK3 – Gesamtziel lokal:** GIVEN die Messung aus AK1, WHEN man die Laufzeit der gesamten
  Suite lokal auf macOS misst, THEN liegt sie bei höchstens **240 s** (Ausgangswert 566 s,
  Entscheidung Q1).
- [ ] **AK4 – CI nicht langsamer:** GIVEN der CI-Job `factory-self-test`, WHEN der Branch darin
  läuft, THEN ist der Schritt der Suite nicht langsamer als vor der Änderung (Ausgangswert 151 s;
  der Vorher-Wert wird im selben Zeitraum neu gemessen, siehe AK1).
- [ ] **AK5 – Assertion-Liste:** GIVEN die Assertion-Liste vor und nach der Änderung, WHEN man sie
  per `diff` vergleicht, THEN ist die **Anzahl** der Assertions gleich. Jede Abweichung in Name oder
  Reihenfolge steht in der Task-Datei mit alter Zeile, neuer Zeile und Begründung (Entscheidung Q4).
  Eine Assertion, die wegfällt und dafür an anderer Stelle neu entsteht, gilt als Abweichung.
- [ ] **AK6 – Gleicher Prüfinhalt:** GIVEN jede Assertion aus `factory-lock-tests.sh`, WHEN man sie
  vor und nach der Änderung vergleicht, THEN prüft sie denselben Sachverhalt mit derselben
  Erwartung (Exit-Code, Meldung, Abwesenheit von Push bzw. schreibenden `gh`-Aufrufen). Das gilt
  auch für Mutationsbelege und Gegenproben.
- [ ] **AK7 – Mutationsbelege bleiben wirksam:** GIVEN jedes in dieser Task geänderte
  Fixture-Muster, WHEN man stichprobenartig mindestens einen davon abhängigen Guard bzw. das
  getestete Skript bricht, THEN wird die zugehörige Assertion rot. Je Fixture-Muster ist mindestens
  ein solcher Rot-Nachweis in der Task-Datei dokumentiert (Lesson „Mutationsbeleg muss denselben
  Assert-Ausdruck ausführen“).
- [ ] **AK8 – Isolation geteilter Fixtures:** GIVEN eine Basis-Fixture, die mehrere Tests teilen,
  WHEN ein Test sie verändert (Datei, Ref, Remote, Konfiguration), THEN sieht kein anderer Test diese
  Veränderung. Belegt wird das durch einen Test, der nach einem mutierenden Fall prüft, dass die
  Basis-Fixture unverändert ist (z. B. per Inhalts-Fingerprint wie `snap_23`).
- [ ] **AK9 – Reihenfolge-Unabhängigkeit:** GIVEN die Abschnitte von `factory-lock-tests.sh`, WHEN
  ein Abschnitt einzeln läuft oder die Abschnitte in anderer Reihenfolge laufen, THEN sind dieselben
  Assertions grün bzw. rot wie im Gesamtlauf. Abschnitte hängen nicht von Zustand ab, den ein
  vorheriger Abschnitt hinterlässt, außer von explizit gemeinsam aufgebauten, unveränderlichen
  Basis-Fixtures.
- [ ] **AK10 – Ergebnis und Exit-Code bei Parallelisierung:** GIVEN `factory-lock-tests.sh` läuft
  parallel zum Rest der Suite, WHEN eine Assertion in einem der beiden Teile rot ist, THEN endet die
  Suite mit Exit ≠ 0, und die Zusammenfassung zählt PASS und FAIL beider Teile zusammen. Die
  Ausgabe jedes Teils erscheint zusammenhängend und ist nicht zeilenweise verschränkt. Ohne
  Parallelisierung entfällt dieses AK, und die Task-Datei vermerkt das.
- [ ] **AK11 – Fail-closed bei abgebrochener Gruppe:** GIVEN die parallel laufende Testgruppe bricht
  ab (Exit ≠ 0 ohne Zusammenfassung, Signal, `exit 2` aus einem fail-closed-Helfer), WHEN die Suite
  ihr Ergebnis zusammenführt, THEN endet die Suite rot und nennt die abgebrochene Gruppe. Ein
  fehlendes Teilergebnis wird nie als grün gelesen. Ohne Parallelisierung entfällt dieses AK.
- [ ] **AK12 – Konsumenten-Neutralität:** GIVEN die geänderte Suite, WHEN sie im Fixture-Lauf eines
  Konsumenten läuft (Dateien der Seite `factory` + Anpassungsstellen + `factory.lock`, Factory-ADR-064
  D6), THEN ist sie grün. Sie setzt weder Node noch eine Datenbank voraus und liest keine
  Konsumenten-Dateien des Factory-Repos (`ci.yml`, `release.yml`, `OWNERSHIP.md`).
- [ ] **AK13 – Plattformen:** GIVEN die geänderte Suite, WHEN sie lokal auf macOS (bash 3.2, BSD-Tools)
  und in CI auf `ubuntu-latest` läuft, THEN ist sie auf beiden grün.
- [ ] **AK14 – Aufräumen:** GIVEN ein vollständiger Suite-Lauf, auch ein roter oder per Signal
  abgebrochener, WHEN er endet, THEN bleiben keine Wegwerf-Verzeichnisse und keine
  Hintergrundprozesse der Testgruppe zurück.
- [ ] **AK15 – Ownership:** GIVEN jede im PR neu getrackte Datei, WHEN `ownership-check.sh` läuft,
  THEN ist sie genau einmal zugeordnet (Helfer und Testdateien unter `scripts/checks/tests/` auf der
  Seite `factory`), und der Check ist grün.

## Fehlerszenarien

- [ ] **F1 – Aufbau der Basis-Fixture scheitert** (z. B. `git`-Fehler beim Origin/Klon): Die
  betroffene Gruppe endet fail-closed rot mit einer Meldung, die den Aufbau nennt. Kein abhängiger
  Test läuft gegen eine halb aufgebaute Fixture und meldet grün.
- [ ] **F2 – Kopie einer Basis-Fixture teilt unbeabsichtigt Zustand** (z. B. gemeinsame
  Objektdatenbank bei `clone --shared`, gemeinsame Hooks, gemeinsame Config): Eine Mutation im
  Testfall erreicht die Basis nicht. Abgedeckt durch AK8.
- [ ] **F3 – Hook-Umgebung:** Läuft die Suite aus einem pre-push-Hook eines Worktrees (`GIT_DIR`,
  `GIT_WORK_TREE`, `GIT_INDEX_FILE` exportiert, Factory-Issue #6), verändern weder die Basis-Fixtures
  noch ein paralleler Teilprozess den echten Worktree.
- [ ] **F4 – Exportierte Umgebungsschalter** (`PR_SHEPHERD`, `FACTORY_STAGE`, `GITHUB_ACTIONS`,
  `GITHUB_OUTPUT`) wirken im parallelen Teilprozess nicht anders als im sequenziellen Lauf.
- [ ] **F5 – Abbruch per Signal** (Ctrl-C während des Laufs): Hintergrundprozesse werden beendet,
  Wegwerf-Verzeichnisse entfernt, und die Suite endet mit Exit ≠ 0. Abgedeckt durch AK11 und AK14.

## Offene Fragen

- [x] Q1: Zielwert der gesamten Suite lokal? → **≤ 240 s** (Entwickler, 2026-11-10).
- [x] Q2: Welche Testgruppen sind im Scope? → **Nur `factory-lock-tests.sh`**. Die
  run-pipeline-E2E-Tests bleiben inhaltlich unberührt (Entwickler, 2026-11-10).
- [x] Q3: Parallelisierung erlaubt? → **Ja**, mit sauber zusammengeführtem Ergebnis und Exit-Code
  (Entwickler, 2026-11-10).
- [x] Q4: Wie streng ist „Assertions identisch“? → **Anzahl gleich**. Name und Reihenfolge dürfen
  abweichen, wenn jede Abweichung in der Task-Datei begründet ist (Entwickler, 2026-11-10).
- [ ] Q5 (für `/architecture`): **Q1 und Q2 zusammen erzwingen fast sicher Parallelisierung.**
  Außerhalb von `factory-lock-tests.sh` laufen heute ~204 s, und die sind nicht im Scope. Sequenziell
  müsste die Gruppe auf ≤ 36 s sinken (−90 %), um 240 s zu erreichen. Mit paralleler Ausführung
  genügt es, dass die Gruppe in ihrem Prozess unter etwa 240 s bleibt und der Rest nicht durch
  Ressourcenkonkurrenz über 240 s wächst. `/architecture` entscheidet den Weg und prüft, ob die
  Parallelisierung ein ADR-Trigger ist (Struktur der ausgelieferten Suite, Verhalten bei Konsumenten).
- [ ] Q6 (für `/architecture`): Läuft die Parallelisierung auch in CI und bei Konsumenten, oder gibt
  es einen Schalter für sequenziellen Lauf (z. B. zum Debuggen)? AK4 verlangt nur, dass CI nicht
  langsamer wird.
