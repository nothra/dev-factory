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
- [ ] AK2.2e – Erstabholung ohne Lock: Abbruch mit Liste, mit Schalter Übernahme + Liste; Schalter mit Lock abgelehnt
- [ ] AK2.3 – keine Anpassungsstelle/kein Projektbereich geändert; solches Manifest abgelehnt
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
Entscheidung: Factory-ADR-063, Nachtrag 2026-10-25 (E1–E9). Kurzfassung für `/implement`:

- **Neue Dateien:** `scripts/lib/factory-lock.sh` (Hash, Lock-/Manifest-Prüfung, Manifest-Abruf,
  Projektbereiche) und `scripts/checks/factory-integrity-check.sh`, je eine Zeile `factory` in
  `docs/factory/OWNERSHIP.md`. Lib relativ zum Skript sourcen (Lesson nothra/tch-gastro-services#431),
  in alle Test-Scaffoldings mitkopieren (Lesson nothra/tch-gastro-services#197).
- **Geändert:** `scripts/factory-sync.sh` (Modus `<version> [--adopt]`, `--compose [--check]` unverändert),
  `pre-commit.sh` + `pre-push.sh` (fester Check), `.github/workflows/factory-ci.yml` (Job `factory-integrity`
  mit `--ci`, `yq` über `install-yq.sh`), `factory.defaults.yml` (`upstream.repo: nothra/dev-factory`),
  beide Test-Suiten, ADR-064 D6 (AK-28c).
- **Transport (E1):** `git clone --depth 1 --branch <tag>`; Manifest `curl -fsSL
  <base>/<tag>/factory-release.json`. Test-Seams `FACTORY_UPSTREAM_GIT_URL`, `FACTORY_RELEASE_BASE_URL`
  (`file://`).
- **Quell-Repo (E2):** `upstream.repo` per `factory_cfg`; `lock.repo` muss gleich sein (F-23.1).
- **Abholung (E4):** Phase 1 prüft ohne Schreiben (zuerst offline Vorbedingung F2/AK2.2e, dann Manifest,
  Klon, Hashes, Zusammensetzen im Temp-Baum); Phase 2 mit Backup + `trap`-Rückbau, `factory.lock` zuletzt.
  Version-Muster `^v[0-9]+\.[0-9]+\.[0-9]+$` vor jedem Netzzugriff.
- **Gate (E8):** Moduswahl `-e || -L`; lokal = Hashes + reguläre Datei + `--compose --check`; `--ci` =
  zusätzlich `jq -S .`-Vergleich Lock ↔ Manifest. Exit 0/1/2 wie `ownership-check.sh`. Hashen in **einem**
  `shasum`-Aufruf (gemessen 0,05 s statt 1,8 s je Datei).
- **Projektbereiche (E6):** `scripts/project/`, `docs/project/`, `docs/adr/`, `docs/specs/`, `tasks/` als Liste
  in der Lib; `customization-points.txt` bleibt wörtlich (ADR-064 D4).
- **Tests (E9):** Fixture-Upstream mit zwei Tags; Stubs für `curl`/`git`/Hash-Werkzeug im `PATH`; Compose-Tests
  der ausgelieferten Suite mit eigenen Fragmenten, Prüfungen am echten Repo → Projekt-Suite (Vorher/Nachher-Liste).
  Guard in der Projekt-Suite: Factory-Repo trackt kein `factory.lock`.

## Offene Fragen
- [x] Q-23.1 Transport und Aufruf → ADR-063 Nachtrag E1–E3
- [x] Q-23.2 Schutz der Anpassungsverzeichnisse → E6 (eigene Liste, ADR-064 D4 bleibt)
- [x] Q-23.3 zusammengesetzte Dateien im Lock → E7 (ADR-064 D1 gilt)
- [x] Q-23.6 Größe → ein PR (~20 Dateien)
- [x] Q-23.4 Release → nach #24 (`v0.7.0`), Issue-Text von #23 anpassen
- [x] Q-23.5 Erstabholung → nur mit Schalter

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/23-factory-sync-lock-integritaets-gate`
Erstellt: 2026-10-25 18:13
