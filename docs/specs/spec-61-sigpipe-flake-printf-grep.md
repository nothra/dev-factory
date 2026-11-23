# Spec: SIGPIPE-Flakes in den Self-Test-Suiten beseitigen (#61, schließt #15 ein)

## Kontext

Die ausgelieferte Self-Test-Suite `scripts/checks/tests/run-tests.sh` schlägt sporadisch fehl, mit wechselndem Test,
ohne Codeänderung (#61: CI `ubuntu-latest`, Job `factory-self-test`; Fehlerbild `printf: write error: Broken pipe`).
Ursache ist die Race-Klasse `printf '%s' "$haystack" | grep -q …` unter `set -o pipefail`: `grep -q` endet beim ersten
Treffer und schließt die Pipe, `printf` schreibt noch, bekommt SIGPIPE, und die Pipeline meldet einen Fehler, obwohl
`grep` getroffen hat. Ob es trifft, hängt vom Timing und der Haystack-Größe ab (ab wenigen KB), nicht vom Code.

**#15 gehört dazu:** Der dort sporadisch rote Test („#334 (Review-Finding 1): der add-ok/commit-fehlgeschlagen-Zweig
greift wie erwartet", macOS lokal und im pre-push-Hook) prüft per `assert_contains_286 "$OUT_334" …`. Der Helfer
(`scripts/checks/tests/lib/assert-helpers.sh`) ist selbst `printf '%s' "$1" | grep -qF -- "$2"`, der Haystack ist die
komplette Ausgabe eines Pipeline-Laufs. Andere Ursachen für #15 sind nicht untersucht; die Abnahme deckt den Test
deshalb ausdrücklich mit ab.

**Zweite Fehlerrichtung:** Der Spiegel-Helfer `assert_absent` nutzt dasselbe Muster. Dort wird die Race zu
**Falsch-Grün**: die Phrase ist vorhanden, die Pipeline meldet trotzdem ≠ 0, die Abwesenheits-Assertion besteht. Das ist
schwerer zu sehen als ein roter Flake und schwächt jeden Test, der damit ein Verbot belegt.

**Warum hier:** Die Dateien gehören der Factory und sind in Konsumenten über `factory.lock` + `factory-integrity` gegen
lokale Änderung gesperrt; der Fix kann nur in diesem Repo entstehen.

Die Regel steht bereits als Lesson (`docs/factory/lessons/testing.md`, Abschnitt zu `assert_contains_286`/`printf |
grep -q`: „gegen eine Variable per Here-String, nie `printf | grep -q`; den Helfer nur für kurze Literale"). Sie hat
das Wiederauftreten nicht verhindert: der Helfer selbst verletzt sie, und er wird mit großen Haystacks aufgerufen.

**Entscheidungen (Mensch, 2026-11-22):**
- #15 wird mit in diesem PR behoben (`Closes #61`, `Closes #15`).
- Ein Guard in der Suite lehnt neu eingeführte Pipe-in-`grep -q`-Zeilen in den Test-Suiten ab.
- CI-Beleg: der Job `factory-self-test` läuft auf dem PR 10× (Neustarts), die Läufe werden im PR verlinkt.
- Produktiv-Skripte bleiben außerhalb des Scopes (siehe unten).

## Scope

**Inbegriffen:**
- Die Helfer `assert_contains_286` und `assert_absent` liefern unabhängig von Haystack-Größe und Timing das richtige
  Ergebnis.
- Alle Stellen in den Test-Suiten, an denen ein Haystack per Pipe an ein vorzeitig endendes `grep` (`-q`, auch
  kombiniert wie `-qF`, `-qE`, `-qx…`) geht: `scripts/checks/tests/**` (Haupt-Suite, `factory-lock-*-tests.sh`,
  `lib/`) und `scripts/project/tests/**`. Bestandsaufnahme beim Start: 138 Zeilen der Form `printf '%s' "$VAR" |
  grep -q…` in `run-tests.sh`, 155 mit allgemeinem `printf … | grep -…q`, weitere in `factory-lock-23-tests.sh`,
  `factory-lock-41-tests.sh` und der Projekt-Suite. Maßgeblich ist der Guard (AK4), nicht diese Zahlen.
- Ein Guard (Self-Test), der eine solche Zeile in den Test-Suiten erkennt und den Lauf rot macht, mit Mutationsbeleg.
- Die Lesson in `docs/factory/lessons/testing.md` verweist auf den Guard; die Einschränkung „Helfer nur für kurze
  Literale" entfällt, wenn sie nach dem Fix nicht mehr gilt.
- Ein Eintrag in `docs/factory/kleinfunde.md` für die Produktiv-Fundstellen (siehe „Nicht inbegriffen"), sofern die
  Schwelle aus `git-workflow.md` (Factory-ADR-043) keinen eigenen Issue verlangt.

**Nicht inbegriffen:**
- **Produktiv-Skripte** mit demselben Muster (`factory-release-check.sh`, `factory-sync.sh`, `factory-update.sh`,
  `install-yq.sh`, `lib/factory-lock.sh`, `metrics.sh`, `checks/check.sh`, `checks/git-context-check.sh`,
  `checks/branch-name-check.sh`). Sie prüfen kurze Werte (Tag, SHA, Slug, Tool-Input-Zeile), die in einem
  Schreibvorgang übergeben werden; das Race ist dort praktisch nicht auslösbar, und der Guard gilt nur für Tests.
- Andere Ursachen sporadischer Fehlschläge als die SIGPIPE-Klasse (z. B. Timing in Wegwerf-Repos, parallele
  Testgruppen nach Factory-ADR-066). Tritt einer davon in den 10 CI-Läufen auf, ist er ein eigener Fund (Issue),
  kein Blocker dieses PRs – außer er betrifft den #15-Test.
- Pipes in `grep` **ohne** vorzeitiges Ende (`grep -c`, `grep -o`, `grep` ohne `-q`): sie lesen bis EOF und sind
  nicht betroffen.
- Der Release, der den Fix an Konsumenten ausliefert (eigener Release-PR, Factory-ADR-063 D6).
- ShellCheck-Einführung.

## Akzeptanzkriterien

- [ ] **AK1 – Positiv-Helfer robust:** GIVEN ein Haystack von mindestens 1 MB, in dem die gesuchte Phrase in der
  ersten Zeile steht, unter `set -o pipefail` WHEN `assert_contains_286` ihn 200× hintereinander prüft THEN ist jede
  Prüfung grün und es erscheint keine `Broken pipe`-Meldung auf stderr.
- [ ] **AK2 – Negativ-Helfer robust (kein Falsch-Grün):** GIVEN derselbe große Haystack mit der Phrase in der ersten
  Zeile WHEN `assert_absent` ihn 200× prüft THEN ist jede Prüfung rot (die Assertion erkennt die vorhandene Phrase
  zuverlässig); GIVEN ein großer Haystack ohne die Phrase WHEN `assert_absent` prüft THEN ist sie grün.
- [ ] **AK3 – Helfer-Semantik unverändert:** GIVEN eine Phrase, die mit `-` beginnt (z. B. `--no-telemetry`), bzw.
  eine Phrase mit Regex-Sonderzeichen WHEN einer der beiden Helfer sie sucht THEN wird sie als fester Text gesucht
  (kein Options- oder Regex-Fehler), wie heute; GIVEN ein leerer Haystack WHEN `assert_contains_286` sucht THEN ist
  die Prüfung rot.
- [ ] **AK4 – Guard erkennt das Muster:** GIVEN eine Datei unter `scripts/checks/tests/` oder
  `scripts/project/tests/` mit einer Zeile, die einen Haystack per Pipe an ein `grep` mit `-q` (allein oder
  kombiniert) übergibt – Produzent `printf` oder `echo` WHEN die Suite läuft THEN schlägt der Guard fehl und nennt
  Datei und Zeile.
- [ ] **AK5 – Guard-Mutationsbeleg:** GIVEN der Guard WHEN eine Fixture-Zeile mit dem Muster eingebracht wird THEN ist
  er rot; WHEN dieselbe Prüfung als Here-String oder als `grep … <datei>` formuliert ist THEN ist er grün;
  Kommentarzeilen, die das Muster nur beschreiben (z. B. in Lessons zitiert oder als `#`-Kommentar), lösen ihn nicht
  aus.
- [ ] **AK6 – Bestand sauber:** GIVEN der Stand des PRs WHEN der Guard über alle Test-Suiten läuft THEN findet er
  keine Zeile; die Haupt-Suite und die Projekt-Suite sind lokal grün, ohne dass ein Test entfernt oder abgeschwächt
  wurde (Anzahl der Assertions vor/nach im PR genannt).
- [ ] **AK7 – CI-Beleg #61:** GIVEN der PR-Stand WHEN der Job `factory-self-test` 10× läuft (Erstlauf + Neustarts)
  THEN ist jeder Lauf grün und kein Log enthält `Broken pipe`; die 10 Lauf-Links stehen im PR-Body.
- [ ] **AK8 – #15 abgedeckt:** GIVEN die 10 CI-Läufe aus AK7 und die lokalen Suite-Läufe WHEN der Test „#334
  (Review-Finding 1): der add-ok/commit-fehlgeschlagen-Zweig greift wie erwartet" ausgewertet wird THEN ist er in jedem
  Lauf grün.
- [ ] **AK9 – Regel nachgezogen:** GIVEN die Lesson in `docs/factory/lessons/testing.md` WHEN der PR gemergt ist THEN
  verweist sie auf den Guard, und keine Aussage darin widerspricht dem neuen Helfer-Verhalten.

## Fehlerszenarien

- [ ] Ein Test wird beim Umstellen versehentlich wirkungslos (z. B. falsche Variable, invertierte Logik): AK6
  verlangt gleichbleibende Assertion-Zahl; `/review` prüft Stichproben der umgestellten Stellen auf Gleichwertigkeit.
- [ ] Der Guard ist zu weit und trifft legitime Pipes ohne `-q` oder Kommentarzeilen: AK5 belegt beides.
- [ ] Der Guard ist zu eng (andere Produzenten wie `cat`, `git`, `sed` vor `grep -q`): Die Bestandsaufnahme fand
  vier solche Stellen in den Tests. Sie werden mit umgestellt; ob der Guard sie ebenfalls erfasst, entscheidet
  `/implement` nach Fehlalarmrisiko und hält es in der Task-Datei fest.
- [ ] Ein CI-Lauf in AK7 ist aus anderem Grund rot (Runner-Störung, fremder Flake): Lauf zählt nicht, wird
  wiederholt; der fremde Grund wird als Fund festgehalten (siehe „Nicht inbegriffen").

## Offene Fragen

- [ ] Keine fachlichen. Ob ein ADR nötig ist: nach Einschätzung nein (keine Architektur-Entscheidung, Anwendung einer
  bestehenden Lesson plus Guard nach bekanntem Muster); `/architecture` entfällt, sofern `/implement` nichts anderes
  findet.
