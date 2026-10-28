# Lessons: Testing & Coverage

> Ausgelagerte `/codify`-Learnings (Volltext) – generische Factory-Learnings zu **Testing & Coverage**.
> **Nicht** `@import`-geladen (ADR-037) – bei Bedarf gezielt lesen. Kanonische Quelle je
> Regel ist der jeweilige Eintrag hier; im @import-Pfad (`PROJECT-CONTEXT.md`) steht nur eine Index-Zeile.
> Neue Learnings kommen in die Lesson-Datei **ihrer Seite** (Zuordnungsregel: betrifft das Learning eine
> Datei der Factory laut `docs/factory/OWNERSHIP.md` → `docs/factory/lessons/`, sonst → `docs/project/lessons/`;
> siehe `/codify` + ADR-037).
> Projekt-Anteil dieses Themas: `docs/project/lessons/testing.md`.

### AC mit Direktive + Begründung: je separierbaren Teil eine eigene Assertion (aus nothra/tch-gastro-services#117, /test-Selbstfund)

Der `nothra/tch-gastro-services#117`-Doc-Guard prüfte, ob `pr-shepherd.md` Schritt 2 das Seam-**Kommando**
(`factory-commit.sh`) nennt – deckte damit aber nur AC1 ab. Die Task hatte ein zweites,
im selben Absatz stehendes Kriterium (AC2): die **fail-closed-Begründung mit ADR-019-Verweis**.
Kommando und Begründung stehen auf **getrennten, einzeln entfernbaren Zeilen** – ein
Presence-`grep` auf das Kommando lässt die Begründung ungetestet. Aufgefallen erst in `/test`,
nicht schon in `/implement`: der Reflex ist, den auffälligsten Token (das Kommando) zu prüfen und
den begleitenden Kontext (Rationale, ADR-Verweis, Warnung) als „mitgetestet" anzunehmen.

**Smell (erweitert nothra/tch-gastro-services#51):** „Entferne ich die **Begründung**, lasse aber das **Kommando** stehen –
schlägt ein Test fehl?" Wenn nein, ist das Begründungs-Kriterium ungetestet.

**Regel:** Bündelt ein Akzeptanzkriterium eine **Direktive** (Kommando/Config-Wert) **und** ihre
**Rationale** (Begründung, ADR-Verweis, Warnung), und liegen beide auf getrennt editierbaren
Zeilen, bekommt jeder separierbare Teil eine **eigene** Assertion – nicht einen gemeinsamen Grep.
Pflicht-Begleitung: Negativ-Nachweis, der die Unabhängigkeit belegt (Begründung entfernen →
Begründungs-Guard **rot**, Kommando-Guard **grün**). Deckt sich mit `testing-standards.md`
(je Kriterium ein Test) und der Positiv-**und**-Negativ-Beispiel-Regel aus `clean-code.md`.

### Neue gesourcte Lib in run-pipeline.sh → in ALLE Temp-Repo-Scaffoldings in run-tests.sh kopieren (aus nothra/tch-gastro-services#197)

`run-tests.sh` baut an mehreren Stellen eine minimale Pipeline-Repo-Kopie in `mktemp -d` auf und
startet `run-pipeline.sh` darin (Preflight-Cleanup, Phase-1b-End-to-End, Turn-Budget-Dry-Run,
`nothra/tch-gastro-services#101`-Lint-Gate …). Jede dieser Stellen kopiert die Laufzeit-Abhängigkeiten einzeln
(`config-validation-check.sh`, `factory.defaults.yml`, `lib/report-verdict.sh`). Sourct
`run-pipeline.sh` eine **neue** Lib (in nothra/tch-gastro-services#197: `lib/tier-select.sh`), bricht das `source` in genau
diesen Temp-Repos mit „No such file" ab – und zwar **nicht** in den Tests der neuen Lib (die kopieren
sie), sondern in **fremden**, bestehenden Tests (hier `nothra/tch-gastro-services#101`, 2 rote Tests, deren Ursache erst auf
den zweiten Blick sichtbar war).

**Smell:** „Ich habe `run-pipeline.sh` ein `source …/lib/<neu>.sh` hinzugefügt – kopiert **jede**
`mktemp`-Pipeline-Kopie in `run-tests.sh` diese Lib?"

**Regel:** Beim Hinzufügen einer gesourcten Datei zu `run-pipeline.sh` **alle** Scaffolding-Stellen
in `run-tests.sh` finden (`grep -n 'cp .*lib/report-verdict.sh'` als Ankerpunkt – dort steht das
Muster) und die neue Lib daneben mitkopieren. Danach die **volle** Suite laufen lassen, nicht nur
die neuen Fälle – die Regression zeigt sich in fremden Tests, nicht in den eigenen.

### Strict-mode-/Umgebungs-Kontrakt-Tests gehören auf die Fehler-/No-Match-Zweige, nicht den Happy-Path (aus nothra/tch-gastro-services#207, Review-Finding W3)

`create_issue_idempotent` (Bash-Seam) bekam in der ersten `/implement`-Runde **einen**
`set -euo pipefail`-Regressionstest – ausgerechnet auf dem **Treffer-Pfad**, der früh via
`return 0` zurückkehrt und gar keine errexit-empfindlichen Konstrukte durchläuft. Die tatsächlich
riskanten Stellen (`raw=$(gh …) || return 2`, `existing=$(…) || rc=$?`, die `while read`-Schleife)
liegen im **No-Match-** und **Fail-open-Zweig**. Der grüne Test belegte strict-mode-Sicherheit also
genau dort, wo am wenigsten schiefgehen kann. Erst im Review (W3) aufgefallen. Failure-Klasse: ein
späterer errexit-Bruch im No-Match-Pfad → die Funktion liefert nichts auf stdout → der Aufrufer
wertet das als Fehler → Retry → genau das Duplikat, das die Funktion verhindern soll; der grüne
Happy-Path-Test bemerkt es nicht.

**Smell:** „Mein `set -euo pipefail`-/Umgebungs-Test läuft über den Happy-Path, der früh
zurückkehrt – durchläuft er auch den Zweig mit `$(…) || return`, die `while read`-Schleife, die
Delegation?" Wenn nein, ist der riskante Pfad unter strict mode ungetestet.

**Regel:** Verifiziert ein Test einen Umgebungs-/Shell-Kontrakt (`set -euo pipefail`, `set -u`,
IFS-Verhalten), muss er **jeden** Zweig durchlaufen, in dem errexit-/nounset-empfindliche
Konstrukte stehen (`x=$(…) || return`, `while read … done < …`, ungeprüfte Pipes, Array-Expansion
unter `set -u`) – insbesondere die **Fehler-/No-Match-/Fail-open-Zweige**, nicht nur den
früh-returnenden Treffer-Pfad. Faustregel: je Kontrakt-Zweig ein eigener strict-mode-Durchlauf. Der
Happy-Path ist fast nie der Zweig, an dem strict mode zuschlägt.

### Spiegel-/Symmetrie-Akzeptanzkriterien: beide Richtungen explizit assertieren (aus nothra/tch-gastro-services#211, Review-Runde-1-Finding)

nothra/tch-gastro-services#211 hatte für den Security-Anker eine Assertion in der einen Richtung (AK4: Verdict-Zeile
`NEEDS_FIXES` + Fließtext-`PASSED` → `NEEDS_FIXES`), aber das **Spiegel-AK6** (Verdict-Zeile
`PASSED` + Fließtext-`NEEDS_FIXES` → `PASSED`, Gate blockiert **nicht**) war nur transitiv über
einen Wiring-Guard (Abwesenheits-Grep „kein Volltext-`grep` mehr") belegt – keine eigene
Laufzeit-Assertion. Das Verhalten war korrekt, aber ausgerechnet die für das Gate **gefährlichere**
Richtung (der alte Volltext-`grep` hätte hier fälschlich blockiert) hatte keinen direkten Test.
Der Reflex „das andere AK ist ja nur die gespiegelte Richtung, ein Test reicht" ist keine
Abdeckung.

**Smell:** „Gibt es ein AC-Paar der Form ‚X blockiert / Y blockiert nicht' (bzw. akzeptiert/
abgelehnt, positiv/negativ) – teste ich **beide** Richtungen mit je eigener Assertion, oder nur
eine und nehme die andere per Symmetrie an?"

