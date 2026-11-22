## Codify-Report: Task 61

### Neue Regeln hinzugefügt
- `docs/factory/lessons/INDEX.md` (Gruppe `testing.md`, Trigger am Gruppen-Header): Nachtrag zur SIGPIPE-Lesson
  – die Prosa-Regel verhinderte das Rezidiv nicht, jetzt Helfer `grep_in` + Guard `pipe_grep_q_lines` – wegen: dasselbe
  `printf | grep -q`-Race trat nach der Prosa-Regel (nothra/tch-gastro-services#426) erneut auf (#61, #15).
- `docs/factory/lessons/INDEX.md` (neue Zeile, `testing.md`): Eine Prosa-Regel gegen ein Fehlermuster reicht nicht; Guard
  fail-closed mit Mutationsbelegen je Variante. Massen-Ersetzung mit Ersatztext auf Leerzeichen verklebt Aufrufe und
  bleibt oft grün – wegen: Review-Iteration 1 (Guard fail-open, Lücken) und `/implement`-Selbstfund.
- Volltext in `docs/factory/lessons/testing.md` stand bereits (AK9); keine neue Lesson-Datei, daher kein Eintrag in `FACTORY.md`.
- Neuer Check: `pipe_grep_q_lines` (Guard in beiden Suiten) ist Teil der Implementierung, kein zusätzlicher Check nötig.

### Keine Änderungen nötig
- `CLAUDE.md` und Guidelines: kein generisches, über Test-Skripte hinausgehendes Learning.

### Offen (Mensch)
- Issue für `scripts/checks/pre-commit.sh:27,35,51` (`git diff --cached | grep -qE` unter `pipefail`, fail-open bei
  Konflikt-/Debug-/Secret-Prüfung; Labels `bug` + `security`): Die Sandbox hat die Anlage dreimal abgelehnt. **Ein Mensch
  muss es vor dem Merge anlegen.** Ähnlich, unkritischer: `factory-update.sh:77`, `start-work.sh:310` (steht als Kleinfund).
- AK7 (10× CI-Lauf `factory-self-test`) und AK8 (#15-Test in allen Läufen grün) brauchen den PR und die CI-Läufe.

### Empfehlung für nächste Features
- Bei Massen-Ersetzungen per Skript danach gezielt auf verklebte Argumente suchen.
- Neue Guards von Anfang an fail-closed bauen und je Erkennungs-Variante einen Mutationsfall mitliefern.
