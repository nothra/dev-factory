# Task 24: factory-update-workflow-update-pr

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [x] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [x] Codify ausgeführt
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

Review-Iteration 3 (`tasks/review-24.md`, APPROVED) – keine Kritisch-/Wichtig-Findings; ein Nitpick:
gitignorete Wegwerf-Dateien (`*.tmp.*`) im Worktree vor `/test` löschen.

Security-Review (`tasks/security-24.md`, NEEDS_FIXES) – Fix 2026-10-31:
- Wichtig (Token bei der Abholung): `factory-sync.sh` läuft per `env -u FACTORY_SYNC_TOKEN -u GH_TOKEN -u GITHUB_TOKEN`
  ohne Anmeldedaten; Test mit Wrapper-Stub (auch der Neustart `--compose --check` ist tokenfrei), Mutationsbeleg mit
  derselben Guard-Funktion. ADR-063 E4 (Prüfung läuft in der neuen Fassung) und E12 präzisiert.
- Hinweise (Release-Notes ungefiltert im Body, Helper ohne Host-Prüfung): bewusst nicht umgesetzt – laut Report
  geringes Risiko bzw. kein Handlungsbedarf. Erneutes `/security-review` steht aus.

Review-Iteration 4 (`tasks/review-24.md`, NEEDS_REWORK) – Rework 2026-10-31:
- W (Hooks sehen das Token): Checkout, Fetch, Commit und Push laufen über `git_nohooks`
  (`-c core.hooksPath=/dev/null`) – nach der Abholung stammen installierte Hooks aus dem ungeprüften Release, der
  `pre-push` erbte das Token, ein rotes Gate darin hätte den Push für F1 verhindert. Test mit protokollierenden Hooks
  (fünf Typen) per `core.hooksPath`, Mutationsbeleg mit derselben Guard-Funktion `hooks_saw_no_token_24`.
  ADR-063 E12 nachgezogen.
- Nitpick: Wegwerf-Sonden `scripts/*.tmp.sh` (gitignoret, nicht im PR) – Löschen manuell, `rm` war nicht freigegeben.

Review-Iteration 5 (`tasks/review-24.md`, APPROVED) – Hook-Finding aus Iteration 4 behoben und per Mutation belegt;
keine Kritisch-/Wichtig-Findings. Nitpick: gitignorete Wegwerf-Dateien (`scripts/*.tmp.sh`, `tasks/telemetry-raw-24-*.tmp.txt`)
vor `/security-review` manuell löschen. Erneutes `/security-review` steht aus.

Security-Review, zweiter Durchgang (`tasks/security-24.md`, NEEDS_FIXES) – Fix 2026-10-31 (`01f00ba`):
Kommentar `factory-update.sh:148-150`, ADR-063 E4 und E12 sagen jetzt, dass `env -u` nur vor versehentlichem
Erben schützt und keine Grenze gegen Release-Code im selben Job ist. Das Restrisiko ist akzeptiert, mit Verweis auf
#37; `env -u`-Aufruf und Test bleiben. Kein Code-Verhalten geändert, Suiten grün (2142 / 145). Erneutes
`/security-review` steht aus. Finding im Wortlaut des Reports:
- Wichtig: `env -u` ist keine Grenze gegen Code aus dem Release im selben Job (`.git/config`-`fsmonitor` vor
  `git add -A` selbst nachgestellt, dazu `/proc/<ppid>/environ`, `sudo`, und PR-Workflows mit Repo-Secrets). Im Scope:
  Kommentar `factory-update.sh:148-149` und ADR-063 E4/E12 ehrlich fassen, Restrisiko benennen, auf #37 verweisen.
  Strukturelle Härtung (Environment-Secret, zwei Jobs) in Issue #37.

Review-Iteration 6 (`tasks/review-24.md`, APPROVED) – Delta seit Iteration 5 (Pagination-Test, Doku-Fix aus dem
zweiten Security-Durchgang) geprüft; keine Kritisch-/Wichtig-Findings, Suiten grün (2142 / 145). Nitpicks: Mutantenlauf
des Pagination-Tests ohne zweigspezifisches Signal, ein langer Zeilenumbruch in ADR-063 E4, gitignorete
`tasks/telemetry-raw-24-*.tmp.txt` liegen noch.

Security-Review, dritter Durchgang (`tasks/security-24.md`, PASSED) – Doku-Fix `01f00ba` deckt das Finding aus dem
zweiten Durchgang; kein ausführbarer Code seitdem geändert. Restrisiko (Token und Release-Code im selben Job) akzeptiert,
verfolgt in #37. Hinweise unverändert (Release-Notes ungefiltert im Body, Helper ohne Host-Prüfung); gitignorete
`tasks/telemetry-raw-24-*.tmp.txt` noch manuell löschen.

## Test-Notizen
/test 2026-10-31: alle AK/FS gegen die Tests geprüft. Lücke: mehrseitige `gh api --paginate`-Antwort (ein Array je
Seite, `add` im Filter) war nie mit zwei Arrays getestet – neuer Test + Mutationsbeleg (ohne `add` rot, derselbe Guard).
Release-Filter (Draft/Pre-Release/Asset/Nicht-SemVer) sind je mit einem höheren Release belegt. Kein Coverage-Werkzeug
für Bash; Abdeckung über AK-Matrix. Suiten grün (2142 / 145). Wegwerf-Dateien `scripts/*.tmp.sh` und
`tasks/telemetry-raw-24-*.tmp.txt` (gitignoret) liegen noch – `rm` war nicht freigegeben, manuell löschen.

## Refactoring-Notizen
/refactor 2026-10-31: `factory-update.sh`, Workflow und Tests gegen die Checkliste geprüft (Naming, Funktionsgröße,
Duplikation, Kommentare) – kein Änderungsbedarf, kein Code geändert. Suiten grün (2124 / 145).
/refactor 2026-10-31 (zweiter Durchgang nach `/test`): erneut kein Änderungsbedarf, kein Code geändert. Suiten grün
(2142 / 145). Ein einzelner Lauf zeigte 1 rot, der nicht reproduzierbar war (zwei Folgeläufe grün, Test unbenannt) –
bei Wiederauftreten Lauf mit Ausgabe sichern. Wegwerf-Dateien (`scripts/*.tmp.sh`, `tasks/telemetry-raw-24-*.tmp.txt`,
gitignoret) liegen weiter; `rm` ist nicht freigegeben – manuell vor `/security-review` löschen.

/refactor 2026-10-31 (dritter Durchgang nach Security-Fix): Delta seit dem zweiten Durchgang ist nur ein Kommentar in
`factory-update.sh` (Restrisiko/#37) plus Doku – kein Änderungsbedarf, kein Code geändert. Suiten grün (2142 / 145).

## Codify-Notizen
/codify 2026-10-31 (`tasks/codify-24.md`): zwei neue Lessons in `factory-workflow.md` (Selbst-Ersatz-Skript; Token +
Release-Code im selben Job) und ein Rezidiv in `build-tooling.md` (Wegwerf-Dateien), je mit Index-Zeile in
`PROJECT-CONTEXT.md`. Kein neuer Check.

---
Branch: `feature/24-factory-update-workflow-update-pr`
Erstellt: 2026-10-30 21:48
