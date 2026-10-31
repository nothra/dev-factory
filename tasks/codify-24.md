## Codify-Report: Task 24

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` (+ Index-Zeile in `PROJECT-CONTEXT.md`) – Skript, das seine eigene Ersetzung
  auslösen kann, endet mit `main "$@"; exit $?`; E2E gegen verlängerte Zielversion + Mutationsbeleg – wegen: K1 aus
  Review-Iteration 1 (Selbst-Ersatz durch `factory-sync.sh`).
- `docs/factory/lessons/factory-workflow.md` (+ Index-Zeile) – Token und ungeprüfter Release-Code im selben Job: Token nur
  für nötige Schritte, Hooks per `core.hooksPath=/dev/null` aus, `env -u` ist keine Grenze, Restrisiko im ADR + Issue #37 –
  wegen: Review-Iteration 4 (Hook erbt Token) und `/security-review` Durchgang 1–3.
- `docs/factory/lessons/build-tooling.md` (+ Index-Zeile) – fünftes Vorkommnis liegengebliebener Wegwerf-Dateien
  (`telemetry-raw-24-*.tmp.txt`, `scripts/*.tmp.sh`) – wegen: sechs Läufe lang nur vermerkt, nie gelöscht.

### Keine Änderungen nötig
- Marke nur im Body-Kopf, Pagination (`add` im Filter): taskspezifisch, durch Tests + ADR-063 E11/E13 abgedeckt.
- Doku-Drift in ADR/Kommentar nach Rework: bereits durch bestehende Lessons (nothra/tch-gastro-services#55/#211) gedeckt.

### Empfehlung für nächste Features
- Vor Merge `tasks/telemetry-raw-24-*.tmp.txt` und `scripts/*.tmp.sh` manuell löschen (gitignoret, nicht im PR).
- T2a-4: Token-Rechte (Q-24.7, „zu wenig Rechte") am echten Repo gegenprüfen; #37 für die strukturelle Härtung.
