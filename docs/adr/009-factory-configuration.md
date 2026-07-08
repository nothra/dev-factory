# ADR 009: Geführte Factory-Konfiguration — kanonische, geschichtete Config

## Status
**Accepted** (2026-06-23) — Architektur durch Review-Konsens (CM + Bastian, !26) bestätigt.
Punkte A–F geklärt, Tiering-Kriterium (G) geschärft. Umsetzung in Phasen; Phase 1b (Rewire
von `run-pipeline.sh` auf Config) kann starten. Reihenfolge: läuft **parallel/nach Stufe 2**,
überholt offene Stufe-2-Items nicht hart.

> **Review-Konsens (!26), eingearbeitet:**
> - **A** `yq` verbindlich, **kein** Fallback — der Rewire löscht die Hardcode-`case`-Blöcke,
>   Config ist die einzige Quelle (§2).
> - **B** `schemaVersion` als **Integer**, unbekannte Keys → fail-closed.
> - **C** `models.yml` datiert + Staleness-Warnung. **D** Schwellen v1 nur Coverage (raise-only).
>   **E** Token-Schätzung v1 statische Obergrenze. **F** `configure-factory` eigener Skill.
> - **G** Tiering-Kriterium geschärft: *„Gibt es ein automatisiertes Gate für den Output des
>   Schritts?"* → `review`/`architecture`/`security-review` „ohne Backstop", `test`/`refactor`
>   „gate-gedeckt" (§4).

## Date
2026-06-19 (Entwurf) · 2026-06-23 (Accepted)

## Context

Das Template muss je nach Team und Projekt stark angepasst werden: welche Pipeline-Schritte
in welcher Ausgestaltung, welches Modell für welchen Agenten, wie viele Turns, welche
Schwellen. Diese Stellschrauben sind heute **verstreut**:

| Stellschraube | Wo sie heute lebt |
|---|---|
| Modell pro Agent | `get_model()` in `run-pipeline.sh` (hardcoded `case`) |
| Max-Turns pro Agent | `get_max_turns()` in `run-pipeline.sh` |
| Welche Schritte / Reihenfolge | fest verdrahtete Sequenz in `run-pipeline.sh` |
| Welche Guidelines gelten | `@import` in `CLAUDE.md` |
| Gates an/aus | `scripts/checks/*` + Hooks + CI |
| Coverage-Schwelle, Projektfakten | `PROJECT-CONTEXT.md` (Platzhalter) |
| Telemetrie | `config/otel.env.example` |

Adoptierende Teams müssen ihren Prozess in der Factory abbilden können, **ohne Skripte zu
patchen**. Verstreute Knöpfe führen zu Inkonsistenz (vgl. die kanonische-Quelle-Lektion in
`PROJECT-CONTEXT.md`) und sind schwer wartbar. Zugleich ist die Modell-/Turn-Wahl der
zentrale **Kosten-Hebel** — eine Config ohne Kosten-Sicht lädt zu teuren Fehlkonfigurationen ein.

Das passt in das Kernprinzip der Factory: **deterministische Skripte orchestrieren Agenten.**
Eine deklarative Config, die der Orchestrator liest, ist genau die fehlende Schicht — kein
Fremdkörper.

### Entscheidungstreiber

| Treiber | Warum kritisch |
|---|---|
| **Single Source of Truth** | Heute leben dieselben Werte an mehreren Orten → Drift. |
| **Doktrin-Schutz** | Eine Config ist „Konversation als Datei" — Non-Negotiables dürfen nicht wegkonfigurierbar sein. |
| **Kosten** | Modell/Turns sind teuer; jeder Kosten-Knopf braucht eine Obergrenze. |
| **Wartbarkeit** | Template-Updates müssen einspielbar bleiben, ohne Team-Anpassungen zu zerstören. |
| **Toolchain** | Gates/Skripte haben heute nur `bash git jq` (kein YAML-Parser). |

## Decision

### 1. Geschichtete Config, nicht ein Monolith
`factory.defaults.yml` (vom Template mitgeliefert = heutige Hardcode-Werte) + team-eigene
`factory.config.yml` (Override, git-getrackt) → deterministischer Merge → **effektive Config**.
Vorteil: sauberer Upgrade-Pfad — das Template liefert neue Defaults, der Team-Override bleibt
klein.

### 2. YAML als Autoren-Format, `yq` ins Runtime-Image
Die Config ist ein **Lehr-Artefakt**, kein reines Datenfile: die Begründung steht als Kommentar
direkt am Knopf, wo jemand ihn dreht. Das ist der Mechanismus, mit dem die Doktrin überlebt —
JSON kann das nicht. `yq` ist ein einzelnes statisches Binary und wird analog zum bestehenden
`factory-selftest`-Image gebacken. Es gibt keinen Hot-Path (Config wird einmal pro Feature
gelesen), daher **kein** kompiliertes JSON-Lockfile in v1 (bewusst offengehalten, falls je ein
Hot-Path entsteht).

