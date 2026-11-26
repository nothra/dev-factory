# Security Review: Task 63

Grundlage: `git diff origin/main...HEAD` (Kern: `scripts/checks/ownership-check.sh`, Tests in `scripts/checks/tests/run-tests.sh`).
Threat-Modell: Pfade sind angreiferkontrolliert (per PR eingebracht), das Gate läuft lokal (pre-push) und in CI (Self-Test-Suite);
`--list factory` speist über `scripts/factory-release-manifest.sh` die Liefermenge.

Statisch geprüft und unauffällig:

- **Command- und Argument-Injection:** kein `eval`, keine unquotierte Expansion. Pfade laufen nur über `printf '%s\n'`,
  `read -r`, `echo "✗ $path…"` (Präfix, also keine Option) sowie `sort`/`comm` auf Dateien. `git ls-files -z` bekommt
  keine Pfad-Argumente, ein `-`-Präfix (`-n`, `--list`) ist also wirkungslos. `$(…)`, Backticks, `*` und `[ab]` im
  Dateinamen sind nur Daten.
- **awk-Muster-Injection:** Der Pfad ist nur `$0` bzw. der linke Operand von `file ~ row_ere[r]`. Als Regex wirken nur die
  Tabellenmuster, und die maskiert `glob_to_ere`. Kein `printf` mit Pfad als Format, kein `-v` mit Pfad (dort gäbe es
  Escape-Verarbeitung).
- **Fail-open:** keiner gefunden. `ls-files -z` + `tr '\0' '\n'` liefert jeden Pfad byte-genau. Ein Zeilenumbruch ist in
  beiden Modi Exit 2, bevor eine Pfadmenge entsteht. `$0 != ""` kann keinen echten Pfad verwerfen, denn Pfade sind nie
  leer. Dass `-F'|'`/`NF == 1` entfällt, schließt einen vorbestehenden fail-open, und zwar auch im Release-Manifest
  (`ls-tree` quotet `|` nicht, so ein Pfad fiel bisher still aus `--list factory` und damit aus der Liefermenge).
- **Abhängigkeiten / Secrets:** keine neuen Werkzeuge (`mktemp`, `tr` sind POSIX), keine Secrets im Diff. Die Tests
  räumen ihre `mktemp -d`-Verzeichnisse auf.

## Kritische Findings (Blocker)
- keine

## Wichtige Findings
- keine

## Hinweise
- [ ] [Ausgabe-Injection / Log-Spoofing, durch diesen PR eingeführt] `scripts/checks/ownership-check.sh:69`
  (`TRACKED_FILES` roh) → Ausgabe in Z. 224/226/227 (Tabellenmodus) und Z. 121 (Lock-Modus). Früher hat git
  Steuerzeichen gequotet. Jetzt erreichen CR, ESC (ANSI-Sequenzen) und andere C0-Zeichen aus einem Pfad ungefiltert
  das Terminal, die pre-push-Ausgabe und das CI-Log. Ein Pfad wie `x/evil<CR><ESC>[2K✓ Zuordnung vollständig …` kann
  die eigene `✗`-Zeile im Terminal mit einer falschen Erfolgszeile überschreiben. Die Wirkung bleibt kosmetisch: Exit 1,
  die rote pre-push-Zeile „push blockiert“ und der CI-Status bleiben richtig. Empfehlung: nur in den Meldezeilen (nicht
  in `--list`) Steuerzeichen sichtbar maskieren, z. B. in awk mit `gsub(/[[:cntrl:]]/, "?", shown)`. Alternative: Pfade
  mit Steuerzeichen außer Tab wie den Zeilenumbruch fail-closed mit Exit 2 abweisen. Einschätzung: kleinfunde (Nitpick).
- [ ] [Temp-Datei, durch diesen PR eingeführt] `scripts/checks/ownership-check.sh:52`: `mktemp` ohne `trap`. Bricht das
  Skript per Signal zwischen Z. 52 und 66 ab, bleibt eine Datei mit der Pfadliste im `$TMPDIR` liegen. Das ist nicht
  geheim, Modus 0600, zufälliger Name, also kein Symlink-Rennen. Scheitert `mktemp`, endet das Skript unter `set -e` mit
  Exit 1 statt 2. Das ist trotzdem fail-closed (≠ 0). Deckt sich mit dem Nitpick in `tasks/review-63.md`.
  Einschätzung: kleinfunde (Nitpick).
- [ ] [Vorbestehend, außerhalb des Scopes] `scripts/factory-release-manifest.sh:37` liest die Pfade per
  `git ls-tree -r --name-only` ohne `-z` und übergibt sie über `OWNERSHIP_FILE_LIST`, den die Spec bewusst nicht
  anfasst. Pfade mit `"`, `\` oder Steuerzeichen kommen dort gequotet an, „keiner Seite zugeordnet“ → `--list` Exit 1 →
  `die` (wegen `pipefail`). Das ist fail-closed (Release bricht ab), nicht fail-open. Ein Tab im Pfad würde zusätzlich
  das TSV in `hashes.tsv` zerlegen, wird aber vorher schon so abgewiesen. Einschätzung: kleinfunde (Nitpick), kein
  echtes Risiko.

Ablage: Hinweis 1 und 3 stehen in `docs/factory/kleinfunde.md`. Hinweis 2 ist schon als Nitpick in `tasks/review-63.md`
erfasst und bekommt keinen zweiten Eintrag. Kein Hinweis erreicht die Issue-Schwelle (ADR-043): Keiner ist fail-open, keiner
ist ausnutzbar über die Ausgabe hinaus.

Praktische Verifikation: ein Wegwerf-Skript mit präparierten Pfaden (`-n`, `--list`, `$(touch PWNED)`, `` `id` ``, `*`,
`[ab].md`, `a|b.md`, ESC, CR, `\xff\xfe`, `"`, `\`, Zeilenumbruch, `TMPDIR` ohne Verzeichnis) liegt im Scratchpad der
Session (`sec63.sh`). Ausführen ließ es sich in dieser Session nicht, denn Bash-Aufrufe außerhalb reiner Lesebefehle
waren nicht freigegeben. Die Befunde oben stützen sich deshalb auf Code-Analyse. Für die Fälle Zeilenumbruch, `"`,
`\`, Tab und `|` gibt es dazu die Tests der Suite (Block „Factory-Issue #63“).

## Ergebnis
PASSED
