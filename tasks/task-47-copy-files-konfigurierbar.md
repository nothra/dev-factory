# Task 47: copy-files-konfigurierbar

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Die feste `.env.local`-Spiegelung in `start-work.sh` wird durch den Config-Schlüssel
`start_work.copy_files` (Liste von Dateipfaden, Default `[]`) ersetzt. Die Schutzlogik bleibt
(nie überschreiben, Modus erhalten, Aufräumen, kein Abbruch). `start_work.hint` wird von der Kopie
entkoppelt, Opt-out heißt `FACTORY_WT_SKIP_COPY` (Alias `FACTORY_WT_SKIP_ENV`), und der
Ursprungs-Wortlaut verschwindet aus Skript und Tests.
Spec: [`docs/specs/spec-47-copy-files-konfigurierbar.md`](../docs/specs/spec-47-copy-files-konfigurierbar.md)

## Akzeptanzkriterien
<!-- Details, GIVEN/WHEN/THEN und Fehlerszenarien F1–F8: siehe Spec -->
- [x] AK1 – Default `[]` kopiert nichts
- [x] AK2 – genau die gelisteten Dateien werden byte-identisch gespiegelt
- [x] AK3 – Modus der Quelle bleibt erhalten
- [x] AK4 – vorhandenes Ziel (Datei/Symlink) wird nie überschrieben, übrige Einträge laufen weiter; Mutationsbeleg
- [x] AK5 – fehlende Elternordner werden im Worktree angelegt
- [x] AK6 – Symlink als Quelle wird als echte Datei kopiert
- [x] AK7 – `FACTORY_WT_SKIP_COPY=1` unterdrückt die Spiegelung
- [x] AK8 – `FACTORY_WT_SKIP_ENV=1` wirkt als Alias
- [x] AK9 – Output nennt den Opt-out-Schalter
- [x] AK10 – `start_work.hint` erscheint auch ohne Kopie
- [x] AK11 – `start_work.hint` erscheint auch im In-Place-Modus und bei Opt-out
- [x] AK12 – leerer Hinweis → keine Hinweis-Zeile
- [x] AK13 – Config-Gate nimmt gültige Liste an
- [x] AK14 – Config-Gate lehnt absolut / `..` / leer / Nicht-String / Skalar statt Liste / abschließendes `/` ab
- [x] AK15 – Konsument mit `[".env.local"]` behält sein Verhalten (Verhaltenstest)
- [x] AK16 – kein Ursprungs-Wortlaut in `start-work.sh` und Testgruppe
- [x] AK17 – Doku (FACTORY.md Regel 8, git-workflow.md, OPERATING.md, .gitignore-Kommentare, CHANGELOG mit Migrationszeile) nachgezogen
- [x] AK18 – alle Gates grün
- [x] Fehlerszenarien F1–F8 getestet

## Technische Notizen
Architektur: Nachtrag 2026-11-01 in `docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md`
(E23–E27, Status Proposed → beim Umsetzen auf Accepted flippen). Kein neues ADR, keine neue Datei.

Implementierungs-Hinweise:
1. **`scripts/lib/gate-config.sh`:** `factory_cfg_list <pfad>` (ein Element je Zeile, `// []`, gleiche
   Merge-Logik wie `factory_cfg`; `*` ersetzt Listen, hängt nicht an) und `copy_entry_problem <eintrag>`
   (leer = gültig; sonst Grund: leer / absolut / `..`-Segment / abschließendes `/` / Steuerzeichen).
   Modul-Header „Stellt bereit" mitpflegen (Lesson nothra/tch-gastro-services#207).
