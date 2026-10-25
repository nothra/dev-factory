# Security Review: Task 22

Stand: Branch `feature/22-…` (PR #25), geprüft bei `202bfb1`, Fund 1 behoben in der Folge-Änderung dieses Schritts. Bedrohungsmodell: Shell-Werkzeug ohne
Webserver, Datenbank oder Sessions; Eingaben von außen sind das Release-Manifest (`factory.lock`), `customization-points.txt`, Dateilisten und Umgebung.
Schutzziel: kein Fail-open des Ownership-Gates, keine Argument-/Command-Injection über Pfade, keine unerwünschte Gate-Abschaltung.
Methode: Security-Agent (read-only, Repros in Wegwerf-Klon) plus eigene Gegenprüfung des Orchestrators.

## Kritische Findings (Blocker)
Keine.

## Wichtige Findings
- [x] [Input-Validierung / Fail-open] `scripts/checks/ownership-check.sh`, `lock_report_class` (vorher Z. 107): `echo "$path" >> findings.txt` behandelt einen Lock-Pfad `-n` als `echo`-Option. Der Fund wird auf stderr gemeldet (`✗ -n: nicht getrackt`), aber nicht in `findings.txt` vermerkt – der Zähler bleibt 0, das Skript endet mit **Exit 0** und `✓ Zuordnung vollständig und eindeutig`.
  Repro (macOS bash 3.2.57): Lock `{"schema":1,"files":[{"path":"-n"}]}`, Dateiliste `a.md` → vorher `rc=0`; mit `-e`/`-E` entsteht zufällig noch eine Zeile (Exit 1). Auswirkung: Ein Lock, dessen einziger Fund ein nicht getrackter Pfad `-n` ist, passiert das Gate. Ausnutzbarkeit gering (der Angreifer muss das Manifest kontrollieren und kann nur diesen Pfad verstecken, andere Funde bleiben sichtbar), aber ein reproduzierbares Fail-open in einem Sicherheits-Gate, das auf fail-closed ausgelegt ist.
  **Behoben:** `printf '%s\n' "$path"` statt `echo`; Test zuerst (rot), dann grün (6 Assertions für `-n`, `-e`, `-E` in der ausgelieferten Suite). Alle anderen `echo`-Aufrufe der geänderten Skripte beginnen mit einem Literal (`✗ `, `ownership-check: …`), nicht mit Fremdinhalt. *(Fund des Orchestrators bei der Gegenprüfung; der Security-Agent hatte Pfade mit führendem `-` als „sauber“ gemeldet – ein Beleg, dass ein einzelner Agent-Lauf nicht genügt.)*

## Hinweise
- [x] [Autorisierung / Moduswechsel] `scripts/checks/ownership-check.sh:151-156`, niedrig: Die bloße Existenz von `factory.lock` schaltet den Check vom Tabellen- in den Lock-Modus. Ein im **Factory-Repo** committetes `factory.lock` würde die Vollständigkeitsprüfung der Tabelle unbemerkt abschalten (Repro des Agents: nicht zugeordnete Datei `evil.sh` → ohne Lock Exit 1, mit Lock Exit 0). Das Release-Manifest bleibt unberührt (liest die Tabelle am Tag). Kein Rechtegewinn gegenüber dem Ändern von CI/Tests, aber ein stiller Wegfall des Gates. **Behoben:** Guard-Test in der Projekt-Suite (`scripts/project/tests/run-tests.sh`): das Factory-Repo trägt kein `factory.lock` (mit Kontrolle gegen ein Verzeichnis mit Lock). Die ausgelieferte Suite bleibt neutral, weil ein Konsument einen Lock hat.
- [ ] [Input-Validierung] `ownership-check.sh:96` (`jq -r '.files[].path'`), niedrig: Ein Lock-Pfad mit Zeilenumbruch wird in mehrere Pfade zerlegt (Repro des Agents: `evil.sh\nREADME.md` → `README.md: Anpassungsstelle steht im Lock`, Exit 1). Kein Rechtegewinn, fail-closed bleibt erhalten. Optional: Pfade mit `\n`/`\r` im `jq`-Gate als ungültigen Lock ablehnen (Exit 2). Als Kleinfund geführt (`docs/factory/kleinfunde.md`).
- [ ] [Dependency] `.github/workflows/ci.yml`, Job `project-self-test`: nutzt `jq` über die Suite, ohne es zu prüfen; auf `ubuntu-latest` vorinstalliert (wie in `factory-ci.yml:76` vermerkt). Optional: Schritt `command -v jq`, damit ein Wegfall laut statt still scheitert.
- [ ] [CI / Supply Chain] `actions/checkout@v4` ist nicht per Commit-SHA gepinnt. Bestehender Repo-Standard, kein neues Problem; als Querschnittsthema zu führen (nicht Teil dieser Task).

## Geprüft und nicht betroffen
- **Lock-Fail-open:** ungültiger Lock, fehlendes `jq`, fehlende/leere Anpassungsstellen-Liste → Exit 2, kein Rückfall in den Tabellenmodus; hängender Symlink gilt als Lock; Fehler einer Vergleichs-Pipeline (`comm`) → Exit 2 (`lock_internal_error`).
- **Injection:** kein `eval`, keine Interpolation in `jq`-Filter (alle Filter sind Konstanten), Pfade gehen nur über `printf '%s\n'`, `comm`, `sort`, `jq -r` als Daten.
- **Temp und Trap:** `WORK_DIR` wird im Skript leer initialisiert (kein Einfluss über die Umgebung); Trap erst nach erfolgreichem `mktemp -d`.
- **Umgebung als Steuerkanal:** `FACTORY_LOCK_FILE`, `CUSTOMIZATION_POINTS_FILE`, `OWNERSHIP_FILE*` wirken nur in der Hand des Aufrufers (Tests, Manifest-Skript); `FACTORY_SELF_TEST_RUN` überspringt nur lokal die Projekt-Suite im Hook (CI setzt sie nicht; der Hook ist ohnehin mit `--no-verify` umgehbar).
- **Manifest:** `factory-release-manifest.sh` erzwingt per `FACTORY_LOCK_FILE="$WORK/kein-lock"` den Tabellenmodus am Tag-Stand (Test belegt es).
- **CI:** `permissions: contents: read`, Trigger `pull_request` (nicht `pull_request_target`), keine Secrets, keine untrusted Inputs in `run:`, `sudo bash scripts/install-yq.sh` mit gepinnter, SHA-256-verifizierter Binary.
- **Secrets/Logs/Error Handling, Authentifizierung/Sessions:** nicht betroffen (Fehlermeldungen nennen nur Repo-Pfade).

## Ergebnis
PASSED

> Hinweis zur Belegqualität: Das Fail-open (Wichtig) wurde vom Orchestrator gefunden und im selben Schritt behoben (Test rot → grün). Die Korrektur ist ein Einzeiler und durch Tests belegt, aber nicht von einem zweiten Agent-Lauf geprüft. Stand nach Korrektur: ausgelieferte Suite 1678/0, Projekt-Suite 135/0, Konsumenten-Fixture 1678/0.
