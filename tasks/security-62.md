# Security Review: Task 62

Umfang: reine Doku-Änderung (`git diff origin/main...HEAD`): Nachtrag in Factory-ADR-029, OPERATING §0.7 und §5.5a,
Rückverweise in Factory-ADR-063, CHANGELOG, dazu Spec, Task-Datei und Review-Report. Kein Skript, kein Workflow, keine
Dependency, keine Config geändert. Bedrohungsfläche: die beschriebene Bedienung (Ruleset ändern, Notfallverfahren) und der
dokumentierte Shell-Befehl.

Prüfkatalog: Injection, Auth, Secrets, Dependencies und Error Handling sind ohne Befund oder nicht anwendbar. Der
`gh api`-Befehl liest nur, nutzt Platzhalter `<owner>/<repo>`/`<ruleset-id>` und enthält keine Token oder IDs eines realen
Konsumenten. Keine Secrets im Diff.

## Kritische Findings (Blocker)
- keine

## Wichtige Findings
- keine

## Hinweise
- [ ] [Integrität / Restrisiko] Die Begründung im Nachtrag („Ein Gate, das den Merge nicht verhindert, schützt nichts") stimmt:
  Der Required Check ist notwendig. Sie lässt aber offen, dass er nicht ausreicht: `factory-integrity` läuft mit
  `factory-ci.yml` und `factory-integrity-check.sh` aus dem PR-Stand (`pull_request`). Ein PR kann also Gate, Workflow und
  Lock gemeinsam ändern und sich selbst grün melden. Das ist bereits als **#30** erfasst („Integritäts-Gate gegen
  Manipulation durch den eigenen PR härten"), kein neues Issue. Empfehlung: im Nachtrag einen Satz „Restrisiko: ein PR,
  der das Gate selbst ändert, siehe #30" ergänzen, damit der Required Check nicht als vollständiger Schutz gelesen wird.
  Kein Blocker, die Lücke entsteht nicht durch diesen PR.
- [ ] [Konfiguration / Zeitfenster] Die Notfall-Abhilfe und die Alternative „bei vielen betroffenen PRs den Check austragen"
  öffnen ein Zeitfenster ohne serverseitige Integritätsprüfung. Abgemildert: Das Notfallverfahren verlangt ein Issue mit
  Zeitraum und gemergten PRs. Eine in dieser Zeit gemergte Abweichung lässt außerdem jeden späteren PR rot werden, weil der
  Baum auf `main` nicht mehr zum Lock passt (fail-closed bei der Erkennung). Empfehlung (optional): auch bei der Alternative
  den Zeitraum dokumentieren lassen, wie beim Notfall. Fällt unter die Schwelle, kein Issue.

## Ergebnis
PASSED
