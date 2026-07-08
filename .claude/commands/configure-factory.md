# /configure-factory – Einzelknopf-Anpassung der Factory-Config

Leichtgewichtige, **laufende** Anpassung einzelner Config-Knöpfe nach dem Erststart –
ohne `/setup-project` zu wiederholen. Ändert genau einen Knopf in `factory.config.yml`,
zeigt dabei die Begründung **aus der einen Quelle** und validiert das Ergebnis über das
Gate, bevor es als fertig gilt.

> **Stage-2 advisory (ADR-009 #7):** Dieser Skill schreibt **ausschließlich**
> `factory.config.yml`. Er ändert **kein** Laufzeitverhalten von `run-pipeline.sh` direkt —
> die Wirkung tritt beim nächsten Pipeline-Lauf über `load_config()` ein.

## Single Source of Truth

Alle Begründungs- und Trade-off-Texte leben **nur** in `factory.defaults.yml`
(Annotations-Konvention **ADR-011**: Tags `@reason` / `@tradeoff` am Knopf). Dieser Skill
**zitiert sie zur Laufzeit** aus dieser Datei — er hält **keine eigene Kopie** (Anti-Drift,
Spec #35 Kriterium C). Beim Anzeigen eines Knopfes immer den aktuellen Text aus den
Defaults extrahieren, nicht hier hineinschreiben.

## Aufgabe

### 1. Welche Knöpfe gibt es? (correct-by-construction)

Biete **nur** die in `factory.defaults.yml` annotierten Knöpfe an. Es gibt **keinen** Knopf
für Non-Negotiables oder die Existenz eines Gates — Doktrin bleibt geschützt (ADR-009,
Leitplanken). Ein Knopf, für den **keine** `@reason`-Annotation existiert, wird **nicht**
angeboten (keine Begründung ohne Quelle).

Knopf-Liste aus den Defaults ableiten (yq, da Prerequisite):

```bash
# Alle justierbaren Skill-Knöpfe (tier / max_turns):
yq eval '.skills | keys | .[]' factory.defaults.yml
# Modell-Tiers (heavy/light → Modell-ID):
yq eval '.model_tiers | keys | .[]' factory.defaults.yml
```

### 2. Begründung aus der einen Quelle zeigen

Bevor ein Knopf geändert wird, die Begründung **aus den Defaults extrahieren** und zeigen.
Verbindlicher Pfad ist **grep** (positions-robust, ADR-011-Extraktions-Vertrag); die
un-verankerte POSIX-Regex (kein `^`-Anker, kein `\s`/`grep -P`):

```bash
# Wert-Ebene (Trailing-Tag am Knopf) – Konvenienz via yq line_comment (verifiziert):
yq eval '.skills.implement | line_comment' factory.defaults.yml

# Verbindlich & positions-robust (eigenständige UND trailing Tags) via grep:
grep -nE '#[[:space:]]*@(reason|tradeoff):[[:space:]]*[^[:space:]]' factory.defaults.yml
```

Zeige dem Entwickler je Knopf **Begründung (@reason)** und – wo vorhanden –
**Trade-off (@tradeoff)** im Klartext, plus den aktuellen effektiven Wert.

### 3. Genau einen Knopf ändern

Frage den Zielwert ab und schreibe ihn nach `factory.config.yml` (anlegen, falls nicht
vorhanden). Schreibe **correct-by-construction**: nur den einen bekannten Knopf-Pfad,
keine unbekannten Keys, keine Begründungs-Kopie (höchstens einen **Verweis** auf
`factory.defaults.yml`, ohne den `@tag:`-Doppelpunkt-Body — siehe ADR-011 Verweis-Form).

Bestehende Overrides in `factory.config.yml` **nicht** verwerfen – nur den Zielknopf
ergänzen/ersetzen.

### 4. Über das Gate validieren (vor „fertig")

Vor dem Abschluss **immer** das Validierungs-Gate (#36) aufrufen:

```bash
bash scripts/checks/config-validation-check.sh
```

- **Exit 0:** Config ist gültig → fertig.
- **Exit ≠ 0:** Die Änderung ist ungültig (unbekannter Key, Wert außerhalb der Grenzen,
  schemaVersion-Mismatch). **Nicht** als fertig melden. Die Änderung zurücknehmen oder
  korrigieren und erneut validieren. Kein ungültiges Artefakt hinterlassen.

## Output

- `factory.config.yml` mit genau dem geänderten, **bekannten** Knopf (Gate-grün).
- Klartext-Zusammenfassung: welcher Knopf, alter → neuer Wert, gezeigte Begründung-Quelle.

## Hinweis

Stage-2 (manuell). Wird **nicht** von `run-pipeline.sh` aufgerufen. Für den Erst-Setup
stattdessen `/setup-project` (Bootstrap inkl. Config-Vorschlag).
