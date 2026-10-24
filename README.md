# dev-factory

Die **dm Development Factory**: Pipeline-Skripte, Claude-Code-Skills, Agent-Personas, Gates und
Hooks, generische Guidelines und Betriebsdoku für deterministische, KI-gestützte
Softwareentwicklung. Kernprinzip: *Deterministische Skripte orchestrieren nicht-deterministische
Agenten-Schritte – nie umgekehrt.*

Das Repo ist die **Quelle der Factory**. Projekte binden sie als übernommene Dateien ein (committete
Kopie plus Release-Manifest, Factory-ADR-063); das Repo selbst nutzt dieselbe Factory für seine
eigene Entwicklung.

## Herkunft

Die Factory entstand im Projekt [`nothra/tch-gastro-services`](https://github.com/nothra/tch-gastro-services)
(Epic `nothra/tch-gastro-services#424`) und wurde mit ihrer Historie herausgelöst: Commits, Autoren
und Daten sind unverändert, Verweise auf Issues und PRs des Ursprungs-Repos sind als
`nothra/tch-gastro-services#<nr>` qualifiziert. Ein unqualifiziertes `#<nr>` meint dieses Repo.

## Inhalt

| Bereich | Pfad |
|---|---|
| Pipeline und Gates | `scripts/` (`run-pipeline.sh`, `start-work.sh`, `scripts/checks/`) |
| Skills | `.claude/commands/` |
| Agent-Regeln, Guidelines, ADRs, Lessons | `docs/factory/` |
| Konfiguration | `factory.defaults.yml`, `factory.config.yml` (eigene Anpassung) |
| CI | `.github/workflows/` |

Einstieg: [`docs/factory/FACTORY.md`](docs/factory/FACTORY.md) (Regeln und Pipeline) und
[`docs/factory/OPERATING.md`](docs/factory/OPERATING.md) (Betrieb). Die Dateizuordnung steht in
[`docs/factory/OWNERSHIP.md`](docs/factory/OWNERSHIP.md).

## Lokales Setup

Voraussetzungen: `git`, `gh`, `jq`, `yq` (`bash scripts/install-yq.sh`); kein pnpm, kein Node, keine
Datenbank.

```bash
bash scripts/install-hooks.sh                  # Git-Hooks (pre-commit, pre-push, commit-msg)
bash scripts/checks/tests/run-tests.sh         # Self-Test-Suite
```

Neue Aufgaben starten mit `bash scripts/start-work.sh <beschreibung> [branch-typ]` (eigener Worktree,
Branch und Draft-PR). Details: [`CONTRIBUTING.md`](CONTRIBUTING.md).

## Lizenz

Apache License 2.0 – siehe [`LICENSE`](LICENSE).

## Versionen

SemVer-Tags `vX.Y.Z` mit GitHub Release und Manifest `factory-release.json`; die Änderungen je
Version stehen in [`CHANGELOG.md`](CHANGELOG.md).
