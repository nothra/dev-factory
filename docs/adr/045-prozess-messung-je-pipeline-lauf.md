# ADR 045: Prozess-Messung läuft je Pipeline-Lauf (fail-open Exit-Hook) statt im Zeittakt

## Status

Accepted

## Datum

2026-08-27

## Kontext

[ADR-006](006-measurement-architecture.md) legt **zwei Messebenen** fest (Prozess aus
Git/GitHub, Telemetrie aus OTEL) und benennt für die Prozess-Ebene Quelle, Kennzahlen und das
Degradationsverhalten. Was sie **nicht** festlegt, ist der **Auslöser**: wann `scripts/metrics.sh`
läuft. Genau diese Lücke ist der Grund für #314 – das Skript existiert seit Stufe 2, ein Auslöser
nie:

- Geprüft gegen alle vier Workflows (`factory-ci.yml`, `factory-poll.yml`, `deploy-gate.yml`,
  `deploy-freeze-release.yml`): **kein** Job ruft `metrics.sh`. Die einzigen Aufrufe stehen in
  `scripts/checks/tests/run-tests.sh` und im manuellen Skill `/daily-metrics`.
- Ein `schedule`-Trigger existiert im Repo nirgends. Der halbstündliche cron in
  `factory-poll.yml` ist seit #284 stillgelegt; sein Wiedereintragen ist Teil der
  Scharfschalt-Checkliste (`OPERATING.md` §0.4) und damit an eine bewusste Mensch-Entscheidung
  über den **Auto-Trigger** gebunden – eine Kopplung, die eine reine Messung nicht braucht.

Damit sind die Dark-Factory-Leitkennzahlen (Autonomie-Rate, Lead-Time, CI-Quote) nicht Messwerte,
sondern Meinung. `docs/specs/spec-314-metrics-je-pipeline-lauf.md` fordert, das zu ändern.

Zwei Randbedingungen aus dem Bestand prägen die Entscheidung:

