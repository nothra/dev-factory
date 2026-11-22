# Review: Task 61

> Iteration 1 · Diff `origin/main...HEAD` (12 Dateien, +487/−193) · Spec `docs/specs/spec-61-sigpipe-flake-printf-grep.md`.
> Statisches Review: Skript-Ausführungen (Mutante, Guard-Sonden, Suiten) wurden in dieser Session nicht freigegeben, Belege
> unten sind aus dem Code abgeleitet.

## Kritische Findings (müssen behoben werden)
- [ ] [scripts/checks/tests/run-tests.sh:7403] **Rest-Fundstelle im Scope, vom Guard nicht erkannt:**
  `printf '%s' "$sec_out" | LC_ALL=C grep -q "$(printf '\033')\[2J"`, danach eine Abwesenheits-Assertion (Zeile 7404).
  Genau das Muster aus AK4 (Produzent `printf`), und in der Falsch-Grün-Richtung aus der Spec. Der Guard übersieht es,
  weil `[|][[:space:]]*grep` keine Umgebungs-Zuweisung zwischen Pipe und `grep` zulässt. Damit stimmt AK6 („Guard findet
  nichts" = Bestand sauber) nur formal. **Fix:** Zeile auf `LC_ALL=C grep_in "$sec_out" -q …` umstellen. Den Guard um
  optionale `NAME=wert`-Präfixe (und `command`) vor `grep` erweitern. Mutationsfall `… | LC_ALL=C grep -q x` → rot ergänzen.

## Wichtige Findings (sollten behoben werden)
- [ ] [scripts/checks/tests/lib/assert-helpers.sh:314-318] **Guard ist bei nicht lesbaren Eingaben fail-open:**
  `! grep -nHE … "$@" | grep -vE …`. Fehlt die Datei oder ist der Glob leer, endet das erste `grep` mit 2 und das zweite
  mit 1. pipefail meldet den rechtesten Fehler (1), `!` macht daraus 0, und der Guard ist grün, nur mit einer
  stderr-Meldung. Das trifft die AK6-Aufrufe (`"$CHECKS_DIR"/tests/*.sh`, `"$PROJECT_TESTS_DIR"/*.sh`), sobald ein Pfad
  driftet. **Fix:** Exit 2 des ersten `grep` getrennt auswerten, z. B. Treffer erst in eine Variable fangen und
  `rc -ge 2` als Fund melden. Dazu ein Mutationsfall „nicht existierende Datei → rot".
- [ ] [scripts/checks/tests/lib/assert-helpers.sh:316] **Guard-Lücken bei Optionsformen:** `-[A-Za-z-]+` lässt keine Ziffern
  und keine Options-Argumente zu. `… | grep -m1 -q x` und `… | grep -e foo -q` bleiben deshalb unerkannt, ebenso `|& grep -q`.
  Im Bestand gibt es dazu heute keinen Treffer. Spec-konform, denn AK4 verlangt nur `printf`/`echo` mit `-q`. Mit
  dem Fix aus dem kritischen Finding lassen sich diese Formen aber billig mit abdecken (`-[A-Za-z0-9-]+`, `|&?`).
- [ ] [tasks/task-61-sigpipe-flake-printf-grep.md, Technische Notizen] **Issue für `scripts/checks/pre-commit.sh:27,35,51`
  steht aus:** `git diff --cached | grep -qE …` unter `set -euo pipefail` (Zeile 10), im Review bestätigt. Bei großem
  Staged-Diff und frühem Treffer lässt das Gate Konfliktmarker, Debug-Ausgaben und Secrets **durch** (fail-open). Das ist
  ein funktionaler Defekt mit reproduzierbarem Auslöser und liegt nach Factory-ADR-043 oberhalb der Schwelle, also ein
  Issue (Labels `bug` + `security`). Der Anlage-Versuch über `create_issue_idempotent` wurde in dieser Session von der
  Sandbox abgelehnt. **Mensch/nächster Schritt:** Issue anlegen, Nummer in Task-Datei und PR-Body nennen. Die offene Checkbox in
  der Task-Datei hängt daran.

## Nitpicks (optional)
- [ ] [scripts/checks/tests/run-tests.sh, Seam-Block `n_labels=$(grep_in "$(tail -n1 "$LOG")" -oE -- '--label' | wc -l …)`]
  Diese Zeile ist ein `grep -o` (liest bis EOF) und wurde trotzdem umgestellt. Laut Technischen Notizen werden nur
  `grep -q…`-Zeilen umgestellt. Harmlos; entweder zurückdrehen oder die Notiz anpassen.
- [ ] [scripts/checks/tests/lib/assert-helpers.sh:310-313] Der Kommentar könnte die bewusst nicht erkannten Formen nennen
  (Env-Präfix, Options-Argumente), solange der Guard sie nicht abdeckt. So weiß der nächste Leser, wo die Grenze liegt.
- [ ] [docs/factory/lessons/testing.md:142-145] Der umformulierte Satz („… <<< "$flat"` – ursprünglich per `printf | grep -qF`,
  das ist ein SIGPIPE-Race …") hat jetzt einen sehr langen Einschub in der Klammer. Als eigener Satz wäre er leichter zu lesen.

## Positives
- Die Ursache sitzt genau an der richtigen Stelle: der Helfer selbst. Ein zentraler Fix (`grep_in`) statt 180 einzelner
  Workarounds, dazu eine klare Begründung im Kommentar, warum der Here-String keinen Produzenten hat, der sterben könnte.
- Die AK1/AK2-Tests erzwingen die Race deterministisch (1 MB, Nadel in Zeile 1, 200×). Gegen den alten Helfer
  `printf '%s' "$1" | grep -qF` wird der Produzent bei 1 MB praktisch immer per SIGPIPE beendet. Der RED-Beleg aus der
  Task-Datei ist damit plausibel.
- `helper_runs_61` isoliert die Suite-Zähler sauber in einer Subshell. Die Guard-Fixtures entstehen über `$PIPE_61`, damit
  die Suite das Muster nicht selbst enthält. Das ist ein elegantes Vermeiden der Selbstauslösung.
- Die Mutationsbelege decken beide Seiten ab: rot bei printf, echo, tail, `-Fqx`, `-E -q` und `--quiet`; grün bei
  Here-String, Datei, Kommentar, `grep -c`, `||` und `q` nur im Muster.
- Stichproben der mechanischen Umstellung (Seam-Block, #212/#298 `efs_msg`, #258 yq, #49/#348 Turn-Staffelung,
  factory-lock-23/24b/41/44/66, `lessons_index_guard_44`, Projekt-Suite #348/#431) sind semantisch gleichwertig. Auch
  verschachtelte Produzenten (`grep_in "$(grep -E … <<< …)"`) und negierte Prüfungen behalten ihr Verhalten bei
  Produzenten-Fehlern. Kein `grep_in` nutzt `-v` oder ein Leer-Muster, für das der angehängte Zeilenumbruch des
  Here-Strings einen Unterschied machen würde.
- Guard-Ort nach Factory-ADR-064 D6 korrekt getrennt: die ausgelieferte Suite prüft `scripts/checks/tests/`, die
  Projekt-Suite ihr eigenes Verzeichnis.
- Lesson nachgezogen (AK9): Die überholte Einschränkung „nur kurze Literale" ist entfernt, der Verweis auf den Guard steht
  drin. Der Kleinfund-Eintrag für Produktiv-Skripte hält das Schema ein.
- Projektregeln eingehalten: keine neue getrackte Datei ohne OWNERSHIP-Zeile (es entsteht keine neue Skriptdatei), Verweise
  qualifiziert, keine Herkunftsbegriffe.

## Empfehlung
NEEDS_REWORK
