# Changelog

Format: ein Abschnitt je Version (`## vX.Y.Z – <Datum>`), neueste oben. Ein Abschnitt zum Tag ist
Voraussetzung für das Release (Factory-ADR-063 D6).

## Unreleased

## v0.6.0 – 2026-10-24

Erste Version der Factory als eigenständiges Repo. Sie wurde mit ihrer Historie aus
[`nothra/tch-gastro-services`](https://github.com/nothra/tch-gastro-services) herausgelöst (Epic
`nothra/tch-gastro-services#424`, Factory-ADR-063); Autoren und Daten der Commits sind unverändert.

### Neu

- **Eigenes Repo mit Release-Mechanik:** SemVer-Tags `vX.Y.Z`, GitHub Release mit Release Notes und dem Manifest
  `factory-release.json` (Pfad + SHA-256 je ausgelieferter Datei, Seite `factory` laut `docs/factory/OWNERSHIP.md`
  am Tag). `scripts/factory-release-manifest.sh` und `scripts/factory-release-check.sh` sind Teil der Auslieferung.
- **Dateizuordnung:** `docs/factory/OWNERSHIP.md` ordnet jede Datei genau einer Seite zu (`factory` = ausgeliefert,
  `project` = Anpassungsstelle); `scripts/checks/ownership-check.sh` erzwingt das im Push-Gate.
- **Anpassungsstellen statt Mischdateien:** `CLAUDE.md` importiert `docs/factory/FACTORY.md` (generisch) und
  `docs/factory/PROJECT-CONTEXT.md` (projekteigen); `.claude/settings.json` und `.gitignore` entstehen per
  `scripts/factory-sync.sh --compose` aus Factory- und Projekt-Fragment; Erweiterungspunkte der Git-Gates unter
  `scripts/project/checks/pre-commit.d/` und `pre-push.d/`.
- **Gate-Kommandos aus der Konfiguration:** `commands.{lint,test,typecheck,format,coverage,install}` in
  `factory.config.yml` (kein pnpm-Default); `labels.{kinds,aspects,aspects_extra}` und `start_work.hint`.
- **Factory-ADRs** liegen unter `docs/factory/adr/` (Nummern unverändert), generische Lessons unter
  `docs/factory/lessons/`.
- **Self-Tests:** die Suite isoliert sich von der Git-Hook-Umgebung (`GIT_DIR` & Co.), sodass sie sicher als
  `commands.test` im pre-push-Hook eines Worktrees läuft.

### Breaking

- Adoptierende Projekte beziehen die Factory-Dateien künftig aus diesem Repo (Release-Manifest) statt aus einem
  Template-Klon; die Umstellung ist der nächste Schritt (T2) und noch nicht vollzogen.
- `commands.*` müssen in `factory.config.yml` gesetzt sein; ein fehlendes Pflicht-Kommando bricht das Gate mit dem
  Schlüsselnamen ab (kein stiller pnpm-Fallback).
- Factory-ADRs liegen nicht mehr in `docs/adr/`, sondern in `docs/factory/adr/`; Verweise sind als `Factory-ADR-NNN`
  zu schreiben.
- `.claude/settings.json` und `.gitignore` sind Ergebnis von `factory-sync.sh --compose` und werden nicht mehr von
  Hand geändert (Fragment ändern, neu zusammensetzen, beides committen).
- Verweise auf das Ursprungs-Repo sind als `nothra/tch-gastro-services#<nr>` qualifiziert; ein unqualifiziertes `#<nr>`
  meint dieses Repo.
