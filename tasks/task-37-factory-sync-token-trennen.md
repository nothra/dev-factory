# Task 37: factory-sync-token-trennen

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Der Update-Workflow führt Code des noch ungeprüften Release im selben Job aus, in dem danach
`FACTORY_SYNC_TOKEN` (schreibberechtigtes PAT) benutzt wird; zusätzlich sieht jeder `pull_request`-Workflow
des Update-PRs alle Repository-Secrets. Das Token ist vom Release-Code zu trennen (Job-/Kontextgrenze statt
`env -u`) und für PR-Workflows unsichtbar zu machen. Spec: `docs/specs/spec-37-factory-sync-token-trennen.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] AK-37a Token nicht neben Release-Code (Schritt-/Job-Grenze, Wiring-Test + Mutationsbeleg)
- [ ] AK-37b Kein Release-Code (Skript, Hook, Git-Config) im Token-Schritt (E2E mit Fixture-Release)
- [ ] AK-37c Ergebnis nur als Daten übergeben, Pfadprüfung vor dem Push
- [ ] AK-37d Verhalten des Update-PRs unverändert (spec-24-Tests grün, unverändert)
- [ ] AK-37e Token für PR-Workflows auf `chore/factory-update` unsichtbar (kein Repository-Secret)
- [ ] AK-37f Kein stiller Rückfall auf ein Repository-Secret (Umfang: Q-37.4)
- [ ] AK-37g `OPERATING.md` §0.6 an neuen Stand angepasst (Doku-Guard)
- [ ] AK-37h Factory-ADR-063 E4/E12 nennen das verbleibende Risiko ehrlich
- [ ] F-37.1 Übergabe scheitert → rot, kein Push/PR
- [ ] F-37.2 Token fehlt im Kontext → FS-T2.3 unverändert, Meldung nennt Kontext
- [ ] F-37.3 Kein Lock → grüner No-op ohne Token und ohne Freigabe
- [ ] F-37.4 Token-Schritt nutzt Workflow-Fassung von `main`, nicht die des Ergebnisses

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Entscheidung: Factory-ADR-063, Nachtrag 2026-10-31 (E17–E22).
- Workflow in vier Jobs: `guard` (kein Environment; kein Lock → No-op; Repository-Secret gleichen Namens → rot),
  `preflight` (Environment, Token-Prüfung, Version/PR-Stand), `fetch` (kein Secret, Release-Code, Ergebnis nur als
  `git bundle`-Artefakt), `publish` (Environment, nur `main`-Code, prüft Bundle, `commit-tree`, Push auf SHA, PR).
- Token als Environment-Secret `factory-update` (Branch-Regel `main`), nicht als Repository-Secret.
- `factory-update.sh`: `guard|preflight|fetch|publish`; ohne Argument Kurzform für Tests (frischer Klon ohne Token,
  Übergabe per Bundle), in CI (`GITHUB_ACTIONS=true`) verweigert.
- Umsetzungs-Reihenfolge (TDD): Wiring-Tests je Job (yq) rot → Workflow; Verhaltenstests mit bösem Fixture-Release
  (fsmonitor-Marker, Hook, Fremdpfad, Symlink) rot → `fetch`/`publish`; Mutationsbelege; dann `OPERATING.md` §0.6
  und E4/E10/E12-Verweise im ADR; ADR-Status auf Accepted.
- Alte Wiring-Anker (`wf_wired_24`) werden durch strengere je Job ersetzt – sonst keine spec-24-Assertion ändern.
- Menschliche Schritte (nicht agentenerfüllbar): Environment/Secret im Konsumenten einrichten; Beleg am echten Repo
  (Test-PR, Secret leer) in T2a-4.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
Siehe Spec: Q-37.1 (beide Maßnahmen nötig?), Q-37.2 (Übergabeformat), Q-37.3 (Beleg am echten Repo),
Q-37.4 (Umgang mit Bestand), Q-37.5 (Environments je GitHub-Plan), Q-37.6 (Concurrency).

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `improvement/37-factory-sync-token-trennen`
Erstellt: 2026-10-31 16:15
