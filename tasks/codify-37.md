## Codify-Report: Task 37

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` + Index-Zeile in `PROJECT-CONTEXT.md` – **Nachtrag Credential/Release-Code**: die Grenze ist
  ein Job (Environment-Secret mit Branch-Regel `main`, Ergebnis als Bundle, Commit per `commit-tree` neu) – wegen: `env -u` aus Task 24 war keine Grenze.
- `docs/factory/lessons/factory-workflow.md` + Index – **Verifier hinter einer Vertrauensgrenze spiegelt jede Prüfung des Werkzeugs**
  (Parität) und nennt die Prüfliste im selben Commit in ADR/Handbuch/Doku-Guard – wegen: fehlende „keine geschützten Stellen"-Prüfung
  (Review-Iteration 1) und danach nicht nachgezogene Doku (Iteration 2).
- `docs/factory/lessons/factory-workflow.md` + Index – **Turn-Limit, siebtes Vorkommnis**: Task mit neuer Sicherheitsgrenze gleich manuell
  in getrennten Skill-Läufen fahren; Telemetrie-Lücke vermerken – wegen: 3×20 Turns ohne Commit in Phase 1.
- `docs/factory/lessons/testing.md` + Index – **Feindcode-Test braucht Laufnachweis und Gegenprobe** – wegen: grüner Hostile-Test, der den
  feindlichen Code nie ausführte.

### Folge-Arbeit
- Issue #41 (aus `/security-review`): Runtime-Token des `fetch`-Jobs gegen Release-Code abschirmen (Label `enhancement`, `security`;
  `factory-pipeline` existiert im Repo nicht).

### Keine Änderungen nötig
- SIGPIPE/`pipefail` im Test, `main "$@"; exit $?` bei Selbst-Ersatz, Mutationsbelege je `die`, Fork-Kontamination, Commit-vor-nächster-Stufe:
  bestehende Lessons haben gegriffen (Rezidive vermieden, kein neuer Eintrag). Pre-Commit-Credential-Heuristik (Fehlalarm bei
  `…_SECRET="${…}"`) und der Guardrails-Hook bei `rm -rf` auf eigene Temp-Verzeichnisse sind Werkzeug-Eigenheiten, keine Repo-Regel.

### Empfehlung für nächste Features
- Vor Auslieferung des Releases: Environment `factory-update` mit Branch-Regel `main` und Secret im Konsumenten einrichten, Repository-Secret
  löschen, Beleg am echten Repo (Q-37.3) – menschliche Schritte, in CHANGELOG „Unreleased" vorgemerkt.
