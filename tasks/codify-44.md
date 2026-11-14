## Codify-Report: Task 44

### Neue Regeln hinzugefügt
- `docs/factory/lessons/testing.md` + Zeile in `docs/factory/lessons/INDEX.md` (Gruppe testing) – „Negativkontrolle bildet den
  realen Ablauf nach; Link-Guard prüft die eigene Zieldatei" – wegen: AK7-Negativkontrolle lief erst über ein real nie
  vorkommendes Szenario (Manifest mit Anpassungsstelle, Sync-Abbruch), und der Link-Guard ließ ein fremdes, existierendes
  Ziel durch (Review Iteration 1, W2 und `tf`/`le`-Fälle).

### Keine weiteren Änderungen nötig
- Portabilitäts-Verweise, Byte-Deckel und Index-Ort sind in dieser Task selbst umgesetzt und in Factory-ADR-037/047
  nachgetragen; als zusätzliche Lesson wären sie Dopplung.
- Out-of-Scope-Funde liegen bereits in `docs/factory/kleinfunde.md` (Lessons zitieren verschobene Regel-Orte;
  Symlinks hinter `@import`-Pfaden). Keine neue Anlage nötig.

### Offen für den Menschen
- Issue „@import-Deckel je Projekt einstellbar machen" (Schwelle A, Label `enhancement`) ist laut `/review` noch **nicht**
  angelegt (Sandbox lehnte `source` ab). Manuell über `scripts/lib/create-issue.sh` anlegen.
- Task-Datei: zwei Checkboxen (E5-Frage, „Offen gelassen (Nitpicks)") vor dem Merge abhaken oder in Fließtext wandeln.
- `tasks/telemetry-raw-44-*.tmp.txt` im Worktree ist ein Pipeline-Artefakt, nicht committen.

### Empfehlung für nächste Features
- Bei Verschiebung von Regel-Orten gleich die Zitate in Lessons mitziehen (siehe Kleinfund), statt sie als Folgearbeit liegen zu lassen.