**Regel:** Jedes AK bekommt eine eigene direkte Assertion – auch das, das ‚nur' die Gegenrichtung
eines bereits getesteten AK ist. Ein Wiring-/Abwesenheits-Guard (z. B. „das alte Muster ist
verschwunden") belegt die Verkabelung, nicht das Laufzeitverhalten der Gegenrichtung; er ersetzt
die zweite Assertion nicht. Bei symmetrischen Gate-Entscheidungen ist die permissive Richtung
(„blockiert **nicht**") mindestens so wichtig zu testen wie die restriktive.

**Rezidiv in neuer Domäne, außerhalb eines Spec-AK-Paars (aus nothra/tch-gastro-services#352, `/test`-Selbstfund):** Ein
manueller Rework-Schritt verschob einen Reset-Handler von `onClick` auf `onSubmit`
(`VeranstaltungMetaForm.tsx`, siehe `lessons/frontend-react.md`) und schrieb dazu **einen**
Test – für den gemeldeten Bug-Pfad (ungültiges Pflichtfeld, Reset darf nicht feuern). Die
Gegenrichtung (gültiges Pflichtfeld, Reset **muss** feuern) blieb ungetestet; der erst im
`/test`-Schritt gelaufene Coverage-Report zeigte die `onSubmit`-Callback-Zeile selbst als nie
ausgeführt. Zwei Lektionen: (1) die Symmetrie-Pflicht gilt nicht nur für Spec-AK-Paare, sondern
für jeden Bugfix, der einen Code-Zweig in zwei Verhaltensweisen aufspaltet (hier: Submit
blockiert vs. Submit gelingt) – „ich habe den gemeldeten Fall getestet" ist noch keine
Abdeckung der Gegenrichtung; (2) ein Coverage-Lauf **nach** einem selbst geschriebenen Fix ist
kein Nice-to-have, sondern deckt genau diese Art Lücke auf, die eine reine Verhaltensprüfung des
gemeldeten Bugs übersieht.

### Deterministisches Gate/Backstop in einem Orchestrator-Skript braucht einen E2E-Verhaltenstest, nicht nur einen Wiring-Grep (aus nothra/tch-gastro-services#212, Review-Runde-2-Finding)

nothra/tch-gastro-services#212 fügte `run-pipeline.sh` einen Endzustands-Verifikations-Backstop hinzu (Verletzung →
`raise-interrupt INCOMPLETE_OUTCOME` → `exit 1`, sonst Erfolgs-Banner). Die reine Entscheidungslogik
(`evaluate_final_state`) war gut unit-getestet, aber der **verdrahtete Pfad im Orchestrator** war
zunächst nur per `grep` belegt („ruft `verify_final_state`", „enthält `INCOMPLETE_OUTCOME`",
Reihenfolge-Guard). Damit war ausgerechnet die **Kern-Symptomatik** der Task („Skript meldet Erfolg
trotz unverifiziertem Endzustand") end-to-end **ungetestet** – ein Wiring-Grep beweist, dass eine
Zeile existiert, nicht, dass das Skript sich bei verletztem Endzustand richtig verhält.

**Smell:** „Der neue Gate-/Abbruch-Pfad in meinem Bash-Orchestrator ist nur durch `grep` auf die
Verdrahtung abgesichert – wird der Zweig (Erfolg unterdrückt, Non-Zero-Exit, Log-Eintrag) je
tatsächlich **ausgeführt**?"

**Regel:** Für ein neues deterministisches Gate/Backstop in einem Orchestrator-Skript einen
**E2E-Verhaltenstest** schreiben, der den Zweig echt durchläuft: das Skript in einem Temp-Repo mit
gestubbten Agenten-/Tool-Aufrufen (`claude`/`gh` als PATH-Shim, no-op) starten, den realen
Terminalzustand herstellen (hier: ein ungepushter Commit) und Exit-Code + Abwesenheit der
Erfolgs-Ausgabe + den Log-/Interrupt-Effekt asserten – plus eine **Positiv-Gegenprobe** (sauberer
Zustand → Erfolg), damit der Test nicht nur „scheitert immer" beweist. Ergänzt „Callback nur durch
Codelesen belegt ist keine Testabdeckung" (nothra/tch-gastro-services#187) und „Reihenfolge-Guards: Kommando ≠ Prosa" (nothra/tch-gastro-services#114)
um Orchestrator-Gates.

### Negativ-Test mit mehreren Fail-Pfaden muss auf den Ziel-Pfad isoliert werden – sonst grün aus dem falschen Grund (aus nothra/tch-gastro-services#214, Review-Finding W1, von 2 Personas unabhängig)

nothra/tch-gastro-services#214 führte einen Drift-Guard mit mehreren unabhängigen Fail-closed-Pfaden ein (fehlender
Verdict-Anker **und** fehlende Findings-Sektionen führen je zu `exit 1`). Der Negativtest für
Fehlerszenario 2 („Verdict-Anker nur im Fließtext, nicht als Überschrift → rot") nutzte ein
Fixture, das **weder** den Verdict-Anker als Überschrift **noch** die Findings-Sektionen enthielt.
Damit trug bereits die Sektions-Prüfung das `exit 1` – der Test war grün, belegte aber **nicht** die
exakt-verankerte Verdict-Logik. Hätte jemand genau diese (die nothra/tch-gastro-services#211-Regression: Verdict unankert
gematcht), wäre der Test **trotzdem grün** geblieben, weil die fehlenden Sektionen das Exit trugen.

**Smell:** „Kann die zu prüfende Funktion in diesem Negativtest über **mehr als einen** Pfad rot
werden – und stelle ich sicher, dass **nur der eine** Pfad greift, den der Testname behauptet?"

**Regel:** Ein Negativ-/Fehlerfall-Test gegen eine Einheit mit mehreren unabhängigen Fail-Pfaden
muss das Fixture so bauen, dass **alle anderen** Bedingungen erfüllt bleiben und **nur** der
Zielpfad fehlschlägt – und zusätzlich das **pfadspezifische Fehlersignal** assertieren (Meldung/
Konstante), nicht bloß `exit != 0`. Konkret in nothra/tch-gastro-services#214: das Fixture aus der echten Quelldatei ableiten
und nur das Zielmerkmal brechen (die `## Empfehlung`-Überschrift → Fließtext), sodass die Sektionen
intakt bleiben; dann `grep` auf `report_verdict(review)` in der Ausgabe **und** die Abwesenheit der
anderen Fehlermeldung (`count_section_items` darf **nicht** erscheinen) prüfen. Ergänzt „Guard-
Clause-Branches brauchen dedizierte Tests" um Einheiten mit mehreren gleichzeitig auslösbaren
Fail-Pfaden. (Der TDD-Stub `guard() { return 0; }` beweist nur Nicht-Vakuität – dass der Test
**überhaupt** rot werden kann –, nicht die Isolation; beides ist nötig.)

### Kopplungs-/Drift-Guard, der Quelle A gegen Quelle B prüft, braucht einen Negativtest je Seite (aus nothra/tch-gastro-services#214, /test-Selbstfund zu AC6)

#214s Guard liest die erwarteten Konstanten aus den Parser-Skripten (`report-verdict.sh`,
`run-pipeline.sh`) und prüft, ob sie als Anker in den Command-Contracts (`review.md`,
`security-review.md`) auftauchen. Das AC verlangte ausdrücklich Erkennung, wenn **eine der beiden
Seiten** driftet („Command **oder** Parser"). Die erste Implementierung testete den Drift aber nur
über Mutation der **Command-Seite** (Überschrift umbenannt); die Gegenrichtung – die **Parser-
Konstante** umbenannt, Command unverändert – blieb ungetestet. Damit war die halbe vom AC geforderte
Drift-Erkennung nicht belegt, obwohl alle Tests grün waren.

**Smell:** „Mein Guard verknüpft zwei Quellen (liest A, prüft gegen B). Habe ich einen Negativtest,
der **A** mutiert, **und** einen, der **B** mutiert – oder mutiere ich immer nur dieselbe Seite?"

**Regel:** Für einen Guard, der zwei Quellen koppelt, je Seite einen eigenen Negativtest: einmal
Quelle A brechen (B echt lassen), einmal Quelle B brechen (A echt lassen) – jeweils rot + korrekte
Konstante. Zusätzlich den Fail-closed-Fall „Quelle unlesbar/Format geändert → Extraktion leer → rot,
nicht still grün" abdecken. Spezialfall der nothra/tch-gastro-services#211-Symmetrie-Regel, zugeschnitten auf Kopplungs-/
Drift-Guards.

### Neue Regressions-Assertion-Schleife gegen bereits vorhandene Schleife mit identischem Rumpf abgleichen, bevor eine parallele Schleife angelegt wird (aus nothra/tch-gastro-services#240, /test→/refactor-Diskrepanz)

`/test` ergänzte in `run-tests.sh` 11 neue Einzel-Assertionen für vorbestehende
`Write(<verzeichnis>/**)`-Einträge (Regressionslücke: nur ein pauschaler Blanket-Check deckte
sie ab) – als **neue, eigene** `for entry in ...`-Schleife direkt neben einer bereits
existierenden Schleife, die exakt denselben Prüfausdruck (`jq -e --arg v "$entry"
'.permissions.allow | index($v) == null' ...`) und dasselbe Assert-Message-Format nutzte, nur
mit einer anderen Eintragsliste (7 Extension-Einträge). Beide Schleifen waren bis auf die
Eintragsliste **byte-identisch** – echte Duplikation, erst im nachfolgenden `/refactor`
bemerkt, nicht schon beim Schreiben in `/test`. Passiert leicht, weil der Fokus beim
Testschreiben auf „deckt jeder Eintrag eine Assertion ab" liegt, nicht auf „gibt es schon eine
Schleife mit demselben Rumpf, die ich einfach erweitern kann".

**Smell:** „Ich schreibe eine neue `for entry in ...`-Schleife für eine Regressions-Assertion –
gibt es im selben Testabschnitt bereits eine Schleife mit demselben `jq`-/`grep`-Prüfausdruck
und Assert-Message-Format, nur für eine andere Eintragsliste?" Wenn ja, gehört der neue Eintrag
in die bestehende Liste, nicht in eine zweite Schleife.

**Regel:** Vor dem Anlegen einer neuen Assertion-Schleife für zusätzliche Einträge derselben
Prüfart (z. B. „Eintrag X darf nicht mehr in `allow`/`deny` vorkommen") im selben Testabschnitt
nach einer bereits vorhandenen Schleife mit identischem Prüfausdruck suchen (`grep -n
"index(\$v) == null"` als Ankerpunkt) und deren Eintragsliste um die neuen Werte erweitern,
statt eine zweite, strukturgleiche Schleife danebenzustellen. Konkrete Instanz von „Neue
Verfügbarkeits-/Capability-Prüfung gegen bereits vorhandene abgleichen" (aus nothra/tch-gastro-services#224,
`code-style.md`) – gilt genauso für Regressions-Assertion-Schleifen in Bash-Testsuiten, nicht
nur für Capability-Checks wie `command -v`.

**Rezidiv trotz vorhandener Lesson, ausgelöst durch mehrdeutigen Spec-Wortlaut (aus nothra/tch-gastro-services#251,
Review-Runde-1-Finding):** `/implement` legte für `run-tests.sh` erneut eine rumpfidentische
Schleife neben eine bestehende an (`jq -e --arg v "$entry" '.permissions.allow | index($v) !=
null' ...`, nur andere Werteliste) – **obwohl** genau diese Lesson bereits existierte und im
selben File ein Merge-Präzedenzfall (die nothra/tch-gastro-services#240-AK1-Schleife) sichtbar war. Ursache: Die Spec
(`spec-251`) formulierte das AK selbst zweideutig – „die Werteliste an geeigneter Stelle
ergänzen/**eine neue Schleife direkt daneben platzieren**" – und bot damit eine scheinbar
gleichwertige Alternative an, die dem eigentlichen Lesson-Verbot widerspricht. Der Implementer
begründete die neue Schleife mit „andere Eintragsgruppe" – exakt die Rechtfertigung, die der
obige Smell bereits ausdrücklich zurückweist („nur für eine andere Eintragsliste").

**Regel (Ergänzung):** Formuliert eine Spec/ein AK eine Anforderung, die einer bestehenden
Lesson entspricht (Duplikat-Rumpf-Vermeidung, Guard-Symmetrie o. Ä.), muss der Wortlaut die
tatsächlich vorgeschriebene Lösung nennen (hier: „in die bestehende Schleife mergen"), nicht
eine weichere Alternativformulierung, die die Lesson wieder zur Option macht. `/implement`
prüft in diesem Fall zusätzlich gegen die Lesson selbst (nicht nur gegen den Spec-Wortlaut) und
gewichtet den Lesson-Text höher, wenn Spec und Lesson widersprüchlich klingen. „Andere
Eintragsgruppe/-liste" ist **nie** eine hinreichende Begründung für eine zweite,
prüfausdrucksidentische Schleife.

**4. Vorkommnis, jetzt bei Einzel-Assertions statt Schleifen (aus nothra/tch-gastro-services#267, /implement→/refactor-
Diskrepanz):** `/implement` schrieb für sechs neue Präsenz-/Abwesenheits-Prüfungen in
`run-tests.sh` (AK1/AK2/AK3/AK4-Mutationsbelege plus zwei AK5-Checks) jeweils den vollen
`printf '%s' "$x" | grep -qF "$y"; assert_true "$([ $? -ne 0 ]; echo $?)" "..."`-Rumpf **inline**,
obwohl im selben File bereits die Helfer `assert_contains_286` (positive Präsenz) und
`assert_absent` (Negativ-Kontrolle, exakt dieser $?-Negations-Rumpf) für genau diesen Zweck
existierten – erst `/refactor` bemerkte die Duplikation und ersetzte alle sechs Stellen durch
Helfer-Aufrufe (12 Zeilen weniger, identische Assertions). Derselbe Smell wie oben, nur auf
Ein-Zeilen-Assertions statt `for`-Schleifen: der Fokus beim Schreiben lag auf „prüft das die
richtige Bedingung", nicht auf „gibt es im File schon eine Funktion mit exakt diesem Rumpf".

**Regel (Ergänzung):** Der Smell/die Regel oben („gegen bereits vorhandene Struktur mit
identischem Prüfausdruck abgleichen, bevor eine neue angelegt wird") gilt unabhängig von der
Sprachkonstrukt-Ebene – Schleife, Capability-Check **oder einzelne Assert-Zeile**. Vor einem
`printf … | grep -qF …; assert_true …`-Konstrukt in `run-tests.sh` den Helfer-Block am
Dateianfang (`assert_contains_286`, `assert_absent`, `flat_286`, `ls_mode_matches` u. Ä.)
gegenprüfen, ob der exakte Rumpf schon als Funktion existiert.

**5. Vorkommnis, jetzt bei Test-Scaffolding statt Assertionen (aus nothra/tch-gastro-services#310, Review-Runde-1-Finding
W3):** `/implement` legte für die neuen Report-Guard-Tests eine eigene, **parallele**
Scaffold-Funktion (`scaffold_310`) an, die ein komplettes Wegwerf-Repo von Grund auf neu aufbaut
– obwohl im selben File bereits `_mk_pipe_repo` existierte und exakt dasselbe Repo-Grundgerüst
lieferte. Anders als bei den bisherigen Vorkommnissen (rumpfidentische Schleife/Assertion neben
einer bestehenden) war hier keine zweite Instanz **desselben** Konstrukts das Problem, sondern
eine neue Funktion, die das bestehende Grundgerüst **nicht wiederverwendet**, sondern komplett
neu nachbaut – der Smell trifft also auch auf Test-Fixture-/Scaffold-Funktionen, nicht nur auf
Assertions. Noch in `/implement` selbst (Review-Rework) auf „`_mk_pipe_repo` aufrufen, nur die
Differenz ergänzen" korrigiert.

**Regel (Ergänzung):** Vor einer neuen Scaffold-/Fixture-Funktion für ein Wegwerf-Repo/-Setup in
`run-tests.sh` prüfen, ob eine bestehende Funktion (`_mk_pipe_repo` u. Ä.) bereits das
Grundgerüst liefert. Wenn ja, diese aufrufen und nur die tatsächliche Differenz (zusätzliche
Dateien, Stubs, Task-Daten) ergänzen – keine parallele Funktion, die das Grundgerüst dupliziert,
selbst wenn sie inhaltlich nicht Zeile-für-Zeile identisch mit der bestehenden ist.

### `grep -qF`-Fixed-String-Regressionstest gegen Markdown-Prosa: beim Umformulieren/Umbrechen die exakte Testphrase auf einer Zeile halten (aus nothra/tch-gastro-services#240, /review-Rework-Selbstfund, 2× in derselben PR-Session; 3. Vorkommnis aus nothra/tch-gastro-services#249, umgekehrte Kausalrichtung)

Ein Review-Fix korrigierte stale `Write(...)`-Prosa in `factory-workflow.md` und brach dabei
**zweimal hintereinander** einen bestehenden `grep -qF 'ist seit nothra/tch-gastro-services#224 über eine generische'
"$WORKFLOW_LESSON"`-Regressionstest (aus nothra/tch-gastro-services#224, AK7) – nicht durch einen inhaltlichen Fehler,
sondern weil die neu formulierten Sätze beim manuellen Zeilenumbruch die vom Test erwartete
Zeichenkette über einen Zeilenumbruch verteilten. `grep -qF` matched nur **innerhalb einer
Zeile** – eine über zwei Zeilen gebrochene Phrase erzeugt keinen Syntaxfehler und keine
Warnung, der Test schlägt einfach lautlos fehl, weil die Zeichenkette „verschwunden" ist. Der
erste Korrekturversuch brach die Phrase erneut an einer anderen Stelle, weil beim Neu-Umbrechen
nicht gezielt auf die exakte Testphrase geachtet wurde, sondern nur auf „ähnliche Zeilenlänge
wie der Rest der Datei".

**Smell:** „Ich formuliere/breche einen Absatz in einer Doku-Datei um, die per `grep -qF
'<phrase>'` regressionsgetestet wird – bleibt die exakte Testphrase dabei auf **einer** Zeile?"

**Regel:** Vor dem Committen einer Umformulierung/eines Zeilenumbruchs in einer Datei mit
`grep -qF`-Fixed-String-Regressionstests (`grep -n "grep -qF.*<Datei-Basename>" run-tests.sh`
als Ankerpunkt, um die erwarteten Phrasen zu finden) den vollen Testlauf **sofort** danach
ausführen – nicht erst am Ende des Schritts. Ein rot gewordener Test aus dieser Klasse zeigt
sich nur als „Assertion nicht gefunden", nicht als offensichtlicher Zusammenhang mit dem
Zeilenumbruch; die Fehlerquelle ist sonst überraschend schwer zu finden. Bei langen Sätzen mit
einer testkritischen Phrase notfalls die Phrase bewusst unformatiert auf einer langen Zeile
lassen (Prettier reflowt Markdown-Prosa standardmäßig nicht) statt sie „schöner" umzubrechen.

**Drittes Vorkommnis, umgekehrte Kausalrichtung (aus nothra/tch-gastro-services#249, /test-Selbstfund):** Bei Task 249
lag der Fehler nicht in einer Umformulierung, sondern in der **Reihenfolge**: `/implement`
schrieb einen neuen Kommentar-Absatz in `factory.config.yml.example`, der die Phrase „NICHT
override-bar" naturgemäß über einen Zeilenumbruch verteilte (kein Fehler für sich – reiner
Fließtext). Erst danach schrieb `/test` einen **neuen** `grep -qi 'nicht override-bar'`-Test
gegen genau diesen bereits vorhandenen Text – und der Test schlug beim ersten Lauf lautlos rot
fehl, weil die Phrase nie zusammenhängend auf einer Zeile stand. Derselbe Mechanismus wie oben
(einzeiliges `grep` matcht keinen Umbruch), aber die Reihenfolge ist umgekehrt: nicht „bestehender
Test bricht durch neue Prosa", sondern „neuer Test bricht an bereits vorhandener Prosa". Ergänzt
die Regel oben: Beim Schreiben eines **neuen** `grep -qF`/`grep -qi`-Fixed-String-Tests gegen
bereits vorhandenen Fließtext vorher `grep -n '<Teil-Phrase>' <Zieldatei>` gegen die Zieldatei
laufen lassen, um zu verifizieren, dass die volle Testphrase tatsächlich auf einer Zeile steht –
nicht erst durch den ersten (roten) Testlauf herausfinden.

**Viertes Vorkommnis, wieder „neuer Test bricht an bereits vorhandener Prosa" (aus nothra/tch-gastro-services#286,
/test-Selbstfund):** Ein Testing-Persona-Audit ergänzte in `run-tests.sh` eine neue
`grep -qF 'funktionaler Defekt mit reproduzierbarem Auslöser'`-Assertion gegen `review.md` –
obwohl die Lesson zu diesem Zeitpunkt bereits existierte und im selben Task-286-Block mehrfach
zitiert wurde. Die Phrase stand in `review.md` über einen Zeilenumbruch verteilt (`ein
funktionaler Defekt mit\nreproduzierbarem Auslöser`), in `codify.md` dagegen zufällig auf einer
Zeile – derselbe Assertion-Aufruf traf also je nach Zieldatei unterschiedlich. **Root-Cause der
Wiederholung:** Die Lesson wurde beim Schreiben nicht konsultiert, weil der Reflex „ich prüfe
nur, ob die Phrase im Inhalt vorkommt" keinen Bezug zu „Markdown-Zeilenumbruch" auslöste – die
Lesson wird eher bei *Umformulierungen* erinnert, nicht beim *Hinzufügen eines schlichten neuen
Inhalts-Checks*. **Fix, diesmal an der Testinfrastruktur statt an der Prosa:** Ein
`flat_286() { tr '\n' ' ' < "$1"; }`-Helper macht alle Mehrwort-Content-Checks im Block
zeilenumbruch-tolerant (Datei einmal flach einlesen, dann `printf '%s' "$flat" | grep -qF
"$phrase"`), statt bei jedem Fund die Zieldatei umzuformulieren. Diese Umkehrung – die
**Testinfrastruktur** robust gegen Umbrüche machen, statt jede betroffene Prosa-Zeile
anzupassen – ist bei **mehreren** Content-Checks gegen dieselbe Doku-Familie oft die
wartungsärmere Lösung.

**Regel (Ergänzung):** Ein `grep -qF`/`grep -qi`-Mehrwort-Check gegen Markdown-Prosa lässt sich
nicht zuverlässig durch „ich achte beim Schreiben auf Zeilenumbrüche" abschließend absichern
(vier Vorkommnisse in vier verschiedenen Tasks belegen das). Sobald **mehr als ein** solcher
Mehrwort-Content-Check gegen dieselbe Datei/Dateifamilie geschrieben wird, lohnt sich ein
zeilenumbruch-tolerantes Lese-Helper-Pattern (Datei flach einlesen vor dem Matchen) gegenüber
dem Reflex, jede einzelne Testphrase in der Zieldatei auf einer Zeile zu halten.

### „Kein Argument übergeben"-Test simuliert nicht automatisch Abwesenheit, wenn das Skript einen echten Repo-Datei-Default hat (aus nothra/tch-gastro-services#254, Review-Finding)

Task 254 ergänzte Gate nothra/tch-gastro-services#254 AK6 („kein Override-File vorhanden → neue Checks übersprungen").
Der erste Testentwurf rief `bash "$GATE" "$DEFAULTS" >/dev/null 2>&1` — also ohne zweites
Argument, in der Annahme, das simuliere „kein Override vorhanden". `config-validation-check.sh`
defaultet `$OVERRIDE` bei fehlendem `$2` aber nicht auf einen leeren/nicht-existenten Pfad,
sondern auf `$REPO_ROOT/factory.config.yml` (`OVERRIDE="${2:-$REPO_ROOT/factory.config.yml}"`) —
und diese Datei existiert im Repo real und ist selbst ein gültiger Mapping-Override. Der Test
war grün, bewies aber **nicht** den behaupteten Skip-Pfad, sondern war inhaltlich deckungsgleich
mit dem bereits bestehenden Positiv-Test für den realen Override. Erst im Review aufgefallen,
nicht in `/implement` oder `/test` selbst.

**Smell:** „Mein Test lässt ein optionales Positionsargument weg, um dessen 'nicht gesetzt'-Fall
zu simulieren – hat das Skript für dieses Argument einen `${N:-<default>}`-Fallback, der auf
einen REALEN, im Repo vorhandenen Pfad zeigt (statt auf einen leeren String)?" Falls ja, testet
das Weglassen den Default, nicht die Abwesenheit.

**Regel:** Vor dem Schreiben eines „Argument X fehlt"-Tests die Default-Zeile des Skripts
(`grep -n '\${.*:-' <skript>` als Ankerpunkt) prüfen. Zeigt der Default auf einen echten,
existierenden Repo-Pfad, muss der Test stattdessen einen garantiert nicht existierenden Pfad
(z. B. `$GTMP/does-not-exist.yml`) explizit als Argument übergeben, um die entsprechende
Existenzprüfung (hier `override_present()`) nachweislich `false` zu machen — nicht das Argument
einfach weglassen. Gilt für jedes Bash-Gate mit einem `${N:-$REPO_ROOT/...}`-Default-Muster,
nicht nur `config-validation-check.sh`.

### YAML-Testfixture per `printf >>` an eine Kopie mit bereits vorhandenem Top-Level-Key anhängen erzeugt ein Duplicate-Key-Dokument – Test besteht nur zufällig (aus nothra/tch-gastro-services#255, Review-Runde-3-Finding)

Ein Negativ-Test für Task 249 (`model_tiers.heavy` nicht override-bar) kopierte das reale
`factory.config.yml` (enthält bereits `model_tiers: { light: ... }`) und hängte per
`printf '\nmodel_tiers:\n  heavy: ...\n' >>` einen **zweiten** Top-Level-`model_tiers:`-Block an,
statt `heavy` in den bestehenden Block einzufügen. `yq` löst dieses YAML-Duplicate-Key-Dokument
per „last-key-wins" auf – `model_tiers.light` verschwindet aus dem effektiven Dokument spurlos.
Der Test bestand trotzdem, weil die geprüfte Regel („`model_tiers.heavy` grundsätzlich
nicht override-bar") ohnehin auf jeden gesetzten `heavy`-Pfad greift, unabhängig vom
Duplicate-Key-Nebeneffekt – er prüfte aber kein realistisches Override-Szenario (ein echter
Nutzer würde nie zwei `model_tiers:`-Blöcke schreiben) und hing von einer nicht spezifizierten
Parser-Eigenheit ab, statt vom eigentlich zu testenden Verhalten.

**Smell:** „Meine Testfixture kopiert eine reale Datei und hängt per `printf`/`cat >>` einen
neuen YAML-Block an – existiert der Top-Level-Key, den ich damit setze, in der kopierten Datei
bereits?" Falls ja, entsteht ein Duplicate-Key-Dokument, dessen Auflösung vom Parser abhängt,
nicht von der Testabsicht.

**Regel:** Soll ein bestehender Top-Level-Key in einer kopierten YAML-Fixture ergänzt/geändert
werden, einen echten Merge nutzen (`yq -i eval '.<pfad> = "<wert>"' <datei>`), niemals per
`printf`/`cat >>` einen zweiten gleichnamigen Top-Level-Block anhängen. Vor dem Schreiben kurz
`yq eval '.<key>' <kopie>` gegenprüfen, dass alle ursprünglich vorhandenen Geschwister-Werte
(hier `model_tiers.light`) im Ergebnis erhalten geblieben sind – ein verschwundener
Geschwister-Wert ist das Signal für ein Duplicate-Key-Problem, nicht nur ein Nebenaspekt.

### Neuer git-Repo-Fixture-Helper, der committet, braucht lokale Git-Identität – auch wenn er lokal zufällig ohne sie durchläuft (aus nothra/tch-gastro-services#265, Review-Finding)

Ein neuer Testfixture-Helper (`hi_repo()` im nothra/tch-gastro-services#265-Abschnitt von `run-tests.sh`, AK4-Worktree-Test)
rief `git init` + später `git commit` auf, ohne vorher `user.email`/`user.name` lokal zu setzen –
anders als jeder andere commit-erzeugende Helper in derselben Datei (u. a. das direkte
Schwestermuster `ih_repo()` aus dem nothra/tch-gastro-services#262-Abschnitt, das denselben Worktree-Aufbau nutzt und dort
explizit `git config user.email`/`user.name` setzt). Auf macOS/den meisten Linux-Entwickler-
umgebungen fällt `git commit` ohne gesetzte Identität auf `whoami@hostname` zurück und läuft
klaglos durch – der Test war lokal grün, aber nur zufällig. In einer Umgebung ohne auflösbare
Identität (kein `~/.gitconfig`, kein GECOS-Eintrag, z. B. ein schlankeres Docker-Test-Image)
schlägt derselbe Commit mit `fatal: empty ident name (for <>) not allowed` fehl (exit 128) –
verifiziert per `env -i HOME=<leer> GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME= GIT_AUTHOR_EMAIL=
GIT_COMMITTER_NAME= GIT_COMMITTER_EMAIL=`.

**Smell:** „Mein neuer Testfixture-Helper ruft `git commit` (oder `git worktree add` nach einem
Commit) auf – setzt er vorher lokal `user.email`/`user.name`, oder verlässt er sich auf eine
globale/System-Identität, die in DIESER Entwicklungsumgebung zufällig vorhanden ist?"

**Regel:** Jeder neue Fixture-Helper, der in einem frisch initialisierten Wegwerf-Repo committet,
setzt die Git-Identität **lokal und explizit** (`git -C "$wt" config user.email t@t` /
`user.name t`, oder `-c user.email=… -c user.name=…` inline) – unabhängig davon, ob die aktuelle
Entwicklungsumgebung zufällig einen Fallback liefert. Vor dem Ergänzen eines neuen
commit-erzeugenden Helpers die bereits vorhandenen Helper in derselben Datei als Muster
heranziehen (>15 Stellen in `run-tests.sh` setzen die Identität bereits); ein Helper ohne diese
Zeile ist die Abweichung, nicht die Norm. Gilt als Spezialfall von „Flaky Tests: Zero Tolerance"
(`testing-standards.md`) – Umgebungsabhängigkeit ist eine Flakiness-Quelle, auch wenn sie beim
Schreiben nicht auffällt.

### Positivkontrolle für einen Mutations-Fixture darf nicht denselben Fail-closed-Pfad eines anderen Guards teilen (aus nothra/tch-gastro-services#284, Review-Runde-2-Nitpick + /test-Selbstfund)

Task #284s Guard-Familie (`poll_trigger_guard`/`poll_dispatch_guard`/`poll_permission_guard`)
belegt Regressionen über `! poll_*_guard "$mutant.yml"`. Review-Runde 2 merkte an: dieser
Fail-Pfad ist identisch mit dem Fail-closed-Fall „Datei nicht lesbar" (AK6) – bliebe die
Mutanten-Datei aus (`mktemp` schlägt fehl, Redirect geht ins Leere), würden alle Belege grün,
ohne etwas geprüft zu haben (Lesson nothra/tch-gastro-services#214-Klasse). Der Fix: je Mutant eine **Positivkontrolle** –
ein anderer Guard soll gegen dieselbe Datei grün bleiben und damit Existenz + Parsbarkeit
belegen. Der erste Versuch griff dafür auf einen **bereits vorhandenen** Mutanten zurück
(`ohne-dispatch.yml`, gebaut um `poll_dispatch_guard` rot zu machen) und ließ `poll_trigger_guard`
als Kontrolle darauf grün laufen – lief aber tatsächlich rot: `ohne-dispatch.yml` hat einen
**leeren** `on:`-Block (Konstruktionsmerkmal, um `workflow_dispatch` fehlen zu lassen), und ein
leerer `on:`-Block ist selbst eine Fail-closed-Vorbedingung von `poll_trigger_guard`
(`[ -n "$on_block" ]`). Die Positivkontrolle für den einen Guard verletzte eine stille
Vorbedingung eines anderen.

**Smell:** „Ich baue eine Positivkontrolle, indem ich einen bereits vorhandenen Mutanten (gebaut,
um EINEN Guard rot zu machen) für einen ANDEREN Guard als ‚sollte grün bleiben' wiederverwende –
verletzt dieser Mutant eine eigene Fail-closed-Vorbedingung des zweiten Guards?"

**Regel:** Eine Positivkontrolle beweist Datei-Existenz und Parsbarkeit nur, wenn sie einen
Mutanten wählt, der ausschließlich das eine Zielsignal des jeweils **anderen** Ziel-Guards
verändert und alle Vorbedingungen des Kontroll-Guards intakt lässt – nicht reflexhaft den
nächstliegenden vorhandenen Mutanten wiederverwenden. Die Kontrolle tatsächlich laufen lassen und
beobachten, ob sie wirklich grün wird: RED-vor-GREEN gilt auch für Positivkontrollen, nicht nur
für Negativtests. Ergänzt nothra/tch-gastro-services#214 („Negativtest auf Zielpfad isolieren") – hier ist es der
**grüne** Kontroll-Pfad, der isoliert werden muss.

### Zähl-Assertion in einem per awk extrahierten Funktionsrumpf: Label behauptet mehr, als das Fenster messen kann (aus nothra/tch-gastro-services#312, Review-Runde-3-Finding W1)

Eine Assertion zählte Vorkommen von `report_verdict` im per `awk` extrahierten Rumpf von
`run_skill()` und war korrekt auf `1` gepinnt. Ihr Label lautete jedoch „run_skill() liest den
Verdict genau einmal **pro Versuch**" – eine Aussage über den gesamten Aufruf-Pfad. Tatsächlich
liest eine von `run_skill()` aufgerufene Hilfsfunktion (`report_is_fresh_and_valid()`, **außerhalb**
des per `awk` extrahierten Fensters) denselben Wert für die Bedingung noch einmal – macht real
zwei Aufrufe pro Versuch. Die Assertion selbst maß korrekt ihr eigenes, bewusst begrenztes
Fenster; das Label unterstellte eine Eigenschaft der aufgerufenen **Funktion insgesamt**, die
das Fenster gar nicht sehen kann. Zwei Review-Runden zuvor hatten „einmal pro Versuch" bereits
unwidersprochen als nachgeprüfte Tatsache übernommen (Runde 1 zählte sogar Code**stellen** statt
Aufrufe) – erst eine dritte, gezielt nachbauende Prüfung (Hilfsfunktion mit Zähler umwickelt,
einen Versuch nachgestellt) deckte die Diskrepanz auf.

**Smell:** Eine Zähl-Assertion extrahiert bewusst nur einen Teil einer Funktion (Performance,
Fokus, Vermeidung von Fragment-Fallen wie nothra/tch-gastro-services#114) – **aber ihr Label spricht über die ganze
Funktion oder den ganzen Aufruf-Pfad**, nicht über das tatsächlich extrahierte Fenster.

**Regel:** Das Label einer Zähl-Assertion darf nur behaupten, was der extrahierte Bereich
tatsächlich abdeckt („… im eigenen Rumpf von X" statt „X tut Y genau einmal"). Ruft die
extrahierte Funktion denselben Wert über eine externe Hilfsfunktion noch einmal ab, gehört das
explizit ins Label oder in einen Kommentar direkt daneben – sonst wiederholt eine spätere
Review-Runde exakt dieselbe falsche Zusammenfassung, weil sie dem Label statt dem Code traut.
Bei jedem neuen Zähl-Guard dieser Art: „Ruft die als isoliert behandelte Funktion selbst wieder
etwas auf, das denselben Wert erneut liest – und liegt dieser Aufruf außerhalb meines
Extraktionsfensters?"

### Neuer EXIT-Trap/Hook, der ein externes CLI aufruft: geteiltes Test-Scaffold braucht einen deterministischen Stub, nicht ambientes Fail-Fast (aus nothra/tch-gastro-services#314, Review-Runde-2-Finding)

Task nothra/tch-gastro-services#314 verdrahtete `metrics.sh --quiet --publish` als `trap … EXIT` in `run-pipeline.sh` –
ab sofort läuft bei **jedem** echten (nicht `--dry-run`) Pipeline-Lauf ein `gh`-Aufruf mit, auch
in den bereits bestehenden `scaffold_310`-basierten Testfällen (nothra/tch-gastro-services#310/#312-Report-Guard-Familie),
die von der neuen Mechanik nichts wissen. Die Tests blieben trotzdem grün – aber nur, weil ein
auf der Testmaschine ambient installierter `gh` gegen den lokalen Bare-Remote der Wegwerf-Repos
(kein bekannter GitHub-Host) sofort mit Exit ungleich 0 scheitert. Funktional richtig, aber eine
unausgesprochene Umgebungsannahme: auf einer Maschine ohne `gh`, mit anderem Fehlerverhalten,
oder gegen einen künftig echten Remote wäre der Testlauf nicht mehr deterministisch von der
lokalen Toolchain entkoppelt.

**Smell:** Ein neuer `trap`/Hook in einem Skript, das von mehreren bereits bestehenden
Test-Scaffolds real (ohne `--dry-run`) ausgeführt wird, ruft ein **externes CLI** auf (`gh`,
`curl`, o. Ä.) – und die Tests bleiben grün, „weil es in dieser Umgebung ohnehin schnell
fehlschlägt", nicht weil ein Stub das Verhalten festnagelt.

**Regel:** Führt ein neuer Hook in einem von einem geteilten Scaffold (hier: `scaffold_310()`)
real ausgeführten Skript ein externes CLI aus, gehört ein deterministischer Stub für dieses CLI
**in das Scaffold selbst** (nicht nur in die eine Testdatei, die den Hook explizit prüft) – so
profitieren alle bestehenden und künftigen Aufrufstellen einheitlich, ohne von der lokalen
Toolchain-Installation abzuhängen. Ein Scaffold, das bereits ein `bin/`-Verzeichnis mit
PATH-Vorrang anlegt (hier: `run_310()`s `PATH="$dir/bin:$PATH"`), braucht dafür nur eine
zusätzliche Stub-Datei, keine neue Infrastruktur.

### Zeilen-Gap-Assertion auf deterministischem Output: unbegründete Toleranz statt Ist-Wert (aus nothra/tch-gastro-services#322, Review-Runde-2-Finding)

Ein neuer Test in Task nothra/tch-gastro-services#322 sollte belegen, dass eine Ausgabe-Zeile "unmittelbar" auf eine andere
folgt (`start-work.sh`s Session-Empfehlung direkt unter der `/implement`-Zeile). Der erste Wurf
prüfte `rec_gap -ge 1 && -le 3` – ein Toleranzbereich, der nie begründet wurde und der aus der
Beschreibung "unmittelbar" nicht folgt. Der tatsächliche Abstand ist bei diesem Skript
deterministisch **exakt 1** (die Empfehlungszeile ist ein `echo` direkt nach der Schritt-Zeile,
ohne Zwischenzeile). Mit der Toleranz bis 3 hätte eine Regression, die z. B. zwei Leerzeilen
zwischen beide schiebt, den Test weiterhin grün gelassen – obwohl "unmittelbar" dann nicht mehr
zutrifft.

**Smell:** Ein Test auf den Zeilenabstand zwischen zwei Ausgabezeilen eines deterministischen
Skripts benutzt ein Intervall (`-ge X && -le Y`) statt eines Einzelwerts, ohne dass ein Kommentar
erklärt, warum genau dieser Bereich (und nicht ein Einzelwert) zulässig sein soll.

**Regel:** Bevor ein Toleranzbereich für einen Zeilen-/Positions-Gap-Check geschrieben wird: den
tatsächlichen Ist-Wert am realen Output ablesen (nicht schätzen) und exakt darauf prüfen
(`-eq <Wert>`). Ein Intervall ist nur zulässig, wenn eine echte, in einem Kommentar benannte
Variabilitätsquelle existiert (z. B. eine optionale Zeile, die je nach Bedingung dazwischen
erscheinen kann) – sonst verschenkt die Toleranz genau die Präzision, die der Test laut seiner
eigenen Beschreibung ("unmittelbar", "direkt danach") behaupten soll.

### Coverage-Ausgabe nur in ignorierte Pfade schreiben (ADR-040, verschoben aus `testing-standards.md`, nothra/tch-gastro-services#319)

Coverage-Artefakte (HTML-Report, `coverage-summary.json`, sonstige Zwischenausgaben) dürfen
**nie** in einen von Git getrackten Pfad geschrieben werden. Ein versehentlich committetes
Coverage-Verzeichnis blockiert später den Push-Gate (Prettier) – und ein unbeaufsichtigter
Pipeline-Lauf lief genau daran auf (nothra/tch-gastro-services#212: `.coverage-tmp209/coverage-summary.json`).

**Regel:** Coverage-Ausgabe zielt ausschließlich auf einen `.gitignore`-abgedeckten Pfad:
- Standard-Report von `pnpm test:coverage` (Vitest): Default-Verzeichnis `coverage/` – bereits
  ignoriert.
- Braucht ein Schritt (z. B. `/test`/`/review`, per-Diff-Coverage) ein **isoliertes** oder
  temporäres Coverage-Verzeichnis, ist der ignorierte Präfix **`.coverage-tmp<id>/`** zu nutzen
  (deckt `.coverage-tmp*/` in `.gitignore`), nie ein Ad-hoc-Pfad im Projektbaum.

Kurz: Wenn Coverage nach `git status` auftaucht, ist der Zielpfad falsch gewählt.

### Fail-closed-Zusicherung eines Gates braucht einen Test, der die MESSUNG bricht – nicht nur den Input (aus nothra/tch-gastro-services#319, Security-Review-Finding)

Ein Gate, das „fail-closed" zusichert, wird üblicherweise gegen **Inputs** getestet: zu groß →
rot, zulässig → grün, Datei fehlt → rot. Alle diese Tests prüfen den Fall, dass die Messung
funktioniert und ihr Ergebnis unerwünscht ist. Ungetestet bleibt der Fall, dass die **Messung
selbst** ausfällt – und genau dort war der @import-Deckel fail-**open**: ein fehlschlagendes
`awk` lieferte einen leeren Wert, `$((total + ""))` addierte lautlos 0, und der Check meldete
„✓ 0 von 1100 Zeilen" mit Exit 0. Zwölf Input-Tests waren grün; keiner sah es.

**Smell:** Die Testliste eines Gates deckt Grenzwerte, Sonderfälle und Fehleingaben ab – aber
kein Fall bricht das **Werkzeug**, mit dem gemessen wird (das externe Kommando, den Parser, die
Datei-API).

**Regel:** Zu jeder Fail-closed-Zusicherung gehört mindestens ein Test, der die Messung
sabotiert statt den Input – am billigsten über einen Stub im `PATH`:

```bash
printf '#!/bin/sh\nexit 1\n' > "$TMP/stub/awk"; chmod +x "$TMP/stub/awk"
sec_out="$(PATH="$TMP/stub:$PATH" FACTORY_DIR="$FX" bash "$CHECK" 2>&1)"; rc=$?
assert_exit 1 "$rc" "nicht ermittelbare Zahl → exit 1 (fail-closed statt still grün)"
assert_absent "$sec_out" "0 von" "meldet keine Summe 0, die eine Freigabe vortäuscht"
```

Dazu die **Kontrolle**, dass derselbe Fixture ohne Manipulation rot ist – sonst belegt der Test
nicht, dass der Stub die Ursache war. Und die zweite Assertion ist kein Luxus: der Exit-Code
allein unterscheidet nicht zwischen „korrekt gemessen und abgelehnt" und „nichts gemessen".

### Content-Scan-Guard, dessen Suchphrase als Literal in der gescannten Datei steht, ist immer rot (aus nothra/tch-gastro-services#319, /implement-Selbstfund)

Ein Guard, der eine Datei nach einer verbotenen Phrase durchsucht, scannt sich selbst mit, wenn
die Datei **die Testdatei ist**. Die Phrase steht dann zwangsläufig darin – als Argument des
Guards:

```bash
assert_absent "$(flat_286 "$CHECKS_DIR/tests/run-tests.sh")" \
  "testing-standards.md: Exhaustiveness-Guards" "kein Verweis mehr auf die alte Datei"
```

Der Guard ist damit **nie erfüllbar**, unabhängig vom tatsächlichen Repo-Zustand. Verwandt mit
dem nothra/tch-gastro-services#312-Learning (verzeichnisweiter Scan ist blind für Tracked-Status), aber eigenständig: dort
war eine fremde Datei die Störquelle, hier ist es die geprüfte Datei selbst.

**Smell:** Ein Abwesenheits-Guard über eine Datei, die auch den Guard enthält – erkennbar daran,
dass der Scan-Pfad auf `run-tests.sh` (oder eine andere Datei mit Testcode) zeigt.

**Regel:** Die Suchphrase zur Laufzeit zusammensetzen, damit sie als Literal nirgends im
gescannten Text steht:

```bash
IC_OLD_HOME="testing-standards.md"
assert_absent "$(flat_286 "$DATEI")" "$IC_OLD_HOME: Exhaustiveness-Guards" "…"
```

Gegenprobe nicht vergessen: Ein Guard, der **sofort** rot ist, ist genauso verdächtig wie einer,
der nie rot wird – beide prüfen nicht, was ihr Label behauptet.

### Ein Anker, der mit `-` beginnt, macht die assert-Helfer still falsch (aus nothra/tch-gastro-services#319, dritter Fall derselben Regel im selben PR)

`assert_contains_286`/`assert_absent` reichen ihren Suchwert als `grep -qF "$2"` weiter – **ohne**
`--`. Beginnt die Phrase mit einem Bindestrich (`-Kontext unter dem Deckel`), liest `grep` sie als
Option. Das Ergebnis ist kein Fehler, sondern ein **stiller Fehlschlag**: der Präsenz-Guard wird
rot, obwohl die Phrase in der Datei steht.

Die Fehldiagnose liegt nahe und kostet Zeit – man sucht den Fehler in der Zieldatei („warum fehlt
der Satz?"), nicht im Anker. In nothra/tch-gastro-services#319 ist die Regel aus `clean-code.md` („Config-/nutzerkontrollierte
Werte als Daten, `--` vor das Pattern") im selben PR dreimal aufgelaufen: einmal bei einem
Ad-hoc-`grep -nF` auf eine Zeile, die mit `- ` beginnt, einmal an diesem Helfer, einmal als
Argument-Injection-Fläche im Gate selbst (`@-v` als awk-Option).

**Smell:** Ein Präsenz-Guard ist rot, obwohl `grep -c` von Hand die Phrase findet – oder ein
Abwesenheits-Guard ist grün, obwohl sie da ist. Erster Blick: **beginnt der Anker mit `-`?**

**Regel:** Anker so wählen, dass sie nicht mit `-` beginnen (ein Wort früher ansetzen), und bei
eigenen `grep`-Aufrufen mit variablem Wert grundsätzlich `grep -qF -- "$wert"` schreiben. Der Fix
in den geteilten Helfern selbst ist als Kleinfund erfasst.

### Claude-Stub-Nebenwirkung ohne Skill-/Task-Bindung lässt ein Testszenario über einen fremden Guard statt den behaupteten Pfad bestehen (aus nothra/tch-gastro-services#334, /test-Selbstfund)

Ein neues E2E-Szenario sollte belegen, dass zwei **normale, vollständig durchlaufende** Läufe
sich gegenseitig nicht überschreiben. Der `claude`-Stub des ersten Laufs schrieb dafür die
Report-Dateien des zweiten Laufs (`review-914.md`/`security-914.md`) vorsorglich unbedingt bei
**jedem** eigenen Aufruf – nicht nur, wenn tatsächlich `/review`/`/security-review` für Task 914
liefen. Dadurch sah der ECHTE `/review`-Aufruf des zweiten Laufs eine bereits vorhandene,
inhaltlich identische Report-Datei vor sich; der Report-Frische-Guard (ADR-019 §4, Fingerprint-
Vergleich) wertete das als „Verdict aus einem früheren Aufruf" (stale) und ließ `/review` nach
drei Versuchen scheitern. Der zweite Lauf brach dadurch in Phase 2 ab – die Telemetrie wurde
trotzdem persistiert, aber über den EXIT-Trap-Fallback, nicht über den regulären Aufrufort
zwischen `/codify` und `/pr-shepherd`, den der Testkommentar eigentlich behauptete. Der Test
bestand, aber aus dem falschen Grund; erst ein Mutationstest (Entfernen des EXIT-Trap-Aufrufs
ließ ausgerechnet dieses „Zwei normale Läufe"-Szenario rot werden, was es laut Beschreibung
nicht dürfte) deckte die Verwechslung auf.

**Smell:** Ein Test-Stub schreibt eine Ausgabedatei für einen SPÄTEREN Lauf/Task **unbedingt**
bei jedem Aufruf des AKTUELLEN Laufs, statt die Bedingung (welcher Skill, welche Task-ID) exakt
so zu prüfen wie das eingebaute Template es für die eigene Task-ID bereits tut. Ein Abgleich
„läuft mein Test durch den behaupteten Pfad oder über einen stillschweigend greifenden
Fallback?" fehlt.

**Regel:** Schreibt ein Test-Stub in einem MEHR-Lauf-Szenario Dateien für einen anderen
Lauf/Task vor, muss die Schreibbedingung an **beide** Marker gebunden sein, die auch die echte
Aufrufzeile trägt – den Skill-Marker UND den Task-Marker (z. B. `*SKILL-review*task-914*`),
nicht nur den Skill-Marker allein. Bei einem Test, der einen bestimmten Erfolgs-**Pfad**
behauptet (hier: regulärer Aufrufort statt EXIT-Trap-Fallback), diesen Pfad zusätzlich per
Mutationstest isoliert bestätigen – ein grüner Test allein belegt nur, dass IRGENDEIN Pfad zum
erwarteten Endzustand geführt hat, nicht welcher.

### Locale-abhängige Zahlenformatierung/-parsing in Shell-Test-Utilities (aus nothra/tch-gastro-services#96, nothra/tch-gastro-services#341)

Sowohl bash `printf '%.1f'` (nothra/tch-gastro-services#96, `metrics.sh`) als auch ein `awk`-Ausdruck, der Dezimalzahlen
parst (`s+=$N`) oder formatiert (`printf "%.Nf"`), sind locale-abhängig: unter einer
Komma-Dezimaltrenner-Locale (z. B. `de_DE.UTF-8`) bricht das Parsen eines Punkt-Dezimalwerts
ab, bzw. der Punkt wird beim Formatieren durch ein Komma ersetzt. Beide Vorfälle blieben
unentdeckt, bis ein Rechner mit deutscher Locale die jeweilige Suite lokal rot färbte – in CI
(C-Locale) blieb sie grün. Das Muster ist also umgebungsabhängig unsichtbar (nicht
gate-blockierend), kostet aber bei jedem betroffenen lokalen Lauf eine Fehlersuche; nothra/tch-gastro-services#341 ist
ein Rezidiv derselben Fehlerklasse wie nothra/tch-gastro-services#96, nur in `awk` statt bash-`printf`, und war bis dahin
nirgends als Lesson festgehalten – nur inline im jeweiligen Testkommentar.

**Smell:** Ein neuer `awk`- oder `printf`-Aufruf in einem Shell-Testskript parst oder
formatiert eine Dezimalzahl (`%.Nf`, `s+=$N`, `sum+=$N`), ohne dass die Locale für genau
diesen Aufruf fixiert ist.

**Regel:** Jeder awk-/bash-Aufruf, der Dezimalzahlen parst oder formatiert, bekommt ein
**lokales** `LC_ALL=C`-Präfix direkt vor dem Aufruf – nicht global am Skriptanfang, da ein
suite-weites `LC_ALL=C` bewusst locale-abhängig getestete Stellen wie den nothra/tch-gastro-services#96-Test selbst
maskieren würde. Wird der Ausdruck sowohl von der echten Assertion als auch von einem
Locale-Regressionstest gebraucht, in einen gemeinsamen Helfer extrahieren statt den Ausdruck
zu kopieren (Drift-Risiko, siehe Mutationsbeleg-Regel oben).

### Ein Config-/Gate-Wert, der als „gültig" akzeptiert wird, ist damit noch nicht als „angewendet" belegt (aus nothra/tch-gastro-services#348, /test-Selbstfund)

Task nothra/tch-gastro-services#348 hob `MAX_TURNS_CEILING` (Gate-Policy-Konstante, `config-validation-check.sh`) samt
dem zugehörigen `factory.config.yml`-Override für `/implement` von 50 auf 80 an. `/implement`
schrieb dafür zwei Grenzfall-Tests: `max_turns: 80` wird vom Gate akzeptiert, `max_turns: 81`
bleibt fail-closed abgelehnt. Beide Tests waren echte Verhaltenstests (kein reiner Wiring-Grep,
vgl. nothra/tch-gastro-services#212) – und trotzdem blieb eine Lücke: Sie belegen nur, dass das **Validierungs-Gate**
den Wert 80 für **gültig** hält, nicht, dass der **Konsument** der effektiven Config
(`run-pipeline.sh`, ein anderes Skript als das Gate) den Wert für `/implement` auch
tatsächlich **anwendet** – ein Tippfehler in der Auflösungslogik von `run-pipeline.sh` selbst
(z. B. ein noch auf den alten Default verweisender Pfad) wäre von den Gate-Tests nicht
gefangen worden, weil sie `run-pipeline.sh` gar nicht aufrufen.

**Smell:** Ein Config-Wert wird durch ein separates Validierungs-Gate geprüft (Positiv-/
Negativ-Fixtures, Grenzfälle) – aber der eigentliche **Verbraucher** dieses Werts ist ein
anderes Skript/Modul, das in diesen Tests nicht selbst ausgeführt wird. „Das Gate lässt den
Wert durch" ist dann nur die halbe Behauptung; die andere Hälfte („der Wert kommt beim
Verbraucher an, kein stiller Fallback auf den alten Default") bleibt unbelegt.

**Regel:** Bei jeder Änderung eines Werts in einer geschichteten Config (ADR-009), der von
einem separaten Gate validiert **und** von einem anderen Skript konsumiert wird, mindestens
eine End-to-End-Assertion ergänzen, die den **realen** Konsumenten mit den **realen**
Repo-Dateien (nicht nur einem synthetischen Testwert) ausführt und den tatsächlich verwendeten
Wert im Output prüft (hier: `run-pipeline.sh <id> --dry-run` gegen die reale
`factory.config.yml`, Assertion auf „max 80 turns" im Klartext-Output). Ergänzt „Deterministisches
Gate/Backstop braucht E2E-Verhaltenstest, nicht nur Wiring-Grep" (nothra/tch-gastro-services#212) um den Fall, dass der
fehlende Beweis nicht die Existenz eines Branches ist, sondern die **Weiterleitung** eines
bereits validierten Werts an eine andere Komponente. **Laden bei:** `/implement`, `/test` bei
Änderungen an `MAX_TURNS_CEILING`, `model_tiers`, `tier_by_size` oder anderen Gate-geprüften
Config-Werten mit eigenem Konsumenten außerhalb des Gates selbst.

### Test, der die Git-Historie liest (`git log --follow`), braucht in CI einen Shallow-Clone-Skip (aus nothra/tch-gastro-services#426, /implement-Selbstfund)

`actions/checkout` klont per Default flach (`fetch-depth: 1`). Ein Test, der die Historie vor einem `git mv`
belegen soll (`git log --follow`, `git blame`, Alt-Pfad-Lookup), findet dort nur den einen Commit und wird
**in CI rot, lokal grün** – der Fehler ist reine Umgebung, kein Verhalten.

**Regel:** Historie-Assertions hinter `[ "$(git rev-parse --is-shallow-repository)" = "false" ]` legen und den
Skip **sichtbar** ausgeben (eigene Zeile, kein stilles Weglassen); das Verhalten selbst bleibt über einen
nicht historienabhängigen Test (Datei liegt am Neu-Ort, am Alt-Ort fehlt sie) abgedeckt. Den Skip nicht durch
`fetch-depth: 0` im Workflow ersetzen – das verlängert jeden Lauf für einen einzigen Test.

### `assert_contains_286` (Pipe-`grep -q`) auf Datei-Haystacks ist ein Race – in CI rot, lokal grün (aus nothra/tch-gastro-services#426, CI-Befund nach `/refactor`)

Der Helfer reicht den Haystack per `printf | grep -q` weiter. `grep -q` beendet sich beim ersten Treffer, `printf`
schreibt noch weiter, bekommt SIGPIPE, und `pipefail` macht den Treffer zum Falsch-Rot (bash-gotchas #3). Das ist
**kein** fester Schwellenwert, sondern ein Race ab wenigen KB (Schreiben in Stücken): `PROJECT-CONTEXT.md` (64 KB)
und eine 38-KB-`--list project`-Ausgabe schlugen auf dem CI-Runner fehl, der Entwickler-Mac blieb grün. Ein
`/refactor` hatte Datei-`grep`-Prüfungen auf den Helfer umgestellt und „identisch grün" aus dem lokalen Lauf
behauptet; erst der zweite CI-Lauf zeigte die Rezidiv-Stelle in `own_side_426`.

**Regel:** Gegen eine **Datei** immer direkt `grep -qF -- … <datei>`; gegen eine **Variable** per Here-String
(`grep -q … <<< "$var"`), nie `printf | grep -q`. Den Helfer nur für kurze Literale (Zeilen/Absätze) nutzen. Nach
einem Test-Refactor die CI-Läufe abwarten, bevor „identisch grün" behauptet wird.

### Rezidiv nothra/tch-gastro-services#348: Gate-Kommando „aus der Config" an einem dritten Konsumenten nur per Grep belegt – Review fand die Lücke (aus nothra/tch-gastro-services#431, Review-Iteration 1)

`/implement` zu nothra/tch-gastro-services#431 verlegte die Gate-Kommandos (`commands.*`) aus hartkodierten pnpm-Defaults in
`factory.config.yml`. Für `pre-commit.sh` und `pre-push.sh` entstanden Verhaltenstests (Config-Kommando läuft,
Env hat Vorrang, fehlender Schlüssel → rot). Für den dritten Konsumenten `run-pipeline.sh` blieb es bei einem
Grep auf `gate_command lint required` – der Struktur-Test blieb grün, auch wenn die Auflösung selbst falsch gewesen
wäre. Erst `/review` Iteration 1 fand das; das Rezidiv der nothra/tch-gastro-services#348-Regel entstand, weil die Verhaltenstests zuerst für die
beiden Hooks geschrieben und die Pipeline als „gleiche Lib, also gleich" abgehakt wurde.

**Regel:** Wird eine Quelle (Config-Schlüssel) auf **mehrere** Konsumenten umgestellt, bekommt **jeder** Konsument
seinen eigenen Verhaltenstest (Marker beweist die Ausführung des Config-Kommandos, Env-Vorrang, Abbruch bei fehlendem
Pflichtwert **vor** der ersten teuren Aktion, Exit-Code mitassertiert). Eine gemeinsame Lib ersetzt das nicht.
Beim Anlegen der Tests die Konsumenten-Liste aus der Spec (hier AK-H3: Hooks **und** Pipeline) abhaken, nicht aus
dem Gedächtnis.

### Die laufende Test-Suite nicht editieren – Bash liest ein Skript inkrementell (aus nothra/tch-gastro-services#431, /implement-Selbstfund)

`run-tests.sh` (9 000+ Zeilen, ~6 Minuten) lief im Hintergrund, während ich dieselbe Datei per Python-Skript erweiterte.
Bash liest ein laufendes Skript Stück für Stück von der Platte: Zeilenverschiebungen mitten im Lauf lassen es an einer
falschen Stelle weiterlesen oder Fragmente ausführen – ein Ergebnis, das weder dem alten noch dem neuen Stand
entspricht (hier nur durch Disziplin vermieden, kein beobachteter Schaden).

**Regel:** Solange ein Hintergrund-Lauf von `run-tests.sh` (oder einem anderen langen Bash-Skript) läuft, wird die
Datei **nicht** verändert; neue Tests in dieser Zeit in einer Scratch-Datei vorbereiten und nach dem Lauf einfügen.

### Zeilenabdeckung für ein Bash-Skript ohne Coverage-Werkzeug: `bash -x` in einem Wrapper (bash 3.2: kein `BASH_XTRACEFD`) (aus Factory-Task #22, `/test`)

Das Repo hat kein `kcov`/`bashcov`, `commands.coverage` ist nur die Suite. Trotzdem lässt sich die Zeilenabdeckung des **einen** Produktionsskripts messen: ein Wrapper (`ownership-check.sh`) ruft das echte Skript mit `PS4='+X ${BASH_SOURCE##*/}:${LINENO}:'
bash -x …` auf, schreibt den Trace in eine Temp-Datei und trennt danach **Trace-Zeilen** (→ Log) von **echter stderr-Ausgabe** (→ stderr) – die Tests lesen stderr und dürfen nichts davon verlieren. Auf macOS (bash 3.2.57) gibt es **kein** `BASH_XTRACEFD`
(erst ab bash 4.1); `SHELLOPTS=xtrace` und ein `BASH_ENV`-Prelude mit `exec 9>>log` greifen deshalb nicht (Trace landete weiter auf stderr, 17 Tests wurden rot). Ausführbare Zeilen = nicht leer, kein Kommentar, keine Klammerzeile; Funktionsköpfe und
`case`-Muster zeigt `xtrace` nie – das sind Messartefakte, keine Lücken.

Der Lauf fand vier fail-closed-Pfade ohne Test (unbekannter Parameter, unlesbare Dateiliste, `git ls-files` scheitert, interner Fehler eines Vergleichs). **Regel:** Vor dem Abschluss einer Gate-/Check-Skript-Task die Zeilenabdeckung per xtrace messen, jede nicht
ausgeführte `exit 2`/`return`-Zeile einzeln bewerten und je Pfad einen Test **mit Mutationsbeleg** schreiben (Skript-Kopie mit zerstörter Zeile, nur der zuständige Test wird rot). Den internen Fehler einer Pipeline erzwingt man mit einem PATH-Stub, dessen Werkzeug mit Exit ≠ 0
endet (Messung brechen, Lesson nothra/tch-gastro-services#319).

### Fail-closed-Zweig „getestet“, weil ein späterer Schritt zufällig auch scheitert – Mutationslauf je `die` (aus Factory-Task #23, `/test`)

Der Test für `factory-sync.sh` hatte für jeden Abbruchpfad eine Assertion „Exit ≠ 0 + nichts geändert“ – und 12 von 26 Fehlerzweigen blieben beim
Mutationslauf (`die "…"` wird zum No-op) trotzdem **grün**: Ohne den Abbruch scheiterte ein späterer Schritt aus anderem Grund (Hash-Prüfung, „fehlt im Tag“,
Folgefehler), mit demselben Exit-Code und unverändertem Baum. Ein Test, der nur Exit-Code und Zustand prüft, belegt den **Ausgang**, nicht den **Zweig**.
Der Symlink-Test war so gebaut, dass eine frühere Stufe (Gate: Inhalt weicht ab) den Fall abfing, bevor der Zweig erreicht wurde.

**Regel:** Für jeden fail-closed-Zweig (a) die **zweigspezifische Meldung** assertieren, (b) die Meldung der **nächsten Stufe** als abwesend
assertieren (`assert_absent`) und (c) die Fixture so bauen, dass nur dieser Zweig den Fall abfängt (gleicher Inhalt beim Symlink-Test, Datei fehlt im Repo statt
mit Nullhash). Vor `/test`-Abschluss je Zweig einen Mutanten laufen lassen: `die "` → `: "` in einer Kopie des Repos (ein Prozess je Mutant, `xargs -0 -P4`),
nur der zuständige Test darf rot werden; Mutanten, die sich nicht auslösen lassen (Fehlerinjektion in `cp`/`rm`, Verteidigung in der Tiefe), im Coverage-Report
begründen. Der `bash -x`-Wrapper aus der Lesson oben versagte hier (Kind-Prozesse: Zeilennummern fehlten im Trace) – der Mutationslauf ist die
belastbarere Messung für Skripte, die andere Skripte aufrufen.

## Neutralitäts-Guard „liest keine Konsumenten-Dateien“ sieht nur direkte Pfade – indirekte Leser per Fixture-Lauf finden (aus Factory-Task #28, `/review`)

Der Guard gegen Lesezugriffe der ausgelieferten Suite auf projekteigene Dateien (`$FACTORY_ROOT/…PROJECT-CONTEXT.md` usw.) war grün und hatte pro Datei einen
Mutationsbeleg – und doch las die Suite weiter eine Projektdatei: ein Test ruft `import-context-limit-check.sh` gegen den echten Repo-Stand auf, das Check-Skript
liest `CLAUDE.md` und `PROJECT-CONTEXT.md`. Ein Pfad-Grep über die Testdatei findet das nie; erst der Suite-Lauf in einer Repo-Kopie ohne `PROJECT-CONTEXT.md`
machte genau diesen Test rot (Issue #32).

**Regel:** Ein statischer Pfad-Guard ersetzt den **Fixture-Lauf** nicht. Für jeden „liest nichts vom Konsumenten“-AK zusätzlich die Suite in Kopien laufen lassen
(Datei fehlt / Datei verändert) und die roten Tests **zwischen den Varianten** vergleichen – Rot, das nur in einer Variante auftritt, ist ein indirekter Leser;
Rot in allen Varianten kommt vom Kopier-Aufbau (kein Git-Verlauf, Pfad). Die Grenze des Pfad-Guards im Kommentar benennen.

### Nachtrag zu Factory-Task #28 (aus Factory-Task #32, Umsetzung)

Der erweiterte Guard (Check-Skript mit `FACTORY_DIR=<echte Wurzel> bash …`) fand den einen bekannten Treffer – und der Fixture-Lauf danach noch einen zweiten, den **kein** Muster sah: ein Test rief `pre-push.sh` direkt aus dem echten `$CHECKS_DIR` auf, dessen Check 6 selbst die echte `CLAUDE.md` liest. Gates/Check-Skripte, die über `FACTORY_DIR` aus ihrem Skriptpfad lesen, in der Test-Wegwerf-Wurzel als **Kopie** ausführen, nicht aus dem Repo.

**Fixture-Lauf sauber aufsetzen:** Die Varianten brauchen identischen Aufbau (Kopie → `git init` + Commit → `install-hooks.sh`), und die entfernte Datei muss **aus dem Baum** verschoben werden, nicht umbenannt im Baum – sonst entsteht eine Datei ohne Ownership-Zeile und ein Rot, das nur der Aufbau erzeugt. Suite-Lauf nicht in `| head` leiten (SIGPIPE bricht ihn ab, das Ergebnis täuscht).

**Mutationsbeleg für optionale Regex-Gruppen:** Ohne Zeilenanfangs-Anker bleibt die Mutation „optionale Gruppe `(env )?` entfernen“ grün, weil der Rest der Zeile auch so trifft – die Gruppe ist dann redundant, nicht ungetestet. Beim Mutationsbeleg prüfen, ob die Mutation überhaupt etwas ändern kann.
