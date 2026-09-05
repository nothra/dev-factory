# ADR 047: `@import`-Kontext der 5 Guidelines nach Erzwungenheit schneiden

## Status

Accepted

## Kontext

`CLAUDE.md` bindet fünf Guidelines per `@import` ein. Sie werden damit bei **jeder** Session und
**jedem** Pipeline-Schritt vollständig geladen. Gemessen im Worktree (2026-09-04):

| Datei | Zeilen | Anteil am Guidelines-Block |
|-------|-------:|---------------------------:|
| `guidelines/git-workflow.md` | 390 | 45 % |
| `guidelines/testing-standards.md` | 181 | 21 % |
| `guidelines/clean-code.md` | 131 | 15 % |
| `guidelines/tdd-principles.md` | 84 | 10 % |
| `guidelines/architecture-principles.md` | 79 | 9 % |
| **Guidelines-Block** | **865** | |
| `CLAUDE.md` (selbst) | 204 | |
| `docs/factory/PROJECT-CONTEXT.md` | 341 | |
| **@import-Kontext gesamt** | **1.410** | |

[ADR-037](037-lessons-auslagern-aus-import-kontext.md) hat die 45 `/codify`-Learnings aus diesem
Pfad nach `docs/factory/lessons/` ausgelagert, den Guidelines-Block aber ausdrücklich
ausgenommen („Guidelines-Dateien und ihre `@import`-Einbindung bleiben unverändert") – und
benennt „5 Guidelines … für jeden der ~7 sequenziellen Stage-3-Agenten" im eigenen Kontext als
Teil des Problems, ohne es zu lösen. Der Punkt war unentschieden, nicht erledigt; Issue #319 löst
ihn heraus. Spec: [`spec-319`](../specs/spec-319-adr-import-kontext-guidelines.md).

**Drei Befunde aus der Bestandsaufnahme, die die Entscheidung tragen:**

1. **Der `@import` ist heute der einzige Zustellweg.** Von allen Skills nennt nur
   `refactor.md:8` eine der 5 Guidelines in seinem „Kontext laden"-Block (`clean-code.md`);
   `implement.md`, `test.md`, `requirements.md`, `pr-shepherd.md` nennen keine. Wer eine Datei
   aus dem `@import` nimmt, muss den Trigger also aktiv schaffen – „der Agent liest sie schon
   bei Bedarf" trifft für den heutigen Stand nicht zu.
2. **Jeder Pipeline-Schritt ist eine eigene Session.** `run_skill()` in
   `scripts/run-pipeline.sh:293` ruft je Skill ein eigenes `claude --print` auf. Der
   `@import`-Präfix ist über die ~7 Aufrufe identisch, weshalb der Prompt-Cache dort real
   greift. Ein Kosten-**Geld**-Argument gegen den heutigen Zustand ist damit schwach – und
   ohnehin nicht belegbar, weil #314 nur Prozess-Metriken liefert und OTEL (Token/Kosten pro
   Skill) per Default aus ist. Diese ADR stützt sich deshalb **nicht** auf Geldkosten.
3. **Die Guidelines unterscheiden sich fundamental darin, ob ihre Regeln technisch erzwungen
   sind.** Das ist das entscheidende Kriterium (siehe Entscheidung).

