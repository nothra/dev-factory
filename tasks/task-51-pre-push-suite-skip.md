# Task 51: pre-push-suite-skip

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Das `commands.test`-Kommando des Factory-Repos überspringt die ausgelieferte Suite (~9,5 min lokal),
wenn die Änderungsmenge des Branchs gegenüber `origin/main` nur `tasks/**` und `docs/specs/**`
umfasst. Gilt gleich für pre-push-Hook und `run-pipeline.sh`-Gates; Override per Env erzwingt den
vollen Lauf; fail-closed bei unbestimmbarem Diff. Keine Änderung an ausgelieferten Dateien.
Spec: `docs/specs/spec-51-pre-push-suite-skip.md`

## Akzeptanzkriterien
<!-- Von /requirements befüllt – Volltext in der Spec -->
- [ ] AK1 – Skip bei nur `tasks/`/`docs/specs/`, Exit 0, Meldung mit Grund
- [ ] AK2 – Voller Lauf bei anderer Datei, Exit-Code durchgereicht
- [ ] AK3 – Uncommittete/untracked Dateien zählen mit
- [ ] AK4 – Umbenennung über die Pfadgrenze → voller Lauf
- [ ] AK5 – Override-Env erzwingt vollen Lauf, Meldung nennt Override
- [ ] AK6 – Gleiches Verhalten für pre-push und `run-pipeline.sh`
- [ ] AK7 – Keine Änderung an Dateien der Seite `factory`
- [ ] AK8 – Ownership-Zeile (Seite `project`) für neue Dateien, Check grün
- [ ] AK9 – Tests in der Projekt-Suite für AK1–AK5 und F1–F3
- [ ] Fehlerszenarien F1–F5 (fail-closed, Sonderzeichen, Präfix-Verwechslung) abgedeckt

## Technische Notizen
<!-- /architecture, 2026-11-09 -->

### Entscheidung: kein ADR (Q3)

Keiner der vier ADR-Trigger (OPERATING.md §4.1) feuert: keine neue Technologie, kein neues
Architekturmuster, kein Schnittstellen-Vertrag mit Außenwirkung (ausgelieferte Dateien bleiben
unberührt, AK7), und der Schritt ist mit einer Config-Zeile umkehrbar. Ein Ablageort fehlt zudem:
`docs/factory/adr/` ist Seite `factory` und würde an Konsumenten ausgeliefert – eine Regel nur dieses
Repos gehört dort nicht hin; ein `docs/adr/` des Repos existiert nicht und lohnt sich für diesen Fall
nicht. Die Entscheidung ist hier, in der Spec und im Kopfkommentar des Wrappers festgehalten;
`factory.config.yml` verweist auf den Wrapper. → Q3 erledigt.

### Gewählte Option A: Wrapper unter `scripts/project/` als `commands.test`

Verworfene Alternativen:

| Option | Vorteile | Nachteile |
|--------|----------|-----------|
| **A: Projekt-Wrapper als `commands.test`** (gewählt) | keine Factory-Datei geändert (AK7); deckt pre-push und Pipeline-Gates mit einer Regel (AK6, Q1); umkehrbar | `commands.test` ist nicht mehr wörtlich die Suite – Pin-Test und Doku nachziehen |
| B: Skip-Logik in `pre-push.sh` (Factory) | für alle Konsumenten nutzbar | ändert ausgelieferte Datei (außerhalb Scope); Konsumenten haben das Problem nicht; Pipeline-Gates nicht gedeckt |
| C: `commands.test` = Projekt-Suite, Factory-Suite nur in CI (wie Konsumenten) | spart den Lauf bei *jedem* Push | Pipeline-Gates und lokale Pushes mit Code-Änderung verlieren das Factory-Suite-Feedback; widerspricht AK2 |
| D: `FACTORY_TEST_COMMAND` lokal setzen | null Code | nicht geteilt, nicht getestet, je Entwickler/Session zu wiederholen |

### Implementierungs-Hinweise für `/implement`

