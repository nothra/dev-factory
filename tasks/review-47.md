# Review: Task 47

> Iteration 1 · Diff `origin/main...HEAD` (14 Dateien, +908/−331) · Spec `docs/specs/spec-47-copy-files-konfigurierbar.md`,
> Factory-ADR-063 Nachtrag 2026-11-01 (E23–E27). CI des PRs grün (factory-self-test, project-self-test, lint,
> config-validation, factory-integrity). Randfälle von `factory_cfg_list`, `copy_entry_problem` und Regel 2/9 mit
> einer Wegwerf-Sonde selbst nachvollzogen (siehe W1).

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] [scripts/lib/gate-config.sh:41 · scripts/start-work.sh:293 · docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md (E24) · Spec F8]
  **Nicht-String-Einträge und Einträge mit Steuerzeichen verschwinden in `start-work.sh` ohne Warnung – ADR und Spec
  sagen „gewarnt".** `factory_cfg_list` filtert solche Elemente vorab heraus (`select(tag == "!!str")`,
  `select(test("[[:cntrl:]]") | not)`), sodass sie `copy_into_worktree` und damit die Warnung aus `copy_entry_problem`
  nie erreichen. Selbst geprüft: `copy_files: [".env.local", 5, "a\nb", "ok two"]` liefert nur `.env.local` und
  `ok two`, ohne jede Ausgabe zu `5` oder `"a\nb"`. E24 sagt dagegen: „Ein ungültiger Eintrag wird im Skript gewarnt
  und übersprungen, nie kopiert." Die Spec sagt bei den Fehlerszenarien: „Eine Warnung im Output gibt es in allen
  Fällen außer F1 und F7." Der Zweig `*[[:cntrl:]]*` in `copy_entry_problem` wird damit von `start-work.sh` aus nie
  erreicht, er greift nur im Gate. Das Verhalten ist sicher (nichts wird kopiert), aber Code und Beschreibung passen
  nicht zusammen (Lesson nothra/tch-gastro-services#211: ändert ein PR die Mechanik, die eine ADR beschreibt, wird die
  ADR im selben PR nachgezogen). Zwei Möglichkeiten, eine davon wählen:
  (a) In `start-work.sh` warnen, wenn Einträge verworfen wurden, z. B. durch einen Vergleich der Rohlänge
  (`factory_cfg "start_work.copy_files | length"` o. ä.) mit der Zahl der gelieferten Zeilen: „N Einträge übersprungen
  – kein String oder Steuerzeichen im Pfad". Dazu ein Test mit `[5, "lokal.conf"]`.
  (b) E24, Spec F8 und den Header von `factory_cfg_list` so formulieren, dass Nicht-Strings und Steuerzeichen-Einträge
  **ohne** Warnung entfallen, weil das Gate sie ablehnt.
  (a) passt besser zu „Defense in depth", weil das Gate nur im pre-push-Hook läuft.

## Nitpicks (optional)

- [ ] [scripts/checks/tests/run-tests.sh (F5-Block, `blockiert/x.conf`)] Der F5-Test belegt nur den Zweig „Komponente
  ist kein Verzeichnis" (`ensure_parent_dirs`, `elif [ -e "$dir" ]`). Der Zweig `mkdir` scheitert („Ordner … ließ sich
  nicht anlegen", z. B. schreibgeschützter Elternordner) läuft nie. Die Assertion `'blockiert/x.conf übersprungen'`
  passt auf beide Meldungen und trennt sie deshalb nicht. Für `/test`: den spezifischen Grund assertieren und den
  `mkdir`-Zweig mit `chmod 555` auf einem Worktree-Ordner abdecken (Skip als root, wie F3).
- [ ] [scripts/checks/tests/run-tests.sh (AK8 `run_start_work … 783 demo-skipenv` und In-Place `bash "$SW" 783 demo-ip`)]
  Task-ID 783 wird jetzt doppelt vergeben. Vorher hatte jeder Fall der Gruppe eine eigene ID (782 Opt-out, 783 In-Place).
  Das ist heute harmlos, weil die Branch-Namen verschieden sind, macht die Fälle aber weniger unabhängig. Eine freie ID
  nehmen (z. B. 802).
- [ ] [docs/factory/OPERATING.md:595] Die Aufzählung „lehnt absolute Pfade, `..`-Segmente, leere Einträge,
  abschließendes `/` und Nicht-Strings … ab" lässt Steuerzeichen weg, die Regel 9 über `copy_entry_problem` ebenfalls
  ablehnt (E24 nennt sie). Ein Wort ergänzen.
