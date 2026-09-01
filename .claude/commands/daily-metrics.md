# /daily-metrics – Prozess-Kennzahlen der Factory

Erzeugt einen Health-/Velocity-Report aus deterministischen Quellen (Git, GitHub,
Task-Dateien) und gibt ihn optional als GitHub-Kommentar aus.

> **Mess-Ebene (ADR-006):** Dieser Skill misst **Prozess** – Lead-Time,
> Autonomie-Rate, CI-Quote, Interrupts, Durchsatz. **Token und Kosten gehören
> NICHT hierher** – die liefert die Telemetrie-Ebene (OTEL, `config/otel.env.example`).
> Kein eigenes Token-Accounting nachbauen.

> **Läuft bereits automatisch (ADR-045, #314):** `scripts/metrics.sh` ist ein
> Abschluss-Schritt **jedes** `run-pipeline.sh`-Laufs (EXIT-Trap, fail-open – läuft auch bei
> Abbruch, verändert nie den Exit-Code der Pipeline). Dieser Skill ist der **manuelle** Weg
> dorthin – z. B. für einen Zwischenstand außerhalb eines Pipeline-Laufs – und erreicht über
> denselben `--publish`-Schalter dieselben Veröffentlichungs-Wege (Schritt 3).

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

`metrics.sh --publish` übernimmt das Veröffentlichen selbst (ADR-045) – kein manueller
`gh`-Aufruf mehr nötig:

```bash
FACTORY_METRICS_ISSUE=<issue-nummer> bash scripts/metrics.sh --publish
```

Veröffentlicht wird an `$GITHUB_STEP_SUMMARY` (wenn gesetzt) und als Kommentar an
`FACTORY_METRICS_ISSUE` (wenn gesetzt, gegen einen nicht-numerischen Wert fail-closed
abgesichert). Ohne `--publish` genügt der Datei-Report (heutiges Verhalten unverändert).

## Regeln

- Keine Token-/Kosten-Metriken (kommen aus OTEL – ADR-006)
- Nichts erfinden: nur ausgeben, was `metrics.sh` aus echten Quellen berechnet
- Fehlende API-Daten ehrlich als „übersprungen" ausweisen, nicht schätzen

## Output

- `tasks/metrics-<datum>.md` (gitignored – Snapshot, jederzeit regenerierbar)
- Kurze Interpretation der Auffälligkeiten
- Optional: GitHub-Kommentar

## Hinweis für Stage 3 / Automatisierung

Deterministisch, kein Gesprächsgedächtnis nötig – und seit #314 bereits verdrahtet: der
EXIT-Trap in `run-pipeline.sh` ruft `bash scripts/metrics.sh --quiet --publish` als
Abschluss-Schritt jedes Pipeline-Laufs auf (ADR-045), kein separater Scheduled Workflow nötig.
