## Codify-Report: Task 62

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` + Zeile in `lessons/INDEX.md`: CI-Verhalten (welche PRs ein Required Check
  betrifft) aus der Workflow-Datei ableiten und als Bedingung formulieren – wegen: ungenaue Aussage „auch der
  Einbindungs-PR hängt" stand in ADR, OPERATING, CHANGELOG und Spec, Review Runde 1 (2 wichtige Findings).

### Keine Änderungen nötig
Review-Nitpicks (Stil, Präzisierung) und Security-Hinweise sind Einzelfall-Formulierungen ohne wiederkehrendes Muster.

### Offen / Folge-Arbeit
- **Issue nicht angelegt:** OPERATING-Anhang „Branch-Protection richtig einordnen" widerspricht ADR-029/§0.7 (Zweifelsfall →
  Issue, Labels `documentation` + `tech-debt`). `. scripts/lib/create-issue.sh` wurde nicht freigegeben. Vor dem PR nachholen.
- Security-Hinweis (optional): Restrisiko „PR ändert das Gate selbst, siehe #30" im ADR-029-Nachtrag ergänzen.

### Empfehlung für nächste Features
Bei Doku-Tasks mit Verhaltensaussagen zu CI die Aussage vor der Spec-Abnahme gegen die Workflow-Datei prüfen.
