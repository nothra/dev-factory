# Review: Task 47

> Iteration 4 (Nachlauf auf den Security-Rework 2) · Schwerpunkt Commit `392e31f` (5 Dateien, +54/−6) im Kontext
> `origin/main...HEAD` · Spec `docs/specs/spec-47-copy-files-konfigurierbar.md` (F9), Factory-ADR-063 E26,
> `tasks/security-47.md` → „Nachlauf" W2. Suiten in dieser Session selbst gelaufen: ausgeliefert 2347/0, Projekt 145/0.
> Iteration 1: NEEDS_REWORK (W1), Iteration 2 und 3: APPROVED, siehe Task-Datei. Neu seit Iteration 3 ist nur der
> Rework `392e31f`. Der Circuit Breaker (3. Review auf denselben Code) greift deshalb nicht. Ein NEEDS_REWORK ginge
> hier aber an den Menschen.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_. Security-W2 ist behoben und selbst nachvollzogen. `copy_into_worktree` (`scripts/start-work.sh:104`)
prüft `git -C "$WORKDIR" check-ignore -q -- "./$entry"`. Die Sonde in dieser Session lief in einem Wegwerf-Repo mit
den Mustern `/.env.local`, `conf/*.local`, `*.secret` und `geheim`. Ergebnisse:
- `:geheim` und `:(top)geheim` → rc 1 (nicht ignoriert, fail-closed).
- Das verankerte Muster `/.env.local` greift weiter mit `./`-Präfix (rc 0). Damit ist der Konsumentenfall AK15 unverändert.
- Verschachtelte Pfade, Leerzeichen, ein führendes `-` und ein Eintrag, der selbst mit `./` beginnt (`./y.secret` → `././y.secret`), werden korrekt als ignoriert erkannt.
- Ein getracktes Ziel liefert rc 1 und wird übersprungen.
- Ein nicht ignorierter Eintrag liefert rc 1.

Die Sonde hat sich selbst gelöscht. Ihr Wegwerf-Repo liegt außerhalb des Baums in `$TMPDIR`.

## Nitpicks (optional)

- [ ] [docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md:820] Die neue Zeile ist nicht umbrochen: Der Satz
  „Grund: mit der frei wählbaren Liste …" hängt an der W2-Ergänzung, und die Zeile ist rund 170 Zeichen lang. Umbrechen
  wie im übrigen Absatz.
- [ ] [CHANGELOG.md:9-15, docs/factory/OPERATING.md:591-595] Offen aus Iteration 3: Beide Beschreibungen von
  `copy_files` nennen den Ignore-Guard nicht. Ein Halbsatz genügt („nur im Worktree gitignorete Dateien, sonst Warnung").
  Doku-Drift im eigenen PR, daher im Scope.
- [ ] [scripts/*47*.tmp.sh, tasks/telemetry-raw-47-*.tmp.txt] Offen aus Iteration 3: Diese Wegwerf-Dateien liegen
  weiter im Baum (gitignoret): `probe47.tmp.sh`, `probe47ci.tmp.sh`, `review47.tmp.sh`, `review47b.tmp.sh` und zwei
  Telemetrie-Rohdateien. Vor dem Merge löschen (Lesson build-tooling). Diese Iteration hat keine liegen gelassen.
- [ ] [scripts/start-work.sh:94/104] Aus Iteration 3, unverändert und harmlos: Ein leerer Elternordner bleibt zurück,
  wenn ein nicht ignorierter verschachtelter Eintrag vorkommt.

## Positives

- **Minimaler, gezielter Fix:** Ein Präfix an genau der Aufrufzeile. Der WHY-Kommentar nennt den Mechanismus
  (Pathspec-Magie, `:x` wird zu `x`) und den Grund, warum `--literal-pathspecs` ausscheidet. Der Validator bleibt
  unverändert. Die Entscheidung gegen eine zusätzliche `:`-Regel ist in der Task-Datei begründet.
- **Test trifft die Gefahr:** `f9_pathspec_refused` prüft das fehlende Ziel und zusätzlich `git status`. Das Muster
  `geheim` ist so gewählt, dass es nur den aufgelösten Namen trifft. Damit wird genau die Pathspec-Verwechslung
  geprüft und nicht ein beliebiger nicht ignorierter Fall.
- **Mutationsbeleg nach Lesson Factory-Task #23:** Dieselbe Funktion läuft auf Original und Mutante. Die Mutante
  stellt die exakte Vor-Fix-Zeile wieder her. Der Anker ist die volle Zeile mit `grep -cxF … -eq 1`.
  `SW_IGN_LINE` des bestehenden F9-Mutationsbelegs ist mitgezogen, sonst wäre der F9-Beleg still unwirksam geworden.
- **Aufräumen:** `:geheim` wird am Ende entfernt. Der `info/exclude`-Eintrag fällt mit dem bestehenden Reset am
  Gruppenende (`run-tests.sh:2450`). Jeder Lauf hat eine eigene Task-ID (811–813).
- **Doku-Drift im selben Commit:** ADR E26 und Spec F9 sind nachgezogen und passen zum Code.

## Empfehlung

APPROVED
