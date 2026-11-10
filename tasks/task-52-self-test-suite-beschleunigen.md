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
- [x] AK1 – Profiling vorher/nachher je Abschnitt (lokal Median aus 3, CI), Methode ohne Zeilen-Zuordnungsartefakt
- [x] AK2 – `factory-lock-tests.sh` lokal ≤ 181 s
- [ ] AK3 – gesamte Suite lokal (macOS) ≤ 240 s — **verfehlt (353 s), eskaliert**: Engpass ist der Rest der Suite außerhalb des Scopes, siehe Umsetzung
- [x] AK4 – CI-Job `factory-self-test` nicht langsamer als vorher
- [x] AK5 – Anzahl der Assertions gleich; jede Namens-/Reihenfolge-Abweichung begründet (Auslegung: alle 2444 alten unverändert, +22 neue Tests für neuen Mechanismus – siehe Umsetzung)
- [x] AK6 – jede Assertion prüft denselben Sachverhalt mit derselben Erwartung
- [x] AK7 – Rot-Nachweis je geändertem Fixture-Muster dokumentiert
- [x] AK8 – geteilte Basis-Fixture bleibt unverändert (Fingerprint-Test)
- [x] AK9 – Abschnitte reihenfolge-unabhängig
- [x] AK10 – parallel: PASS/FAIL zusammengeführt, Exit ≠ 0 bei Rot, Ausgabe nicht verschränkt (entfällt ohne Parallelisierung)
- [x] AK11 – parallel: abgebrochene Gruppe → Suite rot, nie als grün gelesen (entfällt ohne Parallelisierung)
- [x] AK12 – konsumenten-neutral (Fixture-Lauf grün, kein Node/DB)
- [x] AK13 – grün auf macOS (bash 3.2) und `ubuntu-latest`
- [x] AK14 – keine Wegwerf-Verzeichnisse/Hintergrundprozesse nach Lauf (auch rot/Signal)
- [x] AK15 – Ownership-Check grün für neue Dateien
- [x] F1–F5 – Fehlerszenarien der Spec abgedeckt

## Technische Notizen
Entscheidung: [ADR-066](../docs/factory/adr/066-self-test-gruppen-parallel.md) (Accepted mit der Umsetzung).

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

## Umsetzung (`/implement`, 2026-11-10)

**Schnitt (D2, nach Messung):** `factory-lock-tests.sh` → `factory-lock-23-tests.sh`, `-24a-` (bis F-24.3), `-24b-`
(ab FS-T2.3), `-37a-` (Verdrahtung, Doku-Guards, AK-37b/c), `-37b-` (Fail-closed fetch/publish, F-37.1, guard/preflight).
#24 wurde zuerst ungeteilt gemessen (171–174 s, über den ~150 s aus D2) und dann geteilt. Gemeinsame Helfer in
`lib/factory-lock-fixtures.sh`, Start/Sammeln/Ergebnisvertrag in `lib/test-groups.sh`. Die Rümpfe wurden per
`sed`-Zeilenbereich aus dem Original geschnitten (keine Abschrift). D8 (`hostile_37`-Vorlage) entfällt: 37a ist nicht der
kritische Pfad (siehe Messung).

**Abweichung vom ADR beim Exit-Status (D3/D4):** Der Status einer Gruppe kommt nicht aus `wait <pid>` der Suite, sondern
aus einer Datei, die ein Wrapper-Subshell schreibt. Erster Volllauf: 37b war grün (Ergebnis geschrieben), die Suite
meldete aber „Exit 127". Ursache: Die Suite startet bis zum Sammeln Zehntausende Prozesse, die PID der längst beendeten
Gruppe wird wiederverwendet und bash verwirft deren Status. Regressionstest: Der Treiber reapt vor dem Sammeln alle Kinder
(`wait` ohne Argument). Die Mutante „Status aus `wait`" wird rot.

**Messung AK1** (Methode: `run-tests.sh` mit Zeitmarke je Ausgabezeile, Sekunden ab Start. Vorher: Abschnittszeit =
Kopf des Abschnitts bis Kopf des nächsten bzw. bis `Ergebnis:`. Nachher: Wanduhrzeit je Gruppe in ihrem eigenen Prozess
(`SECONDS`, Zeile `• Testgruppe …`). Die Gruppe als Ganzes = längste Gruppe, da alle gleichzeitig starten.
Maschine: macOS arm64, 8 Kerne, bash 3.2, an diesem Tag deutlich langsamer als bei der Messung im Issue.)

