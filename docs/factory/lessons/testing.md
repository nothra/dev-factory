# Lessons: Testing & Coverage

> Ausgelagerte `/codify`-Learnings (Volltext) zu **Vitest, Coverage, Guard-Tests, Zod-Meldungs-Tests**.
> **Nicht** `@import`-geladen (ADR-037) – bei Bedarf gezielt lesen. Kanonische Quelle je
> Regel ist der jeweilige Eintrag hier; im @import-Pfad (`PROJECT-CONTEXT.md`) steht nur eine Index-Zeile.
> Neue Learnings kommen hierher (nicht in den @import-Pfad) – siehe `/codify` + ADR-037.

### Vitest + Testing Library ohne `globals: true` (aus #48)

Ohne `globals: true` registriert Testing Library **kein** Auto-Cleanup → das DOM leakt zwischen
Component-Tests (ein Test sieht das Markup des vorigen; `screen`-Queries schlagen scheinbar grundlos fehl).

**Regel:** In `vitest.setup.ts` `afterEach(() => cleanup())` behalten – nicht entfernen. Async
Server Components in Tests via `render(await Component())` prüfen.

**Ergänzung `vi.clearAllMocks()` vs. `vi.resetAllMocks()` (aus #51):** `clearAllMocks()` löscht
nur Call-History, **nicht** Mock-Implementierungen (`mockReturnValue`/`mockRejectedValue`). Ein
`mockRejectedValue` aus einem `describe`-Block kann dadurch in den nächsten leaken → Reihenfolge-
Abhängigkeit zwischen Test-Blöcken (Verstoß gegen Test-Isolation).

**Regel:** In `beforeEach` immer `vi.resetAllMocks()` verwenden – nicht `vi.clearAllMocks()` –
wenn Test-Blöcke eigene Mock-Implementierungen setzen. `clearAllMocks()` genügt nur, wenn
keine Mock-Implementierungen gesetzt werden (nur `vi.fn()` ohne `.mockReturnValue`/`.mockRejectedValue`).

### Guard-Clause-Branches in Server Actions brauchen dedizierte Tests (aus #51, Review-Finding)

Die `!id || !veranstaltungId`-Guards an der Spitze mehrerer Server Actions hatten keine Tests.
Laut `testing-standards.md` erwartet neuer Code 100 % Coverage – aber der Reflex ist, nur
Happy-Path + bekannte Error-Paths (z. B. `23505`) zu testen, nicht die Eingabe-Guards.

**Smell:** „Wenn ich diesen Guard entferne, schlägt kein Test fehl" – dann fehlt der Test.

**Regel:** Jeder Guard-Clause-Branch an der Action-Grenze (Leerfeldprüfungen, null-Guards auf
Pflicht-IDs) erhält einen eigenen Testfall, der genau diesen Branch auslöst. Beispiel:
```ts
it("should_returnError_when_veranstaltungIdMissing", async () => {
  const formData = new FormData(); // veranstaltungId fehlt
  const result = await addZeileAction(undefined, formData);
  expect(result?.error).toBeDefined();
});
```

### AC mit Direktive + Begründung: je separierbaren Teil eine eigene Assertion (aus #117, /test-Selbstfund)

Der `#117`-Doc-Guard prüfte, ob `pr-shepherd.md` Schritt 2 das Seam-**Kommando**
(`factory-commit.sh`) nennt – deckte damit aber nur AC1 ab. Die Task hatte ein zweites,
im selben Absatz stehendes Kriterium (AC2): die **fail-closed-Begründung mit ADR-019-Verweis**.
Kommando und Begründung stehen auf **getrennten, einzeln entfernbaren Zeilen** – ein
Presence-`grep` auf das Kommando lässt die Begründung ungetestet. Aufgefallen erst in `/test`,
nicht schon in `/implement`: der Reflex ist, den auffälligsten Token (das Kommando) zu prüfen und
den begleitenden Kontext (Rationale, ADR-Verweis, Warnung) als „mitgetestet" anzunehmen.

**Smell (erweitert #51):** „Entferne ich die **Begründung**, lasse aber das **Kommando** stehen –
schlägt ein Test fehl?" Wenn nein, ist das Begründungs-Kriterium ungetestet.

**Regel:** Bündelt ein Akzeptanzkriterium eine **Direktive** (Kommando/Config-Wert) **und** ihre
**Rationale** (Begründung, ADR-Verweis, Warnung), und liegen beide auf getrennt editierbaren
Zeilen, bekommt jeder separierbare Teil eine **eigene** Assertion – nicht einen gemeinsamen Grep.
Pflicht-Begleitung: Negativ-Nachweis, der die Unabhängigkeit belegt (Begründung entfernen →
Begründungs-Guard **rot**, Kommando-Guard **grün**). Deckt sich mit `testing-standards.md`
(je Kriterium ein Test) und der Positiv-**und**-Negativ-Beispiel-Regel aus `clean-code.md`.

### Zod-Fehlermeldung: Ablehnungs-Test ≠ Meldungs-Test (aus #116, Review-Runde-1-Finding)

`should_rejectCategory_when_notInEnum` (`result.success === false`) und
`should_nameAllThreeCategories_when_categoryInvalid` (`firstIssueMessage === Literal`)
sind **zwei separate Tests**. Ein Ablehnungs-Test belegt nicht, dass die Meldung den richtigen
Inhalt hat – eine generische Meldung wie „Ungültige Kategorie." würde genauso durchkommen.
Aufgefallen erst in Review-Runde 1 (nicht in `/implement`): der Reflex ist, die Ablehnung zu
testen und den Meldungstext als „mitgetestet" anzunehmen.

**Smell:** „Ersetze ich die custom message im Schema durch eine generische Meldung – schlägt
ein Test fehl?" Wenn nein, ist der Meldungsinhalt ungetestet.

**Regel:** Wenn das AC den **Inhalt** der Zod-Fehlermeldung vorschreibt (z. B. „nennt alle drei
Kategorien"), ist das ein separierbar-testbares Kriterium und braucht einen eigenen `it`-Block
mit `firstIssueMessage(result.error)` gegen ein unabhängiges Literal:
```ts
// Assertion 1 – Ablehnungs-Verhalten:
it("should_rejectCategory_when_notInEnum", () => {
  const result = schema.safeParse({ category: "snack" });
  expect(result.success).toBe(false);
});

// Assertion 2 – Meldungsinhalt (separierbar, eigener it-Block):
it("should_nameAllThreeCategoriesInMessage_when_categoryInvalid", () => {
  const result = schema.safeParse({ category: "snack" });
  if (!result.success)
    expect(firstIssueMessage(result.error)).toBe("Kategorie muss Getränk, Kaffee oder Essen sein.");
});
```
Verwandt mit der #117-Regel (je separierbares AC-Kriterium eine eigene Assertion) und der
`testing-standards.md`-Regel (erwarteter Wert ist ein Literal, kein erneuter Ergebnis-Zugriff).


### Neue gesourcte Lib in run-pipeline.sh → in ALLE Temp-Repo-Scaffoldings in run-tests.sh kopieren (aus #197)

`run-tests.sh` baut an mehreren Stellen eine minimale Pipeline-Repo-Kopie in `mktemp -d` auf und
startet `run-pipeline.sh` darin (Preflight-Cleanup, Phase-1b-End-to-End, Turn-Budget-Dry-Run,
`#101`-Lint-Gate …). Jede dieser Stellen kopiert die Laufzeit-Abhängigkeiten einzeln
(`config-validation-check.sh`, `factory.defaults.yml`, `lib/report-verdict.sh`). Sourct
`run-pipeline.sh` eine **neue** Lib (in #197: `lib/tier-select.sh`), bricht das `source` in genau
diesen Temp-Repos mit „No such file" ab – und zwar **nicht** in den Tests der neuen Lib (die kopieren
sie), sondern in **fremden**, bestehenden Tests (hier `#101`, 2 rote Tests, deren Ursache erst auf
den zweiten Blick sichtbar war).

**Smell:** „Ich habe `run-pipeline.sh` ein `source …/lib/<neu>.sh` hinzugefügt – kopiert **jede**
`mktemp`-Pipeline-Kopie in `run-tests.sh` diese Lib?"

**Regel:** Beim Hinzufügen einer gesourcten Datei zu `run-pipeline.sh` **alle** Scaffolding-Stellen
in `run-tests.sh` finden (`grep -n 'cp .*lib/report-verdict.sh'` als Ankerpunkt – dort steht das
Muster) und die neue Lib daneben mitkopieren. Danach die **volle** Suite laufen lassen, nicht nur
die neuen Fälle – die Regression zeigt sich in fremden Tests, nicht in den eigenen.

### Layout-Timing-Test-Stub (rAF) vor dem Neuschreiben im Verzeichnis suchen (aus #194, Review-Finding)

`IdentityGate.test.tsx` (#194) schrieb denselben `requestAnimationFrame`-Capture-Stub
(`rafCallbacks`-Array + `flushRaf()`) nochmal von Grund auf, den `FokusListe.test.tsx` bereits aus
#188 für exakt dasselbe Problem (Fokus/Scroll erst im nächsten Frame nach einem layout-änderndem
State-Wechsel) mitbrachte – im selben Verzeichnis (`app/theke/[token]/`). Der Reflow-Timing-Test
selbst war korrekt; nur die Infrastruktur dafür wurde blind dupliziert statt wiederverwendet.
Erst im Code-Qualität-Review aufgefallen, nicht in `/implement` – der Reflex ist, einen
funktionierenden Test-Setup-Block aus Erinnerung zu reproduzieren statt im Zielverzeichnis danach
zu suchen.

**Smell:** „Schreibe ich gerade einen `beforeEach`, der `requestAnimationFrame`/`IntersectionObserver`
o.ä. stubbt, um Layout-Timing zu testen?" → vor dem Schreiben `grep -rl "requestAnimationFrame"
<gleiches-Verzeichnis>/*.test.tsx` prüfen, ob es den Stub schon gibt.

**Regel:** Vor einem neuen Timing-/Browser-API-Stub (rAF, `IntersectionObserver`, `matchMedia` etc.)
in einer Testdatei erst im **selben Feature-/Routen-Verzeichnis** nach einem bereits bestehenden
Stub für dieselbe API suchen. Gibt es einen, in ein geteiltes Helper-Modul auslagern (z. B.
`app/theke/[token]/raf-stub.ts`, exportiert eine `flush()`/`pendingCount()`-Factory) statt ihn zu
kopieren – auch wenn nur zwei Testdateien ihn brauchen (kein Over-Engineering, da es sich um
Test-Infrastruktur handelt, nicht um Produktionscode-Abstraktion).

### Callback-Prop nur durch Codelesen belegt ist keine Testabdeckung – Coverage-Report gegen jedes „Review-Positiv" gegenprüfen (aus #187, Test-Selbstfund)

`IdentityGate` verkabelte den editierbaren Zweig mit
`onFokusWechsel={(id) => writeZielId(token, id)}`. Reviews über drei Runden bewerteten das AC „F7
merkt Ziel weiterhin geräte-lokal" als erfüllt – belegt durch **Codelesen** (die Zeile ist da, der
Callback wird nur im editierbaren Zweig gesetzt). Kein Test tippte in der Fokus-Ansicht tatsächlich
auf einen anderen Chip und prüfte `localStorage`. Erst `pnpm vitest run --coverage` markierte
`IdentityGate.tsx:169` als **nicht** ausgeführt – die Arrow-Function wurde beim Rendern zwar
*erzeugt*, aber ihr Rumpf (`writeZielId(...)`) nie *aufgerufen*, weil kein Test den Chip-Klick im
schon-gemerkten Zustand simulierte.

**Smell:** „Ist dieses AC nur durch **Lesen** der Verkabelung als erfüllt bewertet (Review-Positiv),
oder gibt es einen Testfall, der den Callback tatsächlich **auslöst** und seine Wirkung prüft
(hier: den geschriebenen `localStorage`-Wert)?" Bleibt die Antwort „nur gelesen", ist die Zeile
ungetestet – unabhängig davon, wie plausibel die Verkabelung beim Lesen wirkt.

**Regel:** Für jede inline verkabelte Callback-Prop (`onX={(arg) => sideEffect(arg)}`), die ein AC
über Verkabelung (nicht über sichtbaren Render-Output) erfüllt, braucht es einen eigenen Testfall,
der den auslösenden User-Event tatsächlich feuert und die **Wirkung** des Callback-Rumpfs prüft
(Mock-Aufruf, `localStorage`-Wert, o. ä.) – nicht nur, dass die Komponente rendert. Vor dem
Abschluss von `/test` den Coverage-Report (`pnpm vitest run --coverage`) gezielt auf die Zeilen der
neu verkabelten Callbacks prüfen, nicht nur auf die Gesamt-Prozentzahl – ein Review-„Positiv", das
nur den Code liest, ersetzt diesen Beleg nicht.

### Strict-mode-/Umgebungs-Kontrakt-Tests gehören auf die Fehler-/No-Match-Zweige, nicht den Happy-Path (aus #207, Review-Finding W3)

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

### Spiegel-/Symmetrie-Akzeptanzkriterien: beide Richtungen explizit assertieren (aus #211, Review-Runde-1-Finding)

#211 hatte für den Security-Anker eine Assertion in der einen Richtung (AK4: Verdict-Zeile
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

### Deterministisches Gate/Backstop in einem Orchestrator-Skript braucht einen E2E-Verhaltenstest, nicht nur einen Wiring-Grep (aus #212, Review-Runde-2-Finding)

#212 fügte `run-pipeline.sh` einen Endzustands-Verifikations-Backstop hinzu (Verletzung →
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
Codelesen belegt ist keine Testabdeckung" (#187) und „Reihenfolge-Guards: Kommando ≠ Prosa" (#114)
um Orchestrator-Gates.

### Negativ-Test mit mehreren Fail-Pfaden muss auf den Ziel-Pfad isoliert werden – sonst grün aus dem falschen Grund (aus #214, Review-Finding W1, von 2 Personas unabhängig)

#214 führte einen Drift-Guard mit mehreren unabhängigen Fail-closed-Pfaden ein (fehlender
Verdict-Anker **und** fehlende Findings-Sektionen führen je zu `exit 1`). Der Negativtest für
Fehlerszenario 2 („Verdict-Anker nur im Fließtext, nicht als Überschrift → rot") nutzte ein
Fixture, das **weder** den Verdict-Anker als Überschrift **noch** die Findings-Sektionen enthielt.
Damit trug bereits die Sektions-Prüfung das `exit 1` – der Test war grün, belegte aber **nicht** die
exakt-verankerte Verdict-Logik. Hätte jemand genau diese (die #211-Regression: Verdict unankert
gematcht), wäre der Test **trotzdem grün** geblieben, weil die fehlenden Sektionen das Exit trugen.

**Smell:** „Kann die zu prüfende Funktion in diesem Negativtest über **mehr als einen** Pfad rot
werden – und stelle ich sicher, dass **nur der eine** Pfad greift, den der Testname behauptet?"

**Regel:** Ein Negativ-/Fehlerfall-Test gegen eine Einheit mit mehreren unabhängigen Fail-Pfaden
muss das Fixture so bauen, dass **alle anderen** Bedingungen erfüllt bleiben und **nur** der
Zielpfad fehlschlägt – und zusätzlich das **pfadspezifische Fehlersignal** assertieren (Meldung/
Konstante), nicht bloß `exit != 0`. Konkret in #214: das Fixture aus der echten Quelldatei ableiten
und nur das Zielmerkmal brechen (die `## Empfehlung`-Überschrift → Fließtext), sodass die Sektionen
intakt bleiben; dann `grep` auf `report_verdict(review)` in der Ausgabe **und** die Abwesenheit der
anderen Fehlermeldung (`count_section_items` darf **nicht** erscheinen) prüfen. Ergänzt „Guard-
Clause-Branches brauchen dedizierte Tests" um Einheiten mit mehreren gleichzeitig auslösbaren
Fail-Pfaden. (Der TDD-Stub `guard() { return 0; }` beweist nur Nicht-Vakuität – dass der Test
**überhaupt** rot werden kann –, nicht die Isolation; beides ist nötig.)

### Kopplungs-/Drift-Guard, der Quelle A gegen Quelle B prüft, braucht einen Negativtest je Seite (aus #214, /test-Selbstfund zu AC6)

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
nicht still grün" abdecken. Spezialfall der #211-Symmetrie-Regel, zugeschnitten auf Kopplungs-/
Drift-Guards.

### ESLint-Ignore-Config verhaltensbasiert testen – mit Diskriminierungs-Kontrolle (aus #172, /test-Selbstfund)

Die Ignore-Liste (`globalIgnores`) einer ESLint-**Flat-Config** (`eslint.config.mjs`) wird von
ESLint geladen, **nicht** von Vitest importiert → sie erscheint nicht im Coverage-Report, und ein
String-Match auf das Config-Array beweist nur, dass ein Eintrag *dasteht*, nicht dass ESLint ihn
*anwendet*. Der belastbare Guard prüft das **Verhalten** über die ESLint-Node-API:
`await new ESLint().isPathIgnored("<pfad>")`. Zweite, in `/implement` übersehene Falle: `isPathIgnored`
ist ein boolesches Mitgliedschafts-Prädikat – reine `toBe(true)`-Assertions (der Pfad wird
ignoriert) blieben auch bei einer versehentlich **zu breiten** Regel (z. B. `"**"`) grün. Erst in
`/test` aufgefallen; der Reflex ist, nur die „soll-ignoriert"-Richtung zu prüfen.

**Smell:** „Ich assertiere nur, dass ignorierte Pfade `true` liefern – würde mein Test auch dann
grün bleiben, wenn die Ignore-Regel *alles* erfasst?" Wenn ja, fehlt die Diskriminierungs-Kontrolle.

**Regel:** Ein Test einer Ignore-/Allow-Liste (oder jedes booleschen Mitgliedschafts-Prädikats)
prüft das echte Verhalten (bei ESLint: `isPathIgnored`, nicht das Config-Array) **und** enthält
eine **Positiv-Kontrolle in der Gegenrichtung** – eine bekannte Nicht-Mitglied-Eingabe, die das
Gegenteil liefern muss (hier: eine normale Quelldatei wie `app/layout.tsx` → `isPathIgnored === false`).
Als konkretes JS-Prädikat-Analogon zu #211 (beide Richtungen) und #212 (Positiv-Gegenprobe): ohne
die `false`-Kontrolle beweist der Test nur „ist-immer-ignoriert", nicht „ignoriert **genau** das
Richtige". Bei mehreren Ignore-Zielen jedes einzeln assertieren (Wegfall genau eines Eintrags → nur
der zugehörige Test rot).
