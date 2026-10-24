# Task 22: konsumenten-vertrag-ownership-modus-neutrale-self-tests

## Status
- [ ] In Bearbeitung
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
- [ ] AK2.15a Lock-Modus: Seite `factory` = Lock-Pfadmenge, keine `OWNERSHIP.md` nötig
- [ ] AK2.15a-2 `--list factory|project` im Lock-Modus
- [ ] AK2.15a-3 Lock entscheidet allein, wenn auch `OWNERSHIP.md` existiert; Modus wird ausgegeben
- [ ] AK2.15b Fehlender Lock-Pfad oder Anpassungsstelle im Lock → Exit 1 mit Pfad
- [ ] AK2.15b-2 Mitgelieferte Anpassungsstellen-Liste, Drift-Guard gegen `OWNERSHIP.md`
- [ ] AK2.15c Factory-Repo ohne Lock: Tabellenmodus unverändert
- [ ] AK2.15d-0 `OWNERSHIP.md` nicht mehr im Release-Manifest (Seite `project`)
- [ ] AK2.16a Ausgelieferte Self-Test-Suite läuft im Konsumenten grün
- [ ] AK2.16b Factory-spezifische Prüfungen nach `scripts/project/tests/`, nichts ersatzlos entfallen
- [ ] AK2.16b-2 CI und `pre-push.sh` führen `scripts/project/tests/` mit aus
- [ ] AK2.16b-3 Neue Dateien in `OWNERSHIP.md` zugeordnet
- [ ] F-22.1 bis F-22.5 Fehlerszenarien (siehe Spec)

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

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/22-konsumenten-vertrag-ownership-modus-neutrale-self-tests`
Erstellt: 2026-10-24 17:01
