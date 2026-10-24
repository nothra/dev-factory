# ADR 064: Konsumenten-Vertrag – `factory.lock` als Ownership-Quelle, Lock-Format

## Status
Accepted (2026-10-24, aus Spec `docs/specs/spec-22-konsumenten-vertrag.md`; mit der Umsetzung in #22 angenommen)

## Date
2026-10-24

## Kontext

Die Factory liefert Skripte und Self-Tests an Repos aus, die sie einbinden (ADR-063). Zwei
ausgelieferte Dateien setzen heute das Factory-Repo voraus: `scripts/checks/ownership-check.sh`
liest `docs/factory/OWNERSHIP.md`, und `scripts/checks/tests/run-tests.sh` prüft auch den Zustand
des Factory-Repos selbst (`ci.yml`, `release.yml`, Dateizahlen, `OWNERSHIP.md`).

Festgelegt ist bereits (Spec #22, Entscheidung 2026-10-24): im Lock-Modus gilt die Pfadmenge des
Locks als Seite `factory`; die Anpassungsstellen liefert die Factory als feste Liste selbst mit; kein
Release in #22. Offen waren das **Lock-Format** (#22 liest, #23 schreibt) und der **Ort der
Anpassungsstellen-Liste**.

Randbedingungen aus dem Ist-Stand:
- `scripts/factory-release-manifest.sh` erzeugt bereits `factory-release.json`
  (`{"schema":1,"repo","version","commit","files":[{"path","sha256"}]}`). Es ist der Vertrag für
  adoptierende Projekte und wird mit `jq` erzeugt.
- `jq` ist als Werkzeug der Factory gesetzt (PROJECT-CONTEXT „Tech-Stack").
- `pre-push.sh` hat den Projekt-Erweiterungspunkt `scripts/project/checks/pre-push.d/`; `ci.yml` ist
  projekteigen. Beide können Projekt-Tests anstoßen, ohne eine Factory-Datei zu ändern.

## Entscheidung

**D1 · Format von `factory.lock`: JSON im Schema des Release-Manifests.** `factory.lock` ist das
Release-Manifest der eingebundenen Version, unverändert übernommen (`schema`, `repo`, `version`,
`commit`, `files[].path`, `files[].sha256`). Wer es schreibt (#23), kopiert das heruntergeladene
Manifest; wer es liest (#22, #23), nutzt `jq`. Ablage: `factory.lock` im Repo-Wurzelverzeichnis.

**D2 · Moduswahl in `ownership-check.sh`.** Existiert `$FACTORY_DIR/factory.lock` (Test-Override
`FACTORY_LOCK_FILE`), gilt **allein** der Lock-Modus; sonst der Tabellenmodus, unverändert. Es gibt
keinen Mischmodus. Die Ausgabe nennt den Modus.

**D3 · Lock-Modus-Semantik.** Seite `factory` = Menge `files[].path`; alle übrigen getrackten Dateien
= `project`. Pfade werden wörtlich verglichen (keine Globs). Fehlerklassen:
- Lock unlesbar, kein gültiges JSON, `schema` ≠ 1 oder `files` leer, `jq` fehlt → **Exit 2**
  (fail-closed, kein Rückfall in den Tabellenmodus).
- Lock-Pfad ist nicht getrackt, Lock-Pfad steht in der Anpassungsstellen-Liste oder kommt doppelt
  vor → **Exit 1**, jeder Pfad namentlich.

**D4 · Anpassungsstellen-Liste: `scripts/checks/customization-points.txt`.** Ein Pfad je Zeile
(wörtlich, `#`-Kommentare), Seite `factory` (wird mit ausgeliefert). Fehlt die Datei oder ist sie
nicht lesbar → Exit 2 im Lock-Modus. Sie ist eine **Teilmenge** der `project`-Zeilen von
`OWNERSHIP.md`, nicht deren Gesamtheit (`tasks/**`, `docs/specs/**` u. a. sind `project`, aber keine
Anpassungsstellen). Drift-Guard: jeder Eintrag steht auf Seite `project` laut Tabelle, und jede in
`PROJECT-CONTEXT.md` „Eigene Anpassungsstellen" genannte Datei steht in der Liste.

**D5 · `OWNERSHIP.md` wird `project`.** Die Zeile wechselt von `factory` auf `project`. Das
Release-Manifest (erzeugt am Tag-Stand, liest die Tabelle weiter aus dem Factory-Repo) enthält die
Datei damit nicht mehr. Konsumenten pflegen keine Zuordnungstabelle.

**D6 · Test-Schnitt.** Factory-spezifische Testgruppen wandern aus `scripts/checks/tests/run-tests.sh`
nach `scripts/project/tests/run-tests.sh`, geteilte Helfer bleiben in `scripts/checks/tests/lib/`.
Aufruf im Factory-Repo: `scripts/project/checks/pre-push.d/` (lokal, Erweiterungspunkt) und ein
zusätzlicher Job in `ci.yml` (projekteigen). **Kriterium „Factory-Repo-spezifisch":** die Gruppe liest
`.github/workflows/ci.yml`, `release.yml`, `OWNERSHIP.md` als Zuordnungs-Fixture des echten Repos,
zählt Dateien des echten Repos oder prüft Release-/Manifest-Zustand des Factory-Repos.
Beleg: Inventar der Testgruppen mit Assertion-Zahl vor und nach dem Schnitt.

## Alternativen

### Option A (gewählt): Lock = Release-Manifest (JSON)
Vorteile: kein zweites Format, #23 schreibt den Lock durch Kopieren; Hash-Prüfung (#23) und
Pfad-Prüfung (#22) lesen dieselbe Datei; `jq` ist ohnehin Pflicht-Werkzeug.
Nachteile: Lock enthält Felder, die der Ownership-Check nicht braucht; JSON lässt sich schlecht
von Hand diffen (aber `jq`-sortiert und zeilenweise formatierbar).

### Option B: TSV (`pfad<TAB>sha256`) plus Kopfzeilen
Vorteile: ohne `jq` per `awk` lesbar, zeilenweise diffbar.
Nachteile: zweites Format neben `factory-release.json`; #23 müsste das Manifest umwandeln;
Kopfzeilen (Repo/Tag/Commit) brauchen einen eigenen Parser.

### Option C: YAML
Vorteile: lesbar.
Nachteile: braucht `yq` im Konsumenten (Pin-Seam nötig, ADR-Guardrail), größere Parser-Fläche für
eine reine Pfadliste.

### Anpassungsstellen: Alternativen zu D4
- *In `OWNERSHIP.md` markieren:* im Konsumenten existiert die Tabelle nicht mehr.
- *In `factory.config.yml` führen:* verletzt das Ziel, dass das Projekt nichts pflegt.
- *Im Lock selbst:* Lock ist das Release-Manifest; ein zusätzliches Feld bräuchte ein neues
  Schema (`schema: 2`) und ändert den Vertrag für alle Konsumenten.

## Begründung

Option A hält die Zahl der Formate bei eins und macht die Reihenfolge #22 → #23 billig: #23 muss
nichts umwandeln. `jq` ist bereits Voraussetzung des Manifest-Erzeugers; im Konsumenten wird es
ohnehin für das Gate (#23) gebraucht. Fail-closed bei jedem unklaren Lock verhindert, dass ein
beschädigter Lock stillschweigend die Tabelle wieder einschaltet.

Die Anpassungsstellen-Liste ist eine Teilmenge der `project`-Zeilen, nicht deren Gleichheit: die
erste Fassung der Spec (AK2.15b-2) verlangte Übereinstimmung mit **allen** `project`-Zeilen und wäre
an `tasks/**`/`docs/specs/**` gescheitert. Der Drift-Guard prüft deshalb beide Richtungen einzeln.

## Konsequenzen

- #23 schreibt `factory.lock` als Kopie von `factory-release.json`; `jq` ist im Konsumenten Pflicht.
- Ein Konsument ohne `jq` bekommt im Lock-Modus Exit 2 mit klarer Meldung, nicht Exit 0.
- Jede neue Anpassungsstelle der Factory braucht eine Zeile in `customization-points.txt` und in
  `OWNERSHIP.md`; der Drift-Guard erzwingt beides.
- `OWNERSHIP.md` und `scripts/project/**` brauchen eine `project`-Zeile in `OWNERSHIP.md`
  (`scripts/project/**` hat bislang keine).
- Die Suite ist **aufgeteilt**, nicht verdoppelt: Gruppen, die das Factory-Repo voraussetzen, laufen nur noch in
  `scripts/project/tests/` (lokal über `pre-push.d/`, in CI als Job `project-self-test`). Vorher gehörten sie zum Required Check
  `factory-self-test`. **Das Gate-Niveau sinkt, bis `project-self-test` im Ruleset `protect-main` als Required Check geführt wird**
  (ADR-029; ADR-041 hat „Job, aber nicht required“ aus genau diesem Grund verworfen). Der Ruleset-Eintrag ist ein Admin-Schritt und
  wird als Folge-Issue verfolgt.
- Kopplung ausgelieferte Suite ↔ Projekt-Hook: Die ausgelieferte Suite ruft `pre-push.sh` echt gegen das Repo auf. Sie exportiert
  daher `FACTORY_SELF_TEST_RUN=1`; der Hook `10-project-tests.sh` startet die Projekt-Suite dann nicht (sonst läuft sie verschachtelt
  mehrfach, und ihr Rot färbte unbeteiligte Gate-Tests falsch rot). Im echten Push und im CI-Job ist die Variable nicht gesetzt.
- Der Drift-Guard (D4) liegt in der Projekt-Suite (`points_drift_22`), wird also **nicht ausgeliefert**: Er erzwingt die Deckung
  von Liste, `OWNERSHIP.md` und `PROJECT-CONTEXT.md` nur im Factory-Repo. Ein Konsument pflegt weder Tabelle noch Liste.
- Ein Konsument bringt die zusammengesetzten Dateien `.claude/settings.json` und `.gitignore` mit (Ergebnis von
  `factory-sync.sh --compose`); in `customization-points.txt` stehen nur ihre Fragmente. Die ausgelieferte Suite prüft ihre
  Zusammensetzung (AK-E3).
- Ein späteres Lock-Schema (`schema: 2`) muss `ownership-check.sh` bewusst unterstützen, sonst Exit 2.
- Verhalten im Tabellenmodus (Factory-Repo) ändert sich nicht (AK2.15c).

## Implementierungs-Hinweise

1. `ownership-check.sh`: nach der Argument-Auswertung `LOCK_FILE="${FACTORY_LOCK_FILE:-$FACTORY_DIR/factory.lock}"`;
   Lock-Zweig vor dem Lesen der Tabelle; im Tabellenmodus bleiben awk-Auswertung, Meldungen, Exit-Codes und die Reihenfolge der
   Fehlerklassen (Tabelle lesbar → Dateiliste) unverändert. Das Laden der Dateiliste liegt dafür in `load_tracked_files` und nutzt
   `git -c core.quotepath=false ls-files` (Nicht-ASCII-Pfade bleiben unquotet; wirkt auch im Tabellenmodus).
   Pfade aus `jq -r '.files[].path'`; Existenz gegen `TRACKED_FILES` (gleiche Quelle wie bisher,
   inkl. `OWNERSHIP_FILE_LIST`-Override für Tests).
2. Tests zuerst, je Fall ein Negativtest mit pfadspezifischem Signal (Lessons `testing.md`):
   Lock-Pfad fehlt / Anpassungsstelle im Lock / doppelter Pfad / unlesbarer Lock / `schema` ≠ 1 /
   `jq` fehlt (Stub im `PATH`, nicht nur Input) / Anpassungsstellen-Liste fehlt.
3. Test-Schnitt: zuerst Inventar (Testgruppe → Assertion-Zahl) in die Task-Datei, dann verschieben,
   dann Zählvergleich. Keine Datei in `scripts/checks/tests/` ändern, bevor das Inventar steht.
   Neue gesourcte Libs in allen Scaffoldings mitkopieren (Lesson #197); `source` relativ zum Skript
   (Lesson #431).
4. Eine neue Datei je Zeile in `OWNERSHIP.md` im selben PR (Seite `project` für `scripts/project/**`,
   `factory` für `customization-points.txt`).
5. Reihenfolge der Commits: (a) Lock-Modus mit Tests, (b) `OWNERSHIP.md` → `project`, (c) Test-Schnitt und (d) Verdrahtung
   `pre-push.d` + `ci.yml` – (c) und (d) liegen in einem Commit, weil die Wiring-Tests an derselben Projekt-Suite hängen. Jeder Commit
   hält `bash scripts/checks/tests/run-tests.sh` grün.

## Bezug zu anderen ADRs

- **ADR-063:** D5 kehrt eine Aussage aus dem Nachtrag zu T1a um – `docs/factory/OWNERSHIP.md` ist nicht mehr ausgelieferte
  Factory-Datei, sondern gehört dem Repo; ein Konsument bestimmt die Zuordnung über `factory.lock`. Das Manifest (ADR-063 Q1) und
  der lokale Gate-Lauf lesen weiter dieselbe Tabelle, aber nur im Factory-Repo.
- **ADR-029/ADR-041:** Der neue Job `project-self-test` ist erst mit dem Ruleset-Eintrag ein erzwungenes Gate (siehe Konsequenzen).
