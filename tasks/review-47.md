# Review: Task 47

> Iteration 2 · Diff `origin/main...HEAD` (15 Dateien, +1086/−331), Schwerpunkt Rework-Commit `9621a70` ·
> Spec `docs/specs/spec-47-copy-files-konfigurierbar.md`, Factory-ADR-063 Nachtrag (E23–E27). CI des PRs grün
> (factory-self-test, project-self-test, lint, config-validation, factory-integrity, pr-closes-issue). Randfälle von
> `factory_cfg_list` / `factory_cfg_list_dropped` und Regel 9 mit einer Wegwerf-Sonde gegen yq v4.53.3 (gepinnte
> Version) selbst nachvollzogen. Iteration 1: NEEDS_REWORK (W1), siehe Task-Datei.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_ – W1 aus Iteration 1 ist behoben: `factory_cfg_list_dropped` zählt die verworfenen Elemente,
`start-work.sh` warnt gesammelt, ADR E24 und Spec F8 beschreiben jetzt genau dieses Verhalten. Selbst geprüft:
`[5, "", "a\nb", "lokal.conf"]` → 3 verworfen, `{x: lokal.conf}` / `lokal.conf` / `true` / `0` / `[null]` / `[[x]]` →
1 verworfen, `[]` / unset → 0 und keine Ausgabe.

## Nitpicks (optional)

- [ ] [scripts/lib/gate-config.sh:52 (`(.$1 // []) as $l`)] `copy_files: false` und `copy_files: ~` (null) zählen
  als 0 verworfen, weil `//` beide durch `[]` ersetzt. `start-work.sh` spiegelt dann still nichts, während Regel 9 beide
  als „keine Liste" ablehnt (selbst geprüft, rc=1). Spec F8 sagt „ein Wert, der keine Liste ist, wird gezählt
  gewarnt". Die Wirkung ist sicher (nichts wird kopiert), und `null`/`false` als „aus" zu lesen ist intuitiv. Entweder
  in F8 als Ausnahme benennen oder `false`/`null` mitzählen. Kein Rework-Grund.
- [ ] [scripts/lib/gate-config.sh:34] Ohne `pipefail` maskiert die Pipe `yq eval-all … | yq eval … -` einen
  YAML-Parsefehler (selbst geprüft: rc=0, leere Liste). In `start-work.sh` greift `set -euo pipefail`, die neue
  „nicht lesbar"-Warnung feuert dort also auch bei kaputtem YAML (geprüft: rc=1). Das Verhalten der Lib hängt damit
  vom Strict-Mode des Aufrufers ab. Vorbestehend und nicht von diesem PR eingeführt, nur erwähnt, weil der neue
  Warnpfad darauf aufbaut.
- [ ] [scripts/start-work.sh (Warnung „1 Eintrag … / N Einträge …")] Zwei fast gleiche `warn_copy`-Zeilen nur für
  Singular und Plural. Ein Wort per Variable (`Eintrag`/`Einträge`) würde den Meldungstext an einer Stelle halten.
  Kandidat für `/refactor`. Beide Zweige sind getestet (3 bzw. 1).
- [ ] [scripts/probe47.tmp.sh, scripts/review47.tmp.sh, scripts/review47b.tmp.sh, tasks/telemetry-raw-47-*.tmp.txt]
  Wegwerf-Dateien liegen weiter im Baum. Sie sind gitignoret (`git status --ignored`), aber nach der Lesson
  build-tooling sollten sie sofort gelöscht werden. `review47b.tmp.sh` ist die Sonde dieser Iteration. Ihr `rm` war in
  dieser Session nicht freigegeben; bitte manuell löschen.
- Aus Iteration 1 weiter offen, absichtlich weitergereicht: F5-`mkdir`-Zweig geht an `/test`, die Quell-Elternkette
  an `/security-review`. Beides bleibt ein Hinweis und ist hier kein Finding.

## Positives

- **Rework mit Selbstfund:** Neben W1 wurde ein echter Defekt gefunden und behoben. `.[]` auf einer Map lieferte ihre
  Werte als Einträge (`{x: lokal.conf}` hätte `lokal.conf` kopiert). Jetzt wird nur über `!!seq` iteriert. Das ist
  per Test belegt (804/805) und im Kommentar begründet.
- **Leere Elemente** werden jetzt vorab verworfen und gezählt, statt dass `$(…)` sie am Listenende abschneidet. Der
  `-n`-Guard vor dem Here-String verhindert eine falsche „leerer Pfad"-Warnung, wenn nur verworfene Elemente da sind.
- **Behauptung verifiziert:** „Ohne if/then/else: die gepinnte yq-Version kennt es nicht" stimmt (v4.53.3:
  `lexer: invalid input text "if (…"`).
- **„Nicht lesbar"-Test** setzt einen yq-Stub ein, der nur an `copy_files`-Ausdrücken scheitert. Der übrige Lauf
  bleibt dabei intakt, und der Test belegt die Warnung gezielt auf diesem Pfad (Lesson nothra/tch-gastro-services#214,
  Fail-Pfad isolieren). Die Fail-closed-Zusicherung bricht er über die Messung, nicht über den Input (Lesson
  nothra/tch-gastro-services#319).
- **Nitpicks aus Iteration 1 erledigt:** eigene Task-ID 802 für AK8, Steuerzeichen in OPERATING.md, Warnung bei
  Lesefehler. Der Reihenfolge-Anker auf die exakte Aufrufzeile wurde nach der Einrückungsänderung mitgezogen.
- **Doku-Drift sauber:** ADR E24, Spec F8 und der Modul-Header von `gate-config.sh` (neue Funktion
  `factory_cfg_list_dropped` aufgeführt, Lesson nothra/tch-gastro-services#207) passen zum Code.

## Empfehlung

APPROVED
