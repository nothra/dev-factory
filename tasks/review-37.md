# Review: Task 37

> Runden 1–3 (Logik, Code-Qualität, Architektur) direkt im Orchestrator-Kontext durchgeführt (Lesson
> „Fork-Kontamination“, nothra/tch-gastro-services#298/#267). Geprüft: `git diff origin/main...HEAD`, Spec #37, ADR-063
> Nachtrag E17–E22; Suite grün (2211 / 145), Syntaxprüfung grün.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)
- [ ] scripts/factory-update.sh:189 (`verify_bundle`) – `publish` prüft das frisch geholte Manifest nur auf Form (`fl_validate_manifest`), nicht auf geschützte Pfade (`fl_protected_findings`: Projektbereiche wie `tasks/`, `docs/adr/`, `scripts/project/` und Anpassungsstellen). `factory-sync.sh` lehnt ein solches Manifest ab (`fetch_and_check_manifest`); ein bösartiges Release (Asset-Manifest **und** Abholcode sind beide Release-Eigentum) kann die Sperre umgehen, weil `publish` jeden Pfad des Manifests in die Erlaubt-Liste aufnimmt – AK-37c verspricht „nur erwartete Pfade“, ADR E18 „Pfade ⊆ … neuen Manifests“, und der Projektbesitz-Schutz (ADR-063 E6) ist der erwartete Rahmen. Fix: `fl_protected_findings "$WORK/manifest.json"` in `verify_bundle` (nicht leer oder Rückgabe ≠ 0 → `die`), plus Test mit Fixture-Release, dessen Manifest/Abholung eine Datei unter `tasks/` bzw. an einer Anpassungsstelle liefert, und Mutationsbeleg.
- [ ] .github/workflows/factory-update.yml:98 – `upload-artifact@v4` ohne `overwrite: true`: Artefaktnamen sind pro Workflow-Lauf eindeutig, `github.run_id` bleibt bei „Re-run all jobs“ gleich → der zweite Versuch scheitert im Job `fetch` mit „artifact already exists“, obwohl der Lauf sonst grün wäre. Fix: `overwrite: true` (oder `run_attempt` in den Namen) – und im Download-Schritt denselben Namen verwenden; Wiring-Anker in `wf_ok_37` mitziehen.
- [ ] docs/specs/spec-37-factory-sync-token-trennen.md:84 – Spec-Drift (Lesson nothra/tch-gastro-services#253/#211): AK-37d verlangt „bestehende Tests aus spec-24 laufen unverändert grün (kein Test abgeschwächt)“, umgesetzt sind aber vier angepasste Anker (Rückkehr auf `ORIG_REF` entfällt – die Mutationsprüfung dazu ist ersatzlos weggefallen, `HEAD:`→`<sha>:`-Push-Ziel, Selbst-Ersatz im Modus `fetch`, `wf_wired_24`→`wf_ok_37`). Task-Datei und ADR E22e benennen das, die Spec nicht. Fix: AK-37d-Wortlaut (und die Zuordnungstabelle) an den Ist-Stand angleichen oder die Abweichung als bewusste Entscheidung in der Spec vermerken.

## Nitpicks (optional)
- [ ] scripts/factory-update.sh:51 – `COMPOSED_TARGETS=(.claude/settings.json .gitignore)` dupliziert `SETTINGS_TARGET`/`GITIGNORE_TARGET` aus `factory-sync.sh:42,45` (Magic Strings, Drift-Risiko: ein drittes zusammengesetztes Ziel im Sync würde in `publish` als „unerwarteter Pfad“ rot). Ein Drift-Guard-Test (je Seite ein Negativtest) oder ein gemeinsamer Ort wäre sauberer.
- [ ] scripts/checks/tests/factory-lock-tests.sh (Block #37, `publish`-Aufrufe der Argument-Tests) – derselbe lange `env_23 … publish …`-Aufruf steht dreimal wörtlich statt über `pub_37` (parametrisiert auf Version/Basis); Duplikation im Test (Lesson nothra/tch-gastro-services#240/#267).
- [ ] CHANGELOG.md – der Hinweis „Secret **vor** dem Update umziehen, sonst endet `guard` rot“ (ADR-Konsequenzen, Task-Notiz) steht noch nirgends als Release-Notiz; gehört in den Release-PR (Seite `project`), hier nur vormerken.

## Positives
- Trennung sauber an Job-/Prozessgrenzen statt `env -u`; Wiring-Prüfer `wf_ok_37` je Job mit neun Mutationsbelegen, `guard`/`preflight`/`fetch`/`publish` mit Prüfung der Job-Abhängigkeiten, `if`-Bedingungen und `main`-Checkout (F-37.3/F-37.4).
- `verify_bundle` ist durchgängig fail-closed und je Prüfung mutationsbelegt (Pfad, Symlink/Submodul, Hash, Lock-Gleichheit, Commit-Anzahl/Elternteil, bewegtes `main`, Existenz, Versionsvergleich); Commit wird mit `commit-tree` neu erzeugt (Autor/Nachricht des Release gelangen nicht in den Branch, mit Test samt Mutation).
- Gegenprobe im Test (Abholung **mit** Token → Marker sieht es) belegt, dass die Trennung die Schutzwirkung trägt, nicht der Testaufbau; die Hostile-Tests laufen CI-treu (Modus `fetch` im Checkout, der die Skripte trägt).
- Ehrliches Restrisiko im ADR-Nachtrag; Doku-Guards je Anker mit Mutation; SIGPIPE-Falle (pipefail) im eigenen Test erkannt und behoben.

## Empfehlung
NEEDS_REWORK
