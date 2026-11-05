# Spec: Turn-Limit für `/implement` nach AK-Zahl staffeln

> Issue #49. Erweitert die größenabhängige Modellwahl (Factory-ADR-038, Signal `proxy` = AK-Zahl der
> Spec) um das Turn-Budget. Berührt die Kosten-Obergrenze aus Factory-ADR-009 §6 / ADR-010 / ADR-051
> (`MAX_TURNS_CEILING = 80`) nicht.

## Kontext

`run-pipeline.sh` startet `/implement` mit einem festen Turn-Budget aus `factory.defaults.yml`
(`skills.implement.max_turns: 20`). Das Modell wird schon nach der AK-Zahl der Spec gewählt
(`tier_by_size`), das Turn-Budget dagegen nicht.

**Was heute passiert:** Task 47 (PR #48, 18 AK + 8 Fehlerfälle) riss in `/implement` das Limit von
20 Turns dreimal in Folge. Die Pipeline brach ab. Die Teilarbeit lag uncommittet im Baum und musste von
Hand gesichert und weitergeführt werden. Dieser Fortsatz lief ohne OTEL-Telemetrie. Die Lesson
„Turn-Limit“ in `docs/factory/PROJECT-CONTEXT.md` zählt sieben solcher Vorfälle.

**Warum ein pauschal höherer Wert nicht reicht:** ein fester Wert gilt für alle Läufe und alle
adoptierenden Projekte. Kleine Tasks bekämen damit einen höheren Kosten-Deckel, den sie nicht
brauchen. Ein Override nur im Factory-Repo würde die Dogfooding-Garantie aufgeben: Der Test aus
nothra/tch-gastro-services#348 verlangt, dass `factory.config.yml` dieses Repos keine `skills.*`-Werte setzt.

**Primärer Nutzer:** wer `run-pipeline.sh` für eine Task mit vielen Akzeptanzkriterien startet und
einen Lauf ohne Turn-Limit-Abbruch erwartet. Sekundär: der Maintainer eines adoptierenden Projekts, der
die Stufen in `factory.config.yml` kalibriert.

**Erfolg:** Eine Task in der Größe von Task 47 läuft in `/implement` ohne Turn-Limit-Abbruch durch.
Die Kosten-Wirkung ist in der Config benannt (`@tradeoff`).

## Begriffe

- **AK-Zahl:** Anzahl der Checkbox-Zeilen (`- [ ]` / `- [x]`) im Abschnitt `## Akzeptanzkriterien`
  der Spec `docs/specs/spec-<id>-*.md`. Gezählt wird genau so wie heute für die Modellwahl
  (Signal `proxy`). Es gibt keine zweite Zählweise.
- **Stufe:** ein AK-Bereich und das Turn-Budget, das zu ihm gehört.
- **Turn-Budget:** der Wert, den `run-pipeline.sh` als „max N turns“ an den `/implement`-Aufruf gibt.

## Scope

**Inbegriffen:**
- Das Turn-Budget von `/implement` wird in drei Stufen nach der AK-Zahl gewählt:

  | AK-Zahl | Turn-Budget |
  |---------|-------------|
  | 1 – 5   | 20          |
  | 6 – 11  | 40          |
  | ab 12   | 60          |

- Das gilt für jeden `/implement`-Aufruf eines Laufs, also auch für die Rework-Iterationen nach `/review`.
- Fehlt die Spec, fehlt ihr Abschnitt `## Akzeptanzkriterien` oder enthält er 0 AK, stoppt die
  Pipeline, bevor `/implement` startet. Heute gibt es an dieser Stelle nur eine Warnung.
- Stufen und Werte stehen in `factory.defaults.yml`, jeweils mit `@reason` und einem `@tradeoff`, der
  die Kosten-Wirkung benennt. Ein adoptierendes Projekt kann sie in `factory.config.yml` überschreiben.
  Für die Werte gilt dieselbe Gate-Obergrenze wie für jedes `max_turns` (`[1, MAX_TURNS_CEILING]`).
- Die Doku nennt die Staffelung überall, wo sie heute das Turn-Budget von `/implement` beschreibt:
  `factory.config.yml.example`, `.claude/commands/configure-factory.md`, `docs/factory/OPERATING.md`.
  Außerdem nennt `factory.config.yml.example` die tatsächliche Obergrenze (heute steht dort `[1, 50]`,
  das Gate prüft gegen 80).

**Nicht inbegriffen:**
- `/bug-fix` behält sein festes Budget von 20 Turns, obwohl es das Modell genauso wählt. Für eine
  Staffelung dort gibt es bisher keinen Vorfall.
- Die Turn-Budgets aller anderen Skills (`review`, `security-review`, `test`, `refactor`, `codify`,
  `pr-shepherd`, `default`) bleiben unverändert.
- `MAX_TURNS_CEILING` (80) bleibt unverändert, ebenso die Gate-Mechanik aus ADR-010/ADR-051.
- Die Modellwahl (`tier_by_size`, Schwelle 6) bleibt unverändert, auch ihr Fail-Safe auf `heavy`.
- `MAX_TURNS` als Umgebungsvariable überschreibt das Turn-Budget weiterhin für alle Skills eines Laufs.
- Kein Override von `skills.*` in `factory.config.yml` dieses Repos (Dogfooding-Garantie aus
  nothra/tch-gastro-services#348 bleibt bestehen).
- Ausgeklammert bleibt der Orchestrator-Retry ohne `git status`-Prüfung (Lesson „Turn-Limit“,
  nothra/tch-gastro-services#275), ebenso das Sichern von Teilarbeit nach einem Abbruch.

## Akzeptanzkriterien

Turn-Budget nach AK-Zahl. Die Pipeline wird jeweils mit `--dry-run` und ohne `MAX_TURNS` gestartet:

- [ ] AK1: GIVEN eine Spec mit 5 AK WHEN die Pipeline `/implement` startet THEN meldet sie `max 20 turns`
- [ ] AK2: GIVEN eine Spec mit 6 AK WHEN die Pipeline `/implement` startet THEN meldet sie `max 40 turns`
- [ ] AK3: GIVEN eine Spec mit 11 AK WHEN die Pipeline `/implement` startet THEN meldet sie `max 40 turns`
- [ ] AK4: GIVEN eine Spec mit 12 AK WHEN die Pipeline `/implement` startet THEN meldet sie `max 60 turns`
- [ ] AK5: GIVEN eine Spec mit 18 AK (Größe von Task 47) WHEN die Pipeline `/implement` startet THEN meldet sie `max 60 turns`
- [ ] AK6: GIVEN eine Spec mit 8 AK und einen `/review`-Befund, der eine Rework-Iteration auslöst WHEN die Pipeline `/implement` erneut startet THEN meldet sie auch dort `max 40 turns`
- [ ] AK7: GIVEN eine Spec, deren AK teils abgehakt (`- [x]`) und teils offen (`- [ ]`) sind WHEN die Pipeline das Turn-Budget wählt THEN zählen beide Formen (dieselbe AK-Zahl wie bei der Modellwahl)

Pipeline stoppt bei unerfüllter Vorbedingung:

- [ ] AK8: GIVEN für die Task-ID existiert keine Spec `docs/specs/spec-<id>-*.md` WHEN die Pipeline startet THEN endet sie mit Exit ≠ 0, startet `/implement` nicht und meldet die Task-ID, die Ursache „Spec fehlt“ und den Hinweis auf `/requirements <id>`
- [ ] AK9: GIVEN eine Spec ohne Abschnitt `## Akzeptanzkriterien` WHEN die Pipeline startet THEN endet sie mit Exit ≠ 0, startet `/implement` nicht und meldet die Ursache „Abschnitt Akzeptanzkriterien fehlt“
- [ ] AK10: GIVEN eine Spec, deren Abschnitt `## Akzeptanzkriterien` keine Checkbox-Zeile enthält WHEN die Pipeline startet THEN endet sie mit Exit ≠ 0, startet `/implement` nicht und meldet die Ursache „0 Akzeptanzkriterien“
- [ ] AK11: GIVEN eine der Lagen aus AK8–AK10 WHEN die Pipeline mit `--dry-run` startet THEN stoppt sie genauso (Exit ≠ 0, dieselbe Meldung)
- [ ] AK12: GIVEN eine der Lagen aus AK8–AK10 und `MAX_TURNS=50` in der Umgebung WHEN die Pipeline startet THEN stoppt sie trotzdem (Exit ≠ 0, dieselbe Meldung)

Overrides und Grenzen:

- [ ] AK13: GIVEN eine Spec mit 18 AK und `MAX_TURNS=50` in der Umgebung WHEN die Pipeline `/implement` startet THEN meldet sie `max 50 turns` (Umgebungsvariable vor Staffelung, Bestand)
- [ ] AK14: GIVEN ein `factory.config.yml`, das eine Stufe auf einen anderen gültigen Wert setzt (z. B. ab 12 AK → 70) WHEN die Pipeline `/implement` für eine Spec in dieser Stufe startet THEN meldet sie den überschriebenen Wert
- [ ] AK15: GIVEN ein `factory.config.yml`, das ein Stufen-Budget auf 81 setzt WHEN das Config-Validierungs-Gate läuft THEN lehnt es die Config mit Exit ≠ 0 ab (Obergrenze 80 gilt auch je Stufe)
- [ ] AK16: GIVEN ein `factory.config.yml`, das ein Stufen-Budget auf 0 oder einen Nicht-Integer setzt WHEN das Config-Validierungs-Gate läuft THEN lehnt es die Config mit Exit ≠ 0 ab

Unverändertes Verhalten:

- [ ] AK17: GIVEN eine gültige Spec WHEN die Pipeline die übrigen Skills startet THEN behalten sie ihr heutiges Budget (`review` 30, `security-review` 30, `test` 20, `refactor` 20, `codify` 8, `pr-shepherd` 8)
- [ ] AK18: GIVEN `skills.bug-fix` in `factory.defaults.yml` WHEN die Config gelesen wird THEN steht dort weiterhin ein festes `max_turns: 20` ohne Staffelung
- [ ] AK19: GIVEN der reale `factory.config.yml` dieses Repos WHEN die Pipeline `/implement` für eine Spec startet THEN löst sie das Budget end-to-end aus der Staffelung in `factory.defaults.yml` auf, und `factory.config.yml` setzt keine `skills.*`-Werte (Dogfooding-Garantie aus nothra/tch-gastro-services#348)

Doku und Begründung:

- [ ] AK20: GIVEN `factory.defaults.yml` WHEN man die Staffelung von `skills.implement` liest THEN trägt sie ein `@reason` (Anlass: Turn-Limit-Abbrüche bei großen Tasks) und ein `@tradeoff`, der die Kosten-Wirkung benennt (größere Tasks bis zu dreifaches Budget gegenüber heute)
- [ ] AK21: GIVEN `factory.config.yml.example`, `.claude/commands/configure-factory.md` und `docs/factory/OPERATING.md` WHEN man dort das Turn-Budget von `/implement` nachliest THEN beschreiben sie die Staffelung, und `factory.config.yml.example` nennt die Obergrenze 80

## Fehlerszenarien

- [ ] F1: Spec fehlt → Stopp vor `/implement` (AK8)
- [ ] F2: Abschnitt `## Akzeptanzkriterien` fehlt → Stopp (AK9)
- [ ] F3: Abschnitt vorhanden, 0 Checkbox-Zeilen → Stopp (AK10)
- [ ] F4: Mehrere Spec-Dateien passen auf `spec-<id>-*.md`. Gemessen wird dieselbe Datei wie bei der Modellwahl, damit Modell und Budget nie aus verschiedenen Specs kommen.
- [ ] F5: Stufen-Budget in der Config außerhalb `[1, 80]` oder kein Integer → das Gate lehnt fail-closed ab (AK15, AK16). Es gibt keinen stillen Rückfall auf einen Default.
- [ ] F6: Stufen-Config ist unvollständig oder widersprüchlich (Bereiche überlappen, Lücke zwischen Stufen, fehlende unterste Stufe) → das Gate lehnt fail-closed ab, statt zur Laufzeit eine unbestimmte Stufe zu wählen

## Folgewirkungen (für `/architecture` und `/implement`)

- **Bestehende Tests:** Die Self-Test-Suite ruft `run-pipeline.sh` an rund 116 Stellen auf, meist mit
  `--dry-run` und ohne Spec. Mit dem Stopp aus AK8/AK11 brechen diese Läufe vor `/implement` ab.
  Die Fixtures brauchen also eine Spec mit AK, auch der Test aus nothra/tch-gastro-services#348 in der
  Projekt-Suite. Das ist Teil dieser Task, kein Folge-Issue.
- **Adoptierende Projekte:** Wer die Pipeline heute ohne Spec startet, bekommt nach dem Update einen
  Stopp statt einer Warnung. Das ist eine Verhaltensänderung und gehört in `CHANGELOG.md`.
- **Modell-Fail-Safe:** Der Fail-Safe auf `heavy` für eine nicht bestimmbare AK-Zahl
  (`tier_by_size`) greift für `/implement` künftig nie mehr, weil die Pipeline vorher stoppt. Für
  `/bug-fix` bleibt er wirksam.

## Offene Fragen

- [ ] Q1 (an `/architecture`): Wie wird die Staffelung in der Config dargestellt, und hängt sie mit
  `tier_by_size` zusammen (gemeinsames Signal, getrennte Schwellen)? Die Entscheidung erweitert
  ADR-038 und braucht deshalb eine ADR.
- [ ] Q2 (an `/architecture`): Löst der Stopp aus AK8–AK10 einen Interrupt über `raise-interrupt.sh`
  aus (dann neuer Typ samt Eintrag in der Interrupt-Tabelle von `OPERATING.md`), oder genügt der
  Preflight-Abbruch wie bei den übrigen Preflight-Fehlern?
- [ ] Q3 (an `/architecture`): Prüft das Gate die Stufen-Struktur (F6) selbst, oder ist die Struktur
  so gebaut, dass Überlappung und Lücken gar nicht ausdrückbar sind?
