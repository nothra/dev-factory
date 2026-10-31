# ADR 063: Factory in eigenes Repo – versionierte Übernahme per Manifest

## Status
Accepted (2026-10-19, mit T1a-1, nothra/tch-gastro-services#426)

## Date
2026-10-19

## Kontext

Spec [nothra/tch-gastro-services#424](https://github.com/nothra/tch-gastro-services/blob/main/docs/specs/spec-424-factory-in-eigenes-repo-auslagern.md) verlangt, die Development
Factory aus dem Ursprungs-Repo in ein eigenes Repo auszulagern und als wiederverwendbares, versioniertes
Werkzeug zu betreiben. Bereits entschieden (Spec, Entscheidungstabelle): Historie wird mitgenommen,
neue Versionen kommen als automatischer Update-PR, lokale Änderungen an übernommenen Dateien sind
verboten, Factory-Funde aus Projekt-Arbeit gehen direkt ins Factory-Repo, die Factory entwickelt
sich mit der eigenen Pipeline, `factory-pipeline` wandert ins Factory-Repo und das Ursprungs-Projekt bekommt
`build-pipeline`.

**Befund der Bestandsaufnahme (2026-10-19):**

- **Sichtbarkeit:** `nothra/tch-gastro-services` ist inzwischen **öffentlich** (Ruleset
  `protect-main` aktiv, ADR-029); der Account läuft im **Free-Plan**. Ein **privates** Factory-Repo
  hätte im Free-Plan **keinen** serverseitigen `main`-Schutz (Rulesets für private Repos gesperrt) –
  AK1.6 wäre nicht erfüllbar – und bräuchte in jedem Projekt einen Lese-Token. Der Factory-Inhalt
  ist über das öffentliche Ursprungs-Repo ohnehin schon öffentlich. **Entscheidung mit dem Entwickler
  (2026-10-19): Factory-Repo öffentlich**, Name **`nothra/dev-factory`** (korrigiert die
  Spec-Entscheidung „privat").
- **Mischdateien:** `CLAUDE.md` (Factory-Regeln + Ursprungs-Regeln wie Routen-Doku), `.claude/settings.json`
  (Factory-Hooks/-Permissions + `Edit(app/**)` u. ä.), `.gitignore`,
  `.github/workflows/factory-ci.yml` (Factory-Jobs + pnpm-`lint`/`test`), `pre-push.sh` (ruft
  hart `routes-doc-check.sh`), Skill-/Agent-/Guideline-Texte mit pnpm-/DB-Hinweisen
  (`implement.md`, `coding-agent.md`, `review-agent.md`, `git-workflow.md`, `testing-standards.md`,
  `bash-gotchas.md`), die Label-Tabelle in `git-workflow.md`, der Lessons-Index in
  `PROJECT-CONTEXT.md`.
- **Ursprungs-spezifische Factory-nahe Dateien:** das Datenbank-Reset-Skript für die Integrationsumgebung, `scripts/deploy-freeze*.sh`,
  `.github/workflows/deploy-gate.yml`, `deploy-freeze-release.yml`, `scripts/checks/routes-doc-check.sh`,
  Lessons `frontend-react.md`, `db-drizzle.md`, `next-auth.md`, Teile von `build-tooling.md`/`testing.md`.
- **Gemischte Self-Test-Suite:** `scripts/checks/tests/run-tests.sh` (~8 600 Zeilen) testet auch die
  Ursprungs-spezifischen Skripte.
- **ADR-Verweise:** übernommene Dateien zitieren Factory-ADRs hundertfach (z. B. ADR-019 49×,
  ADR-018 33×). Die gemeinsame Nummernfolge enthält Dubletten (027, 032, 040 – nothra/tch-gastro-services#321).
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
verbraucht keine Claude-Tokens; der stillgelegte `factory-poll`-Schedule (nothra/tch-gastro-services#284) ist davon unberührt.

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
| Gate-Kommandos (`pnpm lint` …) | Werte aus `factory.config.yml` → `commands.{lint,test,typecheck,format,coverage}` (ADR-009-Schichtung); `factory.defaults.yml` liefert **keinen** pnpm-Default, fehlender Wert = klarer Fehler. Das Ursprungs-Projekt setzt seine heutigen Werte → Verhalten unverändert (AKE.1). |
| Label-Tabelle | übernommene Art-/Aspekt-Labels in `factory.defaults.yml` → `labels.aspects`; projekteigene in `factory.config.yml` → `labels.aspects_extra` (Ursprungs-Projekt: `build-pipeline`), Bedeutung/Zuordnungsregel in `PROJECT-CONTEXT.md` (AK3.9). `start-work.sh` und Seam validieren gegen die Vereinigung. `git-workflow.md` beschreibt nur das Schema. |
| Skill-/Agent-/Guideline-Texte mit pnpm/DB/E2E-Details | generisch formulieren, Projekt-Details in `PROJECT-CONTEXT.md` (neuer Abschnitt „Lokale Umgebung & Oberflächentests"), auf den die Texte verweisen |
| Lessons | generische bleiben in `docs/factory/lessons/` (übernommen); Ursprungs-spezifische nach `docs/project/lessons/` (projekteigen). `PROJECT-CONTEXT.md` indiziert beide. |
| Ursprungs-only-Skripte/Workflows (Datenbank-Reset-Skript, `deploy-freeze*`, `deploy-gate.yml` …) | projekteigen; Skripte nach `scripts/project/`; ihre Self-Tests nach `scripts/project/tests/` |

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

Das Factory-Repo entsteht aus einem **frischen Klon** vom Ursprungs-Repo per `git filter-repo` mit einer
**Allowlist** genau der übernommenen Pfade (aus der Zuordnungstabelle in T1a, AK1.5); dadurch
fehlen App-Code (`app/`, `db/`, `lib/` …), Tasks, Specs und Ursprungs-Doku in der gesamten Historie
(AK1.4). Vor dem ersten Push: Secret-Scan über **die ganze umgeschriebene Historie** (`gitleaks`)
plus Grep auf Ursprungs-Domänenbegriffe und E-Mail-Muster in Datei-Inhalten (AK1.3/1.4, F5) – das Repo
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
Verweis-Check prüft beides (AK3.2, F6). Die Dubletten aus nothra/tch-gastro-services#321 werden je Seite in nothra/tch-gastro-services#321 gelöst
(zieht als Factory-Issue mit um, soweit Factory-ADRs betroffen sind).

### D9 · Factory-Repo nutzt sich selbst

`nothra/dev-factory` ist zugleich Quelle und Konsument seiner selbst: eigene `factory.config.yml`
(`commands.lint` = ShellCheck über `scripts/`, `commands.test` = `run-tests.sh`), eigene
`PROJECT-CONTEXT.md`, eigene `docs/specs/`, `tasks/`, Ruleset `protect-main`, CI mit
`factory-self-test`. `start-work.sh` und die Skills laufen dort unverändert (AK1.7). Die
Issue-Nummerierung beginnt dort neu; alte Ursprungs-Tasks/-Specs bleiben als Archiv im Ursprungs-Repo.

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
| **T1a · Trennlinie ziehen** | D3 vollständig im Ursprungs-Repo umsetzen, verhaltensneutral: Erweiterungspunkte, Zuordnungstabelle `docs/factory/OWNERSHIP.md`, Ursprungs-Spezifika an projekteigene Orte, Factory-ADRs nach `docs/factory/adr/`, Tests aufteilen | Ursprungs-Repo |
| **T1b · Herauslösen** | D5, D6, D9: `nothra/dev-factory` per filter-repo, Scan, Ruleset, CI, `v0.6.0` | dev-factory |
| **T2 · Abholen** | D1, D2, D4, D7, D10 + das Ursprungs-Projekt auf `factory.lock` umstellen | beide |
| **T3 · Umziehen** | Issues übertragen, Labels (`factory-pipeline` → dev-factory, `build-pipeline` im Ursprungs-Repo), Doku-Verweise, Verweis-Check | beide |

AK-Zuordnung: AK1.5 → T1a; AK1.1–1.4, 1.6–1.8 → T1b; AK2.x → T2; AK3.2/3.3 überwiegend T1a
(Dateien), Verweis-Check T3; übrige AK3.x → T3.

## Alternativen

### A · Verteilung als Git-Submodul
**Pro:** echte Versionierung über Commit-Pointer, keine Kopie. **Contra:** Dateien müssten an fixen
Pfaden (`.claude/commands`, Wurzel-Hooks) liegen, die ein Submodul nicht bedienen kann; jeder Klon,
jeder Worktree (Default von `start-work.sh`), CI und der Hosting-Build brauchen rekursiven Checkout;
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
**Pro:** nicht öffentlich. **Contra:** Inhalt ist über das Ursprungs-Repo bereits öffentlich; im Free-Plan kein
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
- **Required Checks** im Ursprungs-Repo: `factory-integrity` kommt hinzu (ADR-029 nachtragen).
- **Factory-Änderungen aus dem Ursprungs-Repo heraus sind nicht mehr möglich** – auch kleine Fixes gehen über
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
  T1b-PR dokumentieren. Erster Push auf leeres Repo nur mit `--no-verify` (wie Ursprungs-Bootstrap), danach
  sofort Ruleset.
- T2: `factory-sync.sh` atomar (Temp-Dir, dann `mv`), Bash 3.2-kompatibel (macOS), Dateihashes per
  `shasum -a 256` (BSD + GNU).
- Lessons aus dem Index beachten: `db.transaction` irrelevant; relevant sind `factory-workflow.md`
  (Reihenfolge-/Präsenz-Guards an der echten Aufrufzeile, Fixture-Identität bei `git commit`,
  explizite `-c user.email` in Pipeline-Commits) und `bash-gotchas.md`.

## Nachtrag 2026-10-19 · Detailentscheidungen aus T1a (Spec nothra/tch-gastro-services#426, Q1–Q6)

Entschieden mit dem Entwickler; sie liegen **innerhalb** von D3/D8/D11 und ändern keine
Grundsatzentscheidung.

- **Q1 · Schnitt von T1a:** T1a ist mit 54 Akzeptanzkriterien zu groß für einen Pipeline-Lauf
  (Turn-Limit-Schwelle > 25 AK / > 40 Dateien) und wird in drei nacheinander laufende PRs geteilt:
  **T1a-1 · Dokumente sortieren (nothra/tch-gastro-services#426)** – Zuordnungstabelle, ADRs, Lessons, Kleinfunde;
  **T1a-2 · Mischdateien & Gates (nothra/tch-gastro-services#431)** – `CLAUDE.md`/`FACTORY.md`, zusammengesetzte Dateien,
  Workflows, Erweiterungspunkte, `commands.*`, Labels; **T1a-3 · Projekt-Orte & Texte (nothra/tch-gastro-services#432)** –
  Ursprungs-Skripte und -Tests nach `scripts/project/`, Factory-Texte generisch. Jeder PR ist für sich
  verhaltensneutral und hält die Zuordnungstabelle aktuell.
- **Q2 · Zusammensetzen vor T2:** `scripts/factory-sync.sh` entsteht in T1a-2 mit **nur** dem Modus
  `--compose` (der in D3 genannte Aufruf); T2 ergänzt die übrigen Modi.
- **Q3 · ADR-Zuordnung:** **Factory** (`docs/factory/adr/`): 001–013, 018, 019, 029, 030, 037, 038,
  040 (beide), 041, 042, 043, 045, 047, 049, 051, 063. **Projekt** (`docs/adr/`): alle übrigen.
  Grenzfälle: ADR-029 (Ruleset) ist ein generisches Factory-Prinzip mit Ursprungs-Check-Namen → Factory;
  ADR-063 regelt die Verteilung → Factory; ADR-015/017/032 (Deploy-Gate, Deploy-Freeze) → Projekt.
  Nummern und Dateinamen bleiben, auch die Dubletten (nothra/tch-gastro-services#321 löst sie später je Seite).
- **Q4 · Worktree-Vorbereitung:** die Ursprungs-spezifischen Schritte von `start-work.sh` (`pnpm install`,
  Hinweis „vor dem ersten E2E-Lauf seeden") kommen aus optionalen Schlüsseln `commands.install` und
  `start_work.hint` in `factory.config.yml` (gleiches Muster wie `commands.*`); ohne Eintrag entfällt
  der Schritt still.
- **Q5 · Label-Validierung:** T1a verlegt nur die **Datenquelle** (`labels.aspects` /
  `labels.aspects_extra`); das Verhalten bleibt unverändert (heute fail-open: ein unbekanntes Label
  fällt weg). Eine harte Ablehnung gegen die Vereinigung kommt frühestens in T3 mit dem Label-Wechsel
  – D3 („validieren gegen die Vereinigung") gilt bis dahin als Zielbild.
- **Q6 · Kleinfunde:** `docs/factory/kleinfunde.md` wird nach betroffener Datei geteilt: Einträge zu
  Projekt-Dateien liegen in `docs/project/kleinfunde.md`, Einträge zu Factory-Dateien bleiben. Skills
  nennen beide Orte und die Zuordnungsregel („Datei laut `docs/factory/OWNERSHIP.md`"). Ab T2 gehen
  Factory-Kleinfunde als Issue ins Factory-Repo (D7).
- **Zuordnungstabelle:** `docs/factory/OWNERSHIP.md` ist maschinenlesbar (Zeilen
  `| seite | `muster` | begründung |`); `scripts/checks/ownership-check.sh` ist ihr einziger Parser und
  erzeugt über `--list factory` die `git filter-repo`-Allowlist für T1b (D5). Der Check läuft im
  lokalen `pre-push.sh` und in der Self-Test-Suite (Required Check `factory-self-test`).

## Nachtrag 2026-10-23 · Detailentscheidungen aus T1b (Spec nothra/tch-gastro-services#427, Q1–Q6)

Entschieden mit dem Entwickler; sie verfeinern D5/D6/D9/D11. Drei Punkte **weichen** vom
ursprünglichen Wortlaut ab und sind als solche markiert (D5-Begriffs-Grep vor dem Push,
D6-Versionsangabe, D9-Lint).

- **Q6 · Schnitt von T1b:** T1b wird in zwei nacheinander laufende Tasks geteilt.
  **T1b-1 (nothra/tch-gastro-services#427, nur Ursprungs-Repo):** dieser Nachtrag, das Herauslöse-Werkzeug mit Tests und ein Probelauf
  mit Scan-Bericht – **kein** Push. **T1b-2 (nothra/tch-gastro-services#436, Klammer-Task im Ursprungs-Repo, Arbeit im Factory-Repo):**
  Herauslösen aus dem **gemergten** `main` des Ursprungs-Repos, Scan, Freigabe, Bootstrap-Push, Ruleset,
  Bootstrap- und Bereinigungs-PR, Probe, `v0.6.0`. Grund: Der Nachtrag ist eine Factory-Datei und
  muss vor dem Herauslösen auf `main` des Ursprungs-Repos liegen, die Task-Datei muss vor dem Merge abgeschlossen
  sein (Guardrail aus nothra/tch-gastro-services#63), und T1b hätte mit 24 AK die Turn-Limit-Schwelle erreicht.
- **Q2 · Werkzeug:** `scripts/project/factory-extract.sh` – **projekteigen im Ursprungs-Repo** (einmaliges
  Werkzeug, kennt den Ursprungs-Slug, wandert nicht mit). Unterbefehle:
  - `paths` – Ausgabe von `ownership-check.sh --list factory` plus deren Altpfade aus
    `git log --follow --name-only --format=`, `LC_ALL=C` sortiert, eindeutig (AK A1).
  - `run <ziel>` – `git clone --no-local` von `main` des Ursprungs-Repos nach `<ziel>`, dort
    `git filter-repo --paths-from-file <paths> --replace-message <regeln>`; der Arbeitsklon und
    sein `origin` bleiben unberührt (AK X2). Die Message-Regeln sind die Umschreibregel plus die
    Trailer-Regel (s. u.).
  - `verify <ziel>` – A2 (alle Pfade aller Commits ⊆ Liste, keiner in einem App-/Ursprungs-Bereich),
    A3 (`--follow` jeder Factory-Datei reicht im Ziel über dieselben Namen wie im Ursprungs-Repo),
    A4 (kein unqualifiziertes `#<nr>` in Messages), A5 (Autor/Datum gegen das Ursprungs-Repo, über die commit-map
    von filter-repo).
  - `scan <ziel>` – `gitleaks` über alle Commits **und** über alle Commit-/Tag-Messages
    (`gitleaks stdin`), E-Mail-Muster über alle Blobs (`git rev-list --all --objects`) **und** alle
    Commit-/Tag-Messages gegen die Erlaubt-Liste `scripts/project/factory-extract.allow`; schreibt
    den Scan-Bericht (Markdown) nach stdout, mit getrennten Zeilen für Historie und Messages, der
    geltenden Erlaubt-Liste samt Pfad, per Umgebung überschriebenen Listen und dem Restrisiko des
    E-Mail-Musters (ASCII-Adressen; Umlaut-Domains, verschleierte Formen, komprimierte Dateien
    nicht). Ein Muster der Erlaubt-Liste braucht eine feste Top-Level-Domain (`*`, `*@*`,
    `*@example.*` brechen ab). Falsch-Positive von gitleaks stehen in
    `scripts/project/factory-extract.gitleaksignore` (je Eintrag ein gitleaks-Fingerprint
    `<commit>:<datei>:<regel>:<zeile>` mit Begründungskommentar darüber, übergeben per
    `--gitleaks-ignore-path`); ein Eintrag ohne Begründung oder ohne Commit-Bezug bricht den Scan
    ab, und der Bericht listet jeden ausgenommenen Fingerprint mit seiner Begründung (AK B1).
    gitleaks läuft mit der gepinnten Konfiguration `scripts/project/factory-extract.gitleaks.toml`
    (Standardregeln, keine Ausnahmen), ohne `GITLEAKS_CONFIG` der Umgebung, in einem leeren
    Arbeitsverzeichnis und gegen einen Spiegel-Klon (`--mirror`, alle Refs) **ohne Arbeitsbaum** –
    sonst könnten eine `.gitleaks.toml`/`.gitleaksignore` im herausgelösten Repo oder im
    Aufrufverzeichnis oder die Umgebung den Secret-Scan still abschalten, und Commits außerhalb von
    Branches/Tags blieben ungeprüft. Jedes Inline-`gitleaks:allow` in Dateien oder Messages macht
    den Scan rot (es würde Funde ohne Begründung unterdrücken); ein Platzhalter im Domain-Teil der
    Erlaubt-Liste ist nur unter reservierten Test-Domains zulässig (`*@*.example`, nicht `*@*.de`);
    ein gitleaks ohne Versionsangabe bricht ab, und per Umgebung ersetzte Werkzeuge nennt der
    Bericht (Security-Review und Re-Review nothra/tch-gastro-services#427).
  - `qualify <ziel>` – schreibt Ursprungs-Nummern im **Inhalt** des Arbeitsbaums aus (C3; in T1b-2
    im Bereinigungs-PR aufgerufen): Markdown vollständig, Shell-Skripte **nur in Kommentarzeilen**
    (erstes Nicht-Leerzeichen `#`, nicht `#!`), damit Test-Fixtures wie `"Closes #42"` unverändert
    bleiben. Andere Dateitypen (z. B. YAML-Kommentare) fasst `qualify` nicht an. Was der Regel
    entgeht oder was sie fälschlich trifft (Abschnittsnummern wie `ADR-009 #7`), findet die
    Durchsicht im PR-Diff.

  `git-filter-repo` und `gitleaks` sind Entwickler-Werkzeuge (lokal, kein CI); fehlt eines, bricht
  das Skript fail-closed mit Installationshinweis ab; ihre Versionen stehen im Scan-Bericht.
- **Umschreibregel (A4/C3):** genau eine Regel in `scripts/project/factory-extract.rules`, von
  `run` (Messages) und `qualify` (Inhalt) gemeinsam gelesen: unqualifiziertes `#<ziffern>` (ein
  bis fünf Ziffern) als ganzes Wort, dem kein Wortzeichen, `/`, `.`, `-` oder `&` und nicht `](`
  vorausgeht → `nothra/tch-gastro-services#<ziffern>`. Bereits qualifizierte Verweise
  (`owner/repo#n`), Farbcodes mit Buchstaben (`#1e40af`) oder mit sechs Ziffern (`#333333`),
  HTML-Entities wie `&#8212;` und Markdown-Sprunganker wie `](#12-abschnitt)` bleiben; kürzere
  reine Ziffern-Farbcodes (`nothra/tch-gastro-services#000`) trifft die Regel – im Inhalt fängt die Durchsicht im PR-Diff
  sie ab; in den Commit-Messages gibt es keinen PR-Diff, dort kommen sie heute nicht vor.
  **Konvention ab jetzt:** Im Factory-Repo steht vor jeder Ursprungs-Nummer der Repo-Slug;
  unqualifiziertes `#<nr>` meint das Factory-Repo selbst.
- **Trailer-Regel (Entscheidung des Entwicklers, Security-Review nothra/tch-gastro-services#427):** `Co-authored-by`-Zeilen
  in Commit-Messages, deren Adresse keine noreply-Adresse ist (Firmen- oder Privatadresse,
  Personalnummer), fallen beim Herauslösen ersatzlos weg; noreply-Trailer (Claude, GitHub) bleiben.
  Die Regel steht in `scripts/project/factory-extract.trailers` und gilt nur für Messages (`run`),
  nicht für Datei-Inhalte (`qualify`). Commit-Autor und -Committer bleiben unverändert (D5, AK A5);
  B2 Messages prüft das Ergebnis.
- **Altpfade, die im Ursprungs-Repo noch leben:** `CLAUDE.md` und `.claude/settings.json` sind Altpfade von
  Factory-Dateien (`FACTORY.md`, `settings.factory.json`), existieren im Ursprungs-Repo aber weiter als
  Projekt-Dateien. Sie kommen daher mit ihrer Ursprungs-Fassung ins Factory-Repo; der Bootstrap-PR ersetzt
  sie durch die eigenen Fassungen des Factory-Repos (dessen `CLAUDE.md`, zusammengesetzte
  `settings.json` aus eigenen Projekt-Fragmenten). Ihr alter Inhalt bleibt in der Historie – er ist
  über das Ursprungs-Repo ohnehin öffentlich. `.gitignore` ist laut Probelauf **kein** `--follow`-Altpfad von
  `gitignore.factory` (Git erkennt die Aufteilung nicht als Umbenennung) und kommt nicht mit; der
  Bootstrap-PR setzt sie aus den eigenen Fragmenten neu zusammen.
- **Q5 · Reihenfolge im Factory-Repo:** (1) Bootstrap-Push = herausgelöste Historie, Inhalt
  unverändert, nur Messages umgeschrieben – nichts, was nicht schon über das Ursprungs-Repo öffentlich ist; erster
  Push mit `--no-verify`. (2) **Sofort** Ruleset `protect-main` (kein Bypass, PR-Pflicht, Squash,
  kein Force-Push; Required Checks `pr-closes-issue`, `config-validation`, `factory-self-test`,
  `lint`). (3) Bootstrap-PR (Factory-Issue #1): eigene Anpassungsstellen, `ci.yml`, Labels.
  (4) Bereinigungs-PR: `qualify` + Begriffs-Bereinigung. (5) Wegwerf-Probe. (6) Release.
  Bis (4) gemergt ist, stehen Ursprungs-Begriffe auf `main`; vor dem Release sind sie weg (AK C1).
  **Abweichung von D5:** Der dort verlangte Grep auf Ursprungs-Domänenbegriffe **vor** dem ersten Push
  entfällt; vor dem Push laufen nur Secret- und E-Mail-Scan (`scan`). Grund: Der Bootstrap-Push
  enthält keinen Inhalt, der nicht schon über das öffentliche Ursprungs-Repo öffentlich ist – Ursprungs-Begriffe
  sind dort kein Geheimnis, sondern nur im Factory-Repo fehl am Platz; sie verschwinden im
  Bereinigungs-PR (4) unter CI und Ruleset, und C1 prüft das vor dem Release.
- **Q4 · Besitz im Factory-Repo:** dort eine eigene `docs/factory/OWNERSHIP.md` im selben Format.
  Seite `factory` = ausgeliefert (heute die 111 Dateien der Ursprungs-Liste); Seite `project` = gehört
  dem Factory-Repo selbst: `CLAUDE.md`, `README.md`, `CHANGELOG.md`, `factory.config.yml`,
  `docs/factory/PROJECT-CONTEXT.md`, `.claude/settings.project.json`, `.gitignore.project`, die
  zusammengesetzten `.claude/settings.json`/`.gitignore`, `.github/workflows/ci.yml`,
  `.github/workflows/release.yml`, `docs/specs/**`, `tasks/**` und ab T2 `templates/**`.
  Self-Tests, die Ursprungs-Zustände prüfen (Dateizahlen, Fixtures der T1a-Aufteilung), werden auf das
  Factory-Repo umgestellt, nicht übersprungen.
- **Q1 · Release-Manifest (Vertrag für T2):** Asset `factory-release.json` je Release:
  `{"schema":1,"repo":"nothra/dev-factory","version":"vX.Y.Z","commit":"<40 hex>","files":[{"path":"…","sha256":"…"}]}`,
  `files` = Seite `factory` laut `OWNERSHIP.md` am Tag, nach `path` sortiert (`LC_ALL=C`), Hash per
  `shasum -a 256` über den Blob am Tag (`git show <tag>:<pfad>`, unabhängig vom Arbeitsbaum).
  Erzeugt von `scripts/factory-release-manifest.sh <ref>` – **ausgeliefert**, weil T2
  (`factory-sync.sh`, Integritäts-Gate) dieselbe Hash-Logik braucht.
- **Q1 · Ablauf einer Version (Abweichung von D6 „Versionsangabe aus dem Tag erzeugt"):** Ein Bot
  kann nach dem Taggen nicht auf `main` schreiben (Ruleset). Deshalb: **Release-PR** setzt die
  Versionszeile in `FACTORY.md` und den `CHANGELOG.md`-Abschnitt (Text per `/release-notes`) →
  Merge → Mensch setzt den Tag auf `main` → Workflow `release.yml` (nur Factory-Repo, `push: tags
  v*`) prüft fail-closed „Version in `FACTORY.md` == Tag" und „`CHANGELOG.md` hat einen Abschnitt
  zum Tag", erzeugt das Manifest und legt das GitHub Release an (Notes = CHANGELOG-Abschnitt,
  Asset = Manifest). Passt etwas nicht, entsteht kein Release; der Tag wird gelöscht und neu gesetzt.
- **Q3 · Lint im Factory-Repo (Abweichung von D9 „ShellCheck"):** vorerst `commands.lint` =
  `bash -n` über alle getrackten `*.sh`, CI-Job `lint` in `ci.yml` des Factory-Repos. ShellCheck
  folgt als Issue im Factory-Repo, wenn der Fundbestand bekannt ist.
- **Q3 · Bereinigung auch von ADRs und Lessons:** Im Factory-Repo werden ADRs und Lessons sprachlich
  vom Ursprungs-Repo gelöst (Wortlaut und Beispiele, keine Entscheidung, keine Regel). Das ist die einzige
  erlaubte Änderung an angenommenen ADRs; erlaubte Rest-Treffer sind qualifizierte
  Herkunftsverweise und der Herkunftshinweis in `README.md`/`CHANGELOG.md` (AK C1).
- **Tests (TDD) für T1b-1** in `scripts/project/tests/`: `paths` gegen ein Fixture-Repo mit
  Umbenennung; die Umschreibregel gegen Beispiel-Messages und -Zeilen (inkl. Gegenbeispiele:
  qualifiziert, Farbcode, `#!`, String-Fixture); `verify`/`scan`-Entscheidungslogik gegen
  präparierte Fixture-Repos mit `gitleaks`-Stub im `PATH` (Messung brechen, nicht nur Input – Lesson
  aus nothra/tch-gastro-services#319). `git filter-repo` selbst läuft in keinem Test und in keiner CI.

## Nachtrag 2026-10-24 · Konsumenten-Vertrag (Verweis auf ADR-064)

Die Zuordnungstabelle `docs/factory/OWNERSHIP.md` (Nachtrag zu T1a) gehört seit ADR-064 D5 dem Repo (Seite `project`) und ist nicht mehr
Teil des Release-Manifests. Ein einbindendes Projekt bestimmt die Seite `factory` über seinen `factory.lock` (Pfadmenge des Release-Manifests);
die Tabelle gilt nur im Factory-Repo selbst. Die Prüfungen gegen die Tabelle (Aussage zu `factory-self-test` im Nachtrag zu T1a) laufen seit ADR-064 D6 zum Teil in `project-self-test`; dessen Eintrag in das Ruleset `protect-main` ist am 2026-10-25 erfolgt (Issue #26); die Required-Check-Liste in T1b Q5 nennt den Stand vom Bootstrap (`pr-closes-issue`, `config-validation`, `factory-self-test`, `lint`) und ist um `project-self-test` zu lesen. Details und Konsequenzen: ADR-064.

## Nachtrag 2026-10-25 · Abholen und Integritäts-Gate (Spec #23, Q-23.1–Q-23.3)

Aus `/architecture` zu #23 (T2a-2); gilt als angenommen mit der Umsetzung in #23. Verfeinert D1, D3 und D4.
**E7 ersetzt** den Satz in D3, das Manifest führe die zusammengesetzten Dateien als `composed` mit
Fragment-Hashes; sonst kein Widerspruch zu D1–D4 oder ADR-064.

- **E1 · Transport (Q-23.1):** Dateien per `git clone --depth 1 --branch <tag>` des öffentlichen
  Factory-Repos in ein Temp-Verzeichnis, das Manifest per `curl -fsSL` vom Release-Asset
  (`…/releases/download/<tag>/factory-release.json`). Beides ohne Token. Für Tests umlenkbar über
  `FACTORY_UPSTREAM_GIT_URL` und `FACTORY_RELEASE_BASE_URL` (ein lokales Fixture-Repo mit Tags,
  Manifeste per `file://`); sonst aus `upstream.repo` gebildet (E2).
  *Alternativen:* Tarball per `curl` (kein Abgleich mit dem Commit-SHA des Manifests möglich, F-23.1);
  `gh release download`/`gh api` (braucht eine `gh`-Anmeldung, D1 verlangt „ohne Token"); einzelne
  Dateien über `raw.githubusercontent.com` (über 100 Abrufe je Version, kein konsistenter Stand eines
  Tags). Mit `git` prüft die Abholung zusätzlich, dass der Tag auf `commit` aus dem Manifest zeigt.
- **E2 · Quell-Repo:** Schlüssel `upstream.repo` in `factory.defaults.yml` (Default
  `nothra/dev-factory`), überschreibbar in `factory.config.yml` – derselbe Schlüssel, den D7 für die
  Fund-Ablage vorsieht; er entsteht schon jetzt. Das Feld `repo` im Lock ist **nie** die Quelle, es
  muss `upstream.repo` gleichen (sonst Abbruch, F-23.1). Grund: Der Lock ist Repo-Inhalt; ein PR, der
  ihn auf ein anderes Repo mit passendem Manifest zeigen ließe, würde sonst die CI-Stufe bestehen.
- **E3 · Aufruf:** `factory-sync.sh <version> [--adopt]`; `--compose [--check]` bleibt unverändert.
  `<version>` muss `^v[0-9]+\.[0-9]+\.[0-9]+$` erfüllen, geprüft vor jedem Netzzugriff (kein Wert, der
  `git` als Option erreicht). `--adopt` ist der Schalter der Erstabholung (Spec #23 AK2.2e) und nur
  ohne `factory.lock` zulässig; mit Lock wird er abgelehnt, damit F2 nicht umgehbar ist.
- **E4 · Ablauf der Abholung in zwei Phasen** (F4, Spec #23 AK2.2b):
  1. *Prüfen, nichts im Repo geschrieben:* (a) Vorbedingung im Arbeitsbaum, offline und zuerst: mit
     Lock muss die lokale Gate-Stufe (E8) grün sein, sonst Abbruch mit Dateiliste (F2); ohne Lock
     werden Dateien an Manifest-Pfaden mit abweichendem Inhalt gesammelt, ohne `--adopt` Abbruch mit
     Liste. (b) Manifest holen und prüfen: gültiges JSON, `schema` 1, `version` = Tag, `repo` =
     `upstream.repo`, jeder Pfad relativ, ohne `..`, nicht doppelt, keine Anpassungsstelle und kein
     Projektbereich (E6). (c) Tag klonen, `HEAD` = `commit`, jede Datei hat den Manifest-Hash.
     (d) Zusammensetzen in einem Temp-Baum aus dem neuen Factory-Fragment und den aktuellen
     Projekt-Fragmenten (bestehendes `--compose` mit `FACTORY_DIR` auf den Temp-Baum).
  2. *Übernehmen:* Jede Zieldatei, die überschrieben oder gelöscht wird (übernommene Dateien,
     zusammengesetzte Dateien, `factory.lock`), wird vorher in ein Backup kopiert. Dann neue Dateien
     schreiben, entfallene löschen (Pfade des alten Locks, die das Manifest nicht mehr nennt),
     zusammengesetzte Dateien schreiben, **zuletzt** `factory.lock` als Byte-Kopie des Manifests.
     Scheitert ein Schritt, stellt ein `trap` das Backup wieder her und entfernt neu angelegte Dateien.
     Ein harter Abbruch des Prozesses (`SIGKILL`, Stromausfall) während Phase 2 ist nicht abgedeckt;
     Restrisiko, weil Phase 2 nur lokale Kopien ausführt. Die anschließende Prüfung
     `--compose --check` läuft allerdings schon in der **neuen** Fassung des Skripts aus dem Release –
     Code des abgeholten Tags; wer `factory-sync.sh` automatisiert aufruft, tut das deshalb ohne
     Anmeldedaten in der Umgebung (E12). Leere Verzeichnisse nach dem Löschen bleiben
     (Git führt sie nicht).
- **E5 · Gemeinsame Bibliothek `scripts/lib/factory-lock.sh`** (übernommen, gesourct relativ zum
  Skript): Hash per `shasum -a 256` bzw. `sha256sum`, Prüfung von Lock/Manifest (E4 1b), Abruf des
  Manifests (E1), Liste der Projektbereiche (E6). Abholung und Gate nutzen sie; `ownership-check.sh`
  behält seinen Lock-Leser (#22), um dessen Verhalten nicht anzufassen.
- **E6 · Projektbereiche (Q-23.2):** Die Verzeichnisse, in die die Factory nie liefert –
  `scripts/project/`, `docs/project/`, `docs/adr/`, `docs/specs/`, `tasks/` –, stehen als feste Liste
  in `factory-lock.sh`, **nicht** in `customization-points.txt`. Die Abholung lehnt ein Manifest ab, das
  einen Pfad darin oder eine Anpassungsstelle liefern würde. Begriffe: *Anpassungsstelle* = Datei, die
  das Projekt selbst pflegt (ADR-064 D4, wörtliche Liste); *Projektbereich* = Verzeichnis, das nur das
  Projekt füllt. Weitere projekteigene Workflows und App-Code sind dadurch geschützt, dass die Abholung
  nur Pfade aus Manifest und altem Lock berührt.
  *Alternativen:* Präfixe in `customization-points.txt` (kehrt ADR-064 D4 um, dort sind `tasks/**` und
  `docs/specs/**` bewusst keine Anpassungsstellen, und die Teilmengen-Kontrolle der Projekt-Suite prüft
  das); kein Schutz der Verzeichnisse (verlässt sich allein auf die Tabelle im Factory-Repo, ein
  Zuordnungsfehler dort würde in jedem Konsumenten schreiben).
- **E7 · Zusammengesetzte Dateien (Q-23.3):** ADR-064 D1 gilt, der Lock ist das Manifest unverändert
  (Schema 1, ohne `composed`). Die Integrität von `.claude/settings.json` und `.gitignore` prüft die
  lokale Gate-Stufe über `factory-sync.sh --compose --check`. Fragment-Hashes braucht es nicht: Das
  Factory-Fragment ist eine übernommene Datei mit Hash im Lock, das Projekt-Fragment gehört dem
  Projekt.
- **E8 · Gate `scripts/checks/factory-integrity-check.sh`** (übernommen):
  - *Moduswahl:* `factory.lock` vorhanden (`-e` **oder** `-L`) → prüfen; sonst No-op mit Hinweis,
    Exit 0 (Factory-Repo). Ein Lock, der ein toter Symlink ist, gilt als vorhanden und unlesbar
    (Exit 2). Guard in der Projekt-Suite: Das Factory-Repo trackt kein `factory.lock`.
  - *Lokal (Standard, offline):* Lock gültig (E5); jede Lock-Datei existiert, ist eine reguläre Datei
    und hat den eingetragenen Hash; `--compose --check` grün. Abweichung → Exit 1 mit Dateiname und
    Hinweis „Änderung gehört nach `nothra/dev-factory`"; fehlendes `jq`/Hash-Werkzeug, ungültiger Lock →
    Exit 2.
  - *`--ci`:* lokal, dazu das Manifest von `lock.version` aus `upstream.repo` holen und mit dem Lock
    vergleichen (beide mit `jq -S .` normalisiert, ganzes Dokument). Nicht erreichbar, Tag oder Asset
    fehlt → Exit 2 (fail-closed, D4).
  - *Verdrahtung:* fester Check in `pre-commit.sh` und `pre-push.sh` (Factory-Datei, nicht über
    `*.d/`); CI-Job `factory-integrity` in `factory-ci.yml` mit `--ci` (`yq` über
    `scripts/install-yq.sh`, weil `upstream.repo` aus der Config kommt). Im Factory-Repo läuft der Job
    als No-op grün und ist kein Required Check; im Konsumenten trägt ihn T2a-4 ins Ruleset ein.
- **E9 · Tests (offline):** Fixture-Upstream = lokales Git-Repo mit zwei Tags, Manifeste als Dateien
  per `file://`; Stubs für `curl`, `git` und das Hash-Werkzeug im `PATH` brechen die Messung (Lesson aus
  nothra/tch-gastro-services#319). Die neue Bibliothek kommt in alle Test-Scaffoldings (Lesson aus
  nothra/tch-gastro-services#197). Die Compose-Tests der ausgelieferten Suite bauen ihre
  Projekt-Fragmente selbst (Spec #23 AK-28a); die Prüfungen am echten Repo (Fragmente vorhanden,
  committet == Zusammensetzung) wandern in die Projekt-Suite.

**Konsequenzen:** neue Factory-Dateien `scripts/lib/factory-lock.sh` und
`scripts/checks/factory-integrity-check.sh` (je eine Zeile `factory` in `OWNERSHIP.md`); neuer
Config-Schlüssel `upstream.repo`; `curl` und `git` sind für Abholung und CI-Stufe Voraussetzung (lokale
Stufe braucht nur `jq` und ein Hash-Werkzeug). Jeder Commit und Push im Konsumenten hasht alle
Lock-Dateien (heute 114). Gemessen am 2026-10-25 auf macOS: ein `shasum`-Aufruf über alle Dateien
≈ 0,05 s, ein Aufruf je Datei ≈ 1,8 s – E5 hasht deshalb in **einem** Aufruf (Dateiliste per
`xargs -0`), nicht in einer Schleife je Datei.

## Nachtrag 2026-10-30 · Update-Workflow und Update-PR (Spec #24, Q-24.5/Q-24.6)

Aus `/architecture` zu #24 (T2a-3); angenommen, umgesetzt in #24. Verfeinert D2; kein
Widerspruch zu D1–D4, E1–E9 oder ADR-064. Die Verhaltensentscheidungen Q-24.1–Q-24.4 stehen in der Spec.

- **E10 · Logik in einem Skript, Workflow dünn:** `scripts/factory-update.sh` (übernommen) trägt den
  ganzen Ablauf; `.github/workflows/factory-update.yml` (übernommen) ist nur Auslöser: `schedule`
  (täglich) + `workflow_dispatch`, `concurrency: { group: factory-update, cancel-in-progress: false }`,
  `permissions: contents: read` für `GITHUB_TOKEN` (alle Schreibzugriffe laufen über den PAT),
  `actions/checkout@v4` mit `fetch-depth: 0` und `persist-credentials: false`, `yq` über
  `scripts/install-yq.sh`, dann `bash scripts/factory-update.sh` mit `FACTORY_SYNC_TOKEN` als Env.
  *Alternativen:* Logik inline im YAML (offline nicht testbar, Kernprinzip „Bash orchestriert");
  Fremd-Action wie `peter-evans/create-pull-request` (zusätzliche Lieferketten-Abhängigkeit mit
  Schreibrechten, Branch-/PR-Regeln aus Q-24.3/Q-24.4 nicht abbildbar, nicht offline testbar).
- **E11 · Ablauf von `factory-update.sh`** (Reihenfolge ist Teil der Entscheidung):
  1. *Moduswahl:* kein `factory.lock` (`-e`/`-L` wie E8) → Hinweis, Exit 0, kein Token, kein Netz
     (AK-24e). Lock vorhanden → Lock lesen über `scripts/lib/factory-lock.sh`; ungültig → Exit 1
     (F-24.3).
  2. *Token:* `FACTORY_SYNC_TOKEN` leer → Exit 1 mit Verweis auf `OPERATING.md`. Sonst
     `gh api repos/$GITHUB_REPOSITORY --jq .permissions.push` mit `GH_TOKEN=$FACTORY_SYNC_TOKEN`; Fehler
     oder nicht `true` → Exit 1 (FS-T2.3). Kein Rückfall auf `GITHUB_TOKEN`: das Skript liest ihn nie.
     Vorbehalt: ob `permissions.push` die Rechte eines Fine-grained-Tokens oder die Rolle seines
     Besitzers meldet, ist offline nicht belegbar (Q-24.7). Ein Token mit zu knappen Rechten wird dann
     erst beim Push bzw. bei `gh pr create` rot – rot bleibt der Lauf in jedem Fall; der Beleg am
     echten Repo folgt in T2a-4 (`nothra/tch-gastro-services#428`).
  3. *Neueste Version:* `gh api --paginate repos/<upstream.repo>/releases` (mit Token, kein
     Rate-Limit für anonyme Abrufe vom Runner). Kandidaten: `draft == false`, `prerelease == false`,
     `tag_name` erfüllt `^v[0-9]+\.[0-9]+\.[0-9]+$`, ein Asset `factory-release.json`; die höchste nach
     numerischem Vergleich der drei Teile (kein `sort -V`, bash 3.2/BSD). Abruf scheitert oder Antwort
     ist kein JSON-Array → Exit 1 (F-24.2). Keine Kandidaten oder höchste ≤ N → Hinweis, Exit 0
     (AK2.4b).
  4. *Stand des Branches/PRs* (Ziel V): offener PR = `gh pr list --head chore/factory-update --state
     open`; seine Version ist `version` aus `factory.lock` auf `origin/chore/factory-update`
     (`git show`), nicht Titel oder Body. Gleich V → Hinweis, Exit 0, kein Push (AK-24b). Kein offener
     PR, aber ein geschlossener, nicht gemergter PR dieses Branches trägt im Kopf des Bodys (vor der
     ersten Release-Überschrift aus E13) die Marke `<!-- factory-update-version: V -->` → Hinweis mit
     PR-Link, Exit 0 (AK-24d). Eine Marke in den zitierten Release Notes zählt nicht.
  5. *Neuaufbau:* `git checkout -B chore/factory-update origin/main`, `bash scripts/factory-sync.sh V`
     (scheitert → Exit 1, nichts gepusht, F-24.1), ein Commit `chore: factory auf V heben` mit
     expliziter Identität (`-c user.name=factory-update -c user.email=factory-update@localhost`, Lesson
     nothra/tch-gastro-services#334). Push nur auf `refs/heads/chore/factory-update` mit
     `--force-with-lease=refs/heads/chore/factory-update:<zuvor gelesener SHA>` (leer, wenn der Branch
     noch nicht existiert) – nie ein anderes Ziel (F1).
  6. *PR:* offener PR → `gh pr edit` (Titel, Body); sonst `gh pr create --base main --head
     chore/factory-update --label enhancement` (Art-Label laut `git-workflow.md`, „Infra/Tooling"),
     nicht als Draft. Nie `gh pr merge`, nie `--auto` (AK2.4).
- **E12 · Push-Anmeldung ohne Token in Argumenten oder Config:** Der Push setzt per `-c` einen
  Credential-Helper, der `username=x-access-token` und `password=$FACTORY_SYNC_TOKEN` zur Laufzeit aus der
  Umgebung ausgibt (`credential.helper=` leert vorher geerbte Helper). Das Token steht so weder in der
  Prozessliste noch in `.git/config`; gegen ein lokales `file://`-Origin in Tests ist der Helper wirkungslos.
  *Alternativen:* `actions/checkout` mit `token:` (scheitert ohne Secret schon vor dem No-op aus
  E11.1); `gh auth setup-git` (schreibt in die globale Git-Config – im Test die des Entwicklers);
  Token in der Remote-URL (landet in `.git/config` und Fehlermeldungen).
  *Abholung ohne Token (Security-Review):* `factory-sync.sh` ersetzt sich beim Abholen selbst und startet
  sich danach in der Fassung des Release neu – Code eines noch ungeprüften Tags. Das Skript ruft es deshalb
  mit `env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN` auf; Push und `gh` laufen erst danach mit dem Token.
- **E13 · PR-Body:** Titel `chore: factory auf V heben`. Body in dieser Reihenfolge: ein Satz „hebt
  von N auf V", die Marke aus E11.4, der Hinweis aus AK-24c (Branch gehört dem Workflow, wird bei
  jeder neuen Version neu aufgebaut, eigene Commits entfallen dann), dann je Version in (N, V] neueste
  zuerst eine Überschrift `## <version>` mit dem Release-Body aus E11.3 (AK-24a). Der Release-Body ist
  der CHANGELOG-Abschnitt der Version (`release.yml`); er ist Inhalt des Factory-Repos und geht als
  Daten in den Body, nicht in eine Shell-Auswertung (`--body-file`).
- **E14 · Ausnahme im Gate `pr-closes-issue`** (Fund aus `/architecture`, entschieden 2026-10-30): Ein
  Update-PR hat kein Issue und wäre am Required Check `pr-closes-issue` immer rot (AK2.4).
  `scripts/checks/pr-closes-keyword-check.sh` lässt einen PR ohne Closing-Keyword durch, wenn **beide**
  gelten: Head-Branch `chore/factory-update` **und** Head-Repo = Basis-Repo (ein Fork-PR mit gleichem
  Branch-Namen bleibt geprüft). Eigene Meldung, Exit 0. Der Job in `factory-ci.yml` reicht dafür
  `github.head_ref`, `github.event.pull_request.head.repo.full_name` und `github.repository` als Env
  durch. Das Gate ist ein Hygiene-Gate (verwaiste Issues), keine Sicherheitsgrenze; wer pushen darf, kann
  die Ausnahme nutzen – akzeptiert. Der Check-Name bleibt (ADR-029 unverändert).
  *Alternative:* der Workflow legt je Update-PR ein Issue an und schreibt `Closes #<nr>` (Gate
  unverändert, aber Issue-Lebenszyklus bei Neuaufbau und Ablehnung mitpflegen, Token braucht
  zusätzlich *issues:write*) – verworfen.
- **E15 · Token-Rechte (Q-24.6):** Fine-grained PAT, nur auf das Konsumenten-Repo: *Contents:
  read and write*, *Pull requests: read and write*, *Workflows: read and write* (eine Version, die eine
  Datei unter `.github/workflows/` ändert, lässt sich sonst nicht pushen), *Metadata: read* (implizit).
  Öffentliche Repos wie `nothra/dev-factory` liest jeder Fine-grained PAT ohne eigenes Recht.
  *issues:write* auf `nothra/dev-factory` (D2) braucht erst T2b (Fund-Ablage) und wird dort ergänzt.
  Laufzeit ≤ 1 Jahr; Anlage, Ablauf und Rotation in `OPERATING.md` (neuer Abschnitt im Einmal-Setup,
  Verweis aus §5.5a).
- **E16 · Tests (offline, ausgelieferte Suite):** Upstream-Fixture aus #23 (lokales Repo mit Tags,
  `FACTORY_UPSTREAM_GIT_URL`/`FACTORY_RELEASE_BASE_URL`), dazu ein lokales Bare-Repo als `origin` des
  Konsumenten und ein `gh`-Stub im `PATH`, der Release-Liste, Repo-Rechte und PR-Zustand aus Dateien
  liefert und jeden Aufruf protokolliert. Belege über Protokoll (kein schreibender Aufruf, kein
  `merge`), Branch-SHA in `origin` und `main` vor/nach. Wiring-Tests an den echten Zeilen von
  `factory-update.yml` (Trigger, `concurrency`, Token-Quelle, kein `GITHUB_TOKEN` im Skript-Schritt) und
  am Env-Durchreichen des `pr-closes-issue`-Jobs. Mutationsbelege für Token-Prüfung (FS-T2.3) und
  Fork-Bedingung (E14). Die neue Bibliotheks-Nutzung kommt in alle Scaffoldings (Lesson
  nothra/tch-gastro-services#197).

**Konsequenzen:** neue Factory-Dateien `scripts/factory-update.sh` und
`.github/workflows/factory-update.yml` (je eine Zeile `factory` in `OWNERSHIP.md`); geändert
`scripts/checks/pr-closes-keyword-check.sh`, `.github/workflows/factory-ci.yml` (Env des Jobs
`pr-closes-issue`), `docs/factory/OPERATING.md`, `docs/factory/guidelines/git-workflow.md` (Ausnahme bei
der Closes-Regel nennen). Im Factory-Repo läuft der Workflow täglich als grüner No-op. Der erste echte
Lauf – und damit der Beleg, dass die Gates am Update-PR tatsächlich anlaufen – ist Teil von T2a-4.
