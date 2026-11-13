# Task 45: ursprungs-stack-aus-skills-entfernen

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [x] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [x] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Rest von AK-K1 (spec-426): Stack-Details des Ursprungs-Projekts aus den ausgelieferten
Anweisungstexten entfernen (Skills, Agent-Personas, Guidelines, `pre-push.sh`-Kommentare,
`gitignore.factory`), Herkunftsbegriff aus zwei Lessons entfernen, C1-Guard auf Komposita erweitern,
neuen Stack-Begriff-Guard in der Projekt-Suite anlegen, Übergabe-Kommentar an
nothra/tch-gastro-services#428.

Spec: [`docs/specs/spec-45-ursprungs-stack-aus-skills-entfernen.md`](../docs/specs/spec-45-ursprungs-stack-aus-skills-entfernen.md)

## Akzeptanzkriterien
<!-- Volltext je AK in der Spec -->
- [x] AK1 – Kein Gate-Versprechen ohne Gate (`implement.md`, `review.md`: keine Routen-Doku-/Drift-Check-Aussage) – als Patch geliefert, Mensch wendet an
- [x] AK2 – Oberflächentests generisch (`implement.md` als Patch, `coding-agent.md` erledigt), alle Pflichten erhalten
- [x] AK3 – Review-Agent generisch (kein `runAtomic`/`db.transaction()`/`db-drizzle.md`)
- [x] AK4 – Codify-Themenliste nur Factory-Themen + Verweis auf Projekt-Lessons-Index – als Patch geliefert, Mensch wendet an
- [x] AK5 – `pre-push.sh`: nur Kommentare geändert, kein Ursprungs-Werkzeug in Check 2/3
- [x] AK6 – `*.tmp.spec.tsx` aus `gitignore.factory` (erledigt) und `.gitignore` (als Patch) entfernt, Zusammensetzungs-Guards grün nach Apply
- [x] AK7 – Lessons `testing.md`/`code-style.md` ohne langen C1-Begriff, Lehre unverändert
- [x] AK8 – C1 erkennt Komposita der langen Begriffe (Negativtest je Begriff)
- [x] AK9 – C1 ohne Fehlalarm (`match`, `switch`, `watch`, `neonatal`); kurze C1-Begriffe als ganzes Wort weiter erkannt
- [x] AK10 – C1 behält Herkunftsverweise und erlaubte Stellen
- [x] AK11 – C1 grün auf dem Repo, fail-closed-Prüfung bleibt
- [x] AK12 – Stack-Guard findet jeden Begriff, unabhängig von Groß-/Kleinschreibung, mit Datei und Zeile
- [x] AK13 – Stack-Guard prüft nur die Anweisungstexte
- [x] AK14 – Stack-Guard fail-closed bei leerer Dateiliste
- [x] AK15 – Stack-Guard grün auf dem Repo – grün nach Apply des Patches (in Wegwerf-Kopie belegt)
- [ ] AK16 – Checklisten-Kommentar an nothra/tch-gastro-services#428, im PR-Body verlinkt – Entwurf liegt vor, Freigabe zum Posten ausstehend
- [x] AK17 – `ownership-check.sh` grün

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Kein ADR-Trigger erkannt (keine neue Gate-Verdrahtung, nur weitere Prüfung in der bestehenden
Projekt-Suite). `/architecture` entfällt.

**Umsetzung (/implement, 2026-11-13):**
- C1-Guard in `scripts/project/tests/run-tests.sh`: Begriffsliste in `C1_LONG_TERMS` (Wortteil-Treffer) und
  `C1_SHORT_TERMS` (Ganzwort-Treffer) geteilt; Scan und Tests nutzen dieselben Funktionen `c1_hits_in` und
  `c1_allowed_place`, damit die Tests den echten Guard prüfen und keine Kopie.
- Stack-Guard `stack_hits_45` direkt daneben; Exit 0/1/2 (sauber/Treffer/fail-closed). Tests in einer
  Wegwerf-Kopie (nur `git add`, kein Commit, also keine Git-Identität nötig).
