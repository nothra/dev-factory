# Spec: Fetch-Container vom Host-Gateway und von Link-Local-Diensten abschotten

## Kontext

Seit #41 läuft der Release-Code im Job `fetch` von `.github/workflows/factory-update.yml` in einem Container ohne
Sonderrechte (`factory-update.sh fetch-isolated`, Factory-ADR-063 E28–E34). Der Container ist über Umgebung, Dateien und
Mounts vom Runtime-Token des Laufs getrennt. Beim Netz gibt es diese Trennung nicht: Der Container hängt im
Standard-Bridge-Netz (E31, Q3 damals bewusst so entschieden) und erreicht alles, was der Runner erreicht.

Der Security-Review zu #41 (`tasks/security-41.md`, Hinweis „Netz“) zählt dazu auf:
- das **Bridge-Gateway des Hosts** (z. B. `172.17.0.1`), über das Dienste des Runners selbst erreichbar sind,
- die **Link-Local-Dienste der Cloud**, insbesondere den Metadaten-Endpunkt (Azure IMDS) `169.254.169.254`,
- den **Azure-WireServer** `168.63.129.16`. Die Azure-Regel, die ihn nur für root freigibt, greift vermutlich nicht für
  weitergeleiteten Container-Verkehr (Annahme, nicht verifiziert).

Ein Weg zu `ACTIONS_RUNTIME_TOKEN` über diese Dienste ist nicht bekannt. Trotzdem sind sie unnötige Angriffsfläche für
feindlichen Release-Code: Die Abholung braucht nur das öffentliche Internet (Release-Assets auf GitHub), keinen
dieser Dienste. Restrisiko 2 im ADR-Nachtrag zu #41 nennt das Netz nur pauschal.

**Entscheidungen (Mensch, 2026-11-21):**
- Zielmenge: Bridge-Gateway, IPv4-Link-Local `169.254.0.0/16`, Azure-WireServer `168.63.129.16`, IPv6-Link-Local
  `fe80::/10`. Private Netze (RFC1918) bleiben erreichbar.
- Nachweis: Offline-Guard-Tests mit Mutationsbeleg **und** eine harmlose Probe im CI-Smoke-Job (die gesperrten Ziele
  sind unerreichbar, das Internet bleibt erreichbar). Das ist kein Angriffsversuch und kein Release-Code.
- Lässt sich die Sperre nicht einrichten, endet der Lauf fail-closed (rot).

Damit gilt E31 Q3 („Standard-Bridge, keine weitere Einschränkung, verworfen“) nicht mehr. Das erfordert einen
ADR-Nachtrag (`/architecture`).

## Scope

**Inbegriffen:**
- Jeder Start des Fetch-Containers (`fetch-isolated` und `fetch-smoke`, beide über die eine Stelle in
  `scripts/factory-update.sh`) läuft mit Netz-Sperre für die oben genannte Zielmenge.
- Ausgehender Verkehr ins öffentliche Internet bleibt möglich (DNS-Auflösung und HTTPS zu GitHub), die Abholung
  funktioniert unverändert.
- Fail-closed: Die Sperre wird **vor** jedem Release-Code eingerichtet und wirkt. Lässt sie sich nicht einrichten, startet
  kein Container.
