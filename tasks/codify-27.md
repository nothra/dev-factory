## Codify-Report: Task 27

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` (+ Index-Zeile in `PROJECT-CONTEXT.md`) – Guard-Scan-Helfer: Scanner mit Exit 1 bei Fund plus `| grep -q` ist unter `pipefail` rot, wenn der Guard richtig arbeitet; Mutation in geteilter Fixture sofort zurücknehmen – wegen: fünf rote Tests nach dem ersten Suite-Lauf, beide Ursachen im Test, nicht im Guard.
- `PROJECT-CONTEXT.md` (Index, Turn-Limit-Zeile) – sechstes Vorkommnis: `/implement` riss 3×20 Turns bei 11 Dateien + Guard; die uncommittete Teilarbeit war fast fertig, Diff gegen die AK prüfen und manuell fortsetzen statt Neustart.

### Keine Änderungen nötig
- Review und Security-Review: keine kritischen/wichtigen Findings, nur Nitpicks (kosmetisch, in `tasks/review-27.md`).
- Keine Out-of-Scope-Funde, daher weder Issue noch `kleinfunde.md`-Eintrag.

### Empfehlung für nächste Features
- Tasks mit > 10 Dateien plus neuem Guard vor `run-pipeline.sh` teilen (Verweis-Umstellung / Guard) oder `/implement` manuell fahren.
- `.claude/**`-Änderungen kommen als `tasks/patch-<id>.diff`; der Mensch wendet ihn an, danach laufen Tests erst grün – den Patch-Schritt früh anfordern.
- Telemetrie: Der Lauf wurde nach dem Pipeline-Abbruch manuell fortgesetzt, die OTEL-Messwerte fehlen (keine CSV für Task 27).