**`yq` ist Prerequisite, kein Fallback (A, !26):** Es gibt **keinen** „Config oder Hardcode"-
Notpfad — ein dauerhafter Fallback wäre genau die zweite Quelle, die diese ADR beseitigt. Der
Rewire **löscht** die Hardcode-`case`-Blöcke; die Config ist danach die einzige Quelle. `yq`
gehört damit neben `git`/`bash` in beide Images **und** in die README-Voraussetzungen. Fehlt
`yq` lokal, muss der Lauf **laut** mit Install-Hinweis abbrechen (kein kryptischer Fehler, kein
stilles Defaulting). Die Test-Suite bleibt yq-frei lauffähig (Struktur-Checks per `grep`); der
eigentliche Resolution-Test läuft dort, wo `yq` vorhanden ist.

### 3. Profil-fähige Engine, aber v1 = eine Config
Der Merge-Resolver nimmt einen optionalen Profilnamen entgegen (`defaults → profile → override`);
v1 nutzt immer `default`. Damit sind benannte Profile (z. B. `schnell` für Docs, `gründlich`
für Kernfeatures) später ein **additiver** Layer, kein Breaking Change. Profile jetzt voll
auszubauen wäre Scope-Bruch (YAGNI; `bug-fix` ist bereits ein De-facto-Zweitprofil).

### 4. Konfigurierbarkeits-Grenze: automatisiertes Gate für den Output entscheidet das Tier
> **Die Sicherheit, einen Schritt optional zu machen, hängt davon ab, ob es ein
> *automatisiertes* Gate für den *Output dieses Schritts* gibt.** (Kriterium geschärft im
> !26-Konsens.) Lint/Tests/Coverage backen *Verhalten* und *Stil* — nicht *Design/Logik/Intent*.

