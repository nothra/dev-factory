# Task 37: factory-sync-token-trennen

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [x] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [x] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Der Update-Workflow führt Code des noch ungeprüften Release im selben Job aus, in dem danach
`FACTORY_SYNC_TOKEN` (schreibberechtigtes PAT) benutzt wird; zusätzlich sieht jeder `pull_request`-Workflow
des Update-PRs alle Repository-Secrets. Das Token ist vom Release-Code zu trennen (Job-/Kontextgrenze statt
`env -u`) und für PR-Workflows unsichtbar zu machen. Spec: `docs/specs/spec-37-factory-sync-token-trennen.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [x] AK-37a Token nicht neben Release-Code (Schritt-/Job-Grenze, Wiring-Test + Mutationsbeleg)
- [x] AK-37b Kein Release-Code (Skript, Hook, Git-Config) im Token-Schritt (E2E mit Fixture-Release)
- [x] AK-37c Ergebnis nur als Daten übergeben, Pfadprüfung vor dem Push
- [x] AK-37d Verhalten des Update-PRs unverändert (spec-24-Tests grün; nur die in den Umsetzungs-Notizen genannten Mechanik-Anker angepasst)
- [x] AK-37e Token für PR-Workflows auf `chore/factory-update` unsichtbar (kein Repository-Secret)
- [x] AK-37f Kein stiller Rückfall auf ein Repository-Secret (Umfang: Q-37.4)
- [x] AK-37g `OPERATING.md` §0.6 an neuen Stand angepasst (Doku-Guard)
- [x] AK-37h Factory-ADR-063 E4/E12 nennen das verbleibende Risiko ehrlich
- [x] F-37.1 Übergabe scheitert → rot, kein Push/PR
- [x] F-37.2 Token fehlt im Kontext → FS-T2.3 unverändert, Meldung nennt Kontext
- [x] F-37.3 Kein Lock → grüner No-op ohne Token und ohne Freigabe
- [x] F-37.4 Token-Schritt nutzt Workflow-Fassung von `main`, nicht die des Ergebnisses

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

## Umsetzungs-Notizen (/implement)
- Umbau: `factory-update.sh` mit vier Aufrufformen (`guard|preflight|fetch|publish`) plus Kurzform für Tests (Abholung als
  eigener Prozess ohne Token in frischem Klon, Übergabe per Bundle, in CI verweigert); `factory-update.yml` in vier Jobs.
- **Angepasste spec-24-Anker (AK-37d, Begründung ADR-063 E22e):** (1) Rückkehr auf `ORIG_REF` entfällt (Arbeitsbaum wird nicht mehr
  umgeschaltet) – statt der Mutation prüft ein Test, dass HEAD und lokale Branches unberührt bleiben; (2) Push-Ziel `<sha>:refs/heads/…`
  statt `HEAD:…`; (3) Selbst-Ersatz-Test fährt den Modus `fetch` im Konsumenten-Checkout (Kurzform arbeitet im Klon);
  (4) `wf_wired_24` durch die strengeren Job-Anker (#37) ersetzt. Alle übrigen spec-24-Assertions unverändert grün.
- **Menschliche Schritte (nicht agentenerfüllbar):** Environment `factory-update` (Branch-Regel `main`) und Secret im Konsumenten
  einrichten, Repository-Secret löschen (OPERATING.md §0.6); Beleg am echten Repo (Test-PR, Secret leer) = Q-37.3 / T2a-4.
  Release-Notes des nächsten Releases: Secret **vor** dem Update umziehen, sonst endet `guard` rot.

- **Review-Iteration 1 (tasks/review-37.md) umgesetzt:** (W1) `verify_bundle` lehnt ein Manifest mit geschützten Stellen ab
  (`fl_protected_findings`, wie `factory-sync.sh`; Test + Mutation); (W2) `upload-artifact` mit `overwrite: true` (Re-run, Wiring-Anker +
  Mutation); (W3) Spec AK-37d an die angepassten Mechanik-Anker angeglichen; Nitpicks: Drift-Guard `COMPOSED_TARGETS` ↔ `factory-sync.sh`
  (beide Richtungen mutiert), `publish`-Aufruf der Argument-Tests über `pub_37`, CHANGELOG-Hinweis unter „Unreleased“.

- **Review-Iteration 2 umgesetzt:** ADR-063 E18 und `OPERATING.md` §0.6 nennen die Prüfung „keine geschützten Stellen im Manifest“;
  Doku-Guard-Anker (`ops_ok_37`/`adr_ok_37`) mit je einer Mutation. Die Nitpicks (`verify_bundle` aufteilen, `PROT_37` lesbar machen) gehen an `/refactor`.

- **/test (Abdeckung ohne Coverage-Werkzeug):** Die `die`-Zweige von `fetch`/`publish`/`guard` wurden einzeln auf Test + Mutationsbeleg
  geprüft (Lesson Factory-Task #22/#23). Lücken geschlossen, je mit zweigspezifischer Meldung, „nichts gepusht“ und einer Mutante
  (`|| die` → `|| true`): leerer Bundle-Pfad, Manifest nicht abrufbar/ungültig, Liste der Anpassungsstellen fehlt (kein „keine Funde“),
  Manifest-Datei fehlt im Bundle, Pfad mit Zeilenumbruch, Origin lehnt Push ab, `fetch` mit unsauberem Arbeitsbaum/unbekannter Basis,
  unbekannter Modus. Bewusst ungetestet (nicht ohne Eingriff in git erzeugbar): `commit-tree`-Fehler, `bundle create`-Fehler,
  `fetch`-aus-Bundle-Fehler nach erfolgreichem `bundle verify`, Hash-Werkzeug-Fehler (`fl_hash_paths`, in #23 gedeckt).

- **/refactor (kein neues Verhalten, Testgruppe vorher/nachher 482 grün):** `verify_bundle` (~60 Zeilen) in `load_bundle`,
  `verify_manifest`, `verify_changed_paths`, `verify_hashes` aufgeteilt (Prüfzeilen wörtlich unverändert, damit die Mutationsbelege
  greifen); doppelte Blöcke als `make_work_dir` und `exit_if_current` herausgezogen (drei bzw. zwei Stellen); das `PROT_37`-Fixture ist
  die Funktion `craft_protected_manifest_37`. Beide Nitpicks aus `tasks/review-37.md` erledigt.

- **/security-review (`tasks/security-37.md`, PASSED, keine Blocker/Wichtigen):** Token-Fluss, Handover-Eingaben, Bundle-Prüfung und Pfad-Traversal
  im Token-Job geprüft, ohne Befund. Hinweis: das Runtime-Token des `fetch`-Jobs ist im Folgeschritt `upload-artifact` gegen Release-Code nicht
  abgeschirmt (Cache-Vergiftung von `main`, nur bei Konsumenten mit Caches, nicht nachgestellt) – verfolgt in Issue #41, nicht Teil von #37.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
Siehe `tasks/codify-37.md`: vier Learnings (Job-Grenze, Verifier-Parität, Turn-Limit #7, Feindcode-Test) ausgelagert; Issue #41.
Manuelle Stage-2-Fortsetzung: die OTEL-Telemetrie fehlt für alle Stufen (Lesson zu nothra/tch-gastro-services#346).

---
Branch: `improvement/37-factory-sync-token-trennen`
Erstellt: 2026-10-31 16:15
