# Task 45: ursprungs-stack-aus-skills-entfernen

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
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
- [ ] AK1 – Kein Gate-Versprechen ohne Gate (`implement.md`, `review.md`: keine Routen-Doku-/Drift-Check-Aussage)
- [ ] AK2 – Oberflächentests generisch (`implement.md`, `coding-agent.md`), alle Pflichten erhalten
- [ ] AK3 – Review-Agent generisch (kein `runAtomic`/`db.transaction()`/`db-drizzle.md`)
- [ ] AK4 – Codify-Themenliste nur Factory-Themen + Verweis auf Projekt-Lessons-Index
- [ ] AK5 – `pre-push.sh`: nur Kommentare geändert, kein Ursprungs-Werkzeug in Check 2/3
- [ ] AK6 – `*.tmp.spec.tsx` aus `gitignore.factory` und `.gitignore` entfernt, Zusammensetzungs-Guards grün
- [ ] AK7 – Lessons `testing.md`/`code-style.md` ohne langen C1-Begriff, Lehre unverändert
- [ ] AK8 – C1 erkennt Komposita der langen Begriffe (Negativtest je Begriff)
- [ ] AK9 – C1 ohne Fehlalarm (`match`, `switch`, `watch`, `neonatal`); `TCH`/`Neon`/`Vercel` als Wort weiter erkannt
- [ ] AK10 – C1 behält Herkunftsverweise und erlaubte Stellen
- [ ] AK11 – C1 grün auf dem Repo, fail-closed-Prüfung bleibt
- [ ] AK12 – Stack-Guard findet jeden Begriff, unabhängig von Groß-/Kleinschreibung, mit Datei und Zeile
- [ ] AK13 – Stack-Guard prüft nur die Anweisungstexte
- [ ] AK14 – Stack-Guard fail-closed bei leerer Dateiliste
- [ ] AK15 – Stack-Guard grün auf dem Repo
- [ ] AK16 – Checklisten-Kommentar an nothra/tch-gastro-services#428, im PR-Body verlinkt
- [ ] AK17 – `ownership-check.sh` grün

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
Kein ADR-Trigger erkannt (keine neue Gate-Verdrahtung, nur weitere Prüfung in der bestehenden
Projekt-Suite). `/architecture` entfällt.

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
Keine. Entscheidungen Q1–Q3 stehen in der Spec.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/45-ursprungs-stack-aus-skills-entfernen`
Erstellt: 2026-11-12 23:45
