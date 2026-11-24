# Spec: pre-commit.sh prüft den Staged-Diff fail-closed statt per Pipe in `grep -q` (#70)

## Kontext

`scripts/checks/pre-commit.sh` läuft unter `set -euo pipefail` und prüft drei blockierende Regeln mit
`git diff --cached | grep -qE …` direkt als `if`-Bedingung:

| Check | Regel | Zeile (Stand `main`) |
|-------|-------|----------------------|
| 1 | ungelöste Merge-Konfliktmarker (`^+<<<<<<<`, `^+=======`, `^+>>>>>>>`) | 27 |
| 2 | Debug-Statements (JS-Konsolenausgabe, Java-`System.out`, JS-Debugger, `pry`, `pdb` – Muster siehe Skript) | 35 |
| 4 | hardkodierte Credentials (`password`/`secret`/`api_key`/… `= '<8+ Zeichen>'`) | 51 |

**Fehlerbild (fail-open):** `grep -q` endet beim ersten Treffer und schließt die Pipe. Ist der Staged-Diff größer als
der Pipe-Puffer und steht der Treffer früh, schreibt `git diff` noch weiter, bekommt SIGPIPE (Exit 141), und
`pipefail` macht den Exit-Status der ganzen Pipeline ≠ 0. Die `if`-Bedingung ist damit **falsch**, der Check meldet
„✓ keine Konfliktmarker / keine Debug-Statements / keine Credentials" – der Commit geht **durch**, obwohl `grep` den
Treffer gesehen hat. Das ist dieselbe Race-Klasse wie in #61 (PR #69), dort in den Test-Helfern, hier in einem
produktiven Gate; bei Check 4 trifft es die Secret-Prüfung.

Bei großem Diff ist das Fehlverhalten kein seltener Flake, sondern nahezu sicher: ein Diff von einigen hundert KB mit
einem Treffer in den ersten Zeilen lässt `git diff` praktisch immer nach dem Ende von `grep` weiterschreiben.

