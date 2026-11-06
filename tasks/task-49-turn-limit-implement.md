# Task 49: turn-limit-implement

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [x] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Das Turn-Budget von `/implement` wird nach der AK-Zahl der Spec gestaffelt: 1–5 AK → 20, 6–11 → 40,
ab 12 → 60 Turns. Fehlt die Spec, fehlt ihr AK-Abschnitt oder hat er 0 AK, stoppt die Pipeline vor
`/implement`. `/bug-fix` und die übrigen Skills bleiben unverändert.
Spec: `docs/specs/spec-49-turn-limit-implement.md`

## Akzeptanzkriterien
Volltext (GIVEN/WHEN/THEN) und Fehlerszenarien F1–F6: Spec.

- [x] AK1: 5 AK → `max 20 turns`
- [x] AK2: 6 AK → `max 40 turns`
- [x] AK3: 11 AK → `max 40 turns`
- [x] AK4: 12 AK → `max 60 turns`
- [x] AK5: 18 AK (Größe Task 47) → `max 60 turns`
- [x] AK6: Rework-Iteration nach `/review` nutzt dieselbe Stufe
- [x] AK7: `- [ ]` und `- [x]` zählen gleich (Zählweise wie Modellwahl)
- [x] AK8: Spec fehlt → Stopp vor `/implement`, Exit ≠ 0, Meldung mit Task-ID + Hinweis `/requirements`
- [x] AK9: Abschnitt `## Akzeptanzkriterien` fehlt → Stopp
- [x] AK10: 0 AK → Stopp
- [x] AK11: Stopp greift auch mit `--dry-run`
- [x] AK12: Stopp greift auch mit gesetztem `MAX_TURNS`
- [x] AK13: `MAX_TURNS` überschreibt bei gültiger Spec die Staffelung (Bestand)
- [x] AK14: Stufen-Override in `factory.config.yml` wirkt
- [x] AK15: Gate lehnt Stufen-Budget 81 ab
- [x] AK16: Gate lehnt Stufen-Budget 0 / Nicht-Integer ab
- [x] AK17: Budgets der übrigen Skills unverändert
- [x] AK18: `bug-fix` behält festes `max_turns: 20`
- [x] AK19: Repo-Config setzt keine `skills.*`; Budget kommt end-to-end aus den Defaults (#348)
- [x] AK20: `@reason` + `@tradeoff` (Kosten-Wirkung) an der Staffelung in `factory.defaults.yml`
- [ ] AK21: Doku (`factory.config.yml.example`, `configure-factory.md`, `OPERATING.md`) beschreibt Staffelung; Example nennt Obergrenze 80 – `OPERATING.md` erledigt, Rest im Patch (siehe Blocker)

## Technische Notizen
Entscheidung: [Factory-ADR-065](../docs/factory/adr/065-turn-budget-nach-ak-zahl.md) (Accepted 2026-11-06).

- Config: `skills.implement.max_turns_by_size: { signal: proxy, mid: {from: 6, max_turns: 40}, high: {from: 12, max_turns: 60} }`;
  `max_turns: 20` bleibt Basis (1–5 AK).
- Lib `scripts/lib/tier-select.sh`: neue reine Funktionen `select_max_turns` (Fail-Safe: `high`) und
  `spec_file_for` (eine Spec-Auflösung für Preflight, Modell- und Turn-Wahl, F4); Kopfkommentar mitpflegen.
- `run-pipeline.sh`: `get_max_turns <skill> [task_id]`; `preflight_checks` stoppt bei fehlender Spec,
  fehlendem AK-Abschnitt oder 0 AK mit je eigener Meldung. Kein Interrupt.
- Gate `config-validation-check.sh`: Regel 4d (Signal, `mid.from >= 2`, `high.from > mid.from`, Budgets in `[1, 80]`).
- Doku: `factory.config.yml.example` (auch Obergrenze 80), `configure-factory.md`, `OPERATING.md`,
  `CHANGELOG.md` (Breaking: Stopp ohne Spec); Notizen in ADR-038/ADR-010.
- Reihenfolge: (1) Spec-Fixture-Helfer für die Test-Scaffolds, Suite grün → (2) Lib + Gate →
  (3) Preflight + `get_max_turns` → (4) Doku/ADR-Pflege. In getrennten Skill-Läufen, nicht `run-pipeline.sh`.

### Umsetzungs-Notizen (/implement, 2026-11-06)
- Vorgefunden: Code, Gate, Lib und Tests (Schritte 1–3) lagen uncommittet aus einem früheren Lauf im Baum.
  Diff gegen die AK geprüft und fortgesetzt statt neu begonnen (Lesson „Turn-Limit“). Danach Schritt 4
  (Doku/ADR) ergänzt.
- Gates: `scripts/checks/tests/run-tests.sh` 2443 grün / 0 rot, `scripts/project/tests/run-tests.sh`
  146 grün / 0 rot, `bash -n` über alle `*.sh` grün.
- Spec-Fixture zentral in `mk_spec_fixture` (`scripts/checks/tests/lib/assert-helpers.sh`); Phase-1b-Test
  erwartet jetzt `sonnet` (3 AK → light), vorher lief er ohne Spec über den Fail-Safe `heavy`.
- Telemetrie-Lücke: dieser Fortsatz lief manuell (Stage 2), ohne OTEL-Telemetrie (Factory-ADR-049).
  `tasks/telemetry-raw-49-20261106T120257Z.tmp.txt` (gitignoret) stammt aus dem abgebrochenen Lauf; löschen,
  sobald er nicht mehr gebraucht wird.

Blocker 2026-11-06: Edit/Write auf `.claude/commands/configure-factory.md` und `factory.config.yml.example`
ist für den Agenten gesperrt. Die Änderung liegt als `tasks/patch-49.diff` bei (`git apply --check` grün).
Mensch: `git apply tasks/patch-49.diff`, committen, danach `tasks/patch-49.diff` entfernen und AK21 abhaken.

## Offene Fragen
- [x] Q1–Q3 durch Factory-ADR-065 beantwortet (siehe Spec).
- Hinweis: Rund 116 `run-pipeline.sh`-Aufrufe in der Self-Test-Suite laufen ohne Spec und brauchen eine
  Spec-Fixture (Teil dieser Task). Laut Lesson „Turn-Limit“ (> 10 AK) die Umsetzung in getrennten
  Skill-Läufen fahren.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `improvement/49-turn-limit-implement`
Erstellt: 2026-11-05 11:05
