# Task 47: copy-files-konfigurierbar

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [x] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [x] Codify ausgeführt
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
- [x] F9 – im Worktree nicht gitignoreter Eintrag wird nicht kopiert (Security-W1, Mutationsbeleg)

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
- Iteration 2 (2026-11-03): **APPROVED** – 0 kritisch, 0 wichtig, 4 Nitpicks
  ([`tasks/review-47.md`](review-47.md)). W1 ist behoben und selbst nachvollzogen.
  - Nitpicks: `copy_files: false`/`~` entfallen in `start-work.sh` ohne Warnung (das Gate lehnt sie ab). Die Pipe in
    `_factory_cfg_eval` hängt am `pipefail` des Aufrufers (vorbestehend). Die Warnung steht doppelt, für Singular und
    Plural (für `/refactor`). Die Wegwerf-Dateien (`scripts/*47*.tmp.sh`, `tasks/telemetry-raw-47-*.tmp.txt`) sind
    noch nicht gelöscht.
  - Keine Out-of-Scope-Funde (kein Issue, kein `kleinfunde.md`-Eintrag).
- Iteration 3 (2026-11-04, Nachlauf auf den Security-Rework `ce8f89e`): **APPROVED** – 0 kritisch, 0 wichtig,
  3 Nitpicks ([`tasks/review-47.md`](review-47.md)). Der Ignore-Guard ist fail-closed, F9 samt Mutationsbeleg trifft die
  Gefahr (`git status` im Worktree leer). Nitpicks: leere Elternordner bleiben bei einem nicht ignorierten verschachtelten
  Eintrag zurück (harmlos); CHANGELOG und OPERATING.md nennen den Ignore-Guard nicht; die Wegwerf-Dateien liegen noch im Baum.
  Suiten: 2343/0 (ausgeliefert), 145/0 (Projekt). Keine Out-of-Scope-Funde.

## Test-Notizen
- `/test` (2026-11-03): Alle AK1–AK18 und F1–F8 haben Tests (Abgleich Spec ↔ Testnamen). Keine neuen Tests nötig,
  kein Produktionscode geändert. Suiten: 2331/0 (ausgeliefert), 145/0 (Projekt). Der `mkdir`-Fehlerzweig in
  `ensure_parent_dirs` ist nach den davor liegenden Prüfungen praktisch nicht erreichbar und ohne Test geblieben.

## Refactoring-Notizen
- `/refactor` (2026-11-03): Die doppelte Warnung über verworfene `copy_files`-Einträge (Singular/Plural, Review-Nitpick)
  in `start-work.sh` ist zu einer Warnung mit Wortwahl `Eintrag`/`Einträge` zusammengefasst. Ausgabe unverändert,
  kein neues Verhalten. Suiten vorher und nachher: 2331/0 (ausgeliefert), 145/0 (Projekt).
  Bewusst unverändert: `copy_files: false`/`~` ohne Warnung in `start-work.sh` (das Gate lehnt sie ab, Verhaltensänderung)
  und die Pipe in `_factory_cfg_eval` (vorbestehend).

## Security-Notizen
- `/security-review` (2026-11-03): **PASSED** – 0 kritisch, 1 wichtig, mehrere Hinweise
  ([`tasks/security-47.md`](security-47.md)).
  - W1 (im Scope, vor dem Merge beheben): `copy_into_worktree` prüft nicht, ob der Eintrag im Worktree
    gitignoret ist. Ein nicht ignorierter gelisteter Secret-Pfad landet untracked im Worktree, und
    `factory-commit.sh` (`git add -A`) committet und pusht ihn im nächsten Pipeline-Schritt. Fix: vor dem `cp`
    `git -C "$WORKDIR" check-ignore -q -- "$entry"`, sonst warnen und überspringen, plus Test und ADR-E25/E26-/Spec-Satz.
    Repro R6 im Report. Selbst nachgeprüft: kein `check-ignore` in `start-work.sh`, `git add -A` in `factory-commit.sh`.
  - Hinweise: `echo -e` interpretiert Backslash-Sequenzen in Einträgen (nur Bildschirmausgabe, gleiche Funktion wie W1,
    mit beheben). Quellseitige Symlinks werden absichtlich verfolgt (im ADR benennen). Gate Regel 9 blockiert bei
    yq-Fehler, die Meldung ist missverständlich.
  - Keine Out-of-Scope-Funde (W1 und `echo -e` liegen in der im PR geänderten Funktion; kein Issue, kein
    `kleinfunde.md`-Eintrag). Wegwerf-Dateien `scripts/*47*.tmp.sh` und `tasks/telemetry-raw-47-*.tmp.txt` liegen noch im Baum.

