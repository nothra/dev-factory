# ADR 038: Größenabhängige Modell-Tier-Wahl (dynamisches Tiering)

## Status
Accepted (2026-07-22)

## Kontext

Spec #197 (`docs/specs/spec-197-modell-tiers-gezielter-vergeben.md`) verlangt, die
Modell-Tier-Wahl **vom Aufwand des einzelnen Laufs** abhängig zu machen statt von einer
pauschalen Skill-Zuordnung:

- `review`: `light` unter, `heavy` ab einem Diff-Schwellwert (~150 Zeilen).
- `implement`/`bug-fix`: analog, aber über einen **Proxy aus Spec/Task** (der Code-Diff
  existiert bei der Modellwahl noch nicht).
- `security-review`: bleibt fix `heavy`.

Heutiger Mechanismus (`scripts/run-pipeline.sh`):
- `get_model(skill)` liest ein **statisches** Feld `skills.<skill>.tier` (via `cfg_skill_field`,
  Fallback `default.tier`) und mappt `heavy → CLAUDE_MODEL_HEAVY`, sonst `→ CLAUDE_MODEL_LIGHT`.
- `scripts/checks/config-validation-check.sh` erzwingt **fail-closed** (Regel 4a): jedes
  `skills.*.tier` und `default.tier` muss ein Schlüssel aus `model_tiers` sein (`heavy`/`light`);
  ein leerer/unbekannter Wert bricht den Lauf ab.
- Override-Keys müssen ⊆ Defaults-Blattpfade sein (Regel 2) – neue Knöpfe gehören in
  `factory.defaults.yml`, nicht in den Team-Override.

Die offenen Fragen O1–O4 der Spec sind zu entscheiden, insbesondere **O1**: Wie wird
„größenabhängig" hinterlegt, ohne die `tier ∈ model_tiers`-Invariante (und damit das
fail-closed-Gate) zu brechen?

Diese Entscheidung ist **reversibel** (Config-Feld + Bash-Funktion, kein Datenmodell), aber
langfristig relevant (verändert das Config-Schema und den zentralen Kosten-Hebel) → ADR.

## Entscheidung

**Additives, optionales Feld `tier_by_size` pro Skill; das bestehende statische `tier` bleibt als
Fail-Safe-Fallback erhalten.** Die Größe→Tier-Entscheidung wird in eine sourcebare Lib
extrahiert und getestet.

### 1. Config-Schema (in `factory.defaults.yml`)

```yaml
skills:
  review:
    tier: heavy                 # Fail-safe: gilt, wenn die Größe nicht bestimmbar ist
    tier_by_size:
      signal: diff              # Diff-Zeilen gegen aktuelles origin/main
      threshold: 150            # Netto-Zeilen: < → light, >= → heavy
    max_turns: 14
  implement:
    tier: heavy
    tier_by_size:
      signal: proxy             # Anzahl Akzeptanzkriterien aus der Spec
      threshold: 6              # AK-Zahl: < → light, >= → heavy (Richtwert, kalibrierbar)
    max_turns: 20
  bug-fix:
    tier: heavy
    tier_by_size: { signal: proxy, threshold: 6 }
    max_turns: 20
  security-review:
    tier: heavy                 # @reason: bewusst fix heavy, KEIN tier_by_size (Miss teurer als Token)
    max_turns: 14
  # test/refactor/codify/pr-shepherd/requirements/architecture/release-notes: unverändert (light, kein tier_by_size)
```

- **`tier` bleibt auf jedem Skill ein gültiger `model_tiers`-Schlüssel** → `config-validation`
  Regel 4a bleibt unverändert grün (**AK9**). Kein Sentinel, kein Special-Case im Kern-Constraint.
- Ist `tier_by_size` **nicht** gesetzt (alle übrigen Skills), verhält sich `get_model` **exakt wie
  heute** (statisches `tier`). Rückwärtskompatibel.
- Schwellwerte leben **pro Skill in den Defaults** (unterschiedliche Einheiten: Diff-Zeilen vs.
  AK-Zahl) und sind per Team-Override justierbar (ADR-009-Schichtung) – **O3 entschieden**.

### 2. Auswahl-Logik (`get_model`, neue Lib `scripts/lib/tier-select.sh`)