2. **`config-validation-check.sh`:** `gate-config.sh` relativ zum Skript sourcen
   (`$(dirname "${BASH_SOURCE[0]}")/../lib/gate-config.sh`, nicht über `FACTORY_DIR` – Lesson
   nothra/tch-gastro-services#431). Neue Regel 9 nach dem Muster von Regel 8: Typ `!!seq`, Elemente
   `!!str`, jeder Eintrag durch `copy_entry_problem`. Header-Aufzählung ergänzen.
   **Achtung:** jede Test-Fixture, die `config-validation-check.sh` in eine Wegwerf-Wurzel kopiert, muss
   jetzt auch `scripts/lib/gate-config.sh` mitkopieren (Lesson nothra/tch-gastro-services#197) – vorher
   per Grep zählen.
3. **`factory.defaults.yml`:** `start_work.copy_files: []` mit `@reason`/`@tradeoff`; Kommentar zu
   `hint` von der `.env.local` lösen.
4. **`start-work.sh`:** Funktion je Eintrag (Validator → `-f`-Quelle → Elternkette ohne Symlink, fehlende
   Ordner einzeln per `mkdir` → `-e`/`-L`-Guard → `cp -p` → Aufräumen `|| true`), jede Abweichung = Warnung
   + `return 0`. `-d "$WORKDIR"`-Guard bleibt. Liste per `while IFS= read -r` (Leerzeichen im Pfad
   erlaubt). Opt-out `SKIP="${FACTORY_WT_SKIP_COPY:-${FACTORY_WT_SKIP_ENV:-0}}"`. `ENV_COPIED` und die
   Hinweis-Kopplung entfernen; Hinweis-Block außerhalb jeder Bedingung. Hilfetext: `factory-pipeline` raus,
   Schalter umbenennen. WHY-Kommentare ohne Ursprungs-Wortlaut (AK16).
5. **Tests (`scripts/checks/tests/run-tests.sh`):** Gruppe „#236" neutral umbauen – Fixture-Config setzt
   `copy_files` explizit, Hinweis-Wortlaut neutral (kein `pnpm db:seed`). Bestehende Fälle (Symlink-Quelle,
   defekter Symlink, unlesbar, `cp`-Teilabbruch per PATH-Stub, Modus) bleiben und laufen gegen einen
   konfigurierten Eintrag. Neu: AK1/2/5/7/8/10–12/15, F2/F5/F6/F8, Gate-Fälle AK13/14 (je ein Negativtest).
   Mutationsbeleg AK4: dieselbe Guard-Funktion auf Original und Mutante (Lesson Factory-Task #23).
   Zwei-Einträge-Fälle: Ein Fehlschlag in Eintrag 1 darf Eintrag 2 nicht verhindern – assertieren.
6. **Doku (AK17):** FACTORY.md Regel 8, git-workflow.md (Secret-Hygiene, Env-Schalter), OPERATING.md
   (Abschnitt um Zeile 592), `.gitignore`/`.gitignore.project`-Kommentar, CHANGELOG mit Migrationszeile.
   `@import`-Limit im Blick behalten (FACTORY.md ist importiert).

Umsetzungs-Notizen (/implement, 2026-11-02):
- Pipeline-Lauf brach am Turn-Limit ab; Stand lag als Zwischenstand-Commit `e767f17` vor und wurde
  manuell in Stage 2 fortgesetzt (Diff gegen die AK geprüft, kein Neustart). **Telemetrie-Lücke:** der
  manuelle Fortsatz hat keine OTEL-Telemetrie (Factory-ADR-049).
- Der Zwischenstand trug `skills.implement.max_turns: 40` in `factory.config.yml` – außerhalb des Scopes
  und rot gegen den Projekt-Test #348 (das Factory-Repo setzt keine `skills.*`-Knöpfe). Zurückgenommen;
  ein höheres Turn-Budget gehört in ein eigenes Issue.
- AK14 „Wert statt Liste": Regel 2 (unbekannte Keys) griff vor Regel 9 und meldete „unbekannter Key",
  weil eine leere Default-Liste nur `<pfad>.*` führt. Regel 2 meldet jetzt „ist keine Liste", wenn die
  Defaults an der Stelle eine Liste führen – gilt generisch, also auch für `labels.aspects_extra`.

## Offene Fragen
- [x] ADR-Trigger? → Nachtrag zu Factory-ADR-063 (E23–E27), kein neues ADR (`/architecture`, 2026-11-01).

## Review-Findings
<!-- Wird durch /review befüllt -->
- Iteration 1 (2026-11-02): **NEEDS_REWORK** – 0 kritisch, 1 wichtig, 6 Nitpicks
  ([`tasks/review-47.md`](review-47.md)).
  - W1: Nicht-String- und Steuerzeichen-Einträge entfallen in `start-work.sh` still (Filter in
    `factory_cfg_list`), ADR E24 und Spec F8 versprechen eine Warnung. Entweder warnen oder ADR und Spec angleichen.
  - Keine Out-of-Scope-Funde (kein Issue, kein `kleinfunde.md`-Eintrag).
  - Rework (2026-11-02): W1 nach Variante (a) behoben. `factory_cfg_list_dropped` zählt die verworfenen
    Elemente, `start-work.sh` warnt gesammelt („N Einträge … übersprungen"). Selbstfund dabei:
    `factory_cfg_list` lieferte bei einer Map statt Liste deren Werte als Einträge (`{x: lokal.conf}` hätte
    `lokal.conf` kopiert). Jetzt wird nur über `!!seq` iteriert, und leere Elemente entfallen ebenfalls
    (`$(…)` schnitt sie am Listenende still ab). Nitpicks erledigt: Warnung bei nicht lesbarer Liste
    (yq), eigene Task-ID 802 für AK8, Steuerzeichen in OPERATING.md. Offen (gitignoret, `rm` in dieser Session
    nicht freigegeben): `scripts/probe47.tmp.sh`, `scripts/review47.tmp.sh`,
    `tasks/telemetry-raw-47-*.tmp.txt`. Bewusst
    weitergereicht: F5-`mkdir`-Zweig → `/test`, Quell-Elternkette → `/security-review`.
    ADR E24 und Spec F8 sind angeglichen. Tests: 2331/0 (ausgeliefert), 145/0 (Projekt).

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/47-copy-files-konfigurierbar`
Erstellt: 2026-11-01 19:17
