# Security Review: Task 23

Geprüft: `git diff origin/main...HEAD` (Stand `777bb27`) – `factory-sync.sh` (Abholen), `factory-integrity-check.sh`,
`scripts/lib/factory-lock.sh`, Verdrahtung in `pre-commit.sh`/`pre-push.sh`/`factory-ci.yml`. Angriffsfläche: Release-Manifest
und Tag-Inhalt (aus dem Netz), `factory.lock` (Repo-Inhalt, PR-kontrolliert), Umgebung. Web-/SQL-/XSS-/Krypto-Punkte des
Katalogs entfallen (Shell-Werkzeug, keine neuen Dependencies, keine Secrets, kein Token-Zugriff).

## Kritische Findings (Blocker)
_keine_

## Wichtige Findings
- [x] **Pfad-Injection / Symlink-Guard umgehbar** – `scripts/factory-sync.sh` (`check_target_path`, `backup_target`, `install_file`,
  `rollback`): `dirname "$p"` ohne `--`. Beginnt ein Manifest-Pfad mit `-` (z. B. `-d/x.sh`), liest `dirname` ihn als Option,
  scheitert (`illegal option`) und liefert leer; die Symlink-Prüfung der Elternverzeichnisse (`check_target_path`) läuft dann
  ins Leere. **Repro (verifiziert):** Manifest mit `-d/x.sh`, im Konsumenten `-d` als Symlink auf ein Verzeichnis außerhalb →
  `factory-sync.sh v1.0.0` endet mit Exit 0 und schreibt `x.sh` **außerhalb des Repos** (die Fehlermeldungen von `dirname`
  erscheinen nur auf stderr). Das bricht die Zusage aus ADR-063 E4/F-23.3 („kein Schreiben außerhalb des Repos“).
  Voraussetzung: Manifest mit Pfad `-…` **und** ein gleichnamiger Symlink im Konsumenten – daher kein Blocker, aber eine
  Lücke in der Eingabehärtung, die dieselbe Task für Hashing (`./`-Präfix) schon geschlossen hat.
  **Fix:** überall `dirname -- "$…"` (4 Stellen) **oder** Manifest-Pfade mit führendem `-` in `fl_validate_manifest` ablehnen;
  dazu ein Test mit Symlink `-d` und Mutationsbeleg (Fixture-Tag mit Pfad `-d/x.sh`).

## Hinweise
- [ ] **Gate läuft aus dem Code des eigenen PRs** – ein PR kann Gate-Skript, Lib, `factory-ci.yml` und die Lock-Hashes gemeinsam
  ändern; die CI-Stufe prüft dann gegen manipulierten eigenen Code. Das ist in jedem In-Repo-Gate so und wird heute nur durch
  PR-Review/Ruleset (Pflicht-Approval) aufgefangen. Als Issue angelegt: **#30** (Label `enhancement`; die Aspekt-Labels
  `security`/`factory-pipeline` gibt es im Repo nicht, der Seam hat sie verworfen – nachtragen).
- [ ] **Kein unabhängiger Vertrauensanker für das Manifest** – Manifest (Release-Asset) und Tag stammen vom selben Repo; wer dort
  schreiben darf, kann beides konsistent ändern. Erstabholung pinnt keinen Commit (TOFU). Akzeptiertes Restrisiko laut
  ADR-063 D1 (öffentliches Repo, GitHub-Zugriffskontrolle); eine Signatur wäre eine eigene Entscheidung.
- [x] **`upstream.repo`-Slugmuster erlaubt `..`** – `fl_upstream_repo` akzeptiert `../x` (Segmente aus `[A-Za-z0-9._-]`), die URL
  `https://github.com/../x.git` normalisiert GitHub zu `github.com/x`. Der Wert kommt aus der projekteigenen Config (vertraut),
  daher nur Hinweis; Härtung: Segmente `.`/`..` ablehnen (Zweizeiler).
- [ ] Positiv geprüft: Versionsmuster vor jedem Netzzugriff; `git clone … --branch <tag> -- <url>`; kein `eval`; `curl -L` folgt
  nie auf `file://`; Hashing mit `./`-Präfix; Pfadform (absolut, `..`, Backslash, Steuerzeichen, Duplikate) und Projektbereiche/
  Anpassungsstellen für Manifest **und** alten Lock; Symlink-Prüfung für Ziele und Elternverzeichnisse (außer dem oben
  genannten Fall); Klon-Dateien werden nur als reguläre Dateien akzeptiert; privates `mktemp -d`; Rückbau ohne Datenverlust;
  `rm -rf` nur auf das eigene Temp-Verzeichnis.

## Ergebnis
NEEDS_FIXES

_Fix umgesetzt (Iteration nach Security-Review): `dirname --`/`rmdir -p --` an allen Stellen, Slug-Segmente `.`/`..` abgelehnt; Tests erst rot, dann grün (1887 + 143). Erneuter `/security-review` bestätigt._
