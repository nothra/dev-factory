## Codify-Report: Task 28

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` + Index-Zeile in `docs/factory/PROJECT-CONTEXT.md` – Neutralitäts-Guard per Pfad-Grep findet indirekte Leser
  (Check-Skript gegen den echten Repo-Stand) nicht; zusätzlich Fixture-Lauf in Repo-Kopien, rote Tests zwischen den Varianten vergleichen –
  wegen: Review-Fund, Issue #32.

### Keine Änderungen nötig
- Mutationsbelege, Positivkontrolle und Laufzeit-Muster gegen Selbsttreffer waren durch bestehende Lessons (`testing.md`) abgedeckt und wurden von Anfang an angewandt.
- Der Hook-Fehlalarm (`rm -rf` als Text in einem Heredoc) ist Umgebungsverhalten des lokalen Guardrails-Plugins, keine Factory-Regel.

### Empfehlung für nächste Features
- Issue #32 (indirekter Lesezugriff über `import-context-limit-check.sh`) als eigene Task angehen; den AK6-Guard dabei um Aufrufe der Check-Skripte erweitern.
