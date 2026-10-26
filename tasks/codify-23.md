## Codify-Report: Task 23

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` (+ Index-Zeile in `PROJECT-CONTEXT.md`, Gruppe Testing): **Fail-closed-Zweig nicht nur über Exit-Code + „nichts
  geändert“ belegen** – zweigspezifische Meldung, Abwesenheit der Folgestufen, Fixture so bauen, dass nur dieser Zweig greift, Mutationslauf je `die`.
  Wegen: 12 von 26 Mutanten überlebten im `/test`-Schritt; der Mutationslauf ersetzte den `bash -x`-Wrapper, der bei Kind-Prozessen versagte.
- `docs/factory/PROJECT-CONTEXT.md` (bestehende Index-Zeile „Mutationsbeleg muss denselben Assert-Ausdruck…“): **Rezidiv** als Tautologie
  `grep -vF <zeile> | grep -qF <zeile>` – wegen Review-Runde 1.
- `docs/factory/guidelines/bash-gotchas.md` **#19**: Pfade aus fremden Quellen mit `--`/absolutem Ziel an `dirname`, `rmdir`, `cp`; bei Härtung einer
  Fehlerklasse alle Geschwister-Aufrufe greppen. Wegen: `dirname "-d/x.sh"` umging die Symlink-Prüfung, Schreiben außerhalb des Repos (Security-Review).

### Folge-Arbeit
- **Issue #30** (Security-Review): Gate läuft aus dem Code des eigenen PRs. Die Aspekt-Labels `security`/`factory-pipeline` gibt es im Repo nicht
  (der Seam verwarf sie), am Issue nachzutragen bzw. im Repo anzulegen – sonst fällt jede künftige Aspekt-Klassifizierung still weg.
- Kein `kleinfunde.md`-Eintrag nötig: die kleineren Funde (CHANGELOG, `upstream.repo`-Slug, Löschen geschützter Lock-Pfade) sind im PR behoben.

### Keine Änderungen nötig
- `CLAUDE.md`/`FACTORY.md`: keine neue Grundregel; der @import-Deckel bleibt (766 von 1100 Zeilen).

### Empfehlung für nächste Features
- #24 (Update-Workflow) baut auf `factory-sync.sh <version>` auf: den Zwei-Phasen-Ablauf und die Test-Fixture (`factory-lock-tests.sh`, Tags v1–v3) wiederverwenden.
- Vor T2a-4 (Erst-Einbindung) Issue #30 entscheiden: Required Check `factory-integrity` ohne Entscheidung dazu schützt nur gegen versehentliche Abdrift.
- Fixtures, die auf älteren Fixture-Tags aufbauen, erben deren Eigenheiten (z. B. die Versionszeile in `FACTORY.md` bei v3.0.0) – neue Tag-Fixtures
  setzen die Versionszeile selbst.