- **Datei:** `scripts/project/checks/factory-suite-gate.sh` (Seite `project`, OWNERSHIP-Zeile im
  selben PR – AK8). `factory.config.yml`: `commands.test: "bash scripts/project/checks/factory-suite-gate.sh"`.
  `commands.coverage` bleibt bewusst die volle Suite (nicht im Scope; läuft in der Pipeline nur in `/test`).
- **Wurzel:** `ROOT="${FACTORY_DIR:-<skriptrelativ ../../..>}"` wie `10-project-tests.sh`; alle
  Git-Aufrufe per `git -C "$ROOT"`. Die Suite wird per `exec bash "$ROOT/scripts/checks/tests/run-tests.sh"`
  gestartet – Exit-Code damit unverändert (AK2). Tests legen in einem Wegwerf-Repo einen Stub an diesem
  Pfad ab und setzen `FACTORY_DIR` – kein echter 9-Minuten-Lauf in der Projekt-Suite.
- **Override:** `FACTORY_FORCE_FULL_SUITE` – jeder nicht-leere Wert erzwingt den vollen Lauf (AK5);
  Prüfung vor jeder Git-Abfrage.
- **Änderungsmenge** (alle mit `-z`, jeder Befehl mit eigenem Exit-Check, Ausgabe erst in eine Variable
  bzw. Temp-Datei – keine Prozess-Substitution, die den Exit-Code verschluckt; F3):
  1. `base="$(git merge-base HEAD origin/main)"` – scheitert → voller Lauf mit Grund (F1)
  2. `git diff --name-only -z --no-renames "$base" HEAD` (committet)
  3. `git diff --name-only -z --no-renames HEAD` (staged + unstaged)
  4. `git ls-files -z --others --exclude-standard` (untracked, nicht ignoriert) – AK3
  `--no-renames` liefert bei Umbenennungen Quell- und Zielpfad (AK4).
- **Klassifikation:** NUL-getrennt lesen (`while IFS= read -r -d '' p`), Match per
  `case "$p" in tasks/*|docs/specs/*)` – Schrägstrich im Muster verhindert `tasks-old/` (F5),
  NUL-Trennung schützt vor Sonderzeichen (F4). Leere Menge → voller Lauf (F2).
- **Ausgabe:** Skip-Meldung mit Grund (AK1); jeder Fall mit vollem Lauf nennt seinen Grund
  (Override, Merge-Base fehlt, Git-Fehler, leere Menge, Datei außerhalb) – pfadspezifische Meldungen
  machen die Negativtests eindeutig (AK9, Lesson „Negativ-Test isolieren").
- **Hook-Kontext:** Im pre-push-Hook eines Worktrees exportiert Git `GIT_DIR`/`GIT_WORK_TREE`/
  `GIT_INDEX_FILE`. Für den Wrapper selbst ist das richtig (selbes Repo). Die Tests in der Projekt-Suite
  laufen aber ebenfalls aus dem Hook (`pre-push.d/10-project-tests.sh`) – vor den Wegwerf-Repos diese
  Variablen unsetzen (vgl. `scripts/checks/tests/lib/assert-helpers.sh:20`) und Fixture-Commits mit
  lokaler Git-Identität anlegen (Lesson nothra/tch-gastro-services#265).
- **Mitzuziehen:**
  - `scripts/project/tests/run-tests.sh:428` pinnt `commands.test` auf den alten Wert → auf den Wrapper umstellen.
  - `factory.config.yml`-Kommentar zu `test`.
  - `docs/factory/PROJECT-CONTEXT.md:33` (`(commands.test)` hinter der Suite) → Wrapper nennen.
- **Unberührt:** Die ausgelieferte Suite stubbt `FACTORY_TEST_COMMAND=true` selbst
  (`run-tests.sh:84`) und ist vom neuen Wert nicht betroffen; CI ruft die Suite direkt auf
  (`factory-ci.yml:112`).

## Offene Fragen
- [x] Q3: Projekt-ADR nötig? → Nein, siehe Technische Notizen (`/architecture`, 2026-11-09)

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/51-pre-push-suite-skip`
Erstellt: 2026-11-09 21:20
