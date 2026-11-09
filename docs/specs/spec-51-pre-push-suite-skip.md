# Spec: Factory-Suite bei reinen Spec-/Task-Änderungen überspringen

## Kontext

Im Factory-Repo zeigt `commands.test` (`factory.config.yml`) auf die komplette ausgelieferte Suite
`bash scripts/checks/tests/run-tests.sh`. Die Suite läuft damit an zwei Stellen:

- im lokalen pre-push-Hook (`scripts/checks/pre-push.sh`, Check 1) bei **jedem** Push,
- in `scripts/run-pipeline.sh` als Quality-Gate nach `/implement`, nach jedem Review-Rework und nach
  `/refactor`.

Lokal dauert ein Lauf rund 566 s (~9,5 min, gemessen 2026-11-05, macOS). Typischer Auslöser ohne
Nutzen: der Push nach `start-work.sh` bzw. `/requirements`, der nur eine Task-Datei und eine Spec
enthält. Dass der Lauf redundant ist, hat zwei Gründe. Lokale Hooks sind nur Feedback und lassen sich
umgehen. Fail-closed ist erst das Ruleset `protect-main`, und dessen Required Check
`factory-self-test` führt dieselbe Suite in CI ohnehin aus.

In adoptierenden Projekten tritt das Problem nicht auf: dort ist `commands.test` die Produkt-Suite.
Die Änderung betrifft deshalb nur dieses Repo.

## Scope

**Inbegriffen:**

- Das in `commands.test` konfigurierte Kommando des Factory-Repos überspringt die ausgelieferte Suite,
  wenn **alle** Änderungen des Branchs gegenüber `origin/main` ausschließlich unter `tasks/` oder
  `docs/specs/` liegen. In jedem anderen Fall führt es die Suite unverändert aus.
- Die Regel gilt für **jeden** Aufrufer von `commands.test` gleich: für den pre-push-Hook und für die
  Quality-Gates von `run-pipeline.sh` (Entscheidung Q1).
- Ein Override per Umgebungsvariable erzwingt den vollen Lauf trotz reinem Spec-/Task-Diff
  (Entscheidung Q2). Den Namen der Variable legt `/architecture` bzw. `/implement` fest.
- Der Skip ist sichtbar: Eine Meldung nennt den Grund.
- Tests für das neue Verhalten in der Projekt-Suite (`scripts/project/tests/run-tests.sh`).
- Eine `OWNERSHIP.md`-Zeile (Seite `project`) für jede neue getrackte Datei.

**Nicht inbegriffen:**

- Änderungen an ausgelieferten Dateien (Seite `factory`): `pre-push.sh`, `run-pipeline.sh`,
  `gate-config.sh` und die ausgelieferte Suite bleiben unverändert.
- Die übrigen pre-push-Checks: Typecheck, Format, `pre-push.d` (Projekt-Suite), Hooks,
  `@import`-Deckel, Ownership, Integrität und Branch laufen weiter wie bisher.
- CI: Die Jobs `factory-self-test` und `project-self-test` bleiben unverändert und laufen immer.
- Weitere Pfade als Skip-Grund, z. B. andere `docs/`-Bereiche. Die ausgelieferte Suite enthält
  Doku-Guards über `docs/factory/`, deshalb kommen nur `tasks/` und `docs/specs/` in Frage.
- Eine Beschleunigung der Suite selbst und eine Teilauswahl von Tests nach geänderten Dateien.

## Begriffe

- **Änderungsmenge:** alle Pfade, die sich gegenüber dem Merge-Base von `HEAD` und `origin/main`
  unterscheiden. Dazu gehören committete Änderungen des Branchs, uncommittete Änderungen (staged und
  unstaged) sowie untracked, nicht ignorierte Dateien. Bei einer Umbenennung zählen Quell- und
  Zielpfad.
- **Erlaubte Pfade:** `tasks/**` und `docs/specs/**`.

## Akzeptanzkriterien

- [ ] **AK1 – Skip:** GIVEN ein Branch, dessen Änderungsmenge nicht leer ist und nur aus Pfaden unter
  `tasks/` und `docs/specs/` besteht, WHEN das Kommando aus `commands.test` läuft, THEN startet die
  ausgelieferte Suite nicht, das Kommando endet mit Exit 0, und die Ausgabe nennt den Skip samt Grund
  (nur Spec-/Task-Dateien geändert).
- [ ] **AK2 – Voller Lauf bei anderer Datei:** GIVEN eine Änderungsmenge mit mindestens einem Pfad
  außerhalb von `tasks/` und `docs/specs/`, WHEN das Kommando läuft, THEN läuft die ausgelieferte
  Suite vollständig, und ihr Exit-Code wird unverändert durchgereicht (Rot bleibt Rot, Grün bleibt
  Grün).
