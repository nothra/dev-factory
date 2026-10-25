# Task 23: factory-sync-lock-integritaets-gate

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
T2a-2 (B) des Epics `nothra/tch-gastro-services#424`: `factory-sync.sh` holt eine Factory-Version
ab (atomar, gegen das Release-Manifest geprüft) und schreibt `factory.lock`;
`factory-integrity-check.sh` verhindert lokal (offline) und in CI (`factory-integrity`), dass ein
Projekt übernommene Dateien still ändert. Dazu Fundstelle (2) aus #28 (Compose-Tests konsumenten-
neutral, Abgleich ins Gate, ADR-064 D6). Kein Release in dieser Task (`v0.7.0` nach #24).
Spec: [`docs/specs/spec-23-factory-sync-lock-integritaets-gate.md`](../docs/specs/spec-23-factory-sync-lock-integritaets-gate.md)

## Akzeptanzkriterien
<!-- Volltext in der Spec -->
- [ ] AK2.1a – Lock nennt Repo, Tag, Commit, Pfad + SHA-256, gleich dem Release-Manifest; FACTORY.md-Version passt
- [ ] AK2.1b – Gate: Hashes lokal, Pfadmenge Lock == Manifest in CI (je Stufe Gegenprobe)
- [ ] AK2.1c – nach Abholung ist `ownership-check.sh` im Lock-Modus grün
- [ ] AK2.2a – Abholung lädt den Tag ohne Token, prüft gegen Manifest, schreibt Lock
- [ ] AK2.2b – Abbruch an jeder Stelle → nichts verändert (Messung per Stub gebrochen)
- [ ] AK2.2c – entfallene Dateien gelöscht, neue angelegt, fremde unberührt
- [ ] AK2.2e – Erstabholung ohne Lock: Abbruch mit Liste, mit Schalter Übernahme + Liste
- [ ] AK2.3 – keine Anpassungsstelle geändert; Manifest mit Anpassungsstelle abgelehnt
- [ ] AK2.3b – zusammengesetzte Dateien nach Abholung neu zusammengesetzt
- [ ] AK2.5a – lokale Stufe lehnt Änderung/Löschung ab, nennt Datei + Hinweis; verdrahtet in pre-commit/pre-push
- [ ] AK2.5b – CI-Job `factory-integrity` fängt auch Datei + Hash gemeinsam geändert
- [ ] AK2.5c – im Factory-Repo No-op mit Hinweis
- [ ] AK2.5d – CI-Stufe fail-closed, wenn Factory-Repo/Tag/Manifest nicht erreichbar
- [ ] AK2.6 – Hebung N → N+1 besteht beide Stufen
- [ ] F2 – lokal geänderte Datei → Abholung bricht vor dem Schreiben ab
- [ ] AK2.8 – offline: lokale Stufe, Ownership-Check, `--compose` laufen
- [ ] AK-28a – Compose-Tests der ausgelieferten Suite mit festen Fixtures
- [ ] AK-28b – Abgleich committet == Zusammensetzung im Gate; Repo-Prüfungen in der Projekt-Suite
- [ ] AK-28c – ADR-064 D6 um „prüft Zustand projekteigener Dateien" ergänzt
- [ ] FS-T2.1 – Manifest fehlt/ungültig/unbekanntes Schema → Abbruch
- [ ] FS-T2.2 – Hash-Abweichung → Abbruch
- [ ] FS-T2.4 – Tag ohne Release/Manifest → nicht eingebunden
- [ ] F-23.1 – Manifest widerspricht Tag (version/commit/repo) → Abbruch
- [ ] F-23.2 – Lock unlesbar/ungültig → fail-closed
- [ ] F-23.3 – Manifest-Pfad absolut oder mit `..` → Abbruch

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
- [ ] Q-23.1 Transport und Aufruf – `/architecture`
- [ ] Q-23.2 Schutz der Anpassungsverzeichnisse – `/architecture`
- [ ] Q-23.3 zusammengesetzte Dateien im Lock (ADR-063 D3 vs. ADR-064 D1) – `/architecture`
- [ ] Q-23.6 Größe prüfen nach `/architecture`
- [x] Q-23.4 Release → nach #24 (`v0.7.0`), Issue-Text von #23 anpassen
- [x] Q-23.5 Erstabholung → nur mit Schalter

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/23-factory-sync-lock-integritaets-gate`
Erstellt: 2026-10-25 18:13
