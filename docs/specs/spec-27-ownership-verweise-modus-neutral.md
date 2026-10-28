# Spec: Ausgelieferte Verweise auf `OWNERSHIP.md` modus-neutral fassen (#27)

## Kontext

Seit Factory-ADR-064 D5 gehört `docs/factory/OWNERSHIP.md` dem Repo (Seite `project`) und wird nicht
mehr ausgeliefert. Ein Konsument bestimmt die Seite `factory` über `factory.lock` (Lock-Modus), das
Factory-Repo selbst über die Tabelle (Tabellenmodus). Beide Modi beantworten dieselbe Frage über ein
Kommando: `bash scripts/checks/ownership-check.sh --list factory`.

Ausgelieferte Dateien formulieren die Zuordnungsregel („betroffene Datei laut `OWNERSHIP.md`") aber
weiterhin über die Tabelle. Im Konsumenten sind das tote Links, und die Regel ist dort nicht auswertbar:
Ein Agent, der in einem Konsumenten `/codify`, `/review` oder `/security-review` ausführt, findet die
Tabelle nicht und kann Lesson- bzw. Kleinfund-Ort nicht regelgerecht bestimmen.

Herkunft: Review zu Task #22 (`tasks/review-22.md`, PR #25). Gehört zur Erst-Einbindung (T2a-4) und
muss vor #23/#24 erledigt sein.

## Scope

**Inbegriffen** (Entscheidung Mensch, 2026-10-28):
- Die Zuordnungsregel in diesen ausgelieferten Dateien, wie im Issue genannt:
  - `.claude/commands/codify.md` (Lesson-Ort und Kleinfund-Ort)
  - `.claude/commands/review.md` (Kleinfund-Ort)
  - `.claude/commands/security-review.md` (Kleinfund-Ort)
  - `docs/factory/FACTORY.md` (Kopfzeile „Besitzer: Factory")
  - `docs/factory/OPERATING.md` (Lesson-Ort)
  - `docs/factory/guidelines/git-workflow.md` (Kleinfund-Ort)
  - `docs/factory/kleinfunde.md` (Dateikopf)
- Zusätzlich die Dateiköpfe der vier Factory-Lessons, die dieselbe Regel formulieren:
  `docs/factory/lessons/testing.md`, `build-tooling.md`, `code-style.md`, `factory-workflow.md`.
- Bezugsquelle der neuen Formulierung ist das **Kommando** `bash scripts/checks/ownership-check.sh
  --list factory`, nicht eine der beiden Datenquellen (Tabelle oder Lock).
- Die Tests AK-C5 und AK-L1 aus nothra/tch-gastro-services#426 in `scripts/checks/tests/run-tests.sh`
  prüfen den neuen Wortlaut statt des alten.
- Eine Regressionssperre: Sie meldet, wenn eine ausgelieferte Datei die Zuordnungsregel wieder über
  `OWNERSHIP.md` formuliert.

**Nicht inbegriffen:**
- ADRs (`docs/factory/adr/**`): Sie halten historische Entscheidungen fest und bleiben unverändert.
- Kommentare und Meldungen in Skripten (`scripts/checks/ownership-check.sh`, `scripts/checks/pre-push.sh`,
  `scripts/factory-release-manifest.sh`). `ownership-check.sh` liest die Tabelle im Tabellenmodus
  tatsächlich, `factory-release-manifest.sh` läuft nur im Factory-Repo.
- Historische Vorfall-Erzählungen in Lessons, die `OWNERSHIP.md` als damaligen Zustand nennen (z. B.
  `docs/factory/lessons/factory-workflow.md`, Abschnitt aus Factory-Task #22).
- Projekteigene Dateien (`CLAUDE.md`, `docs/factory/PROJECT-CONTEXT.md`, `OWNERSHIP.md` selbst). Für das
  Factory-Repo bleibt die Tabelle die gepflegte Quelle.
- Verhaltensänderungen an `ownership-check.sh`, etwa ein anderes Verhalten bei Exit 2.

## Akzeptanzkriterien

- [ ] **AK1** GIVEN eine der elf Dateien im Scope WHEN sie beschreibt, wie die Seite einer Datei bestimmt
  wird (Lesson-Ort, Kleinfund-Ort, Besitzer-Kopf) THEN nennt sie als Quelle das Kommando
  `bash scripts/checks/ownership-check.sh --list factory` und enthält keinen Link und keine
  Pfadangabe auf `OWNERSHIP.md`.
- [ ] **AK2** GIVEN die neue Formulierung WHEN ein Agent sie im Factory-Repo (Tabellenmodus) **oder**
  in einem Konsumenten (Lock-Modus) befolgt THEN führt sie in beiden Fällen zu einem ausführbaren
  Kommando ohne toten Link. Die Formulierung nennt keine modusspezifische Datei als Voraussetzung.
- [ ] **AK3** GIVEN die bisherige inhaltliche Regel (Seite `factory` → `docs/factory/…`, Seite
  `project` → `docs/project/…`, bei mehreren Dateien entscheidet die zuerst genannte) WHEN die
  Formulierung umgestellt ist THEN gilt die Regel inhaltlich unverändert. Geändert wird nur die
  Bezugsquelle.
- [ ] **AK4** GIVEN die Tests AK-C5 (`/codify`) und AK-L1 (`/codify`, `/review`, `/security-review`) in
  `scripts/checks/tests/run-tests.sh` WHEN die ausgelieferte Suite läuft THEN prüfen sie, dass die
  jeweilige Zuordnungsregel das Kommando nennt, und nicht mehr den Pfad `docs/factory/OWNERSHIP.md`.
  *Beleg: Mutation – das Kommando aus einem der drei Skills entfernen → Test rot.*
- [ ] **AK5** GIVEN die ausgelieferte Suite WHEN eine Datei der Seite `factory` außerhalb einer
  ausdrücklich benannten Ausnahmeliste einen Verweis auf `OWNERSHIP.md` enthält THEN schlägt eine
  Assertion fehl und nennt Datei und Zeile.
  *Beleg: Mutation – einen alten Verweis in eine der elf Dateien zurücksetzen → rot. Positivkontrolle:
  aktueller Stand → grün.*
- [ ] **AK6** GIVEN die Ausnahmeliste des Guards aus AK5 WHEN man sie liest THEN enthält sie nur die
  Klassen aus „Nicht inbegriffen" (ADRs, die genannten Skripte, die Test-Dateien der Suiten und die
  historischen Lesson-Erzählungen). Jede Ausnahme ist begründet. Keine der elf Scope-Dateien ist
  als ganze Datei ausgenommen. Eine historische Erzählung in einer Scope-Datei wird nur als einzelne
  Stelle ausgenommen.
- [ ] **AK7** GIVEN der Guard aus AK5 in der ausgelieferten Suite WHEN er in einem Konsumenten läuft
  (Lock-Modus, ohne `OWNERSHIP.md`) THEN bestimmt er die Dateimenge der Seite `factory` modus-neutral
  und liest keine projekteigene Datei (konsumenten-neutral nach Factory-ADR-064 D6).
- [ ] **AK8** GIVEN die geänderten Dateien WHEN `scripts/checks/pre-push.sh` und beide Test-Suiten laufen
  THEN sind alle Gates grün, einschließlich @import-Deckel (`FACTORY.md` ist importiert) und
  Factory-Integrität.

## Fehlerszenarien

- [ ] **F1** Der Guard aus AK5 kann die Dateimenge der Seite `factory` nicht bestimmen (das Kommando
  liefert Exit ≠ 0 oder eine leere Liste) → die Assertion ist rot (fail-closed), nicht still grün.
- [ ] **F2** Ein Verweis steht über einen Zeilenumbruch verteilt (Link-Text und Ziel auf
  verschiedenen Zeilen) → der Guard findet ihn trotzdem. Mindestens die heute vorkommenden Formen
  (Markdown-Link, Pfad in Backticks, bloßer Dateiname `OWNERSHIP.md`) werden erkannt.
- [ ] **F3** Die Suchphrase des Guards steht selbst in einer gescannten Datei → kein Dauer-Rot
  (siehe Lesson aus nothra/tch-gastro-services#319: Phrase zur Laufzeit zusammensetzen oder Test-Datei
  ausnehmen).

## Randbedingungen

- Änderungen unter `.claude/**` laufen über den Patch-Workflow (Lesson aus
  nothra/tch-gastro-services#91). Tests prüfen den Endzustand der committeten Live-Datei
  (Lesson aus nothra/tch-gastro-services#212).
- Text-Tests gegen Markdown-Prosa: Die Testphrase steht auf einer Zeile, oder es wird ein
  zeilenumbruch-toleranter Lese-Helfer genutzt (Lesson aus nothra/tch-gastro-services#240/#286).

## Offene Fragen

- [x] Umfang über die Issue-Liste hinaus? → Lesson-Köpfe ja, Skript-Kommentare nein (Mensch, 2026-10-28).
- [x] Bezugsquelle? → das Kommando `ownership-check.sh --list factory` (Mensch, 2026-10-28).
- [x] Regressionssperre? → ja, mit begründeter Ausnahmeliste (Mensch, 2026-10-28).
