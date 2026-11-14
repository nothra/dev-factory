# Task 44: lessons-index-ausliefern

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung

Der Index der Factory-Lessons wandert aus der Anpassungsstelle `docs/factory/PROJECT-CONTEXT.md` (wird nie
ausgeliefert) in ausgelieferte Factory-Dateien:

- **Übersicht** je Lesson-Datei mit „Laden bei"-Trigger in `docs/factory/FACTORY.md` (immer geladen),
- **Einzelzeilen** unverändert in die neue, nicht importierte `docs/factory/lessons/INDEX.md`.

`/codify` schreibt künftig dorthin (Patch). Außerdem misst der `@import`-Deckel zusätzlich Bytes, und der
Dauerkontext dieses Repos sinkt von 82.453 auf < 30.000 Bytes.

Spec (Volltext je AK, Entscheidungen E1–E5, Fehlerszenarien F1–F8):
[`docs/specs/spec-44-lessons-index-ausliefern.md`](../docs/specs/spec-44-lessons-index-ausliefern.md)

## Akzeptanzkriterien
<!-- Volltext je AK in der Spec; hier die Kurzform zum Abhaken -->
- [x] AK1 – `lessons/INDEX.md` enthält alle bisherigen Factory-Index-Zeilen zeichengleich (nur der Link in den 4 Kopfzeilen ist angepasst), Rekonstruktionsbeleg im PR-Body
- [x] AK2 – `INDEX.md` hat keine `### `-Überschriften
- [x] AK3 – `FACTORY.md` hat je Lesson-Datei eine Übersichtszeile mit `**Laden bei:**` + Verweis auf `lessons/INDEX.md`; `factory-workflow.md` trägt einen konkreten Trigger
- [x] AK4 – `INDEX.md` ist nicht Teil des `@import`-Sets
- [x] AK5 – `PROJECT-CONTEXT.md` dieses Repos ohne Factory-Index; „Bekannte Stolpersteine" bleibt als Verweis
- [x] AK6 – Guard in der ausgelieferten Suite (Übersichtszeile, INDEX-Gruppe, nicht Anpassungsstelle, INDEX-Link), je Teil ein Negativtest
- [x] AK7 – E2E: neue Lesson erreicht einen Fixture-Konsumenten per `factory-sync.sh` samt Trigger, Anpassungsstellen byte-gleich, mit Negativkontrolle
- [x] AK8 – `/codify` schreibt Factory-Index-Zeilen nach `INDEX.md` (+ Übersichtszeile bei neuer Datei), Projekt-Zeilen nach `PROJECT-CONTEXT.md` – als Patch geliefert, Mensch wendet an
- [x] AK9 – Assertions auf den neuen `/codify`-Wortlaut (Präsenz + Abwesenheit)
- [x] AK10 – kein Präsens-Verweis mehr auf den alten Index-Ort (Grep-Liste unten abgearbeitet)
- [x] AK11 – Nachträge in Factory-ADR-037 und Factory-ADR-047
- [x] AK12 – CHANGELOG `## Unreleased` mit Migrationshinweis
- [x] AK13 – Deckel summiert Bytes, Grenze inklusiv, Meldungen nennen beide Werte
- [x] AK14 – Bytezahl nicht ermittelbar → rot (fail-closed)
- [x] AK15 – beide Konstanten aus dem Kommentar nachgerechnet (Zeilen /50, Bytes /1000)
- [x] AK16 – Projekt-Suite: realer Stand unter beiden Grenzen
- [x] AK17 – Dauerkontext < 30.000 Bytes, vorher/nachher im PR-Body
- [x] AK18 – Kürzungen in `FACTORY.md` erhalten alle Test-Anker; entfernte Details stehen in `OPERATING.md`
- [x] AK19 – „Portabilität in Gate-/Shell-Skripten" zeichengleich nach `bash-gotchas.md` § 20 verschoben
- [x] AK20 – alle Gates grün (nach Apply des Patches)

## Technische Notizen

> Von `/requirements` vorbereitet, damit `/implement` mechanisch arbeiten kann. Reihenfolge einhalten:
> Inhalte zuerst (Schritte 1–6), dann messen und Konstanten setzen (7), dann Tests (8), dann Doku/ADR/CHANGELOG
> (9–10). Alle Befehle im Worktree `/Users/Ralf.Notheis/ws/dev-factory.worktrees/feature-44-lessons-index-ausliefern`.
> Wegwerf-Sonden **nur** in `$TMPDIR`, nie unter `scripts/` (Lesson `build-tooling.md`, 7. Vorkommnis).

### Vorab: Umfang und Fahrweise