**Zusatzbefund (Issue #319):** Der Lessons-**Index** in `PROJECT-CONTEXT.md` – als Ersatz für den
ausgelagerten Volltext auf „~60–80 Zeilen" kalkuliert – steht heute bei 341 Zeilen. Es gibt
keinen Mechanismus, der ihn beschneidet: dieselbe Governance-Lücke wie bei ADR-037, eine Ebene
höher. Sie gehört in diese Entscheidung, nicht in eine dritte Runde.

## Entscheidung

### 1 · Unterscheidungskriterium: technisch erzwungen vs. nur durch Kontext wirksam

Eine Guideline darf den Dauerkontext verlassen, wenn **eine** der beiden Bedingungen gilt:

1. **Erzwungen:** Ihre Verbindlichkeit hängt nicht vom Gelesenwerden ab, weil ein Gate, Hook oder
   Ruleset sie fail-closed erzwingt.
2. **Enger Adressatenkreis:** Ihre Regeln betreffen nur namentlich benennbare Skills, für die ein
   „Laden bei"-Trigger existiert oder geschaffen wird – dann trägt der Trigger die Zustellung,
   auch ohne technische Erzwingung.

Wo die Regel **nur** dadurch wirkt, dass der Agent sie im Kontext hat, **und** jeden Schritt
treffen kann, bleibt sie geladen. Begründung: Bei Lessons ist Nicht-Laden folgenlos (man findet
die Lesson später), bei einer Gate-Regel ist es eine stille Verletzung – und still verletzte
Clean-Code-/TDD-Regeln fallen erst im Review auf, also nach der Arbeit.

Bedingung 2 ist die schwächere und trägt allein den Fall `architecture-principles.md` (§2). Sie
ist bewusst an „namentlich benennbar" gebunden: sobald der Adressatenkreis „jeder Schritt" ist,
greift sie nicht mehr, sonst wäre jede Datei auslagerbar.

### 2 · Der Schnitt je Datei

| Datei | Entscheidung | Erzwungen durch | Begründung |
|-------|--------------|-----------------|------------|
| `git-workflow.md` (390) | **raus** aus `@import`; 8 Kern-Kurzregeln + „Laden bei"-Trigger inline (§3) | Ruleset `protect-main` (serverseitig fail-closed, auch für Admins) – der `pre-push`-Hook ist daneben nur lokales, umgehbares Feedback; `issue-sync`-Gate (Task↔Issue), `pr-closes-issue`-Job (`Closes #<id>`). **Nicht** erzwungen sind: das Commit-Message-Format (der `commit-msg`-Hook lehnt ausschließlich `--help`/`-h` ab, `commit-msg-check.sh` §Scope) und der Branch-Typ – `branch-name-check.sh` ist ein Claude-Code-**PreToolUse**-Hook auf den Bash-Tool-Input und greift nur bei `checkout -b`/`switch -c` aus Claude Code, nicht bei `git worktree add -b`, nicht außerhalb von Claude Code und in keinem Push-/CI-Gate. Für beide tragen die Kern-Kurzregeln 2 und 5 | Größter Block, geringstes Risiko: die harten Grenzen stoppen einen unwissenden Agenten fail-closed. Zudem ist ein großer Teil Mensch-/Setup-Doku (`git gone`-Alias, Hook-Installation, Worktree-Aufräumen, Secret-Hygiene) oder Label-Nachschlagewerk, das nur `review`/`security-review`/`codify` punktuell brauchen |
| `architecture-principles.md` (79) | **raus** aus `@import`; Trigger `/architecture`, `/review` | – (nicht erzwungen) | Trotz fehlender Erzwingung ausgelagert, weil der Adressatenkreis eng und scharf ist: generische Prinzipien (SOLID, SoC, DI), die nur zwei Skills brauchen. `architecture.md:26` referenziert die Datei bereits im Aufgabenteil – der Trigger existiert praktisch schon |
| `clean-code.md` (131) | **bleibt** geladen | – (kein Linter prüft Namensgüte, Funktionslänge, Kommentar-Ort) | Betrifft jede code-schreibende Task; Nicht-Laden = stille Verletzung. Prinzip 2 in `CLAUDE.md` („Clean Code. Kein Kompromiss") |
| `tdd-principles.md` (84) | **bleibt** geladen, **verdichtet** | – (kein Gate prüft „Test zuerst geschrieben") | Prinzip 1 in `CLAUDE.md` („Tests zuerst"). Verdichtbar, weil ~40 % Didaktik-Prosa sind („Warum Test-First", „Wenn TDD schwer fällt", „Was TDD nicht bedeutet") – der normative Kern ist Red→Green→Refactor + Granularität |
| `testing-standards.md` (181) | **bleibt** geladen, **verdichtet**; Lessons-artige Teile nach `lessons/testing.md` | Coverage-Gate (80 %) nur für die Coverage-Zahl, nicht für AAA/Mocking/Guard-Tests | Die Abschnitte „Exhaustiveness-Guards", „Mock-Default mit leerem Array" und „Coverage-Ausgabe nur in ignorierte Pfade" sind der Form nach `/codify`-Learnings (Smell → Regel → Beispiel, mit Herkunfts-Issue) und liegen damit am nach ADR-037 falschen Ort. Sie wandern in die Lesson; der regelharte Kern (AAA, Test-Namen, Isolation, Flaky-Toleranz, Coverage-Anforderung) bleibt inline |

**Zielgröße (Richtwert, nicht Zusage):** Guidelines-Block 865 → ~250 Zeilen, `@import`-Kontext
gesamt 1.410 → ~800. Die exakte Zahl wird im PR dokumentiert (spec-319 AC7), nicht hier
vorweggenommen – sie liegt erfahrungsgemäß leicht über dem Richtwert, weil die Kurzregeln und die
Trigger in `CLAUDE.md` zurückwachsen, was der Guidelines-Block abgibt.

### 3 · Absicherung des Gate-Risikos für die ausgelagerten Dateien

Für `git-workflow.md` und `architecture-principles.md` gilt – analog ADR-037 §2, aber mit
umgekehrter Beweislast:

- **Kern-Kurzregeln inline** in `CLAUDE.md`: je ausgelagerter Datei die Regeln, die einen
  beliebigen Pipeline-Schritt betreffen können. Für `git-workflow.md` sind das acht: (1) nie
  direkt auf `main`, (2) Branch-Typ-Konvention, (3) `Closes #<id>` im PR-Body, (4) Rebase statt
  Merge, (5) Commit-Message-Format, (6) Task-ID = Issue-Nummer, (7) der **Verweis** auf
  Labels/Issue-Anlage/Schwelle, (8) Aufräumen nach dem Merge.
- **Was ausdrücklich NICHT gespiegelt wird:** die Label-Konvention, der Issue-Seam und die
  Schwelle „Issue oder `kleinfunde.md`". Sie haben eine eigene kanonische Quelle **mit eigenem
  Drift-Guard**: `git-workflow.md` sagt „Die kanonische Label-Liste bleibt allein in diesem
  Abschnitt", [ADR-018](018-central-issue-seam.md) wiederholt es, und
  [ADR-043](043-schwelle-fuer-autonome-issue-anlage.md) entscheidet „ein Ort je Regel, drei dünne
  Referenzen". Der Registry-Guard aus #315 (`run-tests.sh`, `LABEL_DOC_FILES_315`) bewacht sieben
  Fundstellen – eine achte in `CLAUDE.md` wäre die einzige unbewachte, und zwar die, die jeder
  Agent immer im Kontext hat. Kurzregel 7 ist deshalb ein Verweis, keine Kopie; ein Test hält das
  fest (Abwesenheits-Guard auf die Label-/Schwellen-Formulierungen).
- **„Laden bei"-Trigger** je Datei, im Format des bestehenden Lessons-Index
  (`PROJECT-CONTEXT.md` → „Bedarfsgesteuertes Laden"): Skill + Situation.
- **Referenz-Guard**: Ein Test sichert, dass jede nicht-importierte Guideline in `CLAUDE.md`
  referenziert bleibt – das Muster existiert bereits für `bash-gotchas.md`
  (`scripts/checks/tests/run-tests.sh:1261-1264`) und wird auf die neu ausgelagerten Dateien
  ausgeweitet. Ohne diesen Guard wird eine ausgelagerte Datei zur toten Datei.

### 4 · Governance gegen Zurückwachsen: Deckel als `pre-push`-Check

Ein deterministischer Check begrenzt den **gesamten** `@import`-Kontext (`CLAUDE.md` + rekursiv
alle `@`-eingebundenen Dateien) auf eine Obergrenze:

- **Warum ein Gate und nicht eine Prosa-Pflicht:** ADR-037 hat den Index per Prosa-Konvention
  schlank halten wollen und ist damit von ~80 auf 341 Zeilen gelaufen. Eine zweite
  Prosa-Pflicht derselben Art hätte keinen Grund, anders auszugehen.
- **Warum jetzt und nicht bei #196:** Dort wurde ein Umfangs-Gate bewusst als YAGNI verworfen –
  gestützt auf die `/codify`-Faustregel „Kein Check-Skript aus Reflex: ein Gate nur, wenn der
  Fehler verlässlich grep-bar **und** wiederkehrend ist" (kanonisch in
  [`OPERATING.md`](../factory/OPERATING.md) §5.1). Diese Begründung ist überholt, nicht die
  Faustregel: das Problem ist seither eingetreten und gemessen (341 statt 80 Zeilen), der Fehler
  ist grep-bar (Zeilensumme) und wiederkehrend (zweites Mal nach ADR-037). YAGNI schützt vor
  spekulativen Gates, nicht vor eingetretenen Defekten.
- **Ein Deckel für beide Probleme:** Weil der Check die Summe prüft, deckt er den
  Guidelines-Block **und** das Index-Wachstum mit einem Mechanismus ab (AC4).
- **Grenze als hergeleitete Konstante**, nicht als Magic Number: Ist-Stand nach der Umstellung
  + ~25 % Puffer, aufgerundet auf 50 Zeilen; Herleitung als Kommentar an der Konstante. Der
  Puffer muss legitime Regel-Ergänzungen tragen, ohne den nächsten Wildwuchs zu decken.
- **Fail-closed:** Ist eine `@`-referenzierte Datei nicht lesbar, ist der Check rot (nicht
  „überspringen") – sonst umgeht eine Umbenennung den Deckel lautlos.
- **Fail-closed heißt auch: nicht messbar ist rot.** Lässt sich die Zeilenzahl einer Datei nicht
  ermitteln, ist der Check rot statt still grün, und ein Kandidat, der aus der Projektwurzel
  herausführt (absolut oder `..`), wird abgelehnt statt gezählt. Beides ist Ergebnis der
  Security-Review zu #319: ohne den Integer-Guard machte `$((total + ""))` das Gate lautlos grün,
  und ohne das Confinement war es ein Zeilenzahl-Orakel über beliebige lesbare Dateien der
  Maschine. Abgeleitete Pfade gehen zudem nie durch `echo -e`, damit ein präparierter Pfad die
  Ausgabe der übrigen Push-Checks nicht überschreiben kann.
- **Ort: `pre-push`, plus ein schwaches CI-Bein.** Der Hook ist lokales Feedback und mit
  `--no-verify` umgehbar. Server-seitig läuft der Check heute nur über **eine Assertion** in der
  Self-Test-Suite (`run-tests.sh`, erster Test des #319-Blocks) gegen den echten Repo-Stand, die
  über den required Check `factory-self-test` greift. Das ist genau das Muster, das
  [ADR-041](041-config-validation-ci-required-check.md) für `config-validation-check.sh` als
  fragil verworfen und durch einen eigenen CI-Job plus `required_status_checks`-Eintrag ersetzt
  hat. Hier wird es bewusst zunächst in Kauf genommen: die Ruleset-Änderung braucht nach
  [ADR-029](029-branch-protection-main-ruleset.md) Adminrechte und einen dokumentierten
  `gh api`-Befehl, also einen menschlichen Schritt. Nachgezogen wird das über
  [Issue #328](https://github.com/nothra/tch-gastro-services/issues/328); bis dahin gilt der
  Deckel als lokal erzwungen und server-seitig nur mittelbar abgesichert.
- **Beide Referenz-Formen zählen:** die alleinstehende `@pfad`-Zeile **und** ein `@pfad` mitten in
  Prosa, auch mit Markdown-Dekoration (`**@docs/x.md**`, `_@…_`, `>@…`, geklammert, mit
  angehängtem Satzzeichen). Dass Claude Code diese Formen lädt, ist empirisch belegt (Review zu
  #319: Fixture-`CLAUDE.md` mit dem Pfad in einem Satz gab den Marker zurück, dieselbe Zeile ohne
  `@` nicht) – ein Deckel, der nur Zeilen-Imports zählt, wäre per Prosa-Zeile lautlos umgehbar und
  hätte damit dieselbe Konventions-Abhängigkeit, an der ADR-037 gescheitert ist.
- **Restgrenzen, ausdrücklich benannt** (der Deckel deckt die im Repo vorkommenden und im
  Ladeverhalten belegten Formen ab, nicht beweisbar jede): Inline-Referenzen zählen nur, wenn sie
  auf eine **lesbare Datei** auflösen – anders sind sie von Prosa wie dem real vorhandenen
  „nicht @importiert (ADR-037)" nicht zu unterscheiden. Diese Form ist damit **nicht**
  fail-closed; eine Inline-Referenz auf eine gelöschte Datei fällt still weg. Fail-closed bleibt
  die alleinstehende Zeile – die Form, in der die echten Imports stehen. Ungewöhnliche
  Einbettungen (typografische Anführungszeichen o. ä.) können ungezählt bleiben; die
  Trimm-Liste steht im Skript-Header.

## Alternativen

### Option A: Differenziert nach Erzwungenheit (gewählt)

Vorteile: Nimmt genau die Dateien aus dem Dauerkontext, deren Nicht-Laden folgenlos oder
technisch abgesichert ist – 469 der 865 Zeilen (54 %) ohne neues Gate-Risiko. Trifft beide
Achsen: Reduktion **und** Skalierungsmechanismus (§4). Behält Clean Code und TDD dort, wo sie
unbedingt gelten.
Nachteile: Fünf Dateien, drei verschiedene Behandlungen – höhere Erklärlast als ein
Pauschalmechanismus. Der Schnitt muss je Datei begründet bleiben, sonst driftet er beim nächsten
Zuwachs. Verdichten von `tdd-principles.md`/`testing-standards.md` verlangt die Trennung
„Regel vs. Didaktik", die Urteil erfordert.

### Option B: Nur verdichten, alle 5 bleiben geladen (Kandidat 3 pur)

Vorteile: Null Gate-Risiko (alles bleibt geladen), billigster Schnitt, keine Trigger-Infrastruktur
nötig, kein `.claude/**`-Patch.
Nachteile: Erreicht ~500 statt ~250 Zeilen und lässt die 390 Zeilen `git-workflow.md` –
überwiegend Mensch-/Setup-Doku – im Kontext **jedes** Agenten. „Löst das Skalierungsproblem aber
nicht" (Issue #319): der Kontext wächst weiter, nur langsamer. Verworfen, weil die Ursache
(alles wird immer geladen) unangetastet bleibt.

### Option C: Alle 5 raus, konsequentes ADR-037-Muster

Vorteile: Maximale Reduktion (~80 Zeilen), ein einziger, einheitlich erklärbarer Mechanismus,
keine Sonderfälle.
Nachteile: Verlegt Clean Code und TDD – die beiden nicht verhandelbaren Prinzipien 1 und 2 aus
`CLAUDE.md` – in Dateien, die kein Gate erzwingt und die heute kein Skill lädt (Befund 1). Der
wahrscheinliche Ausgang ist stille Erosion: Code entsteht ohne Test-First, und es fällt erst im
Review auf. Auf der Skalierungs-Achse ist C dagegen so gut wie A: der Dauerkontext ist minimal,
und alles Wachstum landet in nicht geladenen Dateien. Verworfen trotzdem: der Gewinn von
170 Zeilen gegenüber A rechtfertigt das Risiko am Kern des Harness nicht.

### Option C2: Rollen-spezifische Zuschnitte (Kandidat 2 des Issues)

Vorteile: Maximale Relevanz je Schritt – jeder Agent bekäme genau seine Guidelines. Auf der
Skalierungs-Achse die stärkste Option: neue Regeln wachsen in eine Rollen-Datei, nicht in den
gemeinsamen Dauerkontext.
Nachteile: Auf der Gate-Achse die schwächste. Personas werden weder per `@import` geladen noch von
einem Skript zugestellt – `run_skill()` gibt nur den Pfad im Prompt mit, und keine Persona
referenziert heute eine Guideline. Eine Zustellung, die davon abhängt, dass der Agent die
Persona-Datei von sich aus liest, ist für Gate-relevante Regeln zu unzuverlässig; zudem entstünde
eine zweite Zuordnungsquelle neben der Rollen-Tabelle in `CLAUDE.md`, die driften kann. Verworfen –
siehe §Begründung.

### Option D: Nichts ändern (Cache-Argument)

Vorteile: Kein Aufwand, kein Risiko, und das Geldkosten-Argument ist tatsächlich schwach –
identischer Präfix über die ~7 Sessions, der Prompt-Cache greift (Befund 2).
Nachteile: Widerlegt nur die Geld-, nicht die **Relevanz**-Kosten. Irrelevanter Kontext bleibt
irrelevant, auch wenn er billig ist: eine Server-Action-Task trägt 390 Zeilen Git-/Label-/
Worktree-Doku mit, eine CI-Task 84 Zeilen TDD-Didaktik. Verdrängung und Fokusverlust sind vom
Cache unberührt. Auf der Skalierungs-Achse ist D die schlechteste Option: sie ist genau der
Status quo, dessen unbegrenztes Wachstum diesen Task ausgelöst hat. Verworfen – aber die ADR
übernimmt daraus, dass die Begründung **nicht** auf Token-Preise gestützt wird.

## Begründung

Option A ist die einzige, die beide Achsen der Spec trifft, ohne am Kern zu riskieren: Sie
reduziert den Dauerkontext um 54 % des Guidelines-Blocks (§2), sichert die ausgelagerten Regeln
über Kurzregeln, Trigger und Referenz-Guard (§3) und schließt mit dem Deckel (§4) die
Governance-Lücke, die diesen Task überhaupt verursacht hat.

Das Erzwungenheits-Kriterium ist dabei mehr als eine Zuordnungshilfe: Es macht die Entscheidung
**begründbar statt geschmacksabhängig** und beim nächsten Zuwachs erneut anwendbar. Es
korrespondiert mit der bestehenden Defense-in-depth-Logik des Repos (`git-workflow.md`: Hook =
lokales Feedback, Ruleset = verbindliche Grenze): Wo eine verbindliche Grenze existiert, muss der
Kontext sie nicht wiederholen. Wo keine existiert, ist der Kontext die Grenze – und bleibt.

Bewusst **nicht** gewählt wurde der rollenspezifische Zuschnitt (Kandidat 2 des Issues): Personas
werden weder per `@import` geladen noch von einem Skript zugestellt – `run_skill()` gibt nur den
Pfad im Prompt mit, und keine Persona referenziert heute eine Guideline. Eine Zustellung, die
davon abhängt, dass der Agent die Persona-Datei von sich aus liest, ist für Gate-relevante Regeln
zu unzuverlässig; zudem entstünde eine zweite Zuordnungsquelle neben der Rollen-Tabelle in
`CLAUDE.md`, die driften kann (offene Frage der Spec, damit beantwortet).

## Konsequenzen

- **Neue Konvention:** Ob eine Guideline im `@import`-Dauerkontext bleibt, entscheidet sich an
  der Frage „ist ihre Verbindlichkeit technisch erzwungen?". Diese ADR ist die kanonische Quelle
  des Kriteriums; sie ergänzt ADR-037 (dort: Lessons-Volltext) um die Guidelines-Ebene.
- **ADR-037 wird präzisiert, nicht ersetzt:** Der Satz „Guidelines-Dateien und ihre
  `@import`-Einbindung bleiben unverändert" gilt ab hier nicht mehr und erhält einen Verweis auf
  diese ADR. Der Lessons-Teil von ADR-037 bleibt vollständig in Kraft (kein `Superseded`).
- **`CLAUDE.md` ändert sich strukturell:** zwei `@import`-Zeilen entfallen, dafür kommen
  Kern-Kurzregeln + „Laden bei"-Trigger für die zwei ausgelagerten Dateien hinzu.
- **Neues Push-Gate:** Der Deckel-Check läuft bei jedem Push. Er kann legitime Arbeit blockieren,
  wenn der Kontext an die Grenze stößt – das ist beabsichtigt und erzwingt dann eine bewusste
  Entscheidung (konsolidieren oder Grenze mit Begründung anheben), statt lautlos zu wachsen.
- **`/codify` bleibt inhaltlich unberührt**, arbeitet aber künftig gegen einen harten Deckel:
  wächst der Index weiter, wird der Push rot. Das ist der Mechanismus, der ADR-037 fehlte.
- **Wechselwirkung mit ADR-009:** Dort ist als mögliche Arbeit vermerkt, den `@import`-Block aus
  der Config zu speisen. Das ist nicht umgesetzt, und diese ADR macht den Block handkuratierter
  (Kurzregeln + Trigger inline) – ein späterer Config-Ansatz müsste diesen Teil ausnehmen oder
  mit abbilden. Zugleich stimmt die ADR-009-Zeile „Welche Guidelines gelten | `@import` in
  `CLAUDE.md`" nur noch für die drei geladenen; zwei kommen über Trigger.
- **Kein Produktverhalten betroffen** – reine Kontext-/Doku-Umschichtung am Factory-Harness.
- **Fachlich gilt unverändert alles:** Verdichtung reduziert Prosa, Vorfall-Narrativ und
  Redundanz, keine geltende Regel (spec-319 AC5). Beleg über ein Regel-Inventar vorher/nachher.
