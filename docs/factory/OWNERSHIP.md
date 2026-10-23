# Zuordnungstabelle: Factory- vs. Projekt-Dateien

> **Kanonische Quelle** für die Frage „Gehört diese Datei der Factory oder dem Projekt?"
> (ADR-063 D3/D11, Spec [#426](../specs/spec-426-trennlinie-factory-projekt-ziehen.md)). Jede
> getrackte Datei gehört **genau einer** Seite – es gibt keine Mischdateien.
>
> - **`factory`** – gehört der Factory; wandert in T1b nach `nothra/dev-factory` und kommt ab T2
>   als übernommene Datei zurück. Änderungen gehören dorthin.
> - **`project`** – gehört TCH; bleibt nur hier; ab T2 eine Anpassungsstelle (wird nie überschrieben).

## Zeilenformat (maschinenlesbar)

Eine Zeile je Muster, genau diese Form – `scripts/checks/ownership-check.sh` ist der **einzige**
Parser und liest nichts anderes:

```
| <seite> | `<muster>` | <begründung> |
```

- `<seite>` ist `factory` oder `project`.
- `<muster>` ist ein Pfad relativ zur Repo-Wurzel oder ein Glob: `*` steht für beliebig viele Zeichen
  **innerhalb** eines Pfadsegments, `**` für beliebig viele Segmente. Alles andere ist wörtlich
  (ein `.` ist ein Punkt). Backticks um das Muster sind Pflicht-Optik, das Muster selbst enthält
  kein `|`.
- Alle anderen Zeilen (Überschriften, Prosa, die Kopfzeile jeder Tabelle) werden ignoriert.

## Regeln

1. **Jede** von `git ls-files` gelistete Datei trifft mindestens ein Muster – sonst schlägt der Check
   fehl und nennt die Datei. Eine neue Datei braucht also in **demselben PR** eine Zeile.
2. Treffen Muster **beider** Seiten dieselbe Datei, schlägt der Check ebenfalls fehl (beide Muster
   werden genannt). Zwei Muster derselben Seite sind erlaubt.
3. Der Check läuft im lokalen `pre-push.sh` und in der Self-Test-Suite (`run-tests.sh`), die CI als
   Required Check `factory-self-test` ausführt – kein eigener Check-Name.
4. **Allowlist für T1b:** `bash scripts/checks/ownership-check.sh --list factory` gibt genau die
   Dateien der Factory aus (Eingabe für `git filter-repo`). Ein zweites Format gibt es nicht.

> **Übergangsstand (T1a-1, #426):** Dateien, die heute noch Factory- **und** TCH-Anteile mischen,
> stehen mit der Seite, der sie nach dem Aufteilen gehören. Aufgelöst werden sie in T1a-2 (#431:
> `CLAUDE.md`, `.claude/settings.json`, `.gitignore`, `factory-ci.yml`, `pre-commit.sh`,
> `pre-push.sh`, `factory.defaults.yml`) und T1a-3 (#432: Skripte/Tests und Texte). Die Tabelle wird
> dort mit jedem Verschieben nachgezogen.

## Factory

| Seite | Muster | Begründung |
|---|---|---|
| factory | `.claude/commands/**` | Skills der Pipeline |
| factory | `.github/workflows/factory-ci.yml` | Factory-Jobs (`pr-closes-issue`, `issue-sync`, `config-validation`, `factory-self-test`, `post-merge-verify`); kein `pnpm` |
| factory | `.github/workflows/factory-poll.yml` | Async-Start der Pipeline (ADR-008) |
| factory | `config/otel.env.example` | Vorlage für die Telemetrie-Erhebung |
| factory | `docs/factory/FACTORY.md` | Generischer Teil der Agenten-Regeln (aus `CLAUDE.md`, #431) |
| factory | `docs/factory/OPERATING.md` | Betriebshandbuch der Pipeline; TCH-Abschnitte stehen in `docs/project/betrieb.md` |
| factory | `docs/factory/OWNERSHIP.md` | diese Tabelle |
| factory | `docs/factory/kleinfunde.md` | Kleinfunde zu Factory-Dateien (Q6) |
| factory | `docs/factory/agents/**` | Agenten-Personas |
| factory | `docs/factory/guidelines/**` | Coding-/Workflow-Guidelines |
| factory | `docs/factory/lessons/**` | generische `/codify`-Learnings (App-Lessons: `docs/project/lessons/`) |
| factory | `docs/factory/adr/**` | Factory-ADRs (ADR-063 D8, Nummern unverändert) |
| factory | `factory.defaults.yml` | Konfigurations-Defaults (ADR-009) |
| factory | `factory.config.yml.example` | Vorlage der Projekt-Konfiguration |
| factory | `scripts/checks/adr-links-check.sh` | Gate: kein toter ADR-Link (Spec #426 AK-B3) |
| factory | `scripts/checks/branch-name-check.sh` | Hook: Branch-Namen |
| factory | `scripts/checks/check.sh` | Hook-Einstieg (PreToolUse) |
| factory | `scripts/checks/commit-msg-check.sh` | Hook: Commit-Message-Flag-Guard |
| factory | `scripts/checks/completion-check.sh` | Hook: Task-Abschluss |
| factory | `scripts/checks/config-validation-check.sh` | Gate: `factory.config.yml` (ADR-010) |
| factory | `scripts/checks/git-context-check.sh` | Hook: Git-Kontext |
| factory | `scripts/checks/hooks-installed-check.sh` | Gate: Git-Hooks installiert (ADR-042) |
| factory | `scripts/checks/import-context-limit-check.sh` | Gate: `@import`-Deckel (ADR-047) |
| factory | `scripts/checks/interrupt-check.sh` | Hook: Interrupt-Sentinel |
| factory | `scripts/checks/ownership-check.sh` | Gate: diese Tabelle |
| factory | `scripts/checks/pr-closes-keyword-check.sh` | Gate: `Closes #<id>` im PR-Body |
| factory | `scripts/checks/pre-commit.sh` | Git-Hook; Projekt-Checks über `scripts/project/checks/pre-commit.d/` |
| factory | `scripts/checks/pre-push.sh` | Git-Hook; Projekt-Checks über `scripts/project/checks/pre-push.d/` |
| factory | `scripts/checks/tests/**` | Self-Test-Suite der Factory |
| factory | `scripts/checks/tests/lib/**` | gemeinsame Prüf-Helfer der Test-Suiten; Factory- und Projekt-Suite sourcen sie (#432, Q10) |
| factory | `scripts/factory-sync.sh` | Setzt `settings.json`/`.gitignore` aus Fragmenten zusammen (`--compose`, ADR-063 Q2) |
| factory | `.claude/settings.factory.json` | Factory-Anteil der Settings (Hooks, generische Permissions) |
| factory | `docs/factory/gitignore.factory` | Factory-Anteil der `.gitignore` |
| factory | `scripts/factory-commit.sh` | Commit/Push-Seam (ADR-019) |
| factory | `scripts/factory-poll.sh` | Poll-Skript (ADR-008) |
| factory | `scripts/init-factory.sh` | Initialisierung |
| factory | `scripts/install-hooks.sh` | Hook-Installation (ADR-042) |
| factory | `scripts/install-yq.sh` | gepinnter `yq`-Seam |
| factory | `scripts/lib/**` | Bibliotheken der Pipeline-Skripte |
| factory | `scripts/metrics.sh` | Prozess-Kennzahlen (ADR-006) |
| factory | `scripts/post-merge-verify.sh` | Verifikation nach dem Merge (ADR-007) |
| factory | `scripts/raise-interrupt.sh` | Interrupt-Mechanismus (ADR-004) |
| factory | `scripts/run-pipeline.sh` | Pipeline-Orchestrierung |
| factory | `scripts/start-work.sh` | Task-Start (ADR-013) |
| factory | `scripts/sync-issues.sh` | Task↔Issue-Sync |

## Projekt

| Seite | Muster | Begründung |
|---|---|---|
| project | `.claude/launch.json` | Dev-Server-Konfiguration der App |
| project | `.claude/settings.json` | Ergebnis von `factory-sync.sh --compose` aus Factory- + Projekt-Fragment; nicht von Hand ändern |
| project | `.claude/settings.project.json` | Projekt-Fragment der Settings (App-Pfade, Lockfile-Deny) |
| project | `.env.example` | App-Umgebungsvariablen |
| project | `.github/workflows/ci.yml` | Projekt-CI: `lint` + `test` der App (aus `factory-ci.yml`, #431) |
| project | `.github/workflows/deploy-gate.yml` | Vercel-Deploy-Gate (ADR-015/017) |
| project | `.github/workflows/deploy-freeze-release.yml` | Deploy-Freeze (ADR-032) |
| project | `.gitignore` | Ergebnis von `factory-sync.sh --compose`; nicht von Hand ändern |
| project | `.gitignore.project` | Projekt-Fragment der `.gitignore` (Node/Next/Playwright) |
| project | `.issue-npm-pin.md` | verwaister Issue-Entwurf, kein Pipeline-Bestandteil |
| project | `.prettierignore` | App-Formatierung |
| project | `.prettierrc.json` | App-Formatierung |
| project | `CLAUDE.md` | Projekt-Regeln (TCH); importiert `FACTORY.md` und `PROJECT-CONTEXT.md` |
| project | `LICENSE` | Lizenz des Projekts |
| project | `app/**` | App-Code |
| project | `db/**` | Schema, Migrationen, Data-Layer |
| project | `docs/*.md` | Changelog, FAQ, Routen-Doku der App |
| project | `docs/adr/**` | App-ADRs (Factory-ADRs: `docs/factory/adr/`) |
| project | `docs/anleitung/**` | Anwender-Anleitung der App |
| project | `docs/factory/PROJECT-CONTEXT.md` | Projekt-Gedächtnis (Anpassungsstelle) |
| project | `docs/project/**` | projekteigene Doku (App-Lessons, Kleinfunde) |
| project | `docs/project/betrieb.md` | TCH-Betrieb: Werkzeuge, lokale Umgebung, Deploy-Gate-Secrets, Vercel, destruktive Migrationen (#432) |
| project | `docs/specs/**` | Spec-Archiv des Projekts |
| project | `docs/ux/**` | UX-Glossar und -Entwürfe der App |
| project | `docker-compose.yml` | lokale Datenbank |
| project | `e2e/**` | Playwright-Tests der App |
| project | `eslint/**` | Farb-Gate der App (ADR-052) |
| project | `factory.config.yml` | Projekt-Konfiguration (Anpassungsstelle) |
| project | `lib/**` | App-Bibliothek |
| project | `pnpm-lock.yaml` | Abhängigkeiten der App |
| project | `pnpm-workspace.yaml` | pnpm-Einstellungen der App |
| project | `public/**` | statische App-Assets |
| project | `scripts/project/**` | Projekt-Erweiterungspunkte der Git-Gates (`checks/pre-commit.d/`, `checks/pre-push.d/`), u. a. Routen-Doku-Drift der App (#145) |
| project | `scripts/project/*.sh` | TCH-Skripte: Deploy-Freeze (`deploy-freeze.sh`, `deploy-freeze-notify.sh`), Neon-INT-Reset (`neon-reset-int.sh`) |
| project | `scripts/project/tests/**` | Projekt-Suite (`run-project-tests.sh`); läuft im Required Check `test` des `ci.yml` (#432) |
| project | `tasks/**` | Task-, Review- und Telemetrie-Archiv des Projekts |
| project | `types/**` | App-Typdeklarationen |
| project | `*.json` | Wurzel-Konfiguration der App (`package.json`, `tsconfig.json`, `vercel.json`) |
| project | `*.md` | Wurzel-Dokumente (`README.md`, `CONTRIBUTING.md`, `SECURITY.md`) |
| project | `*.mjs` | Wurzel-Konfiguration der App (`eslint`, `postcss`) |
| project | `*.ts` | Wurzel-Konfiguration und -Code der App (`auth`, `proxy`, `next.config`, `vitest` …) |
