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

### Row/Cell-Index-Assertions gegen einen gerenderten Report sind beim Schreiben Magic Numbers – Herleitung sofort mitschreiben (aus #189, Review-Runde-1-Finding)

Ein Test für `berichtXlsx.ts` (Excel-Renderer) rendert einen Bericht und liest ihn über
`workbook.xlsx.load()` zurück, um konkrete Zellwerte zu prüfen (hier: Formula-Injection-
Neutralisierung in `bezeichnung`/`anzeigename`). Die naheliegende erste Fassung griff direkt
`sheet.getRow(2)`, `sheet.getRow(9)`, `sheet.getRow(14)` – korrekt hergeleitet aus der
Zeilenreihenfolge des Renderers, aber **ohne** Kommentar, warum genau diese Zahlen stimmen. Ohne
Herleitung ist so ein Row-Index nicht von einem echten Zufallswert zu unterscheiden: Ändert sich
das Renderer-Layout (eine Kopfzeile mehr, ein zusätzlicher Teilnehmer vor der Zielzeile), bricht
der Test **stillschweigend falsch** (liest die falsche Zelle, statt rot zu werden) – erst im
Review (nicht in `/implement`) als Magic-Number-Verstoß gegen `clean-code.md` aufgefallen.

**Smell:** „Ich greife in einem Renderer-Round-Trip-Test auf `getRow(<Zahl>)`/`getCell(<Zahl>)` zu
– kann ich in einem Satz erklären, warum genau diese Zahl die Zielzelle trifft, ohne den
Renderer-Quellcode danebenzuhalten?" Wenn nein, fehlt die Herleitung.