- Offline-Guard-Tests an Skript und Workflow mit Mutationsbelegen (Muster aus #41, `factory-lock-41-tests.sh`).
- Probe im CI-Job `fetch-container-smoke` (`.github/workflows/factory-ci.yml`).
- Doku: ADR-063-Nachtrag (Entscheidung, Alternativen, Restrisiko; Korrektur von E31 Q3 und Restrisiko 2),
  `docs/factory/OPERATING.md` §0.6 (Voraussetzung und Restrisiko für Konsumenten), Verweis in `tasks/security-41.md`.

**Nicht inbegriffen:**
- Sperre privater Netze (RFC1918) und eine Allowlist nur für GitHub-Hosts (bewusst verworfen, siehe Kontext).
- Schutz vor Datenabfluss ins Internet (Restrisiko 2 aus E17–E22, unverändert: der Container darf ins Internet).
- Netz-Sperre für andere Jobs (`guard`, `preflight`, `publish`) oder für die Kurzform von `factory-update.sh` ohne
  Container.
- Unterstützung selbst gehosteter Runner, auf denen sich die Sperre nicht einrichten lässt (dort `fetch` rot, siehe F1).
- Die übrigen Findings aus `tasks/security-41.md` (W1 stdout-Kanal, Ressourcen-DoS, Nitpicks).

## Akzeptanzkriterien

### AK1 · Sperre wirkt

- [ ] **AK1.1** GIVEN der Fetch-Container läuft (`fetch-isolated` oder `fetch-smoke`) WHEN Code im Container eine
  Verbindung zum Bridge-Gateway des Hosts aufbaut (beliebiger Port, TCP und UDP) THEN kommt sie nicht zustande.
- [ ] **AK1.2** GIVEN der Fetch-Container läuft WHEN Code im Container eine Verbindung zu einer Adresse aus
  `169.254.0.0/16` aufbaut (insbesondere `169.254.169.254`) THEN kommt sie nicht zustande.
- [ ] **AK1.3** GIVEN der Fetch-Container läuft WHEN Code im Container eine Verbindung zu `168.63.129.16` aufbaut THEN
  kommt sie nicht zustande.
- [ ] **AK1.4** GIVEN der Fetch-Container läuft WHEN Code im Container eine Verbindung zu einer Adresse aus `fe80::/10`
  aufbaut THEN kommt sie nicht zustande. (Hat der Container gar kein IPv6, ist das erfüllt.)
- [ ] **AK1.5** GIVEN Release-Code im Container WHEN er die Sperre von innen aufheben will THEN gelingt das nicht. Die
  Sperre liegt außerhalb dessen, was der Container mit seinen Rechten (`--cap-drop ALL`, `no-new-privileges`,
  Runner-UID) verändern kann.

### AK2 · Abholung funktioniert weiter

- [ ] **AK2.1** GIVEN der Fetch-Container mit Sperre WHEN er Namen auflöst und per HTTPS GitHub erreicht THEN gelingt
  das. `fetch-isolated` erzeugt dasselbe Bundle wie bisher (AK3.1 aus #41 bleibt erfüllt).
- [ ] **AK2.2** GIVEN die bestehenden Tests zu #23/#24/#37/#41 WHEN die Suite läuft THEN bleiben sie grün. Geänderte
  Anker am `docker run`-Aufruf (exakter Vergleich, Verbots-Prüfer) werden durch mindestens gleich strenge ersetzt; die
  übrigen Verbote aus E31 (u. a. kein `--network=host`, kein `--cap-add`) gelten weiter.

### AK3 · Fail-closed

- [ ] **AK3.1** GIVEN die Sperre lässt sich auf dem Runner nicht einrichten WHEN `fetch-isolated` startet THEN endet es
  rot mit verständlicher Meldung, bevor ein Container startet. Kein Artefakt, `publish` läuft nicht. Ein stiller
  Rückfall auf einen Container ohne Sperre ist verboten.
- [ ] **AK3.2** GIVEN dasselbe WHEN `fetch-smoke` startet THEN endet auch der Smoke-Job rot.

### AK4 · Tests

- [ ] **AK4.1** GIVEN `scripts/factory-update.sh` und die echten Workflows WHEN die Offline-Guard-Tests laufen (ohne
  Docker, lokal unter macOS und in CI) THEN prüfen sie: Die Sperre umfasst alle vier Ziele aus AK1, sie wird vor dem
  Container-Start eingerichtet, beide Modi starten nur mit Sperre, und ein Fehler beim Einrichten bricht ab (AK3).
- [ ] **AK4.2** GIVEN je eine tragende Eigenschaft (eines der vier Ziele fehlt, Sperre erst nach dem Container-Start,
  ein Modus ohne Sperre, Fehler beim Einrichten wird ignoriert) WHEN sie per Mutation verletzt wird THEN schlägt
  mindestens ein Test fehl.
- [ ] **AK4.3** GIVEN der CI-Job `fetch-container-smoke` WHEN er läuft THEN prüft er im echten Container mit den echten
  Optionen: Verbindungen zum Bridge-Gateway, zu `169.254.169.254` und zu `168.63.129.16` scheitern, eine
  HTTPS-Verbindung zu `github.com` gelingt. Jede Abweichung macht den Job rot. Kein Angriffsversuch, kein Release.

### AK5 · Dokumentation

- [ ] **AK5.1** GIVEN Factory-ADR-063 WHEN man es liest THEN beschreibt ein neuer Nachtrag (#66) die Netz-Sperre, die
  Zielmenge, die verworfenen Alternativen (keine Sperre, zusätzlich RFC1918, Allowlist nur GitHub) und das
  verbleibende Restrisiko. E31 Q3 und Restrisiko 2 aus dem Nachtrag zu #41 verweisen auf den neuen Nachtrag.
- [ ] **AK5.2** GIVEN `docs/factory/OPERATING.md` §0.6 WHEN ein Konsument „Aufbau des Workflows“ liest THEN erfährt er,
  dass `fetch` den Container vom Host-Gateway und von Link-Local-Diensten abschottet, welche Voraussetzung der Runner
  dafür erfüllen muss (GitHub-gehostet: erfüllt) und dass `fetch` sonst rot wird.
- [ ] **AK5.3** GIVEN `tasks/security-41.md` WHEN man den Hinweis „Netz“ liest THEN verweist er auf #66 (offene
  Ablage-Zeile wird durch die Issue-Nummer ersetzt).

## Fehlerszenarien

- [ ] **F1** Sperre nicht einrichtbar (fehlende Rechte, fehlendes Werkzeug, selbst gehosteter Runner) → `fetch` bzw.
  `fetch-smoke` rot mit verständlicher Meldung, kein Container, kein Artefakt (AK3).
- [ ] **F2** Das Bridge-Gateway lässt sich nicht ermitteln → wie F1, fail-closed (keine Sperre „ohne Gateway“).
- [ ] **F3** Die Sperre bricht die Abholung (z. B. DNS über eine gesperrte Adresse) → der Smoke-Job wird rot (AK4.3),
  bevor ein Konsument betroffen ist.
- [ ] **F4** Eine Sperre aus einem früheren Lauf ist auf einem langlebigen Runner noch vorhanden → das Einrichten ist
  wiederholbar und schlägt deswegen nicht fehl. Andere Container oder Dienste auf dem Runner werden durch die Sperre
  nicht dauerhaft beeinträchtigt.

## Offene Fragen (für `/architecture`)

Alle geklärt in Factory-ADR-063, Nachtrag 2026-11-21 (E35–E40):

- [x] **Q1** Mechanismus: eigenes Docker-Netz `factory-fetch` mit Bridge `factory-fetch0`, Regeln auf dem Host per
  `sudo -n iptables`: `INPUT` sperrt den Host ganz, `DOCKER-USER` sperrt `169.254.0.0/16` und `168.63.129.16` (E35, E36).
  Offline belegt mit Fake-`docker`/`sudo`/`iptables` (E40 a, b).
- [x] **Q2** Geltung nur für die Schnittstelle des Fetch-Containers; idempotent anlegen, nach dem Lauf per `trap`
  abräumen (E35, E38).
- [x] **Q3** DNS läuft auf Azure über `168.63.129.16`; dort bleibt nur Port 53 (UDP/TCP) frei (E36, Restrisiko 2).
- [x] **Q4** IPv6 im Container per `--sysctl net.ipv6.conf.all.disable_ipv6=1` aus, Netz ohne IPv6; belegt durch die
  Smoke-Probe (E37, E40 c).
- [x] **Q5** `curl --retry` gegen kurze Aussetzer; bleibt `github.com` unerreichbar, wird der Smoke-Job rot (E40 c).

**Präzisierung aus `/architecture`:** F2 (Gateway nicht ermittelbar) entfällt für die Sperre: Die Regel hängt an der
Schnittstelle, nicht an der Adresse (E39). Die Gateway-Adresse braucht nur noch die Smoke-Probe; ist sie dort nicht
ermittelbar, wird der Smoke-Job rot.
