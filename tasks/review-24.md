# Review: Task 24

Diff-Basis: `git diff origin/main...HEAD` (490e6d9). Spec: `docs/specs/spec-24-factory-update-workflow-update-pr.md`,
Entscheidungen: Factory-ADR-063 Nachtrag 2026-10-30 (E10–E16). Drei Runden (Logik, Code-Qualität, Architektur)
im Orchestrator-Kontext, ohne Fork-Delegation. Ausgelieferte Suite `scripts/checks/tests/run-tests.sh` lokal:
2084 grün, 0 rot (Exit 0) – das kritische Finding liegt außerhalb dessen, was die Suite heute abdeckt.

## Kritische Findings (müssen behoben werden)
- [x] [scripts/factory-update.sh:206] **Das laufende Skript wird während des Laufs überschrieben – nach `main` liest bash
  weiter aus der neuen Version.** In CI läuft `bash scripts/factory-update.sh` aus dem Checkout des Konsumenten, und genau
  diese Datei ist eine übernommene Factory-Datei im Manifest. `factory-sync.sh` schreibt sie in `install_file`
  (`scripts/factory-sync.sh:274`) per `cp -p` **auf denselben Inode**. Bash liest Skripte stückweise und setzt
  nach `main "$@"` am alten Byte-Offset fort – in der **neuen** Datei. Im Erfolgsfall (`publish_pr` → `main` kehrt normal
  zurück) führt der Lauf also beliebige Zeilen der Zielversion aus, wenn diese `factory-update.sh` verlängert: Syntaxfehler,
  ein falscher Exit-Code oder ein zweiter `main`-Aufruf. Auslöser ist jede Version, die das Skript länger macht.
  Repro (Wegwerf-Skript, gelöscht): `main() { cp "$NEWVER" "$0"; echo fertig; }; main "$@"` mit einer längeren Ersatzdatei →
  Ausgabe `fertig`, danach `AUSGEFUEHRT-AUS-NEUER-VERSION`, `rc=7`. Die Suite sieht den Fall nicht, weil `upd_24`
  (`scripts/checks/tests/factory-lock-tests.sh:585-588`) das Skript aus `$FACTORY_ROOT` startet und nicht die Kopie in `C1`
  (Lesson nothra/tch-gastro-services#431 „Bash liest Skripte inkrementell", hier zur Laufzeit in Produktion).
  **Fix:** die Aufrufzeile so schreiben, dass bash nach `main` nichts mehr aus der Datei liest, z. B. `main "$@"; exit $?` auf
  **einer** Zeile (oder `{ main "$@"; exit; }`); WHY-Kommentar dazu. **Test:** E2E-Fall, in dem das Skript aus dem
  Konsumenten-Checkout läuft (`bash "$C1_23/scripts/factory-update.sh"`) und die Zielversion im Upstream-Fixture eine
  längere `scripts/factory-update.sh` mit einer erkennbaren Zeile am alten Offset liefert; Mutationsbeleg (`exit` entfernt →
  rot).

## Wichtige Findings (sollten behoben werden)
- [x] [scripts/checks/tests/factory-lock-tests.sh:730] **Der Testkommentar behauptet ein Verhalten, das weder geprüft noch
  umgesetzt ist:** „eine Marke in den Release Notes [sperrt] auch nicht". Der Test darunter prüft nur den Fork-PR; die
  Release-Liste des Falls hat den Body `Notes v1.1.0` ohne Marke. Die Prüfung in `scripts/factory-update.sh:130-131` sucht
  die Marke per `contains($m)` im **ganzen** Body, also auch in den eingebetteten Release Notes. Fall: die Notes einer
  übersprungenen Version zitieren das Markenformat mit der Zielversion, etwa ein CHANGELOG-Abschnitt, der dieses Feature
  beschreibt. Wird der PR ohne Merge geschlossen, sperrt das die Version, obwohl der PR für sie gar nicht gebaut war.
  Das Risiko ist klein, aber der Kommentar ist eine falsche Zusicherung (Lesson „X erzwingt Y", nothra/tch-gastro-services#319).
  **Fix:** entweder die Marke nur im Kopf des Bodys suchen (vor der ersten `## `-Überschrift; der Body wird in
  `write_body` mit fester Reihenfolge erzeugt) und einen Test mit Marke in den Notes ergänzen, oder den Halbsatz aus dem
  Kommentar streichen.

## Nitpicks (optional)
- [x] [scripts/factory-update.sh:69] `.permissions.push` aus `GET /repos/{repo}` gibt vermutlich die Rolle des
  **Token-Besitzers** im Repo wieder, nicht die Rechte eines Fine-grained PAT (unverifiziert, offline nicht prüfbar).
  Dann käme ein Token mit nur *Contents: read* durch die Prüfung und scheitert erst beim Push bzw. bei `gh pr create`.
  Der Lauf bleibt rot (fail-closed), aber nicht „vor jedem weiteren Schritt" (FS-T2.3, Fall „zu wenig Rechte"). Beim
  ersten echten Lauf (T2a-4) mit einem Token ohne Schreibrecht gegenprüfen, sonst die Meldung bzw. `OPERATING.md` §0.6
  ehrlich formulieren.
- [x] [scripts/factory-update.sh:43] `ORIG_REF` steht zwischen `die`/`note` und `cleanup`, getrennt von `WORK` (Z. 38).
  Beide Zustandsvariablen zusammen deklarieren.
- [x] [scripts/checks/tests/factory-lock-tests.sh:746,790] Weltnamen aus der Byte-Länge des Testwerts (`g$(… | wc -c)`,
  `r$(…)x`) sind nur zufällig eindeutig. `world_23` bricht zwar fail-closed ab (gut), aber ein neuer Testwert gleicher Länge
  bricht die Suite. Ein Zähler wäre robuster.

## Positives
- Die Reihenfolge aus E11 ist genau umgesetzt: Moduswahl per `-e`/`-L` (inkl. hängendem Symlink als Test), Token-Prüfung
  vor jedem Netzaufruf, `GITHUB_TOKEN` per `unset` hart entfernt und im Stub-Protokoll als nie angekommen belegt.
- Push mit `--force-with-lease` auf den gelesenen SHA, inklusive eines echten Race-Tests über einen git-Wrapper, der einen
  Fremd-Push dazwischenschiebt. Das ist stärker, als die Spec verlangt.
- Credential-Helper ohne Token in argv oder `.git/config`, mit Verhaltenstest über `git credential fill` und Negativprüfung
  auf `.git/config`.
- AK2.2d wird über Tree-Gleichheit gegen eine direkte Abholung belegt, nicht über Einzeldateien. F3/AK-24a prüfen die
  Reihenfolge der Überschriften per Positionsvergleich (Lesson nothra/tch-gastro-services#286).
- Die Mutationsbelege für Token-Prüfung und Fork-Bedingung ersetzen die volle Aufrufzeile und belegen per Zählung, dass
  genau diese Zeile ersetzt wurde (Lesson nothra/tch-gastro-services#310). Der Wiring-Guard am Workflow hat eine eigene
  Mutation.
- Der Scaffold wird wiederverwendet (`world_23` → `world_24`) statt parallel gebaut, der `gh`-Stub liegt im Scaffold und
  die Git-Identität in Fixtures ist explizit gesetzt (Lessons nothra/tch-gastro-services#310/#314/#265).
- Die Doku ist vollständig nachgezogen: ADR-Nachtrag E10–E16, `OPERATING.md` §0.6 plus Verweis aus §5.5a, die Ausnahme
  in `git-workflow.md`, beide `OWNERSHIP.md`-Zeilen und der #431-Guard für Skriptverweise um `factory-update.yml`
  erweitert.
- Architektur: ADR-063 D2 (Pull statt Push), E10 (dünner Workflow) und ADR-029 (Check-Name unverändert) sind eingehalten.
  Keine Routen-Änderung, `docs/routes.md` ist nicht betroffen.

## Empfehlung
NEEDS_REWORK