**Bekannte Regel, nicht eingehalten:** `docs/factory/guidelines/bash-gotchas.md` §3 und die Lesson in
`docs/factory/lessons/testing.md` (Factory-Issue #61: „gegen eine Variable per Here-String, nie `<produzent> | grep -q`
– das gilt für jeden Produzenten") beschreiben die Klasse. Der Guard `pipe_grep_q_lines` aus #61 scannt nur die
Test-Suiten, nicht die Gates – deshalb ist `pre-commit.sh` durchgerutscht.

**Warum hier:** `pre-commit.sh` gehört der Factory (Seite `factory` in `OWNERSHIP.md`) und ist in Konsumenten über
`factory.lock` + `factory-integrity` gegen lokale Änderung gesperrt; der Fix kann nur in diesem Repo entstehen und geht
mit dem Patch-Release v0.8.1 hinaus.

## Scope

**Inbegriffen:**
- `scripts/checks/pre-commit.sh`, Checks 1, 2 und 4: der Staged-Diff wird **einmal** gelesen (Variable oder temporäre
  Datei) und per Here-String bzw. Datei-Argument gegrept, nie per Pipe in ein vorzeitig endendes `grep`.
- Fail-closed beim Lesen: schlägt `git diff --cached` selbst fehl, blockiert das Gate (Exit ≠ 0), statt die Checks auf
  leerer Eingabe grün zu melden.
- Regressionstests in der ausgelieferten Suite `scripts/checks/tests/run-tests.sh` (großer Diff, früher Treffer, je
  Check; Gegenprobe ohne Treffer; Fehlerpfad).
- Guard: `pipe_grep_q_lines` (aus #61) wird zusätzlich auf `scripts/checks/pre-commit.sh` angewendet, damit das Muster
  dort nicht zurückkehrt.

**Nicht inbegriffen:**
- Check 3 (TODO ohne Ticket-Referenz): `awk` liest seine Eingabe vollständig (Auswertung erst im `END`-Block), endet
  also nicht vorzeitig – kein SIGPIPE. Zudem nur Warnung. Er darf im Zuge der Umstellung dieselbe gelesene
  Diff-Quelle nutzen, sein Verhalten ändert sich nicht.
- Die im Issue genannten ähnlichen Stellen `scripts/factory-update.sh:77` (`env | grep -qE`) und
  `scripts/start-work.sh:310` (`git worktree list | grep -qxF`): Produzent mit kleiner Ausgabe, kein Sicherheits-Gate.
  Sie werden in `/implement` als Kleinfund in `kleinfunde.md` vermerkt (Schwelle laut `git-workflow.md`), nicht
  umgestellt.
- Ein repo-weiter Guard über alle Produktiv-Skripte (`scripts/**`) – eigene Entscheidung, ggf. eigenes Issue.
- Inhaltliche Änderung der drei Regex-Regeln (was als Konfliktmarker, Debug-Statement oder Credential gilt).
- `pre-push.sh` und andere Gates.

## Akzeptanzkriterien

> Gemeinsame Testbedingung (AK1–AK5): Wegwerf-Git-Repo mit den nötigen Factory-Skripten, `FACTORY_LINT_COMMAND=true`
> (Lint neutralisiert), Integritäts-Check im Factory-Modus No-op. Geprüft wird der **Exit-Code von `pre-commit.sh`**
> und die Meldung des jeweiligen Checks – nicht nur, dass `grep` den Treffer findet. „Großer Diff" heißt: der
> gestagte Diff ist ≥ 1 MiB und damit um ein Vielfaches größer als ein Pipe-Puffer.

- [ ] **AK1 – Konfliktmarker, großer Diff, früher Treffer:** GIVEN ein gestagter großer Diff, dessen **erste**
  hinzugefügte Zeile `<<<<<<< HEAD` ist, WHEN `pre-commit.sh` läuft, THEN endet es mit Exit 1 und meldet
  „Ungelöste Merge-Konflikte gefunden".
- [ ] **AK2 – Debug-Statement, großer Diff, früher Treffer:** GIVEN ein gestagter großer Diff, dessen erste
  hinzugefügte Zeile das Check-2-Muster trifft (z. B. ein JS-Konsolen-Log-Aufruf), WHEN `pre-commit.sh` läuft, THEN Exit 1 und Meldung
  „Debug-Statements gefunden".
- [ ] **AK3 – Credential, großer Diff, früher Treffer:** GIVEN ein gestagter großer Diff, dessen erste hinzugefügte
  Zeile das Check-4-Muster trifft (Zuweisung an `password` mit einem String-Literal ab 8 Zeichen), WHEN `pre-commit.sh` läuft, THEN Exit 1 und Meldung „Mögliche
  hardkodierte Credentials gefunden".
- [ ] **AK4 – Messung gebrochen (Mutationsbeleg):** GIVEN die bisherige Fassung der Checks
  (`git diff --cached | grep -qE …`), WHEN die Tests AK1–AK3 gegen sie laufen, THEN ist **jeder** dieser
  drei Tests rot (Exit 0 statt 1 bzw. „✓"-Meldung). Der Beleg (Kommando + Ergebnis) steht in der Task-Datei. Damit ist
  gezeigt, dass die Tests die Race tatsächlich auslösen und nicht nur den Treffer im Input prüfen.
- [ ] **AK5 – keine Falsch-Rot-Gegenprobe:** GIVEN ein gestagter großer Diff **ohne** Konfliktmarker,
  Debug-Statement und Credential, WHEN `pre-commit.sh` läuft, THEN Exit 0 und für Checks 1, 2 und 4 die jeweilige
  „✓"-Meldung.
- [ ] **AK6 – Treffer am Ende eines großen Diffs:** GIVEN ein gestagter großer Diff mit dem Treffer (je Check einer)
  nur in der **letzten** hinzugefügten Zeile, WHEN `pre-commit.sh` läuft, THEN Exit 1 mit der Meldung des
  jeweiligen Checks (das Lesen bricht nicht nach einem Teil der Eingabe ab).
- [ ] **AK7 – fail-closed bei Lesefehler:** GIVEN `git diff --cached` schlägt fehl (z. B. per Stub im `PATH`, der für
  `diff --cached` mit Exit ≠ 0 endet), WHEN `pre-commit.sh` läuft, THEN endet es mit Exit ≠ 0 und meldet **keinen**
  der drei Checks als „✓".
- [ ] **AK8 – Guard:** GIVEN die Suite, WHEN sie läuft, THEN prüft ein Test, dass `pipe_grep_q_lines
  scripts/checks/pre-commit.sh` keinen Fund meldet; eine Mutation (eine Pipe-in-`grep -q`-Zeile in eine Kopie von
  `pre-commit.sh`) macht diesen Test rot.
- [ ] **AK9 – bestehendes Verhalten unverändert:** GIVEN die bestehenden pre-commit-Tests der Suite (u. a. #431
  AK-H3/H4, #262), WHEN die Suite läuft, THEN sind sie unverändert grün; die Meldungstexte der Checks 1–4 bleiben
  wortgleich.

## Fehlerszenarien

- [ ] Staged-Diff leer (nichts gestagt): Checks 1, 2, 4 grün, kein Fehler durch leere Variable unter `set -u`.
- [ ] Diff enthält Binärdateien: `git diff --cached` liefert „Binary files … differ" – kein Abbruch, kein Treffer.
- [ ] Diff mit Zeilen, die mit `-` beginnen (Here-String/Datei-Argument): kein Fehl-Parsing als `grep`-Option.
- [ ] `git diff --cached` schlägt fehl → Gate blockiert (AK7), statt still zu bestehen.

## Technische Hinweise (für `/implement`)

- Muster laut Lesson: `staged_diff="$(git diff --cached)"` einmal oben (unter `set -e` bricht ein Lesefehler das
  Skript ab → Exit ≠ 0 = fail-closed), danach `grep -qE … <<< "$staged_diff"`. Alternative bei Speicherbedenken:
  temporäre Datei + `grep -qE … "$datei"` mit Aufräum-Trap. Die Wahl trifft `/implement`; ein ADR ist dafür nicht nötig.
- Command Substitution entfernt nur abschließende Newlines – für zeilenbasierte Regex ohne Belang.
- Der Mutationsbeleg (AK4) muss reproduzierbar rot sein; ≥ 1 MiB Diff mit Treffer in Zeile 1 reicht dafür auf macOS
  und Linux. Falls ein Lauf doch grün bleibt, Diff vergrößern statt den Test zu wiederholen.
- Testnamen in `run-tests.sh` mit Präfix `#70 AK<n>:` (Konvention „`#<nr>` in Shell-Strings").
- **Trigger-Strings nie wörtlich in getrackte Dateien:** Eine Zeile, die Check 2 oder 4 trifft, blockiert den eigenen
  Commit der Test-Suite (beim Schreiben dieser Spec passiert). Fixtures setzen die Trigger zur Laufzeit zusammen
  (z. B. `dbg="console"; dbg+=".log"`) und schreiben sie nur in das Wegwerf-Repo.

## Offene Fragen

- [x] Ähnliche Stellen (`factory-update.sh`, `start-work.sh`) mit umstellen? → Nein, Kleinfund (siehe Scope).
- [x] ADR nötig? → Nein: keine Architekturentscheidung, nur Anwendung einer bestehenden Regel (bash-gotchas §3,
  Lesson #61).
