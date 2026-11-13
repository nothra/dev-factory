# Review: Task 45

> Iteration 2, 2026-11-13. Geprüft: `git diff origin/main...HEAD` (Commit `abca57e`, 12 Dateien) plus
> `tasks/patch-45.diff` (`.claude/commands/implement.md`, `review.md`, `codify.md`, `.gitignore`).
> Projekt-Suite im Arbeitsbaum ohne Patch: 252 grün, 3 rot – genau die drei, die laut Task-Datei erst
> nach dem Apply grün werden (AK15 echter Baum, zwei `.gitignore`-Zusammensetzungs-Guards #431 AK-E3).
> Die Rot-Treffer von AK15 liegen ausschließlich in den drei Patch-Dateien (Grep über die Pfade aus
> Scope 4). Die ausgelieferte Suite wurde nicht gelaufen; ein Grep über `scripts/checks/tests/*.sh`
> findet keinen Guard, der am alten Wortlaut der geänderten Stellen ankert (Fehlerszenario 3).
>
> Iteration 1 (NEEDS_REWORK, W1–W3): alle drei behoben – W1 Pfad-Orakel `SPEC_FILES_45` + Test je Pfad
> am echten Baum, W2 `git-workflow.md:72` und `pre-push.sh:86-87` generisch, W3 Umsetzung committet.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_

## Nitpicks (optional)

- [ ] [docs/factory/lessons/build-tooling.md:32] Die Regel sagt im Präsens „`.gitignore` deckt jetzt
  zusätzlich `*.tmp.spec.ts`/`*.tmp.spec.tsx`". Nach diesem PR stimmt das für `*.tmp.spec.tsx` nicht
  mehr – weder hier noch in einem Konsumenten, der nur `gitignore.factory` bekommt. Die Spec schließt
  Lessons bewusst aus (Q1), aber das hier ist keine Historie, sondern eine Ist-Aussage über eine
  Mechanik, die der PR ändert (Lesson nothra/tch-gastro-services#176). Das Risiko ist klein, weil
  dieselbe Lesson vor jeder Wegwerf-Datei `git check-ignore -v` verlangt. Vorschlag: „deckt
  `*.tmp.spec.ts` (Wegwerf-E2E-Specs; weitere Endungen legt das Projekt in `.gitignore.project` fest)".
- [ ] [scripts/project/tests/run-tests.sh:594, :622] Die fünf Pfade aus Scope 4 stehen als Orakel
  zweimal als Literal da (`SPEC_FILES_45` als Dateien, die AK15-Schleife als Pfade). Eine gemeinsame
  Liste `SPEC_PATHS_45`, aus der die Fixture-Dateien abgeleitet werden, wäre eine Stelle weniger zum
  Pflegen. Die Unabhängigkeit von `STACK_PATHS_45` bleibt dabei erhalten.
- [ ] [scripts/project/tests/run-tests.sh:569] `sed "s#^#$f:#"` setzt den Dateinamen ungeschützt in
  den Ersetzungsteil: ein `#` oder `&` im Pfad würde die Ausgabe verfälschen (bei `#` bricht `sed`
  ab, die Pipeline liefert dann leer und der Treffer ginge verloren). Heute gibt es solche Pfade
  nicht; `printf '%s:%s\n' "$f"` vor jede Zeile (z. B. per `while read`) wäre robust.
- [ ] [.claude/commands/codify.md:43 (nach Patch)] Neu eingefügt ist `„Projekt-Lessons"` mit geradem
  Schlusszeichen, die Nachbarzeile nutzt `„Projekt-Lessons“`. Nur Typografie.
- [ ] [tasks/task-45-ursprungs-stack-aus-skills-entfernen.md, AK16] Weiter offen (aus Iteration 1):
  Kommentar an nothra/tch-gastro-services#428 erst nach Freigabe posten und im PR-Body verlinken; der
  Entwurf sollte die zwei in W2 generisch gemachten Stellen (`git-workflow.md`, `pre-push.sh` Check 4)
  und – falls umgesetzt – die Lesson-Zeile aus Nitpick 1 nennen. Ohne AK16 ist die Task nicht fertig.

## Positives

- **W1 sauber gelöst:** `SPEC_FILES_45` ist bewusst unabhängig von `STACK_PATHS_45` und dient als
  Orakel; der dokumentierte Mutationsbeleg (je gestrichenem Pfad genau dessen Test rot) zeigt
  Kausalität. Zusätzlich prüft AK15 je Pfad „hat getrackte Dateien" – damit ist „sauber" am echten
  Baum nicht mehr trivial grün.
- **AK1/AK2 (Patch):** Alle Pflichten des Oberflächentest-Abschnitts bleiben (automatisiert je AK,
  interaktiv durchklicken, nicht in den pre-push-Gates), die Stage-3-Regel ist unverändert. Auch
  `proxy.ts`, `.env.local` und die Preview-Config sind generisch, obwohl die Begriffsliste sie nicht
  verlangt – AK2 fordert „ohne Werkzeug-, Pfad- oder Config-Namen".
- **AK5:** Im Diff von `pre-push.sh` ändern sich nur Kommentarzeilen; die qualifizierten
  Herkunftsverweise bleiben.
- **C1-Guard:** Scan und Tests nutzen dieselben Funktionen (`c1_hits_in`, `c1_allowed_place`); die
  erlaubten Stellen stehen an genau einer Stelle; je langem und je kurzem Begriff ein Test, dazu die
  vier Fehlalarm-Wörter aus AK9. Begriffe zur Laufzeit zusammengesetzt (Lesson
  nothra/tch-gastro-services#319).
- **Stack-Guard:** Exit 0/1/2 getrennt, Lesbarkeit je Datei geprüft, Wegwerf-Kopie ohne Commit, der
  AK13-Dateiname gegen den ADR-Link-Check zusammengesetzt.
- **Arbeitsstand:** Umsetzung committet, nur der Push wartet begründet auf den Patch-Apply; die
  Task-Datei beschreibt Blocker und Nachschritte korrekt.

## Empfehlung
APPROVED
