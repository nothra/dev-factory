# /pr-shepherd – PR-Lifecycle bis Auto-Merge

Führt den aktuellen Branch durch den vollständigen PR-Lifecycle: Review-Kommentare
auflösen, Rebase, CI-Status prüfen, Auto-Merge freigeben – oder deterministisch
stoppen, wenn menschliche Entscheidung nötig ist.

## Kontext laden

Lies zuerst:
- `docs/factory/PROJECT-CONTEXT.md` – Projekt-Name, Git-Remote, CI-Konfiguration
- `tasks/task-$ARGUMENTS.md` – Aufgaben-Details, Status
- Aktuellen Branch-Status: `git status`, `git log main...HEAD --oneline`
- Offene MR/PR via `glab mr view` oder GitLab MCP

## Shepherd-Prozess

### Schritt 1: Zustand erfassen

```bash
git status
git log main...HEAD --oneline
glab mr view --web=false   # oder: gh pr view
```

Prüfe:
- Gibt es offene Review-Kommentare?
- Ist der Branch noch auf aktuellem `main` (oder hinter ihm)?
- Ist CI grün / laufend / rot?
- Stehen Approvals aus?

### Schritt 2: Review-Kommentare auflösen

Für jeden offenen Kommentar:

1. Kommentar lesen und Intention verstehen
2. Wenn eindeutig umsetzbar: Code ändern, Test anpassen, committen
   - Commit-Message: `fix: address review comment – [Kurzbeschreibung] (task-$ARGUMENTS)`
3. Wenn widersprüchlich oder unklar:
   ```bash
   bash scripts/raise-interrupt.sh $ARGUMENTS REVIEW_CONFLICT \
     "Widersprüchliche Review-Kommentare: [Kommentar A] vs [Kommentar B]"
   ```
   → Pipeline stoppt deterministisch. Kein stilles Weiterlaufen.

### Schritt 3: Rebase auf main

Server-seitig rebasen – kein lokaler Force-Push nötig (die Regel
„Nie force-pushen ohne Interrupt" bleibt gewahrt). Ein lokales `git rebase`
würde nie im Remote-MR landen, ohne force-zu-pushen:

```bash
glab mr rebase   # rebased den MR-Branch GitLab-seitig auf den aktuellen main
```

Bei Merge-Konflikt (Rebase nicht automatisch möglich):
```bash
bash scripts/raise-interrupt.sh $ARGUMENTS MERGE_CONFLICT \
  "Rebase-Konflikt in [Datei(en)] – manuelles Eingreifen nötig"
```

### Schritt 4: CI-Status prüfen

```bash
glab ci status   # oder: gh run list
```

- **Grün:** weiter zu Schritt 5
- **Laufend:** `glab mr merge --auto` (Schritt 6) wartet ohnehin auf die Pipeline –
  kein aktives Warten in der Session nötig
- **Rot (flaky Test):** CI-Re-Run anstoßen (`glab ci retry` / `gh run rerun`)
  – max. 1 Re-Run, danach Interrupt
- **Rot (echter Fehler):**
  ```bash
  bash scripts/raise-interrupt.sh $ARGUMENTS CI_FAILURE \
    "CI rot nach Re-Run – Log-Auszug: [Fehlermeldung]"
  ```

### Schritt 5: Approval-Status prüfen

```bash
glab mr approvals   # oder: gh pr view --json reviewDecision
```

- Wenn alle erforderlichen Approvals vorhanden → weiter
- Wenn Approval aussteht:
  ```bash
  bash scripts/raise-interrupt.sh $ARGUMENTS APPROVAL_PENDING \
    "Approval von [Reviewer] steht noch aus"
  ```

### Schritt 6: Auto-Merge freigeben

Wenn Schritt 2–5 alle grün:

```bash
glab mr merge --auto   # oder: gh pr merge --auto --squash
```

Ergebnis in Task-Datei dokumentieren:
```
PR-Shepherd [Datum]: Auto-Merge freigegeben – alle Gates grün.
```

## Regeln

- Kein Schritt überspringen
- Nie force-pushen ohne vorherigen Interrupt
- Kein Auto-Merge, wenn CI rot oder Approval fehlt
- Widersprüchliche Review-Kommentare immer zu einem Interrupt eskalieren

## Output

- Offene Review-Kommentare adressiert (committed)
- Branch rebased auf aktuellem main
- CI grün oder Interrupt ausgelöst
- Auto-Merge freigegeben oder Interrupt mit Grund

## Hinweis für Stage 3

Input: Task-ID
Output: Branch merge-ready, Auto-Merge freigegeben
Nicht-automatisierbare Zustände (Konflikte, CI-Fehler, fehlende Approvals):
→ `scripts/raise-interrupt.sh` aufrufen – Pipeline stoppt deterministisch (ADR-004).
