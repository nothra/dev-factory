# Spec: Runtime-Token des `fetch`-Jobs gegen Release-Code abschirmen

## Kontext

Der Workflow `.github/workflows/factory-update.yml` holt täglich eine neue Factory-Version ab
(Factory-ADR-063, Nachtrag 2026-10-31 E17–E22, Spec #37). Im Job `fetch` läuft dabei Code des
**noch ungeprüften** Release (`factory-sync.sh` ersetzt sich selbst und startet in der neuen Fassung).
`FACTORY_SYNC_TOKEN` liegt in diesem Job nicht vor; das ist durch #37 gelöst.

Offen ist das **Runtime-Token des Laufs** (`ACTIONS_RUNTIME_TOKEN`), das jeder Job hat. Es kann keinen Code
pushen, aber **Caches im Scope des Standard-Branches `main` schreiben**, und `pull_request`-Workflows lesen diese
Caches. Ein bösartiges Release könnte so Caches vergiften, die Prüfläufe späterer PRs ungeprüft verwenden.

Das Issue (aus dem Security-Review zu #37) nennt einen Weg: Release-Code schreibt über `$GITHUB_ENV` oder
`$GITHUB_PATH` in die Umgebung des Folgeschritts `actions/upload-artifact`, der das Token trägt. Bei der Analyse
für diese Spec kam ein zweiter, schwerer wiegender Weg dazu: Auf GitHub-gehosteten Runnern hat der Benutzer
`runner` **passwortloses `sudo`**. Release-Code kann das Token damit direkt aus dem Speicher des Prozesses
`Runner.Worker` lesen. Diese Cache-Poisoning-Technik ist öffentlich beschrieben. Den Folgeschritt herauszunehmen
schließt also nur den ersten Weg.

Die Aussage in ADR-063 E17 („`sudo` bleibt auf einem Wegwerf-Runner wirkungslos“) stimmt für `FACTORY_SYNC_TOKEN`,
nicht aber für das Runtime-Token des Laufs.

**Entscheidung (Mensch, 2026-11-20):** Release-Code läuft in einer echten Isolationsgrenze, einem unprivilegierten
Container. Nachweis über Offline-Tests wie bei #37, ohne Live-Angriffsversuch.

Betroffen sind nur Konsumenten, die Caches verwenden (`actions/cache`, `setup-*` mit `cache`). Das Factory-Repo
selbst nutzt keine. Der Angriff ist nicht praktisch nachgestellt.

## Scope

**Inbegriffen:**
- Im Job `fetch` läuft der gesamte Release-Code (Abholung, Commit, Bundle) in einem Container ohne Sonderrechte.
  Der Container hat keinen Zugriff auf Host-Prozesse, auf die Runner-Dateien (`$GITHUB_ENV`, `$GITHUB_PATH`,
  `$GITHUB_OUTPUT`, `$GITHUB_STEP_SUMMARY`) und auf das Runtime-Token. Aus dem Container zurück kommt nur die
  Bundle-Datei.
- Nach dem Container führt der Host nichts aus dem vom Release-Code beschriebenen Verzeichnis aus und ruft dort
  kein `git` auf. Er reicht nur die Bundle-Datei an `actions/upload-artifact` weiter.
- Ein neuer Nachtrag in Factory-ADR-063: Entscheidung, Alternativen, Restrisiko. Dazu eine Korrektur der
  `sudo`-Aussage in E17 (Verweis auf den Nachtrag).
- `docs/factory/OPERATING.md` §0.6 („Aufbau des Workflows“): Isolation und Restrisiko für Konsumenten mit Caches.
- Wiring-Tests an der echten `factory-update.yml` mit Mutationsbelegen (Muster aus #37, `factory-lock-37a-tests.sh`).

**Nicht inbegriffen:**
- Live-Nachweis am echten Runner (bewusst verworfen, siehe Kontext).
- Änderungen an `guard`, `preflight` und `publish` und an der Prüfliste des Bundles (E18).
- Kurzform von `factory-update.sh` (lokal/Tests). Sie läuft weiter ohne Container, in CI wird sie weiter verweigert.
- Unterstützung selbst gehosteter Runner ohne Docker (dort schlägt `fetch` fail-closed fehl, siehe Fehlerszenarien).
- Kurzlebiges GitHub-App-Token statt PAT (ADR-063 E17 Alternative D, eigenes Thema).
- Abwehr eines bösartigen Release, das der Mensch im Update-PR übersieht (Restrisiko 1 aus E17–E22, unverändert).

## Akzeptanzkriterien

### AK1 · Isolation des Release-Codes

- [ ] **AK1.1** GIVEN der Job `fetch` WHEN er die neue Version abholt THEN laufen `factory-sync.sh`, der Commit und
  `git bundle create` ausschließlich innerhalb eines Containers; außerhalb läuft in diesem Job kein Code aus dem
  Release.
- [ ] **AK1.2** GIVEN der Container-Aufruf WHEN man seine Optionen prüft THEN fehlen alle Sonderrechte: kein
  `--privileged`, kein `--pid=host`, kein `--network=host`, kein `--ipc=host`, kein `--cap-add`, kein eingebundener
  Docker-Socket. Zusätzlich sind `--cap-drop ALL` und `--security-opt no-new-privileges` gesetzt.
- [ ] **AK1.3** GIVEN der Container-Aufruf WHEN man prüft, welche Umgebung und Dateien er erhält THEN bekommt er
  keine `ACTIONS_*`-, `GITHUB_TOKEN`- oder Token-Variablen, kein `--env-file` und keine der Runner-Dateien
  `$GITHUB_ENV`, `$GITHUB_PATH`, `$GITHUB_OUTPUT`, `$GITHUB_STEP_SUMMARY` (weder als Variable noch eingebunden).
  Eingebunden sind nur ein eigens angelegtes Arbeitsverzeichnis und ein eigenes Ausgabeverzeichnis für das Bundle.
- [ ] **AK1.4** GIVEN das Container-Image WHEN der Workflow es startet THEN ist seine Basis per Digest (`@sha256:…`)
  gepinnt. Das Image wird vor jedem Release-Code nur aus Code von `main` gebaut, ohne Build-Kontext aus dem
  Arbeitsbaum (Factory-ADR-063 E30).

### AK2 · Rückweg nur als Daten

- [ ] **AK2.1** GIVEN der Container ist beendet WHEN der Job weiterläuft THEN folgt ihm nur der Upload der
  Bundle-Datei (`actions/upload-artifact`, `path` im Ausgabeverzeichnis). Kein Schritt nach dem Container ruft `git`
  im vom Container beschriebenen Verzeichnis auf oder führt eine Datei daraus aus.
- [ ] **AK2.2** GIVEN Release-Code, der `.git/config` (`core.fsmonitor`) oder Hooks im Arbeitsverzeichnis verändert
  WHEN der Job `fetch` endet THEN wird diese Veränderung auf dem Host nie ausgeführt (folgt aus AK2.1; die
  Verhaltensprüfung von E22 (b) bleibt grün).

### AK3 · Unverändertes Ergebnis

- [ ] **AK3.1** GIVEN eine neuere Factory-Version WHEN der Workflow durchläuft THEN entsteht dasselbe Bundle wie
  bisher: ein Commit auf `base_sha`. `publish` übernimmt es ohne Änderung und legt den Update-PR wie bisher an bzw.
  pflegt ihn.
- [ ] **AK3.2** GIVEN die bestehenden Tests zu #23/#24/#37 WHEN die Suite läuft THEN bleiben sie grün. Geänderte
  Anker an der `fetch`-Struktur werden durch mindestens gleich strenge ersetzt (kein ersatzloses Entfernen).

### AK4 · Tests

- [ ] **AK4.1** GIVEN die echte `factory-update.yml` WHEN die Wiring-Tests laufen THEN prüfen sie AK1.1–AK1.4 und
  AK2.1 per `yq`/Textprüfung. Docker ist dafür nicht nötig (lokal unter macOS und in CI lauffähig).
- [ ] **AK4.2** GIVEN je eine tragende Eigenschaft (Release-Code außerhalb des Containers, `--privileged`,
  eingebundener Docker-Socket, `--pid=host`, `--network=host`, durchgereichte Runner-Datei oder `ACTIONS_*`-Variable,
  Image ohne Digest, Schritt nach dem Container, der im Arbeitsverzeichnis arbeitet) WHEN sie per Mutation verletzt
  wird THEN schlägt mindestens ein Test fehl.

### AK5 · Dokumentation

- [ ] **AK5.1** GIVEN Factory-ADR-063 WHEN man es liest THEN beschreibt ein neuer Nachtrag (#41) beide Wege zum
  Runtime-Token, die Container-Entscheidung, die verworfenen Alternativen (nur Doku; nur Folgeschritt trennen) und
  das verbleibende Restrisiko. E17 verweist bei der `sudo`-Aussage auf den Nachtrag.
- [ ] **AK5.2** GIVEN `docs/factory/OPERATING.md` §0.6 WHEN ein Konsument den Abschnitt „Aufbau des Workflows“ liest
  THEN erfährt er, dass `fetch` den Release-Code im Container ausführt, dass der Job deshalb Docker auf dem Runner
  braucht (GitHub-gehostet: vorhanden) und welches Restrisiko für Caches bleibt.

- [ ] **AK4.3** GIVEN der CI-Workflow `factory-ci.yml` WHEN er läuft THEN baut ein Smoke-Job das Image echt und
  startet es mit den echten Optionen und einem harmlosen Kommando (Werkzeuge vorhanden, `/out` beschreibbar). Kein
  Angriffsversuch, kein Release (Factory-ADR-063 E34 f; ergänzt in `/architecture`, weil der Container-Pfad sonst erst
  beim Konsumenten zum ersten Mal liefe).

## Fehlerszenarien

- [ ] **F1** Docker auf dem Runner nicht verfügbar (z. B. selbst gehostet) → `fetch` endet rot mit verständlicher
  Meldung, kein Artefakt, `publish` läuft nicht. Ein stiller Rückfall auf Ausführung ohne Container ist verboten
  (fail-closed).
- [ ] **F2** Image nicht ladbar oder Digest passt nicht → `fetch` rot, nichts gepusht.
- [ ] **F3** Release-Code im Container scheitert oder erzeugt kein Bundle → `fetch` rot
  (`if-no-files-found: error` bleibt), `publish` läuft nicht.
- [ ] **F4** Release-Code legt statt der Bundle-Datei einen Symlink oder ein Verzeichnis ins Ausgabeverzeichnis →
  der Upload übernimmt nichts von außerhalb des Ausgabeverzeichnisses. Ein manipuliertes Bundle fängt weiter die
  Prüfliste in `publish` (E18).

## Offene Fragen (für `/architecture`)

Alle geklärt in Factory-ADR-063, Nachtrag 2026-11-20 (E28–E34):

- [x] **Q1** Image: lokal gebaut aus `debian:<stable>-slim@sha256:…` per Heredoc ohne Kontext, `git jq curl
  ca-certificates` per `apt`; `yq` als verifizierte Host-Binary read-only eingebunden (E30).
- [x] **Q2** Ort: neuer Modus `factory-update.sh fetch-isolated`; `fetch` verweigert in CI (E29).
- [x] **Q3** Netz: Standard-Bridge, keine weitere Einschränkung (E31).
- [x] **Q4** Benutzer: UID/GID des Runners, kein root; Checkout read-only, Arbeitskopie im Container (E31).
- [x] **Q5** Restwege: Container-Ausbruch, Netz, Image-Lieferkette, übersehenes bösartiges Release (Restrisiko im
  Nachtrag).
