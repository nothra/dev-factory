# ADR 011: Annotations-Konvention für Config-Begründungen (verfeinert ADR-009)

## Status
Accepted (2026-06-25)

> Verfeinert **ADR-009** (Geführte Factory-Konfiguration, Accepted) und entscheidet die
> in **Spec #35 „Offene Fragen"** an `/architecture` geroutete Frage: Reicht der heutige
> freie Kommentarstil in `factory.defaults.yml` als maschinell extrahierbare Begründungs-
> Quelle, oder braucht es eine strukturierte Konvention? Sie ändert keine Entscheidung von
> ADR-009, sondern füllt eine Umsetzungs-Vorbedingung von Task #35 (Kriterium C).
> Aufgeworfen im Review zu MR !35 (CM/Claude).

## Date
2026-06-25

## Kontext

ADR-009 #2 begründet YAML-statt-JSON damit, dass jeder Knopf seine **Begründung am Knopf**
trägt — als Kommentar, lesbar für Mensch *und* die Ph.3-Wizards. Spec #35 baut darauf die
**Single-Source-Begründung** (Kriterium A/B/C): `/setup-project`, `/configure-factory`,
`factory.config.yml.example` und Inline-Kommentare sollen Begründung + Trade-off **aus einer
Quelle ziehen** statt sie zu kopieren (W-02/W-03-Drift-Lektion).

Der heutige Stil in `factory.defaults.yml` mischt drei Sorten Kommentar:

```yaml
model_tiers:
  heavy: claude-opus-4-8      # CLAUDE_MODEL_HEAVY        ← Env-Var-Hinweis
  light: claude-sonnet-4-6    # CLAUDE_MODEL_LIGHT
skills:
  implement: { tier: heavy, max_turns: 20 }  # TDD-Zyklen, schreibt Code   ← freie Begründung
```

Problem (CM-Review !35): Dieser Freitext ist **nicht verlässlich einem Knopf und einer
Begründungs-*Art* zuzuordnen**. Ein Extraktor kann nicht unterscheiden, ob `# CLAUDE_MODEL_HEAVY`
eine Begründung, ein Trade-off oder ein Env-Var-Hinweis ist; ein Knopf mit *Begründung und
Trade-off* (Kriterium A verlangt beides) hat heute kein Feld für den Trade-off. Ohne stabile
Konvention kann der Wizard die Single Source nicht maschinell ziehen — Kriterium C wäre nur
durch Hand-Pflege erfüllbar (genau die Drift, die wir ausschließen wollen).

