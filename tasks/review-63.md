# Review: Task 63

Grundlage: `git diff origin/main...HEAD` (5 Dateien, +285/−8), Spec `docs/specs/spec-63-ownership-check-nicht-ascii-pfade.md`.
Runden: 1 Backend/Logik, 2 Code-Qualität, 3 Architektur & Patterns (Personas aus `docs/factory/agents/review-agent.md`).

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] [tasks/task-63-ownership-check-nicht-ascii-pfade.md:27] AK8 verlangt laut Spec, dass Exit-Code, Erfolgszeile und
  `--list factory`/`--list project` im Repo selbst **identisch** zum Stand vor dem Fix sind. Belegt ist das nur per
  Argument, nicht per Vergleich. Das Argument stimmt: Pfade ohne `"`, `\`, Steuerzeichen und `|` kommen über
  `ls-files -z` + `tr '\0' '\n'` byte-gleich an, und Command Substitution schneidet abschließende Zeilenumbrüche in beiden
  Fassungen gleich ab. Der Beleg ist trotzdem ein Kommando (main-Fassung per `git show origin/main:… > tmp`, beide Fassungen
  mit `FACTORY_DIR=<repo>` in den drei Aufrufarten, `cmp`). In dieser Review-Session war er nicht freigegeben. Bis `/test`
  nachholen und das Ergebnis unter AK8 eintragen.

## Nitpicks (optional)

- [ ] [scripts/checks/ownership-check.sh:52] `raw="$(mktemp)"` ohne Trap. Bricht das Skript zwischen `mktemp` und `rm` ab
  (Signal, `set -e` bei einem `tr`-Fehler in Z. 61), bleibt eine Temp-Datei mit der vollständigen Pfadliste liegen.
  Scheitert `mktemp` selbst, endet das Skript unter `set -e` mit Exit 1, also „Fund“ statt fail-closed Exit 2. Beides ist
  nicht fail-open. Abhilfe: `raw="$(mktemp)" || { …; exit 2; }` plus `trap 'rm -f "$raw"' RETURN`, oder den Lese-Schritt in
  den späteren `WORK_DIR` verlegen.
- [ ] [scripts/checks/ownership-check.sh:50] Der Kommentar „Geprüft wird per `tr` und nicht per Command Substitution“ liest
  sich wie ein Widerspruch zu Z. 56, die `$(…)` nutzt. Gemeint ist: nicht den Rohinhalt in eine Variable lesen. So
  formulieren, z. B. „nicht über eine Shell-Variable: die schnitte NUL-Bytes und abschließende Zeilenumbrüche ab“.
- [ ] [scripts/checks/ownership-check.sh:56] Die doppelte `tr`-Kette (`tr -cd '\n' | tr '\n' x`) ist korrekt, aber erst
  nach kurzem Nachdenken lesbar. Das zweite `tr` gibt es nur, weil `$(…)` reine Zeilenumbrüche wegschneiden würde.
  `[ "$(LC_ALL=C tr -cd '\n' < "$raw" | wc -c)" -ne 0 ]` sagt dasselbe direkter.
- [ ] [scripts/checks/tests/run-tests.sh:8372] `OWN_CHECK_63` ist dieselbe Variable wie `OWN_CHECK_22`. `own_repo_63`
  verallgemeinert den Inline-Aufbau aus F-22.3 (Z. 8263–8269), der Test-Aufbau steht also zweimal. F-22.3 auf den neuen
  Helfer umzustellen gehört nicht in diesen Scope (Spec: nur `ownership-check.sh` + neue Tests). Erwähnt nur für einen
  späteren Aufräum-PR, kein `kleinfunde.md`-Eintrag nötig.

## Positives

- **Ursache statt Symptom:** `ls-files -z` löst alle Quoting-Fälle (`"`, `\`, Tab, Nicht-ASCII) auf einmal, statt
  git-Quoting nachzuparsen. Die Spec-Analyse (`core.quotepath=false` deckt nur Bytes > 0x7F ab) trägt das sauber.
- **Fail-open geschlossen:** `-F'|'`/`NF == 1` weg, jede Zeile ist ein Pfad (AK3/AK4). Das `split(line, cell, "|")` der
  Tabellenzeilen setzt den Trenner explizit und hängt damit nicht an `FS`. Die Änderung ist also lokal.
- **Zeilenumbruch fail-closed in beiden Modi:** Die Prüfung sitzt im gemeinsamen Lese-Schritt, nicht doppelt je Modus.
  Im Lock-Modus greift sie nach `lock_require_inputs` und vor dem Workspace, das passt zur bestehenden Reihenfolge. Der
  Test deckt alle 6 Kombinationen (Modus × Aufrufart) mit Exit-Code, stderr-Meldung und leerem stdout ab.
- **Tests gegen echtes git** mit explizit gesetztem `core.quotepath true`, also unabhängig von globaler Konfiguration.
  Tabelle, Lock und Anpassungsstellen liegen bewusst ungetrackt daneben, die getrackte Menge bleibt exakt. Listen werden
  bytewise sortiert verglichen.
- **AK7-Mutationsbeleg** mit Zahlen je AK. Ehrlich vermerkt ist, dass AK3s Exit-0-Assertion schon vorher grün war, gerade
  wegen des fail-open.
- **Scope-Disziplin:** `OWNERSHIP_FILE_LIST` und das `--list`-Format bleiben unverändert (Spec „nicht inbegriffen“). Der
  Nebenfund (leere Null-Zählung in der Erfolgszeile) steht korrekt als `kleinfunde.md`-Eintrag mit verifizierter Zeile 236
  im Schema des Dateikopfs.
- **Architektur/Projektregeln:** Die neuen Tests liegen in der ausgelieferten Suite und sind konsumenten-neutral, sie
  setzen weder `OWNERSHIP.md` noch `ci.yml` dieses Repos voraus (Factory-ADR-064 D6). Neue Dateien sind über
  `docs/specs/**` bzw. `tasks/**` in `OWNERSHIP.md` zugeordnet. Kein ADR-Trigger, keine Herkunftsbegriffe, Verweise
  korrekt qualifiziert.

## Empfehlung

APPROVED
