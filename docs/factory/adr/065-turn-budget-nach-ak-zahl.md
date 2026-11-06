# ADR 065: Turn-Budget von `/implement` nach AK-Zahl staffeln (erweitert ADR-038)

## Status

Accepted (2026-11-06)

> Erweitert **ADR-038** (größenabhängige Modellwahl) um das Turn-Budget und **ADR-010** um eine
> Gate-Regel. Obergrenze (`MAX_TURNS_CEILING = 80`, ADR-051), Merge-Semantik der Config (ADR-009)
> und die Modellwahl selbst bleiben unverändert.

## Kontext

Spec: [`docs/specs/spec-49-turn-limit-implement.md`](../../specs/spec-49-turn-limit-implement.md)
(Issue #49).

`/implement` startet mit einem festen Budget von 20 Turns (`skills.implement.max_turns`). Bei Task 47
(18 AK) riss dieses Limit dreimal in Folge, und die Pipeline brach ab. Die Spec verlangt drei Stufen
nach der AK-Zahl der Spec (1–5 → 20, 6–11 → 40, ab 12 → 60). Außerdem soll die Pipeline stoppen,
wenn die Spec fehlt, ihr AK-Abschnitt fehlt oder er 0 AK enthält. Heute gibt es dort nur eine Warnung
im Preflight.

Die Spec übergibt drei Fragen:

- **Q1:** Wie sieht die Staffelung in der Config aus, und wie hängt sie mit `tier_by_size` zusammen?
- **Q2:** Löst der Stopp einen Interrupt aus?
- **Q3:** Muss das Gate Überlappung und Lücken der Stufen prüfen?

Rahmenbedingungen aus dem Bestand:

- Die effektive Config entsteht per Deep-Merge (`. * $item`). Maps werden zusammengeführt, **Listen
  werden ersetzt**.
- Regel 2 des Gates lehnt jeden Override-Blattpfad ab, den `factory.defaults.yml` nicht kennt. Ein
  Team kann also nur Werte überschreiben, die schon existieren.
- `measure_size proxy` (in `scripts/lib/tier-select.sh`) zählt die AK schon für die Modellwahl. Bei
  fehlender Spec oder fehlendem Abschnitt liefert es eine leere Ausgabe, bei 0 Checkboxen `0`.
- Preflight-Fehler beenden die Pipeline mit `exit 1`, bevor der Metrik-Trap registriert ist
  (ADR-045 §6). Im Async-Betrieb setzt `factory-poll.sh` das Issue bei Exit ≠ 0 auf `factory::failed`.

## Entscheidung

### 1. Config: Feld `max_turns_by_size` mit zwei benannten Stufen über dem Basiswert (Q1)

```yaml
skills:
  implement:
    tier: heavy
    tier_by_size: { signal: proxy, threshold: 6 }
    max_turns: 20                       # Basis: gilt unterhalb der ersten Stufe (1–5 AK)
    max_turns_by_size:
      signal: proxy
      mid:  { from: 6,  max_turns: 40 } # 6–11 AK
      high: { from: 12, max_turns: 60 } # ab 12 AK
```

- **Additiv und analog zu `tier_by_size`:** Das statische `max_turns` bleibt Pflichtfeld auf jedem
  Skill (Regel 4b unverändert) und ist die unterste Stufe. Skills ohne `max_turns_by_size` verhalten
  sich wie heute.
- **Benannte Stufen statt Liste:** `mid` und `high` sind Map-Schlüssel. Damit greift der Deep-Merge
  pro Blatt, und jedes Blatt (`…mid.from`, `…high.max_turns` usw.) existiert in den Defaults. Ein Team
  kann Grenzen und Budgets einzeln überschreiben (Spec AK14). Weitere Stufen oder ein
  `max_turns_by_size` an einem anderen Skill kann es nicht hinzufügen: Regel 2 lehnt das ab. Damit
  bleibt `bug-fix` ohne Staffelung (AK18), ohne dass dafür eine eigene Regel nötig ist.
- **Eigenes Feld, gemeinsames Signal:** Turn-Staffelung und Modellwahl lesen dieselbe Messung
  (`measure_size`), haben aber getrennte Schwellen. Dass die erste Turn-Stufe bei 6 liegt wie die
  Modell-Schwelle, ist eine Kalibrier-Entscheidung, keine Kopplung. Beide Werte lassen sich unabhängig
  ändern.
- **Signal-Werte:** wie bei `tier_by_size` `{diff, proxy}`. `/implement` nutzt `proxy`.

### 2. Auswahl-Logik: reine Funktion `select_max_turns` in `scripts/lib/tier-select.sh`

```
select_max_turns <size> <base> <mid_from> <mid_turns> <high_from> <high_turns>
  size leer/nicht-numerisch → high_turns   (Fail-Safe: kein stilles Downgrade, wie ADR-038)
  size >= high_from         → high_turns
  size >= mid_from          → mid_turns
  sonst                     → base
```

`get_max_turns <skill> [task_id]` in `run-pipeline.sh` ruft die Funktion auf, wenn
`max_turns_by_size.signal` gesetzt ist. Sonst liefert sie wie heute das statische `max_turns`.
`run_skill` gibt `task_id` weiter. `MAX_TURNS` aus der Umgebung hat weiter Vorrang
(`${MAX_TURNS:-$(get_max_turns …)}`, AK13).

Der Fail-Safe auf `high_turns` ist für `/implement` nicht erreichbar, weil der Preflight (§3) vorher
stoppt. Er sichert nur den Fall ab, dass ein Team `max_turns_by_size` für einen anderen Lauf nutzt
oder die Spec mitten im Lauf verschwindet.

Die Funktion kommt in die bestehende Lib, nicht in eine neue Datei. So muss kein Test-Scaffold eine
weitere Lib kopieren (`cp_pipeline_libs`, Lesson „Neue gesourcte Lib“). Der Kopfkommentar der Lib,
der heute „zwei reine Funktionen“ nennt, wird mitgepflegt.

### 3. Stopp im Preflight, unabhängig von der Config (Q2: kein Interrupt)

`preflight_checks` macht aus der Warnung „No spec file found“ einen Fehler (`errors+1`) und prüft
dazu den AK-Abschnitt. Es gibt drei Fälle mit je eigener Meldung, jeweils mit Task-ID und dem
Hinweis `/requirements <id>`:

| Lage | Erkennung | Meldung (Ursache) |
|------|-----------|-------------------|
| Spec fehlt | keine Datei `docs/specs/spec-<id>-*.md` | „Spec fehlt“ |
| Abschnitt fehlt | `measure_size proxy` leer | „Abschnitt Akzeptanzkriterien fehlt“ |
| 0 AK | `measure_size proxy` = `0` | „0 Akzeptanzkriterien“ |

- Der Stopp ist eine **Vorbedingung des Laufs** und hängt nicht an der Turn-Config. Auch ein Team,
  das die Staffelung überschreibt, startet `/implement` nie ohne Spec mit AK.
- `--dry-run` und gesetztes `MAX_TURNS` umgehen den Preflight nicht (AK11/AK12). Der Preflight läuft
  schon heute vor jedem Modus.
- **Kein Interrupt.** Die anderen Preflight-Fehler (Platzhalter, unsauberer Baum) lösen auch keinen
  aus. Im Async-Betrieb wird der Abbruch über `factory::failed` sichtbar, lokal über Exit ≠ 0 und die
  Meldung. Ein neuer Interrupt-Typ würde einen Eintrag in der Interrupt-Tabelle von `OPERATING.md`
  und eine zweite Benachrichtigung für denselben Zustand nach sich ziehen.
- **Dieselbe Spec-Datei (F4):** Preflight und `_measure_proxy` finden die Datei heute je mit einem
  eigenen `find … | head -1`. Beides wird zu einem Helfer `spec_file_for <task_id> <repo_dir>` in
  `tier-select.sh` zusammengezogen. Damit wählen Preflight, Modellwahl und Turn-Wahl dieselbe Datei
  aus derselben Funktion, nicht nur zufällig aus demselben Ausdruck.

### 4. Gate-Regel 4d in `config-validation-check.sh` (Q3)

Wo `max_turns_by_size` in der effektiven Config steht:

- `signal ∈ {diff, proxy}`
- `mid.from`, `high.from` sind Integer, `mid.from >= 2` (die Basis deckt mindestens 1 AK ab) und
  `high.from > mid.from`
- `mid.max_turns`, `high.max_turns` sind Integer in `[1, MAX_TURNS_CEILING]`, also dieselbe Obergrenze
  wie Regel 4b

Fehlt ein Feld, kommt `""`/`null` an und fällt in die Integer-Ablehnung. **Lücken sind nicht
ausdrückbar**, weil jede Stufe bis zur nächsten `from`-Grenze reicht. **Überlappung** wird durch
`high.from > mid.from` ausgeschlossen. **Eine fehlende unterste Stufe** gibt es nicht, weil sie das
Pflichtfeld `max_turns` ist. Monoton steigende Budgets erzwingt das Gate nicht: ein absteigendes
Budget ist teuer-unsinnig, aber nicht kostentreibend, und eine Regel dafür wäre Gold-Plating.

## Alternativen

### Option A: Benannte Stufen `mid`/`high` über dem Basis-`max_turns` (gewählt)

Vorteile: passt zu Deep-Merge und Regel 2 (jedes Blatt überschreibbar, nichts hinzufügbar); Lücken
nicht ausdrückbar; `max_turns` bleibt Pflichtfeld mit klarer Bedeutung; Muster von `tier_by_size`.
Nachteile: genau drei Stufen sind fest verdrahtet. Eine vierte Stufe braucht eine Änderung an
Defaults, Lib und Gate.

### Option B: Liste von Stufen (`steps: [{from, max_turns}, …]`)

Vorteile: beliebig viele Stufen.
Nachteile: Der Deep-Merge ersetzt Listen komplett. Ein Team, das nur ein Budget ändern will, muss
alle Stufen wiederholen. Regel 2 müsste Listen-Indizes als Blattpfade behandeln (heute fängt sie
Listen gerade als unbekannte Pfade ab, Lesson zu `yq` und `!!seq`). Das Gate müsste Sortierung,
Lücken und Duplikate prüfen. Mehr Mechanik für eine Flexibilität, die niemand verlangt (YAGNI).

### Option C: Map mit Untergrenzen als Schlüssel (`steps: { "1": 20, "6": 40, "12": 60 }`)

Vorteile: kompakt; Lücken nicht ausdrückbar.
Nachteile: Die Grenzen stecken im Schlüssel. Eine Grenze zu verschieben heißt, einen neuen Blattpfad
einzuführen, und den lehnt Regel 2 ab. Ein Team könnte nur Budgets ändern, keine Grenzen. Außerdem
dupliziert die Map das Pflichtfeld `max_turns` (Stufe „1“).

### Option D: Turn-Stufen an `tier_by_size` koppeln (ein Feld, eine Schwelle)

Vorteile: kein neues Feld.
Nachteile: `tier_by_size` ist binär (eine Schwelle), die Spec verlangt drei Stufen. Modell- und
Turn-Schwelle ließen sich nicht mehr getrennt kalibrieren.

### Zu Q2: Stopp als Interrupt (`raise-interrupt.sh`, neuer Typ)

Vorteile: im Async-Betrieb ein eigener, maschinenlesbarer Abbruchgrund.
Nachteile: Ein Interrupt bedeutet „menschliche Entscheidung mitten im Lauf“. Hier hat der Lauf noch
gar nicht begonnen. Anders als andere Preflight-Fehler wäre das eine Sonderbehandlung, mit neuem
Eintrag in der Interrupt-Tabelle und doppelter Meldung neben `factory::failed`. Abgelehnt.

## Begründung

Option A ist die kleinste Erweiterung, die alle Spec-Anforderungen an die Config erfüllt
(Kalibrierbarkeit von Grenzen und Budgets, Obergrenze je Stufe, keine Lücken). Sie verlässt sich
dabei auf zwei Mechanismen, die es schon gibt (Deep-Merge, Regel 2), statt neue zu bauen. Auswahl-
und Messlogik bleiben reine Funktionen in einer schon gesourcten Lib und sind ohne `claude`-Lauf
testbar. Der Stopp gehört in den Preflight, weil er eine Vorbedingung des ganzen Laufs prüft und
keine Eigenschaft der Turn-Wahl ist.

Die Entscheidung ist reversibel. Stufenwerte sind Config. Das Feld lässt sich entfernen, dann gilt
wieder das statische `max_turns`. Die Telemetrie (ADR-049) zeigt pro Lauf Turns und Kosten, damit
lassen sich die Stufen später an Messwerten ausrichten.

## Konsequenzen

**Positiv:**
- Große Tasks (Task 47: 18 AK) bekommen 60 statt 20 Turns, kleine bleiben bei 20.
- `/implement` startet nie mehr ohne Spec mit AK. Teure Läufe ohne Abnahmekriterien entfallen.
- Kein neuer Mechanismus: Merge, Regel 2, Obergrenze und Lib bleiben, wie sie sind.

**Negativ / Trade-offs:**
- **Kosten:** Ein `/implement`-Lauf ab 12 AK darf bis zum Dreifachen des heutigen Budgets
  verbrauchen, ab 6 AK bis zum Doppelten. Das steht als `@tradeoff` an der Staffelung in
  `factory.defaults.yml`.
- **Verhaltensänderung für adoptierende Projekte:** Ein Lauf ohne Spec bricht künftig ab, statt zu
  warnen. Das gehört als Breaking-Hinweis in `CHANGELOG.md` (Abschnitt `Unreleased`).
- **Test-Fixtures:** Etwa 116 Aufrufe von `run-pipeline.sh` in der Self-Test-Suite laufen heute ohne
  Spec und stoppen künftig im Preflight. Sie brauchen eine Spec-Fixture mit AK.
- **Toter Fail-Safe für `/implement`:** Der `heavy`-Fallback von `tier_by_size` (ADR-038 F2) greift
  für `/implement` nicht mehr, weil der Preflight vorher stoppt. Für `/bug-fix` bleibt er wirksam.
- Drei feste Stufen. Mehr Stufen brauchen eine neue ADR (Option B nachrüstbar).

## Implementierungs-Hinweise

**Betroffene Artefakte:**
- `factory.defaults.yml`: `skills.implement.max_turns_by_size` (Werte wie oben) mit `@reason` und
  `@tradeoff` (Kosten-Wirkung). Den Kommentar am `max_turns: 20` auf „Basis, unterhalb der ersten
  Stufe“ ändern.
- `scripts/lib/tier-select.sh`: `select_max_turns`, `spec_file_for`; `_measure_proxy` nutzt
  `spec_file_for`; Kopfkommentar mitpflegen.
- `scripts/run-pipeline.sh`: `get_max_turns <skill> [task_id]`, Aufruf in `run_skill`;
  `preflight_checks` Schritt 2 als Fehler mit drei Meldungen (über `spec_file_for` und `measure_size`).
- `scripts/checks/config-validation-check.sh`: Regel 4d.
- Doku: `factory.config.yml.example` (Staffelung, Obergrenze 80 statt 50),
  `.claude/commands/configure-factory.md`, `docs/factory/OPERATING.md`, `CHANGELOG.md` (`Unreleased`).
- ADR-Pflege: Erweiterungs-Notiz in ADR-038 und ADR-010, Zeile im ADR-Index (`README.md`); Status
  dieser ADR beim Umsetzen auf `Accepted`.

**Tests:**
- `select_max_turns` direkt gegen die Lib testen: Grenzen 5/6/11/12, leer, nicht-numerisch.
- E2E per `--dry-run` gegen die echte `factory.defaults.yml` (Spec AK1–AK5). Ein Gate-Test beweist
  nicht, dass der Konsument den Wert nutzt (Lesson nothra/tch-gastro-services#348).
- Preflight: je Lage (AK8–AK10) die eigene Meldung prüfen und die Abwesenheit von
  „Starte: /implement“, außerdem mit `--dry-run` und `MAX_TURNS`. Mutation je Zweig (Lesson zum
  Fail-closed-Zweig).
- Gate 4d: je Regel ein Negativtest (`mid.from = 1`, `high.from <= mid.from`, Budget 0/81/Text,
  falsches Signal) und ein Positivtest mit gültigem Override (AK14).
- **Fixtures zuerst:** Den gemeinsamen Scaffold-Helfern (`mk_feature_repo`, `_mk_pipe_repo`, ggf.
  `scaffold_310`) eine Spec-Fixture mit 3 AK geben, bevor der Preflight scharf geschaltet wird. Inline
  aufgebaute Repos einzeln nachziehen. Für die Fixture einen Helfer schreiben, nicht 116-mal inline
  (Lesson zu duplizierten Scaffolds).
- Projekt-Suite: Der #348-Test braucht eine Spec-Fixture. Die erwartete Zahl ergibt sich aus der Stufe
  der Fixture, nicht mehr aus `.skills.implement.max_turns` allein.

**Vorgehen:** Laut Turn-Limit-Lesson (> 10 AK) in getrennten Skill-Läufen fahren, nicht über
`run-pipeline.sh`. Sinnvolle Reihenfolge: (1) Fixtures + Helfer, Suite grün; (2) Lib + Gate;
(3) Preflight + `get_max_turns`; (4) Doku/ADR-Pflege.
