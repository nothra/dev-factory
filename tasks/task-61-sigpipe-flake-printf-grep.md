# Task 61: sigpipe-flake-printf-grep

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
SIGPIPE-Race `printf … | grep -q` unter `pipefail` in den Self-Test-Suiten beseitigen: Helfer `assert_contains_286` /
`assert_absent` robust machen, alle Fundstellen in `scripts/checks/tests/**` und `scripts/project/tests/**` umstellen,
Guard gegen Wiedereinführung. Schließt #15 ein (gleiche Ursache über `assert_contains_286`).
Spec: [`docs/specs/spec-61-sigpipe-flake-printf-grep.md`](../docs/specs/spec-61-sigpipe-flake-printf-grep.md)
PR-Body: `Closes #61`, `Closes #15`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [ ] AK1 – `assert_contains_286` robust: ≥1-MB-Haystack, Phrase in Zeile 1, 200× unter `pipefail` → immer grün, kein `Broken pipe`
- [ ] AK2 – `assert_absent` ohne Falsch-Grün: Phrase vorhanden → 200× rot; Phrase fehlt → grün
- [ ] AK3 – Helfer-Semantik unverändert: `-`-Phrase und Regex-Zeichen als fester Text; leerer Haystack → `assert_contains_286` rot
- [ ] AK4 – Guard: Pipe aus `printf`/`echo` in `grep -q…` unter `scripts/checks/tests/`, `scripts/project/tests/` → rot mit Datei:Zeile
- [ ] AK5 – Guard-Mutationsbeleg: Muster rot; Here-String / `grep … <datei>` grün; Kommentarzeilen lösen nicht aus
- [ ] AK6 – Bestand sauber: Guard findet nichts; Haupt- und Projekt-Suite grün; Assertion-Zahl vor/nach im PR genannt
- [ ] AK7 – CI-Beleg #61: `factory-self-test` 10× grün, kein `Broken pipe`, Lauf-Links im PR-Body
- [ ] AK8 – #15 abgedeckt: Test „#334 (Review-Finding 1): der add-ok/commit-fehlgeschlagen-Zweig …“ in allen Läufen grün
- [ ] AK9 – Lesson `lessons/testing.md` verweist auf den Guard, kein Widerspruch zum neuen Helfer-Verhalten
- [ ] Produktiv-Fundstellen (nicht im Scope) als `kleinfunde.md`-Eintrag bzw. Issue nach Schwelle Factory-ADR-043

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
<!-- Fragen, die noch geklärt werden müssen -->
- Keine fachlichen. Kein ADR-Trigger erwartet (`/architecture` entfällt).
- Entscheidungen Mensch 2026-11-22: #15 im Scope; Guard ja; CI-Beleg per 10 Job-Läufen; Produktiv-Skripte nicht im Scope.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/61-sigpipe-flake-printf-grep`
Erstellt: 2026-11-22 13:51
