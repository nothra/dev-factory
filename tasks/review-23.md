# Review: Task 23

Review-Runde 1 (Diff `origin/main...HEAD`, 15 Dateien, Spec `spec-23-factory-sync-lock-integritaets-gate.md`).
Alle 24 Kriterien der Spec haben mindestens einen Test; Suiten grün (1835 + 143).

## Kritische Findings (müssen behoben werden)
_keine_

## Wichtige Findings (sollten behoben werden)
- [ ] `scripts/factory-sync.sh` (`apply_version`, Zeilen um `for path in "$SETTINGS_TARGET" …`): `check_target_path` prüft nur Manifest- und entfallene Pfade, nicht die Ziele `.claude/settings.json`, `.gitignore` und `factory.lock`. Ist eine davon im Repo ein Symlink, schreibt `install_file` (`cp -p`) durch den Link und damit außerhalb des Repos – genau der Fall, den E4/F-23.3 ausschließen wollen. Fix: dieselbe Prüfung für die drei Ziele in Phase 1 (vor `APPLYING=1`) plus Test (Symlink als `.gitignore` → Abbruch, nichts geändert).
- [ ] `scripts/checks/tests/factory-lock-tests.sh` („Verdrahtung“, je zwei Zeilen „(Mutation)“ für Hooks und CI-Job): Die Mutationsbelege sind Tautologien. `grep -vF <zeile> | grep -qF <zeile>` scheitert immer, egal ob der Guard taugt; sie beweisen nichts über die davor stehende Präsenz-Assertion (Lesson „Mutationsbeleg muss denselben Assert-Ausdruck ausführen“, aus nothra/tch-gastro-services#286). Fix: Guard als Funktion (wie `ci_ok_22` in der Projekt-Suite) und dieselbe Funktion einmal auf Original, einmal auf die Mutante anwenden.
- [ ] `scripts/checks/pre-push.sh`: Das Gate ist nur per Grep belegt, nur `pre-commit.sh` hat einen Verhaltenstest (Lesson nothra/tch-gastro-services#431: je Konsument ein eigener Test). Ein Test mit `mk_feature_repo` + echtem `pre-push.sh` (Vorbild nothra/tch-gastro-services#149) oder zumindest ein Lauf mit manipulierter Datei fehlt.
- [ ] `docs/factory/OPERATING.md`: Die Betriebsanleitung nennt nur `factory-sync.sh --compose` (Zeile 484). Abholen (`<version> [--adopt]`), das Gate (lokal/`--ci`) und der Job `factory-integrity` sind dort nicht beschrieben; Lesson „Doku im Präsens beschreibt eine Mechanik“ (aus nothra/tch-gastro-services#176). Kurzer Abschnitt reicht (Aufruf, Exit-Codes, Fehlerbild „Änderung gehört nach `nothra/dev-factory`“).

## Nitpicks (optional)
- [ ] `scripts/factory-sync.sh` (`collect_diverging`, `clone_and_verify`) und `scripts/checks/factory-integrity-check.sh` (`check_files`): derselbe Hash-Vergleich (`awk … want[$2] != $1`) und derselbe `jq … | sort`-Aufbau der Soll-Tabelle stehen dreimal. In die Lib auslagern (`fl_manifest_tsv`, `fl_diff_hashes`).
- [ ] `scripts/factory-sync.sh` (`run_pull`): `path` ist nicht `local` deklariert (läuft über Schleifen, aber globaler Zustand).
- [ ] `scripts/checks/tests/factory-lock-tests.sh`: ungenutzte Variablen (`a` in `reject_23`, `before_23` in Szenario w1, `out_23` im FS-T2.1-Fall); `shasum` wird in den Test-Helfern direkt gerufen statt über die Lib-Wahl (`sha256sum`-only-Umgebungen).
- [ ] `scripts/checks/factory-integrity-check.sh` / `factory-sync.sh`: Fehlt `factory-integrity-check.sh` im Konsumenten, meldet `precheck_local_state` „lokal geändert oder Lock ungültig“ statt „Check fehlt“.

## Positives
- Zwei-Phasen-Ablauf wie in ADR-063 E4: Phase 1 schreibt nichts, Phase 2 mit Backup und `trap`-Rückbau; Lock zuletzt; jede Abbruchstelle hat einen Test, der die Messung bricht (Stubs für `curl`, `git`, Hash-Werkzeug, nicht beschreibbares Ziel).
- Versionsmuster vor jedem Netzzugriff, `--`-Trennung bei `git clone`, `./`-Präfix beim Hashen, Pfad-/Duplikat-/Projektbereich-Prüfung im Manifest – saubere Eingabehärtung.
- Ein Hash-Aufruf für alle Dateien, `-e || -L`-Moduswahl, `lock.repo == upstream.repo` (Lock nie Quelle) umgesetzt.
- Mutationsbeleg für den Manifest-Vergleich der CI-Stufe ist echt (Mutant läuft und besteht die Manipulation).
- Compose-Tests konsumenten-neutral umgestellt, Vorher/Nachher-Liste in der Task-Datei, Guard „Factory-Repo trackt kein `factory.lock`“.

## Empfehlung
NEEDS_REWORK
