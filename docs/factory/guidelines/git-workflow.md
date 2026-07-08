# Git-Workflow-Regeln

Diese Regeln gelten für jeden Agenten und Entwickler, der in diesem Projekt arbeitet.
Sie sind nicht verhandelbar – der pre-push Hook erzwingt einen Teil davon technisch.

---

## Branches

**Nie direkt auf `main` oder `master` committen oder pushen.**
Jede Änderung – auch kleine Fixes – kommt über einen Feature-Branch und einen Pull Request:

```
git checkout -b feature/<kurzbeschreibung>
# ... Arbeit ...
git push origin feature/<kurzbeschreibung>
# → PR erstellen (gh pr create)
```

Branch-Konvention (aligned mit Conventional Commits):

| Präfix | Wann |
|--------|------|
| `feature/<beschreibung>` | Neue Funktionalität |
| `fix/<beschreibung>` | Bugfix |
| `improvement/<beschreibung>` | Refactoring, Docs, Tooling (kein neues Verhalten) |
| `hotfix/<beschreibung>` | Dringender Produktions-Fix |
| `refactor/<beschreibung>` | Refactoring ohne neues Verhalten |
| `docs/<beschreibung>` | Nur Dokumentation |
| `test/<beschreibung>` | Nur Tests |
| `chore/<beschreibung>` | Build, CI, Tooling, Dependencies |

`branch-name-check.sh` erzwingt diese Konvention automatisch.

Der pre-push Hook blockiert direkte Pushes auf `main`/`master` hart.

---

## Jeder Task hat ein GitHub-Issue (ADR-013)

**Die Task-ID ist die GitHub-Issue-Nummer.** Jede `tasks/task-<id>-*.md` hat ein
Issue #`<id>` – so ist der Task auf GitHub sichtbar und für den Auto-Trigger
(`factory::run`) erreichbar.

Am einfachsten **Issue-first** über `start-work.sh` (legt das Issue an und leitet die
Task-ID aus dessen Nummer ab):

```bash
bash scripts/start-work.sh "user-login implementieren"     # legt Issue an → Task-ID = Issue-Nr.
bash scripts/start-work.sh 42 user-login-implementieren     # bestehendes Issue #42 (wird validiert)
```

Prüfen/Reparieren:
```bash
bash scripts/sync-issues.sh --check      # exit 1, wenn ein Task kein Issue hat
bash scripts/sync-issues.sh --create     # fehlende Issues anlegen
```

Das CI-Gate `issue-sync` erzwingt die Invariante bei jedem Push/PR.

---

## Vor dem Start: Immer pullen

Bevor ein neuer Feature-Branch angelegt wird:

```bash
git checkout main
git pull --rebase origin main
git checkout -b feature/<beschreibung>
```

Warum: Verhindert, dass auf einem veralteten Stand gearbeitet wird, und
minimiert Konflikte beim späteren Rebase.

---

## Vor dem Push: Nochmals pullen und rebasen

Bevor ein Branch gepusht (oder ein PR erstellt) wird:

```bash
git fetch origin
git rebase origin/main
```

Warum: Der eigene Branch soll auf dem aktuellen `main` aufsetzen,
damit der PR ohne Konflikte gemerged werden kann.

---

## Rebase statt Merge

**`git rebase`, nicht `git merge`** – für das Aktualisieren des Feature-Branches
gegenüber `main`.

```bash
# Richtig:
git rebase origin/main

# Falsch:
git merge origin/main
```

Warum: Rebase erzeugt eine lineare, lesbare Git-History.
Merge-Commits ("Merge branch 'main' into feature/xyz") haben keinen Informationswert
und erschweren `git log`, `git bisect` und Code-Reviews.

**Ausnahme:** Das Zusammenführen in `main` (der eigentliche PR-Merge) erfolgt
durch GitHub – dort ist ein Merge-Commit oder Squash
je nach Team-Konvention in Ordnung.

---

## Eine Task = Eine Session

Jede neue Task in einer neuen Claude-Session starten.

**Warum:**
- Kleiner Kontext → KI bleibt fokussiert auf die aktuelle Task
- Kein Übersprechen von Entscheidungen oder Fehlern aus vorherigen Tasks
- Weniger Token-Verbrauch, da kein irrelevanter Verlauf mitgeschleppt wird

**Wie:**
```bash
bash scripts/start-work.sh "<beschreibung>"   # Issue-first: legt Issue an, Nr. = Task-ID
# → neues Terminal / neue Claude-Session öffnen
# → /implement <task-id>
```

Das Skript gibt am Ende immer einen Hinweis dazu.

---

## Commit-Nachrichten

Format: `<typ>: <kurze Beschreibung im Imperativ>`

| Typ | Bedeutung |
|-----|-----------|
| `feat` | Neue Funktionalität |
| `fix` | Bugfix |
| `docs` | Nur Dokumentation |
| `refactor` | Kein neues Verhalten, keine Bugfixes |
| `test` | Nur Tests |
| `chore` | Build, CI, Tooling |

Beispiele:
- `feat: add user authentication via OAuth2`
- `fix: return 404 when order not found`
- `docs: document rebase workflow`

Keine Commit-Messages wie "WIP", "fix", "asdf" – jeder Commit soll für sich verständlich sein.
