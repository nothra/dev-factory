# ADR 006: Mess-Architektur – zwei Ebenen: Prozess (Git/GitLab) und Telemetrie (OTEL/Gateway)

## Status
Accepted

> **Update (2026-07-08, [ADR-012](012-github-platform-migration.md)):** Plattform von
> GitLab auf GitHub migriert. Die Zwei-Ebenen-Entscheidung bleibt unverändert gültig; die
> Prozess-Ebene liest die Kennzahlen jetzt über die GitHub-API (`gh`) statt `glab`.
> Historischer Text unten nennt weiterhin GitLab.

## Datum
2026-06-17

## Kontext

Stufe 2 der Roadmap („Orchestrieren & messen") macht die Factory messbar. Beim Schneiden der
Mess-Funktionalität trafen zwei Anforderungen aufeinander, die leicht zu einem einzigen,
überladenen „Metrics"-Baustein verschmelzen würden:

1. **Prozess-/Outcome-Kennzahlen** (Issue #12): Lead-Time, Autonomie-Rate, CI-Grün-Quote,
   offene Interrupts. Quelle: Git-History + GitLab-API. Lokal berechenbar.
2. **LLM-Nutzungs-Telemetrie** (Issue #17): Token, Kosten, Latenz, Modell-/Skill-Nutzung pro
   Call. Quelle: client-seitige OpenTelemetry-Instrumentierung von Claude Code.

Anstoß für (2) kam von **Rene Lengwinat** (Teams, 2026-06-17): Das Team prüft AI-Gateways zur
Reduktion der Anthropic-Abhängigkeit; Nutzungsmetriken lassen sich dort erfassen, „vollumfänglich
allerdings erst, wenn im Client die OTEL-Integration aktiviert ist – das sollte bei jeder
Factory im Bauchladen enthalten sein."

Ohne klare Grenze würde #12 anfangen, Token/Kosten selbst zu schätzen (aus Logs parsen o. ä.) –
ein fragiler Nachbau dessen, was OTEL bereits liefert.

## Entscheidung

Die Factory misst auf **zwei getrennten Ebenen mit getrennten Quellen**:

| Ebene | Misst | Quelle | Issue |
|-------|-------|--------|-------|
| **Prozess** | Lead-Time, Autonomie-Rate, CI-Quote, Interrupts, Tasks | Git + GitLab-API (`glab`) | #12 |
| **Telemetrie** | Token, Kosten, Latenz, Modell-/Skill-/Agent-Nutzung | Claude Code OTEL → Gateway/Collector | #17 |

**Verbindliche Scope-Grenze:** Die Prozess-Ebene (#12) baut **kein** eigenes Token- oder
Kosten-Accounting nach. Diese Dimension kommt ausschließlich aus der Telemetrie-Ebene.

**Telemetrie ist client-seitig und backend-unabhängig.** Verifiziert gegen
[code.claude.com/docs/en/monitoring-usage](https://code.claude.com/docs/en/monitoring-usage):
Claude Code emittiert die Metriken unabhängig vom Backend (direkter API-Key, Bedrock, Vertex,
Foundry oder AI-Gateway mit Non-Anthropic-Modell). `claude_code.token.usage` bleibt exakt und
ist nach `model`/`skill.name`/`agent.name` aufschlüsselbar. `claude_code.cost.usage` (USD) ist
laut Doku eine Approximation – sobald Non-Anthropic-Pricing greift, gilt: **authoritative
Kosten vom Gateway, Attribution von OTEL.**

**Prozess-Ebene ist local-first.** Lokal berechenbare Kennzahlen laufen immer; die
GitLab-API-Teile (Lead-Time, CI-Quote) degradieren sauber, wenn kein `glab`-Token vorhanden ist
(CI/headless/adoptiertes Projekt ohne Auth).

## Alternativen

### Option B: Ein einziger Metrics-Baustein, der auch Token/Kosten erfasst
Würde Token/Kosten aus Logs oder API-Antworten selbst parsen. **Abgelehnt:** fragiler Nachbau
einer Funktion, die Claude Code nativ und genauer liefert; zudem nicht gateway-portabel.

### Option C: Nur Telemetrie (OTEL), keine separate Prozess-Ebene
**Abgelehnt:** Die Dark-Factory-Leitkennzahlen (Autonomie-Rate, Lead-Time, CI-Quote) sind
Prozess-Metriken, die OTEL nicht liefert – sie entstehen aus Issue/MR/Interrupt-Daten.

## Konsequenzen

**Positiv:**
- Jede Ebene bleibt in ihrer Spur; #12 wird kleiner und robuster.
- Telemetrie überlebt einen Gateway-/Modellwechsel, weil client-seitig – keine Mess-Lücke beim
  Anbieterwechsel.
- Saubere Arbeitsteilung bei Kosten: Gateway = Wahrheit, OTEL = Attribution.

**Negativ / Trade-offs:**
- Zwei Quellen statt einer: ein vollständiges Bild erfordert das Zusammenführen von Prozess-
  und Telemetrie-Daten (z. B. im Gateway-Dashboard). Akzeptiert – die Entkopplung wiegt schwerer.
- Der USD-Kostenwert aus OTEL ist hinter einem Non-Anthropic-Gateway nur eine Schätzung.
  Akzeptiert – für exakte Kosten ist ohnehin die Gateway-/Provider-Abrechnung maßgeblich.

## Betroffene Stellen
- `config/otel.env.example` (#17) – Telemetrie-Ebene, default aus
- README / CLAUDE.md – Dokumentation der Telemetrie-Aktivierung (#17)
- `scripts/metrics.sh` + `/daily-metrics` (#12, Folge-MR) – Prozess-Ebene
- `scripts/raise-interrupt.sh` (#12, Folge-MR) – append-only Interrupt-Log als Quelle der Autonomie-Rate

## Quelle
Telemetrie-Ebene angestoßen durch Rene Lengwinat (Teams, 2026-06-17).
