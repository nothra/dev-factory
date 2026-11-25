## Codify-Report: Task 70

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` + Zeile in `lessons/INDEX.md` (Gruppe `testing`) – **Gate-Skript mit `Producer | grep -q`
  im `if` ist fail-open; Guard und Test auf Produktivskripte ausweiten** – wegen: `pre-commit.sh` ließ bei großem Diff und
  frühem Treffer den Commit durch (SIGPIPE + `pipefail`); der Guard `pipe_grep_q_lines` lief nur über Test-Suiten.
- `docs/factory/lessons/factory-workflow.md` + Zeile in `lessons/INDEX.md` – **CHANGELOG-Eintrag gehört zur Änderung an
  ausgelieferten Dateien, nicht erst zum Release** – wegen: Review-Finding W1 (Eintrag unter `## Unreleased` fehlte nach
  `/implement`).

### Außerhalb der Lessons erledigt
- `CHANGELOG.md`: Eintrag `### Behoben` unter `## Unreleased` nachgezogen (Review-W1 war bis dahin offen).
- Kleinfunde (`factory-update.sh:77`, `start-work.sh:310`) stehen bereits in `docs/factory/kleinfunde.md`; unterhalb der
  Schwelle (ADR-043), kein Issue.

### Keine Änderungen nötig
- `CLAUDE.md`/Guidelines: `bash-gotchas.md` §3 deckt die Regel bereits ab; die Lücke war der Geltungsbereich des Guards,
  nicht die Regel – das steht jetzt als Lesson (b).
- Kein neuer Check: der Guard AK8 erfasst `pre-commit.sh` bereits.

### Empfehlung für nächste Features
- Beim Einführen oder Erweitern eines Fehlerklassen-Guards zuerst `git ls-files '*.sh'` gegen den Geltungsbereich prüfen.
- Ein Folge-Issue für die zwei Kleinfund-Stellen lohnt erst, wenn dort ein reproduzierbarer Auslöser auftaucht.