## Codify-Notizen
- `/codify` (2026-11-03): zwei Lessons in `lessons/factory-workflow.md` (Ignore-Status im Ziel bei `git add -A`-Folgeprozess;
  `yq` `.[]` über Map) + Index-Zeilen, sechstes Wegwerf-Datei-Vorkommnis in `build-tooling`, `kleinfunde.md` um dritte
  `echo -e`-Fundstelle erweitert. Report: [`tasks/codify-47.md`](codify-47.md).
  **Offen: Security-W1 (`check-ignore`) ist noch nicht behoben** – Rework vor dem Merge nötig.

## Security-Rework (/implement, 2026-11-04)
- W1 behoben: `copy_into_worktree` prüft nach dem `-e`/`-L`-Guard `git -C "$WORKDIR" check-ignore -q -- "$entry"`;
  nicht ignoriert oder Git-Fehler → Warnung + Überspringen. Reihenfolge bewusst nach `ensure_parent_dirs`:
  `check-ignore` endet bei einem Symlink in der Elternkette mit rc 128 („beyond a symbolic link") und
  hätte die genauere F6-Meldung verdeckt; nach dem `-e`/`-L`-Guard, weil ein getracktes Ziel rc 1 liefert und
  sonst die AK4-Meldung verdeckt würde. `check-ignore` nimmt den Pfad wörtlich (`*`, Leerzeichen, `\`,
  `-rf.conf` per Sonde geprüft); `--literal-pathspecs` lehnt der Befehl ab (rc 128).
- `echo -e` → `printf '%s'` in `warn_copy` und der Erfolgszeile; `kleinfunde.md` entsprechend gekürzt.
- Tests: Fixture-Ignore-Muster im gemeinsamen `info/exclude` (kein Commit auf `main` der Fixture, am Gruppenende
  zurückgesetzt), F9 mit zwei Varianten (kein Muster / Muster nur in uncommitteter Quell-`.gitignore`),
  Mutationsbeleg nach Lesson Factory-Task #23, Backslash-Eintrag wörtlich in der Meldung.
  Suite: 2343/0 (ausgeliefert).
- Doku: ADR-063 E25 (Quellseite folgt Symlinks bewusst) und E26 (Ignore-Guard), Spec F9, `git-workflow.md`,
  `factory.defaults.yml`.
- Wegwerf-Sonde `scripts/probe47ci.tmp.sh` (gitignoret) blieb liegen – ihr Selbst-Lösch-Trap nutzte relatives
  `$0` nach einem `cd`; `rm` war nicht freigegeben. Telemetrie-Lücke: manueller Stage-2-Fortsatz ohne OTEL.
- Hinweis: der in diesem Rework geänderte Code lag nach `/security-review` und `/codify` – ein kurzer
  Nachlauf von `/review` bzw. `/security-review` auf den Rework-Diff ist vor dem Merge sinnvoll.

---
Branch: `feature/47-copy-files-konfigurierbar`
Erstellt: 2026-11-01 19:17

Blocker 2026-11-03: Pipeline pausiert – REVIEW_CONFLICT: Merge gestoppt: Security-W1 (tasks/security-47.md) ist offen – start-work.sh copy_into_worktree prueft nicht per git check-ignore, ob der Eintrag im Worktree gitignoret ist; factory-commit.sh (git add -A) wuerde einen nicht ignorierten Secret-Pfad committen und pushen. Rework (check-ignore + Test + ADR-E25/E26/Spec-Satz, echo -e) vor dem Merge noetig. CI ist gruen, PR bleibt Draft. (/architecture ausführen, dann Pipeline neu starten)
