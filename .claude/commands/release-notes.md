# /release-notes – Changelog für Release generieren

Dieser Skill aggregiert Commit-Messages, Task-Beschreibungen und Codify-Learnings
der letzten N abgeschlossenen Features zu einem strukturierten CHANGELOG-Eintrag.
Nützlich unmittelbar vor einem Release.

## Argument

`$ARGUMENTS` = Anzahl der letzten Features (Standard: 5).
Beispiele:
- `/release-notes`    → letzte 5 Features
- `/release-notes 10` → letzte 10 Features

## Kontext laden

- `docs/factory/PROJECT-CONTEXT.md` – Projektname, aktuelle Version
- `tasks/task-*.md` – die letzten N Task-Dateien (nach Änderungsdatum sortiert)
- `tasks/codify-*.md` – zugehörige Codify-Reports (falls vorhanden)
- Git-Log der letzten 100 Commits: `git log --oneline --no-merges -100`

## Aufgabe

### 1. Features identifizieren

Bestimme die letzten N abgeschlossenen Features.
Sortiere nach Task-ID (numerisch absteigend) – nicht nach Änderungszeit,
da `/codify` ältere Task-Dateien nachträglich anfassen kann:
```bash
ls tasks/task-*.md | sort -t- -k2 -n | tail -${ARGUMENTS:-5}
```
Ermittle die zugehörigen Task-IDs aus den Dateinamen.

### 2. Pro Feature sammeln

Für jede Task-ID:
- **Titel und Beschreibung** aus `tasks/task-<id>.md` (erste `# `-Zeile)
- **Commit-Messages** des Feature-Branches aus dem Git-Log, gefiltert nach Task-ID
  (Pattern: `task-<id>`, `#<id>`, `feat(<id>)`, etc.)
- **Neue Regeln** aus `tasks/codify-<id>.md` unter "Neue Regeln hinzugefügt" (falls vorhanden)
- **Kategorie** ableiten aus Conventional-Commit-Präfixen:
  - `feat:` / `feat(…):` → Added
  - `fix:` / `fix(…):` → Fixed
  - `refactor:` → Refactored
  - `docs:` → Documentation
  - `test:` → Testing
  - `chore:` / sonstige → Changed

### 3. CHANGELOG-Eintrag generieren

Strukturiere den Eintrag nach [Keep a Changelog](https://keepachangelog.com):

```markdown
## [Unreleased] – YYYY-MM-DD

### Added
- Kurze Beschreibung des Features (#task-id)

### Changed
- Beschreibung der Änderung (#task-id)

### Fixed
- Beschreibung des Bugfixes (#task-id)

### Refactored
- Beschreibung des Refactorings (#task-id)
```

Regeln für gute Einträge:
- Aus Nutzersicht formulieren, nicht aus Implementierungssicht
- Maximal eine Zeile pro Feature
- Interne Refactorings und technische Schulden in "Refactored" bündeln
- Leere Abschnitte weglassen

### 4. Ausgabe

Schreibe den Eintrag in `docs/CHANGELOG.md`:
- Falls die Datei existiert: neuen Eintrag oben einfügen (nach dem Header)
- Falls nicht: Datei neu anlegen mit Standard-Header:

```markdown
# Changelog

Alle nennenswerten Änderungen an diesem Projekt.
Format: [Keep a Changelog](https://keepachangelog.com)
```

Gib den generierten Eintrag zusätzlich auf der Konsole aus.

## Hinweis

`/release-notes` erzeugt einen ersten Entwurf – immer vor dem Release-Tag gegenlesen.
Es ersetzt kein manuelles Release-Review, aber spart die initiale Aufbereitung.