| Tier | Schritte | Regel |
|---|---|---|
| **Gesperrt** | `codify` (Non-Negotiable #6), `implement` (Test-Gate erzwingt TDD) | Modell/Turns tunable, Entfernen unmöglich |
| **Gate-gedeckt** | `test`, `refactor` | Als Schritt abschaltbar — ein Auto-Gate fängt den Output ab |
| **Ohne Backstop** | `review`, `architecture`, `security-review` | Opt-out nur mit **ADR-Referenz** in der Config (auditierbar), kein stilles `enabled: false` |

**Warum `review`/`architecture`/`security-review` „ohne Backstop":** Sie produzieren
Urteile über Design/Logik/Intent bzw. Sicherheit — genau die Klasse, für die es **kein**
automatisches Gate gibt. Beleg ist die Zusammenarbeit selbst: Reviews fangen in jedem MR Bugs,
die **alle Tests grün** lassen (`grep -c`-Fehlerausgabe, falsche Autonomie-Mengen, curl-`000`,
`if`-ohne-`else`-Exit). Opt-out daher nur mit ADR-begründetem Beschluss.

**Warum `refactor` trotzdem „gate-gedeckt":** Seine definierende Eigenschaft ist
*verhaltenserhaltend* — und das **prüfen die Tests** (grün bleiben = Verhalten erhalten). Sein
*Wert* (sauberes Design) ist von Lint nur teilweise gegated; eingestuft wird er dennoch als
gate-gedeckt, **weil die Folge des Weglassens erholbar ist** (Tech-Debt, später nachholbar) —
anders als bei review/security, wo ein Defekt/Loch nach dem Merge live ginge. Die Konsequenz-
Asymmetrie, nicht eine vollständige Gate-Deckung, rechtfertigt die Einstufung.

### 5. Gates: Existenz gesperrt, Strenge nur nach oben
Schwellen (z. B. Coverage) dürfen in die Config wandern, aber nur **rauf** vom Template-Floor,
nie drunter. Ein Gate kann nicht abgeschaltet, nur verschärft werden.

### 6. Jeder Kosten-Knopf bekommt eine harte Obergrenze
`max-turns`, der Review↔Implement-Circuit-Breaker (heute fix „max 3") u. Ä. werden
tunable-**mit-Maximum** im Schema. Verhindert, dass eine Config versehentlich eine
Kostenexplosion erlaubt. (Dasselbe Prinzip wie der Budget-Guard in ADR-008.)

### 7. Stage 2 advisory, Stage 3 verbindlich
`run-pipeline.sh` (Stage 3) liest die Config und steuert Modell/Turns hart. Im interaktiven
Stage-2-Betrieb (`/implement` in einer Session) ist die Config **advisory** — der Skill kann
sie lesen und vorschlagen, aber das Session-Modell gewinnt. Sonst divergieren beide still.

### 8. Token-Analyse phasiert: erst statisch, dann empirisch
- **Statisch (v1):** Obergrenze aus der Config (Modellpreis × Turns × Schritte). Sofort
  verfügbar, grob. Preise leben in einer **datierten** `models.yml` (Single Source); die
  Schätzung druckt „Preise Stand <Datum>", damit Staleness sichtbar ist.
- **Empirisch (später):** OTEL-Historie (ADR-006) → Pro-Skill-Verteilung → kalibrierte
  Schätzung mit Pro-Feature-Nenner (Tokens/gemergtem Feature). Andockend an `/daily-metrics`.

### 9. Geführter Prozess in `/setup-project`
Erststart-Bootstrap (Stack erkennen → Config mit Trade-offs vorschlagen) in `/setup-project`,
plus ein leichtes `/configure-factory` für laufende Anpassung. Der Wert liegt in der
**Führung mit Begründung**, nicht im YAML. Die Begründungs-Texte haben **einen** Ort
(Annotationen der Defaults-Datei), aus dem Wizard und Inline-Kommentare gespeist werden —
keine Dreifach-Kopie (W-02/W-03-Lektion).

## Alternatives

### JSON statt YAML
**Pro:** `jq` ist überall vorhanden, keine neue Abhängigkeit.
**Contra:** keine Kommentare → die Begründung am Knopf (Kern des „geführten" Versprechens)
geht verloren. **Abgelehnt** — das Lehr-Artefakt-Argument wiegt schwerer als die ~10 MB `yq`.

### Eine einzige Config-Datei (kein Defaults/Override)
**Pro:** einfacher zu lesen. **Contra:** Template-Updates an Defaults sind schwer einspielbar.
**Abgelehnt** zugunsten der Schichtung.

### Env-Vars erweitern (Status quo)
**Pro:** minimaler Aufwand. **Contra:** bleibt verstreut, kein Schema, keine Führung.
**Abgelehnt** — löst das Kernproblem nicht.

### Kompiliertes JSON-Lockfile (YAML → `factory.config.lock.json`)
**Pro:** Skripte lesen jq-nativ, Mensch editiert YAML. **Contra:** generiertes Artefakt +
Drift-Disziplin, ohne Hot-Path Over-Engineering. **Zurückgestellt** — Option, falls je ein
Hot-Path entsteht.

### Volle Profile / freie Schritt-Reihenfolge in v1
**Abgelehnt für v1** — Reordern ist eine große Korrektheits-Angriffsfläche (Schritte kodieren
Abhängigkeiten, vgl. ADR-005) für wenig Mehrwert; volle Profile sprengen den Scope. Beides
bleibt additiv nachrüstbar.

## Consequences

**Positiv:** Single Source of Truth; Teams konfigurieren ohne Skript-Patches; Doktrin bleibt
geschützt (Non-Negotiables nicht abschaltbar, Gates raise-only); Kosten werden vor dem Lauf
einschätzbar; profil- und lockfile-fähig ohne Vorab-Aufwand.

**Negativ / Trade-offs:** neue `yq`-Abhängigkeit im Image; Schema-Versionierung wird nötig
(Template-Update kann Team-Override stale machen → `schemaVersion` als Integer + Validierung
gegen unbekannte/entfernte Keys, fail-closed); die `models.yml`-Preistabelle rottet ohne Pflege (daher datiert
+ sichtbar).

## Betroffene Stellen (bei Umsetzung)
> **Verfeinert durch ADR-010** (Accepted): Das „JSON-Schema" und das Maximum „im Schema" (§6)
> werden als **yq-natives Gate** umgesetzt — kein JSON-Schema-Validator in der Toolchain, die
> erlaubte Key-Oberfläche wird aus `factory.defaults.yml` abgeleitet. Details: `docs/adr/010-config-validation-gate.md`.

- `factory.defaults.yml` / `factory.config.yml` (neu) + Validierung (yq-nativ, ADR-010)
- `scripts/checks/` — Validierungs-Gate (schema-getestet, Positiv/Negativ-Fall)
- `scripts/run-pipeline.sh` — von Hardcode auf Config-Lesen umstellen; `--dry-run` als
  Golden-Test-Oberfläche
- `.claude/commands/setup-project.md` (+ neues `configure-factory`)
- `CLAUDE.md` — `@import`-Block aus der Config speisen statt statisch
- `models.yml` (neu, datiert) für die Token-Schätzung
- `ci/factory-selftest.Dockerfile` — `yq` ergänzen
