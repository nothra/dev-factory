# Task 47: copy-files-konfigurierbar

## Status
- [ ] In Bearbeitung
- [ ] Review bestanden
- [ ] Tests vollständig
- [ ] Security-Review bestanden
- [ ] Refactoring abgeschlossen
- [ ] Codify ausgeführt
- [ ] Fertig / PR erstellt

## Beschreibung
Die feste `.env.local`-Spiegelung in `start-work.sh` wird durch den Config-Schlüssel
`start_work.copy_files` (Liste von Dateipfaden, Default `[]`) ersetzt. Die Schutzlogik bleibt
(nie überschreiben, Modus erhalten, Aufräumen, kein Abbruch). `start_work.hint` wird von der Kopie
entkoppelt, Opt-out heißt `FACTORY_WT_SKIP_COPY` (Alias `FACTORY_WT_SKIP_ENV`), und der
Ursprungs-Wortlaut verschwindet aus Skript und Tests.
Spec: [`docs/specs/spec-47-copy-files-konfigurierbar.md`](../docs/specs/spec-47-copy-files-konfigurierbar.md)

## Akzeptanzkriterien
<!-- Details, GIVEN/WHEN/THEN und Fehlerszenarien F1–F8: siehe Spec -->
- [ ] AK1 – Default `[]` kopiert nichts
- [ ] AK2 – genau die gelisteten Dateien werden byte-identisch gespiegelt
- [ ] AK3 – Modus der Quelle bleibt erhalten
- [ ] AK4 – vorhandenes Ziel (Datei/Symlink) wird nie überschrieben, übrige Einträge laufen weiter; Mutationsbeleg
- [ ] AK5 – fehlende Elternordner werden im Worktree angelegt
- [ ] AK6 – Symlink als Quelle wird als echte Datei kopiert
- [ ] AK7 – `FACTORY_WT_SKIP_COPY=1` unterdrückt die Spiegelung
- [ ] AK8 – `FACTORY_WT_SKIP_ENV=1` wirkt als Alias
- [ ] AK9 – Output nennt den Opt-out-Schalter
- [ ] AK10 – `start_work.hint` erscheint auch ohne Kopie
- [ ] AK11 – `start_work.hint` erscheint auch im In-Place-Modus und bei Opt-out
- [ ] AK12 – leerer Hinweis → keine Hinweis-Zeile
- [ ] AK13 – Config-Gate nimmt gültige Liste an
- [ ] AK14 – Config-Gate lehnt absolut / `..` / leer / Nicht-String / Skalar statt Liste / abschließendes `/` ab
- [ ] AK15 – Konsument mit `[".env.local"]` behält sein Verhalten (Verhaltenstest)
- [ ] AK16 – kein Ursprungs-Wortlaut in `start-work.sh` und Testgruppe
- [ ] AK17 – Doku (FACTORY.md Regel 8, git-workflow.md, OPERATING.md, .gitignore-Kommentare, CHANGELOG mit Migrationszeile) nachgezogen
- [ ] AK18 – alle Gates grün
- [ ] Fehlerszenarien F1–F8 getestet

## Technische Notizen
<!-- Von /architecture befüllt oder eigene Notizen -->

## Offene Fragen
- [ ] ADR-Trigger? Vermutlich nur Nachtrag zu Factory-ADR-063 Q4 (Kopplung `start_work.hint` ↔ `.env.local` dort beschrieben) – `/architecture` entscheidet.

## Review-Findings
<!-- Wird durch /review befüllt -->

## Codify-Notizen
<!-- Wird durch /codify befüllt – Learnings dieser Task -->

---
Branch: `feature/47-copy-files-konfigurierbar`
Erstellt: 2026-11-01 19:17
