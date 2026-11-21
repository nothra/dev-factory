# Task 66: fetch-container-netz-abschotten

## Status
- [ ] In Bearbeitung
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
- [ ] AK1.5 Sperre aus dem Container heraus nicht aufhebbar
- [ ] AK2.1 DNS + HTTPS zu GitHub funktionieren, Bundle unverändert
- [ ] AK2.2 Tests #23/#24/#37/#41 grün, Anker mindestens gleich streng
- [ ] AK3.1 `fetch-isolated` fail-closed, wenn Sperre nicht einrichtbar
- [ ] AK3.2 `fetch-smoke` ebenso rot
- [ ] AK4.1 Offline-Guard-Tests (ohne Docker) für Zielmenge, Reihenfolge, beide Modi, Fehlerfall
- [ ] AK4.2 Mutationsbelege je tragender Eigenschaft
- [ ] AK4.3 Smoke-Probe in `fetch-container-smoke`: gesperrte Ziele scheitern, `github.com` erreichbar
- [ ] AK5.1 ADR-063-Nachtrag (#66), Verweise aus E31 Q3 und Restrisiko 2
- [ ] AK5.2 `OPERATING.md` §0.6 ergänzt
- [ ] AK5.3 `tasks/security-41.md` Hinweis „Netz" verweist auf #66
- [ ] F1, F3, F4 Fehlerszenarien abgedeckt (F2 entfällt, E39; siehe Spec)

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Entscheidung: Factory-ADR-063, Nachtrag 2026-11-21 (E35–E40), Status Proposed. Kurzfassung für `/implement`:

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
- [ ] ADR-Nachtrag annehmen (Status Proposed → Accepted)

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/66-fetch-container-netz-abschotten`
Erstellt: 2026-11-21 06:57
