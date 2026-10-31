# Lessons: Build & Tooling

> Ausgelagerte `/codify`-Learnings (Volltext) – generische Factory-Learnings zu **Build & Tooling**.
> **Nicht** `@import`-geladen (ADR-037) – bei Bedarf gezielt lesen. Kanonische Quelle je
> Regel ist der jeweilige Eintrag hier; im @import-Pfad (`PROJECT-CONTEXT.md`) steht nur eine Index-Zeile.
> Neue Learnings kommen in die Lesson-Datei **ihrer Seite** (Zuordnungsregel: betrifft das Learning eine
> Datei der Factory, d. h. eine von `bash scripts/checks/ownership-check.sh --list factory` gelistete,
> → `docs/factory/lessons/`, sonst → `docs/project/lessons/`;
> siehe `/codify` + ADR-037).
> Projekt-Anteil dieses Themas: `docs/project/lessons/build-tooling.md`.

### Debug-/Lint-Artefakte nicht durch .gitignore gedeckt (aus nothra/tch-gastro-services#67)

Im Lint-Debugging entstanden `lint-out.tmp.txt` und `scripts/lint-debug.tmp.sh` im
Arbeitsbaum. `.gitignore` deckte `*.log` und `*-debug.log*` ab, aber keine `.tmp`-Muster.
Der Review musste explizit auf das Entfernungserfordernis hinweisen – ohne diesen Fund
wären die Dateien mit `git add .` ins Repo gewandert.

**Regel:** `.gitignore` enthält jetzt `*.tmp.txt` und `*.tmp.sh`. Neue Debugging-/Lint-
Hilfsskripte, die nicht eingecheckt werden sollen, immer nach einem dieser Muster benennen
(oder das Muster in `.gitignore` ergänzen), bevor sie erstellt werden – nicht nachträglich
aufräumen.

**Nachtrag (aus nothra/tch-gastro-services#324): Muster wiederholt sich bei einer Wegwerf-E2E-Verifikation, und ihr
eigener Kommentar behauptete eine falsche Gitignore-Abdeckung.** Ein `/implement`-Lauf legte
zur manuellen Verifikation `e2e/verify-324.tmp.spec.ts` und `.verify-324/` (Screenshot-Ordner)
an. Der Kommentar in der Spec-Datei behauptete „`*.tmp.*` ist gitignoret" – tatsächlich deckte
`.gitignore` nur `*.tmp.txt`/`*.tmp.sh`/`*.tmp.py` ab, keinen Wildcard `*.tmp.*` und kein
`.verify-*/`-Verzeichnis; `git status` zeigte beide Pfade als `Untracked`. Die Behauptung wurde
nie gegen den echten `.gitignore`-Inhalt geprüft, nur angenommen.

**Regel (erweitert):** `.gitignore` deckt jetzt zusätzlich `*.tmp.spec.ts`/`*.tmp.spec.tsx`
(Wegwerf-E2E-Specs) und `.verify-*/` (Wegwerf-Verifikationsartefakte wie Screenshots) ab. Ein
Kommentar, der behauptet „Muster X ist gitignoret", ist selbst eine überprüfbare
Tatsachenbehauptung (vgl. `lessons/testing.md` nothra/tch-gastro-services#314-Learning zu unverifizierten
Verhaltensbehauptungen) – vor dem Anlegen einer Wegwerf-Datei `git check-ignore -v <pfad>`
gegen den geplanten Dateinamen laufen lassen, nicht das Muster erraten.

**Nachtrag (aus nothra/tch-gastro-services#374): drittes Vorkommnis – Wegwerf-Playwright-Config.** `playwright.capture.tmp.config.ts` für
die AK5.4-Aufnahmen stand im Review als `??` im `git status`; `*.tmp.spec.ts` deckte sie nicht ab. Das Muster
`*.tmp.config.ts` fehlt in `.gitignore` noch (Edit wurde in der Session nicht freigegeben, offen). Regel unverändert: vor dem Anlegen eines Wegwerf-Artefakts mit
`git check-ignore -v <pfad>` prüfen, dass ein Muster es deckt, nicht hinterher aufräumen.

**Nachtrag (aus Factory-Task #24): fünftes Vorkommnis – `tasks/telemetry-raw-<id>-*.tmp.txt` (von der Pipeline erzeugt) und `scripts/*.tmp.sh`-Sonden** lagen über sechs Skill-Läufe liegen, weil `rm` nicht freigegeben war; jeder Report vermerkte es, niemand löschte. Gitignoret heißt unkritisch für den Diff, aber stale für verzeichnisweite Scan-Guards (siehe `factory-workflow.md`). Sonden direkt nach Gebrauch über einen erlaubten Weg löschen (z. B. `bash scripts/…`-Wrapper) oder gar nicht erst anlegen.