Reihenfolge in `get_model(skill)`:
1. `CLAUDE_MODEL` gesetzt → dieses Modell (globaler Override sticht weiterhin, **AK10**). Unverändert.
2. `tier_by_size.signal` gesetzt → `size = measure_size(signal)`:
   - `size` bestimmbar **und** `size >= threshold` → `heavy`
   - `size` bestimmbar **und** `size <  threshold` → `light`
   - `size` **nicht** bestimmbar (leer) → **statisches `tier`** (= `heavy`) → Fail-Safe (**F1/F2**)
3. Kein `tier_by_size` → statisches `tier` (Bestandsverhalten).
4. `tier → Modell`-Mapping wie heute (`heavy`→HEAVY, sonst LIGHT).

`measure_size(signal, …)` und die reine Entscheidung `select_tier(size, threshold, fallback_tier)`
werden nach `scripts/lib/tier-select.sh` extrahiert (Muster: `scripts/lib/report-verdict.sh`),
von `run-pipeline.sh` gesourct und in `scripts/checks/tests/run-tests.sh` direkt getestet
(**Testbarkeit ohne claude-Aufruf**).

### 3. Größensignale (O2/O4 entschieden)

- **`diff`:** `git fetch --quiet origin main` (best effort), dann Summe `added + deleted` über
  `git diff --numstat origin/main...HEAD` (Drei-Punkt = Merge-Base, misst nur die Branch-eigenen
  Änderungen → nutzt das **aktuelle `origin/main`**, nicht das evtl. zurückliegende lokale `main`,
  **AK3**). Binärdateien (numstat `-`) werden übersprungen.
  - **O4:** Keine Pfad-Ausschlüsse in v1 (auch Lockfiles zählen). Ein Über-Zählen verschiebt die
    Wahl Richtung `heavy` – das ist die **sichere** Fehlerrichtung, konsistent mit dem Fail-Safe.
    Ein Ausschluss-Knopf ist nachrüstbar, falls es sich als zu grob erweist (YAGNI).
  - Schlägt `git`/`fetch` fehl → `measure_size` gibt leer zurück → Fail-Safe `heavy` (**F1**).
- **`proxy`:** Anzahl der Akzeptanzkriterien-Checkboxen (`- [ ]`/`- [x]`) im Abschnitt
  `## Akzeptanzkriterien` der Spec-Datei `docs/specs/spec-<id>-*.md` (via `awk` zwischen der
  Überschrift und der nächsten `## `-Zeile). Fehlt die Spec/der Abschnitt → leer → Fail-Safe
  `heavy` (**F2**). Der Schwellwert `6` ist ein Richtwert und ausdrücklich kalibrierbar
  (`@tradeoff`); ADR-006-Metriken können ihn später datenbasiert nachschärfen.

### 4. Config-Validierung (neue Regel 4c, `config-validation-check.sh`)

Wo `tier_by_size` in der **effektiven** Config existiert:
- `signal ∈ { diff, proxy }`, sonst `fail`.
- `threshold` ist positiver Integer (`case ''|*[!0-9]*`), sonst `fail` (**F3**).

Additiv – Regel 4a (statisches `tier`) bleibt unverändert. Neue Blattpfade
(`skills.<skill>.tier_by_size.signal|threshold`) existieren in den Defaults, also greift Regel 2
(unbekannte Override-Keys) weiterhin: ein Team darf bestehende `tier_by_size`-Werte überschreiben,
aber `tier_by_size` nicht per Override an einem **neuen** Skill einführen (correct-by-construction).

## Alternativen

### Option A: Additives `tier_by_size`-Feld + `tier` als Fail-Safe (gewählt)
Vorteile: `tier ∈ model_tiers` bleibt intakt → Kern-Gate unverändert grün; Fail-Safe-Fallback
ergibt sich **geschenkt** aus dem vorhandenen `tier`; nicht-dynamische Skills verhalten sich
byte-genau wie heute; Schwellwert + Signal an EINEM Ort am Knopf begründet (ADR-011).
Nachteile: leichte semantische Doppelung (`tier` *und* `tier_by_size` an denselben Skills) –
per Kommentar entschärft.

