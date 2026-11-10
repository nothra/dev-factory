# Security Review: Task 52

Geprüft: `git diff origin/main...HEAD` (Stand `739c1e0`), Schwerpunkt `scripts/checks/tests/lib/test-groups.sh`,
`scripts/checks/tests/lib/factory-lock-fixtures.sh`, die fünf Gruppen `factory-lock-{23,24a,24b,37a,37b}-tests.sh` und
die Änderungen an `scripts/checks/tests/run-tests.sh`. Threat Surface: reine Test-Infrastruktur, läuft lokal (pre-push)
und im CI-Job `factory-self-test` ohne Secrets; kein Produktionscode, keine neue Dependency, kein Netzzugriff
(Fixtures über `file://`).

## Kritische Findings (Blocker)
- keine

## Wichtige Findings
- keine

## Hinweise
- [x] [Integrität Ergebnisvertrag] Die Ergebnisdatei einer Gruppe ist gegen Fälschung durch getestete Skripte geschützt:
  `test-groups.sh:14-15` übernimmt `FACTORY_TEST_GROUP_RESULT` in eine **nicht exportierte** Variable und entfernt die
  Umgebungsvariable, bevor ein Kindprozess läuft; der Exit-Status kommt aus einer separaten `.rc`-Datei des Wrappers,
  nicht aus dem Log. Test `#52 D3: weder eine RESULT-Zeile im Log noch ein Kindprozess …` belegt beides. Kein Handlungsbedarf.
- [x] [Temp-Dateien] Alle neuen Verzeichnisse entstehen per `mktemp -d` (Modus 0700, nicht vorhersagbar); `rm -rf` nur
  auf nicht-leere, selbst erzeugte Pfade (`test-groups.sh:113`, `test_group_trap`). Logs enthalten nur Fixture-Tokens
  (`GOOD_TOKEN_24="pat-gueltig-24"`) und werden nach dem Sammeln bzw. bei INT/TERM entfernt. Kein Handlungsbedarf.
- [x] [Token-Trennung #24/#37] Die Security-Assertions zu `FACTORY_SYNC_TOKEN`/`GH_TOKEN`/`GITHUB_TOKEN` sind
  unverändert übernommen (AK5/AK6); `unset GITHUB_ACTIONS GITHUB_OUTPUT` steht wie an der alten Stelle vor den #24-Fällen
  (`factory-lock-fixtures.sh:138`), damit kein Test in die `GITHUB_OUTPUT`-Datei des echten CI-Jobs schreibt. Geprüft:
  Die Gruppen starten jetzt vor den Exporten in `run-tests.sh:84`/`:345` (`FACTORY_*_COMMAND`, `FACTORY_HEALTHCHECK_*`);
  die Gate-Kommandos entfernt die Fixture-Lib selbst (`:24`), auf `FACTORY_HEALTHCHECK_*` greift keine Gruppe und keines
  der getesteten Skripte zu (Grep leer). Kein Verhaltensunterschied mit Sicherheitsbezug.
- [x] [Signal an fremde PID] `test_groups_cleanup` schickt TERM nur an Gruppen ohne `.rc`-Datei (Review W1). Restfall: ein
  per KILL hart beendeter Wrapper hinterlässt keine `.rc`; bricht die Suite danach **vor** dem Sammeln ab, ginge TERM an
  dessen freie PID. Folgen bleiben auf Prozesse desselben Benutzers begrenzt (kein Rechtewechsel), das Fenster setzt
  einen fremden KILL voraus – Zuverlässigkeits-, kein Sicherheitsrisiko; gleiche Klasse wie das Review-Nitpick
  „Cleanup nicht ganz idempotent" (Iteration 2). Akzeptiert, kein eigener Eintrag.
- [x] [Ausführung per Glob] Die Gruppenliste ist der Glob `factory-lock-*-tests.sh` (`run-tests.sh`, `TEST_GROUP_FILES_52`);
  früher wurde eine feste Datei gesourct. Damit liefe auch eine ungetrackte Datei mit passendem Namen mit. Keine neue
  Angriffsfläche: wer in `scripts/checks/tests/` schreiben kann, kann `run-tests.sh` selbst ändern; der Neutralitäts-Guard
  (`SHIPPED_TESTS_28`) prüft dieselbe Liste. Aktuell liegt dort keine ungetrackte/ignorierte Datei
  (`git ls-files --others --ignored` leer). Akzeptiert.
- [x] [Injection] Keine neuen `eval`-Stellen (die vorhandene in `factory-lock-24b-tests.sh:234` ist unverändert
  übernommen und wertet eine aus dem eigenen Skript gelesene Helper-Zeile aus). Gruppennamen stammen aus Dateinamen des
  Repos und werden nur gequotet verwendet; `strip_literal_37` übergibt Text per stdin und Literal per `ENVIRON`
  (keine Escape-/Code-Auswertung in `awk`).

Out-of-Scope-Funde nach ADR-018/ADR-043: keine (beide akzeptierten Restpunkte sind ohne Sicherheitsrisiko und ohne
Handlungsbedarf).

## Ergebnis
PASSED