- [ ] **AK3 – Uncommittete/untracked Änderungen zählen mit:** GIVEN committete Änderungen nur unter
  den erlaubten Pfaden, aber eine uncommittete oder untracked, nicht ignorierte Datei außerhalb davon,
  WHEN das Kommando läuft, THEN läuft die Suite vollständig. Damit greift der Skip auch in den
  Pipeline-Gates, die auf dem Working Tree laufen, nur bei wirklich reinem Spec-/Task-Stand.
- [ ] **AK4 – Umbenennung:** GIVEN eine Umbenennung von einem Pfad außerhalb der erlaubten Pfade nach
  `tasks/` bzw. `docs/specs/` (oder umgekehrt), WHEN das Kommando läuft, THEN läuft die Suite
  vollständig.
- [ ] **AK5 – Override:** GIVEN eine Änderungsmenge wie in AK1 und die gesetzte Override-Variable,
  WHEN das Kommando läuft, THEN läuft die Suite vollständig, und die Ausgabe nennt den Override als
  Grund.
- [ ] **AK6 – Gleiches Verhalten für alle Aufrufer:** GIVEN `commands.test` in `factory.config.yml`,
  WHEN der pre-push-Hook oder ein `run-pipeline.sh`-Quality-Gate das Test-Kommando auflöst, THEN
  erhalten beide dasselbe Kommando mit derselben Skip-Regel (keine Sonderbehandlung je Aufrufer).
- [ ] **AK7 – Ausgelieferte Dateien unverändert:** GIVEN der fertige PR, WHEN man
  `git diff origin/main...HEAD` auf Dateien der Seite `factory` (`OWNERSHIP.md`) filtert, THEN ist
  die Liste leer.
- [ ] **AK8 – Ownership:** GIVEN jede im PR neu getrackte Datei, WHEN `ownership-check.sh` läuft,
  THEN ist sie genau einmal der Seite `project` zugeordnet, und der Check ist grün.
- [ ] **AK9 – Tests:** GIVEN die Projekt-Suite, WHEN sie läuft, THEN deckt sie AK1–AK5 sowie die
  Fehlerszenarien F1–F3 jeweils mit einem eigenen Test ab, und jeder Negativtest belegt seinen
  Ziel-Pfad per pfadspezifischer Meldung (Lesson „Negativ-Test mit mehreren Fail-Pfaden isolieren").

## Fehlerszenarien

Grundsatz: Im Zweifel läuft die Suite. Der Skip greift nur, wenn die Änderungsmenge sicher bestimmt
ist und nur erlaubte Pfade enthält (fail-closed).

- [ ] **F1 – `origin/main` fehlt oder Merge-Base nicht bestimmbar** (kein Remote, flacher Klon ohne
  gemeinsamen Vorfahren, fehlender Ref): Die Suite läuft vollständig, und die Ausgabe nennt den Grund.
- [ ] **F2 – Leere Änderungsmenge** (z. B. `HEAD` gleich `origin/main`): Die Suite läuft vollständig.
  Ohne Änderungen gibt es keinen Beleg für „nur Spec/Task".
- [ ] **F3 – Git-Befehl zur Bestimmung der Änderungsmenge scheitert** (nicht in einem Git-Repo,
  Fehler bei `diff`/`status`): Die Suite läuft vollständig. Ein Fehler wird nie als „nur erlaubte
  Pfade" gelesen.
- [ ] **F4 – Pfade mit Leerzeichen/Sonderzeichen:** Sie werden korrekt klassifiziert. Eine Datei
  außerhalb der erlaubten Pfade darf nicht durch Zeichen im Namen als erlaubt erscheinen.
- [ ] **F5 – Präfix-Verwechslung:** Pfade wie `tasks-old/x` oder `docs/specs-archive/x` zählen
  **nicht** als erlaubt; es zählt nur das Verzeichnis selbst.

## Offene Fragen

- [x] Q1: Gilt der Skip auch für die `run-pipeline.sh`-Gates? → **Ja**, eine Regel für alle Aufrufer
  von `commands.test` (Entwickler, 2026-11-09).
- [x] Q2: Override zum Erzwingen des vollen Laufs? → **Ja**, per Umgebungsvariable; den Namen legen
  `/architecture` bzw. `/implement` fest (Entwickler, 2026-11-09).
- [ ] Q3 (für `/architecture`, falls ADR-Trigger): Braucht die Abweichung vom Grundsatz „pre-push
  führt `commands.test` vollständig aus" eine Projekt-ADR, oder reicht der Kommentar in
  `factory.config.yml` plus die Spec?
