# ADR 004: Stage-3-Interrupt – deterministischer Stopp bei menschlicher Entscheidung

## Status
Accepted

## Datum
2026-06-12

## Kontext

Die Stage-3-Pipeline (`run-pipeline.sh`) ruft Agenten nicht-interaktiv über
`claude --print` auf. Es gibt zur Laufzeit keinen Menschen.

Der ADR-Trigger-Check (Spec-002, ADR-002) weist den Coding-Agenten an, bei einer
der vier Trigger-Kategorien zu **stoppen und den Menschen zu fragen**. Dieses
Verhalten ist auf einen interaktiven Menschen ausgelegt. In Stage 3 ist offen,
was passiert, wenn der Trigger feuert: hängen, still weiterlaufen oder stoppen –
nichts davon ist spezifiziert (aufgedeckt im Review zu !9, Issue #4).

**Stilles Weiterlaufen ist das schlechteste Szenario:** die Pipeline meldet grün,
obwohl eine architektonische Entscheidung aussteht – zwei Wahrheiten im System.
Ein ADR-Trigger ist kein Warning, sondern ein Gate. Wenn Stage 2 stoppt, muss
Stage 3 dasselbe tun.

Der Fall ist nicht ADR-spezifisch: **jeder** Schritt kann auf eine nicht
automatisierbare Entscheidung stoßen. Es braucht ein Querschnitts-Konzept, keinen
Einzel-Fix pro Feature.

## Entscheidung

Ein dateibasierter **Interrupt-Mechanismus**, der dem Factory-Kernprinzip folgt
(deterministische Skripte orchestrieren, Agenten signalisieren – Agenten rufen
keine Pipelines):

1. **Signal (Agent → Pipeline):** Ein Agent, der eine nicht automatisierbare
   Entscheidung erkennt, ruft `scripts/raise-interrupt.sh <task-id> <typ> <nachricht>`
   auf. Das schreibt ein Sentinel `tasks/INTERRUPT-<task-id>.md`.

2. **Erkennung (Pipeline):** `run-pipeline.sh` führt nach **jedem** Skill-Schritt
   `scripts/checks/interrupt-check.sh <task-id>` aus. Existiert das Sentinel:
   - actionable Meldung (`[INTERRUPT] <typ>: <nachricht> → <aktion>`),
   - Blocker-Eintrag in der Task-Datei (gleiche Konvention wie `/implement`),
   - `exit 1` – harter Stopp wie ein gefallenes Quality Gate.

3. **Stage-Signal:** `run-pipeline.sh` setzt `FACTORY_STAGE=3` für jeden
   Agenten-Aufruf. Skill (`/implement` Schritt 0) und Persona (`coding-agent.md`)
   verzweigen darauf: in Stage 3 wird nicht gefragt, sondern der Interrupt ausgelöst.

4. **Stale-Bereinigung:** Der Preflight entfernt ein Sentinel aus einem früheren
   Lauf, damit ein frischer Lauf nicht sofort wieder stoppt. Das Sentinel bleibt
   sonst zur Inspektion liegen.

ADR-Trigger ist der erste Konsument; der Mechanismus ist generisch (beliebiger
`typ`/`nachricht`) und für künftige Schritte wiederverwendbar.

## Alternativen

### Option A: stdout-Marker parsen
Der Agent gibt einen Marker (`[[INTERRUPT:...]]`) auf stdout aus, `run-pipeline.sh`
greppt den gestreamten Output.
**Nachteile:** fragil (Marker kann zufällig in Erklärtext auftauchen), erfordert
Output-Capture statt Streaming, kein strukturierter Inhalt. Abgelehnt – Datei-
Kommunikation ist das Factory-Muster und eindeutig.

### Option B: Exit-Code des Skill-Aufrufs
Der Agent beendet den Lauf mit einem speziellen Exit-Code.
**Nachteile:** `claude --print` reicht keinen frei wählbaren fachlichen Exit-Code
des Agenten durch; nicht zuverlässig steuerbar. Abgelehnt.

### Option C: Nichts tun (Status quo)
**Nachteile:** genau das Design-Gap aus #4 – stiller Durchlauf oder Hängen.
Abgelehnt.

## Begründung

Das Sentinel ist deterministisch prüfbar, strukturiert und folgt dem etablierten
Datei-Kommunikationsmuster der Factory. Die **Garantie liegt im Skript**: wenn ein
Sentinel existiert, stoppt die Pipeline – unabhängig vom Modellverhalten. Ob der
Agent den Interrupt auslöst, ist der nicht-deterministische Teil – exakt analog zur
ADR-Trigger-Erkennung selbst (ADR-002). Die Trennung „Skript erkennt & stoppt
deterministisch / Agent entscheidet & signalisiert" ist konsistent mit der
bestehenden Quality-Gate- und Circuit-Breaker-Logik.

## Konsequenzen

**Positiv:**
- Kein stiller Durchlauf mehr: ausstehende Entscheidungen stoppen die Pipeline hart.
- Generisches Querschnitts-Konzept, nicht ADR-spezifisch.
- Eigenständig testbar (`raise-interrupt.sh`, `interrupt-check.sh`), konsistent mit
  den übrigen Checks.
- Stage-2-Verhalten (interaktiv fragen) bleibt unverändert.

**Negativ / Trade-offs:**
- Ob der Agent in Stage 3 tatsächlich `raise-interrupt.sh` aufruft, bleibt
  Model-Best-Effort (wie die Trigger-Erkennung). Mitigation: Anker in Skill **und**
  Persona, plus `FACTORY_STAGE=3` als deterministisches Umgebungssignal.
- Zusätzliche Konvention (Sentinel-Format), die Skill, Persona und die beiden
  Skripte konsistent halten müssen.
