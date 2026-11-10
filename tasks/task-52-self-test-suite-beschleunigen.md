# Task 52: self-test-suite-beschleunigen

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Laufzeit der ausgelieferten Self-Test-Suite senken, ohne Abdeckung zu verlieren. Schwerpunkt ist
`scripts/checks/tests/factory-lock-tests.sh` (362 von 566 s lokal). Parallele Ausführung ist erlaubt.
Spec: [`docs/specs/spec-52-self-test-suite-beschleunigen.md`](../docs/specs/spec-52-self-test-suite-beschleunigen.md)

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] AK1 – Profiling vorher/nachher je Abschnitt (lokal Median aus 3, CI), Methode ohne Zeilen-Zuordnungsartefakt
- [ ] AK2 – `factory-lock-tests.sh` lokal ≤ 181 s
- [ ] AK3 – gesamte Suite lokal (macOS) ≤ 240 s
- [ ] AK4 – CI-Job `factory-self-test` nicht langsamer als vorher
- [ ] AK5 – Anzahl der Assertions gleich; jede Namens-/Reihenfolge-Abweichung begründet
- [ ] AK6 – jede Assertion prüft denselben Sachverhalt mit derselben Erwartung
- [ ] AK7 – Rot-Nachweis je geändertem Fixture-Muster dokumentiert
- [ ] AK8 – geteilte Basis-Fixture bleibt unverändert (Fingerprint-Test)
- [ ] AK9 – Abschnitte reihenfolge-unabhängig
- [ ] AK10 – parallel: PASS/FAIL zusammengeführt, Exit ≠ 0 bei Rot, Ausgabe nicht verschränkt (entfällt ohne Parallelisierung)
- [ ] AK11 – parallel: abgebrochene Gruppe → Suite rot, nie als grün gelesen (entfällt ohne Parallelisierung)
- [ ] AK12 – konsumenten-neutral (Fixture-Lauf grün, kein Node/DB)
- [ ] AK13 – grün auf macOS (bash 3.2) und `ubuntu-latest`
- [ ] AK14 – keine Wegwerf-Verzeichnisse/Hintergrundprozesse nach Lauf (auch rot/Signal)
- [ ] AK15 – Ownership-Check grün für neue Dateien
- [ ] F1–F5 – Fehlerszenarien der Spec abgedeckt

## Technische Notizen
Entscheidung: [ADR-066](../docs/factory/adr/066-self-test-gruppen-parallel.md) (Proposed → beim Umsetzen auf Accepted flippen).

**Messung (2026-11-10, macOS, Gruppe allein, 504 s, 482 ✓):** #23 66 s · #24 151 s · #37 287 s
(AK-37c 84 s, guard/preflight 84 s, /test-fetch/publish 58 s, Doku-Guards 23 s). Helfer: `world_23` 0,3 s,
`world_24` 0,5 s, `upd_24` 4,0 s (51×), `sync_23` 1,7 s (29×), `hostile_37` 7,1 s (10×), `${adr_37//x/}` 8,4 s (4×).
→ Fixtures sind billig; die Zeit liegt in den Läufen der getesteten Skripte (= Prüfgegenstand). Hebel = Überlappung.

**Reihenfolge für `/implement`:**
1. Baseline festhalten: Assertion-Liste (`✓`/`✗`-Zeilen ohne Farbcodes) von `origin/main` sichern (AK5) und
   Vorher-Profiling nach AK1 (Median aus 3, Zeitmarke je Abschnittskopf).
2. D7 zuerst (klein, unabhängig): Literal-Entfernung linear statt `${v//x/}`, mit Äquivalenztest auf kleinen Eingaben.
3. D2: Helfer nach `scripts/checks/tests/lib/factory-lock-fixtures.sh`; Abschnitte in Shard-Dateien
   (`factory-lock-23-tests.sh`, `-24-`, `-37a-`, `-37b-` – Schnitt nach Messung, kein Shard deutlich > ~150 s).
   Jeder Shard: eigenes `mktemp -d`, eigene Vorlage, EXIT-Trap fürs Aufräumen (D5).
4. D1/D3/D4/D6: `scripts/checks/tests/lib/test-groups.sh` (Start + Sammeln); Start am Anfang von `run-tests.sh`,
   Sammeln an der heutigen `source`-Stelle; Ergebnisdatei `RESULT <pass> <fail>`; fail-closed als eine rote
   Assertion je abgebrochenem Shard; `FACTORY_SELF_TEST_SERIAL=1` = derselbe Pfad ohne Überlappung.
5. Nachmessen; D8 (`hostile_37`-Vorlage) nur, wenn der #37-Shard danach der kritische Pfad über dem Ziel ist.

**Fallen / mitzupflegen:**
- `SHIPPED_TESTS_28` in `run-tests.sh` (Liste ausgelieferter Testdateien) um die neuen Dateien erweitern.
- `OWNERSHIP.md`: jede neue Datei Seite `factory`; Fixture-Lauf der Konsumenten-Neutralität (ADR-064 D6) erneut fahren.
- Shard-Prozess braucht `set -uo pipefail`, die Helfer aus `lib/assert-helpers.sh` (neutralisiert `GIT_*`, F3) und
  `FACTORY_ROOT`/`HAS_YQ`/`CHECKS_DIR`/`SCRIPTS_DIR`; `FACTORY_SELF_TEST_RUN` ist exportiert und erreicht die Shards.
- `GITHUB_ACTIONS`/`GITHUB_OUTPUT`/`PR_SHEPHERD`/`FACTORY_STAGE` im Shard wie bisher behandeln (F4; Lesson CI-Erkennung).
- Ergebnisdatei getrennt vom Log (Log-Inhalt ist Testausgabe, darf das Ergebnis nicht fälschen).
- Neue Tests für D3/D4/D5/D6 mit Stub-Shards (grün, rot, `exit 2` ohne RESULT, kaputte RESULT-Zeile, Signal),
  je Fail-Pfad pfadspezifische Meldung (Lesson „Negativ-Test mit mehreren Fail-Pfaden isolieren“).
- Wegwerf-Sonden nur in `$TMPDIR` (Lesson build-tooling).
- Verweise auf `factory-lock-tests.sh` in ADR-063 (Z. ~773) und Spec #37: Hinweis auf den neuen Ort.

## Offene Fragen
- [x] Q5 (`/architecture`): → Shards parallel, ADR-066 – Ziel ≤ 240 s ist bei Scope „nur factory-lock“ praktisch nur mit Parallelisierung erreichbar – Weg + ADR-Trigger prüfen
- [x] Q6 (`/architecture`): → parallel überall, `FACTORY_SELF_TEST_SERIAL=1`, ADR-066 D6 – Parallelisierung auch in CI/bei Konsumenten, Schalter für sequenziellen Lauf?

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `test/52-self-test-suite-beschleunigen`
Erstellt: 2026-11-10 02:18
