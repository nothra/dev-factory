## Codify-Report: Task 41

### Neue Regeln hinzugefügt
- `docs/factory/lessons/factory-workflow.md` + `lessons/INDEX.md`: „Feindlicher Code im Container: Der Log-Kanal ist ein
  Rückkanal“ – wegen: W1 aus `/security-review` (stdout/stderr als Workflow-Kommando-Kanal), von Spec/ADR/Review nicht erfasst.
- `docs/factory/lessons/factory-workflow.md` + `lessons/INDEX.md`: „Pin-Wert ohne Netz nicht erfindbar“ – wegen: Null-Digest
  mit absichtlich rotem Test blockierte den Push; der spätere Format-Test belegt die Ladbarkeit nicht (AK1.4/AK4.3 offen).

### Folge-Arbeit
- Oberhalb der Schwelle (Zweifelsregel → Issue): „Fetch-Container vom Host-Gateway und Link-Local-Diensten abschotten“
  (`enhancement` + `security`). **Noch anzulegen:** Der Aufruf von `create_issue_idempotent` (`. scripts/lib/create-issue.sh`)
  wurde im Codify-Lauf vom Permission-Layer abgelehnt. Nach der Anlage die Nummer in `tasks/security-41.md` (Hinweis „Netz“) nachtragen.
- Unterhalb der Schwelle: DoS durch riesiges Bundle steht schon in `docs/factory/kleinfunde.md`.

### Empfehlung für nächste Features
- Vor dem Merge: W1 (`::stop-commands::`) und Review-Wichtig 1 (Smoke-Befehl um `cp -a`/git-Commit erweitern) umsetzen,
  dann auf grünen `fetch-container-smoke` warten und erst danach AK1.4/AK4.3 abhaken.
- Bei Sicherheitsgrenzen die Rückkanäle in der Spec als Liste führen (Datei, Log, Exit-Code, Artefakt).
