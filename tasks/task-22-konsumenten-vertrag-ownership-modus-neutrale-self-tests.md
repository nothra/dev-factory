# Task 22: konsumenten-vertrag-ownership-modus-neutrale-self-tests

## Status
- [x] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Konsumenten-Vertrag der Factory (T2a-1): `ownership-check.sh` mit zwei Modi (Lock / `OWNERSHIP.md`),
`OWNERSHIP.md` projekteigen, Self-Test-Suite konsumenten-neutral. Spec: `docs/specs/spec-22-konsumenten-vertrag.md`.
Kein Release in #22.

## Akzeptanzkriterien
- [x] AK2.15a Lock-Modus: Seite `factory` = Lock-Pfadmenge, keine `OWNERSHIP.md` nötig
- [x] AK2.15a-2 `--list factory|project` im Lock-Modus
- [x] AK2.15a-3 Lock entscheidet allein, wenn auch `OWNERSHIP.md` existiert; Modus wird ausgegeben
- [x] AK2.15b Fehlender Lock-Pfad oder Anpassungsstelle im Lock → Exit 1 mit Pfad
- [x] AK2.15b-2 Mitgelieferte Anpassungsstellen-Liste, Drift-Guard gegen `OWNERSHIP.md`
- [x] AK2.15c Factory-Repo ohne Lock: Tabellenmodus unverändert
- [x] AK2.15d-0 `OWNERSHIP.md` nicht mehr im Release-Manifest (Seite `project`)
- [x] AK2.16a Ausgelieferte Self-Test-Suite läuft im Konsumenten grün
- [x] AK2.16b Factory-spezifische Prüfungen nach `scripts/project/tests/`, nichts ersatzlos entfallen
- [x] AK2.16b-2 CI und `pre-push.sh` führen `scripts/project/tests/` mit aus
- [x] AK2.16b-3 Neue Dateien in `OWNERSHIP.md` zugeordnet
- [x] F-22.1 bis F-22.5 Fehlerszenarien (siehe Spec)

## Technische Notizen
ADR 064 (`docs/factory/adr/064-konsumenten-vertrag-lock-als-ownership-quelle.md`, Proposed → mit Umsetzung auf Accepted):
- Lock = Release-Manifest (JSON, `schema` 1), gelesen per `jq`; Lock-Modus wenn `factory.lock` existiert, kein Mischmodus.
- Fail-closed: Exit 2 bei unlesbarem/ungültigem Lock, fehlendem `jq` oder fehlender Anpassungsstellen-Liste; Exit 1 bei fehlendem/doppeltem Lock-Pfad oder Anpassungsstelle im Lock.
- Anpassungsstellen: `scripts/checks/customization-points.txt` (Seite `factory`), Teilmenge der `project`-Zeilen.
- `OWNERSHIP.md` → Seite `project`; `scripts/project/**` braucht eine `project`-Zeile.
- Test-Schnitt nach `scripts/project/tests/`; Aufruf über `pre-push.d/` und `ci.yml`. Zuerst Inventar (Testgruppe → Assertions), dann verschieben.
- Commit-Reihenfolge: Lock-Modus mit Tests → `OWNERSHIP.md` → Test-Schnitt → Verdrahtung.

## Offene Fragen
- [x] Q-22.4 Lock-Format: JSON wie `factory-release.json` (ADR 064 D1)
- [ ] Q-22.5 #23 darf `OWNERSHIP.md` nicht als zu liefernde Datei erwarten
- [ ] Issue-Body #22 nennt „je Factory-Task ein Release", die Spec entscheidet „kein Release in #22" – Issue anpassen

## Umsetzungs-Notizen (/implement, 2026-10-24)

**Commits:** (a) Lock-Modus + Tests + `customization-points.txt` · (b) `OWNERSHIP.md` → `project`, Projekt-Suite mit Drift-Guard ·
(c)+(d) Test-Schnitt und Verdrahtung in einem Commit (der Schnitt und die Wiring-Tests hängen an derselben Suite).

