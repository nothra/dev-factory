# ADR 010: Config-Validierung über yq-natives Gate (verfeinert ADR-009)

## Status
Accepted (2026-06-24)

> Verfeinert **ADR-009** (Geführte Factory-Konfiguration, Accepted). ADR-009 nennt in
> „Betroffene Stellen" ein „JSON-Schema" und in §6 ein Maximum „im Schema"; diese ADR
> entscheidet konkret **wie** validiert wird, nachdem klar ist, dass die Toolchain keinen
> JSON-Schema-Validator hat. Sie ändert keine Entscheidung von ADR-009, sondern füllt eine
> offene Umsetzungsfrage (siehe Task #36 „Offene Fragen").

## Date
2026-06-24

## Kontext

ADR-009 §B fordert: `schemaVersion` als Integer, unbekannte Keys **fail-closed**. §6 fordert
für jeden Kosten-Knopf (v1: `max_turns`) eine **harte Obergrenze**. Heute (nach !34) liest
`run-pipeline.sh` die geschichtete Config (`factory.defaults.yml [* factory.config.yml]`), aber
**nichts validiert sie**: ein Tippfehler im Override (`max_turn` statt `max_turns`, ein
unbekannter Key, eine absurde Turn-Zahl) greift still ins Leere — der Default zieht heimlich.
Genau die „stilles Defaulting"-Falle, die ADR-009 ausschließen will.

Die Krux: ADR-009 schreibt „JSON-Schema", aber die Gate-/Skript-Toolchain ist bewusst schlank
(`bash git jq yq`, siehe ADR-009-Treiber „Toolchain"). Ein echter JSON-Schema-Validator wäre
eine **neue** Abhängigkeit in beiden CI-Images — dieselbe Klasse Entscheidung wie „yq vs.
Fallback" (ADR-009 §A), die nicht beiläufig getroffen werden soll.

Zusätzliche Randbedingung aus dem Projekt: Validierungs-Regeln dürfen die **kanonische Quelle**
nicht duplizieren (W-02/W-03-Lektion). Die Menge erlaubter Knöpfe lebt bereits in
`factory.defaults.yml` — eine zweite, separat gepflegte Schema-Liste derselben Keys würde
genau die Drift erzeugen, die ADR-009 bekämpft.

## Entscheidung

Ein **yq-natives Validierungs-Gate** als eigenes Skript `scripts/checks/config-validation-check.sh`.
Kein zusätzlicher JSON-Schema-Validator in der Toolchain.

Die erlaubte Struktur wird, soweit möglich, **aus `factory.defaults.yml` abgeleitet** (Single
Source, kein zweites Schema-Dokument für dieselben Keys):

1. **Unbekannte Keys → fail-closed.** Jeder Blatt-Pfad in `factory.config.yml` muss als Pfad in
   `factory.defaults.yml` existieren. Die Default-Datei **ist** die erlaubte Oberfläche; ein neuer
   Knopf wird automatisch erlaubt, sobald er in den Defaults steht (keine Schema-Pflege nötig).
   Fehlerausgabe nennt den verletzenden Pfad.
2. **`schemaVersion`-Mismatch → fail-closed.** Erwartete Version = `factory.defaults.yml`-Wert
   (Single Source); weicht der Override ab, klare Meldung mit Upgrade-Hinweis.
3. **Werte-Constraints:**
   - `tier` ∈ Schlüssel von `model_tiers` (abgeleitet: heute `{heavy, light}`).
   - `max_turns` ist Integer und `1 ≤ x ≤ MAX_TURNS_CEILING`.
   - `schemaVersion` ist Integer.
4. **YAML-Parsefehler → fail-closed** mit Datei/Stelle (keine stille Verarbeitung).

**Heimat der Obergrenze (das einzige genuin Neue, nicht aus Defaults ableitbar):** v1 als
benannte Konstante am Kopf des Gate-Skripts (`MAX_TURNS_CEILING`), mit Kommentar auf ADR-009 §6.
Es gibt in v1 **genau eine** Obergrenze; sie ist Gate-**Policy**, kein überschreibbarer
Default — sie gehört bewusst nicht in die merge-bare Config (sonst könnte ein Override sein
eigenes Maximum anheben und den Guard aushebeln). Kommen weitere Obergrenzen hinzu, werden sie
in eine deklarative Policy-Datei neben dem Gate promotet (siehe Konsequenzen).

**Aufrufpunkte (zwei, fail-closed):**
- **Laufzeit:** `run-pipeline.sh` → in/vor `load_config()` (Z. 73). Ungültige Config bricht den
  Lauf **vor** der ersten Agenten-Aktion ab. yq ist dort ohnehin Prerequisite (ADR-009 §A).
- **Test-Suite:** `run-tests.sh` mit Positiv- **und** Negativ-Fixtures (clean-code.md: Gate-Logik
  immer beidseitig testen). yq-abhängig → `HAS_YQ`-gated `skip_yq`, damit die Suite **yq-frei
  grün** bleibt ([[factory-yq-test-suite-yqfree]]).

## Alternativen

### Option A: yq-natives Gate (gewählt)
**Vorteile:** keine neue Abhängigkeit (yq schon Prerequisite); erlaubte Keys aus den Defaults
abgeleitet → keine Schema-Drift; reines Bash/yq → mit den vorhandenen Tabellen-Tests beidseitig
testbar; konsistent zur „schlanken Toolchain"-Linie von ADR-009.
**Nachteile:** wir interpretieren Validierungs-Regeln selbst statt sie deklarativ zu standardisieren;
komplexere Constraints (verschachtelte Typen, `oneOf`) wären in yq mühsam — für den heutigen
flachen Knopf-Satz (`tier`, `max_turns`, `schemaVersion`) aber kein Thema.

### Option B: Echter JSON-Schema-Validator (`check-jsonschema`/`ajv`/python-`jsonschema`)
**Vorteile:** deklaratives Standard-Schema; ausdrucksstark; Schema separat dokumentier-/wiederverwendbar.
**Nachteile:** **neue Abhängigkeit** in beiden CI-Images (Python/Node-Tool) — Gewicht und
Angriffsfläche für einen heute trivialen Regel-Satz; das Schema listet die erlaubten Keys ein
**zweites Mal** neben den Defaults → Drift-Gefahr (W-02/W-03); widerspricht ADR-009-Treiber
„Toolchain schlank". **Abgelehnt für v1** — YAGNI; das „JSON-Schema"-Wort in ADR-009 war Absicht,
nicht Tool-Festlegung.

### Option C: Hybrid — JSON-Schema-Datei, interpretiert durch yq/jq (kein externer Validator)
**Vorteile:** deklaratives Schema-Artefakt ohne neues Tool.
**Nachteile:** wir bauten einen Teil-JSON-Schema-Interpreter in Bash — Over-Engineering; das
Schema dupliziert weiterhin die Default-Keys. **Zurückgestellt** (analog zum Lockfile in ADR-009):
Option, falls der Constraint-Satz je deklarativ-komplex wird.

## Begründung

Das Einfachste, das ADR-009 §B/§6 erfüllt (YAGNI, architecture-principles „erst korrekt, dann
schnell"). Der Regel-Satz ist klein und flach; ein Standard-Validator löst ein Problem, das wir
nicht haben, und zahlt mit einer Abhängigkeit + einer zweiten Wahrheit. Das Ableiten der
erlaubten Oberfläche aus den Defaults ist der eigentliche Hebel gegen Drift — es macht das
Gate **billiger zu pflegen** als jedes separate Schema. Die Entscheidung ist **reversibel**:
Aufrufpunkt und Regel-Set sind hinter einem Skript gekapselt; ein späterer Wechsel auf Option B/C
berührt nur dieses Skript, nicht die Aufrufer.

## Konsequenzen

**Positiv:**
- Stilles Defaulting ist geschlossen — Tippfehler/unbekannte Keys/Über-Maxima brechen laut ab.
- Keine neue Toolchain-Abhängigkeit; CI-Images unverändert.
- Erlaubte Keys bleiben automatisch synchron mit den Defaults (kein Pflege-Doppel).
- Das Gate ist eigenständig testbar und wird von `run-pipeline.sh` **und** der Test-Suite genutzt.
- Schafft die Vorbedingung für **Task #35** (Ph.3-Wizard validiert seine erzeugte Config hierüber).

**Negativ / Trade-offs:**
- Validierungs-Regeln sind Bash/yq-Code statt eines deklarativen Standards — bei künftig
  komplexeren Constraints neu zu bewerten (dann Option C/B).
- `MAX_TURNS_CEILING` als Skript-Konstante ist eine bewusste Vereinfachung gegenüber ADR-009 §6
  („im Schema"). Bei mehr als einer Obergrenze → deklarative Policy-Datei neben dem Gate
  (`scripts/checks/`), die Aufrufer ändert das nicht.
- Override-seitiges Setzen von `limits`/Policy ist nicht vorgesehen — bewusst (Guard-Schutz).
- Folge der abgeleiteten Key-Oberfläche: **neue Tiers oder Skills kommen nur über die Defaults
  (Template-Update), nicht per Team-Override.** Ein nicht-vordefinierter Pfad (`model_tiers.medium`,
  ein neuer Skill-Key) wird als unbekannter Key fail-closed abgelehnt; ein `tier:` außerhalb
  `{heavy, light}` ebenso. Bewusst für v1 — Profile/Erweiterbarkeit sind additiv nachrüstbar
  (ADR-009 §3), ohne die Aufrufer zu berühren.

## Implementierungs-Hinweise (für den Coding-Agenten, Task #36)

- **Neues Skript** `scripts/checks/config-validation-check.sh`:
  - Eingabe: Pfad zu defaults + optional override (Default: die Repo-Dateien). Exit 0 = gültig,
    ≠ 0 = ungültig (Pfad/Grund auf stderr).
  - **Unbekannte-Key-Prüfung:** Blatt-Pfade des Overrides via `yq ... | path`-Ausgabe gegen die
    Pfad-Menge der Defaults prüfen (Override-Pfade ⊆ Defaults-Pfade). Tippfehler wie `max_turn`
    fallen hier raus.
  - **Constraints:** `tier ∈ {keys(model_tiers)}`, `max_turns` Integer in `[1, MAX_TURNS_CEILING]`,
    `schemaVersion` Integer == Defaults-Wert.
  - `MAX_TURNS_CEILING` als dokumentierte Konstante am Skriptkopf (Verweis ADR-009 §6 / ADR-010).
  - Portable POSIX-Regex; keine BSD/GNU-Divergenz (clean-code.md).
- **`run-pipeline.sh`:** `load_config()` (Z. 73) ruft das Gate nach dem Merge / vor der ersten
  Nutzung; bei ≠ 0 → roter Abbruch mit Hinweis (kein Default-Fallback).
- **Tests in `run-tests.sh`:** je Regel ein Positiv- und ein Negativ-Fixture
  (gültiger Override, unbekannter Key, `schemaVersion`-Mismatch, `max_turns` über Ceiling,
  kaputtes YAML, gültige Defaults-only). Alles unter `HAS_YQ` → sonst `skip_yq`, nie rot.
  Fixtures unter `scripts/checks/tests/` (Test-Artefakte; **nicht** das in #35 ausgelieferte
  `factory.config.yml.example`).
- **Abgrenzung:** Coverage-Schwelle (ADR-009 §D, raise-only) lebt heute in `PROJECT-CONTEXT.md`,
  nicht in `factory.config.yml` — **nicht** Teil von #36. Sobald sie in die Config wandert,
  ergänzt eine raise-only-Regel dieses Gate.
- **Reihenfolge:** #36 **vor** #35 mergen (der Wizard baut darauf auf).
