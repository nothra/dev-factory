# Review: Task 52

Iteration 1 · Stand `36090e4` · Diff `origin/main...HEAD` · drei Runden (Logik, Code-Qualität, Architektur), parallel als
Lese-Agenten gefahren, Kritisch-/Wichtig-Funde vom Koordinator gegen den Code nachgelesen. Proben im `$TMPDIR` waren in
dieser Session nicht freigegeben: Aussagen zur Shell-Semantik sind aus dem Code abgeleitet und als solche markiert.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] **W1** `scripts/checks/tests/lib/test-groups.sh:98-104` – `test_groups_cleanup` schickt bei Abbruch (Ctrl-C/TERM vor
  dem Sammeln) `kill -TERM` an **jede** Gruppen-PID mit leerem `TEST_GROUP_RCS`. Vor `test_groups_collect` ist das jede
  Gruppe, auch eine längst beendete (Gruppen fertig nach ~140 s, Sammeln erst bei ~330 s). bash hat deren Wrapper schon
  gereapt; die PID ist frei. Die Task-Datei belegt selbst, dass genau diese PIDs im Lauf wiederverwendet werden
  (Umsetzung, „Abweichung vom ADR beim Exit-Status"). Folge: Ein Ctrl-C kann SIGTERM an einen fremden Prozess desselben
  Nutzers schicken (Nachbar-Session, Editor). Fix: nur beenden, wenn `"$TEST_GROUPS_DIR/$i.rc"` fehlt. Regressionstest:
  Stub-Gruppe fertig, dann TERM an den Treiber, Gruppen-PID durch einen Wächterprozess „besetzt" bzw. per Trace prüfen,
  dass kein `kill` an eine Gruppe mit `.rc` geht. (Abgeleitet aus Code + dokumentierter PID-Wiederverwendung, kein Repro.)
- [ ] **W2** `scripts/checks/tests/run-tests.sh:40` (`for group_52 in 23 24a 24b 37a 37b`), `:9074-9078`
  (`SHIPPED_TESTS_28`), `:9368` (`test_groups_collect`) – Die Gruppenliste steht von Hand an zwei verdrahteten Stellen (dazu
  in Kommentaren `lib/factory-lock-fixtures.sh:5`, `run-tests.sh:9366`). Kein Guard prüft, dass jede Datei
  `factory-lock-*-tests.sh` gestartet und in `SHIPPED_TESTS_28` geführt wird. Ein künftiges `…-24c-tests.sh` liefe nie und
  entginge auch dem Neutralitäts-Guard #28 – still grün. Ebenso fiele ein verlorener `test_groups_collect`-Aufruf nicht auf:
  `test_groups_cleanup` beim EXIT beendet nicht gesammelte Gruppen kommentarlos, der Exit-Code bleibt 0. Fix: Glob
  `"$CHECKS_DIR"/tests/factory-lock-*-tests.sh` an beiden Stellen (sortiert in derselben Reihenfolge, auf die 24b/37b ohne
  eigenen Abschnittskopf bauen) **und** im EXIT-Pfad jede nicht zusammengeführte Gruppe als rote Assertion zählen bzw.
  `exit 1` erzwingen (D4-Geist: ein fehlendes Teilergebnis ist nie grün). Test mit Stub-Treiber ohne Sammeln.
- [ ] **W3** `docs/factory/adr/066-self-test-gruppen-parallel.md:73-81` – ADR beschreibt die umgesetzte Mechanik nicht
  (Lesson nothra/tch-gastro-services#211). D3 sagt „als **letzte Zeile** `RESULT …`", der Code verlangt die **einzige** Zeile
  (`test-groups.sh:7`, Regex über den ganzen Inhalt). D4 nennt „drei Fälle", der Code hat vier (`test-groups.sh:67-69`:
  „abgebrochen, kein Exit-Status"). Der Wrapper mit `.rc`-Datei, das Weiterreichen von TERM und der Grund (PID-Wiederverwendung)
  fehlen ganz; die Task-Datei nennt es selbst „Abweichung vom ADR". Dazu: D2 (`:68`) nennt noch `factory-lock-24-tests.sh`
  statt 24a/24b; die Regel für künftige Gruppen (`:159-161`) nennt `CHECKS_DIR`/`SCRIPTS_DIR`/`HAS_YQ`/`FACTORY_ROOT` „aus dem
  Hauptprozess" – keine davon wird exportiert (`run-tests.sh:21`, `:88`), die Gruppen holen `FACTORY_ROOT`/`HAS_YQ` aus den
  eigenen Libs; ein Shard mit `$CHECKS_DIR` bräche unter `set -u` ab. Gleicher Satz in der Task-Datei (Fallen-Liste). Fix:
  D3/D4/D2/Konsequenzen nachziehen, Ergebnis AK3 (353 s, Rest der Suite ist der Engpass, #334-Versuch ohne Nutzen) als
  Satz in „Konsequenzen".
- [ ] **W4** `docs/specs/spec-52-self-test-suite-beschleunigen.md:61-66, 77-80` gegen Task-Datei AK1/AK5 – Spec-Drift bei
  zwei abgehakten AK (Lesson nothra/tch-gastro-services#388). **AK5** verlangt „Anzahl gleich"; die Task-Datei hakt ab mit
  eigener „Auslegung" (2466 = 2444 + 22). Die 22 neuen sind von ADR-066 gefordert und gut begründet, aber die Spec trägt
  weder Q-Eintrag noch angepassten AK-Wortlaut. **AK1** verlangt die Dauer je Abschnitt auch in CI; belegt ist nur die
  Job-Gesamtdauer inkl. Setup (`gh run view`/`gh api` nicht freigegeben). Fix: AK5-Wortlaut in Spec und Task-Datei
  anpassen („alle alten unverändert, neue nur für den neuen Mechanismus, aufgelistet") mit Q-Eintrag; AK1-CI-Teil entweder
  nachmessen oder als Abweichung in der Spec vermerken und das Häkchen entsprechend setzen.
- [ ] **W5** `scripts/checks/tests/run-tests.sh` (F5/AK14-Test, ~`:9345-9355`) – kann aus dem falschen Grund grün werden
  (Lesson Task #37 „Feindcode lief nie", nothra/tch-gastro-services#214). Die Warteschleife gibt nach 100 × 0,1 s ohne
  Prüfung auf; wurde `slow.pid` nie geschrieben, bleiben `slow_pid_52`/`slow_dir_52` leer bzw. ungesetzt. Mit leeren Werten
  sind `! kill -0 ""` und `[ ! -e "" ]` wahr; unter `set -u` bricht die Kommandosubstitution ab, liefert leeren Text, und
  `assert_true` wertet `[[ "" -eq 0 ]]` als grün. Gleiches Muster bei D5 (`:9324`): `[ ! -e "$(cat groups-dir)" ]` ist
  auch bei leerer/veralteter Datei wahr, `groups-dir` wird zwischen den `drive_52`-Läufen nicht gelöscht. Fix: vorab
  `[ -s slow.pid ] && [ -n "$slow_pid_52" ]` bzw. `rm -f groups-dir` vor jedem Lauf und `[ -n … ]` assertieren.
  (Abgeleitet, Repro nicht freigegeben.)
- [ ] **W6** PR #54 / Issue #52 – Der PR-Body ist nur `Closes #52`. AK3 ist verfehlt und „eskaliert", aber die Eskalation
  steht nur in der Task-Datei: kein Folge-Issue, kein PR-Kommentar, kein Hinweis im Body. Ein Merge schlösse #52 ohne
  Entscheidung. Fix (menschlicher Schritt vor dem Merge): Entscheidung zu AK3 treffen (Folge-Issue „Prozess-Starts je
  Assertion senken" **mit Nummer** in Task-Datei/ADR, oder AK3 anpassen) und im PR-Body die Abweichung nennen.
- [ ] **W7** `FACTORY_SELF_TEST_SERIAL=1` ist nur in ADR-066, Spec, Task-Datei und Code-Kommentaren dokumentiert, nicht in
  `docs/factory/guidelines/testing-standards.md`, `docs/factory/OPERATING.md` oder `PROJECT-CONTEXT.md` (Build/Test-Block).
  ADR-066 D6 nennt den Schalter als Rückfall für ressourcenknappe Runner und Konsumenten – die finden ihn so nicht. Ebenso
  fehlt die Pflicht für künftige Testgruppen (eigenständig, eigene Vorlage, `test_group_finish`) in `testing-standards.md`.
  Fix: je ein kurzer Absatz in `testing-standards.md` (+ eine Zeile im Build/Test-Block).

## Nitpicks (optional)

- [ ] `run-tests.sh` (D1-Test, `stub_52 green` mit `sleep 1`) – Überlappung hängt am Timing; unter Load 8–12 (Task-Datei)
  möglich Falsch-Rot. Deterministischer: `green` wartet mit Timeout auf ein `other.started`-Marker.
- [ ] `run-tests.sh` (#52-Assertions D4/AK11, D6) – mehrere Sachverhalte je `assert_true` (Lesson
  nothra/tch-gastro-services#117); bei Rot nicht erkennbar, welcher Teil scheiterte.
- [ ] `run-tests.sh` (`PREWAIT_52`-Label) – „PID schon gereapt bzw. wiederverwendet": getestet ist nur „gereapt".
- [ ] `run-tests.sh` – `t_52` doppelt belegt (Zeitdifferenz in F5, Text in der D7-Schleife); „(11 Fälle)" im Label ist
  handgezählt.
- [ ] `test-groups.sh:28-30` – TERM-Trap des Wrappers erst nach dem Start der Gruppe; TERM in diesem Fenster ließe die
  Gruppe verwaist weiterlaufen. Trap vor dem `&` setzen.
- [ ] `lib/factory-lock-fixtures.sh:45-78, :121` – `factory_lock_setup` prüft nur den Status der letzten `&&`-Kette von
  `build_template_23`; ein früher gescheiterter Schritt (z. B. `mk_manifest_23` v3.0.0) liefe weiter (F1 nicht dicht).
  `mk_manifest_23` legt seine Temp-Datei außerhalb von `T23` an (`:33`) – bei TERM bleibt sie liegen (AK14).
- [ ] Shard-Köpfe (`factory-lock-*-tests.sh:10-16`) – derselbe ~7-Zeilen-Startblock fünfmal; optional ein
  `factory_lock_group_init [24]`.
- [ ] Doppelte Leerzeilen `factory-lock-24a-tests.sh:23-24`, `factory-lock-23-tests.sh:450-451`.
- [ ] Task-Datei AK10/AK11 – „(entfällt ohne Parallelisierung)" ist Rest aus `/requirements`, Parallelisierung ist umgesetzt.
- [ ] Out of Scope (Schritt B): Konvention „`#<nr>` in Testnamen = Ursprungs-Repo" (`run-tests.sh:16-17`) stimmt für die
  Factory-Issues nicht mehr → Eintrag in `docs/factory/kleinfunde.md` angelegt.

## Positives

- Ergebnisvertrag echt fail-closed: Ergebnis getrennt vom Log, Regex über den ganzen Inhalt, „Exit ≠ 0 bei fail = 0" rot,
  Pfad der Ergebnisdatei vor jedem Kindprozess aus der Umgebung entfernt – der `fake`-Stub belegt, dass weder Log noch
  Kindprozess das Ergebnis fälschen.
- Je Fail-Pfad eigene Meldung und eigener Stub-Test (abort, badresult, exitnofail, signal, wrapkill, fake), 14 Mutanten rot.
- Der PID-Wiederverwendungs-Befund im ersten Volllauf sauber diagnostiziert, mit Regressionstest (`PREWAIT_52`) und
  WHY-Kommentar.
- D7 (`strip_literal_37`) mit Äquivalenztest über Glob-, Escape-, Zeilenumbruch- und Leer-Fälle und Vergleich auf der
  ganzen ADR-063; größter Einzelhebel.
- Saubere Teilung: Rümpfe per `sed`-Zeilenbereich geschnitten, jede Gruppe allein lauffähig, eigene Vorlage mit
  AK8-Fingerprint; AK9 in umgekehrter Reihenfolge nachgewiesen.
- Konsumenten-Neutralität geprüft: Shards und Libs lesen nur Dateien der Seite `factory`; `SHIPPED_TESTS_28` erweitert;
  `FACTORY_ROOT`-Ableitung stimmt auch im Konsumenten-Layout; OWNERSHIP über Globs abgedeckt.
- Nebenläufigkeit geprüft ohne Befund: der Rest der Suite verändert keine echte Repo-Datei (`sed -i`/`mv`/`chmod` nur auf
  Temp-Pfaden), kein blankes `wait` außer im Stub-Treiber.
- Ehrliche Messung: AK3 nicht schöngerechnet, Fehlversuch (#334 als Gruppe) mit Ursache dokumentiert und zurückgenommen.

## Empfehlung
NEEDS_REWORK
