# Review: Task 24

Review-Iteration 3 (letzte vor dem Circuit Breaker). Diff-Basis: `git diff origin/main...HEAD` (3ad8017). Spec:
`docs/specs/spec-24-factory-update-workflow-update-pr.md`, Entscheidungen: Factory-ADR-063 Nachtrag 2026-10-30
(E10–E16). Drei Runden (Logik, Code-Qualität, Architektur) im Orchestrator-Kontext, ohne Fork-Delegation.
Lokal: ausgelieferte Suite `scripts/checks/tests/run-tests.sh` 2091 grün / 0 rot, Projekt-Suite
`scripts/project/tests/run-tests.sh` 145 grün / 0 rot.

Iteration 2 (NEEDS_REWORK) ist vollständig abgearbeitet (Commit 3ad8017):
- W1: ADR-063 E11.4 nennt jetzt „im Kopf des Bodys (vor der ersten Release-Überschrift aus E13)“ und schließt
  zitierte Release Notes ausdrücklich aus. Das deckt sich mit `scripts/factory-update.sh:128-130` (`split("\n## ")[0]`).
- W2: Den Vorbehalt „zu wenig Rechte“ tragen jetzt die Spec (FS-T2.3 plus neue offene Frage Q-24.7), ADR E11.2,
  `OPERATING.md` §0.6 und die Task-Datei bei FS-T2.3, alle mit derselben Aussage. Rot wird der Lauf in jedem Fall,
  der Beleg am echten Repo folgt in T2a-4.
- Den Nitpick zur Grenze von 65 536 Zeichen hat das Rework begründet zurückgestellt (Task-Datei). Ein zu langer Body
  macht den Lauf rot, er wird nicht still falsch. Das ist akzeptabel.

## Kritische Findings (müssen behoben werden)
_(keine)_

## Wichtige Findings (sollten behoben werden)
_(keine)_

## Nitpicks (optional)
- [ ] [Arbeitsbaum, nicht im Diff] Im Worktree liegen gitignorete Wegwerf-Dateien aus früheren Runden:
  `scripts/review24-repro.tmp.sh`, `scripts/checks/tests/lock24.tmp.sh`, `tasks/.ak24.tmp.txt` (dazu `tasks/.rt24.tmp.log`
  aus diesem Review-Lauf; die Freigabe für `rm` fehlte). Sie landen nicht im PR. Laut Lesson `build-tooling.md`
  (nothra/tch-gastro-services#372) gehören sie aber direkt nach der Nutzung gelöscht. Verzeichnisweite Content-Scan-Guards
  können sie sonst später fälschlich treffen (Lesson nothra/tch-gastro-services#312). Spätestens vor `/test` löschen.

## Positives
- Alle Akzeptanzkriterien und Fehlerszenarien sind verhaltensnah belegt, jeweils über einen echten Lauf gegen
  Bare-Origin und `gh`-Stub mit Aufruf-Protokoll: AK2.2d, AK2.4, AK2.4b, F3, AK-24a–f, F1, FS-T2.3, F-24.1–F-24.3.
  Die Mutationsbelege für Token-Prüfung, Fork-Bedingung, Workflow-Token-Zeile und Selbst-Ersatz (`main "$@"; exit $?`)
  zielen jeweils auf genau die echte Zeile (Lessons nothra/tch-gastro-services#286/#310).
- Die Reihenfolge aus E11 ist im Skript eins zu eins abgebildet. Fail-closed gilt an jeder Stelle: Lock, Token,
  Release-Liste (Prüfung auf JSON-Array), PR-Listen, Fetch, sauberer Arbeitsbaum, Abholung, Commit, Push mit Lease.
- Das Token steht nirgends in argv, URL oder `.git/config`. Der Credential-Helper wird per `-c` gesetzt, ein leerer
  Helper davor setzt geerbte Helper außer Kraft, `GITHUB_TOKEN` wird explizit `unset`. Im Workflow gelten
  `persist-credentials: false` und `contents: read`.
- Die Commit-Identität ist explizit gesetzt (Lesson nothra/tch-gastro-services#334), `yq` kommt über den Seam
  `install-yq.sh`, Versionen werden numerisch verglichen statt mit `sort -V`.
- Die Doku ist konsistent und ehrlich. `OPERATING.md` §0.6 (Anlegen, Rechte, Rotation, Symptom), der Verweis aus
  §5.5a, die Ausnahme in `git-workflow.md`, die Gate-Kommentare („Hygiene-Gate, keine Sicherheitsgrenze“) und die
  zwei `OWNERSHIP.md`-Zeilen passen zueinander.
- Architektur: ADR-063 D2/E10–E16 eingehalten (der Workflow löst nur aus, die Logik steht im Skript), ADR-029
  ebenfalls (Check-Name `pr-closes-issue` unverändert), ADR-064 D6 auch (die Tests liegen in der ausgelieferten,
  konsumenten-neutralen Suite). Keine Routen-Änderung, `docs/routes.md` ist nicht betroffen.

## Empfehlung
APPROVED
