# Task 41: fetch-token-abschirmen

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Im Job `fetch` von `factory-update.yml` läuft Release-Code auf einem Runner, auf dem das Runtime-Token des Laufs liegt
(Cache-Schreibrecht im Scope `main`). Er erreicht es über `$GITHUB_ENV`/`$GITHUB_PATH` und den Folgeschritt sowie über
`sudo` direkt aus dem Speicher von `Runner.Worker`. Lösung: Release-Code in einem unprivilegierten Container ausführen,
zurück kommt nur das Bundle. Dazu ADR-063-Nachtrag und OPERATING §0.6. Spec: `docs/specs/spec-41-fetch-token-abschirmen.md`.
ADR-Trigger: ja (Jobstruktur/Isolationsgrenze) → `/architecture 41` vor `/implement`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt; Volltext in der Spec -->
- [ ] AK1.1 Release-Code (Abholung, Commit, Bundle) läuft im `fetch`-Job nur im Container
- [ ] AK1.2 Container ohne Sonderrechte (kein privileged/pid/network/ipc host, kein cap-add, kein Docker-Socket; cap-drop ALL, no-new-privileges)
- [ ] AK1.3 Keine ACTIONS_*-/Token-Variablen, kein env-file, keine Runner-Dateien; nur Arbeits- und Ausgabeverzeichnis eingebunden
- [ ] AK1.4 Image per Digest gepinnt, nicht aus Arbeitsbaum/Release gebaut
- [ ] AK2.1 Nach dem Container nur der Upload der Bundle-Datei; kein git/keine Ausführung im Container-Verzeichnis
- [ ] AK2.2 Manipulation von `.git/config`/Hooks wird auf dem Host nie ausgeführt
- [ ] AK3.1 Bundle und Update-PR unverändert
- [ ] AK3.2 Tests zu #23/#24/#37 grün, geänderte Anker mindestens gleich streng
- [ ] AK4.1 Wiring-Tests an der echten `factory-update.yml`, ohne Docker lauffähig
- [ ] AK4.2 Mutationsbeleg je tragender Eigenschaft
- [ ] AK5.1 ADR-063-Nachtrag (#41) inkl. Korrektur der `sudo`-Aussage in E17
- [ ] AK5.2 OPERATING §0.6: Container, Docker-Voraussetzung, Restrisiko für Caches
- [ ] F1 Kein Docker → `fetch` rot, kein stiller Rückfall
- [ ] F2 Image nicht ladbar/Digest falsch → rot
- [ ] F3 Kein Bundle → rot, `publish` läuft nicht
- [ ] F4 Symlink/Verzeichnis statt Bundle → nichts von außerhalb des Ausgabeverzeichnisses hochgeladen

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
Q1–Q5 für `/architecture` (Image, Ort des `docker run`, Netz, Benutzer, Restweg) – siehe Spec.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/41-fetch-token-abschirmen`
Erstellt: 2026-11-20 21:41
