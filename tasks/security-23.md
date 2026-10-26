# Security Review: Task 23

Re-Review (Stand `e157b0a`) nach dem Fix des ersten Berichts. Geprüft: `git diff origin/main...HEAD`, insbesondere
`scripts/factory-sync.sh`, `scripts/lib/factory-lock.sh`, `scripts/checks/factory-integrity-check.sh`. Angriffsfläche:
Release-Manifest und Tag-Inhalt (Netz), `factory.lock` (PR-kontrolliert), Umgebung. Web-/SQL-/XSS-/Krypto-Punkte des Katalogs
entfallen (Shell-Werkzeug, keine neuen Dependencies, keine Secrets, kein Token-Zugriff).

## Kritische Findings (Blocker)
_keine_

## Wichtige Findings
_keine offen._ Behoben aus Runde 1:
- [x] **Pfad-Injection / Symlink-Guard umgehbar** (`dirname` ohne `--`, Manifest-Pfad `-d/x.sh`): alle `dirname`-/`rmdir -p`-Aufrufe
  auf Manifest-Pfaden stehen jetzt mit `--`. **Re-Repro (verifiziert):** derselbe Aufbau wie im ersten Bericht (Manifest mit
  `-d/x.sh`, Symlink `-d` nach außerhalb) endet mit Exit 1 („Zielverzeichnis ist ein Symlink: -d“), außerhalb des Repos wird
  nichts geschrieben. Tests (Symlink-Fall, legitimer `-d/x.sh`) erst rot, dann grün; restliche Aufrufe geprüft: alle übrigen
  Dateioperationen auf Manifest-Pfaden verwenden absolute Ziele (`$ROOT/…`, `$WORK/…`) oder feste Konstanten, das Hashing das
  `./`-Präfix – keine weitere Optionsinjektion.

## Hinweise
- [x] **`upstream.repo`-Slugmuster erlaubte `..`** – behoben (`fl_upstream_repo` lehnt die Segmente `.`/`..` ab, drei Tests).
- [ ] **Gate läuft aus dem Code des eigenen PRs** – Design-Restrisiko jedes In-Repo-Gates, nur durch PR-Review/Ruleset
  aufgefangen; als Issue **#30** erfasst (Aspekt-Labels `security`/`factory-pipeline` fehlen im Repo und sind am Issue
  nachzutragen).
- [ ] **Kein unabhängiger Vertrauensanker für das Manifest** (Manifest und Tag vom selben Repo, Erstabholung pinnt keinen Commit):
  akzeptiertes Restrisiko laut ADR-063 D1; eine Signatur wäre eine eigene Entscheidung.
- [ ] Positiv: Versionsmuster vor jedem Netzzugriff, `git clone … --branch <tag> -- <url>`, kein `eval`, `curl -L` folgt nie auf
  `file://`, Pfadform- und Schutzprüfung für Manifest und alten Lock, Symlink-Prüfung für Ziele und Elternverzeichnisse,
  nur reguläre Dateien aus dem Klon, privates `mktemp -d`, Rückbau ohne Datenverlust.

## Ergebnis
PASSED