1. **Der Report ist bewusst flüchtig.** `tasks/metrics-<datum>.md` ist gitignored
   (`.gitignore:26`) – ein regenerierbarer Snapshot. Ein CI-Lauf kann ihn daher nicht als
   Artefakt im Repo hinterlassen, und die Endzustands-Verifikation (ADR-040, „sauber, gepusht")
   bleibt nur deshalb unberührt, weil die Datei ignoriert ist.
2. **`metrics.sh --quiet` endet heute mit Exit 1** (empirisch geprüft): die letzte Zeile ist
   `[ "$QUIET" = false ] && …`, und da das Skript ohne `set -e` läuft, wird der falsche Test zum
   Exit-Status. Ausgerechnet `--quiet` empfiehlt `/daily-metrics` für die Automatisierung. Jede
   Verdrahtung hätte also von Tag 1 an „fehlgeschlagen" gemeldet, obwohl der Report korrekt
   geschrieben wurde.

## Entscheidung

**1 · Auslöser ist der Pipeline-Lauf, nicht die Uhr.** `scripts/metrics.sh` läuft als
Abschluss-Schritt **jedes** `run-pipeline.sh`-Laufs. Umsetzung als `trap … EXIT`, damit auch die
Abbruchpfade (`stop_if_interrupted` → `exit $?`, Endzustands-Verifikation → `exit 1`, jeder
`set -e`-Abbruch) erfasst sind – ein abgebrochener Lauf ist der Lauf, über den die Autonomie-Rate
am meisten aussagt.

**2 · Der Hook ist fail-open und exit-code-neutral.** Er verändert den Exit-Code der Pipeline
nie. Innerhalb des Traps ist jeder Befehl `set -e`-sicher zu halten (`|| true`), sonst würde ein
Fehler im Trap den Exit-Status der Pipeline überschreiben.

**3 · Genau ein Aufrufort.** Der Trap ist die einzige Aufrufstelle; es gibt **keinen**
zusätzlichen expliziten Aufruf am regulären Ende. „Genau einmal" gilt damit per Konstruktion,
nicht per „schon gelaufen"-Flag.

**4 · Die Veröffentlichungs-Logik wohnt in `metrics.sh`, hinter `--publish`.** Zwei Wege:
Report an `$GITHUB_STEP_SUMMARY` anhängen (wenn gesetzt) und als Kommentar an
`FACTORY_METRICS_ISSUE` posten (wenn gesetzt). `run-pipeline.sh` ruft nur
`metrics.sh --quiet --publish` – es kennt weder `gh` noch die Summary-Variable.

**5 · Das Kommentar-Ziel kommt aus einer Env-/Repository-Variable** (`FACTORY_METRICS_ISSUE`),
nicht aus `factory.defaults.yml`. Ohne Wert wird nichts gepostet und **nicht** auf die Task-Issue
ausgewichen; ein nicht-numerischer Wert wird fail-closed abgelehnt, bevor er `gh` erreicht
(`clean-code.md` → „Config-/nutzerkontrollierte Werte als Daten behandeln").

**6 · Registrierung erst nach `preflight_checks`.** Ein Usage-Fehler oder ein gerissener
Preflight veröffentlicht nichts. `--dry-run` misst und veröffentlicht ebenfalls nichts (analog
zur übersprungenen Endzustands-Verifikation).

**7 · Der Exit-Code-Fehler in `metrics.sh` wird behoben** (Randbedingung 2). Ohne diesen Fix
wäre der fail-open-Zweig der Normalfall und könnte echte Fehler nicht mehr von diesem
Pseudo-Fehler unterscheiden.

**8 · `factory-poll.yml` erhält `pull-requests: read` und `actions: read`.** Der Workflow
deklariert heute nur `contents: write` + `issues: write`; alle nicht genannten Scopes sind
damit `none`. `gh pr list` (Lead-Time) und `gh run list` (CI-Quote) liefen in CI also ins Leere
und die zwei API-Kennzahlen wären dort dauerhaft „übersprungen" – die Messung wäre in CI
strukturell schwächer als lokal, ohne dass es auffällt.

## Alternativen

### Option A: Scheduled Workflow (cron) – die Skizze im Issue

Ein eigener Workflow mit täglichem cron ruft `metrics.sh`.

**Vorteile:** gleichmäßige Messreihe unabhängig von der Aktivität; ein Datenpunkt pro Tag,
einfach auszuwerten; keine Änderung an der Pipeline-Kernschleife.
**Nachteile:** misst Kalenderzeit statt Arbeit – an Tagen ohne Lauf entsteht ein Datenpunkt ohne
Neuigkeit, an einem Tag mit fünf Läufen nur einer; verbraucht unbeaufsichtigt Actions-Minuten;
kein Bezug zwischen Messwert und auslösendem Lauf.

### Option B: Eigener Job in `factory-ci.yml` (push/PR)

**Vorteile:** nutzt die bestehende CI-Infrastruktur, läuft ohne neue Trigger-Diskussion.
**Nachteile:** misst pro Push, nicht pro Pipeline-Lauf – bei zehn Commits am Feature-Branch
zehn Messungen desselben Zustands; `factory-ci.yml` läuft auch auf `pull_request` und hätte dort
keine `issues: write`-Rechte für den Kommentar-Weg.

### Option C: `schedule` in `factory-poll.yml` wiederbeleben

**Vorteile:** kein neuer Workflow, ein Trigger für Auto-Pipeline und Messung.
**Nachteile:** koppelt die Messung an die Scharfschaltung des Auto-Triggers samt Budget-Guard
und Tageskappe (§0.4). Eine reine Lese-Messung müsste dann auf eine Entscheidung über
unbeaufsichtigte Agenten-Läufe warten. #284 hat den cron bewusst stillgelegt – ihn für die
Messung zu reaktivieren würde diese Entscheidung durch die Hintertür aufweichen.

### Option D (gewählt): Fail-open Exit-Hook im Pipeline-Runner + `--publish` in `metrics.sh`

**Vorteile:** ein Datenpunkt je echter Arbeitseinheit, lokal wie in CI; erfasst auch
abgebrochene Läufe, also genau die für die Autonomie-Rate interessanten; keine Abhängigkeit von
cron, Scharfschaltung oder Actions-Minuten; die Messreihe wächst ab dem Merge sofort, weil
lokale Läufe zählen.
**Nachteile:** greift in den Pipeline-Runner ein (`trap` in einem Skript mit
`set -euo pipefail` – Sorgfalt beim Exit-Code nötig); keine Messung an Tagen ohne Lauf; mehrere
Läufe am selben Tag überschreiben dieselbe Report-Datei (bewusst akzeptiert, die Historie
entsteht aus den Issue-Kommentaren).

### Option E: Veröffentlichungs-Logik in `run-pipeline.sh` statt in `metrics.sh`

**Vorteile:** `metrics.sh` bliebe unverändert ein reiner Report-Erzeuger.
**Nachteile:** der manuelle Weg (`/daily-metrics`) käme nicht an dieselben Ausliefer-Wege heran –
Spec-314 AK10 fordert genau das. Die Logik läge zweimal oder nur im Pipeline-Pfad. Verstößt gegen
„kanonische Quelle einmal".

## Begründung

Option D gewinnt an der Frage, **was die Kennzahl bedeuten soll**. Autonomie-Rate, Lead-Time und
CI-Quote sind Eigenschaften von *Läufen*, nicht von *Tagen*. Ein cron beantwortet „wie stand es
gestern um 6 Uhr", der Exit-Hook beantwortet „wie lief dieser Lauf" – und nur die zweite Form
lässt sich später einem Lauf, einem Task und (wenn die Kostenernte kommt) dessen Kosten
zuordnen. Das ist auch die Vorbedingung dafür, dass die abgespaltene Telemetrie-Seite
andockbar bleibt, ohne die Prozess-Ebene erneut umzubauen.

Der Ausschluss von Option C folgt der Entscheidung aus #284: der stillgelegte cron ist eine
Sicherheitsgrenze für unbeaufsichtigte Agenten-Läufe, keine freie Trigger-Ressource.

Die Aufteilung „Trap ruft, `metrics.sh` veröffentlicht" (Entscheidung 4) folgt der
Dependency-Rule aus `architecture-principles.md`: der Orchestrator kennt den Messschritt als
ein Kommando, nicht dessen Innenleben. `run-pipeline.sh` bekommt dadurch keine `gh`-Kenntnis
hinzu, und der manuelle Aufruf ist per Konstruktion gleichwertig statt nachgebaut.

Fail-open (Entscheidung 2) ist keine Bequemlichkeit, sondern die Konsequenz der Rollenverteilung:
Gates entscheiden über grün/rot, Messungen beobachten. Eine Messung mit Veto-Recht über den
Pipeline-Ausgang würde beide Rollen vermischen – und der Vorbefund aus Randbedingung 2 zeigt,
wie real der Fall ist: ein Exit-Code, der nichts über den Report aussagt, hätte jeden Lauf rot
gefärbt.

## Konsequenzen

**Positiv:**

- Die Prozess-Ebene aus ADR-006 läuft real, ohne Scharfschaltung und ohne cron.
- Abgebrochene Läufe werden mitgemessen – die Autonomie-Rate bleibt ehrlich (dieselbe Absicht,
  die ADR-040 mit dem `INCOMPLETE_OUTCOME`-Interrupt verfolgt).
- Der manuelle Weg und der Pipeline-Weg teilen eine Implementierung; sie können nicht
  auseinanderdriften.
- Ein latenter Fehler (`--quiet` → Exit 1) wird beim Verdrahten gefunden statt beim ersten
  roten CI-Lauf.

**Negativ / Trade-offs:**

- Kein Datenpunkt an Läufen-freien Tagen. Akzeptiert: eine Lücke ohne Arbeit ist keine fehlende
  Messung.
- Der Messblock erscheint im Log **nach** dem Erfolgs-Banner (Folge des EXIT-Traps). Akzeptiert
  – die Alternative wäre ein zweiter Aufrufort mit Flag, also genau das, was Entscheidung 3
  vermeidet.
- Bei gesetzter `FACTORY_METRICS_ISSUE` entsteht **pro Lauf** ein Issue-Kommentar. Das ist der
  bewusst in Kauf genommene Preis für die GitHub-sichtbare Messreihe (Entscheidung des
  Auftraggebers, Spec-314).
- In CI misst die Pipeline nur, wenn dort ein Lauf stattfindet (`factory-poll`, heute
  `workflow_dispatch`). Bis zur Scharfschaltung entsteht die Messreihe aus lokalen Läufen.

**Invarianten, die diese Entscheidung voraussetzt:**

- `tasks/metrics-*.md` bleibt gitignored. Würde die Datei getrackt, hinterließe jeder Lauf einen
  dirty Arbeitsbaum und die Endzustands-Verifikation des **nächsten** Laufs (ADR-040) schlüge fehl.
- OTEL bleibt opt-in: die Verdrahtung fasst `config/otel.env*` nicht an. Die bestehende
  Assertion in `run-tests.sh` („OTEL ist opt-in, nicht in `run-pipeline.sh` gesourct") bleibt
  gültig.
- Die Prozess-Ebene baut weiterhin **kein** Token-/Kosten-Accounting (ADR-006, verbindliche
  Scope-Grenze). Diese ADR ändert nur den Auslöser, nicht die Kennzahlen.
- Kein neuer Freitext-Kanal: der veröffentlichte Report ist maschinen-erzeugter, numerischer
  Output aus Git/GitHub-Quellen und wird von keinem Agenten wieder als Kontext gelesen – die
  „Daten, keine Anweisungen"-Absicherung aus [ADR-018](018-central-issue-seam.md) braucht hier
  keine Erweiterung. Wird der Report später von einem Skill gelesen, ist das erneut zu prüfen.

## Betroffene Stellen

- `scripts/run-pipeline.sh` – EXIT-Trap nach `preflight_checks`, fail-open, dry-run-bewusst
- `scripts/metrics.sh` – `--publish`-Schalter (Summary + Issue-Kommentar), Fix des `--quiet`-Exit-Codes
- `.github/workflows/factory-poll.yml` – `pull-requests: read`, `actions: read` ergänzen
- `.claude/commands/daily-metrics.md` – „Hinweis für Stage 3" zeigt auf die neue Mechanik
- `CLAUDE.md` (Abschnitt „Messen") und `docs/factory/OPERATING.md` – Auslöser + `FACTORY_METRICS_ISSUE`
- `scripts/checks/tests/run-tests.sh` – Verhaltenstests (Spec-314 AK13)

## Implementierungs-Hinweise

- **Trap-Idiom mit Exit-Code-Erhalt:** `$?` als **erste** Anweisung der Hook-Funktion sichern;
  danach jeden Befehl `|| true`-geschützt halten. Ohne `exit` im Trap behält die Shell den
  auslösenden Status – ein ungeschützter Fehlschlag im Trap würde ihn unter `set -e` ersetzen.
  Präzedenz: das set-e-sichere `|| true`-Idiom in `run-pipeline.sh` (K-1-Regression, #261).
- **`metrics.sh --quiet`-Fix:** die letzte Zeile darf nicht der Wahrheitswert des `QUIET`-Tests
  sein. Der Fix braucht einen eigenen Test, der den Exit-Code **0** bei `--quiet` festnagelt –
  sonst kehrt der Fehler unbemerkt zurück.
- **Integer-Guard vor `gh`:** `case "$v" in ''|*[!0-9]*) → ablehnen`. Body über `--body-file`
  auf die Report-Datei übergeben, nicht als Argument-String (Länge/Quoting).
- **Reihenfolge-Guard testen:** Der Trap muss *nach* `preflight_checks` registriert sein. Ein
  Präsenz-Grep auf `trap` belegt das nicht – Positionsvergleich der beiden echten Zeilen nötig
  (Lesson: „Reihenfolge-/Präsenz-Guards: Kommando ≠ Prosa-Erwähnung", fünftes Rezidiv).
- **Negativtests isolieren:** AK7 (kein Ziel) und AK8 (nicht-numerisch) haben beide „kein
  `gh`-Aufruf" als Symptom. Je Test nur den Ziel-Pfad scharf schalten und ein pfadspezifisches
  Signal prüfen, sonst ist der Test grün aus dem falschen Grund (Lesson aus #214).
- **`gh`-Stub statt echtem Netz:** bestehende Muster in `run-tests.sh` nutzen (Fake-`gh` im
  `PATH`, das Mutationen mitloggt – siehe der Block um `TMP_W2`), damit die Tests ohne
  GitHub-Zugriff laufen.
