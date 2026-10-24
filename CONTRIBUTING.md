# Mitarbeit an der Factory

Das Repo entwickelt sich mit der eigenen Factory. Der Ablauf ist derselbe wie in jedem Projekt, das
sie nutzt – Regeln im Detail: [`docs/factory/FACTORY.md`](docs/factory/FACTORY.md).

## Einrichtung

```bash
bash scripts/install-hooks.sh   # idempotent; installiert pre-commit, pre-push und den commit-msg-Hook
```

Der `commit-msg`-Hook lehnt Messages ab, die in Wahrheit ein CLI-Flag sind (`--help`/`-h`). Die Hooks
sind lokales, umgehbares Feedback; serverseitig schützt das Ruleset `protect-main` (PR-Pflicht, Squash,
Required Checks `lint`, `factory-self-test`, `pr-closes-issue`, `config-validation`).

## Ablauf

1. Issue anlegen und Task starten: `bash scripts/start-work.sh <beschreibung> [branch-typ]`
   (Branch-Typen und Labels: [`git-workflow.md`](docs/factory/guidelines/git-workflow.md)).
2. Im ausgegebenen Worktree arbeiten, Tests zuerst; committen und pushen über
   `bash scripts/factory-commit.sh "<typ>: <beschreibung>"`.
3. PR mit `Closes #<nr>` im Body; Merge per Squash, sobald die Required Checks grün sind.

## Beitragsarten

Fehlerbehebungen, Erweiterungen von Skripten, Skills, Gates und Guidelines sowie Doku. Jede neue
getrackte Datei braucht eine Zeile in [`docs/factory/OWNERSHIP.md`](docs/factory/OWNERSHIP.md).
Verweise auf das Ursprungs-Repo werden qualifiziert (`nothra/tch-gastro-services#<nr>`).