- [ ] [scripts/start-work.sh:293] `factory_cfg_list … 2>/dev/null || COPY_FILES=""` verschluckt auch „yq nicht
  gefunden". Ein Konsument, der nach der Migration `copy_files` gesetzt hat, aber kein `yq` installiert hat, bekommt
  still keine Kopie. Vor diesem PR wurde die `.env.local` ohne `yq` kopiert. Der Hinweis-Block hat dasselbe Muster, und
  `yq` ist Factory-Prerequisite. Trotzdem wäre eine Warnung bei Exit ≠ 0 billig.
- [ ] [scripts/start-work.sh (`copy_into_worktree`)] Nur die Ziel-Elternkette wird auf Symlinks geprüft (E25), die
  Quell-Elternkette nicht. Ein Eintrag `link/x` mit `$FACTORY_DIR/link → /irgendwo` liest also außerhalb des Quellbaums
  und kopiert in den Worktree. Die Config ist vertrauenswürdig und das Lesen ist nicht vom Scope der Spec erfasst, also
  ist das kein Defekt. Als Hinweis für `/security-review` gedacht, die die Einordnung bestätigen soll.
- [ ] [tasks/telemetry-raw-47-20261102T203824Z.tmp.txt, tasks/telemetry-raw-47-20261102T204037Z.tmp.txt] Die
  Telemetrie-Rohdateien aus dem abgebrochenen Pipeline-Lauf liegen noch im Baum. Sie sind gitignoret, aber die Lesson
  build-tooling sagt, Wegwerf-Dateien direkt nach der Nutzung zu löschen. Dasselbe gilt für die Review-Sonde
  `scripts/review47.tmp.sh`, deren `rm` in dieser Session nicht freigegeben war.

## Positives

- **Ein Validator für Gate und Skript (E24)** ist sauber umgesetzt. `copy_entry_problem` gibt immer 0 zurück und ist
  damit sicher unter `set -e`. Gate und `start-work.sh` rufen dieselbe Funktion, es gibt keine zweite Regel, die
  driften kann.
- **`ensure_parent_dirs`** setzt E25 genau um: Komponente für Komponente, `mkdir` ohne `-p`, Symlink-Prüfung vor dem
  Verzeichnis-Test, ohne `realpath`. `a//b` und `./x` werden korrekt übergangen (selbst geprüft).
- **Regel 9 liest die Elemente per Index** statt zeilenweise, mit dem `|`-Suffix gegen das Abschneiden von
  Zeilenumbrüchen. So kommt ein Eintrag mit eingebettetem Zeilenumbruch wirklich als **ein** ungültiger Eintrag an. Gut
  begründet im Kommentar.
- **Die Änderung an Regel 2 („ist keine Liste")** ist generisch richtig: `leaf_paths` normalisiert auch nicht leere
  Listen auf `.*`. Selbst geprüft mit `labels.kinds: bug` → „ist keine Liste". `copy_files: {}` landet sauber in
  Regel 9 (Typ `!!map`).
- **Tests:** Der Mutationsbeleg zu AK4 führt dieselbe Prüffunktion auf Original und Mutante aus (Lesson Factory-Task
  #23), mit einem Anker auf die exakte Guard-Zeile und einer Prüfung, dass sie genau einmal vorkommt. Der
  Ursprungs-Wortlaut-Guard zu AK16 setzt seine Begriffe zur Laufzeit zusammen (Lesson nothra/tch-gastro-services#319),
  bricht die Extraktion fail-closed ab und hat einen eigenen Mutationsbeleg. AK14 prüft je Grund Schlüssel **und**
  Grund in der Meldung. Die Fälle mit mehreren Einträgen belegen durchgängig „Folge-Eintrag läuft weiter".
- **Fixture-Hygiene:** `cp_pipeline_libs` kopiert `gate-config.sh` schon mit (Lesson nothra/tch-gastro-services#197 ist
  erfüllt). Das Gate sourct die Lib relativ zum Skript (Lesson nothra/tch-gastro-services#431). Die Fixture-Config wird
  am Gruppenende zurückgesetzt.
- **Doku und ADR** sind vollständig nachgezogen (FACTORY.md Regel 8, git-workflow.md, OPERATING.md, `.gitignore*`,
  CHANGELOG mit Migrationszeile, ADR-Status Accepted, Q4 ergänzt). Ein Doku-Guard in der Suite sichert das ab.
- **Scope-Disziplin:** Das scope-fremde `skills.implement.max_turns` aus dem Zwischenstand wurde erkannt und
  zurückgenommen.

## Empfehlung

NEEDS_REWORK