- 20 AK, ein `.claude/**`-Patch, eine neue Testgruppe. Laut Lesson (Factory-Task #37, Turn-Limit 7. Vorkommnis)
  **nicht** über `run-pipeline.sh` fahren, sondern skillweise in getrennten Sessions (`/implement 44` in frischer Session).
- Turn-Budget bei Pipeline-Lauf wäre 60 (≥ 12 AK, Factory-ADR-065).
- Patch-Weg: `.claude/**` ist für Agenten gesperrt. Ergebnis ist `tasks/patch-44.diff`, angewendet vom Menschen.
  Die AK9-Assertions sind bis zum Apply rot → **lokal committen, Push zurückhalten**, Patch in einer Wegwerf-Kopie
  belegen (Lesson „Neuer Guard prüft Dateien, die nur per `.claude/**`-Patch änderbar sind", Factory-Task #45).
  Den Patch deshalb **früh** liefern (Schritt 4) und den Menschen um Apply bitten, bevor der erste Push nötig ist.

### Schritt 1 – Ausgangswerte festhalten

```bash
cd /Users/Ralf.Notheis/ws/dev-factory.worktrees/feature-44-lessons-index-ausliefern
bash scripts/checks/import-context-limit-check.sh               # erwartet: 794 von 1100 Zeilen
wc -c CLAUDE.md docs/factory/FACTORY.md docs/factory/PROJECT-CONTEXT.md \
      docs/factory/guidelines/{clean-code,tdd-principles,testing-standards}.md   # erwartet: 82453 total
```

Beide Werte in „Messwerte" unten eintragen.

### Schritt 2 – `docs/factory/lessons/INDEX.md` anlegen (AK1, AK2)

2.1 Quelle: `docs/factory/PROJECT-CONTEXT.md` ab der Zeile `#### Factory-Lessons (`docs/factory/lessons/`)`
(heute Z. 105) bis zum Dateiende. Darin stehen vier Gruppen, je eine Kopfzeile
`**[`lessons/<datei>.md`](lessons/<datei>.md)** – … · **Laden bei:** …` gefolgt von `- …`-Zeilen.

2.2 Neue Datei, exakt dieser Kopf (Leerzeile danach), dann die vier Gruppen in **unveränderter Reihenfolge**
(testing, build-tooling, code-style, factory-workflow), je Gruppe Kopfzeile + Leerzeile + Einzelzeilen + Leerzeile:

```markdown
# Factory-Lessons – Einzelliste

> **Besitzer: Factory** (`bash scripts/checks/ownership-check.sh --list factory`), wird ausgeliefert und ist
> **nicht** `@import`-geladen (Factory-ADR-037, Nachtrag #44). Die Übersicht je Lesson-Datei mit
> „Laden bei"-Trigger steht in `docs/factory/FACTORY.md` → „Bedarfsgesteuert laden". Diese Datei öffnen,
> sobald dort ein Trigger passt, und nur die passenden Einträge der Lesson lesen.
>
> Eine Zeile je Learning (Titel + Herkunft). `#<nr>` in den Herkunftsangaben bezeichnet Issues des
> Ursprungs-Repos (siehe `README.md` → Herkunft), „Factory-Task #<nr>" ein Issue dieses Factory-Repos.
> `/codify` hängt neue Zeilen ans Ende der Gruppe ihrer Lesson-Datei.
```

> Der Kopf nennt den Ursprungs-Repo-Namen bewusst **nicht** unqualifiziert (Konvention „Erlaubte Stellen für
> Herkunftsbegriffe", `PROJECT-CONTEXT.md`). Die Einzelzeilen enthalten ihn nur als `nothra/tch-gastro-services#<nr>`
> (geprüft beim Erstellen der Spec).

2.3 Einzige Änderung an den Kopfzeilen: das Link-**Ziel** (nicht der Anzeigetext) verliert das `lessons/`-Präfix,
weil `INDEX.md` selbst in `lessons/` liegt:
`**[`lessons/testing.md`](lessons/testing.md)**` → `**[`lessons/testing.md`](testing.md)**`. Keine `### `-Überschriften
(AK2).

2.4 Rekonstruktionsbeleg (einmalig, Sonde in `$TMPDIR`, Ergebnis in den PR-Body und unter „Messwerte"):

```bash
old="$(mktemp)"
git show origin/main:docs/factory/PROJECT-CONTEXT.md \
  | awk '/^#### Factory-Lessons/{f=1; next} f' | grep -v '^[[:space:]]*$' > "$old"
bad=0; n=0
while IFS= read -r l; do
  n=$((n + 1))
  case "$l" in '**[`lessons/'*) l="$(printf '%s' "$l" | sed -E 's#\]\(lessons/#](#')" ;; esac
  c="$(grep -cxF -- "$l" docs/factory/lessons/INDEX.md)"
  [ "$c" -ge 1 ] || { echo "✗ fehlt: $l" | cut -c1-120; bad=$((bad + 1)); }
done < "$old"
echo "geprüfte Zeilen: $n, fehlend: $bad"; rm -f "$old"
```

Erwartet: `fehlend: 0`. Zusätzlich muss `grep -c '' docs/factory/lessons/INDEX.md` minus Kopf und Leerzeilen der
Zahl `n` entsprechen (kein Zusatzinhalt).

### Schritt 3 – Übersicht in `FACTORY.md` (AK3, AK4) und `PROJECT-CONTEXT.md` (AK5)

3.1 In `docs/factory/FACTORY.md`, Abschnitt „Coding Guidelines": den Spiegelstrich
`> - Ausgelagerte `/codify`-Learnings (Stolpersteine, Volltext): `docs/factory/lessons/` – **nicht** … die passende Lesson bei Bedarf lesen`
(heute Z. 129–131) **ersetzen** durch:

```markdown
>
> **Factory-Lessons** (`/codify`-Learnings, Volltext, nicht @importiert – Factory-ADR-037):
>
> - [`lessons/testing.md`](lessons/testing.md) – Guard-/Gate-Tests für Skripte und Pipeline, Mutationsbelege, Fixtures, Test-Helfer · **Laden bei:** `/implement`, `/test`, `/review` beim Schreiben von Tests für Skripte/Gates/Pipeline
> - [`lessons/build-tooling.md`](lessons/build-tooling.md) – Wegwerf-/Debug-Artefakte und `.gitignore` · **Laden bei:** `/implement`, `/review` bei Wegwerf-Dateien und Ignore-Mustern
> - [`lessons/code-style.md`](lessons/code-style.md) – Clean-Code-Muster (Naming, Kommentar-Ort) · **Laden bei:** `/refactor`, `/review` (Clean-Code)
> - [`lessons/factory-workflow.md`](lessons/factory-workflow.md) – Git/CI, Pipeline-Skills, Patch-Workflow, Branch/Label, Review-Scope, kanonische Quellen, Blocker · **Laden bei:** jedem Skill bei Git-/Rebase-/CI-Arbeit, Pipeline-Abbruch oder Turn-Limit, `.claude/**`-Patch, ADR-/Spec-/Doku-Drift, Review-/Security-Review-Runden und Issue-/`kleinfunde.md`-Anlage
> - Einzelliste je Learning (Titel, Herkunft, bei `factory-workflow.md` ein Trigger je Eintrag):
>   [`lessons/INDEX.md`](lessons/INDEX.md). Projekt-Lessons: `docs/factory/PROJECT-CONTEXT.md` → „Bekannte Stolpersteine".
```

- Thema und Trigger der ersten drei Zeilen sind wörtlich aus den alten Kopfzeilen übernommen. Bei
  `factory-workflow.md` ist der Trigger neu (AK3), das Thema ohne „Terminologie-Sweep" gekürzt.
- Kein `@` in diesen Zeilen (AK4).

3.2 In derselben Datei, Blockquote-Kopf „Bedarfsgesteuert laden" (Z. 114): `im Format des Lessons-Index in
`docs/factory/PROJECT-CONTEXT.md`` → `im Format der Factory-Lessons-Übersicht unten`. (Die Kürzung dieses Blockquotes
erfolgt in M5, Schritt 5.)

3.3 `docs/factory/PROJECT-CONTEXT.md`: alles ab `## Bekannte Stolpersteine` bis Dateiende **ersetzen** durch:

```markdown
## Bekannte Stolpersteine

> Factory-Lessons: Übersicht mit „Laden bei"-Trigger in `docs/factory/FACTORY.md` → „Bedarfsgesteuert laden",
> Einzelliste in [`lessons/INDEX.md`](lessons/INDEX.md) (beides ausgeliefert, Factory-ADR-037 Nachtrag #44).
> Projekt-Lessons (`docs/project/lessons/`): dieses Repo hat keine. Legt `/codify` eine an, kommt hier eine Gruppe
> „Projekt-Lessons" mit „Laden bei"-Trigger am Gruppen-Header hinzu.
```

### Schritt 4 – `/codify`-Patch (AK8) – früh liefern

4.1 Wegwerf-Kopie der Datei in `$TMPDIR` bearbeiten. In `.claude/commands/codify.md` gelten diese Zielfassungen:

**„Kontext laden"** – die Zeilen zu `PROJECT-CONTEXT.md` und `lessons/` werden zu:

```markdown
- `docs/factory/PROJECT-CONTEXT.md` – Index der Projekt-Lessons + Kern-Kurzregeln
- `docs/factory/lessons/INDEX.md` – Einzelliste der Factory-Lessons (Übersicht je Datei: `docs/factory/FACTORY.md` → „Bedarfsgesteuert laden")
- `docs/factory/lessons/` (generisch) und `docs/project/lessons/` (projektspezifisch) – Volltext der
  ausgelagerten Stolperstein-Learnings (ADR-037)
```

**Schritt 2, dritter Spiegelstrich** wird zu:

```markdown
- Ist er eine Lesson → Volltext in `docs/factory/lessons/<thema>.md` **oder**
  `docs/project/lessons/<thema>.md` (Zuordnungsregel in Schritt 3) + eine Index-Zeile mit
  „Laden bei"-Trigger im Index der Seite (Factory: `docs/factory/lessons/INDEX.md`, Projekt: `PROJECT-CONTEXT.md`)?
```

**Schritt 3, „Neue Lesson"**: der Satzteil ab `**plus** eine **Index-Zeile** unter „Index der ausgelagerten Learnings“ in`
bis `in den @import-Volltext (ADR-037).` wird ersetzt durch:

```markdown
**plus** eine **Index-Zeile** im Index der Seite – **nicht** in den @import-Volltext (ADR-037, Nachtrag #44):

- **Factory-Lesson:** Zeile ans Ende der Gruppe ihrer Lesson-Datei in `docs/factory/lessons/INDEX.md`. Legst du eine
  **neue** Factory-Lesson-Datei an, zusätzlich eine Gruppe in `INDEX.md` **und** eine Übersichtszeile in
  `docs/factory/FACTORY.md` → „Bedarfsgesteuert laden" (Format der vorhandenen Zeilen). Factory-Index-Zeilen
  gehören **nie** nach `PROJECT-CONTEXT.md`: die Datei wird nicht ausgeliefert, der Trigger erreichte keinen Konsumenten.
- **Projekt-Lesson:** Zeile in `docs/factory/PROJECT-CONTEXT.md` → „Bekannte Stolpersteine", Gruppe „Projekt-Lessons"
  (neu angelegt: mit „Laden bei"-Trigger am Gruppen-Header).
```

Alles Übrige im Absatz bleibt, insbesondere die Phrasen `docs/factory/lessons/<thema>.md`,
`docs/project/lessons/<thema>.md`, `Zuordnungsregel` und `bash scripts/checks/ownership-check.sh --list factory`.
Diese Phrasen tragen die bestehenden Tests „#426 AK-C5" / „#27 AK4". Das Wort für die Ownership-Tabelle darf nicht
auftauchen (Test „#27 AK4").

4.2 Patch erzeugen: `diff -u .claude/commands/codify.md "$TMPDIR/codify.md"` mit den Pfadköpfen
`a/.claude/commands/codify.md` / `b/.claude/commands/codify.md`. Danach mit `git apply --check tasks/patch-44.diff`
in einer Wegwerf-Kopie des Worktrees belegen, als `tasks/patch-44.diff` committen und den Menschen um Apply bitten:
`git apply tasks/patch-44.diff` (danach `git rm tasks/patch-44.diff` im selben Commit wie die angewendete Datei;
toter Patch-Zweig entfernen, Lesson nothra/tch-gastro-services#432).

### Schritt 5 – Kürzungen bis < 30.000 Bytes (AK17–AK19)

5.1 **Anker-Liste zuerst.** Diese Phrasen erwarten Tests wörtlich in `FACTORY.md`. Sie bleiben unverändert und
jeweils auf **einer** Zeile (Lesson „`grep -qF` gegen Markdown-Prosa"):

| Test (Datei:Zeile ca.) | Phrase |
|---|---|
| run-tests.sh 8654 | Zeile 1 `# Development Factory · vX.Y.Z` |
| run-tests.sh 8648 | Überschriften `## Kernprinzip`, `## Nicht verhandelbare Prinzipien`, `## Pipeline-Übersicht`, `## Coding Guidelines`, `### Kern-Kurzregeln Git-Workflow (immer geladen)`, `## Agent-Rollen`, `## Work Tracking`, `## Guardrails`, `## Self-Improvement Loop` (zeilengleich) |
| run-tests.sh 7142, 8659 | `@docs/factory/guidelines/clean-code.md`, `…/tdd-principles.md`, `…/testing-standards.md` als eigene Zeilen |
| run-tests.sh 7131 | `guidelines/git-workflow.md`, `guidelines/architecture-principles.md`, `guidelines/bash-gotchas.md`, `guidelines/token-efficiency.md` (referenziert, **nicht** per `@`) |
| run-tests.sh 7161–7162 | `guidelines/git-workflow.md) – Branches, PR/Issue, Labels, Commits, Worktrees, Hook-Installation, Branch-Aufräumen · **Laden bei:**` und `guidelines/architecture-principles.md) – SOLID, Separation of Concerns, Dependency Rule, Fehlerbehandlung, API-Design · **Laden bei:**` |
| run-tests.sh 1214 | `bash-gotchas.md` |
| run-tests.sh 2434 | Zeile mit `8. **Nach dem Merge aufräumen:**`, die `start_work.copy_files` und `FACTORY_WT_SKIP_COPY=1` enthält |
| run-tests.sh 5010 | `scripts/install-hooks.sh`, `` `commit-msg`-Hook `` |
| run-tests.sh 5353 | `scripts/install-yq.sh` |
| run-tests.sh 5593–5600 | `Empfehlung (keine Pflicht): Für den `/implement`-Schritt einer Task eine neue Claude-Session öffnen`, `Kanonische Quelle für Regelfall und Grenze:`, `guidelines/git-workflow.md`; **abwesend:** `Jede neue Task in einer neuen Claude-Session starten` |
| run-tests.sh 6840–6843 | `läuft automatisch als Abschluss-Schritt`, `FACTORY_METRICS_ISSUE` |
| run-tests.sh 7958–7965 | `läuft seit nothra/tch-gastro-services#334 automatisch je Pipeline-Lauf`, `--no-telemetry`, `tasks/telemetry-<task-id>-<zeitstempel>.csv`; **abwesend:** `OTEL-Metriken (Token/Kosten/Nutzung pro Skill & Agent). Default aus` |
| run-tests.sh 7233–7243 | `nie aus dem Gedächtnis`, `„GitHub-Labels"`; **abwesend:** `Fund-Art`, `Im Zweifel Issue`, `beliebig viele Aspekt-Labels` |
| run-tests.sh 8550 (#27) | **abwesend:** Name der Ownership-Tabellendatei |

Vor dem Kürzen zur Sicherheit erneut sammeln:
`grep -n -E 'FACTORY\.md|FACTORY_MD|CLAUDE_MD|CLAUDE_FLAT' scripts/checks/tests/*.sh scripts/project/tests/run-tests.sh`.
Neue Treffer gegenüber der Tabelle ergänzen.

5.2 **Maßnahmen in dieser Reihenfolge**, nach jeder neu messen (`wc -c` wie Schritt 1):

- **M1** (Schritt 3.3) Index aus `PROJECT-CONTEXT.md` – ca. −47.300 Bytes.
- **M2** (Schritt 3.1) Übersicht in `FACTORY.md` – ca. +900 Bytes netto.
- **M3** `FACTORY.md` → „Pipeline-Übersicht": Die drei Absätze `**Messen (zwei Ebenen, Factory-ADR-006):**` (samt
  beider Unterpunkte), `**Nach dem Merge:**` und `**Async-Start (optional, Factory-ADR-008):**` **ersetzen** durch:

  ```markdown
  **Messen (Factory-ADR-006):** Prozess-Kennzahlen laufen automatisch als Abschluss-Schritt jedes
  `run-pipeline.sh`-Laufs (fail-open, Factory-ADR-045; manuell `/daily-metrics`, Veröffentlichung an `FACTORY_METRICS_ISSUE`).
  Telemetrie läuft seit nothra/tch-gastro-services#334 automatisch je Pipeline-Lauf (Factory-ADR-049, abschaltbar mit `--no-telemetry`),
  personenfrei nach `tasks/telemetry-<task-id>-<zeitstempel>.csv`. Details: `docs/factory/OPERATING.md` §0.5, §5.2.

  **Nach dem Merge:** `/post-merge-verify` prüft die deployte Umgebung (Factory-ADR-007, `OPERATING.md` §5.3).
  **Async-Start:** `scripts/factory-poll.sh` über das Label `factory::run`, Default aus (Factory-ADR-008, `OPERATING.md` §0.4).
  ```

  Vorher prüfen, dass `OPERATING.md` §0.4, §0.5, §5.2, §5.3 die entfallenden Details trägt (Budget-Guard,
  Concurrency, Tageskappe, `FACTORY_HEALTHCHECK_CMD`/`_URL`, `POST_MERGE_FAIL`, Commit der CSV zwischen `/codify` und
  `/pr-shepherd`, `config/otel.env.example`, stillgelegter `schedule`-Trigger). Fehlt etwas, dorthin verschieben
  (AK18) und in „Messwerte" notieren. Ca. −1.600 Bytes.
- **M4** `FACTORY.md` → „Guardrails": die ganze Spiegelstrich-Liste **ersetzen** durch:

  ```markdown
  - Nie committen ohne grünes `scripts/checks/pre-commit.sh`, nie pushen ohne grünes `scripts/checks/pre-push.sh`. Der Hook
    ist lokales Feedback; fail-closed schützt `main` allein das Ruleset `protect-main` ([Factory-ADR-029](../docs/factory/adr/029-branch-protection-main-ruleset.md)).
  - **Git-Hooks nur aus `bash scripts/install-hooks.sh`** ([Factory-ADR-042](../docs/factory/adr/042-hook-installation-single-source.md),
    idempotent, einmal je Clone): `pre-commit`, `pre-push` und der `commit-msg`-Hook (lehnt `--help`/`-h` als Message ab).
  - **`yq` kommt in CI nur aus `bash scripts/install-yq.sh`** (Version + SHA-256 gepinnt, fail-closed, nothra/tch-gastro-services#258) – kein
    eigener `wget`/`curl`-Block; dasselbe Muster für jedes weitere Fremd-Binary.
  - Keine offenen Checkboxen in der Task-Datei → kein Done. Letzte Checkbox und Abschluss-Notizen **vor dem Merge auf dem
    Feature-Branch** setzen – danach nur per neuem PR (nothra/tch-gastro-services#63).
  - **Der `@import`-Dauerkontext ist gedeckelt** (Zeilen und Bytes, `scripts/checks/import-context-limit-check.sh`,
    [Factory-ADR-047](../docs/factory/adr/047-import-kontext-guidelines-nach-erzwungenheit.md) §4; lokal, in CI nur mittelbar, nothra/tch-gastro-services#328).
    Neue Regeln verdichten oder als Lesson auslagern (`docs/factory/lessons/` + Zeile in `lessons/INDEX.md`), nicht anhängen.
  - Circuit Breaker: max. 3 Review↔Implement-Iterationen, dann eskalieren.
  - **Empfehlung (keine Pflicht): Für den `/implement`-Schritt einer Task eine neue Claude-Session öffnen**; `start-work.sh`
    und `/requirements` (ggf. `/architecture`) laufen im Regelfall in derselben Session. Kanonische Quelle für Regelfall und Grenze: `docs/factory/guidelines/git-workflow.md` → „Eine Task = Eine Session".
  - **Vor jeder neuen Task `bash scripts/start-work.sh`** – nie manuell branchen. Jede Task bekommt einen eigenen
    Worktree (parallele Sessions verschieben nie gegenseitig `HEAD`, nothra/tch-gastro-services#71); nach dem Merge `git worktree remove`.
  ```

  Achtung, die Anker-Phrase „Empfehlung … öffnen" und „Kanonische Quelle für Regelfall und Grenze:" je auf einer Zeile
  halten. Die oben gezeigten Umbrüche sind nur Darstellung, im Zweifel die ganze Phrase auf eine Zeile setzen.
  Ca. −2.200 Bytes.
- **M5** `FACTORY.md` → „Coding Guidelines": den Blockquote-Absatz `> **Bedarfsgesteuert laden statt `@import`
  (Factory-ADR-047).** … im Format …:` **ersetzen** durch:

  ```markdown
  > **Bedarfsgesteuert laden statt `@import` (Factory-ADR-047):** Was ein Gate erzwingt oder nur ein eng benennbarer
  > Adressatenkreis braucht, steht unten mit „Laden bei"-Trigger (Skill + Situation), im Format der
  > Factory-Lessons-Übersicht unten. Regeln, die jeden Schritt treffen, bleiben oben geladen oder stehen als Kern-Kurzregeln inline.
  ```

  Die vier Guideline-Spiegelstriche (git-workflow, architecture-principles, token-efficiency, bash-gotchas) bleiben
  **zeichengleich** (Anker 7161/7162). Ca. −400 Bytes.
- **M6** `FACTORY.md` → „Kern-Kurzregeln Git-Workflow": nur den einleitenden Blockquote (`> Die Regeln aus
  `git-workflow.md`, die **jeden** Pipeline-Schritt …`) **ersetzen** durch
  `> Die Regeln aus `git-workflow.md` (kanonische Quelle), die jeden Schritt treffen können (Factory-ADR-047 §3); Regel 7 verweist bewusst nur.`
  Regeln 1–8 bleiben **unverändert**. Ca. −400 Bytes.
- **M7** `docs/factory/guidelines/clean-code.md`: den Abschnitt `## Portabilität in Gate-/Shell-Skripten` bis
  Dateiende **ausschneiden**, in `docs/factory/guidelines/bash-gotchas.md` **vor** `## Querregel` als
  `## 20. Portabilität in Gate-/Shell-Skripten` einfügen. Der Rumpf bleibt zeichengleich, nur die Überschrift bekommt
  die Nummer. In `clean-code.md` an der Stelle einfügen:
  `## Portabilität in Gate-/Shell-Skripten` + Leerzeile +
  `Nur POSIX-Regex, Gate-Regex mit Positiv-/Negativtest, Fremdwerte als Daten (`--`, Integer-Guard): \`bash-gotchas.md\` § 20 (Laden bei: Shell-Skripte).`
  (Überschrift bleibt, damit Verweise auf „clean-code.md: Portabilität" nicht ins Leere gehen; Link relativ
  `[`bash-gotchas.md`](bash-gotchas.md)`.) Danach `git grep -n 'Portabilität in Gate' -- scripts docs` und jeden
  Kommentar mit „clean-code.md … Portabilität" auf `bash-gotchas.md § 20` umstellen (bekannt: `run-tests.sh` ~5536).
  Ca. −1.000 Bytes.
- **M8** `docs/factory/guidelines/testing-standards.md` Z. 10–11: `(`PROJECT-CONTEXT.md` → `lessons/testing.md`)` →
  `(`FACTORY.md` → Factory-Lessons → `lessons/testing.md`)`. Nahezu byte-neutral, Pflicht wegen AK10.
- **M9 – nur falls nach M1–M8 noch ≥ 30.000:** `FACTORY.md` → Blockquote `> **Zwei Phasen:** …` auf einen Satz
  kürzen: `> **Zwei Phasen:** Phase 1 ist immer interaktiv, Phase 2 kann vollautomatisch laufen – kanonisch: [`docs/factory/OPERATING.md`](OPERATING.md) → „Die zwei Phasen der Factory".`
- **Stopp (F8):** Liegt die Summe danach noch ≥ 30.000 Bytes, **nicht weiter kürzen**, sondern den Menschen fragen.

Erwartetes Ergebnis nach M1–M8 (Schätzung): ~29.200 Bytes.

### Schritt 6 – Deckel um Bytes erweitern (AK13, AK14)

In `scripts/checks/import-context-limit-check.sh`:

- Neue Konstante direkt unter `MAX_IMPORT_LINES`, gleicher Kommentarstil. Die Basiszeile muss vom Test gelesen
  werden können (siehe Schritt 7):
  ```bash
  # Obergrenze in Bytes (wc -c) für dasselbe Datei-Set – eine lange Zeile zählt sonst als eine (Factory-Issue #44).
  # Herleitung (ADR-047 §4): Ist-Stand nach Factory-Issue #44
  # = <B> Bytes; + 25 % Puffer = <B*1,25>; aufgerundet auf das nächste Vielfache von 1.000 = <MAX>.
  MAX_IMPORT_BYTES=<MAX>
  ```
- In der Schleife nach der Zeilenzählung: `bytes="$(wc -c < "./$rel" 2>/dev/null | tr -d '[:space:]')" || bytes=""`.
  Derselbe `case`-Integer-Guard wie bei `lines`, Meldung
  `"Bytezahl nicht ermittelbar: $rel (fail-closed)"`, `failed=1; continue`. Dann `total_bytes=$((total_bytes + bytes))`
  und `breakdown_bytes` analog zu `breakdown`.
- Nach dem bestehenden Zeilen-Vergleich ein zweiter Vergleich `"$total_bytes" -gt "$MAX_IMPORT_BYTES"` →
  `✗ @import-Dauerkontext zu groß: <b> Bytes (Grenze: <MAX>, ADR-047 §4)`, Byte-Beitragsliste (`sort -rn`), dieselben
  zwei Remediation-Zeilen (Text siehe unten), `exit 1`. Reihenfolge: erst Zeilen, dann Bytes. Bestehende Ausgaben bei
  Zeilen-Überschreitung bleiben **unverändert** (Tests parsen sie).
- Remediation-Zeile anpassen (AK10):
  `Beheben: verdichten oder auslagern (Volltext → docs/factory/lessons/ bzw. docs/project/lessons/, Index-Zeile in docs/factory/lessons/INDEX.md bzw. PROJECT-CONTEXT.md).`
  Bei beiden Überschreitungen gilt die Zeile „Grenze anheben …" mit `MAX_IMPORT_LINES` bzw. `MAX_IMPORT_BYTES`.
- Grün-Meldung: `✓ @import-Dauerkontext: $total von $MAX_IMPORT_LINES Zeilen, $total_bytes von $MAX_IMPORT_BYTES Bytes`.
  Vorher prüfen, ob ein Test die alte Grün-Meldung wörtlich erwartet
  (`grep -n 'von .*Zeilen' scripts/checks/tests/*.sh scripts/project/tests/run-tests.sh`), und dort nachziehen.
- Kopfkommentar: im Abschnitt „Bekannte Grenzen" einen Punkt „**Bytes:** `wc -c` zählt Bytes (UTF-8: Umlaut = 2);
  BSD-`wc` rückt die Zahl mit Leerzeichen ein, deshalb `tr -d` vor dem Integer-Guard" ergänzen. Zeile 3 des Kopfs:
  „Summiert die Zeilen und Bytes …".

### Schritt 7 – messen und Konstanten setzen (AK15, AK17)

```bash
bash scripts/checks/import-context-limit-check.sh      # Zeilen-Ist Z und Byte-Ist B ablesen
```

- `MAX_IMPORT_LINES`: Basis-Kommentar auf `# = <Z> Zeilen; + 25 % Puffer = …; aufgerundet auf das nächste Vielfache
  von 50 = <((Z*125/100)+49)/50*50>.` umschreiben. Format `# = <n> Zeilen` **beibehalten**, sonst liest der Test
  (`run-tests.sh` ~6877, `sed -n 's/^# = \([0-9]*\) Zeilen.*/\1/p'`) die Basis nicht. Die Herkunftsangabe
  („Ist-Stand direkt nach der Umstellung aus nothra/tch-gastro-services#319") auf „Ist-Stand nach Factory-Issue #44" ändern.
- `MAX_IMPORT_BYTES = ((B*125/100)+999)/1000*1000`.
- Beide Werte und die Summe vorher/nachher unter „Messwerte" eintragen.

### Schritt 8 – Tests

8.1 **Ausgelieferte Suite** `scripts/checks/tests/run-tests.sh`, Deckel-Abschnitt (#319, ab ~6870). Zwillingstests
für Bytes, jeweils mit eigenem Fixture (`mktemp -d`, eigene `CLAUDE.md`, `FACTORY_DIR=<fixture>`):

- Konstante lesbar: `sed -n 's/^MAX_IMPORT_BYTES=\([0-9]*\).*/\1/p'`. Basis lesbar: `sed -n 's/^# = \([0-9]*\) Bytes.*/\1/p'`.
  Rechenregel `((basis*125/100)+999)/1000*1000 == MAX` (AK15).
- Grenzwert: Fixture mit **genau** `MAX_IMPORT_BYTES` Bytes in **einer** Zeile → exit 0. Ein Byte mehr → exit 1,
  Ausgabe enthält `Bytes (Grenze:`. Erzeugen mit
  `awk -v n="$N" 'BEGIN { for (i = 1; i < n; i++) printf "x"; printf "\n" }' > CLAUDE.md` (n Bytes inkl. Newline).
  Wenige Zeilen, damit nur der Byte-Pfad greift (Lesson „Negativ-Test mit mehreren Fail-Pfaden isolieren"); zusätzlich
  `assert_absent` auf `Zeilen (Grenze:`.
- Fail-closed (AK14): `wc`-Stub im `PATH`, der (a) `exit 1` und (b) `echo abc` liefert → exit 1, Ausgabe enthält
  `Bytezahl nicht ermittelbar`. Achtung: der Stub darf `awk` nicht treffen. Stub-Verzeichnis nur mit `wc`.
- BSD-Polsterung (F4): `wc`-Stub, der `printf '     42\n'` ausgibt, bei einem Fixture unter der Grenze → exit 0
  (belegt das `tr -d`). Mutationsbeleg: dieselbe Assertion gegen eine Kopie des Skripts ohne `tr -d` → exit 1.
- Grün-Meldung nennt `Bytes`: `assert_contains_286 "$out" 'Bytes'` auf einem grünen Fixture.

8.2 **Ausgelieferte Suite**, neuer Abschnitt `# ─── Factory-Issue #44: Lessons-Index ausgeliefert ───` (am Ende vor
der Zusammenfassung), konsumenten-neutral (liest nur `FACTORY.md`, `lessons/*`, `customization-points.txt`, `codify.md`):

- Guard-Funktion `lessons_index_guard_44 <factory_md> <index_md> <lessons_dir> <customization_txt>` → gibt je Verstoß
  eine Zeile aus (`fehlt-uebersicht:<datei>`, `fehlt-gruppe:<datei>`, `toter-link:<ziel>`, `anpassungsstelle:<pfad>`,
  `fehlt-index-link`, `UNLESBAR:<pfad>`), Exit 1 bei Fund. Regeln:
  - Für jede `<lessons_dir>/*.md` außer `INDEX.md`: in `<factory_md>` eine Zeile mit `](lessons/<datei>)` **und**
    `**Laden bei:**` auf derselben Zeile; in `<index_md>` eine Zeile, die mit `` **[`lessons/<datei>`]( `` beginnt. Das
    Link-Ziel dieser Zeile existiert relativ zu `<lessons_dir>`.
  - `docs/factory/FACTORY.md` und `docs/factory/lessons/INDEX.md` stehen nicht als Zeile in `<customization_txt>`.
  - `<factory_md>` enthält `](lessons/INDEX.md)`.
  - `<factory_md>` enthält keine Zeile `^@docs/factory/lessons/INDEX\.md$` und kein Token `@docs/factory/lessons/INDEX.md` (AK4).
  - Jede unlesbare Quelle → `UNLESBAR:` (F5).
- Assertions: (1) echter Stand → kein Output, exit 0. (2) je Regel ein Negativtest gegen eine **Kopie** in `mktemp -d`
  (Übersichtszeile von `code-style.md` entfernen; Gruppe von `testing.md` aus INDEX-Kopie entfernen; Link-Ziel einer
  Gruppe auf `gibt-es-nicht.md`; `docs/factory/FACTORY.md` an die Kopie der customization-points anhängen; INDEX-Link
  entfernen; `@docs/factory/lessons/INDEX.md` als eigene Zeile anhängen; je Quelle eine unlesbare Variante) → jeweils
  das **pfadspezifische** Signal assertieren, nicht nur Exit 1 (Lesson nothra/tch-gastro-services#214).
  Scanner mit Exit 1 + `| grep -q` unter `pipefail` vermeiden: Ausgabe erst in Variable fangen (Lesson Factory-Task #27).
- AK2: `grep -c '^### ' docs/factory/lessons/INDEX.md` = 0.
- Umzug aus der Projekt-Suite (#319): „Coverage-Ausgabe nur in" hat eine Zeile in `docs/factory/lessons/INDEX.md`
  (Datei-`grep -qF`, kein `printf | grep` – Lesson SIGPIPE nothra/tch-gastro-services#426).
- AK9 (rot bis Patch-Apply): auf `flat_286 .claude/commands/codify.md`
  `assert_contains_286 … 'docs/factory/lessons/INDEX.md'`,
  `assert_contains_286 … 'Factory-Index-Zeilen gehören **nie** nach'`,
  `assert_absent … 'Index der ausgelagerten Learnings'`.
  Die Assertions an den bestehenden Block „#426 AK-C5" (~8460) anhängen.

8.3 **Neue Testgruppe** `scripts/checks/tests/factory-lock-44-tests.sh` (AK7). Wird über den Glob
`factory-lock-*-tests.sh` automatisch gestartet, Ownership über `scripts/checks/tests/**` (Seite factory, keine neue
OWNERSHIP-Zeile). Kopf und Rahmen 1:1 nach `factory-lock-24a-tests.sh`: Libs `assert-helpers test-groups
factory-lock-fixtures`, `HAS_YQ`-Skip, `factory_lock_setup`, am Ende `factory_lock_template_unchanged` und
`test_group_finish; exit $?`. Ablauf:

```text
world_23 l44
# Konsument C1: eigene Anpassungsstellen anlegen und committen, Fingerprint merken
printf '# Projekt-Regeln\n@docs/factory/FACTORY.md\n' > "$C1_23/CLAUDE.md"
mkdir -p "$C1_23/docs/factory"; printf '# Projekt-Kontext\n' > "$C1_23/docs/factory/PROJECT-CONTEXT.md"
git -C "$C1_23" add -A && git_23 -C "$C1_23" commit -q -m kontext
sha_claude=$(shasum -a 256 < "$C1_23/CLAUDE.md"); sha_pc=$(shasum … PROJECT-CONTEXT.md)
# Upstream-Release v4.0.0 aus den ECHTEN Factory-Dateien + neuer Lesson
mkdir -p "$U23/docs/factory/lessons"
sed '1s/.*/# Development Factory · v4.0.0/' "$FACTORY_ROOT/docs/factory/FACTORY.md" > "$U23/docs/factory/FACTORY.md"
cp "$FACTORY_ROOT"/docs/factory/lessons/*.md "$U23/docs/factory/lessons/"
printf '### Neue Lesson 44\n\ntext\n' > "$U23/docs/factory/lessons/neu-44.md"
# Übersichtszeile: nach der Zeile mit ](lessons/factory-workflow.md) einfügen (awk), Format wie die übrigen:
#   > - [`lessons/neu-44.md`](lessons/neu-44.md) – Testthema 44 · **Laden bei:** /implement bei Fall 44
# INDEX-Gruppe anhängen: \n**[`lessons/neu-44.md`](neu-44.md)** – Testthema 44 · **Laden bei:** …\n\n- Neue Lesson 44 (aus Fixture)\n
git -C "$U23" add -A && git_23 -C "$U23" commit -q -m v4 && git -C "$U23" tag v4.0.0
mk_manifest_23 "$U23" v4.0.0 "$R23/v4.0.0/factory-release.json"
out=$(sync_23 "$C1_23" v4.0.0); rc=$?
```

Assertions:
- `rc == 0`.
- `cmp` von `neu-44.md` und `INDEX.md` zwischen U23 und C1.
- In `$C1_23/docs/factory/FACTORY.md` eine Zeile mit `](lessons/neu-44.md)` und `**Laden bei:**`.
- `lessons_index_guard_44` aus 8.2 grün gegen C1. Dazu die Funktion in `lib/assert-helpers.sh` legen, damit beide
  Dateien sie nutzen; sie ist konsumenten-neutral.
- SHA von `CLAUDE.md` und `PROJECT-CONTEXT.md` in C1 unverändert.

Negativkontrolle (zweite Welt `world_23 l44n`): wie oben, aber Übersichtszeile und INDEX-Gruppe **nicht** schreiben,
stattdessen die Zeile in eine Upstream-`docs/factory/PROJECT-CONTEXT.md` legen. Nach dem Sync meldet der Guard gegen C1
`fehlt-uebersicht:neu-44.md`, und die Konsumenten-`PROJECT-CONTEXT.md` ist unverändert. Damit ist belegt, dass der alte
Weg den Trigger nicht ausliefert. Falls das Manifest/Sync eine `PROJECT-CONTEXT.md` im Upstream ablehnt oder
überspringt, genügt die Assertion „Guard meldet fehlt-uebersicht" plus „Konsumenten-Datei unverändert".

Vorher die Zeilen um `add_release_24` und `mk_manifest_23` lesen: Versionszeile von FACTORY.md == Tag ist Pflicht
(Gate AK2.1a). Kein Netz: `env_23` lenkt um.

8.4 **Projekt-Suite** `scripts/project/tests/run-tests.sh`:

- Block „verschoben aus der ausgelieferten Suite: #319: Index-Zeile „Coverage-Ausgabe nur in" in PROJECT-CONTEXT.md"
  (~216) **löschen**, er lebt jetzt in 8.2.
- Block „#426 AK-C3: Index in PROJECT-CONTEXT.md …" (~298–316) **löschen**, ersetzt durch den Guard in 8.2. Als
  Ersatz-Assertion in der Projekt-Suite: `PROJECT-CONTEXT.md` enthält **nicht** `#### Factory-Lessons` (AK5),
  Datei-`grep`.
- Kommentar am Block „#319 AC4" (~222–225): „der Lessons-Index …" → „PROJECT-CONTEXT.md (Projekt-Gedächtnis inkl.
  Index der Projekt-Lessons)". Test bleibt.
- Realstand-Test (Factory-Issue #32, ~348): zusätzlich zur Zeilen- auch die Byte-Grenze, d. h. Exit 0 des Checks
  gegen die echte Wurzel deckt beides ab. Assertion-Label um „Zeilen und Bytes" ergänzen, Breakdown bei Rot wie gehabt
  ausgeben (AK16).
- `ic_dead_links_319`-Dateiliste: `docs/factory/lessons/INDEX.md` ergänzen.

8.5 Lauf: `bash scripts/checks/tests/run-tests.sh` und `bash scripts/project/tests/run-tests.sh`. Laufende Suite nicht
editieren (Lesson nothra/tch-gastro-services#431). Bei unerwartetem Rot eines Content-Scan-Guards zuerst
`git status --ignored` (Lesson nothra/tch-gastro-services#312).

### Schritt 9 – Doku-Sweep (AK10)

```bash
git grep -n -E 'Index-Zeile|Lessons-Index|Index der ausgelagerten|Index der Stolpersteine|Stolpersteine' \
  -- ':!tasks' ':!docs/specs' ':!docs/factory/lessons/INDEX.md'
```

Bekannte Treffer und Soll (Stand Spec-Erstellung):

| Fundstelle | Aktion |
|---|---|
| `.claude/commands/codify.md` 13, 31, 43–46 | Patch (Schritt 4) |
| `docs/factory/FACTORY.md` 114, 129–131, 204 | Schritte 3.1, 3.2, M4 |
| `docs/factory/OPERATING.md` 347 | `Learnings → Regeln in `CLAUDE.md`/`PROJECT-CONTEXT.md`/Guidelines` → `Learnings → Regeln in `CLAUDE.md`/Guidelines, Lessons + `lessons/INDEX.md` (Projekt: `PROJECT-CONTEXT.md`)` |
| `docs/factory/OPERATING.md` 459–470 | „+ Index-Zeile in `docs/factory/PROJECT-CONTEXT.md`" → „+ Index-Zeile in `docs/factory/lessons/INDEX.md` (generisch) bzw. `docs/factory/PROJECT-CONTEXT.md` (projektspezifisch)", an beiden Stellen |
| `docs/factory/guidelines/token-efficiency.md` 88–89 | „plus eine Index-Zeile in `PROJECT-CONTEXT.md` (ADR-037)" → „plus eine Index-Zeile in `docs/factory/lessons/INDEX.md` bzw. `PROJECT-CONTEXT.md` (ADR-037, Nachtrag #44)" |
| `docs/factory/guidelines/testing-standards.md` 10–11 | M8 |
| `scripts/checks/import-context-limit-check.sh` 219 | Schritt 6 |
| `scripts/project/tests/run-tests.sh` 224, 303 | Schritt 8.4 |
| ADR-037 44/58, ADR-047 61/77/107, ADR-063 33 | Entscheidungstext – **nicht** ändern, Nachtrag (Schritt 10) |
| `scripts/checks/import-context-limit-check.sh` 7, `scripts/checks/pre-push.sh` 113, `docs/factory/lessons/factory-workflow.md` 1506 | historisch (Vorfall „~80 auf 341 Zeilen") – unverändert |
| `docs/factory/guidelines/git-workflow.md` 174 | betrifft Labels, nicht Lessons – unverändert |

Neue Treffer einordnen und die Tabelle hier ergänzen. Zusätzlich `git grep -n 'README' README.md` prüfen, ob das
README des Repos den Index-Ort nennt. Falls ja, nachziehen (README ist Seite `project`).

### Schritt 10 – ADR-Nachträge und CHANGELOG (AK11, AK12)

**Factory-ADR-037**, am Ende anfügen:

```markdown
## Nachtrag 2026-11-<TT> (#44): Index ausgeliefert, zweistufig

Der Index stand in `PROJECT-CONTEXT.md`, einer Anpassungsstelle, die nie ausgeliefert wird. Factory-Lessons kamen
deshalb ohne „Laden bei"-Trigger beim Konsumenten an. Neu: (1) Übersicht je Lesson-Datei mit Trigger in
`docs/factory/FACTORY.md` → „Bedarfsgesteuert laden" (Dauerkontext); (2) die Einzelzeilen unverändert in
`docs/factory/lessons/INDEX.md` (ausgeliefert, nicht `@import`-geladen). `/codify` schreibt Factory-Zeilen dorthin,
Projekt-Zeilen weiter nach `PROJECT-CONTEXT.md`. Entscheidung 2 und 3 oben gelten mit diesem Ort. Abgesichert durch
einen Guard in der ausgelieferten Suite und einen E2E-Test über `factory-sync.sh` (Spec 44).
```

**Factory-ADR-047**, am Ende anfügen:

```markdown
## Nachtrag 2026-11-<TT> (#44): Bytes als zweite Messgröße, Portabilität ausgelagert

- **§4:** Der Deckel misst zusätzlich Bytes (`MAX_IMPORT_BYTES`, gleiche Herleitung: Ist + 25 %, aufgerundet auf
  1.000). Die Zeilenzahl allein maß den Token-Bedarf nicht: der Lessons-Index lag mit 145 Zeilen bei 47 KB. Beide
  Grenzen wurden am Stand nach #44 neu hergeleitet (<Z> Zeilen / <B> Bytes).
- **§3:** Das Trigger-Format verweist auf die Factory-Lessons-Übersicht in `FACTORY.md` statt auf `PROJECT-CONTEXT.md`.
- **§2:** „Portabilität in Gate-/Shell-Skripten" wandert aus `clean-code.md` nach `bash-gotchas.md` § 20. Die
  Regeln betreffen nur Shell-Skripte, also genau den Adressatenkreis, den der „Laden bei"-Trigger von
  `bash-gotchas.md` schon benennt (§2, zweite Klausel).
```

**CHANGELOG.md**, unter `## Unreleased` → `### Geändert` **oben** einfügen:

```markdown
- **Factory-Lessons-Index ausgeliefert (Factory-ADR-037/047 Nachtrag, #44):** Der Index der Factory-Lessons steht nicht
  mehr in `docs/factory/PROJECT-CONTEXT.md` (Anpassungsstelle, wurde nie ausgeliefert), sondern zweistufig in
  ausgelieferten Dateien: Übersicht je Lesson-Datei mit „Laden bei"-Trigger in `docs/factory/FACTORY.md`, Einzelzeilen in
  der neuen `docs/factory/lessons/INDEX.md` (nicht `@import`-geladen). `/codify` schreibt dorthin. Der
  `@import`-Deckel misst zusätzlich Bytes (`MAX_IMPORT_BYTES`), beide Grenzen neu hergeleitet. „Portabilität in
  Gate-/Shell-Skripten" steht jetzt in `bash-gotchas.md` § 20. **Migration:** Den Abschnitt `#### Factory-Lessons` samt
  Einzelzeilen aus dem eigenen `docs/factory/PROJECT-CONTEXT.md` entfernen; Projekt-Lessons bleiben dort.
```

### Schritt 11 – Abschluss `/implement`

- Gates: `bash scripts/checks/pre-commit.sh`, `bash scripts/checks/pre-push.sh` (nach Patch-Apply),
  `git ls-files -z '*.sh' | xargs -0 -n1 bash -n`, `bash scripts/checks/ownership-check.sh`.
- PR-Body (`gh pr edit 57 --body …`, Lesson nothra/tch-gastro-services#233) enthält: Messwerte vorher/nachher
  mit Aufschlüsselung, Rekonstruktionsbeleg (Schritt 2.4), Hinweis auf den Patch, `Closes #44`.
- Wegwerf-Dateien in `$TMPDIR` löschen, `git status` sauber.

### Messwerte
<!-- von /implement befüllen -->
- Vorher: 794 Zeilen, 82.453 Bytes (CLAUDE.md 1.159 · FACTORY.md 16.451 · PROJECT-CONTEXT.md 53.154 · clean-code 5.118 · tdd 1.950 · testing-standards 4.621)
- Rekonstruktion (Schritt 2.4): geprüfte Zeilen 131, fehlend 0; INDEX ohne Kopf 131 Zeilen, 0 `### `-Überschriften
- Nach M1–M9 (F8): 30.111 Bytes, 577 Zeilen – 111 Bytes über AK17. Entscheidung F8 (Mensch): Variante 1, weiter kürzen in `FACTORY.md`
  (Satz „Skills sind für beide Stufen designed …" entfernt, zwei Pfadangaben gekürzt)
- Nachher: 575 Zeilen, 29.994 Bytes → `MAX_IMPORT_LINES` = 750 (575 + 25 % = 718, auf 50 gerundet), `MAX_IMPORT_BYTES` = 38.000 (29.994 + 25 % = 37.492, auf 1.000 gerundet)
- Doku-Sweep (Schritt 9): `OPERATING.md` (Zeile 347, 460, 469) und `token-efficiency.md` nachgezogen; `README.md` nennt den Index-Ort nicht
- Negativkontrolle AK7: der Sync lehnt eine Upstream-`PROJECT-CONTEXT.md` als geschützte Stelle ab; der Guard prüft dann den Upstream-Stand (Signal `fehlt-uebersicht`)

## Offene Fragen
- [ ] (für `/architecture`, optional) Nachträge statt neuem ADR (Spec E5). Ohne Einwand gilt E5, dann ist `/architecture` nicht nötig.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/44-lessons-index-ausliefern`
Erstellt: 2026-11-13 20:11
