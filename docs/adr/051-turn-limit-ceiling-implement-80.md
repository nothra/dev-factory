# ADR 051: Turn-Limit-Ceiling für `/implement` von 50 auf 80 anheben (erweitert ADR-009 §6 / ADR-010)

## Status

Accepted

> Erweitert **ADR-009** §6 („Jeder Kosten-Knopf bekommt eine harte Obergrenze") und
> **ADR-010** (Heimat der konkreten `MAX_TURNS_CEILING`-Konstante). Ändert keine Entscheidung
> von ADR-009/ADR-010 – Mechanismus (yq-natives Gate, Ceiling als Skript-Konstante, nicht
> Team-überschreibbar) bleibt unverändert. Diese ADR entscheidet nur den **Zahlenwert**.

## Kontext

`MAX_TURNS_CEILING` in `scripts/checks/config-validation-check.sh` ist laut ADR-009 §6 /
ADR-010 bewusst **keine** per Team-Config überschreibbare Zahl, sondern eine Gate-Policy-
Konstante – genau damit kein Team-Override das eigene Kosten-Maximum aushebeln kann. Ein
früherer Versuch, `skills.implement.max_turns` direkt auf 80 zu setzen, wurde vom Gate deshalb
korrekt fail-closed abgelehnt (`factory.config.yml:46-48`).

**Das ist kein Einzelfall – die Ceiling für `/implement` wurde bereits zweimal aus demselben
Grund angehoben, und reißt jetzt am dritten Mal wieder:**

| Anlass | Änderung | Symptom |
|---|---|---|
| Task #49 (2026-07-14) | `implement` 20 → 40 | 2× „Reached max turns" ohne Ergebnis bei Default 20 |
| Task #53 (`c300d14`, Review-Notiz `tasks/review-53.md:58`) | `implement` 40 → 50 (+ Tier auf `heavy`) | Sonnet 5 riss 3× ab bei größerem Scope (Auslagenerstattung) |
| **Issue #324** (aktuell) | Ceiling selbst reicht nicht mehr | `/implement` riss **erneut 3×** ab – diesmal *am bereits maximal erlaubten Wert* (50), obwohl im Arbeitsbaum ein funktional fast fertiger, committierbarer Diff über 6 Module/15 AC lag (`docs/factory/lessons/factory-workflow.md` „Turn-Limit-Exhaustion", Nachtrag #324; `tasks/codify-324.md`) |

Jede Runde hatte dasselbe Muster: `/implement` bricht bei größerem Scope mehrfach mit
„Reached max turns" ab, ohne committierbares Ergebnis, bis der Turn-Deckel angehoben wird.
Anders als bei #49/#53 hilft diesmal keine reine Config-Änderung – `/implement` steht bereits
auf der Policy-Obergrenze. Ohne eine dokumentierte Anhebung der Ceiling selbst bleibt der
einzige Ausweg der manuelle Nachtrag durch einen Menschen (wie in #324 geschehen), was den
Automatisierungsgrad der Pipeline unterläuft.

Ein verwandter, aber **separater** Defekt (Orchestrator `run_skill()` prüft zwischen Retries
nicht auf `git status`, retryt blind – Issue #275, dokumentiert im selben Lesson-Eintrag)
verschärft die Kosten dieses Symptoms (drei komplette Neuversuche statt Fortsetzung), ist aber
nicht Gegenstand dieser Entscheidung: Selbst ein perfekter Retry-Mechanismus würde einem
15-AC/6-Modul-Task nicht helfen, wenn schon der **erste** Versuch beim aktuellen Limit (50)
nicht durchläuft.

## Entscheidung

`MAX_TURNS_CEILING` wird von **50 auf 80** angehoben. `skills.implement.max_turns` in
`factory.config.yml` wird auf **80** gesetzt (bisher: 50, dem alten Maximum). Kein anderer
Skill-Wert ändert sich; die Ceiling bleibt weiterhin die einzige, nicht via Team-Config
überschreibbare Obergrenze (ADR-010 unverändert).

`ADR-009 §6` selbst beschreibt nur den **Mechanismus** („tunable mit Maximum im Schema"),
keinen konkreten Zahlenwert – dort entsteht keine Drift, keine Änderung nötig. `ADR-010`
benennt die konkrete Konstante (`MAX_TURNS_CEILING`) als „Heimat der Obergrenze" und bekommt
eine kurze Erweiterungs-Notiz auf diese ADR (Drift-Regel, `PROJECT-CONTEXT.md`).

## Alternativen

### Option A: Globale Ceiling auf 80 anheben (gewählt)

**Vorteile:** Minimale, reversible Änderung an genau einer Stelle (Skript-Konstante) plus dem
betroffenen Team-Override; folgt demselben, bereits zweimal bewährten Muster (#49, #53); keine
neue Mechanik, keine neue Abhängigkeit; sofort wirksam für den nächsten großen `/implement`-Lauf.

**Nachteile:** Erhöht implizit den möglichen Kosten-Rahmen für **alle** Skills (die Ceiling ist
global, nicht pro Skill) – auch wenn aktuell nur `implement` den neuen Spielraum nutzt.

### Option B: Pro-Skill-Ceiling statt einer globalen Konstante

Statt einer einzigen `MAX_TURNS_CEILING` je Skill ein eigenes Maximum (z. B.
`MAX_TURNS_CEILING_IMPLEMENT=80`, andere bleiben bei 50).

**Vorteile:** Verhindert den Nebeneffekt aus Option A (andere Skills könnten theoretisch auch
bis 80 konfiguriert werden, ohne dass dafür ein Incident vorliegt).

**Nachteile:** Widerspricht der in ADR-010 „Alternativen"/Option A explizit gewählten
Einfachheit („für den heutigen flachen Knopf-Satz kein Thema") – heute hat **kein** anderer
Skill je sein Maximum gerissen; eine Pro-Skill-Ceiling löst ein Problem, das nicht existiert
(YAGNI). Größerer Diff (neue Konstanten-Struktur statt einer Zeile), mehr Wartungsfläche.
**Abgelehnt für v1** – bleibt additiv nachrüstbar, falls je ein anderer Skill sein Maximum
reißt.

### Option C: Nur den Orchestrator-Retry-Defekt (#275) beheben, Ceiling unverändert lassen

**Vorteile:** Behebt die Ursache, warum aus einem Abbruch drei komplette Neuversuche werden
(kein `git status`-Check zwischen Retries) – reduziert verschwendete Turns strukturell.

**Nachteile:** Löst das eigentliche Symptom aus #324 nicht: Der **erste** Versuch selbst
erreichte bereits das Limit (50), bevor überhaupt ein Retry nötig war. Ein Task mit 15 AC über
6 Module braucht mehr als 50 Turns für eine vollständige TDD-Implementierung – daran ändert ein
besseres Retry-Verhalten nichts. **Abgelehnt als Ersatz** (Issue #275 bleibt trotzdem sinnvoll,
aber komplementär, nicht alternativ – bewusst außerhalb des Scopes dieser Task, siehe
[spec-348](../specs/spec-348-max-turns-ceiling-implement.md) „Nicht inbegriffen").

## Begründung

Option A ist die einfachste Änderung, die das dokumentierte, wiederkehrende Problem behebt
(YAGNI, `architecture-principles.md` „Reversible Entscheidungen: schnell treffen, günstig zu
ändern"). Die Eskalationshistorie (#49 → #53 → #324) zeigt, dass eine Anhebung des Turn-Budgets
für `/implement` bei größerem Scope bereits zweimal die richtige, wirksame Maßnahme war – die
dritte Wiederholung desselben Symptoms ist kein Zufall, sondern ein Hinweis, dass 50 für Tasks
dieser Größenordnung strukturell zu knapp ist. Die Entscheidung ist **reversibel**: eine
Skript-Konstante ist in einer Zeile wieder senkbar, falls die OTEL-Telemetrie (ADR-049) zeigt,
dass der zusätzliche Spielraum die Kosten unverhältnismäßig treibt, ohne die Abbruchrate zu
senken.

Option B wäre die „vorsichtigere" Wahl, löst aber kein reales Problem (kein anderer Skill ist je
an sein Maximum gestoßen) und widerspricht der in ADR-010 bereits getroffenen
Einfachheits-Entscheidung. Option C behebt einen echten, aber **anderen** Defekt und wird durch
diese ADR nicht ersetzt, sondern bleibt als eigenständige Härtung (#275) bestehen.

## Konsequenzen

**Positiv:**
- `/implement` hat für groß skopierte Tasks (viele AC, mehrere Module) wieder realen Spielraum,
  ohne dass ein Mensch den Zwischenstand manuell fertigstellen muss.
- Die Ceiling bleibt eine **harte** Obergrenze (80, nicht „unbegrenzt") – ADR-009 §6 bleibt
  erfüllt.
- Kein Mechanismus-Wechsel: bestehende Gate-Tests (Tippfehler-Key, `max_turns: 0`,
  nicht-Integer, `schemaVersion`-Mismatch) bleiben unverändert gültig.
- Reversibel: eine künftige Senkung berührt dieselbe einzelne Konstante.

**Negativ / Trade-offs:**
- Erhöhter Kosten-Rahmen pro `/implement`-Lauf (bis zu 80 statt 50 Turns) – Sichtbarkeit über
  die bestehende Telemetrie (ADR-049), kein neues Messverfahren nötig.
- Andere Skills (`pr-shepherd`, `codify`, `test`) könnten künftig per Team-Override ebenfalls
  bis 80 konfiguriert werden, obwohl dafür kein Incident vorliegt – bewusst akzeptierter
  Nebeneffekt der globalen Ceiling (bestehendes Trade-off-Muster, s. ADR-010 „Konsequenzen":
  „Folge der abgeleiteten Key-Oberfläche …"), keine neue Regel nötig.
- Reißt `/implement` das Limit erneut (z. B. bei noch größerem Scope), ist die richtige nächste
  Maßnahme **nicht** eine dritte unbedingte Anhebung, sondern vorrangig: (a) den
  Orchestrator-Retry-Defekt (#275) beheben, und/oder (b) den Task vor `/implement` in kleinere
  Akzeptanzkriterien-Schnitte teilen. Eine Ceiling, die bei jedem Anlass einfach mitwächst,
  verliert ihren Zweck als harte Obergrenze (ADR-009 §6) – diese Empfehlung gehört in den
  nächsten `/codify`-Lauf, falls das Muster ein viertes Mal auftritt.

## Implementierungs-Hinweise (für den Coding-Agenten)

- **`scripts/checks/config-validation-check.sh`:**
  - Zeile 34: `MAX_TURNS_CEILING=50` → `MAX_TURNS_CEILING=80`.
  - Kopf-Kommentar (Zeilen ~20-31, Regel 4 / „Heimat"-Hinweis): Verweis auf ADR-009 §6 / ADR-010
    um „, ADR-051 (Wert 80)" ergänzen.
- **`factory.config.yml`:**
  - Zeile 50: `implement: { max_turns: 50 }` → `implement: { max_turns: 80 }`.
  - `@reason`-Kommentar (Zeilen ~38-48): die überholte Notiz „ein Versuch mit 80 wurde vom
    config-validation-check hart abgelehnt" ersetzen durch einen Verweis auf ADR-051 und die
    Eskalationshistorie (#49/#53/#324) – nicht nur den Zahlenwert ändern, sonst erklärt der
    Kommentar nicht mehr, warum 80 jetzt sicher ist.
- **`docs/adr/010-config-validation-gate.md`:** kurze Blockquote-Notiz („Erweitert durch
  ADR-051") direkt am Absatz „Heimat der Obergrenze … Es gibt in v1 genau eine Obergrenze"
  ergänzen (Muster: ADR-036 D1 ↔ ADR-046, siehe dortige Blockquote). **Kein** Rewrite des
  Bestandstexts, keine Status-Änderung.
- **`docs/adr/009-*.md` §6:** unverändert lassen – beschreibt nur den Mechanismus, keinen
  Zahlenwert, daher keine Drift.
- **`scripts/checks/tests/run-tests.sh`** (Abschnitt „Config-Validierungs-Gate", ab Zeile ~1500):
  - Neuer Positiv-Test: `skills:\n  implement: { max_turns: 80 }` → Exit 0
    (Analog zum bestehenden `ok.yml`-Fixture, Zeile 1508).
  - Neuer Grenzfall-Negativ-Test: `skills:\n  implement: { max_turns: 81 }` → Exit ≠ 0
    (Analog zum bestehenden `ceil.yml`-Fixture, Zeile 1528 – **nicht** dieses Fixture
    überschreiben, da `9999` bereits den „weit über Ceiling"-Fall abdeckt; 81 ist der
    eigentliche Grenzfall-Beleg für den neuen Wert).
  - Bestehende Fixtures (`typo.yml`, `zero.yml`, `nonint.yml`, `tier.yml`, `broken.yml`)
    unverändert lassen – sie sind ceiling-wert-unabhängig.
- **`docs/factory/lessons/factory-workflow.md`** (optional, empfohlen – kein hartes AC):
  kurzer Nachtrag beim #324-Eintrag „Ceiling seit #348/ADR-051 auf 80 angehoben".
