# Review: Task 27

> Alle drei Runden (Logik, Code-Qualität, Architektur) wurden direkt im Orchestrator-Kontext durchgeführt,
> ohne Sub-Agenten (Lesson aus nothra/tch-gastro-services#298/#267). Grundlage: `git diff origin/main...HEAD`
> (Commit c439773), Spec `docs/specs/spec-27-ownership-verweise-modus-neutral.md`, beide Suiten
> (1956 bzw. 145 grün).

## Kritische Findings (müssen behoben werden)
- keine

## Wichtige Findings (sollten behoben werden)
- keine

## Nitpicks (optional)
- [ ] docs/factory/lessons/{testing,build-tooling,code-style,factory-workflow}.md:7 – Der Satz bricht vor dem Pfeil
  um („… gelistete,\n> → `docs/factory/lessons/`"); lesbarer wäre der Umbruch hinter dem Pfeil. AK3 prüft die Phrase
  bereits zeilenumbruch-tolerant, eine Änderung bräuchte nur eine Anpassung des Wortlauts.
- [ ] docs/specs/spec-27-ownership-verweise-modus-neutral.md – die AK-/F-Checkboxen der Spec sind offen, in der
  Task-Datei abgehakt. Reine Pflegefrage.
- [ ] scripts/checks/tests/run-tests.sh (AK4-Mutation) – die Mutation arbeitet per `sed` auf dem geflachten Text
  statt auf einer Skill-Kopie; sie belegt die Assertion, nicht den Lesepfad. Für AK4 ausreichend.

## Positives
- Alle elf Scope-Dateien nennen das Kommando; `grep` über die Dateimenge der Seite `factory` findet außerhalb der
  begründeten Ausnahmen keinen Verweis auf die Tabelle mehr (AK1/AK2).
- Zuordnungsregel inhaltlich unverändert, Vorrangregel „zuerst genannt" per Test gesichert (AK3).
- Guard: fail-closed bei leerer/unlesbarer Dateimenge und bei Exit ≠ 0 des Kommandos (F1), Suche nach dem
  Dateinamen allein erfasst Zeilenumbruch-Formen (F2), Suchphrase zur Laufzeit zusammengesetzt (F3).
- Ausnahmeliste begründet, historische Stelle nur als Einzelstelle (Datei + Anker); Mutationstest belegt, dass ein
  neuer Verweis in derselben Datei rot wird (AK6).
- Lock-Modus-Fixture ohne Tabelle belegt die Konsumenten-Neutralität (AK7).
- Mutationsbelege je Guard-Seite; Fixture-Leak der AK6-Mutation und `pipefail`-Falle (`| grep -q`) wurden vor
  dem Commit gefunden und behoben.

## Empfehlung
APPROVED
