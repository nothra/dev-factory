## Codify-Report: Task 47

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` (+ Index-Zeile in `PROJECT-CONTEXT.md`) – **Ignore-Status im Ziel erzwingen**,
  wenn ein Schritt Dateien in einen Worktree legt, den ein Folgeprozess per `git add -A` committet; beim
  Konfigurierbarmachen einer festen Liste fragen, welche Garantie an der Festverdrahtung hing – wegen: Security-Review-W1
  (nicht ignorierter `copy_files`-Eintrag würde committet und gepusht; Architektur, Spec und zwei Review-Runden übersahen es).
- `docs/factory/lessons/factory-workflow.md` (+ Index-Zeile) – **`yq` `.[]` über eine Map liefert deren Werte**; Listen nur über
  `!!seq` iterieren, Nicht-Listen zählen/melden, frühere Gate-Regel darf spätere Typ-Regel nicht mit falscher Meldung maskieren –
  wegen: Review-Iteration 1 (Selbstfund, `{x: lokal.conf}` hätte `lokal.conf` kopiert).
- `PROJECT-CONTEXT.md` (Index `build-tooling.md`) – sechstes Vorkommnis „Wegwerf-Dateien nicht gelöscht" (`scripts/*47*.tmp.sh`,
  Telemetrie-Rohdateien über vier Skill-Läufe, `rm` nie freigegeben); Regel ergänzt: Sonde als Wrapper schreiben, der sich selbst löscht.
- `docs/factory/kleinfunde.md` – bestehender Eintrag `echo -e` mit Backslash-Escapes um die dritte Fundstelle
  (`start-work.sh`, `warn_copy`/Erfolgszeile) erweitert; unterhalb der Schwelle, kein Issue.

### Keine Änderungen nötig
- CLAUDE.md, Guidelines: kein Kandidat für eine generische Regel; beide Lessons haben einen engen „Laden bei"-Trigger.
- Kein neuer Check: das W1-Muster ist ohne Kenntnis des Ziel-Branches nicht statisch prüfbar (Gate kann es nicht abfangen).

### Nachlauf nach dem Security-Rework (2026-11-05)
- `lessons/factory-workflow.md` + Index-Zeile – **W2**: `git check-ignore` liest den Eintrag als Pathspec (`:secret` → `secret`), der
  W1-Fix selbst hatte die Lücke; Fix `./`-Präfix. Nachtrag an der W1-Lesson – wegen: Security-Nachlauf W2.
- `lessons/factory-workflow.md` + Index-Zeile – **Pipeline-Abbruch an der Verdict-Wache** bei bereits geprüftem Stand; Pipeline kann nicht
  mitten im Ablauf einsteigen, Rest manuell fahren – wegen: zwei überflüssigen Neustarts bei Task 47.
- `PROJECT-CONTEXT.md` (Index `build-tooling.md`) – siebtes Vorkommnis Wegwerf-Dateien (Review-Läufe, trotz Regel).
- `CHANGELOG.md`, `OPERATING.md` – Ignore-Guard genannt (Doku-Drift aus Review-Iteration 3/4, Nitpick im Scope).
- W1 und W2 sind behoben, Security-Nachlauf 2: PASSED; kein neuer Out-of-Scope-Fund, kein Issue, kein `kleinfunde.md`-Eintrag.

### Offen vor dem Merge
- Wegwerf-Dateien (gitignoret, nicht im Commit): `scripts/probe47*.tmp.sh`, `scripts/review47*.tmp.sh`, `tasks/*.tmp.txt` – `rm` braucht Freigabe.

### Empfehlung für nächste Features
- Bei jeder Verallgemeinerung einer festverdrahteten Liste in `/architecture` explizit „welche Garantie hing an der Festverdrahtung?" notieren.
- Telemetrie-Lücke dieser Task: der manuelle Stage-2-Fortsatz nach Turn-Limit hat keine OTEL-Telemetrie (Factory-ADR-049).