### Option B: Sentinel-Tier `auto`
`tier: auto` + separate Threshold-Felder; `get_model` und der Validator behandeln `auto` speziell.
Vorteile: ein Feld weniger.
Nachteile: durchbricht die zentrale `tier ∈ model_tiers`-Invariante (der Validator muss `auto`
gesondert erlauben); `auto` trägt Signal/Threshold **nicht** selbst → braucht trotzdem Zusatzfelder;
kein natürlicher Fail-Safe-Wert mehr (was ist das Modell, wenn die Größe unbestimmbar ist?).
Schwächt das fail-closed-Gate – abgelehnt.

### Option C: Logik hart in Bash, ohne Config
Schwellwerte/Signale direkt in `get_model` verdrahten.
Vorteile: kein Schema-Change.
Nachteile: widerspricht ADR-009 (SSOT = `factory.defaults.yml`, per Team justierbar) und ADR-011
(Begründung am Knopf); Re-Introduktion von Hardcode-Drift, die ADR-009 gerade beseitigt hat –
abgelehnt.

### Option D: dritter/mittlerer Tier
Explizit in der Spec ausgeschlossen (YAGNI) – hier nur zur Vollständigkeit; löst das
Größenproblem ohnehin nicht (die Frage bliebe, *wann* welcher Tier).

## Begründung

Option A ist die kleinste Erweiterung, die alle Akzeptanzkriterien erfüllt, **ohne** die
fail-closed-Config-Invariante anzutasten. Der Fail-Safe auf `heavy` fällt nicht als
Sonderbehandlung an, sondern ist die schon vorhandene statische Zuordnung – das ist robust und
lehrbar. Extraktion der Entscheidung in eine sourcebare Lib macht die Größen-Logik testbar, ohne
einen echten `claude`-Lauf – passend zum bestehenden Test-Harness. Die sichere Fehlerrichtung
(Unsicherheit → `heavy`) deckt sich mit `token-efficiency.md` §6: an teuren Stellen lieber das
starke Modell als ein übersehener Fehler.

## Konsequenzen

- **Schema-Erweiterung** (`schemaVersion` bleibt `1`: rein additive, optionale Felder brechen keine
  bestehenden Overrides; ein Bump wäre nur bei inkompatibler Änderung nötig).
- Betroffen: `factory.defaults.yml` (neue Felder + `@reason`/`@tradeoff`), `factory.config.yml`
  (provisorischen `implement`-Override auflösen, **AK12**), `scripts/lib/tier-select.sh` (neu),
  `scripts/run-pipeline.sh` (`get_model` sourct/nutzt die Lib), `config-validation-check.sh`
  (Regel 4c), `scripts/checks/tests/run-tests.sh` (Positiv-/Negativ-Fälle je Signal),
  `docs/factory/guidelines/token-efficiency.md` §6 (Verweis auf reale SSOT, **AK11**).
- **Kalibrierung nötig:** Der Proxy (AK-Zahl) ist eine Heuristik; der Diff-Schwellwert ~150 und die
  Proxy-Schwelle 6 sind Richtwerte. Beide sind Knöpfe und dürfen mit Betriebserfahrung wandern.
- Der Proxy misst **Spec-Detailtiefe**, nicht garantiert Implementierungsaufwand – ein knapp
  spezifizierter, aber kniffliger Task kann `light` gewählt bekommen. Fail-safe ist hier nur der
  Nicht-Bestimmbarkeits-Fall; Fehlkalibrierung fängt weiterhin die Review↔Implement-Schleife
  (Circuit Breaker) ab.
- `model_tiers`-IDs bleiben unverändert (Issue-Vorgabe); die `light`-ID-Pflege
  (`claude-sonnet-5` im Override) ist nicht Teil dieser ADR.

## Offene Fragen aus der Spec – Status

- **O1 (Repräsentation):** entschieden → additives `tier_by_size` + `tier` als Fail-Safe.
- **O2 (Proxy-Metrik/Schwelle):** entschieden → AK-Zahl der Spec, Default-Schwelle 6 (kalibrierbar).
- **O3 (Ort der Schwellwerte):** entschieden → pro Skill in `factory.defaults.yml`, override-fähig.
- **O4 (Diff-Randfälle):** entschieden → numstat added+deleted, Binär übersprungen, keine
  Pfad-Ausschlüsse in v1 (Über-Zählen → `heavy` = sichere Richtung).
