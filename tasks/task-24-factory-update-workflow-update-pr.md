# Task 24: factory-update-workflow-update-pr

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Übernommener Workflow `factory-update.yml` (täglich + `workflow_dispatch`): erkennt eine neuere
Factory-Version im Quell-Repo, holt sie per `factory-sync.sh` ab und pflegt **einen** Update-PR auf dem
festen Branch `chore/factory-update` (Release Notes im Body, PAT `FACTORY_SYNC_TOKEN`, kein Auto-Merge).
Teil-Task T2a-3 von `nothra/tch-gastro-services#428`. Spec: `docs/specs/spec-24-factory-update-workflow-update-pr.md`.

## Akzeptanzkriterien
<!-- Volltext: docs/specs/spec-24-factory-update-workflow-update-pr.md -->
- [x] AK2.2d – neue Version → Update-PR auf `chore/factory-update` mit Release Notes, ohne menschliches Zutun
- [x] AK2.4 – Push/PR mit `FACTORY_SYNC_TOKEN` (nicht `GITHUB_TOKEN`), nie Merge/Auto-Merge
- [x] AK2.4b – keine neuere Version / kein Release → nichts geändert, Lauf grün
- [x] F3 – mehrere Versionen → höchstens ein offener PR, neu aufgebaut auf die neueste
- [x] AK-24a – Release Notes jeder übersprungenen Version im Body
- [x] AK-24b – PR schon auf neuester Version → Branch unberührt (auch mit Fremd-Commits)
- [x] AK-24c – neuere Version ersetzt Fremd-Commits sichtbar (Hinweis im Body)
- [x] AK-24d – ohne Merge geschlossene Version wird nicht erneut angeboten
- [x] AK-24e – ohne `factory.lock` (Factory-Repo): No-op, grün, ohne Token
- [x] AK-24f – Update-PR besteht `pr-closes-issue` (Ausnahme nur für `chore/factory-update` im selben Repo, Fork bleibt geprüft)

