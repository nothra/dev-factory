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
- [ ] F1–F4 Fehlerszenarien abgedeckt (siehe Spec)

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
- [ ] Q1–Q5 für `/architecture` (Mechanismus, Geltungsbereich/Aufräumen, DNS, IPv6, Flakiness der Smoke-Probe) – siehe Spec

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/66-fetch-container-netz-abschotten`
Erstellt: 2026-11-21 06:57
