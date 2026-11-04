# Review: Task 47

> Iteration 3 (Nachlauf auf den Security-Rework) · Schwerpunkt Commit `ce8f89e` (9 Dateien, +116/−10) im Kontext
> `origin/main...HEAD` · Spec `docs/specs/spec-47-copy-files-konfigurierbar.md` (F9), Factory-ADR-063 E25/E26,
> `tasks/security-47.md` W1. Suiten in dieser Session selbst gelaufen: ausgeliefert 2343/0, Projekt 145/0.
> Iteration 1: NEEDS_REWORK (W1), Iteration 2: APPROVED, siehe Task-Datei. Neuer Code seit Iteration 2 ist nur der
> Rework – der Circuit Breaker (3. Review auf denselben Code) greift deshalb nicht, ein weiteres NEEDS_REWORK
> ginge aber an den Menschen.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_ – Security-W1 ist behoben und selbst nachvollzogen: `copy_into_worktree`
(`scripts/start-work.sh:103`) prüft vor dem `cp` per `git -C "$WORKDIR" check-ignore -q -- "$entry"`, ein
nicht ignorierter Eintrag und jeder Git-Fehler führen zu Warnung + Überspringen (fail-closed). Die Reihenfolge
(nach `ensure_parent_dirs` und dem `-e`/`-L`-Guard) ist begründet und lässt die genaueren F6-/AK4-Meldungen
stehen. `info/exclude` liegt im gemeinsamen Git-Verzeichnis und gilt damit auch im Worktree – die Fixture-Wahl
ist korrekt; `REPO_SW` hat keine getrackte `.gitignore`, das `rm -f "$REPO_SW/.gitignore"` am Ende von F9
löscht also nur die eigene Testdatei.

## Nitpicks (optional)

- [ ] [scripts/start-work.sh:94/103] `ensure_parent_dirs` legt fehlende Elternordner **vor** dem Ignore-Guard an.
  Ein nicht ignorierter verschachtelter Eintrag (`sub/x.txt`) hinterlässt deshalb ein leeres `sub/` im Worktree.
  Harmlos (Git trackt keine leeren Ordner, `git add -A` committet nichts), die Reihenfolge ist wegen der
  F6-Meldung bewusst gewählt. Höchstens als Satz in E26 oder als Aufräumschritt erwähnenswert, kein Rework-Grund.
- [ ] [CHANGELOG.md:9-15, docs/factory/OPERATING.md:591-595] Beide Beschreibungen von `copy_files` nennen den neuen
  Ignore-Guard nicht. ADR E26, Spec F9, `git-workflow.md` und `factory.defaults.yml` sind nachgezogen. Für
  Konsumenten ist der CHANGELOG die Stelle, an der sie erfahren, dass eine nicht ignorierte gelistete Datei jetzt mit
  Warnung übersprungen wird – ein Halbsatz („nur im Worktree gitignorete Dateien") genügt. Doku-Drift im eigenen PR,
  daher im Scope und kein `kleinfunde.md`-Eintrag.
- [ ] [scripts/*47*.tmp.sh, tasks/telemetry-raw-47-*.tmp.txt] Die Wegwerf-Dateien liegen weiter im Baum
  (`probe47.tmp.sh`, `probe47ci.tmp.sh`, `review47.tmp.sh`, `review47b.tmp.sh`, zwei Telemetrie-Rohdateien). Sie
  sind gitignoret (`git status --ignored`), sollten aber vor dem Merge gelöscht werden (Lesson build-tooling).
  Diese Iteration hat keine neue Sonde angelegt.

## Positives

- **Fail-closed sauber umgesetzt:** `2>/dev/null` plus `!` behandelt rc 1 (nicht ignoriert) und rc 128 (Fehler,
  z. B. „beyond a symbolic link") gleich. Der Kommentar nennt den Grund (Folgeschritt `git add -A`) und die ADR-Stelle.
- **Test trifft die eigentliche Gefahr:** F9 prüft nicht nur, dass die Datei fehlt, sondern zusätzlich, dass
  `git status --porcelain --untracked-files=all` im Worktree leer ist – genau das, was `git add -A` sehen würde.
- **Zweite Variante deckt den Denkfehler ab**, den ein Gate-seitiger Check hätte (Muster nur in der uncommitteten
  `.gitignore` des Quellbaums). Das begründet auch, warum die Prüfung im Ziel und nicht im Config-Gate steht (E26).
- **Mutationsbeleg nach Lesson Factory-Task #23:** dieselbe Funktion `f9_unignored_refused` läuft auf Original und
  Mutante, die Mutante ersetzt die exakte Aufrufzeile (Anker auf die volle Zeile, `grep -cxF … -eq 1`).
- **Zwei-Einträge-Regel eingehalten:** der folgende, ignorierte Eintrag `lokal.conf` wird nach den abgelehnten
  trotzdem gespiegelt – assertiert.
- **`echo -e` → `printf '%s'` mitgezogen**, mit Regressionstest (`back\cslash.conf` erscheint wörtlich), und
  `kleinfunde.md` ist ehrlich gekürzt statt still gelöscht. Kein weiteres `echo -e` interpoliert noch einen Eintrag
  (`grep` über `start-work.sh` geprüft).
- **Doku-Drift im selben Commit:** ADR E25 (Quellseite folgt Symlinks bewusst) und E26, Spec F9, `git-workflow.md`,
  `factory.defaults.yml` und der Security-Report (W1 als behoben markiert) passen zum Code.

## Empfehlung

APPROVED
