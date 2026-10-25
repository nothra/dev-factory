## Codify-Report: Task 22

Quelle: Task-Datei, Review-Report (3 Iterationen), Security-Report, Coverage-Report, Verlauf der Nacharbeiten. Zuordnung der Learnings: alle betreffen Factory-Dateien
(Skripte, Gates, Self-Tests, Guidelines) → `docs/factory/lessons/` und `docs/factory/guidelines/`.

### Neue Regeln hinzugefügt
- `docs/factory/guidelines/bash-gotchas.md` **#14** – `echo "$wert"` mit fremdem Wert: führendes `-n`/`-e`/`-E` ist eine Option, der Wert geht verloren – wegen: Fail-open im Fundzähler von
  `ownership-check.sh` (Lock-Pfad `-n` → Exit 0), erst bei der Gegenprüfung des `/security-review` gefunden.
- `docs/factory/guidelines/bash-gotchas.md` **#15** – Rückgabewerte als Zähler laufen modulo 256 um (kein Deckel bei 255) – wegen: falsche Fundzahl („255 Fund(e)“ bei 300), bei 256 wäre das Ergebnis 0.
- `docs/factory/guidelines/bash-gotchas.md` **#16** – `git ls-files` quotet Nicht-ASCII-Pfade (`core.quotepath`); Test gegen echtes git und vom globalen Config isoliert – wegen: Lock-Pfad `docs/für.md` als „nicht getrackt“.
- `docs/factory/guidelines/bash-gotchas.md` **#17** – `[ -e … ]` folgt Symlinks: hängender Symlink als Moduswahl-Datei fällt still zurück (`-e || -L`) – wegen: stiller Rückfall in den Tabellenmodus (F-22.1).
- `docs/factory/guidelines/bash-gotchas.md` **#18** – Ungequotetes Heredoc/Doppelquotes führen Backticks aus (Markdown-Text immer über `<<'EOF'` oder Datei) – wegen: zweimal in dieser Session (`command not found: factory`).
- `docs/factory/lessons/factory-workflow.md` – **Konsumenten-Neutralität per Fixture-Lauf messen** (44 rote Tests → 0; `NO_LOCK_FILE`, `FACTORY_SELF_TEST_RUN`, Aufruf-Trace für den Zählvergleich, hartes `source`) – wegen: Test-Schnitt dieser Task.
- `docs/factory/lessons/factory-workflow.md` – **Verfolgungs-Aussage braucht die Issue-Nummer, bevor der Satz steht** – wegen: ADR-064 „wird als Folge-Issue verfolgt“ ohne Issue (Review-Iteration 2 und 3).
- `docs/factory/lessons/factory-workflow.md` – **Gate mit Moduswahl per Dateiexistenz: `-e` und `-L`, Guard-Test, Modus für Tag-Konsumenten erzwingen** – wegen: `factory.lock` im Factory-Repo schaltet die Tabellenprüfung ab; Manifest-Skript brauchte den erzwungenen Tabellenmodus.
- `docs/factory/lessons/factory-workflow.md` – Rezidiv im bestehenden Eintrag „Review-Sub-Agent kann eine falsche Bash-/Shell-Verhaltensbehauptung …“ (**False-Negative**: „nicht betroffen“ für Fremdwerte in `echo` war falsch) – wegen: Security-Agent und drei Review-Runden hatten das Fail-open nicht gesehen.
- `docs/factory/lessons/testing.md` – **Zeilenabdeckung für Bash ohne Coverage-Werkzeug per xtrace-Wrapper** (bash 3.2: kein `BASH_XTRACEFD`; Mutationsbeleg je fail-closed-Pfad) – wegen: vier ungetestete fail-closed-Pfade in `/test`.
- `docs/factory/PROJECT-CONTEXT.md` – vier neue Index-Zeilen mit „Laden bei“-Trigger (Testing-Gruppe, Factory-Workflow-Gruppe) und die Rezidiv-Ergänzung an der bestehenden Zeile; @import-Dauerkontext 765 von 1100 Zeilen.

### Muster über die Iterationen
- **Fail-open durch Fremdwerte in Zählern/Sammelschleifen** war der einzige Fund mit Sicherheitsrelevanz; er lag in Code, den drei Review-Runden und ein Security-Lauf gelesen hatten. Wirksam war die Gegenprobe mit einem
  konkreten Eingabewert (`-n`), nicht das Lesen. → Gotcha #14 + die Regel „Test mit `-n`/`-e`/`-E` zu jeder Sammelschleife über fremde Zeilen“.
- **Texte behaupten Zustände, die es nicht gibt** (ADR: „Folge-Issue“, falsche Kommentare zu `NOJQ_TOOLS_22`/„gekappt“): in jeder Review-Iteration kam mindestens ein Fund dieser Art. Die bestehende Lesson (#211: Text beim PR nachziehen) greift
  nicht, wenn der Text von Anfang an etwas Geplantes als Tatsache formuliert. → neue Lesson „Verfolgungs-Aussage braucht die Nummer“.
- **Was gut funktioniert hat:** Fixture-Lauf als Messinstrument (statt Lesen), Mutationsbelege auf Skript-Kopien, Test-zuerst auch bei Review-Funden (RED vor GREEN je Fund), Zählvergleich vorher/nachher in Task-Datei und PR.

### Keine Änderungen nötig
- `CLAUDE.md` und `docs/factory/FACTORY.md`: keine neue Kernregel; die Learnings sind Gotchas/Lessons, kein Prinzip.
- `docs/factory/guidelines/clean-code.md`/`testing-standards.md`: keine Ergänzung (der Dauerkontext ist gedeckelt; die Regeln stehen bedarfsgesteuert in Gotchas/Lessons).
- Kein neuer Check in `scripts/checks/`: ein Gate gegen `echo "$var"` mit Fremdwert wäre ein Lint-Thema – bereits als Issue #14 (ShellCheck als Lint-Gate) geführt; die Tests sichern die konkrete Stelle.

### Folge-Arbeit (klassifiziert)
- Bereits angelegt: #26 (Ruleset: `project-self-test` als Required Check), #27 (ausgelieferte Verweise auf `OWNERSHIP.md`), #28 (Zweifel: ausgelieferte Suite liest projekteigene Dateien).
- In `docs/factory/kleinfunde.md`: Hook-Fortschrittsanzeige, zusammengesetzte Ziele in `customization-points.txt`, `jq`-Vorabprüfung (Erst-Einbindung, Bezug #23), Lock-Pfade mit Zeilenumbruch.
- Nicht neu angelegt: SHA-Pinning der GitHub-Actions (bestehender Standard, Querschnittsthema).

### Empfehlung für nächste Features
- Bei jedem Check, der fremde Zeilen sammelt/zählt: Tests mit `-n`, Zeilenumbruch, Umlaut, CRLF und mehr als 255 Treffern gleich in der ersten Test-Runde anlegen – vier der Review-Funde dieser Task waren genau diese Randfälle.
- Vor dem Schreiben eines ADR-Satzes „wird verfolgt“ das Issue anlegen; vor dem Abschluss einer Check-Skript-Task die Zeilenabdeckung per xtrace messen.
- #23 (Abholen, `factory.lock`, Integritäts-Gate) setzt auf dem Lock-Format dieser Task auf: `jq` als Voraussetzung vorab prüfen und `OWNERSHIP.md` nicht als zu lieferndes Artefakt erwarten (Q-22.5).