**Regel:** Row-/Cell-Index-Zugriffe in einem Renderer-Round-Trip-Test (Bericht rendern → Datei-
Format zurücklesen → Zellwert prüfen) sofort beim Schreiben als **benannte Konstanten mit
WHY-Kommentar** einführen, der die Zeilen-Arithmetik gegen die tatsächliche `addRow`-Reihenfolge
im Renderer referenziert (z. B. „5 Kopfzeilen + Leerzeile + Header + Preiszeile ⇒ Zeile 9 für den
ersten Teilnehmer") – nicht erst auf einen Review-Fund warten. Wiederkehrende Lade-/Cast-
Boilerplate (`new Workbook()` + Format-Load) in einen kleinen Helper extrahieren, wenn mehr als
ein Testfall sie braucht.

### Flaky Timeout durch unamortisierten teuren Erst-Aufruf: in `beforeAll` aufwärmen mit eigenem, endlichem Timeout – nicht das Default-Timeout global erhöhen (aus #238)

`eslint.config.test.ts` (#172-Regression-Guard) schlug sporadisch mit einem Timeout fehl, aber
**nur** unter Parallellast (volle Suite, viele Worker) – isoliert lief er immer grün. Ursache:
`new ESLint().isPathIgnored(...)` löst beim **ersten** Aufruf die teure Flat-Config-Resolution
aus (lädt `eslint.config.mjs`, cached das Config-Array danach pfad-unabhängig). Unter
Parallellast überschritt allein diese einmalige Resolution gelegentlich das Vitest-Default-
Timeout (5000 ms) des ersten Testfalls – ein klassischer „isoliert immer grün, unter Last
manchmal rot"-Flaky, der leicht als reines Last-/Infrastruktur-Problem abgetan wird.

**Smell:** „Dieser Test ist isoliert **immer** grün, aber unter voller Suite/Last gelegentlich
rot mit Timeout" + der erste Testfall ruft eine teure, aber cachende Operation zum ersten Mal
auf (Config-Resolution, Erst-Verbindung, Erst-Kompilierung o. ä.). Der Reflex „globales
Vitest-Timeout hochsetzen" behebt das Symptom für **alle** Tests und maskiert echte Hänger.

**Regel:** Den teuren Erst-Aufruf explizit in einem `beforeAll` vorab ausführen (Aufwärmen) und
diesem `beforeAll` ein **eigenes, großzügigeres, aber weiterhin endliches** Timeout geben (hier
30_000 ms statt des 5000-ms-Defaults) – nicht das globale Timeout aller Testfälle erhöhen. Die
eigentlichen Testkörper bleiben beim Default-Timeout, da die teure Ressource danach bereits
aufgelöst/gecacht ist. Ein echter Hänger in der Resolution schlägt weiterhin nach endlicher
Frist fehl (kein unbegrenztes Timeout, das Bugs maskiert – Zero-Tolerance-Vorgabe oben bleibt
gewahrt). Pfad-Literale, die im Aufwärm-Aufruf **und** in einer Testassertion (z. B. einer
Positiv-Kontrolle) identisch sein müssen, sofort als geteilte benannte Konstante einführen, um
Drift zwischen beiden Stellen zu verhindern.

### Neue Regressions-Assertion-Schleife gegen bereits vorhandene Schleife mit identischem Rumpf abgleichen, bevor eine parallele Schleife angelegt wird (aus #240, /test→/refactor-Diskrepanz)

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
Verfügbarkeits-/Capability-Prüfung gegen bereits vorhandene abgleichen" (aus #224,
`code-style.md`) – gilt genauso für Regressions-Assertion-Schleifen in Bash-Testsuiten, nicht
nur für Capability-Checks wie `command -v`.

**Rezidiv trotz vorhandener Lesson, ausgelöst durch mehrdeutigen Spec-Wortlaut (aus #251,
Review-Runde-1-Finding):** `/implement` legte für `run-tests.sh` erneut eine rumpfidentische
Schleife neben eine bestehende an (`jq -e --arg v "$entry" '.permissions.allow | index($v) !=
null' ...`, nur andere Werteliste) – **obwohl** genau diese Lesson bereits existierte und im
selben File ein Merge-Präzedenzfall (die #240-AK1-Schleife) sichtbar war. Ursache: Die Spec
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

### `grep -qF`-Fixed-String-Regressionstest gegen Markdown-Prosa: beim Umformulieren/Umbrechen die exakte Testphrase auf einer Zeile halten (aus #240, /review-Rework-Selbstfund, 2× in derselben PR-Session; 3. Vorkommnis aus #249, umgekehrte Kausalrichtung)

Ein Review-Fix korrigierte stale `Write(...)`-Prosa in `factory-workflow.md` und brach dabei
**zweimal hintereinander** einen bestehenden `grep -qF 'ist seit #224 über eine generische'
"$WORKFLOW_LESSON"`-Regressionstest (aus #224, AK7) – nicht durch einen inhaltlichen Fehler,
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

**Drittes Vorkommnis, umgekehrte Kausalrichtung (aus #249, /test-Selbstfund):** Bei Task 249
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

**Viertes Vorkommnis, wieder „neuer Test bricht an bereits vorhandener Prosa" (aus #286,
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

### „Kein Argument übergeben"-Test simuliert nicht automatisch Abwesenheit, wenn das Skript einen echten Repo-Datei-Default hat (aus #254, Review-Finding)

Task 254 ergänzte Gate #254 AK6 („kein Override-File vorhanden → neue Checks übersprungen").
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

### YAML-Testfixture per `printf >>` an eine Kopie mit bereits vorhandenem Top-Level-Key anhängen erzeugt ein Duplicate-Key-Dokument – Test besteht nur zufällig (aus #255, Review-Runde-3-Finding)

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

### Neuer git-Repo-Fixture-Helper, der committet, braucht lokale Git-Identität – auch wenn er lokal zufällig ohne sie durchläuft (aus #265, Review-Finding)

Ein neuer Testfixture-Helper (`hi_repo()` im #265-Abschnitt von `run-tests.sh`, AK4-Worktree-Test)
rief `git init` + später `git commit` auf, ohne vorher `user.email`/`user.name` lokal zu setzen –
anders als jeder andere commit-erzeugende Helper in derselben Datei (u. a. das direkte
Schwestermuster `ih_repo()` aus dem #262-Abschnitt, das denselben Worktree-Aufbau nutzt und dort
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

### Positions-/Zustand-Freeze-Test ohne vorherige Divergenz-Aktion ist nicht diskriminierend – dreifach im selben Task übersehen (aus #253, Review-Runde 1–3, W-Findings)

Task #253 fror die Render-Reihenfolge einer Liste client-seitig ein (`useState`-Initializer); der
Server liefert bei jedem Rerender ggf. eine andere Sortierung, die eingefrorene Position soll aber
bestehen bleiben. Drei aufeinanderfolgende Review-Runden fanden an drei verschiedenen Stellen
(`page.test.tsx` StatusToggle-Test, `EingefroreneZeilenListe.test.tsx` Fehlerszenario-Test)
denselben Fehler: `render`/`rerender` wurden mit **identischen** bzw. nicht-divergierenden Props
aufgerufen. Solange Server-Reihenfolge und eingefrorene Reihenfolge gleich sind, ist weder eine
Reihenfolge- noch eine daran hängende Status-Assertion diskriminierend – beide bleiben grün, ob
der Freeze-Code existiert oder komplett entfernt ist (Mutation `ordneNachEingefrorenerReihenfolge(
…).map(...)` → `zeilen.map(...)`: Test bleibt grün).

**Smell:** „Mein Test prüft ‚Position/Status bleibt trotz X unverändert' – divergiert die
Server-Reihenfolge an irgendeiner Stelle im Testverlauf tatsächlich von der eingefrorenen? Wenn
nicht, kann die Assertion gar nicht unterscheiden zwischen ‚Freeze wirkt' und ‚kein Freeze da'."

**Regel:** Ein Freeze-/Unverändert-Test (Position, Reihenfolge, Zustand bleibt über einen Rerender
hinweg stabil) braucht **zuerst eine echte, state-ändernde Aktion**, die Server- und eingefrorenen
Zustand tatsächlich auseinanderlaufen lässt (hier: ein *erfolgreicher* Kassiervorgang, der die
Server-Sortierung ändert), **bevor** der eigentliche Zielfall (z. B. ein *fehlgeschlagenes*
Kassieren, ein StatusToggle) ausgeführt wird. Ohne diesen vorgeschalteten Divergenz-Schritt ist der
Test bestenfalls ein Wiring-Test, kein Freeze-Beweis – Spezialfall von #214 („grün aus dem
falschen Grund"), hier auf Zustands-Freeze statt auf Fail-Pfad-Isolation zugeschnitten.

### Positivkontrolle für einen Mutations-Fixture darf nicht denselben Fail-closed-Pfad eines anderen Guards teilen (aus #284, Review-Runde-2-Nitpick + /test-Selbstfund)

Task #284s Guard-Familie (`poll_trigger_guard`/`poll_dispatch_guard`/`poll_permission_guard`)
belegt Regressionen über `! poll_*_guard "$mutant.yml"`. Review-Runde 2 merkte an: dieser
Fail-Pfad ist identisch mit dem Fail-closed-Fall „Datei nicht lesbar" (AK6) – bliebe die
Mutanten-Datei aus (`mktemp` schlägt fehl, Redirect geht ins Leere), würden alle Belege grün,
ohne etwas geprüft zu haben (Lesson #214-Klasse). Der Fix: je Mutant eine **Positivkontrolle** –
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
für Negativtests. Ergänzt #214 („Negativtest auf Zielpfad isolieren") – hier ist es der
**grüne** Kontroll-Pfad, der isoliert werden muss.