| Stand | Lauf 1 | Lauf 2 | Lauf 3 | **Median** | #23 | #24 | #37 | Gruppe |
|---|---|---|---|---|---|---|---|---|
| vorher `origin/main` @ 8676a44 | 1242 s | 1076 s | 1006 s | **1076 s** | 58 s | 136 s | 526 s | 720 s (seq.) |
| nachher (Branch, 5 Gruppen) | 353 s | 357 s | 337 s | **353 s** | 95 s | 24a 95 s · 24b 121 s | 37a 136 s · 37b 126 s | **136 s** (parallel) |
| nachher seriell (`FACTORY_SELF_TEST_SERIAL=1`) | 932 s | – | – | – | 64 s | 79 + 101 s | 126 + 134 s | 504 s (seq.) |

(Lauf 1 vorher überlappte mit einer Sonde; Median und Abschnittswerte stammen aus Lauf 2.) Der größte Einzelhebel ist D7:
`${adr_37//x/}` kostete an diesem Tag ~124 s je Mutante (4×), `strip_literal_37` < 1 s bei gleichem Ergebnis.

- **AK2 ✓:** Gruppe 136 s (Median, längste Gruppe 37a) ≤ 181 s; Vorher 720 s.
- **AK3 ✗ – eskaliert:** Gesamt 353 s > 240 s. Der Engpass ist jetzt der Rest der Suite außerhalb des Scopes (Spec Q2):
  Die Gruppen sind nach ≤ 143 s fertig, das Sammeln beginnt erst bei ~330–350 s. Schon vorher lag der Rest an diesem Tag
  bei ~300–350 s (Kopf #23 vorher bei 297–356 s), also über 240 s. Das ist das Restrisiko aus ADR-066 „Konsequenzen":
  Nicht still den Scope erweitert. Entscheidung durch den Menschen nötig (z. B. Folge-Issue für die
  run-pipeline-E2E-Abschnitte oder Zielwert relativ zur Maschine).
  **Versuch AK3 (2026-11-10, verworfen):** Der größte serielle Block (#334, 81 s, 286 Assertions) wurde probehalber als
  sechste Gruppe `telemetry-334-tests.sh` mit gemeinsamer Lib ausgelagert (2467 grün, Gruppe allein 83–88 s). Ergebnis:
  Die Gesamtzeit sank **nicht** (Läufe 398/419 s statt 353 s; die übrigen Abschnitte wurden unter Last langsamer, z. B.
  #310 34→51 s, #312 31→49 s). Ursache: Die Suite nutzt im Mittel nur 1,3 Kerne (`time`: 186 s user + 335 s system über
  398 s, 131 % CPU) bei Load 8–12 – die Systemzeit (Prozess-Starts, `fork`/`exec`) dominiert und skaliert auf diesem Mac
  nicht mit zusätzlichen Gruppen. Weitere Auslagerung bringt hier nichts; ein Hebel wäre nur weniger Prozess-Starts
  je Assertion (Umbau tausender Testzeilen, außerhalb des Scopes). Der Versuch wurde zurückgenommen (kein gemessener
  Nutzen). Entscheidung weiter beim Menschen: AK3 als Folge-Issue (Prozess-Starts senken) oder Zielwert je Maschine.
- **AK4 ✓:** CI-Job `factory-self-test` (`ubuntu-latest`, Dauer laut `gh pr checks`, inkl. Setup): vorher 3 min 14 s
  (PR #53 = Stand von `main` 8676a44, derselbe Tag), nachher **1 min 44 s** (PR #54 @ 864b213), grün. Einschränkung:
  `gh run view`/`gh api` waren in dieser Session nicht freigegeben, deshalb gilt die Job-Dauer statt der Dauer des
  Suite-Schritts allein. Das Setup (Checkout, yq, Hooks) ist in beiden Läufen gleich.
- **AK5 ✓:** Alle 2444 Assertions von vorher stehen unverändert und in derselben Reihenfolge in der Liste von nachher
  (`diff` zeigt nur Einfügungen). Neu sind 22 Zeilen (2466 = 2444 + 22):
  - 15 × `#52 …` (Abschnitt „Factory-Issue #52“ vor dem Sammelpunkt): Tests für D1/D3/D4/D5/D6/D7, F5, von ADR-066 verlangt.
  - 5 × `#52 AK8: Vorlage der Testgruppe factory-lock-<g>-tests nach allen Fällen unverändert` am Ende jeder Gruppe (AK8).
  - 2 × `#22 F-22.5: scripts/checks/tests/lib/{factory-lock-fixtures,test-groups}.sh wird mit der Suite ausgeliefert`
    (bestehende Schleife über `lib/*`, wächst mit jeder neuen Lib).
  Weggefallen ist keine Assertion. Name und Reihenfolge der alten Assertions sind unverändert.
- **AK6 ✓:** Assertions, Erwartungen und Mutationsbelege sind unverändert übernommen. Einzige inhaltliche Änderung:
  Die vier Prosa-Mutanten in 37a entstehen per `strip_literal_37` statt `${v//x/}` (Äquivalenztest D7: 11 Fälle,
  zusätzlich auf der ganzen ADR-063 verglichen: identisch, 69331 Zeichen). Fixture-Ort `H23` liegt jetzt in `T23` (Aufräumen).
- **AK7 ✓ – Rot-Nachweise je geändertem Fixture-Muster** (Repo-Kopie, Mutation in `lib/factory-lock-fixtures.sh`,
  echter Shard. Kontrolle mit wirkungsloser Änderung: 37a 57 grün / 0 rot):
  - *Prosa-Mutante (D7):* `strip_literal_37` entfernt nichts (`n > 0` → `n < 0`) → 37a: genau die 4 Assertions
    „AK-37c/g/h (Mutation): … ist derselbe Guard rot“ werden ✗ (erwartet exit=1, war 0), 53 grün / 4 rot.
  - *Welt je Gruppe / eigene Vorlage (D2, AK8/F2):* `world_23` legt einen Symlink auf die Vorlage statt einer Kopie an
    → 23: `#52 AK8: Vorlage … unverändert` wird ✗ (dazu 53 Folgefehler), 157 grün / 54 rot.
  - *Ergebnisvertrag/Aufräumen (`test-groups.sh`):* 14 Mutanten, alle rot (AK10/AK11).
- **AK9 ✓:** Die fünf Gruppen allein in umgekehrter Reihenfolge (37b, 37a, 24b, 24a, 23) ergeben je Exit 0, zusammen
  487 Assertions, identisch mit den letzten 487 Zeilen des Gesamtlaufs. Gemeinsamer Zustand: keiner, jede Gruppe baut
  ihre eigene Vorlage.
- **AK10/AK11 ✓:** Tests mit Stub-Gruppen (grün+grün, grün+rot, `exit 2` ohne Ergebnis, kaputte RESULT-Zeile,
  Exit ≠ 0 bei fail = 0, Signal, Wrapper per KILL, gefälschtes Ergebnis aus Log/Kindprozess, Reihenfolge der Ausgabe).
  14 Mutanten von `test-groups.sh`/D7 werden alle rot (je Fail-Pfad eine eigene Meldung).
- **AK12 ✓:** Fixture-Lauf (127 Dateien der Seite `factory` aus dem Manifest von 864b213 + Anpassungsstellen ohne
  `ci.yml`/`release.yml`/`OWNERSHIP.md` + `factory.lock` + `--compose`, Hooks installiert): **2466 grün, 0 rot**, 380 s,
  ohne Node/DB.
- **AK13 ✓:** macOS/bash 3.2 (oben) und `ubuntu-latest` (CI-Job `factory-self-test` grün, PR #54).
- **AK14 ✓:** Jede Gruppe räumt `T23` per EXIT-Trap auf (TERM → `exit 143` → Trap). Die Suite beendet und erwartet
  laufende Gruppen bei Ende, INT und TERM. Test F5: TERM an die Suite → Exit ≠ 0 binnen 10 s, Gruppe beendet, ihr
  Temp-Verzeichnis und die Logs sind weg (die Mutanten „kein kill“, „kein Weiterreichen“, „kein Shard-Trap“ werden rot).
- **AK15:** `scripts/checks/tests/**` und `lib/**` sind in `OWNERSHIP.md` schon Seite `factory`, also keine neue Zeile.
  F-22.5 bestätigt beide neuen Libs als ausgeliefert.
- **F1:** Scheitert der Aufbau, endet `factory_lock_setup` mit `exit 2` → die Gruppe zählt fail-closed als rot.
  **F2:** AK8-Fingerprint. **F3:** jede Gruppe sourct `assert-helpers.sh` (neutralisiert `GIT_*`).
  **F4:** `GITHUB_ACTIONS`/`GITHUB_OUTPUT` werden wie bisher ab #24 entfernt. Die Gate-Kommandos werden wie an der alten
  source-Stelle entfernt, `FACTORY_SELF_TEST_RUN` wird gesetzt. Selbstfund: Der eigene D1-Test erbte
  `FACTORY_SELF_TEST_SERIAL=1` aus der Suite und wurde seriell rot. Jetzt setzt der Treiber den Schalter immer selbst.
  **F5:** siehe AK14.

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
