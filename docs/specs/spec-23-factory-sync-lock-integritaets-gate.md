# Spec: Abholen, `factory.lock` und Integritäts-Gate – T2a-2

> **Teil-Task T2a-2** von `nothra/tch-gastro-services#428` (Epic `nothra/tch-gastro-services#424`).
> Kriterien-Quelle ist `spec-428-factory-versioniert-per-factory-lock-einbinden.md` im Ursprungs-Repo
> (Branch `feature/428-factory-split-t2-factory-lock-einbinden`, bis zum Merge dort). Hier stehen die
> Kriterien AK2.1a–c, AK2.2a–c, AK2.3, AK2.3b, AK2.5a–d, AK2.6, AK2.8, F2, F4, F7, FS-T2.1, FS-T2.2,
> FS-T2.4, verfeinert auf den Ist-Stand nach #22, plus die Erstabholung (AK2.2e) und der in #28 gefundene
> Rest des Konsumenten-Vertrags (AK-28a–c). Entscheidungen: Factory-ADR-063 D1, D3, D4 und
> Factory-ADR-064 D1–D4. Reihenfolge strikt A (#22) → **B (diese Task)** → C (#24) → Erst-Einbindung im
> ersten Konsumenten (`nothra/tch-gastro-services#428`).

## Kontext

Seit #22 kann ein Projekt einen `factory.lock` **lesen** (`ownership-check.sh` im Lock-Modus), aber
nichts **schreibt** ihn: Es gibt kein Werkzeug, das eine Version abholt, und kein Gate, das verhindert,
dass ein Projekt Factory-Dateien still ändert. `scripts/factory-sync.sh` kennt nur `--compose`
(Factory-ADR-063 Nachtrag T1a Q2: „T2 ergänzt die übrigen Modi").

Ohne diese Task gibt es keine Einbindung: Der erste Konsument hätte weder einen Weg zur Version noch
einen Schutz gegen Abdrift. Der Update-PR (#24) baut auf dem Abhol-Werkzeug dieser Task auf.

Dazu kommt ein Rest aus #22 (Einordnung in #28): Die ausgelieferte Self-Test-Suite prüft in den
Compose-Tests (#431 Gruppe E) den **Stand des Konsumenten** – sie verlangt dessen Projekt-Fragmente und
vergleicht seine committeten `settings.json`/`.gitignore` mit der Zusammensetzung. Ein Konsument, der
sein Fragment ändert und nicht neu zusammensetzt, bekäme `factory-self-test` rot, obwohl die Factory
korrekt arbeitet. Dieser Abgleich gehört ins Integritäts-Gate des Konsumenten, nicht in die Self-Tests
der Factory.

## Scope

**Inbegriffen:**
- `factory-sync.sh` lernt das **Abholen** einer Version: Tag aus dem Factory-Repo holen (öffentlich, ohne
  Token), jede Datei gegen das Release-Manifest `factory-release.json` prüfen, atomar übernehmen,
  `factory.lock` als Kopie des Manifests schreiben (Factory-ADR-064 D1), zusammengesetzte Dateien neu
  zusammensetzen. Bash 3.2, `shasum -a 256` bzw. `sha256sum`.
- **Erstabholung** in einem Repo ohne `factory.lock`: nur mit ausdrücklichem Schalter, wenn dort schon
  Factory-Dateien mit anderem Inhalt liegen (Entscheidung 2026-10-25, Q-23.5).
- `scripts/checks/factory-integrity-check.sh` (ausgeliefert): **lokale Stufe** (offline, in `pre-commit.sh`
  und `pre-push.sh`) und **CI-Stufe** (zusätzlich Lock gegen das Release-Manifest des Tags, CI-Job
  `factory-integrity` in `factory-ci.yml`). Im Factory-Repo selbst ein No-op mit Hinweis.
- Aus #28, Fundstelle (2): Compose-Tests der ausgelieferten Suite auf feste Fixtures umstellen; der
  Abgleich „committet == Zusammensetzung" wandert ins Integritäts-Gate; Factory-ADR-064 D6 um das
  Kriterium „prüft den Zustand projekteigener Dateien" ergänzen.
- Je neue Datei eine Zeile in `docs/factory/OWNERSHIP.md`.

**Nicht inbegriffen:**
- Update-Workflow `factory-update.yml`, Update-PR, `FACTORY_SYNC_TOKEN` (AK2.2d, AK2.4, AK2.4b, F1, F3,
  FS-T2.3 – T2a-3, #24).
- Ein Release. Das nächste Release `v0.7.0` erscheint nach #24, gemeinsam für #23 und #24
  (Entscheidung 2026-10-25, Q-23.4).
- Erst-Einbindung im ersten Konsumenten, `factory-integrity` als Required Check in dessen Ruleset,
  Entfernen von dessen `OWNERSHIP.md` (T2a-4, `nothra/tch-gastro-services#428`).
- `--init` für ein leeres neues Repo, Vorlagen der Anpassungsstellen, Fund-Ablage ins Factory-Repo
  (T2b, `nothra/tch-gastro-services#441`).
- `factory-integrity` als Required Check im Ruleset des Factory-Repos (dort ist der Check ein No-op).
- Fundstellen (1) und (3) aus #28 (Label-Drift-Guard, `factory.config.yml`): kein Fehler, bleiben
  unverändert.

## Akzeptanzkriterien

> Nummerierung folgt spec-428 (AK2.x); neu sind AK2.2e und AK-28a–c. „Beleg" nennt, womit der AK im Test
> nachgewiesen wird. Alle Tests laufen **offline** gegen ein Fixture-Factory-Repo (lokales Git-Repo mit
> Tags) und Fixture-Release-Manifeste; Netzzugriffe sind dafür umlenkbar (Seam, Detail in Q-23.1).

### Einbindung und Version

- [ ] **AK2.1a** GIVEN ein Repo nach einer Abholung WHEN man `factory.lock` liest THEN nennt es Quell-Repo,
  genau eine Version (Tag), den Commit-SHA und je übernommener Datei Pfad + SHA-256, und es ist inhaltlich
  gleich dem Release-Manifest der Version (Factory-ADR-064 D1). Die Versionszeile in
  `docs/factory/FACTORY.md` ist selbst eine übernommene Datei und nennt denselben Tag; eine zweite,
  abweichende Versionsangabe gibt es nicht. *Beleg: Test liest Lock + `FACTORY.md` nach einer Abholung.*
- [ ] **AK2.1b** GIVEN `factory.lock` WHEN das Gate läuft THEN entspricht jede übernommene Datei im
  Arbeitsbaum Byte für Byte dem eingetragenen Hash (lokale Stufe), und die Pfadmenge des Locks ist genau
  die Pfadmenge des Release-Manifests der Version (CI-Stufe). *Beleg: Test + Gegenprobe je Stufe (Datei
  ergänzt / Datei entfernt).*
- [ ] **AK2.1c** GIVEN ein Repo nach einer Abholung WHEN `ownership-check.sh` läuft THEN ist er im
  Lock-Modus grün: jeder Lock-Pfad ist getrackt, keiner ist eine Anpassungsstelle (Besitz ist eindeutig,
  Factory-ADR-063 D3; Prüfung selbst seit #22). *Beleg: Abholung im Fixture, danach Ownership-Check.*

### Abholen

- [ ] **AK2.2a** GIVEN eine veröffentlichte Version WHEN `factory-sync.sh` mit ihr aufgerufen wird THEN
  lädt es **den Tag** aus dem Factory-Repo ohne Token, prüft jede Datei gegen das Release-Manifest und
  schreibt `factory.lock` neu.
- [ ] **AK2.2b** (F4) GIVEN der Lauf bricht an irgendeiner Stelle ab (Netz, Hash-Abweichung,
  Schreibfehler) WHEN man den Arbeitsbaum ansieht THEN ist **nichts** verändert – weder übernommene
  Dateien noch `factory.lock` noch zusammengesetzte Dateien. *Beleg: je Abbruchstelle ein Test, der die
  Messung bricht (Stub im `PATH` für Download- und Hash-Werkzeug, nicht beschreibbares Ziel) – Lesson
  aus `nothra/tch-gastro-services#319`.*
- [ ] **AK2.2c** GIVEN eine Datei steht im alten Lock, aber nicht im neuen Manifest WHEN abgeholt wird THEN
  wird sie gelöscht; GIVEN eine Datei steht neu im Manifest THEN wird sie angelegt. Dateien, die weder im
  alten Lock noch im Manifest stehen, bleiben unberührt (z. B. `docs/factory/OWNERSHIP.md`, die seit #22
  nicht mehr ausgeliefert wird – Q-22.5).
- [ ] **AK2.2e** GIVEN ein Repo **ohne** `factory.lock`, in dem Dateien an Manifest-Pfaden mit anderem
  Inhalt liegen WHEN ohne Schalter abgeholt wird THEN bricht die Abholung ab, nennt jede abweichende Datei
  und ändert nichts; WHEN mit dem ausdrücklichen Schalter abgeholt wird THEN übernimmt sie die Version und
  gibt die Liste der überschriebenen Dateien aus. Ohne abweichende Dateien braucht es keinen Schalter.
  In einem Repo **mit** `factory.lock` wird der Schalter abgelehnt (F2 bleibt unumgehbar,
  ADR-063 Nachtrag E3). *Beleg: vier Tests (ohne Schalter, mit Schalter, ohne Abweichung, Schalter mit
  Lock).*
- [ ] **AK2.3** GIVEN eine Abholung WHEN man die geänderten Dateien ansieht THEN ist keine Anpassungsstelle
  darunter (`scripts/checks/customization-points.txt`) und kein Pfad in einem Projektbereich
  (`scripts/project/`, `docs/project/`, `docs/adr/`, `docs/specs/`, `tasks/` – Factory-ADR-063
  Nachtrag E6). *Beleg: Fixture mit allen Stellen, Hashes vor/nach gleich.
  Gegenprobe: ein Manifest, das eine Anpassungsstelle liefern würde, wird **abgelehnt**, nichts
  geändert.*
- [ ] **AK2.3b** GIVEN die zusammengesetzten Dateien (`.claude/settings.json`, `.gitignore`) WHEN abgeholt
  wird THEN werden sie aus den dann aktuellen Fragmenten neu zusammengesetzt (bestehender Modus
  `--compose`), und der Lauf endet nur grün, wenn das Ergebnis den Fragmenten entspricht. *Beleg: Factory-
  Fragment ändert sich zwischen zwei Fixture-Versionen, danach enthält die zusammengesetzte Datei die
  Änderung.*

### Integritäts-Gate

- [ ] **AK2.5a** (F7) GIVEN eine übernommene Datei wird lokal geändert **oder gelöscht** WHEN committet
  oder gepusht wird THEN lehnt die lokale Stufe ab (offline), nennt die Datei und den Hinweis
  „Änderung gehört nach `nothra/dev-factory`". *Beleg: je ein Test für Änderung und Löschung, mit
  Dateinamen im Signal; Wiring-Test an der echten Aufrufzeile in `pre-commit.sh` und `pre-push.sh`.*
- [ ] **AK2.5b** GIVEN dieselbe Änderung kommt per PR (Hook umgangen) WHEN CI läuft THEN schlägt der
  Job `factory-integrity` fehl. Er greift auch, wenn **Datei und Hash im Lock gemeinsam** geändert wurden,
  weil die CI-Stufe den Lock gegen das Release-Manifest des eingetragenen Tags prüft. *Beleg: Test mit
  umgelenktem Factory-Repo-Zugriff + Mutationsbeleg (Manifest-Vergleich weglassen → Test rot); Wiring-Test
  für den Job in `factory-ci.yml`.*
- [ ] **AK2.5c** GIVEN das Gate läuft im **Factory-Repo selbst** (kein `factory.lock`) WHEN es aufgerufen
  wird THEN ist es ein No-op mit Hinweis und Exit 0 – lokal wie in CI.
- [ ] **AK2.5d** GIVEN das Factory-Repo ist für die CI-Stufe nicht erreichbar, oder Tag bzw. Manifest
  fehlen dort WHEN `factory-integrity` läuft THEN schlägt er **fail-closed** fehl (nicht still grün), mit
  klarer Meldung; die lokale Stufe bleibt offline nutzbar. *Beleg: Stub, der den Download scheitern
  lässt.*
- [ ] **AK2.6** GIVEN ein Repo wird per Abholung von Version N auf N+1 gehoben WHEN beide Stufen des Gates
  laufen THEN bestehen sie (Version, Hashes und Dateien konsistent auf einem echten Tag); die Hebung wird
  nicht als „lokale Änderung" abgelehnt. *Beleg: Fixture mit zwei Tags.*
- [ ] **F2** GIVEN im Repo mit Lock ist eine übernommene Datei lokal geändert WHEN abgeholt wird THEN
  meldet `factory-sync.sh` die Datei und bricht ab, bevor irgendetwas geschrieben wird: kein stilles
  Überschreiben, kein stilles Behalten.

### Offline-Betrieb

- [ ] **AK2.8** GIVEN das Factory-Repo ist nicht erreichbar WHEN im Projekt entwickelt, committet und
  gepusht wird THEN laufen lokale Stufe des Gates, `ownership-check.sh` und `--compose` wie gewohnt;
  betroffen sind nur Abholung und CI-Stufe, beide mit klarem Fehler und ohne halbe Aktualisierung.
  *Beleg: lokale Stufe mit Download-Stubs, die jeden Netzzugriff scheitern lassen, ist grün.*

### Konsumenten-Vertrag, Rest aus #28

- [ ] **AK-28a** GIVEN ein Repo mit eingebundener Factory, dessen Projekt-Fragmente
  (`.claude/settings.project.json`, `.gitignore.project`) eigene Inhalte haben oder fehlen WHEN die
  ausgelieferte Self-Test-Suite läuft THEN sind die Compose-Tests grün: Sie bauen ihre Projekt-Fragmente
  selbst (feste Fixtures) und lesen keine Projekt-Fragmente und keine committeten zusammengesetzten Dateien
  des echten Repos. Die Mutations- und Fail-closed-Fälle (F-4, fehlendes Fragment) bleiben erhalten.
  *Beleg: Fixture-Lauf der Suite mit verändertem und mit fehlendem Projekt-Fragment.*
- [ ] **AK-28b** GIVEN ein Repo mit `factory.lock`, dessen committete `.claude/settings.json` oder
  `.gitignore` von der Zusammensetzung der Fragmente abweicht WHEN die lokale Stufe des Gates läuft THEN
  lehnt sie ab und nennt die Datei (Abgleich wie `factory-sync.sh --compose --check`). Die bisherigen
  Prüfungen am echten Factory-Repo (Fragmente vorhanden, committet == Zusammensetzung) laufen weiter, in
  der Projekt-Suite `scripts/project/tests/run-tests.sh`; keine entfällt ersatzlos. *Beleg: Mutation je
  Datei; Vorher/Nachher-Liste der verschobenen Assertions in Task-Datei und PR.*
- [ ] **AK-28c** GIVEN Factory-ADR-064 D6 WHEN man das Kriterium „Factory-Repo-spezifisch" liest THEN
  umfasst es auch Gruppen, die **den Zustand projekteigener Dateien des echten Repos prüfen** (Vorhandensein
  oder Inhalt von z. B. `.gitignore.project`, `.claude/settings.project.json`, `PROJECT-CONTEXT.md`); das
  Lesen einer Factory-Datei oder eine Mutation auf einer Kopie zählt nicht dazu.

## Fehlerszenarien

- [ ] **FS-T2.1** Das Release-Manifest fehlt, ist kein gültiges JSON oder hat ein unbekanntes `schema` →
  Abbruch mit klarer Meldung, nichts geändert (Abholung und CI-Stufe).
- [ ] **FS-T2.2** Der Hash einer heruntergeladenen Datei weicht vom Release-Manifest ab (Manipulation oder
  Übertragungsfehler) → Abbruch mit Dateinamen, nichts geändert.
- [ ] **FS-T2.4** Ein Tag existiert, hat aber kein Release oder kein Manifest-Asset → wird nicht
  eingebunden, der Lauf meldet es.
- [ ] **F-23.1** Manifest und Tag widersprechen sich (Manifest-`version` ≠ angeforderter Tag, `commit` ≠
  Commit des Tags, `repo` ≠ Quell-Repo) → Abbruch, nichts geändert.
- [ ] **F-23.2** `factory.lock` ist vorhanden, aber unlesbar oder kein gültiges JSON → lokale Stufe und
  Abholung brechen fail-closed ab (Exit ≠ 0), kein Rückfall auf „kein Lock = No-op".
- [ ] **F-23.3** Ein Manifest-Pfad ist absolut oder enthält `..` → Abbruch vor jedem Schreiben (kein
  Schreiben außerhalb des Repos).

## Offene Fragen

> Q-23.1 bis Q-23.3 sind in `/architecture` entschieden: Factory-ADR-063, Nachtrag 2026-10-25 (E1–E9).

- [x] **Q-23.1 · Transport und Aufruf:** → `git clone --depth 1 --branch <tag>` + Manifest per `curl` vom
  Release-Asset, Test-Seams `FACTORY_UPSTREAM_GIT_URL`/`FACTORY_RELEASE_BASE_URL` (E1); Quell-Repo aus
  `upstream.repo` (Default `nothra/dev-factory`), das Feld `repo` im Lock muss ihm gleichen (E2); Aufruf
  `factory-sync.sh <version> [--adopt]` (E3).
- [x] **Q-23.2 · Schutz der Anpassungsstellen:** → feste Liste der Projektbereiche in
  `scripts/lib/factory-lock.sh`, getrennt von `customization-points.txt`; ADR-064 D4 bleibt (E6).
- [x] **Q-23.3 · Zusammengesetzte Dateien im Lock:** → ADR-064 D1 gilt (Lock ohne `composed`); die lokale
  Gate-Stufe prüft sie über `--compose --check` (E7, AK-28b).
- [x] **Q-23.4 · Release:** → in #23 kein Release; `v0.7.0` erscheint nach #24 für beide Tasks
  (entschieden 2026-10-25). Der Issue-Text von #23 („Je Factory-Task ein Release", „Voraussetzung: A ist
  released") wird angepasst.
- [x] **Q-23.5 · Erstabholung ohne Lock:** → nur mit ausdrücklichem Schalter, sonst Abbruch mit Liste der
  abweichenden Dateien (entschieden 2026-10-25, AK2.2e).
- [x] **Q-23.6 · Größe:** → bleibt ein PR. 19 Kriterien + 6 Fehlerszenarien; laut ADR-063 Nachtrag E1–E9
  rund 20 betroffene Dateien (2 neu), deutlich unter der Schwelle von 40 Dateien (Lesson
  `nothra/tch-gastro-services#369`).

## Zuordnung zu spec-428

| spec-428 | Hier |
|---|---|
| AK2.1a–c, AK2.2a–c, AK2.3, AK2.3b | gleich (verfeinert) |
| AK2.5a–d, AK2.6, AK2.8 | gleich (AK2.6 ohne Update-PR: Hebung per Abholung) |
| F2, F4, F7 | F2; F4 → AK2.2b; F7 → AK2.5a |
| FS-T2.1, FS-T2.2, FS-T2.4 | gleich |
| neu | AK2.2e, AK-28a–c, F-23.1–F-23.3 |
