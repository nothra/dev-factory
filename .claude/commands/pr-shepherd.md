# /pr-shepherd – PR-Lifecycle bis Auto-Merge

Führt den aktuellen Branch durch den vollständigen PR-Lifecycle: Review-Kommentare
auflösen, Rebase, CI-Status prüfen, Auto-Merge freigeben – oder deterministisch
stoppen, wenn menschliche Entscheidung nötig ist.

## Kontext laden

Lies zuerst:
- `docs/factory/PROJECT-CONTEXT.md` – Projekt-Name, Git-Remote, CI-Konfiguration
- `tasks/task-$ARGUMENTS.md` – Aufgaben-Details, Status
- Aktuellen Branch-Status: `git status`, `git log main...HEAD --oneline`
- Offenen PR via `gh pr view`

## Shepherd-Prozess

### Schritt 1: Zustand erfassen

```bash
git status
git log main...HEAD --oneline
gh pr view
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

Server-seitig aktualisieren – kein lokaler Force-Push nötig (die Regel
„Nie force-pushen ohne Interrupt" bleibt gewahrt). Ein lokales `git rebase`
würde nie im Remote-PR landen, ohne force-zu-pushen:

```bash
gh pr update-branch   # führt den aktuellen main GitHub-seitig in den PR-Branch (kein Force-Push)
```

Bei Merge-Konflikt (Rebase nicht automatisch möglich):
```bash
bash scripts/raise-interrupt.sh $ARGUMENTS MERGE_CONFLICT \
  "Rebase-Konflikt in [Datei(en)] – manuelles Eingreifen nötig"
```

### Schritt 4: CI-Status prüfen

```bash
gh pr checks   # Status der CI-Checks des PRs (oder: gh run list)
```

- **Grün:** weiter zu Schritt 5
- **Laufend:** `gh pr merge --auto` (Schritt 6) wartet ohnehin auf die Checks –
  kein aktives Warten in der Session nötig
- **Rot (flaky Test):** CI-Re-Run anstoßen (`gh run rerun --failed`)
  – max. 1 Re-Run, danach Interrupt
- **Rot (echter Fehler):**
  ```bash
  bash scripts/raise-interrupt.sh $ARGUMENTS CI_FAILURE \
    "CI rot nach Re-Run – Log-Auszug: [Fehlermeldung]"
  ```

### Schritt 5: Approval-Status prüfen

```bash
gh pr view --json reviewDecision
```

- Wenn alle erforderlichen Approvals vorhanden → weiter
- Wenn Approval aussteht:
  ```bash
  bash scripts/raise-interrupt.sh $ARGUMENTS APPROVAL_PENDING \
    "Approval von [Reviewer] steht noch aus"
  ```

### Schritt 5b: Draft-Status auflösen

`gh pr merge --auto` kann auf einem **Draft-PR** nicht aktiviert werden (GitHub lehnt
Auto-Merge/Merge für Drafts ab). Der von `start-work.sh --draft` angelegte PR muss daher
– erst jetzt, wenn Schritt 2–5 grün sind (fail-closed: bleibt Draft, wenn ein Gate rot
ist) – aus dem Draft geholt werden. Idempotent, nur wenn nötig:

```bash
if [ "$(gh pr view --json isDraft -q .isDraft)" = "true" ]; then
  gh pr ready            # Draft → ready for review, bevor Auto-Merge aktiviert wird
fi
```

### Schritt 6: Abschlussnotiz committen + pushen, dann Auto-Merge freigeben

Wenn Schritt 2–5 alle grün. **Reihenfolge ist kritisch (Squash-Merge):** Die
Abschlussnotiz muss auf dem Feature-Branch **committet und gepusht** sein, *bevor*
Auto-Merge aktiviert wird. Sonst landet eine nur lokal geschriebene Notiz **nie auf
`main`** – nach dem Merge liegt die Task-Datei auf `main` und ist nur noch über einen
neuen PR änderbar (Direkt-Commit auf `main` ist verboten). Vorfall: #112/#114.

1. Ergebnis in die Task-Datei schreiben:
   ```
   PR-Shepherd [Datum]: Auto-Merge freigegeben – alle Gates grün.
   ```
2. Abschlussnotiz committen **und** pushen (Feature-Branch, *vor* dem Merge) – über den
   Commit/Push-Seam, nicht über rohes `git commit`/`git push` (ADR-019):
   ```bash
   bash scripts/factory-commit.sh "docs: pr-shepherd-Abschlussnotiz (task-$ARGUMENTS)"
   ```
3. **Erst dann** Auto-Merge freigeben:
   ```bash
   gh pr merge --auto --squash
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
