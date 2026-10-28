# Task 32: import-deckel-test-fixture

## Status
- [x] In Bearbeitung
- [x] Review bestanden
- [x] Tests vollständig
- [x] Security-Review bestanden
- [x] Refactoring abgeschlossen
- [x] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Der @import-Deckel-Test der ausgelieferten Suite liest über `import-context-limit-check.sh` `CLAUDE.md` und
`PROJECT-CONTEXT.md` des Konsumenten (indirekter Leser, vom AK6-Guard aus #28 nicht erfasst). Fix: Test aus der
ausgelieferten Suite in die Projekt-Suite verschieben, AK6-Guard um indirekte Leser erweitern.
Spec: `docs/specs/spec-32-import-deckel-test-fixture.md`.

## Akzeptanzkriterien
<!-- Von /requirements befüllt oder manuell eingeben -->
- [x] **AK1** Kein Falsch-Rot der ausgelieferten Suite durch fehlende/aufgeblähte Konsumenten-Dateien (Fixture-Lauf)
- [x] **AK1a** Ausgelieferte Suite prüft die Dauerkontext-Größe des echten Repos nicht (Projekt-QS, keine Factory-Funktionsprüfung – Entscheidung Mensch)
- [x] **AK2** Deckel-Verhaltenstests bleiben vollständig; nur der Aufruf gegen die echte Wurzel entfällt
- [x] **AK3** Projekt-Suite (Projekt-QS) prüft den realen @import-Stand (Mutation belegt)
- [x] **AK4** AK6-Guard (#28) erkennt Check-Skript-Aufrufe gegen die echte Wurzel (Negativfall, Kontrolle, fail-closed)
- [x] **AK5** Erweiterter Guard im Ist-Stand grün oder weitere Treffer behoben/mit Issue dokumentiert
- [x] **AK6** Gates und beide Suiten grün

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->
- Kein ADR-Trigger (Änderung einer Test-Zuordnung nach Factory-ADR-064 D6).
- Realstand-Test lebt bereits in der Projekt-Suite (`#431 AK-D5`); die Dublette in der ausgelieferten Suite entfällt, die Projekt-Suite gibt bei Rot die Breakdown-Liste aus.
- Guard `#28 AK6` erkennt zusätzlich `FACTORY_DIR|FACTORY_ROOT|REPO_ROOT=<echte Wurzel> bash …`; Mutant-Zeilen werden zur Laufzeit gebaut (kein Selbsttreffer).
- AK5-Zusatzfund (vom Guard nicht erkennbar, im Fixture-Lauf gefunden): `#149`-Test rief `pre-push.sh` des echten Repos auf, dessen Check 6 liest die echte `CLAUDE.md` – behoben im selben PR, indem der Test eine Gate-Kopie in der Wegwerf-Wurzel nutzt.
- Belege: Fixture-Läufe der ausgelieferten Suite (mit / ohne `PROJECT-CONTEXT.md` / `CLAUDE.md` +400 Zeilen) je 1904 grün, 0 rot; Projekt-Suite mit aufgeblähter `CLAUDE.md` rot (Mutation).

## Offene Fragen
- Lösungsort der Realstand-Assertion und Erkennungsmuster des Guards → `/architecture` bzw. `/implement` (siehe Spec)

## Test-Notizen
- Kein Coverage-Werkzeug für Bash; Vollständigkeit je AK geprüft. Ergänzt: Guard-Test für die `env FACTORY_DIR=… bash`-Form (Suite jetzt 1905 grün).
- Mutationsbeleg zeigte: `(env[[:space:]]+)?` im Guard-Muster ist redundant (kein Zeilenanfangs-Anker, `env`-Zeile trifft auch ohne) – Vereinfachung an `/refactor` übergeben.

## Refactoring-Notizen
- Redundantes `(env[[:space:]]+)?` aus dem Guard-Muster entfernt (Test für die `env`-Form bleibt grün); Blindstellen des Guards im Kommentar benannt (Review-Nitpick 1). Kein neues Verhalten, Suite 1905 grün.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `fix/32-import-deckel-test-fixture`
Erstellt: 2026-10-27 10:28