- Mutationsbeleg (Wegwerf-Lauf): lange Begriffe wieder als Ganzwort → 6 rote AK8-Tests; Guard ohne `-i` →
  12 rote AK12-Tests (Großschreibung); fail-closed-Zählung entfernt → 2 rote AK14-Tests.
- Der AK13-Fixture-Dateiname unter `docs/factory/adr/` wird zur Laufzeit zusammengesetzt, sonst meldet
  `adr-links-check.sh` (ausgelieferte Suite, #426 AK-B3) ihn als toten ADR-Link.
- `implement.md`: neben Playwright/`e2e/`/`webServer` auch `proxy.ts`, `.env.local`, `reuseExistingServer` und
  „Preview-Config `dev`" generisch formuliert (AK2: keine Werkzeug-, Pfad- oder Config-Namen eines Stacks).
- Hinweis außerhalb des Scopes: `docs/factory/guidelines/git-workflow.md` (Hook-Tabelle, „Format (Prettier),
  Routen-Doku-Drift") und der Kommentar zu Check 4 in `pre-push.sh` nannten weiter den Routen-Doku-Drift-Check
  des Ursprungs-Projekts. Im Rework zu Review-Iteration 1 (W2) mitgenommen, der Kleinfund-Eintrag ist damit
  wieder entfernt.

**Rework nach `/review` Iteration 1 (2026-11-13):**
- W1: je Pfad aus Scope 4 der Spec ein Fixture-Test „rot mit Datei und Zeile" (Orakel-Liste `SPEC_FILES_45`
  bewusst unabhängig von `STACK_PATHS_45`) und am echten Baum je Pfad „hat getrackte Dateien". Mutationsbeleg
  (Wegwerf-Wrapper, selbstlöschend): je gestrichenem Pfad (`pre-push.sh`, `guidelines`, `gitignore.factory`,
  `agents`) wird genau dessen AK12-Pfadtest rot; ohne `agents` zusätzlich der AK14-Lesbarkeitstest.
- W2: Hook-Tabelle in `git-workflow.md` und Kommentar zu Check 4 in `pre-push.sh` generisch („projekteigene
  Checks aus `pre-push.d/`"). Gehört in den Übergabe-Kommentar (AK16) mit.
- W3: Umsetzung committet (roher `git commit`, weil `factory-commit.sh` immer pusht), Push bleibt bis nach dem
  Patch-Apply zurückgehalten.
- Nitpick 1: toter Pfad `lessons/frontend-react.md` in `lessons/testing.md` durch Verweis auf die Projekt-Lesson
  ersetzt. Nitpick 2 (`app/`, `db/`, `lib/` in `codify.md`): nicht umgesetzt, Kontextzeile des Patches, nicht in
  der Begriffsliste.

**Erledigt 2026-11-13 (Blocker aufgelöst): `.claude/**` und `.gitignore` sind für den Agenten gesperrt – Mensch hat angewendet:
`git apply tasks/patch-45.diff` an.** Der Patch (programmatisch erzeugt, `git apply --check` grün) ändert
`.claude/commands/implement.md`, `review.md`, `codify.md` und `.gitignore`. In einer Wegwerf-Kopie mit
angewendetem Patch ist die Projekt-Suite grün (245 grün, 0 rot). Ohne Patch sind dort 3 Tests rot (AK15 und die
beiden `.gitignore`-Zusammensetzungs-Guards). Die übrigen Dateien sind committet; nur der **Push** wartet,
weil der pre-push-Hook die Projekt-Suite ausführt und diese drei Tests ihn blockieren würden. Nach dem Apply:
Patch-Datei entfernen, `[~]` auf `[x]` setzen, committen und pushen.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
Keine. Entscheidungen Q1–Q3 stehen in der Spec.

## Review-Findings
<!-- Wird durch /review befüllt -->
Iteration 1 (2026-11-13): **NEEDS_REWORK** – 0 kritisch, 3 wichtig, 3 Nitpicks, Details in
[`review-45.md`](review-45.md). W1: Stack-Guard prüft nachweislich nur `.claude/commands/`, die
anderen vier Pfade sind ungetestet. W2: Routen-Doku-Drift-Gate noch in `git-workflow.md:72` und
`pre-push.sh:86-87` (als Kleinfund verankert, Mitnahme empfohlen). W3: Umsetzung committen, nur
den Push zurückhalten. → W1–W3 und Nitpick 1 im Rework behoben (siehe Technische Notizen).

Iteration 2 (2026-11-13): **APPROVED** – 0 kritisch, 0 wichtig, 5 Nitpicks (Lesson
`build-tooling.md:32` nennt `*.tmp.spec.tsx` noch als ignoriert, doppelte Pfad-Orakel-Liste,
`sed`-Ersetzung mit ungeschütztem Dateinamen, Anführungszeichen in `codify.md`, AK16 offen).
Projekt-Suite ohne Patch: 252 grün, 3 rot (die drei erwarteten, grün erst nach dem Apply).

## Test-Notizen
`/test` (2026-11-13): Projekt-Suite 252 grün, 3 rot (die drei erwarteten, grün erst nach `git apply
tasks/patch-45.diff`). Je AK ein Test: AK8/AK9/AK10 (C1, je Begriff), AK11 (bestehender
fail-closed-Test „liest die getrackten Dateien“), AK12 (je Begriff in Groß-/Kleinschreibung, je Pfad),
AK13, AK14 (leer, falsche Wurzel, unlesbar), AK15 (Pfade getrackt + Repo-Lauf), AK17 (ausgelieferte
Suite). AK1–AK4, AK6, AK7 sind inhaltlich vom Stack-Guard (AK15) bzw. C1-Scan (AK11) mitgeprüft. Keine
neuen Tests nötig, kein Produktionscode geändert. Coverage-Werkzeug gibt es für Bash hier nicht.

## Refactor-Notizen
`/refactor` (2026-11-13): zwei kleine Umbauten in `scripts/project/tests/run-tests.sh`, kein neues Verhalten.
`c1_hits_in` ersetzt den Herkunftsverweis nur noch einmal (statt zweimal `sed` je Datei). `stack_hits_45` setzt
den Dateinamen per `awk -v` vor die Treffer statt per `sed`-Ersetzung – ein Dateiname mit `#` bricht den
Ausdruck nicht mehr (Review-Nitpick). Projekt-Suite vorher/nachher identisch: 252 grün, 3 rot (die drei
erwarteten, grün erst nach `git apply tasks/patch-45.diff`). Nicht angefasst: doppelte Pfad-Orakel-Liste
(bewusst unabhängig, siehe Kommentar), `build-tooling.md:32` (Lesson-Historie, Codify).

## Codify-Notizen
`/codify` (2026-11-13): zwei Lesson-Einträge (Mehrpfad-Guard in `testing.md`, Patch-gesperrte Guard-Ziele als Index-Zeile), `build-tooling.md` nachgeführt. Details: [`codify-45.md`](codify-45.md).

---
Branch: `fix/45-ursprungs-stack-aus-skills-entfernen`
Erstellt: 2026-11-12 23:45

Blocker 2026-11-13: Pipeline pausiert – PUSH_GATE_BLOCKED: Push wartet auf Mensch: tasks/patch-45.diff (.claude/** + .gitignore) ist nicht angewendet, 3 Projekt-Suite-Tests (AK15 + 2 gitignore-Guards) blockieren den pre-push-Hook; 6 Commits unpushed (origin/fix/45 steht auf 63c8be3). Zusätzlich offen: AK16 (Kommentar an nothra/tch-gastro-services#428 zum Posten freigeben). Ablauf: git apply tasks/patch-45.diff, Patch-Datei entfernen, [~]->[x], committen, pushen, dann /pr-shepherd erneut. (/architecture ausführen, dann Pipeline neu starten)
