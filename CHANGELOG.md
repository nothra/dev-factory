# Changelog

Format: ein Abschnitt je Version (`## vX.Y.Z – <Datum>`), neueste oben. Ein Abschnitt zum Tag ist
Voraussetzung für das Release (Factory-ADR-063 D6).

## Unreleased

## v0.7.0 – 2026-10-31

Erste Version, die ein Konsumenten-Repo selbst abholen und aktuell halten kann (T2a, Epic
`nothra/tch-gastro-services#424`). Bis v0.7.1 gilt die Einschränkung zu `FACTORY_SYNC_TOKEN` unten.

### Neu

- **Konsumenten-Vertrag (Factory-ADR-064, #22):** `ownership-check.sh` kennt zwei Modi. Mit `factory.lock` im Wurzelverzeichnis
  gilt allein der Lock (Seite `factory` = seine Pfadmenge), ohne Lock weiter `OWNERSHIP.md`. Die Liste der
  Anpassungsstellen liefert die Factory als `scripts/checks/customization-points.txt` mit.

- **Abholen und Integritäts-Gate (Factory-ADR-063 Nachtrag 2026-10-25, #23):** `bash scripts/factory-sync.sh <version> [--adopt]`
  holt einen Tag aus `upstream.repo` (neuer Schlüssel in `factory.defaults.yml`, Default `nothra/dev-factory`), prüft jede Datei
  gegen das Release-Manifest, übernimmt atomar (Backup + Rückbau) und schreibt `factory.lock`. `--adopt` erlaubt die
  Erstabholung über abweichende Dateien. `scripts/checks/factory-integrity-check.sh` verhindert, dass ein Projekt übernommene
  Dateien still ändert: lokale Stufe offline in `pre-commit.sh`/`pre-push.sh`, CI-Stufe (`--ci`, Job `factory-integrity`)
  zusätzlich gegen das Release-Manifest des Tags. Beschreibung in `docs/factory/OPERATING.md` §5.5a.

- **Update-Workflow (Factory-ADR-063 Nachtrag 2026-10-30, #24):** `.github/workflows/factory-update.yml` läuft täglich und per
  `workflow_dispatch`, erkennt eine neuere Version in `upstream.repo`, holt sie mit `factory-sync.sh` ab und pflegt dafür **einen**
  Update-PR auf dem festen Branch `chore/factory-update` (Release Notes jeder übersprungenen Version im Body). Er merged nie und
  setzt kein Auto-Merge; über den PR entscheiden die Gates und der Mensch. Push und PR laufen mit dem PAT `FACTORY_SYNC_TOKEN`
  (nicht `GITHUB_TOKEN`, damit die Gates am PR laufen); ohne `factory.lock` ist der Lauf ein grüner No-op. Logik in
  `scripts/factory-update.sh`, Einrichtung und Rotation des Tokens in `docs/factory/OPERATING.md` §0.6. Das Gate
  `pr-closes-issue` lässt den Update-PR ohne Issue durch (nur dieser Branch im selben Repo).

### Geändert

- Die Compose-Tests der ausgelieferten Self-Test-Suite bauen ihre Projekt-Fragmente selbst; der Abgleich „committete
  `settings.json`/`.gitignore` == Zusammensetzung“ liegt beim Konsumenten im Integritäts-Gate, im Factory-Repo in der Projekt-Suite.
- Die ausgelieferte Self-Test-Suite ist konsumenten-neutral; Prüfungen, die das Factory-Repo voraussetzen, laufen in
  `scripts/project/tests/` (lokal über `pre-push.d/`, in CI als Job `project-self-test`) (#28).
- Der @import-Deckel-Test liest `CLAUDE.md`/`PROJECT-CONTEXT.md` des Konsumenten nicht mehr: er läuft nur noch in der
  Projekt-Suite des Factory-Repos, die Kontextgröße ist Sache des Projekts (#32).
- Ausgelieferte Dateien verweisen für die Dateizuordnung (Lesson-/Kleinfund-Ort, Besitzer-Kopf) auf
  `bash scripts/checks/ownership-check.sh --list factory` statt auf `docs/factory/OWNERSHIP.md` – im Konsumenten gibt es
  sonst tote Links (#27).

### Breaking

- `docs/factory/OWNERSHIP.md` wird nicht mehr ausgeliefert (Factory-ADR-064 D5). Mit `factory.lock` bestimmt allein der Lock
  die Seite `factory`; ein Projekt ohne Lock pflegt `OWNERSHIP.md` selbst (Seite `project`).
- Mit `factory.lock` lehnen `pre-commit.sh`/`pre-push.sh` und der CI-Job `factory-integrity` jede lokale Änderung an einer
  übernommenen Datei ab. Änderungen an Factory-Dateien gehen ab jetzt über das Factory-Repo und eine neue Version.

### Bekannte Einschränkungen

- **#37 offen – `FACTORY_SYNC_TOKEN` erst ab v0.7.1 hinterlegen.** `factory-update.sh` führt im selben Job Code des noch
  ungeprüften Release aus, der an das schreibberechtigte Token kommen kann. Das Secret daher im Konsumenten erst nach dem
  Fix in v0.7.1 anlegen. Bis dahin endet der Workflow bei vorhandenem `factory.lock` ohne Token sauber mit Fehler
  (`FACTORY_SYNC_TOKEN fehlt …`, FS-T2.3), ohne etwas zu ändern; Updates holt der Mensch manuell mit
  `bash scripts/factory-sync.sh <version>`.

## v0.6.1 – 2026-10-24

Patch-Release ohne Verhaltensänderung.

### Geändert

- Lizenz Apache-2.0 ergänzt (`LICENSE`).
- Bezeichnung der Factory in Doku, Workflows und Skripten neutralisiert (#18).

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