**Belege je AK**
- AK2.15a/a-2/a-3/b, F-22.1/.3/.4: 35 Assertions in `scripts/checks/tests/run-tests.sh` (Block „Konsumenten-Vertrag"), RED vor GREEN (31 rot → 0 rot);
  F-22.1 „kein `jq`" bricht die Messung per PATH-Stub, nicht nur den Input; F-22.2 über fehlende Liste.
- AK2.15b-2: Drift-Guard in `scripts/project/tests/run-tests.sh`, je Richtung ein Negativtest mit pfadspezifischem Signal + Fail-closed bei fehlender Quelle.
  Die Liste ist Teilmenge der `project`-Zeilen; `PROJECT-CONTEXT.md` nennt die Anpassungsstellen jetzt mit vollem Pfad.
- AK2.15c: die Tabellen-Tests blieben unverändert. Einzige Änderung: sie setzen `FACTORY_LOCK_FILE=/nicht/vorhanden/factory.lock`, damit ein
  `factory.lock` im Konsumenten sie nicht in den Lock-Modus zieht.
- AK2.15d-0 (Manifest vorher `3557ae1` / nachher `HEAD`, je 114 Pfade): `- docs/factory/OWNERSHIP.md`, `+ scripts/checks/customization-points.txt`, sonst identisch.
- AK2.16a: Konsumenten-Fixture (Dateien der Seite `factory` + eigene Anpassungsstellen + `factory.lock` aus dem Manifest, Hooks installiert):
  ausgelieferte Suite **1648 grün, 0 rot**. Vor dem Schnitt waren es 44 rot.
- AK2.16b/b-3, F-22.5: Zählvergleich unten, beide Suiten brechen ohne `assert-helpers.sh` mit Exit 2 ab (vorher: `command not found` und Weiterlauf); `ownership-check.sh` grün (132 Dateien: factory 114, project 18).
- AK2.16b-2: `scripts/project/checks/pre-push.d/10-project-tests.sh` + Job `project-self-test` in `ci.yml`; Wiring an den echten Aufrufzeilen, Verhalten des Hooks
  (grün/rot) und je eine Mutation (ohne `run:`-Zeile, ohne yq-Schritt).

**Zählvergleich Assertions** (Summe vorher = Summe nachher, abzüglich neuer Prüfungen)

| | ausgelieferte Suite | Projekt-Suite | Summe |
|---|---|---|---|
| vorher (Commit b) | 1737 | 25 (Drift-Guard) | 1762 |
| nachher | 1648 | 132 | 1780 |
| davon neu durch diese Task | 3 (F-22.5: Lib/Fixtures sind `factory`) | 7 Wiring + 2 Kopplungsschutz des Hooks + 1 Aufteilung AK-F4 (Skriptpfade je Workflow-Satz) + 5 (F-22.5: Suite ohne Lib bricht hart ab) | 18 |

1762 + 18 = 1780 → keine Prüfung entfallen. Verschoben wurden 92 Assertions in 29 Gruppen (Gruppen siehe Kopfzeilen `# ── verschoben aus der
ausgelieferten Suite: …` in `scripts/project/tests/run-tests.sh`): Prüfungen, die `ci.yml`, `release.yml`, `OWNERSHIP.md`, `CLAUDE.md`,
`CONTRIBUTING.md`, `README.md`, `PROJECT-CONTEXT.md`, `factory.config.yml`, die zusammengesetzte `.gitignore` oder die Git-Historie dieses Repos lesen.
Geteilte Helfer (`cp_pipeline_libs`, `bare_factory_adr_426`) wanderten dafür nach `scripts/checks/tests/lib/assert-helpers.sh`.

**Nicht-offensichtliche Entscheidungen**
- Die ausgelieferte Suite exportiert `FACTORY_SELF_TEST_RUN=1`; der Projekt-Hook startet dann nichts. Ohne das ruft die Suite über `pre-push.sh` (#149, #265 …)
  die Projekt-Suite dreimal verschachtelt auf, und deren Rot färbte unbeteiligte Gate-Tests falsch rot.
- C1 (Herkunftsbegriffe) läuft nur in der Projekt-Suite über alle getrackten Dateien; ein Konsument besitzt eigene Dateien mit eigenen Begriffen.
  Folge: die Spec `spec-22-…md` musste neutral umformuliert werden (der Guard war schon vor dieser Task durch sie rot).
- AK-B1 (Liste der Factory-ADRs) um `064` ergänzt – war seit dem ADR-Commit rot.
- Der Hook `10-project-tests.sh` liegt unter `scripts/project/**` (Seite `project`); er wird nie ausgeliefert.

**Umgebungsbedingt rot (nicht durch diese Task):** `#149 konform …` und `#149 leerer FACTORY_FORMAT_COMMAND …` – beide verlangen installierte Git-Hooks
(`hooks-installed-check.sh`). In CI installiert `factory-self-test` sie vorher; im Fixture mit `install-hooks.sh` grün (1645/0). In diesem Worktree wurden
die Hooks bewusst nicht installiert (geteiltes `.git`).

**Offen / Folgearbeit**
- `ci.yml` hat jetzt den Job `project-self-test`. Der Ruleset `protect-main` verlangt ihn erst, wenn er dort als Required Check eingetragen ist (GitHub-Setting, nicht in dieser Task).
- Skills und Doku (`/codify`, `/review`, `/security-review`) nennen `docs/factory/OWNERSHIP.md` als Zuordnungstabelle; im Lock-Modus eines Konsumenten gibt es sie nicht.
  Doku-Anpassung gehört zur Erst-Einbindung (T2a-4), die Tests (AK-C5/AK-L1) prüfen den heutigen Wortlaut.
- Q-22.5 (#23 darf `OWNERSHIP.md` nicht als zu liefernde Datei erwarten) und die Anpassung des Issue-Body #22 („je Task ein Release") bleiben offen.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/22-konsumenten-vertrag-ownership-modus-neutrale-self-tests`
Erstellt: 2026-10-24 17:01
