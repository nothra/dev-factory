# Spec: Factory-Lessons-Index ausliefern und Dauerkontext verkleinern (#44)

## Kontext

Der Index der **Factory**-Lessons steht heute in `docs/factory/PROJECT-CONTEXT.md` (Abschnitt
„Bekannte Stolpersteine" → „Index der ausgelagerten Learnings", Gruppe „Factory-Lessons"). Diese Datei
ist eine **Anpassungsstelle** (Seite `project`, `scripts/checks/customization-points.txt`) und wird bei
einem Update nie ausgeliefert. `/codify` schreibt die Index-Zeile neuer Factory-Lessons trotzdem dorthin
(`.claude/commands/codify.md`, Schritt 3 „Neue Lesson").

**Folge 1 – Auslieferungsfehler:** Eine im Factory-Repo entstandene Lesson kommt beim Konsumenten zwar als
Datei unter `docs/factory/lessons/` an (Glob `docs/factory/lessons/**` ist Seite `factory`), ihr
„Laden bei"-Trigger aber nicht – kein Skill im Konsumenten lädt sie. Beleg (Issue, Stand 2026-11-01): die
Index-Zeilen der Factory-Tasks #22, #23, #24, #27, #32 stehen nur im `PROJECT-CONTEXT.md` dieses Repos.

**Folge 2 – Dauerkontext:** Der Index ist der größte Posten im `@import`-Dauerkontext. Messung am
Stand `22e6cac` (`wc -c`):

| Datei | Bytes | davon Index |
|-------|------:|------:|
| `CLAUDE.md` | 1.159 | – |
| `docs/factory/FACTORY.md` | 16.451 | – |
| `docs/factory/PROJECT-CONTEXT.md` | 53.154 | ~47.660 (Zeile 100 bis Dateiende) |
| `docs/factory/guidelines/clean-code.md` | 5.118 | – |
| `docs/factory/guidelines/tdd-principles.md` | 1.950 | – |
| `docs/factory/guidelines/testing-standards.md` | 4.621 | – |
| **Summe** | **82.453** | |

`scripts/checks/import-context-limit-check.sh` zählt nur **Zeilen** (794 von 1.100). Eine lange Zeile
zählt als eine, der Deckel misst den Token-Bedarf also nicht.

**Warum jetzt:** Die Änderung betrifft den Konsumenten-Vertrag. Sie muss vor der Reintegration landen
(vor `nothra/tch-gastro-services#441`, spätestens mit `nothra/tch-gastro-services#428`). Danach müsste
jeder Konsument sein `PROJECT-CONTEXT.md` von Hand umbauen.

## Entscheidungen (Mensch, 2026-11-13)

- **E1 – Zweistufiger Index:**
  - **Stufe 1 (immer geladen):** Eine **Übersicht** in `FACTORY.md` mit einer Zeile je Lesson-Datei
    (Link, Thema, „Laden bei"-Trigger).
  - **Stufe 2 (bei Bedarf gelesen):** die **Einzelzeilen** je Learning, **unverändert** verschoben in
    die neue, **nicht** `@import`-geladene Datei `docs/factory/lessons/INDEX.md`, samt Vorfallketten.
    Kein Umschreiben, kein Kürzen.
- **E2 – Größenziel < 30.000 Bytes:** Der gemessene `@import`-Dauerkontext dieses Repos liegt am Ende
  unter 30.000 Bytes (`wc -c`-Summe über CLAUDE.md und alle importierten Dateien). Dafür werden über
  den Index hinaus Kürzungen in `FACTORY.md` und eine Verlagerung aus `clean-code.md` nötig (Maßnahmen
  M3–M8 unten).
- **E3 – Deckel misst Zeilen und Bytes:**
  - `import-context-limit-check.sh` prüft zusätzlich eine **Byte-Grenze**. Beide Grenzen sind fail-closed.
  - Beide Grenzen werden nach der Regel aus Factory-ADR-047 §4 **neu hergeleitet**: Ist-Stand nach der
    Umstellung + 25 % Puffer, aufgerundet; Zeilen auf das nächste Vielfache von 50, Bytes auf das
    nächste Vielfache von 1.000.
- **E4 – Migration nur per CHANGELOG:** ein Migrationshinweis im Abschnitt `## Unreleased`. Kein neuer
  Check, keine automatische Migration.
- **E5 – ADR (Vorschlag Requirements, `/architecture` darf abweichen):** kein neuer ADR. Stattdessen
  datierte **Nachträge**:
  - in Factory-ADR-037 (Ort und Form des Index),
  - in Factory-ADR-047 (§2: Verlagerung „Portabilität", §3: Format-Verweis, §4: Byte-Grenze).

  Begründung: Die Mechanik beider ADRs bleibt bestehen. Es ändern sich nur der Ablageort, das Format
  und die Messgröße. Das ist dasselbe Muster wie die Nachträge in Factory-ADR-063.

## Scope

**Inbegriffen:**

1. Neue Datei `docs/factory/lessons/INDEX.md` (Seite `factory`, über den bestehenden Glob
   `docs/factory/lessons/**` abgedeckt) mit den unverändert verschobenen Einzelzeilen.
2. Lessons-Übersicht (Stufe 1) in `docs/factory/FACTORY.md`, Abschnitt „Coding Guidelines" →
   „Bedarfsgesteuert laden".
3. `docs/factory/PROJECT-CONTEXT.md` dieses Repos: Der Factory-Index entfällt. Der Abschnitt „Bekannte
   Stolpersteine" bleibt als kurzer Platzhalter für Projekt-Lessons, mit Verweis auf die Factory-Übersicht.
4. `/codify` (`.claude/commands/codify.md`, **Patch-Workflow**): Factory-Lessons kommen nach `INDEX.md`
   (+ Übersichtszeile in `FACTORY.md` bei neuer Lesson-Datei), Projekt-Lessons nach `PROJECT-CONTEXT.md`.
5. Alle Doku-Stellen, die den Index-Ort im Präsens beschreiben (Liste unter „Betroffene Dateien").
6. Deckel: Byte-Messung, neu hergeleitete Grenzen und Tests.
7. Kürzungen M3–M8 bis unter 30.000 Bytes.
8. Tests:
   - Guard „jede Lesson-Datei hat Übersichtszeile + INDEX-Gruppe" in der **ausgelieferten** Suite.
   - E2E-Test „neue Lesson erreicht Konsumenten per `factory-sync.sh`" gegen ein Fixture-Repo.
   - Umzug der Index-Tests aus der Projekt-Suite.
9. CHANGELOG-Eintrag mit Migrationshinweis; Nachträge in Factory-ADR-037/047.

**Nicht inbegriffen:**

- Vorfallketten in den Index-Zeilen kürzen oder umformulieren (E1: verbatim).
- `factory-workflow.md` thematisch aufteilen oder Lesson-Volltexte ändern.
- Änderungen an `tdd-principles.md` und `testing-standards.md`. Ausnahme: der eine Verweissatz in
  `testing-standards.md` Z. 10–11, der den Index-Ort nennt.
- Ein Check im Konsumenten, der einen veralteten Factory-Abschnitt in dessen `PROJECT-CONTEXT.md` erkennt (E4).
- Änderungen an den Erkennungsregeln des Deckels (Referenz-Zeile/Inline-Referenz, Confinement, Zyklen).
- Ein eigener CI-Job für den Deckel (Zuständigkeit `nothra/tch-gastro-services#328`).
- Änderungen in `nothra/tch-gastro-services`.
- Der Weg einer in einem **Konsumenten** entstandenen Factory-Lesson zurück ins Factory-Repo
  (`lesson-vorschlag`, `nothra/tch-gastro-services#441`). Dieser Task regelt nur, wohin `/codify` im
  Factory-Repo schreibt und wie das Ergebnis ausgeliefert wird.
- Versionszeile in `FACTORY.md` (setzt der Release-PR).

## Akzeptanzkriterien

### A – Index ausgeliefert

- [ ] **AK1** – GIVEN der Stand nach dem PR
  WHEN man `docs/factory/lessons/INDEX.md` öffnet
  THEN enthält die Datei je Factory-Lesson-Datei (`build-tooling.md`, `code-style.md`,
  `factory-workflow.md`, `testing.md`) eine Gruppe. Die Gruppe beginnt mit der bisherigen
  Gruppen-Kopfzeile, der Link ist auf den neuen Ort umgeschrieben (`(testing.md)` statt
  `(lessons/testing.md)`). Darunter stehen alle Einzelzeilen dieser Gruppe aus dem bisherigen Index,
  **zeichengleich** und in derselben Reihenfolge.
  *Beleg: einmaliger Rekonstruktionslauf (Task-Datei, Schritt 2.4). Jede nicht-leere Zeile des alten
  Abschnitts ab `#### Factory-Lessons` kommt in `INDEX.md` genau einmal vor; Ausnahme sind nur die
  vier Kopfzeilen mit geändertem Link. Ergebnis mit Zahlen im PR-Body.*
- [ ] **AK2** – GIVEN `docs/factory/lessons/INDEX.md`
  WHEN man nach Überschriften der Form `### ` sucht
  THEN gibt es keine. Die Datei nutzt nur `#` und `##`, damit keine Prüfung, die Lesson-Überschriften
  (`### `) zählt, sie als Lesson missversteht.
- [ ] **AK3** – GIVEN `docs/factory/FACTORY.md`
  WHEN man den Block „Bedarfsgesteuert laden" liest
  THEN steht dort je Factory-Lesson-Datei genau eine Übersichtszeile
  `[`lessons/<datei>.md`](lessons/<datei>.md) – <Thema> · **Laden bei:** <Trigger>` und eine Zeile,
  die auf [`lessons/INDEX.md`](lessons/INDEX.md) als Einzelliste verweist.
  Die Übersichtszeile von `factory-workflow.md` trägt einen **konkreten** Trigger (Wortlaut in der
  Task-Datei, Schritt 3.2), nicht „je Eintrag unterschiedlich".
- [ ] **AK4** – GIVEN `docs/factory/FACTORY.md`
  WHEN der Deckel die Imports auflöst
  THEN ist `docs/factory/lessons/INDEX.md` **nicht** Teil des `@import`-Sets: keine Referenz-Zeile
  `@docs/factory/lessons/INDEX.md`, kein `@`-Token, das auf die Datei auflöst.
- [ ] **AK5** – GIVEN dieses Repo
  WHEN man `docs/factory/PROJECT-CONTEXT.md` liest
  THEN fehlen die Überschriften `### Index der ausgelagerten Learnings` und
  `#### Factory-Lessons`, und keine Zeile verweist mehr auf eine Datei unter `lessons/` als
  Index-Gruppe. Der Abschnitt `## Bekannte Stolpersteine` existiert weiter. Er verweist auf die
  Factory-Übersicht in `FACTORY.md` und hält fest, dass dieses Repo keine Projekt-Lessons hat.
- [ ] **AK6** – GIVEN die **ausgelieferte** Suite (`scripts/checks/tests/run-tests.sh`)
  WHEN sie läuft
  THEN prüft ein Guard für jede Datei `docs/factory/lessons/*.md` außer `INDEX.md`:
  - (a) Es gibt eine Übersichtszeile in `FACTORY.md` mit `**Laden bei:**`.
  - (b) Es gibt eine Gruppen-Kopfzeile in `INDEX.md`, deren Link auf eine existierende Datei zeigt.

  Zusätzlich prüft er:
  - (c) `FACTORY.md` und `INDEX.md` stehen **nicht** in `scripts/checks/customization-points.txt`.
  - (d) Der Link auf `lessons/INDEX.md` steht in `FACTORY.md`.

  Jeder Teil hat einen eigenen Negativtest per Mutation an einer Kopie (Übersichtszeile entfernen,
  Gruppe entfernen, Eintrag in einer Kopie der customization-points ergänzen, Link entfernen). Die
  Suite liest dafür nur Dateien der Seite `factory` (Konsumenten-Neutralität, Factory-ADR-064 D6).
- [ ] **AK7** – GIVEN ein Fixture-Konsument (`world_23`, Stand nach Abholung von v1.0.0) mit eigener
  `CLAUDE.md` und eigenem `docs/factory/PROJECT-CONTEXT.md`, und ein Fixture-Release v4.0.0. Das
  Release enthält:
  - die **echte** `FACTORY.md` dieses Stands (nur die Versionszeile ersetzt),
  - die **echten** Dateien unter `docs/factory/lessons/`,
  - eine neue Lesson-Datei `docs/factory/lessons/neu-44.md` samt Übersichtszeile in `FACTORY.md` und
    Gruppe in `INDEX.md`.

  WHEN `factory-sync.sh v4.0.0` im Konsumenten läuft
  THEN ist der Lauf grün, `neu-44.md` und `INDEX.md` liegen byte-gleich im Konsumenten, die
  Übersichtszeile für `neu-44.md` mit `**Laden bei:**` steht in dessen `FACTORY.md`, und `CLAUDE.md`
  und `PROJECT-CONTEXT.md` des Konsumenten sind byte-gleich wie vorher.
  *Negativkontrolle im selben Test:* ein zweites Release, das die neue Index-Zeile **nur** in eine
  `PROJECT-CONTEXT.md` des Upstream schreibt, liefert den Trigger nicht aus. Die Assertion „Trigger im
  Konsumenten vorhanden" ist dort rot; der Test erwartet genau das.

### B – `/codify` schreibt an den neuen Ort

- [ ] **AK8** – GIVEN `.claude/commands/codify.md` nach Anwenden von `tasks/patch-44.diff`
  WHEN man den Schritt „Neue Lesson" liest
  THEN steht dort:
  - Index-Zeile einer Factory-Lesson → `docs/factory/lessons/INDEX.md` (Gruppe der Datei),
  - neue Factory-Lesson-Datei → zusätzlich eine Gruppe in `INDEX.md` **und** eine Übersichtszeile in
    `FACTORY.md`,
  - Index-Zeile einer Projekt-Lesson → `docs/factory/PROJECT-CONTEXT.md` (Gruppe „Projekt-Lessons"),
  - Factory-Lessons kommen **nie** in `PROJECT-CONTEXT.md`.

  „Kontext laden" nennt `docs/factory/lessons/INDEX.md`. Die bestehenden Anker der Tests
  „#426 AK-C5" / „#27 AK4" bleiben erfüllt.
- [ ] **AK9** – GIVEN die ausgelieferte Suite
  WHEN sie `codify.md` prüft
  THEN behauptet eine neue Assertion `docs/factory/lessons/INDEX.md` im Skill-Text, und eine zweite
  Assertion schließt aus, dass der Skill Factory-Index-Zeilen nach `PROJECT-CONTEXT.md` leitet.
  Der Anker ist eine Phrase aus dem Patch-Wortlaut der Task-Datei.

### C – Doku ohne Drift

- [ ] **AK10** – GIVEN der Stand nach dem PR
  WHEN man `git grep -n -E 'Index-Zeile|Lessons-Index|Index der ausgelagerten|Index der Stolpersteine'`
  ausführt
  THEN beschreibt jeder Treffer, der den **aktuellen** Ort des Factory-Index nennt, `lessons/INDEX.md`
  bzw. die Übersicht in `FACTORY.md`. Historische Vorfall-Narrative bleiben unverändert (ADR-Kontext,
  Skript-Kommentare mit „von ~80 auf 341 Zeilen", Lessons, Specs, Tasks). Die Treffer-Liste mit
  Einordnung (geändert/historisch) steht in der Task-Datei.
- [ ] **AK11** – GIVEN Factory-ADR-037 und Factory-ADR-047
  WHEN man sie liest
  THEN trägt jede einen datierten Nachtrag (2026-11-…, #44):
  - ADR-037: Ort, zweistufige Form, `/codify`-Weg.
  - ADR-047: §2 Verlagerung „Portabilität in Gate-/Shell-Skripten" nach `bash-gotchas.md`; §3
    Formatverweis zeigt auf die Übersicht in `FACTORY.md`; §4 Byte-Grenze mit Herleitung.
- [ ] **AK12** – GIVEN `CHANGELOG.md`
  WHEN man `## Unreleased` liest
  THEN gibt es unter `### Geändert` einen Eintrag „Factory-Lessons-Index ausgeliefert (#44)". Er nennt
  Ort, Zweistufigkeit und Byte-Grenze und trägt einen **Migration**-Satz: „Den Abschnitt
  `#### Factory-Lessons` samt Einzelzeilen aus dem eigenen `docs/factory/PROJECT-CONTEXT.md`
  entfernen; Projekt-Lessons bleiben dort."

### D – Deckel misst Bytes

- [ ] **AK13** – GIVEN `import-context-limit-check.sh`
  WHEN er läuft
  THEN summiert er für dasselbe Datei-Set wie bisher zusätzlich die **Bytes** (`wc -c`, Ausgabe vor
  dem Integer-Guard von Leerzeichen befreit). Er ist rot (exit 1), wenn die Summe `MAX_IMPORT_BYTES`
  überschreitet, und grün bei genau `MAX_IMPORT_BYTES`. Die Grün-Meldung nennt beide Werte:
  `@import-Dauerkontext: <z> von <MAX_IMPORT_LINES> Zeilen, <b> von <MAX_IMPORT_BYTES> Bytes`.
  Die Rot-Meldung bei Byte-Überschreitung nennt Ist, Grenze und eine Bytes-Beitragsliste je Datei.
- [ ] **AK14** – GIVEN `import-context-limit-check.sh`
  WHEN die Bytezahl einer Datei nicht ermittelbar ist (Stub `wc` im `PATH`, der scheitert oder
  Nicht-Zahl liefert)
  THEN ist der Check rot mit `Bytezahl nicht ermittelbar: <datei> (fail-closed)`, nicht still grün.
  Bei Messbruch gibt es keinen stillen Rückfall auf die Zeilenprüfung allein.
- [ ] **AK15** – GIVEN die Konstanten `MAX_IMPORT_LINES` und `MAX_IMPORT_BYTES`
  WHEN der bestehende Herleitungstest (`#319: MAX_IMPORT_LINES … entspricht der dokumentierten
  Herleitung`) und ein neuer Zwillingstest für Bytes laufen
  THEN rechnen beide die Konstante aus der Basis im Kommentar nach:
  - Zeilen: `((basis*125/100)+49)/50*50`, Kommentar `# = <n> Zeilen …`
  - Bytes: `((basis*125/100)+999)/1000*1000`, Kommentar `# = <n> Bytes …`

  Die Basis ist jeweils der **gemessene Ist-Stand dieses Repos nach allen Kürzungen**.
- [ ] **AK16** – GIVEN die Projekt-Suite (`scripts/project/tests/run-tests.sh`)
  WHEN sie läuft
  THEN prüft sie, dass der reale Stand dieses Repos unter **beiden** Grenzen liegt (bestehender
  Realstand-Test, um Bytes erweitert).

### E – Dauerkontext < 30.000 Bytes

- [ ] **AK17** – GIVEN der Stand nach dem PR
  WHEN man die Bytes über das `@import`-Set misst (Ausgabe von `import-context-limit-check.sh`)
  THEN ist die Summe **< 30.000**. Der Wert vorher (82.453) und nachher stehen mit Datei-Aufschlüsselung
  im PR-Body und in der Task-Datei.
- [ ] **AK18** – GIVEN die Kürzungen in `FACTORY.md` (M3–M6)
  WHEN die Suiten laufen
  THEN ist jede Anker-Phrase, die ein Test in `FACTORY.md` erwartet, wörtlich erhalten (Liste in der
  Task-Datei, Schritt 5.1). Jede entfernte Detail-Aussage steht nachweislich in `OPERATING.md` bzw. in
  der genannten Guideline. Falls nicht, wird sie dorthin verschoben, nicht gelöscht.
- [ ] **AK19** – GIVEN `clean-code.md` und `bash-gotchas.md` (M7)
  WHEN man sie liest
  THEN steht der Abschnitt „Portabilität in Gate-/Shell-Skripten" zeichengleich als neuer Abschnitt
  `## 20.` in `bash-gotchas.md` (vor `## Querregel`). `clean-code.md` trägt an seiner Stelle einen
  Einzeiler-Verweis. Code-Kommentare, die `clean-code.md "Portabilität …"` zitieren, zeigen auf
  `bash-gotchas.md`.

### F – Gates

- [ ] **AK20** – GIVEN der Stand nach Anwenden des Patches
  WHEN `scripts/checks/pre-push.sh`, beide Suiten, `bash -n`-Lint und `ownership-check.sh` laufen
  THEN sind alle grün.

## Fehlerszenarien

- [ ] **F1** `INDEX.md` wird versehentlich per `@` eingebunden → AK4-Guard rot. Der Deckel zählt die
  Datei mit und meldet die Überschreitung.
- [ ] **F2** Neue Lesson-Datei ohne Übersichtszeile oder ohne `INDEX.md`-Gruppe → AK6-Guard rot und
  nennt die Datei namentlich.
- [ ] **F3** Gruppen-Link in `INDEX.md` zeigt ins Leere → AK6(b) rot.
- [ ] **F4** `wc -c` liefert unter BSD führende Leerzeichen → wird vor dem Integer-Guard entfernt.
  Ohne Entfernung wäre der Check auf macOS immer rot (Test läuft lokal **und** in CI).
- [ ] **F5** Unlesbare/fehlende Quelle des AK6-Guards (`FACTORY.md`, `INDEX.md`,
  `customization-points.txt`) → rot (`UNLESBAR:`), nicht still grün. Je Quelle gibt es einen eigenen
  Negativtest (Lesson „Kopplungs-/Drift-Guard").
- [ ] **F6** Patch `tasks/patch-44.diff` noch nicht angewendet → AK9-Assertions rot. Der Push wird
  bis zum Apply zurückgehalten (Lesson „Neuer Guard prüft Dateien, die nur per `.claude/**`-Patch
  änderbar sind").
- [ ] **F7** Konsument mit noch vorhandenem altem Factory-Abschnitt in `PROJECT-CONTEXT.md` → nichts
  bricht: Doppel-Index, nur größer. Behebung per CHANGELOG-Migration (E4); kein Test nötig.
- [ ] **F8** Ziel < 30.000 Bytes nach M3–M8 nicht erreicht → **Stopp und Rückfrage an den Menschen**.
  Keine freien Kürzungen in `tdd-principles.md`, `testing-standards.md` oder den Kern-Kurzregeln 1–8.

## Offene Fragen

- [ ] (für `/architecture`, optional) Sind die Nachträge statt eines neuen ADR akzeptabel (E5)? Ohne
  Einwand gilt E5.
