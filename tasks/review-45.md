# Review: Task 45

> Iteration 1, 2026-11-13. Geprüft wurde der **nicht committete Arbeitsbaum** (`git diff`, 9 Dateien)
> plus `tasks/patch-45.diff` (`.claude/commands/implement.md`, `review.md`, `codify.md`, `.gitignore`).
> `git diff origin/main...HEAD` enthält nur Spec und Task-Anlage, siehe W3.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] [scripts/project/tests/run-tests.sh:557 (`STACK_PATHS_45`), :571-585 (AK12-Tests)] **Der Stack-Guard
  belegt nur, dass er `.claude/commands/` prüft, nicht die vier anderen Pfade.** Alle AK12-Fixtures
  schreiben nach `.claude/commands/skill.md`; die AK15-Prüfung am echten Baum ist trivial grün, wenn
  ein Pfad fehlt; die fail-closed-Zählung greift nur bei **null** Dateien insgesamt. Streicht oder
  vertippt man `scripts/checks/pre-push.sh`, `docs/factory/gitignore.factory`, `docs/factory/agents`
  oder `docs/factory/guidelines` in `STACK_PATHS_45`, bleibt die ganze Suite grün und der Guard prüft
  die Datei still nicht mehr. Begründung: Scope 4 der Spec legt die geprüften Dateien fest, AK13 testet
  nur die Gegenrichtung („außerhalb ist kein Treffer"). Lessons „Spiegel-Akzeptanzkriterien beide
  Richtungen" (nothra/tch-gastro-services#211) und „Fail-closed braucht Test, der die Messung bricht"
  (nothra/tch-gastro-services#319). Fix: im Fixture je Eintrag aus `STACK_PATHS_45` eine Datei mit
  einem Begriff anlegen und je Pfad „rot mit Datei und Zeile" prüfen; zusätzlich am echten Baum je Pfad
  „mindestens eine getrackte Datei gefunden" (sonst rot). Mutationsbeleg: einen Pfad aus der Liste
  streichen → genau dessen Test rot.
- [ ] [docs/factory/guidelines/git-workflow.md:72, scripts/checks/pre-push.sh:86-87] **Das
  Gate-Versprechen aus AK1 steht noch an zwei weiteren Anweisungstexten.** Die Hook-Tabelle nennt
  „Format (Prettier), Routen-Doku-Drift" als Teil von `pre-push`, der Kommentar zu Check 4 „u. a. den
  Routen-Doku-Drift-Check". Das ist dieselbe Falschaussage, die die Spec im Kontext begründet; die
  Spec listet die zwei Stellen aber nicht (Scope 1), daher außerhalb des Scopes. Klassifiziert nach
  Factory-ADR-043 als Doku-Drift unter zehn Zeilen → **Eintrag in `docs/factory/kleinfunde.md`**
  („Routen-Doku-Drift-Check wird weiter als Factory-Gate genannt"). Empfehlung: im Rework mitnehmen,
  `pre-push.sh` ist in diesem PR ohnehin geändert (Kleinfunde-Regel); dann Eintrag wieder löschen. Den
  Implement-Vermerk in der Task-Datei („Hinweis außerhalb des Scopes") hat dieser Eintrag damit
  verankert.
- [ ] [tasks/task-45-ursprungs-stack-aus-skills-entfernen.md, Abschnitt „Blocker"] **Die Umsetzung ist
  nicht committet, die Begründung trägt nicht.** Die Task-Datei sagt, es sei nichts committet, „der
  pre-push-Hook würde den Push blockieren". Ein Commit ist davon nicht betroffen: `pre-commit.sh`
  führt die Projekt-Suite nicht aus (nur `pre-commit.d/`). Ohne Commit sieht jeder spätere Schritt mit
  `git diff origin/main...HEAD` (`/test`, `/security-review`, `/refactor`) nur die Spec, und ein
  versehentliches `git checkout`/`reset` verliert die Arbeit. Lesson nothra/tch-gastro-services#391
  („Rework-Ende = sauberes `git status` + Commit, erst dann `/review`"). Fix: die Nicht-Patch-Dateien
  (inkl. dieses Reports und `kleinfunde.md`) jetzt committen, nur den Push bis nach dem Patch-Apply
  zurückhalten; die Blocker-Notiz entsprechend korrigieren.

## Nitpicks (optional)

- [ ] [docs/factory/lessons/testing.md:97] Die in AK7 geänderte Zeile verweist weiter auf
  `lessons/frontend-react.md`. Relativ zu `docs/factory/lessons/` gibt es die Datei nicht; das Thema
  liegt beim Konsumenten unter `docs/project/lessons/`. Vorschlag: „siehe die Projekt-Lesson zu
  Formular-Handlern" ohne Pfad, oder `docs/project/lessons/frontend-react.md` (vor diesem PR schon
  so, aber die Zeile wird hier ohnehin angefasst).
- [ ] [.claude/commands/codify.md:39 (nach Patch)] Die Beispiele für Projekt-Code (`app/`, `db/`,
  `lib/`, E2E) sind die Verzeichnisse des Ursprungs-Projekts. Nicht in der Begriffsliste und als
  Beispiel lesbar; wer den Patch ohnehin anfasst, könnte „(App-/Produktcode des Projekts)" schreiben.
- [ ] [tasks/task-45-ursprungs-stack-aus-skills-entfernen.md, AK16] AK16 ist offen und nicht vom
  Agenten erfüllbar ohne Freigabe zum Posten. Vor `/pr-shepherd` muss der Kommentar an
  nothra/tch-gastro-services#428 stehen und im PR-Body verlinkt sein (Fehlerszenario 4 der Spec);
  den Entwurf um die zwei Stellen aus W2 ergänzen, falls sie im Rework mitgenommen werden.

## Positives

- **AK1/AK2/AK4 (Patch):** Alle bisherigen Pflichten des Oberflächentest-Abschnitts bleiben erhalten
  (automatisiert je AK, interaktiv durchklicken, nicht in den pre-push-Gates); die Stage-3-Regel
  (`implement.md:101-105`) ist unverändert. `reuseExistingServer` ist sinngleich als „startet den
  Dev-Server selbst oder nutzt einen bereits laufenden" übernommen.
- **AK3:** Der generische Kern des Review-Prüfpunkts (Zielumgebung vs. lokaler/CI-Testpfad) bleibt,
  der Herkunftsverweis auf nothra/tch-gastro-services#345 ist korrekt qualifiziert.
- **AK5:** `pre-push.sh` ändert nur Kommentarzeilen (im Diff geprüft), die Herkunftsverweise bleiben.
- **C1-Guard:** Scan und Tests nutzen dieselben Funktionen (`c1_hits_in`, `c1_allowed_place`) – die
  Tests prüfen den echten Guard, keine Kopie; die Liste der erlaubten Stellen steht nur noch an einer
  Stelle. Begriffe weiter zur Laufzeit zusammengesetzt (Lesson nothra/tch-gastro-services#319). Die
  Negativtests decken je langem und je kurzem Begriff einen Fall ab, dazu die vier
  Fehlalarm-Wörter aus AK9.
- **Stack-Guard:** Exit-Codes 0/1/2 sauber getrennt, Lesbarkeit je Datei geprüft, Wegwerf-Kopie ohne
  Commit (keine Git-Identität nötig), AK13-Dateiname gegen den ADR-Link-Check zusammengesetzt; der
  dokumentierte Mutationsbeleg (Ganzwort, ohne `-i`, ohne Zählung) zeigt Kausalität.
- Grep über die geprüften Pfade im Arbeitsbaum: außer den drei Patch-Dateien kein Stack-Begriff mehr
  (`setup-project.md:12` nennt `.eslintrc` als eines von mehreren Beispielen beim Erkennen eines
  fremden Stacks – kein Begriff der Liste, inhaltlich richtig).

## Empfehlung
NEEDS_REWORK