### Fehlerszenarien
- [x] F1 – rote Gates im Update-PR: PR bleibt offen, `main` unverändert, Workflow schreibt nie auf `main`
- [x] FS-T2.3 – Token fehlt/abgelehnt → Lauf rot vor jedem weiteren Schritt, auch ohne neue Version
  (Vorbehalt Q-24.7: bei „zu wenig Rechte" ggf. erst beim Push/PR rot – Beleg am echten Repo in T2a-4)
- [x] F-24.1 – Abholung scheitert → rot, kein Push, bestehender PR unverändert
- [x] F-24.2 – Release-Liste nicht lesbar → rot (fail-closed)
- [x] F-24.3 – `factory.lock` unlesbar → rot, kein Rückfall auf No-op

### Begleitend
- [x] `OPERATING.md`: Token anlegen, Rechte, Ablauf, Rotation
- [x] `OWNERSHIP.md`: je neue Datei eine Zeile

## Technische Notizen
Entscheidungen: Factory-ADR-063, Nachtrag 2026-10-30 (E10–E16). Kurzfassung für `/implement`:
- **Neu (Seite `factory`, je eine Zeile in `OWNERSHIP.md`):** `scripts/factory-update.sh` (ganze Logik),
  `.github/workflows/factory-update.yml` (nur Auslöser: `schedule` täglich + `workflow_dispatch`,
  `concurrency` ohne Cancel, `permissions: contents: read`, Checkout `fetch-depth: 0` +
  `persist-credentials: false`, `install-yq.sh`, Skript mit `FACTORY_SYNC_TOKEN` als Env).
- **Ablauf des Skripts (E11), Reihenfolge fest:** kein Lock → No-op Exit 0 · Lock ungültig → Exit 1 ·
  Token leer/abgelehnt (`gh api repos/$GITHUB_REPOSITORY --jq .permissions.push`) → Exit 1 · Release-Liste
  (`gh api --paginate`, Filter: kein Draft/Pre-Release, SemVer-Tag, Asset `factory-release.json`; numerisch
  vergleichen, kein `sort -V`) · ≤ N → Exit 0 · offener PR mit Lock-Version = V → Exit 0 · geschlossener,
  nicht gemergter PR mit Body-Marke `<!-- factory-update-version: V -->` → Exit 0 · sonst Neuaufbau von
  `origin/main`, `factory-sync.sh V`, Commit mit expliziter Identität, Push nur auf
  `refs/heads/chore/factory-update` mit `--force-with-lease=…:<alter SHA>`, dann `gh pr edit` bzw.
  `gh pr create --label enhancement` (kein Draft, nie `merge`/`--auto`).
- **Push-Anmeldung (E12):** Credential-Helper per `-c`, der das Token aus der Umgebung liest – kein Token in
  argv, URL oder `.git/config`; kein `gh auth setup-git`.
- **PR-Body (E13):** Satz „hebt von N auf V", Marke, Hinweis zum Branch-Besitz, je Version in (N, V] neueste
  zuerst `## <version>` + Release-Body; per `--body-file`.
- **Gate-Ausnahme (E14):** `pr-closes-keyword-check.sh` grün ohne Keyword nur bei Head-Branch
  `chore/factory-update` **und** Head-Repo = Basis-Repo; Env im Job `pr-closes-issue` in `factory-ci.yml`
  durchreichen; `git-workflow.md` nennt die Ausnahme bei der Closes-Regel.
- **Doku (E15):** `OPERATING.md` neuer Einmal-Setup-Abschnitt (Token: Contents/Pull requests/Workflows
  read+write auf dem Konsumenten-Repo, ≤ 1 Jahr, Rotation, Symptom „Lauf rot: Token") + Verweis aus §5.5a.
- **Tests (E16):** ausgelieferte Suite; Upstream-Fixture aus #23 + Bare-Repo als `origin` + `gh`-Stub im
  `PATH` (Zustand aus Dateien, Aufruf-Protokoll). Mutationsbelege für Token-Prüfung und Fork-Bedingung.
  Lessons: Scaffold-Helfer wiederverwenden statt parallel (#310), Stub im Scaffold (#314), Git-Identität
  in Fixtures (#265).

## Offene Fragen
- Q-24.1–Q-24.4 entschieden 2026-10-30 (siehe Spec).
- Q-24.5, Q-24.6 entschieden in `/architecture` (Factory-ADR-063 E10–E16); dabei neu AK-24f (Gate `pr-closes-issue`).

## Review-Findings
<!-- Wird durch /review befüllt -->
Review-Iteration 1 (`tasks/review-24.md`, NEEDS_REWORK) – Rework 2026-10-31, alle Findings behoben:
- K1 Selbst-Ersatz: Aufrufzeile `main "$@"; exit $?` (bash liest nach `main` nichts mehr aus der von
  `factory-sync.sh` ersetzten Datei). E2E-Test läuft aus dem Konsumenten-Checkout gegen eine verlängerte
  Zielversion + Mutationsbeleg (ohne `exit` → rot).
- W1 Marke: nur der Body-Kopf vor der ersten `## `-Überschrift zählt; Test mit zitierter Marke in den Notes.
- N1 `permissions.push`: offline nicht klärbar – `OPERATING.md` §0.6 benennt ehrlich, dass zu knappe Rechte
  ggf. erst beim Push/PR rot werden; am echten Repo in T2a-4 gegenprüfen.
- N2 `ORIG_REF` neben `WORK`; N3 Weltnamen per Zähler (`next_world_24`), Mutanten-Scaffold als `factory_scripts_24`.

Review-Iteration 2 (`tasks/review-24.md`, NEEDS_REWORK) – Rework 2026-10-31:
- W1 ADR-063 E11.4: Marke zählt nur im Kopf des Bodys (vor der ersten Release-Überschrift aus E13).
- W2 Vorbehalt „zu wenig Rechte" in Spec (FS-T2.3 + neue offene Frage Q-24.7), ADR E11.2 und hier bei FS-T2.3.
- N (65 536-Zeichen-Grenze des PR-Bodys): bewusst nicht umgesetzt – optional, die Notes sind
  CHANGELOG-Abschnitte; ein zu langer Body macht den Lauf rot, nicht still falsch.

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/24-factory-update-workflow-update-pr`
Erstellt: 2026-10-30 21:48
