# ADR 063: Factory in eigenes Repo – versionierte Übernahme per Manifest

## Status
Proposed

## Date
2026-10-19

## Kontext

Spec [#424](../specs/spec-424-factory-in-eigenes-repo-auslagern.md) verlangt, die dm Development
Factory aus dem TCH-Repo in ein eigenes Repo auszulagern und als wiederverwendbares, versioniertes
Werkzeug zu betreiben. Bereits entschieden (Spec, Entscheidungstabelle): Historie wird mitgenommen,
neue Versionen kommen als automatischer Update-PR, lokale Änderungen an übernommenen Dateien sind
verboten, Factory-Funde aus Projekt-Arbeit gehen direkt ins Factory-Repo, die Factory entwickelt
sich mit der eigenen Pipeline, `factory-pipeline` wandert ins Factory-Repo und TCH bekommt
`build-pipeline`.

**Befund der Bestandsaufnahme (2026-10-19):**

- **Sichtbarkeit:** `nothra/tch-gastro-services` ist inzwischen **öffentlich** (Ruleset
  `protect-main` aktiv, ADR-029); der Account läuft im **Free-Plan**. Ein **privates** Factory-Repo
  hätte im Free-Plan **keinen** serverseitigen `main`-Schutz (Rulesets für private Repos gesperrt) –
  AK1.6 wäre nicht erfüllbar – und bräuchte in jedem Projekt einen Lese-Token. Der Factory-Inhalt
  ist über das öffentliche TCH-Repo ohnehin schon öffentlich. **Entscheidung mit dem Entwickler
  (2026-10-19): Factory-Repo öffentlich**, Name **`nothra/dev-factory`** (korrigiert die
  Spec-Entscheidung „privat").
- **Mischdateien:** `CLAUDE.md` (Factory-Regeln + TCH-Regeln wie Routen-Doku), `.claude/settings.json`
  (Factory-Hooks/-Permissions + `Edit(app/**)` u. ä.), `.gitignore`,
  `.github/workflows/factory-ci.yml` (Factory-Jobs + pnpm-`lint`/`test`), `pre-push.sh` (ruft
  hart `routes-doc-check.sh`), Skill-/Agent-/Guideline-Texte mit pnpm-/DB-Hinweisen
  (`implement.md`, `coding-agent.md`, `review-agent.md`, `git-workflow.md`, `testing-standards.md`,
  `bash-gotchas.md`), die Label-Tabelle in `git-workflow.md`, der Lessons-Index in
  `PROJECT-CONTEXT.md`.
- **TCH-spezifische Factory-nahe Dateien:** `scripts/neon-reset-int.sh`, `scripts/deploy-freeze*.sh`,
  `.github/workflows/deploy-gate.yml`, `deploy-freeze-release.yml`, `scripts/checks/routes-doc-check.sh`,
  Lessons `frontend-react.md`, `db-drizzle.md`, `next-auth.md`, Teile von `build-tooling.md`/`testing.md`.
- **Gemischte Self-Test-Suite:** `scripts/checks/tests/run-tests.sh` (~8 600 Zeilen) testet auch die
  TCH-spezifischen Skripte.
- **ADR-Verweise:** übernommene Dateien zitieren Factory-ADRs hundertfach (z. B. ADR-019 49×,
  ADR-018 33×). Die gemeinsame Nummernfolge enthält Dubletten (027, 032, 040 – #321).
- **Vorhandene Bausteine:** ADR-009 sieht bereits „Defaults vom Template + Team-Override" vor;
  der Issue-Seam (ADR-018) nimmt schon einen Ziel-Repo-Slug (`$FACTORY_REPO`) entgegen.

## Entscheidung

### D1 · Verteilung: committete Kopie + Manifest (`factory.lock`)

Übernommene Dateien liegen **an ihren heutigen Pfaden** committet im Projekt-Repo (`scripts/`,
`.claude/commands/`, `docs/factory/` …) – kein Verschieben nach `.factory/`, weil Claude Code und
die Hooks feste Pfade erwarten und die Umbau-Fläche klein bleiben soll.

Ein **Manifest `factory.lock`** (JSON, Repo-Wurzel, neben `factory.config.yml`) hält: Quell-Repo,
Version (Tag), Commit-SHA und je übernommener Datei Pfad + SHA-256. Es ist die **einzige** Stelle
der eingebundenen Version (AK2.1) und zugleich die maschinenlesbare Antwort auf „gehört diese
Datei der Factory?" (AK2.12).

Ein deterministisches Bash-Skript **`scripts/factory-sync.sh <version>`** (übernommen) lädt den
Tag aus `nothra/dev-factory` (öffentlich → ohne Token), prüft ihn gegen das Release-Manifest,
schreibt alle Dateien zunächst in ein Temp-Verzeichnis und ersetzt erst bei vollständigem Erfolg
(keine halbe Aktualisierung, F4). Dateien, die in N+1 entfallen, werden gelöscht; Anpassungsstellen
(D3) werden nie angefasst (AK2.3).

### D2 · Update-PR: Pull aus dem Projekt, ein fester Branch

Übernommener Workflow **`factory-update.yml`** im Projekt-Repo (Schedule täglich +
`workflow_dispatch`): liest das neueste Release von `nothra/dev-factory`, vergleicht mit
`factory.lock`, führt bei neuerer Version `factory-sync.sh` aus und pflegt **einen** festen Branch
`chore/factory-update` (bei jeder neuen Version neu aufgebaut) mit **einem** PR (F3); der PR-Body
trägt die Release Notes (AK2.2). **Kein Auto-Merge** (AK2.4).

PR-Erstellung mit einem **Fine-grained PAT `FACTORY_SYNC_TOKEN`** statt `GITHUB_TOKEN`, weil mit
`GITHUB_TOKEN` erstellte PRs keine `pull_request`-Workflows auslösen – die Gates würden nicht
laufen. Rechte: Projekt-Repo *contents:write* + *pull-requests:write*; `nothra/dev-factory`
*issues:write* (D7). Laufzeit max. 1 Jahr → Rotation in `OPERATING.md` dokumentieren. Der Workflow
verbraucht keine Claude-Tokens; der stillgelegte `factory-poll`-Schedule (#284) ist davon unberührt.

Pull statt Push (Factory-Release schreibt in Konsumenten-Repos), weil die Factory dann kein
Konsumenten-Register und keine Schreibrechte in fremde Repos braucht.

### D3 · Besitz: jede Datei gehört genau einer Seite – keine Mischdateien

Regel: Eine Datei ist **entweder** übernommen (im Manifest) **oder** projekteigen. Es gibt keine
Marker-Blöcke in übernommenen Dateien. Mischdateien werden so aufgelöst:

| Heute | Danach |
|---|---|
| `CLAUDE.md` | **projekteigen**, dünn: `@docs/factory/FACTORY.md` (übernommen, der generische Teil der heutigen `CLAUDE.md`) + `@docs/factory/PROJECT-CONTEXT.md` + projekteigene Regeln (z. B. Routen-Doku). `import-context-limit-check.sh` folgt den Imports wie bisher. |
| `.claude/settings.json` | **zusammengesetzt** (siehe unten) aus `.claude/settings.factory.json` (übernommen) + `.claude/settings.project.json` (projekteigen) |
| `.gitignore` | **zusammengesetzt** aus `docs/factory/gitignore.factory` (übernommen) + `.gitignore.project` (projekteigen) |
| `factory-ci.yml` | übernommen, nur noch Factory-Jobs (`pr-closes-issue`, `issue-sync`, `config-validation`, `factory-self-test`, `factory-integrity`, `post-merge-verify`); `lint`/`test` wandern in projekteigenes `ci.yml` (Job-Namen bleiben → Required Checks in `protect-main` unverändert, nur `factory-integrity` kommt hinzu) |
| `pre-commit.sh`/`pre-push.sh` | übernommen; rufen zusätzlich jedes ausführbare Skript in `scripts/project/checks/pre-commit.d/` bzw. `pre-push.d/` (projekteigen, lexikalisch, fail-closed). `routes-doc-check.sh` wandert dorthin. |
| Gate-Kommandos (`pnpm lint` …) | Werte aus `factory.config.yml` → `commands.{lint,test,typecheck,format,coverage}` (ADR-009-Schichtung); `factory.defaults.yml` liefert **keinen** pnpm-Default, fehlender Wert = klarer Fehler. TCH setzt seine heutigen Werte → Verhalten unverändert (AKE.1). |
| Label-Tabelle | übernommene Art-/Aspekt-Labels in `factory.defaults.yml` → `labels.aspects`; projekteigene in `factory.config.yml` → `labels.aspects_extra` (TCH: `build-pipeline`), Bedeutung/Zuordnungsregel in `PROJECT-CONTEXT.md` (AK3.9). `start-work.sh` und Seam validieren gegen die Vereinigung. `git-workflow.md` beschreibt nur das Schema. |
| Skill-/Agent-/Guideline-Texte mit pnpm/DB/E2E-Details | generisch formulieren, Projekt-Details in `PROJECT-CONTEXT.md` (neuer Abschnitt „Lokale Umgebung & Oberflächentests"), auf den die Texte verweisen |
| Lessons | generische bleiben in `docs/factory/lessons/` (übernommen); TCH-spezifische nach `docs/project/lessons/` (projekteigen). `PROJECT-CONTEXT.md` indiziert beide. |
| TCH-only-Skripte/Workflows (`neon-reset-int.sh`, `deploy-freeze*`, `deploy-gate.yml` …) | projekteigen; Skripte nach `scripts/project/`; ihre Self-Tests nach `scripts/project/tests/` |

**Zusammengesetzte Dateien** (`.claude/settings.json`, `.gitignore`): Weil Claude Code genau eine
geteilte Projekt-Settings-Datei und Git eine Wurzel-`.gitignore` liest, erzeugt
`factory-sync.sh` sie deterministisch aus Factory- und Projekt-Fragment (Settings per `jq`:
Arrays vereinigt und sortiert, Hooks hintereinander; Gitignore: Factory-Teil, dann Projekt-Teil).
Das Ergebnis wird committet; das Manifest führt sie als `composed` mit den Fragment-Hashes, und der
Integritäts-Check prüft „Datei == Zusammensetzung(Fragmente)". Ändern geht nur über das
Projekt-Fragment + erneutes Zusammensetzen (`factory-sync.sh --compose`).

**Anpassungsstellen** (nie überschrieben, AK2.3): `CLAUDE.md`, `factory.config.yml`,
`docs/factory/PROJECT-CONTEXT.md`, `.claude/settings.project.json`, `.gitignore.project`,
`scripts/project/**`, `docs/project/**`, `docs/adr/**`, `docs/specs/**`, `tasks/**`,
alle Workflows außer den übernommenen, aller App-Code. Kanonisch ist das Manifest: was nicht drin
steht, gehört dem Projekt.

### D4 · Integritäts-Gate zweistufig

`scripts/checks/factory-integrity-check.sh` (übernommen):

1. **Lokal (pre-commit/pre-push, offline):** jede Manifest-Datei existiert und hat den
   eingetragenen Hash; zusammengesetzte Dateien entsprechen ihren Fragmenten. Abweichung oder
   Löschung (F7) → Abbruch mit Dateiname und Hinweis „Änderung gehört nach nothra/dev-factory"
   (AK2.5).
2. **CI-Job `factory-integrity` (required Check in `protect-main`):** zusätzlich wird das Manifest
   selbst gegen das Release-Manifest des eingetragenen Tags in `nothra/dev-factory` geprüft. Damit
   fängt CI auch den Umgehungsversuch „Datei **und** Hash im Manifest geändert". Ein Update-PR
   besteht beide Stufen, weil er Version, Hashes und Dateien konsistent auf einen echten Tag hebt
   (AK2.6).

Im Factory-Repo selbst (Quelle, kein `factory.lock`) ist der Check ein No-op mit Hinweis.

### D5 · Historie: `git filter-repo` mit Pfad-Allowlist + Vorab-Scan

Das Factory-Repo entsteht aus einem **frischen Klon** von TCH per `git filter-repo` mit einer
**Allowlist** genau der übernommenen Pfade (aus der Zuordnungstabelle in T1a, AK1.5); dadurch
fehlen App-Code (`app/`, `db/`, `lib/` …), Tasks, Specs und TCH-Doku in der gesamten Historie
(AK1.4). Vor dem ersten Push: Secret-Scan über **die ganze umgeschriebene Historie** (`gitleaks`)
plus Grep auf TCH-Domänenbegriffe und E-Mail-Muster in Datei-Inhalten (AK1.3/1.4, F5) – das Repo
ist öffentlich, ein Fund ist danach nicht mehr rückholbar. Commit-Autoren-Metadaten bleiben (die
eigenen Adressen des Entwicklers; kein Anwendungsdatum).

`git filter-repo` ist ein einmaliges Entwicklerwerkzeug (lokal per `pip`/`brew`), kein CI-Bestandteil.

### D6 · Versionen: SemVer-Tags + GitHub Release

Tags `vMAJOR.MINOR.PATCH` in `nothra/dev-factory`, je Tag ein GitHub Release mit Release Notes
(bestehender Skill `/release-notes`) und dem Release-Manifest (Pfad + SHA-256) als Asset;
zusätzlich `CHANGELOG.md` (AK1.8). Start mit **`v0.6.0`** (Fortsetzung der bisherigen Angabe
„v0.5.0"); bis zur Stabilisierung nach T3 darf eine MINOR-Version brechen, Brüche stehen unter
„Breaking" in den Notes. Ein Release ist ein bewusster menschlicher Schritt (Tag), nicht jeder Merge.
Die Versionsangabe in `FACTORY.md` wird aus dem Tag erzeugt, nicht von Hand gepflegt.

### D7 · Factory-Funde aus Projekten → Factory-Repo

Seam-Erweiterung (ADR-018) um **`create_factory_issue`** mit demselben stdout/stderr-Kontrakt wie
`create_issue`, Ziel `factory.config.yml` → `upstream.repo` (Default `nothra/dev-factory`):

- **Zuordnung (AK2.12):** Fund betrifft eine Datei aus `factory.lock` → Factory; betrifft er
  Pipeline-/Skill-Verhalten ohne Datei-Bezug → im Zweifel Factory; sonst Projekt.
- **Formen:** Issue oberhalb der ADR-043-Schwelle (AK2.9); Kleinfund als Issue mit Label
  `kleinfund` (AK2.10, im Factory-Repo kein `kleinfunde.md`-Schreibweg von außen); generisches
  Learning aus `/codify` als Issue mit Label `lesson-vorschlag` (AK2.11). Herkunftsblock
  (Projekt-Slug, Task-ID, PR-Link) wird vom Seam vorangestellt.
- **Inhalt (AK2.13):** Der Seam lehnt Bodies mit Treffern aus derselben Credential-Heuristik wie
  `pre-commit.sh` ab; Skills beschreiben den Factory-Defekt, nicht die Fachlichkeit.
- **Berechtigung:** lokal die `gh`-Anmeldung des Entwicklers; in CI/Stage 3 `FACTORY_SYNC_TOKEN`.
- **Fallback (F8):** scheitert die Anlage, schreibt der Seam den Fund in den Abschnitt
  „Factory-Funde (nicht übertragen)" der Task-Datei, warnt auf stderr und gibt Exit 0 mit leerem
  stdout zurück – der Lauf bricht nicht ab.

### D8 · ADRs: getrennte Nummernräume, Altnummern bleiben

Factory-ADRs behalten ihre Nummern und liegen künftig unter **`docs/factory/adr/`** (übernommen,
also auch in jedem Projekt lesbar – die hunderten `ADR-NNN`-Verweise in übernommenen Dateien
bleiben gültig). App-ADRs bleiben in `docs/adr/`. Ab der Trennung führen beide Repos **eigene**
Nummernfolgen ab der jeweils höchsten vorhandenen Nummer. Auflösung von Verweisen ist
**ortsabhängig**: `ADR-NNN` in übernommenen Dateien → `docs/factory/adr/`, in projekteigenen →
`docs/adr/`; projekteigene Texte, die eine Factory-ADR meinen, schreiben `Factory-ADR-NNN`. Ein
Verweis-Check prüft beides (AK3.2, F6). Die Dubletten aus #321 werden je Seite in #321 gelöst
(zieht als Factory-Issue mit um, soweit Factory-ADRs betroffen sind).

### D9 · Factory-Repo nutzt sich selbst

`nothra/dev-factory` ist zugleich Quelle und Konsument seiner selbst: eigene `factory.config.yml`
(`commands.lint` = ShellCheck über `scripts/`, `commands.test` = `run-tests.sh`), eigene
`PROJECT-CONTEXT.md`, eigene `docs/specs/`, `tasks/`, Ruleset `protect-main`, CI mit
`factory-self-test`. `start-work.sh` und die Skills laufen dort unverändert (AK1.7). Die
Issue-Nummerierung beginnt dort neu; alte TCH-Tasks/-Specs bleiben als Archiv in TCH.

### D10 · Neues Projekt aufsetzen

`init-factory.sh` geht in **`factory-sync.sh --init <version>`** auf: Dateien + Manifest +
Vorlagen der Anpassungsstellen (`templates/` im Factory-Repo, nicht übernommen) + `install-hooks.sh`.
Nachweis (AK2.7) zweifach: ein Self-Test initialisiert ein Temp-Repo offline und lässt die Gates
laufen; einmalig ein echtes Wegwerf-Repo nach `docs/factory/NEW-PROJECT.md`, Ergebnis im T2-PR.

### D11 · Schnitt in vier Teil-Tasks (verfeinert die Spec)

Mit dem Entwickler vereinbart (2026-10-19): T1 wird geteilt, damit die Factory bis zum Umzug ein
Zuhause hat und kein Teil das Turn-Limit sprengt.

| Task | Inhalt | Repo |
|---|---|---|
| **T1a · Trennlinie ziehen** | D3 vollständig in TCH umsetzen, verhaltensneutral: Erweiterungspunkte, Zuordnungstabelle `docs/factory/OWNERSHIP.md`, TCH-Spezifika an projekteigene Orte, Factory-ADRs nach `docs/factory/adr/`, Tests aufteilen | TCH |
| **T1b · Herauslösen** | D5, D6, D9: `nothra/dev-factory` per filter-repo, Scan, Ruleset, CI, `v0.6.0` | dev-factory |
| **T2 · Abholen** | D1, D2, D4, D7, D10 + TCH auf `factory.lock` umstellen | beide |
| **T3 · Umziehen** | Issues übertragen, Labels (`factory-pipeline` → dev-factory, `build-pipeline` in TCH), Doku-Verweise, Verweis-Check | beide |

AK-Zuordnung: AK1.5 → T1a; AK1.1–1.4, 1.6–1.8 → T1b; AK2.x → T2; AK3.2/3.3 überwiegend T1a
(Dateien), Verweis-Check T3; übrige AK3.x → T3.

## Alternativen

### A · Verteilung als Git-Submodul
**Pro:** echte Versionierung über Commit-Pointer, keine Kopie. **Contra:** Dateien müssten an fixen
Pfaden (`.claude/commands`, Wurzel-Hooks) liegen, die ein Submodul nicht bedienen kann; jeder Klon,
jeder Worktree (Default von `start-work.sh`), CI und Vercel brauchen rekursiven Checkout;
Änderungs-Gate entfällt nicht, wird aber unsichtbar. **Verworfen.**

### B · `git subtree`
**Pro:** Dateien liegen im Repo, Historie mergbar. **Contra:** Subtree arbeitet auf einem
Unterverzeichnis – unsere Factory ist über Wurzel, `scripts/`, `.claude/`, `.github/`, `docs/`
verteilt; Updates werden Merge-Commits gegen die Rebase-Regel; kein Manifest, kein natürliches
Gate. **Verworfen.**

### C · Claude-Code-Plugin
**Pro:** Skills/Agenten/Hooks zentral installierbar, kein Kopieren. **Contra:** Bash-Gates,
Git-Hooks und CI-Workflows müssen trotzdem ins Repo; zwei Verteilwege statt einem. Laut Spec out of
scope; als spätere Ergänzung für den Skill-Teil denkbar.

### D · Push-Modell (Factory-Release erstellt PRs in Konsumenten)
**Pro:** sofortige Updates. **Contra:** Factory braucht Konsumentenliste und Schreib-Token für
fremde Repos – größere Angriffsfläche, Kopplung in die falsche Richtung. **Verworfen** zugunsten
D2 (Pull).

### E · Marker-Blöcke in Mischdateien (`# >>> factory` … `# <<< factory`)
**Pro:** keine neuen Dateien. **Contra:** halb-übernommene Dateien machen das Integritäts-Gate
unscharf (Hash nur über Blöcke), Merge-Logik fehleranfällig, für JSON (`settings.json`) nicht
möglich. **Verworfen** zugunsten D3 (Import bzw. Zusammensetzen).

### F · ADRs neu nummerieren (Factory ab 001)
**Pro:** saubere Reihe. **Contra:** hunderte Verweise in Code, Kommentaren, Lessons und Historie
brechen oder müssten umgeschrieben werden; Commit-Messages bleiben ohnehin alt. **Verworfen**
zugunsten D8.

### G · Factory-Repo privat (ursprüngliche Spec-Entscheidung)
**Pro:** nicht öffentlich. **Contra:** Inhalt ist via TCH bereits öffentlich; im Free-Plan kein
serverseitiger `main`-Schutz (AK1.6 verfehlt); Lese-Token in jedem Projekt; begrenzte
Actions-Minuten. **Verworfen** mit dem Entwickler.

## Begründung

Committete Kopie + Manifest ist das Einfachste, das alle harten Anforderungen erfüllt: Projekte
bleiben offline voll arbeitsfähig (AK2.8), jede Factory-Änderung ist im PR-Diff sichtbar und läuft
durch dieselben Gates (AK2.4), und das Manifest beantwortet die Besitzfrage maschinenlesbar – für
das Gate (D4) ebenso wie für die Fund-Zuordnung (D7). Die Regel „keine Mischdateien" ist der Preis
dafür, dass das Gate scharf und einfach bleibt. Das Pull-Modell hält die Factory frei von Wissen
über ihre Konsumenten. Die Trennlinie zuerst im bestehenden Repo zu ziehen (T1a) macht den
riskantesten Teil verhaltensneutral und mit der vorhandenen Testsuite prüfbar, bevor irgendetwas
das Repo verlässt.

## Konsequenzen

- **Neue Artefakte:** `factory.lock`, `scripts/factory-sync.sh`, `factory-update.yml`,
  `factory-integrity-check.sh` + CI-Job, `create_factory_issue`, `docs/factory/FACTORY.md`,
  `docs/factory/OWNERSHIP.md`, Fragment-Dateien, `scripts/project/`, `docs/project/lessons/`,
  `docs/factory/adr/`, `templates/` (nur dev-factory).
- **Secret `FACTORY_SYNC_TOKEN`** in jedem Konsumenten-Repo, mit Ablaufdatum → Rotation ist Betriebsaufgabe.
- **Required Checks** in TCH: `factory-integrity` kommt hinzu (ADR-029 nachtragen).
- **Factory-Änderungen aus TCH heraus sind nicht mehr möglich** – auch kleine Fixes gehen über
  `dev-factory` + Release + Update-PR. Das ist gewollt (AK2.5), verlängert aber den Weg; Mitigation:
  PATCH-Releases sind billig.
- **ADR-009** wird um `commands.*`, `labels.*`, `upstream.repo` erweitert (Nachtrag, kein Widerspruch).
- **ADR-018** um `create_factory_issue` (Nachtrag). **ADR-042** (Hook-Installation): Hooks kommen
  weiter aus `install-hooks.sh`, das jetzt übernommen ist.
- **ADR-043:** die Schwelle bleibt; nur das Ziel der Ablage ändert sich für Factory-Funde.
- **Öffentlichkeit:** Alles im Factory-Repo ist öffentlich – D5-Scan ist Pflicht vor dem ersten Push.
- **Reversibilität:** T1a ist voll reversibel; ab T1b-Push ist die öffentliche Historie nicht mehr
  zurückholbar (nur das Repo löschbar).

## Implementierungs-Hinweise

- Reihenfolge strikt T1a → T1b → T2 → T3; T2 erst, wenn `v0.6.0` veröffentlicht ist.
- T1a: Zuordnungstabelle zuerst (vollständig, AK1.5) und per Test gegen `git ls-files` prüfen, dann
  verschieben – jede Datei genau eine Zeile. Factory-ADRs per `git mv`, damit `--follow` greift.
- T1a: `AKE.1` belegen – `run-tests.sh` + App-Gates vor und nach grün, Required-Check-Namen unverändert.
- T1b: Allowlist für filter-repo aus `OWNERSHIP.md` generieren, nicht von Hand. Scan-Ergebnis im
  T1b-PR dokumentieren. Erster Push auf leeres Repo nur mit `--no-verify` (wie TCH-Bootstrap), danach
  sofort Ruleset.
- T2: `factory-sync.sh` atomar (Temp-Dir, dann `mv`), Bash 3.2-kompatibel (macOS), Dateihashes per
  `shasum -a 256` (BSD + GNU).
- Lessons aus dem Index beachten: `db.transaction` irrelevant; relevant sind `factory-workflow.md`
  (Reihenfolge-/Präsenz-Guards an der echten Aufrufzeile, Fixture-Identität bei `git commit`,
  explizite `-c user.email` in Pipeline-Commits) und `bash-gotchas.md`.
