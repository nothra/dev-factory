# /daily-metrics – Prozess-Kennzahlen der Factory

Erzeugt einen Health-/Velocity-Report aus deterministischen Quellen (Git, GitHub,
Task-Dateien) und gibt ihn optional als GitHub-Kommentar aus.

> **Mess-Ebene (ADR-006):** Dieser Skill misst **Prozess** – Lead-Time,
> Autonomie-Rate, CI-Quote, Interrupts, Durchsatz. **Token und Kosten gehören
> NICHT hierher** – die liefert die Telemetrie-Ebene (OTEL, `config/otel.env.example`).
> Kein eigenes Token-Accounting nachbauen.

## Ablauf

Der Skill ist ein dünner Wrapper um ein deterministisches Skript – die Bash
rechnet, der Agent interpretiert und verteilt nur.

### Schritt 1: Report erzeugen

```bash
bash scripts/metrics.sh
```

Das Skript schreibt `tasks/metrics-<datum>.md` und gibt den Report aus. Ohne
`gh`/Token laufen die lokalen Metriken trotzdem (Lead-Time/CI-Quote werden
dann als „übersprungen" markiert – local-first, ADR-006).

### Schritt 2: Auffälligkeiten benennen

Lies den Report und hebe hervor, was Aufmerksamkeit braucht:
- **Autonomie-Rate gesunken?** → welche Tasks haben Interrupts ausgelöst (siehe `tasks/interrupt-log.jsonl`)?
- **CI-Grün-Quote niedrig?** → wiederkehrende Gate-Fehler?
- **Lead-Time gestiegen?** → wo stockt der Fluss (Review-Schleifen, offene Interrupts)?
- **Offene Interrupts > 0?** → diese blockieren aktiv und brauchen eine Entscheidung.

### Schritt 3 (optional): Veröffentlichen

Wenn eine Ziel-Issue-/PR-Nummer gegeben ist, den Report als Kommentar posten:

```bash
gh issue comment <issue-nummer> --body-file tasks/metrics-<datum>.md
```

Sonst genügt der Datei-Report.

## Regeln

- Keine Token-/Kosten-Metriken (kommen aus OTEL – ADR-006)
- Nichts erfinden: nur ausgeben, was `metrics.sh` aus echten Quellen berechnet
- Fehlende API-Daten ehrlich als „übersprungen" ausweisen, nicht schätzen

## Output

- `tasks/metrics-<datum>.md` (gitignored – Snapshot, jederzeit regenerierbar)
- Kurze Interpretation der Auffälligkeiten
- Optional: GitHub-Kommentar

## Hinweis für Stage 3 / Automatisierung

Deterministisch, kein Gesprächsgedächtnis nötig. Kann via GitHub Actions Scheduled
Workflow täglich laufen (`bash scripts/metrics.sh --quiet`) und den Report als
Artefakt oder Issue-Kommentar ablegen.
