# /setup-project – Factory-Initialisierung für neues Projekt

Dieser Skill wird **einmalig zu Beginn eines neuen Projekts** ausgeführt.
Er analysiert das vorhandene Projekt und befüllt `docs/factory/PROJECT-CONTEXT.md`.

## Aufgabe

1. **Projekt analysieren** – scanne alle relevanten Konfigurationsdateien:
   - Sprache/Framework: `pom.xml`, `build.gradle`, `package.json`, `go.mod`,
     `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `*.csproj`
   - Tests: Suche nach Test-Verzeichnissen und Test-Framework-Abhängigkeiten
   - Linting/Formatierung: `.eslintrc`, `checkstyle.xml`, `.golangci.yml`, etc.
   - CI/CD: `.github/workflows/`, `.gitlab-ci.yml`
   - README, vorhandene ADRs

2. **Erkenntnisse zusammenfassen** und dem Entwickler zur Bestätigung vorlegen:
   ```
   Erkannte Konfiguration:
   - Sprache: [erkannt]
   - Framework: [erkannt]
   - Build: [erkannt]
   - Tests: [erkannt]
   - Lint: [erkannt]
   Ist das korrekt? Was fehlt oder ist falsch?
   ```

3. **Offene Fragen stellen** für Punkte, die nicht automatisch erkennbar sind:
   - Projektname und kurze Beschreibung
   - Team-Name
   - Architekturstil (falls nicht aus Code ersichtlich)
   - Mindest-Coverage-Schwelle
   - Projektspezifische Konventionen

4. **PROJECT-CONTEXT.md befüllen** – alle `{{PLATZHALTER}}` durch echte Werte ersetzen.

5. **checks/pre-commit.sh und pre-push.sh anpassen** – konkrete Lint- und Test-Befehle
   eintragen (die Platzhalter-Befehle ersetzen).

6. **Erste ADR anlegen** (optional) – falls bereits Architekturentscheidungen
   dokumentiert oder erkennbar sind.

7. **Factory-Config-Bootstrap** – `factory.config.yml` *mit Begründung* vorschlagen
   (siehe eigener Abschnitt unten). Nicht nur leere YAML hinstellen.

8. **Abschluss-Zusammenfassung** ausgeben:
   ```
   Factory initialisiert für: [Projektname]
   Tech-Stack: [Stack]
   Nächster Schritt: Erste Task anlegen mit `bash scripts/start-work.sh`
   ```

## Factory-Config-Bootstrap

> **Stage-2 advisory (ADR-009 #7):** Dieser Schritt schreibt **nur** die Datei
> `factory.config.yml`. Er ändert **kein** Laufzeitverhalten von `run-pipeline.sh`
> direkt — die Wirkung tritt erst beim nächsten Pipeline-Lauf über `load_config()` ein.

Ziel: dem Team einen **begründeten** Config-Vorschlag machen, nicht nur eine leere Datei.

### a) Bestehende Config schützen

Falls **bereits** eine `factory.config.yml` existiert: **nicht** stillschweigend
überschreiben. Hinweisen und um Bestätigung bitten; ohne Bestätigung die Datei
unangetastet lassen.

### b) Knöpfe + Begründung aus der einen Quelle

Alle Begründungs-/Trade-off-Texte leben **nur** in `factory.defaults.yml`
(Annotations-Konvention **ADR-011**: Tags `@reason` / `@tradeoff` am Knopf). Dieser
Skill **zitiert sie zur Laufzeit** aus den Defaults und hält **keine eigene Kopie**
(Anti-Drift, Spec #35 Kriterium C). Extraktion (verbindlich grep, Konvenienz yq):

```bash
yq eval '.skills | keys | .[]' factory.defaults.yml   # justierbare Skill-Knöpfe
grep -nE '#[[:space:]]*@(reason|tradeoff):[[:space:]]*[^[:space:]]' factory.defaults.yml
```

Biete **nur** die annotierten Knöpfe an (correct-by-construction). Die zwei v1-Knöpfe
**Modell-Tier** und **max_turns** sind **stack-unabhängig** — die Stack-Erkennung speist
`PROJECT-CONTEXT.md`, **nicht** diese Knöpfe. Daher: Default aus den Defaults vorschlagen
und kurz erfragen, nicht aus dem Stack ableiten. Je Knopf **Begründung (@reason)** und,
wo vorhanden, **Trade-off (@tradeoff)** zeigen. Für Non-Negotiables/Gate-Existenz gibt es
**keinen** Knopf. **Coverage ist kein Config-Knopf** (lebt in `PROJECT-CONTEXT.md`,
ADR-009 §D) — nicht anbieten; sonst unbekannter Key → Gate fail-closed.

### c) Correct-by-construction schreiben

Nach Bestätigung `factory.config.yml` schreiben — **nur** in den Defaults bekannte
Knöpfe, keine unbekannten Keys, keine Begründungs-Kopie (höchstens ein **Verweis** auf
`factory.defaults.yml` ohne `@tag:`-Body). Als Vorlage dient `factory.config.yml.example`.

### d) Über das Gate validieren — sonst keine Datei hinterlassen

```bash
bash scripts/checks/config-validation-check.sh
```

- **Exit 0:** Config gültig → behalten.
- **Exit ≠ 0:** **Keine** ungültige Datei hinterlassen — die geschriebene
  `factory.config.yml` wieder entfernen (bzw. den Vorschlag verwerfen) und melden, warum
  das Gate fehlschlug. Die Task gilt **nicht** als fertig mit ungültigem Artefakt.

Spätere Einzelanpassungen laufen über `/configure-factory`.

## Output

- `docs/factory/PROJECT-CONTEXT.md` vollständig befüllt
- `scripts/checks/pre-commit.sh` mit echten Befehlen
- `scripts/checks/pre-push.sh` mit echten Befehlen
- `factory.config.yml` (begründeter Vorschlag, Gate-grün) – oder bewusst keine, wenn
  Defaults passen / Gate fehlschlägt / bestehende Datei nicht überschrieben werden soll
- Optional: `docs/adr/001-initial-architecture.md`

## Hinweis

Dieser Skill ist für Stage 2 (manuell) ausgelegt. Er wird nicht durch
`run-pipeline.sh` aufgerufen – nur einmalig vom Entwickler. Laufende
Einzelknopf-Anpassungen danach: `/configure-factory`.
