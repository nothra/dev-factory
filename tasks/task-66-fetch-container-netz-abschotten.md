# Task 66: fetch-container-netz-abschotten

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Der Fetch-Container aus #41 (`factory-update.sh fetch-isolated`/`fetch-smoke`) soll das Bridge-Gateway des Hosts,
IPv4-Link-Local `169.254.0.0/16` (IMDS), den Azure-WireServer `168.63.129.16` und IPv6-Link-Local `fe80::/10` nicht mehr
erreichen. Das öffentliche Internet bleibt erreichbar. Lässt sich die Sperre nicht einrichten: fail-closed.
Spec: [`docs/specs/spec-66-fetch-container-netz-abschotten.md`](../docs/specs/spec-66-fetch-container-netz-abschotten.md).
ADR-Trigger: kehrt Factory-ADR-063 E31 Q3 um → `/architecture` vor `/implement`.

## Akzeptanzkriterien
<!-- Volltext in der Spec -->
- [ ] AK1.1 Bridge-Gateway des Hosts aus dem Container unerreichbar
- [ ] AK1.2 `169.254.0.0/16` (inkl. `169.254.169.254`) unerreichbar
- [ ] AK1.3 `168.63.129.16` unerreichbar
- [ ] AK1.4 `fe80::/10` unerreichbar (oder kein IPv6 im Container)
- [x] AK1.5 Sperre aus dem Container heraus nicht aufhebbar
- [ ] AK2.1 DNS + HTTPS zu GitHub funktionieren, Bundle unverändert
- [x] AK2.2 Tests #23/#24/#37/#41 grün, Anker mindestens gleich streng
- [x] AK3.1 `fetch-isolated` fail-closed, wenn Sperre nicht einrichtbar
- [x] AK3.2 `fetch-smoke` ebenso rot
- [x] AK4.1 Offline-Guard-Tests (ohne Docker) für Zielmenge, Reihenfolge, beide Modi, Fehlerfall
- [x] AK4.2 Mutationsbelege je tragender Eigenschaft
- [ ] AK4.3 Smoke-Probe in `fetch-container-smoke`: gesperrte Ziele scheitern, `github.com` erreichbar
- [x] AK5.1 ADR-063-Nachtrag (#66), Verweise aus E31 Q3 und Restrisiko 2
- [x] AK5.2 `OPERATING.md` §0.6 ergänzt
- [x] AK5.3 `tasks/security-41.md` Hinweis „Netz" verweist auf #66
- [ ] F1, F3, F4 Fehlerszenarien abgedeckt (F2 entfällt, E39; siehe Spec)

**Stand `/implement` (2026-11-21, Runde 3):** Offline vollständig belegt (`factory-lock-66-tests.sh`, 84 grün; ganze Suite
2732 grün, Projekt-Suite 249 grün).
Offen bis zum ersten grünen CI-Lauf des Jobs `fetch-container-smoke` am PR: AK1.1–AK1.4, AK2.1, AK4.3 und F3 – deren
Wirkung im echten Container (iptables-Backend, `DOCKER-USER`, DNS über `168.63.129.16`) ist offline nicht belegbar
(ADR-063 Nachtrag 2026-11-21, Restrisiko 4). F1 und F4 sind offline belegt.

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Entscheidung: Factory-ADR-063, Nachtrag 2026-11-21 (E35–E40), Status Accepted (2026-11-21). Kurzfassung für `/implement`:

- **Netz (E35):** Konstanten `FETCH_NETWORK=factory-fetch`, `FETCH_BRIDGE=factory-fetch0`;
  `docker network create --driver bridge -o com.docker.network.bridge.name=factory-fetch0 factory-fetch`.
- **Regeln (E36):** ein Array an einer Stelle, per `sudo -n iptables -I`, danach jede per `-C` prüfen:
  `INPUT -i factory-fetch0 -j REJECT`; `DOCKER-USER -i factory-fetch0 -d 168.63.129.16/32 -p udp|tcp --dport 53 -j RETURN`
  **vor** `DOCKER-USER -i factory-fetch0 -d 168.63.129.16/32 -j REJECT`; `DOCKER-USER -i factory-fetch0 -d 169.254.0.0/16 -j REJECT`.
  Achtung: `-I` fügt am Anfang ein – Reihenfolge der Einfügungen so wählen, dass die RETURN-Regeln vor der REJECT-Regel stehen.
- **`docker run` (E31 + E37):** zusätzlich `--network factory-fetch --sysctl net.ipv6.conf.all.disable_ipv6=1`, sonst unverändert.
- **Reihenfolge (E39):** `require_docker` → Reste abräumen → Netz + Regeln + `-C` → Image bauen → Container; in
  `fetch-isolated` **und** `fetch-smoke`. Jeder Fehler → `die` mit Hinweis auf passwortloses `sudo`/`iptables`, kein Rückfall.
- **Abräumen (E38):** `trap` auf `EXIT`: Regeln per `-D` (solange `-C` trifft), Netz entfernen; Fehler nur Warnung.
- **Tests (E40):** Fakes für `docker`/`sudo`/`iptables` im `PATH`; Verbots-Prüfer erlaubt `--network` nur mit
  `factory-fetch`; Mutationsbelege laut E40 b. Gruppe in `factory-lock-41-tests.sh` erweitern oder neue
  `factory-lock-66-tests.sh` (dann `OWNERSHIP.md` + `run-tests.sh`).
- **Smoke (E40 c):** Host startet `python3 -m http.server --bind <gateway>` als Lauscher + Gegenprobe vom Host,
  Gateway als Positionsargument in den Container; im Container scheitern Lauscher, `169.254.169.254`,
  `168.63.129.16:80`; gelingen DNS + HTTPS `github.com` (`curl --retry`); `/proc/net/if_inet6` ohne Adresse außer `lo`.
- **Doku:** `OPERATING.md` §0.6, `tasks/security-41.md` (Hinweis „Netz" → #66), Release-Notes (selbst gehostete Runner).

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
- [x] Q1–Q5 geklärt in Factory-ADR-063, Nachtrag 2026-11-21 (E35–E40)
- [x] ADR-Nachtrag angenommen (Accepted, 2026-11-21) – E35–E40
- [x] E41 (host-weiter Lock, aus `/implement` Runde 2) vom Menschen angenommen (Accepted, 2026-11-21)

Notizen aus `/implement`:
- Fakes für `docker`/`sudo`/`iptables` (und Host-Lauscher, Container-`curl`) liegen jetzt in `lib/factory-lock-fixtures.sh`
  (`fetch_fakes_41`), geteilt von den Gruppen #41 und #66. Der Fake-`iptables` nutzt nur Builtins: mit Hilfsprozessen je Aufruf
  lief die Gruppe lokal 302 s statt 86 s.
- Neue Gruppe `factory-lock-66-tests.sh` (per Glob in `run-tests.sh`, `OWNERSHIP.md` deckt `scripts/checks/tests/**` schon ab).
- Smoke-Probe: Port des Host-Lauschers fest `18066`; die Gegenprobe vom Host läuft vor dem Container, sonst Smoke rot.
- Mit kaputtem `iptables -C` kann auch das Abräumen keine Regel finden (Test lässt dort nur die Abräum-Prüfung weg).
- Runde 2: Der Lock liegt auf fd 9 (bash 3.2 kennt `{var}>` nicht); der Lauscher der Smoke-Probe startet mit `9>&-`, sonst
  hielte er den Lock über das Skriptende hinaus. `FACTORY_FETCH_LOCK` lenkt die Lock-Datei nur in Tests um.
- In Testnamen `${var}` vor „“ schreiben: bash liest das typografische Anführungszeichen sonst als Teil des Namens (unbound variable).

## Review-Findings
<!-- Wird durch /review befüllt -->
Runde 1 (2026-11-21): **NEEDS_REWORK**, Details in [`review-66.md`](review-66.md). 0 Kritisch, 3 Wichtig: parallele Läufe
auf einem Docker-Host entfernen sich gegenseitig die Sperre; die Smoke-Probe trennt „gesperrt“ nicht von „unerreichbar“
(Exit 7 verlangen); der #41-Anker `docker_calls_41` ist schwächer geworden (AK2.2). Dazu 10 Nitpicks.

Runde 2 (`/implement`, 2026-11-21): alle drei wichtigen Findings behoben, 9 von 10 Nitpicks umgesetzt (Details mit „→" in
`review-66.md`). Entscheidung zum Nebenläufigkeits-Finding: host-weiter Lock per `flock` (fail-closed), als **E41** im
ADR-063-Nachtrag 2026-11-21 ergänzt – vom Review an `/implement` delegiert, bitte beim nächsten `/review` mitprüfen.
Nicht umgesetzt: `--name`/`docker rm -f` bei Abbruch (Restrisiko 5 im ADR, Abhilfe von Hand in `OPERATING.md` §0.6).

Runde 2 (`/review`, 2026-11-21): **NEEDS_REWORK**, nur noch ADR-/Doku-Arbeit (Iteration 2 von 3). Die drei Fixes aus
Runde 1 sind korrekt, Restrisiko 5 ist akzeptiert. Gruppen #66 (77 grün) und #41 (93 grün) laufen lokal grün.
2 Wichtig:
- E41 trägt fälschlich den Menschen-Status „Accepted“. **Die Annahme durch den Menschen steht aus.**
- Die Grenze des Locks („gemeinsamer Daemon, getrenntes `/tmp`“) fehlt als Restrisiko, die Alternative „Namen je Lauf“
  fehlt ganz.

Dazu 10 Nitpicks, u. a. die Zusage zu Exit 7 bei fehlender Route, ein Mutant für „Lock bis Prozessende gehalten“ und
`OPERATING.md` mit Verweis E35–E41.

Runde 3 (`/implement`, 2026-11-21): beide wichtigen Findings und alle 10 Nitpicks umgesetzt (Details in `review-66.md`,
„Umsetzung Runde 3“). E41 ist im ADR jetzt als **Proposed** gekennzeichnet; die Annahme durch den Menschen steht aus und
ist Voraussetzung für den Merge. Neu: Restrisiko 6 (gemeinsamer Daemon, getrenntes `/tmp`), Alternative „Namen je Lauf“,
zwei Lock-Mutanten (Lock vor dem Container frei, Lauscher erbt den Lock).

Runde 3 (`/review`, 2026-11-21): **NEEDS_REWORK – Circuit Breaker erreicht (3. Review), Eskalation an den Menschen.**
Am Code ist nichts mehr nachzuarbeiten (Suite 2732 grün, Projekt-Suite 249 grün). Offen ist allein ein wichtiges Finding:
die **Annahme von E41 durch den Menschen**. Nach der Annahme (Status in ADR und „Offene Fragen“) gilt der Review ohne
weitere Runde als bestanden. Dazu 3 optionale Nitpicks: CHANGELOG ohne Grenze aus Restrisiko 6, zwei Umbrüche.

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/66-fetch-container-netz-abschotten`
Erstellt: 2026-11-21 06:57