Randbedingungen aus dem bereits gemergten Stand (ADR-010, #36):
- Das Validierungs-Gate arbeitet **rein auf dem Datenmodell** (Blatt-Pfade, `tier`/`max_turns`).
  YAML-Kommentare sind für das Gate unsichtbar — eine kommentar-basierte Konvention ist
  **gate- und schema-neutral** (kein `schemaVersion`-Bump, keine Gate-Änderung).
- `yq` (v4, Prerequisite seit Ph.1b) kann Kommentare lesen. **Verifiziert gegen v4.53.3:**
  `yq '.<pfad> | line_comment'` liefert den Trailing-Text zuverlässig (Block-Skalar + Flow-Map);
  `head_comment`/`foot_comment` sind dort **unzuverlässig** (leer) — daher grep als Primär-Pfad.
- Kriterium C verlangt einen **Anti-Drift-Test mit portabler POSIX-Regex** — die Konvention
  muss also auch greppbar sein, nicht nur yq-lesbar.

## Entscheidung

Eine **strukturierte Kommentar-Konvention** mit festem Tag-Vokabular. Begründungen bleiben
**Kommentare** (kein Daten-Feld) — das hält das Datenmodell sauber, das Gate/Schema unberührt
und bleibt der ADR-009-#2-Linie „Begründung am Knopf" treu.

### Tag-Grammatik

Zwei Tags, je eine Kommentarzeile:

- **`# @reason: <text>`** — *warum* es diesen Knopf / diesen Default gibt. **Pflicht** für
  jeden Knopf, den ein Wizard anbietet.
- **`# @tradeoff: <text>`** — was man beim Ändern aufgibt (Kosten/Qualität). **Pflicht**, wo
  der Knopf ein echter Hebel ist (Modell-Tier, `max_turns`); entfällt, wo es keinen Trade-off
  gibt.

Andere Kommentare (Env-Var-Hinweise wie `# CLAUDE_MODEL_HEAVY`, Abschnitts-Header) bleiben
unangetastet — sie tragen kein `@`-Tag und sind damit klar von der extrahierbaren Quelle
getrennt.

### Position (deterministische Zuordnung)

- **Wert-Ebene** (warum *dieser* Knopf den Default-Wert hat): als **Trailing-`line_comment`** auf
  der Knopf-Zeile, z. B. `tier: heavy  # @reason: …`. Extraktion: `yq '.<pfad> | line_comment'` —
  **gegen yq v4.53.3 verifiziert** (Block-Skalar *und* Inline-Flow-Map).
- **Dimensions-Ebene** (was ein `tier`/`max_turns`/`model_tiers` *ist* + dessen genereller
  Trade-off, ggf. mehrzeilig — das, was der Wizard beim Anbieten der Knopf-*Art* zeigt,
  Kriterium A): als **eigenständige `# @reason:`/`# @tradeoff:`-Kommentarzeilen** direkt über dem
  Mapping-Schlüssel (line-start). Mehrzeilige Bodies über zusammenhängende `#`-Folgezeilen.

> **Empirisch, gegen yq v4.53.3 verifiziert (CM-Nitpick):** `line_comment` (Trailing) ist
> zuverlässig — `head_comment`/`foot_comment` liefern in dieser Version **leer**, ihre Zuordnung
> ist nicht verlässlich. Darum ist der **verbindliche Extraktions-Pfad grep-basiert** (s. u.) und
> verlässt sich **nicht** auf Head-/Foot-Comment-Operatoren; `line_comment` ist eine bestätigte
> Konvenienz für die Wert-Ebene. Wandert die CI auf eine andere yq-Version, ist dieser Befund
> erneut zu prüfen — die grep-Form ist davon unabhängig stabil.

### Extraktions-Vertrag

- **Verbindlich (Wizard *und* Anti-Drift-Test): grep-basiert.** Ein **Textkörper** = Tag-Doppelpunkt
  **plus nicht-leerer Inhalt**, an **beliebiger** Position der Zeile (eigenständig *oder* trailing):
  `#[[:space:]]*@(reason|tradeoff):[[:space:]]*[^[:space:]]` (POSIX, BSD/GNU/ugrep-verifiziert;
  kein `\s`/`grep -P`). **Bewusst ohne `^`-Anker** — sonst entginge ein Trailing-Kommentar
  (`tier: heavy  # @reason: …`), bei dem das `#` nicht am Zeilenanfang steht. Das `[^[:space:]]`
  am Ende ist Absicht: nur eine Tag-Zeile **mit** Inhalt zählt als Textkörper; ein bloßer Verweis
  (Tag-Name ohne Doppelpunkt-Body, s. u.) matcht nicht.
- **Konvenienz (Wert-Ebene):** `yq '.<pfad> | line_comment'` liefert den Trailing-Text direkt
  (verifiziert). Kein Verlass auf `head_comment`/`foot_comment`.

### Single-Source-Regel (Anti-Drift)

Der Begründungs-**Text** (Tag-Doppelpunkt + Inhalt) lebt ausschließlich in `factory.defaults.yml`.
`/setup-project`, `/configure-factory`, `factory.config.yml.example` und etwaige Inline-Kommentare
**verweisen**, statt den Text zu wiederholen.

Die **Verweis-Form ist bewusst kollisionsfrei** zum Textkörper: sie nennt Pfad + Tag-Namen
**ohne** den `@tag:`-Doppelpunkt-Body, z. B. `# Begründung: siehe factory.defaults.yml →
skills.implement (Tag @reason)`. Damit hängt die Unterscheidung **nicht** allein am An-/Abwesenheit
eines Doppelpunkts irgendwo in der Zeile, sondern am Muster „`@reason:` + Inhalt" (Textkörper) vs.
„`@reason` als Wort" (Verweis) — siehe Worked Example.

Der Anti-Drift-Test (Kriterium C) prüft fail-closed: außer in `factory.defaults.yml` matcht **keine**
getrackte Datei die Textkörper-Regex (oben). Verweise matchen sie nicht und sind erlaubt.

### Worked Example (Vorher → Nachher)

In `factory.defaults.yml` (die **einzige** Heimat der Textkörper):

```yaml
# Dimensions-Ebene: eigenständige Tag-Zeilen über dem Schlüssel (mehrzeilig erlaubt).
# @reason: Trennt schweres Reasoning (Implementieren/Reviewen/Security) vom Rest,
#   damit teure Modelle nur dort laufen, wo sie sich lohnen.
# @tradeoff: heavy senkt Fehlerrate, kostet aber mehr pro Turn; light spart, kann
#   bei komplexem Reasoning aber nachfassen müssen.
model_tiers:
  heavy: claude-opus-4-8      # CLAUDE_MODEL_HEAVY     (Env-Var-Hinweis, kein @-Tag)
  light: claude-sonnet-4-6    # CLAUDE_MODEL_LIGHT
skills:
  # Wert-Ebene: Trailing-line_comment auf der Knopf-Zeile (yq line_comment, verifiziert).
  implement:
    tier: heavy        # @reason: TDD-Zyklen schreiben Code → schweres Reasoning lohnt heavy.
    max_turns: 20      # @tradeoff: höhere Obergrenze = mehr Spielraum, aber teurer pro Lauf.
  review: { tier: heavy, max_turns: 8 }   # @reason: Lese-Analyse über mehrere Personas.
```

Beide getaggten Stellen — eigenständig (line-start) wie trailing — matchen dieselbe un-verankerte
Textkörper-Regex; die Wert-Ebene zusätzlich via `yq '.skills.implement.tier | line_comment'`.

Verweis anderswo (z. B. in `factory.config.yml.example` oder einem Skill) — **kein** Textkörper
(`@reason` ohne Doppelpunkt-Body), löst den Anti-Drift-Test also nicht aus:

```yaml
# Begründung/Trade-off: siehe factory.defaults.yml → skills.implement (Tag @reason)
implement:
  max_turns: 30
```

## Alternativen

### Option A: Strukturierte `@reason:`/`@tradeoff:`-Kommentare (gewählt)
**Vorteile:** greppbar (Kriterium-C-Test) **und** yq-lesbar (Wizard); null Gate-/Schema-Impact
(Kommentare sind für das Gate unsichtbar); bleibt „Begründung am Knopf" (ADR-009 #2); festes
Vokabular trennt Begründung/Trade-off/Env-Hinweis sauber.
**Nachteile:** Konvention ist konventionell erzwungen (per Test), nicht durch das Datenformat;
mehrzeilige Trade-offs brauchen Fortsetzungs-Kommentare.

### Option B: Begründung als Daten-Felder (`_doc: { reason:, tradeoff: }`)
**Vorteile:** trivial via `yq '.skills.implement._doc.reason'` extrahierbar, kein Kommentar-Parsing.
**Nachteile:** **bläht das Datenmodell** und zwingt das #36-Gate, Nicht-Knopf-Schlüssel
(`_doc.*`) bei der „Override-Pfade ⊆ Defaults-Pfade"- und Constraint-Prüfung auszunehmen
(Sonderfall genau in der Logik, die ADR-010 bewusst schlank hält); `schemaVersion`-Bump;
widerspricht ADR-009 #2 („Begründung als Kommentar am Knopf"). **Abgelehnt.**

### Option C: Freitext-Status quo lassen
**Vorteile:** keine Arbeit.
**Nachteile:** löst den CM-Blocker nicht — nicht verlässlich extrahierbar, kein Trade-off-Feld,
Kriterium C nur per Hand-Pflege erfüllbar (Drift). **Abgelehnt.**

## Begründung

Das Einfachste, das Kriterium A (Begründung **und** Trade-off je Knopf-Art) und Kriterium C
(eine extrahierbare, nicht duplizierte Quelle) erfüllt, ohne die in ADR-010 mühsam schlank
gehaltene Gate-/Schema-Schicht anzufassen (YAGNI; „erst korrekt, dann schnell"). Die Konvention
ist **reversibel**: Tags sind additiv, ein späterer Umzug nach Option B berührt nur die Defaults-
Datei + den Extraktor im Wizard, nicht die Aufrufer. Der eigentliche Hebel gegen Drift ist
derselbe wie in ADR-010 — **eine** Quelle, per Test erzwungen, statt zweiter Kopien.

## Konsequenzen

**Positiv:**
- Kriterium C wird testbar (greppbare Tags + „kein Text-Körper außerhalb der Defaults").
- Wizard/`/configure-factory` ziehen Begründung **und** Trade-off deterministisch — grep-basiert
  (positions-robust), Wert-Ebene zusätzlich via `yq line_comment` (verifiziert).
- Null Impact auf das #36-Gate und `schemaVersion`; CI-Images unverändert.
- Env-Var-/Header-Kommentare bleiben erhalten und sind durch das fehlende `@`-Tag klar abgegrenzt.

**Negativ / Trade-offs:**
- Konvention per Test erzwungen, nicht durch das Format — ein neuer Knopf ohne `@reason` fällt
  erst im Anti-Drift-/Vollständigkeits-Test auf (bewusst: derselbe „Test erzwingt Disziplin"-
  Mechanismus wie bei den übrigen Gates).
- Mehrzeilige Begründungen brauchen Fortsetzungs-Kommentarzeilen; der Extraktor muss
  zusammenhängende `#`-Zeilen unterhalb eines Tags als dessen Körper lesen.
- `factory.defaults.yml` wird etwas länger (Trade-off-Zeilen) — akzeptiert, das ist das
  Lehr-Artefakt.

## Implementierungs-Hinweise (für Task #35)

- **`factory.defaults.yml`:** bestehende Freitext-Begründungen in `@reason:`/`@tradeoff:`-Tags
  überführen (Dimensions-Ebene als eigenständige `#`-Zeilen über dem Schlüssel, Wert-Ebene als
  Trailing-`line_comment`). Env-Var-Hinweise (`# CLAUDE_MODEL_HEAVY`) **nicht** taggen.
- **Extraktor (Wizard-seitig):** primär **grep** mit der un-verankerten Textkörper-Regex (unten),
  Zuordnung über Pfad-Nähe (Trailing = selbe Zeile; eigenständig = direkt über dem Schlüssel);
  `yq '.<pfad> | line_comment'` als verifizierte Konvenienz für die Wert-Ebene. **Nicht** auf
  `head_comment`/`foot_comment` verlassen (in yq v4.53.3 leer — gegen die CI-yq gegenprüfen).
  Mehrzeilige Bodies über zusammenhängende `#`-Folgezeilen.
- **Anti-Drift-Test (Kriterium C, `run-tests.sh`):** portable POSIX-Regex **ohne `^`-Anker**
  `#[[:space:]]*@(reason|tradeoff):[[:space:]]*[^[:space:]]` (matcht eigenständige *und* trailing
  Tags); (a) jeder vom Wizard angebotene Knopf-Pfad hat ≥1 `@reason`; (b) kein Textkörper außerhalb
  `factory.defaults.yml` (Verweise matchen nicht). yq-freie Teile laufen ungated, yq-Teile unter
  `HAS_YQ`/`skip_yq` (ADR-009 §A). Test beidseitig (Positiv-Tag + Negativ-Verweis), clean-code.md.
  **Scope (b):** nur produktive Artefakte prüfen (`factory.config.yml*`, Skill-Dateien) — `docs/`
  (dieses ADR, die Spec) **ausnehmen**, da sie die Konvention lehren und legitim Beispiel-Tags
  tragen; sonst schlägt der Test an den Lehr-Beispielen an.
- **`factory.config.yml.example` / Skills:** nur Verweise (Pfad + Tag-Name ohne Doppelpunkt-Body),
  keine Text-Kopie.
