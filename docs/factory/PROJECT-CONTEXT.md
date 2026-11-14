# Projekt-Kontext

> Projekt-Gedächtnis des **Factory-Repos selbst** (Factory-ADR-063 D9: die Factory nutzt sich selbst).
> Agenten haben kein Langzeitgedächtnis – diese Datei ist ihr Onboarding-Dokument. Sie ist eine
> Anpassungsstelle (Seite `project` in `docs/factory/OWNERSHIP.md`) und wird bei einem Update nie
> überschrieben.

---

## Projekt

| Feld | Wert |
|------|------|
| **Name** | dev-factory (Development Factory) |
| **Beschreibung** | Pipeline, Skills, Gates/Hooks, Agent-Personas und Guidelines für deterministische, KI-gestützte Softwareentwicklung – als eigenständiges Repo, das Projekte als übernommene Dateien einbinden |
| **Typ** | Werkzeug-Repo (Shell-Skripte, Markdown, YAML) |
| **Repository** | https://github.com/nothra/dev-factory |
| **Herkunft** | herausgelöst mit Historie aus `nothra/tch-gastro-services` (Epic `nothra/tch-gastro-services#424`, Factory-ADR-063) |

---

## Tech-Stack

| Feld | Wert |
|------|------|
| **Primärsprache** | Bash (Skripte), Markdown (Skills, Doku), YAML (Config, CI) |
| **Werkzeuge** | `git`, `gh`, `jq`, `yq` (gepinnt über `scripts/install-yq.sh`), `claude` (nur für die Pipeline) |
| **Build / Datenbank** | keine – kein pnpm, kein Node, keine Datenbank |

## Build, Test, Lint

```bash
bash scripts/checks/tests/run-tests.sh                 # ausgelieferte Self-Test-Suite
FACTORY_SELF_TEST_SERIAL=1 bash scripts/checks/tests/run-tests.sh  # dieselbe Suite, Testgruppen nacheinander (Factory-ADR-066 D6)
bash scripts/project/checks/factory-suite-gate.sh      # commands.test: Suite, außer bei reinem tasks/-/docs/specs/-Diff
bash scripts/project/tests/run-tests.sh                # Projekt-Suite: Prüfungen, die dieses Repo voraussetzen
git ls-files -z '*.sh' | xargs -0 -n1 bash -n          # Syntaxprüfung (commands.lint)
bash scripts/install-hooks.sh                          # Git-Hooks einmalig installieren
```

- **Test-Framework:** eigene Bash-Suiten – die ausgelieferte `scripts/checks/tests/run-tests.sh` und die Projekt-Suite
  `scripts/project/tests/run-tests.sh` – mit gemeinsamen Helfern in `scripts/checks/tests/lib/`; Konventionen in
  `docs/factory/guidelines/testing-standards.md`.
- **Lint:** `bash -n` über alle getrackten `*.sh` (CI-Job `lint`); ShellCheck folgt als Issue.
- **Gates lokal:** `scripts/checks/pre-commit.sh`, `scripts/checks/pre-push.sh` (laufen ohne Node/DB).

---

## Architektur

- **Aufbau:** `scripts/` (Pipeline, Gates, Hooks), `.claude/commands/` (Skills),
  `docs/factory/` (Agenten-Regeln, Guidelines, ADRs, Lessons, Betriebshandbuch), `.github/workflows/`.
- **Eigene Anpassungsstellen** (Seite `project`): `CLAUDE.md`, `factory.config.yml`,
  `docs/factory/PROJECT-CONTEXT.md` (diese Datei), `README.md`, `CHANGELOG.md`, `.claude/settings.project.json`,
  `.gitignore.project`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`.
- **Anpassungsstellen-Liste:** Die Factory liefert sie als `scripts/checks/customization-points.txt` mit; ein Drift-Guard in
  `scripts/project/tests/run-tests.sh` hält sie und diese Aufzählung deckungsgleich.
- **Zuordnung** jeder Datei zu `factory` (wird ausgeliefert) oder `project` (gehört dem Repo):
  [`OWNERSHIP.md`](OWNERSHIP.md); Quelle des Release-Manifests ist die Seite `factory`.
- **Releases:** SemVer-Tags `vX.Y.Z` auf `main`, Release-PR setzt Versionszeile in `FACTORY.md` und
  `CHANGELOG.md` (Factory-ADR-063 D6).
- Relevante ADRs: `docs/factory/adr/` – insbesondere **063** (eigenes Repo, Manifest).

## Konventionen

- **Referenzen:** unqualifiziertes `#<nr>` meint ein Issue/PR **dieses** Repos; ein Verweis auf
  `nothra/tch-gastro-services` steht immer qualifiziert (`nothra/tch-gastro-services#<nr>`).
- **Erlaubte Stellen für Herkunftsbegriffe (AK C1):** Die Begriffe `Veranstaltung`, `Montagsrunde`,
  `Thekenwart`, `Heuchelheim`, `TCH`, `tch-gastro`, `Neon`, `Vercel` kommen im Repo nur vor in
  (1) qualifizierten Herkunftsverweisen `nothra/tch-gastro-services#<nr>`, (2) dem Herkunftshinweis in
  `README.md` und `CHANGELOG.md`, (3) der Fixture `scripts/checks/tests/fixtures/lessons-split-426.tsv`
  (Rekonstruktions-Daten der Lesson-Aufteilung, unverändert), (4) dieser Datei.
- **`#<nr>` in Shell-Strings** (Testnamen und Meldungen in `scripts/checks/tests/run-tests.sh`) bezeichnet das Issue
  des Ursprungs-Repos, aus dem der jeweilige Test stammt; in Kommentaren und Dokumenten steht der Verweis qualifiziert.
- **Zwei Suiten (Factory-ADR-064 D6):** die ausgelieferte Suite `scripts/checks/tests/run-tests.sh` ist konsumenten-neutral und
  setzt weder `ci.yml`, `release.yml` noch `OWNERSHIP.md` dieses Repos voraus; was dieses Repo voraussetzt, steht in
  `scripts/project/tests/run-tests.sh` (lokal über `pre-push.d/`, in CI als Job `project-self-test`).

---

## Projekt-Labels

> Das Factory-Repo trägt **keine** projekteigenen Aspekt-Labels (`labels.aspects_extra` ist leer):
> hier ist alles Factory-Arbeit – die Unterscheidung „Werkzeug vs. Produkt" gibt es nur in
> adoptierenden Projekten.

| Label | Aspekt |
|-------|--------|
| _(keine)_ | – |

---

## Bekannte Stolpersteine

> Factory-Lessons: Übersicht mit „Laden bei"-Trigger in `docs/factory/FACTORY.md` → „Bedarfsgesteuert laden",
> Einzelliste in [`lessons/INDEX.md`](lessons/INDEX.md) (beides ausgeliefert, Factory-ADR-037 Nachtrag #44).
> Projekt-Lessons (`docs/project/lessons/`): dieses Repo hat keine. Legt `/codify` eine an, kommt hier eine Gruppe
> „Projekt-Lessons" mit „Laden bei"-Trigger am Gruppen-Header hinzu.
