## Codify-Report: Task 49

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` + Index-Zeile in `PROJECT-CONTEXT.md` – „Turn-Limit: Gegenmaßnahme umgesetzt,
  Fortsetzung nach Netz-Abbruch per Bestandsaufnahme" – wegen: (a) Turn-Limit-Serie (Task 37/47) durch Factory-ADR-065
  an der Ursache behandelt; (b) ein Aufräum-Löschbefehl, verkettet mit `git apply`, ließ den Classifier die ganze Kette
  ablehnen; (c) Patch-Weg für `factory.config.yml.example` war unnötig (Rezidiv der Lesson zu nothra/tch-gastro-services#291).
- Import-Kontext: 780 von 1100 Zeilen (Gate grün).

### Keine Änderungen nötig
Review (APPROVED, keine kritischen Findings) und Security-Review (PASSED) lieferten keine weiteren Muster; die
Test-Findings (Label, Meldung bei vertauschten Stufen) waren bereits durch bestehende Lessons abgedeckt.

### Empfehlung für nächste Features
- Offen (Mensch, `.claude/` für Edit gesperrt): `.claude/commands/pipeline.md:12` – Spec-Muster `spec-$ARGUMENTS-*.md`
  und Vorbedingung „mindestens ein AK" nachziehen (Nitpick aus `/review`, in der Task-Datei vermerkt).
- Telemetrie-Lücke: Fortsatz lief manuell (Stage 2), keine OTEL-Daten (Factory-ADR-049).
