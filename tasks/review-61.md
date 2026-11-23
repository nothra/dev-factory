# Review: Task 61

> Iteration 2 · Diff `origin/main...HEAD` (13 Dateien, +591/−194), Schwerpunkt Rework-Commit `3664fa8` · Spec
> `docs/specs/spec-61-sigpipe-flake-printf-grep.md`. Die Sandbox hat das Ausführen von Skripten (Suiten, Mutante, Guard-Sonden)
> und das Anlegen des Issues erneut abgelehnt. **Statisch belegt:** Die exakte Guard-Regex aus `pipe_grep_q_lines` lief per
> `grep -rnHE -f` über `scripts/checks/tests/` und `scripts/project/tests/`. Einziger Treffer ist die Kommentarzeile
> `assert-helpers.sh:112`, die der Guard ausfiltert. Eine breitere Suche (beliebiger Text zwischen Pipe und `grep`, Pipes mit
> Zeilenfortsetzung) fand ebenfalls nur Kommentare bzw. die Fixture-Zeile mit `$PIPE_61`.

## Kritische Findings (müssen behoben werden)

_(keine – das kritische Finding aus Iteration 1 ist behoben: `run-tests.sh:7403` nutzt jetzt `LC_ALL=C grep_in "$sec_out" -q …`.
Die Env-Zuweisung gilt für die Dauer des Funktionsaufrufs und erreicht damit das `grep` darin. Das Verhalten ist also gleich.
Der Guard erkennt die Form `| LC_ALL=C grep -q`, der Mutationsfall `run-tests.sh:9604` belegt das.)_

## Wichtige Findings (sollten behoben werden)
- [ ] [tasks/task-61-sigpipe-flake-printf-grep.md, AK-Liste letzte Checkbox] **Issue für `scripts/checks/pre-commit.sh:27,35,51`
  steht weiter aus.** Das ist kein Code-Finding, ein weiterer `/implement`-Lauf behebt es nicht: Auch in dieser Session hat die
  Sandbox `create_issue_idempotent` abgelehnt. `gh issue list --search "pre-commit.sh SIGPIPE"` findet kein bestehendes Issue.
  **Mensch, vor dem Merge:** Issue anlegen, Art-Label `bug`, Aspekt-Label `security`. Titelvorschlag: „pre-commit.sh:
  SIGPIPE-Race in `git diff --cached | grep -q` macht das Gate fail-open". Danach die Nummer in der Task-Datei und im PR-Body
  nennen und die Checkbox abhaken.

## Nitpicks (optional)
- [ ] [scripts/checks/tests/lib/assert-helpers.sh:125-126] Der Kommentar nennt Zeilenfortsetzung und Aufrufe über
  Variablen/Funktionen als bewusst nicht erkannt. Es gibt zwei weitere Grenzen, die er nicht nennt. Erstens ein Muster-Wort
  mit `|` vor dem `-q` (`grep -E 'a|b' -q`), weil die Wort-Klasse an `|` endet. Zweitens ein Befehlswort vor `grep`
  (`xargs grep -q`, `sudo grep -q`). Im Bestand gibt es dafür keinen Treffer. Ergänzung: ein Halbsatz im Kommentar.
- [ ] [scripts/checks/tests/lib/assert-helpers.sh:111-115] `grep_in` hängt per Here-String ein `\n` an. Bei leerer Phrase
  und leerem Haystack trifft `assert_contains_286 "" ""` deshalb jetzt; über die Pipe traf es vorher nicht. Der Kommentar
  schränkt das schon korrekt ein („für jede nicht-leere Phrase"). Kein Aufrufer nutzt eine leere Phrase, es gibt also keinen
  Handlungsbedarf. Die Notiz steht hier nur, damit der Unterschied bekannt ist.

## Positives
- **Alle Findings aus Iteration 1 umgesetzt:**
  - Fail-closed: Exit ≥ 2 des Such-`grep` wird getrennt ausgewertet und meldet die Eingabe. Ein Aufruf ohne Argumente ist
    rot und liest nicht still von stdin. Beides ist per Mutationsfall belegt (`run-tests.sh:9610-9614`).
  - Guard-Lücken: `|&`, Env-Präfix, `command`, Optionen mit Ziffer und Options-Argumente vor `-q` sind geschlossen. Je ein
    Rot-Fall belegt das (`run-tests.sh:9604-9608`).
  - Nitpicks: Die Notiz zu `n_labels` ist angepasst, die Grenzen stehen im Kommentar, der Lesson-Satz ist geteilt.
- **Guard-Regex sauber begrenzt:** Das Pipe-Ziel endet an `|`, `;`, `&`, `)`. Damit bleibt eine Zeile wie
  `… | grep -c x; grep -q y "$file"` grün, ein eigener Grün-Fall sichert das ab (`:9609`). `(^|[^|])` schließt `||` aus.
  Die `-q`-Erkennung verlangt ein Token, das mit `-` beginnt. `q` im Muster (`grep -o 'quiet'`) löst deshalb nicht aus.
- **`local hits rc` getrennt von der Zuweisung**, also schluckt `local` den Exit-Code nicht. `--` vor der Regex und vor
  den Dateinamen. Den Kommentarfilter (`grep_in "$hits" -vE`) erreicht nur ein nicht-leeres `hits`, der angehängte
  Zeilenumbruch kann bei `-v` also keinen Falsch-Fund erzeugen.
- **Abdeckung vollständig:** Außerhalb von `lib/` gibt es unter `scripts/checks/tests/` und `scripts/project/tests/` keine
  `*.sh` in Unterverzeichnissen. Die beiden Globs der AK6-Aufrufe erfassen damit den ganzen Bestand. Ein gedrifteter Pfad
  macht den Guard jetzt rot.
- **Zahlen stimmig:** 6 neue `guard_case_61` und 3 Einzel-Assertions ergeben +9 und passen zu „2766 → 2775" in der Task-Datei.
- **Projektregeln:** keine neue getrackte Datei, Verweise qualifiziert, keine Herkunftsbegriffe. Die ausgelieferte Suite
  bleibt konsumenten-neutral (Factory-ADR-064 D6).

## Empfehlung
APPROVED

> Code-seitig freigegeben. Vor dem Merge offen und nicht durch `/implement` lösbar: Issue für `pre-commit.sh` anlegen
> (Mensch). Außerdem stehen die PR-Belege AK7/AK8 aus (10 CI-Läufe `factory-self-test`, #15-Test grün, Lauf-Links und
> Assertion-Zahlen im PR-Body). Die lokalen Suiten-Läufe konnten in dieser Session nicht ausgeführt werden; die Zahlen
> stammen aus dem `/implement`-Lauf.
