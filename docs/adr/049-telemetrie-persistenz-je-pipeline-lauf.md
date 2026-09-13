# ADR 049: Telemetrie-Persistenz je Pipeline-Lauf – in `run-pipeline.sh` integriert, Default an, personenfrei getrackt in Git

## Status

Accepted

## Datum

2026-09-11 (Entscheidungen E3 und E4 am selben Tag revidiert – siehe „Revisionen")

## Kontext

[ADR-006](006-measurement-architecture.md) trennt zwei Messebenen: **Prozess** (Git/GitHub) und
**Telemetrie** (Token/Kosten/Modell-Nutzung via OTEL). Die Prozess-Ebene läuft seit #314
automatisch je Lauf ([ADR-045](045-prozess-messung-je-pipeline-lauf.md)). Die Telemetrie-Ebene
existiert dagegen nur als Beispiel-Datei mit Default aus – es entsteht **keine Historie**.

Damit fehlt die Grundlage für eine Entscheidungsklasse, die die Factory laufend trifft:
**welches Modell für welchen Schritt.** [ADR-038](038-modell-tiers-groessenabhaengig.md) vergibt
Tiers größenabhängig, [ADR-009](009-factory-configuration.md) nennt als späteren
Kalibrierungs-Input ausdrücklich „OTEL-Historie (ADR-006) → Pro-Skill-Verteilung → kalibrierte
Defaults", und [ADR-047](047-import-kontext-guidelines-nach-erzwungenheit.md) musste ohne
Kostenzahlen entscheiden. `spec-314` hat die „Ernte" bewusst vertagt: sie liege „genau auf der
Grenze, die ADR-006 zieht (Option B …) – das braucht eine eigene ADR und eine eigene Issue".
Issue = #334, ADR = diese.

Anforderungen stehen in
[`spec-334`](../specs/spec-334-otel-metriken-je-lauf-persistieren.md) (AK1–AK8). Zwei
Auftraggeber-Vorgaben prägen jede Option:

1. **Keine Personendaten in den persistierten Werten** (AK5, präzisiert am 2026-09-11). Die
   OTEL-Attribute tragen `user.email`, `user.id`, `user.account_id`, `user.account_uuid` und
   `organization.id` – diese Felder dürfen die Ablage nie erreichen.
   *Bis zur Präzisierung lautete die Vorgabe „rein lokal, kein zentraler Versand"; sie ist durch
   „getrackt in Git" (Vorgabe 3) ersetzt. Damit wechselt die Sicherung ihre Natur: vorher
   strukturell (die Daten verließen den Rechner nicht), jetzt ein **Filter im Code**. Eine
   Code-Zusicherung ist schwächer als eine strukturelle und braucht daher einen Guard – siehe
   E5.*
2. **Die Erzeugung ist Teil des normalen Pipeline-Laufs und standardmäßig an**, abschaltbar per
   Parameter (Auftrag vom 2026-09-11). Das kehrt die ursprüngliche Fassung dieser ADR um und
   verschiebt AK4 von *opt-in* auf *opt-out*.
3. **Die Werte werden je Pipeline-Lauf in Git gespeichert, mit Bezug zum Task** (Auftrag vom
   2026-09-11). Getrackt und versioniert, nicht nur lokal abgelegt – die Historie wird damit
   Teil des Repos und über den Task auffindbar.

Die Faktenlage ist in Task 334 gemessen, nicht angenommen (Details in `spec-334`). Relevant:
`agent.name` existiert und weist Sub-Agenten als eigene, disjunkte Messreihe aus; `skill.name`
erscheint beim Aufrufweg der Pipeline (Skill-Datei-Text als Prompt, `run-pipeline.sh:271`)
**nie**; je Pipeline-Schritt startet ein **eigener** `claude`-Prozess; der Console-Output stört
die Pipeline-Logik nicht, weil `run_skill` Exit-Code und Report-*Dateien* auswertet.

**Neu gemessen für E4** (Wegwerf-Worktree, 2026-09-11): `git worktree remove` löscht eine
gitignorete Datei im Arbeitsbaum **ohne `--force` und ohne jede Warnung** mit – Git zählt
ignorierte Dateien nicht als „untracked" und verweigert daher nicht. Da CLAUDE.md das Entfernen
des Worktrees nach dem Merge vorschreibt, hätte die ursprünglich geplante Ablage unter `tasks/`
die Historie bei jedem abgeschlossenen Task lautlos vernichtet.

## Entscheidung

### E1 – Das Konsumieren des OTEL-Kanals ist **nicht** die abgelehnte Option B

ADR-006 lehnte Option B mit zwei Gründen ab: „fragiler **Nachbau** einer Funktion, die Claude
Code nativ und genauer liefert" und „nicht gateway-portabel". Beide greifen hier nicht:

- Es wird nichts nachgebaut. Übernommen werden ausschließlich die von der CLI **selbst
  berechneten** Ist-Werte (`claude_code.token.usage`, `claude_code.cost.usage`). Es entsteht
  kein eigenes Token-Zähl- oder Preismodell.
- OTEL ist laut ADR-006 selbst „client-seitig und backend-unabhängig" – die Ernte überlebt
  einen Gateway-/Modellwechsel genauso wie der Kanal selbst.

Der dritte Kern von Option B – **ein einziger** Metrics-Baustein, der beide Ebenen vermischt –
bleibt abgelehnt und wird respektiert: `scripts/metrics.sh` wird **nicht** erweitert (siehe E4).

**Verbindliche Grenze dieser ADR:** Es wird nie ein Wert selbst berechnet, geschätzt,
interpoliert oder aus Roh-Verkehr rekonstruiert. Emittiert die CLI einen Wert nicht, bleibt er
**leer** und wird als fehlend ausgewiesen. Sobald eine Umsetzung anfängt zu rechnen, ist sie
Option B und damit von ADR-006 verboten.

### E2 – Erhebung über den Console-Exporter, abgesichert durch einen Format-Drift-Guard

`OTEL_METRICS_EXPORTER=console`; die Ernte liest den Roh-Output des Laufs. Die „fragil"-Kritik
aus ADR-006 wird nicht weggeredet, sondern **beherrscht**: ein Drift-Guard prüft das erwartete
Ausgabeformat gegen eine Fixture und schlägt **laut** fehl, wenn das Format nicht mehr erkannt
wird. Stille Null- oder Teilwerte sind unzulässig – ein unerkanntes Format ist ein Fehler, keine
Messung von 0.

### E3 – Integration in `run-pipeline.sh`, Default **an**, Abschaltung per Parameter

Die Telemetrie-Erzeugung ist Teil des regulären Pipeline-Laufs. `scripts/run-pipeline.sh`
aktiviert sie selbst und erntet am Ende; es gibt **keinen** zweiten Einstiegspunkt.

- **Default an.** Ein Lauf ohne weitere Angabe erzeugt Telemetrie.
- **Abschaltbar per Parameter** – ein Schalter analog zum bestehenden `--dry-run` (dessen
  Argument-Parsing in `run-pipeline.sh:53–60` das Muster vorgibt).
- **Die Erhebung darf den Lauf nie gefährden** (AK6, fail-open): Ein Fehler in Aktivierung,
  Ernte oder Auswertung lässt den ursprünglichen Exit-Code unberührt. Das ist bei Default an
  strikter zu nehmen als bei opt-in, weil nun **jeder** Lauf betroffen ist.
- Die Schritt-Zuordnung (AK3) entsteht aus der Marker-Zeile, die `run_skill` ohnehin ausgibt
  (`→ Starte: /<skill> <id> …`) – nicht aus `skill.name`, das auf diesem Aufrufweg
  nachweislich fehlt. Umgesetzt schreibt `run_skill` eine **farbfreie Kopie** derselben Zeile
  in den Roh-Log (`telemetry_note_step`); die Terminal-Ausgabe trägt ANSI-Codes und taugt als
  Parse-Anker nicht. Jeder Marker eröffnet einen eigenen Abschnitt mit laufender Nummer –
  sonst verschmölzen die zwei `/implement`-Aufrufe der Rework-Schleife (zwei Prozesse, zwei
  bei 0 startende Counter) zu einer Zeile und der zweite Betrag verschwände.

**Diese Entscheidung ändert zwei bestehende Zusicherungen; beide sind im selben PR
nachzuziehen, nicht stillschweigend zu brechen:**

1. Die fail-closed-Assertion `run-tests.sh:292` („OTEL ist opt-in (nicht automatisch in
   run-pipeline.sh gesourct)") wird **ungültig**. Sie ist durch eine Assertion zu **ersetzen**,
   die die neue Zusicherung bewacht – dass die Erzeugung standardmäßig läuft **und** der
   Abschalt-Parameter sie wirklich abschaltet. Ersatz, nicht Löschung: ein entfernter Guard
   hinterlässt eine unbewachte Zusicherung.
2. Die ADR-045-Invariante „OTEL bleibt opt-in: die Verdrahtung fasst `config/otel.env*` nicht
   an. Die bestehende Assertion … bleibt gültig." ist überholt. ADR-045 ist entsprechend zu
   ergänzen (Verweis auf diese ADR), damit die beiden ADRs sich nicht widersprechen.

### E4 – **Getrackte** Datei je Lauf unter `tasks/`, im Lauf committet und gepusht

Ablage ist `tasks/telemetry-<task-id>-<zeitstempel>.csv`, **versioniert in Git**. Der Task-Bezug
steckt im Dateinamen und stellt die Verbindung zur `tasks/task-<id>-*.md` her; der Zeitstempel
trennt mehrere Läufe derselben Task (AK1). Geprüft: der Pfad ist von keinem `.gitignore`-Muster
erfasst, also trackbar.

Format: CSV mit Kopfzeile – maschinenauswertbar über viele Läufe (der Zweck) und im Editor
lesbar. Je Messwert eine Zeile mit: Lauf-Zeitstempel, Task-ID, Pipeline-Schritt, **Modell**
(AK8), Herkunft (Hauptsession vs. Sub-Agent inkl. `agent.name`, AK2), Metrik, Werttyp
(`input`/`output`/`cacheRead`/`cacheCreation`) und Wert. **Keine** Spalte trägt Personenbezug
(E5).

**Weil die Datei getrackt ist, muss sie im Lauf committet *und* gepusht werden.**
`verify_final_state` (ADR-040) prüft beides: einen dirty Arbeitsbaum **und** ungepushte Commits
(`verify-final-state.sh:52–59`). Eine nur geschriebene Datei ließe die Verifikation dieses Laufs
bzw. jedes Folgelaufs im selben Worktree fehlschlagen.

**Ort im Ablauf: nach `/codify`, vor `/pr-shepherd`.** Grund: Läuft `PR_SHEPHERD=true`, ist der PR danach gemergt – ein späterer Commit hätte
kein Ziel mehr, und ein Direkt-Commit auf `main` ist verboten. Das ist derselbe Grund, aus dem
CLAUDE.md verlangt, die Task-Datei **vor** dem Merge final zu machen.

**Der Commit staged ausschließlich die eigene Datei.** `scripts/factory-commit.sh` ist hier
**nicht** zu verwenden: es macht `git add -A` (`factory-commit.sh:89`) und würde bei einem
Abbruch mitten im Lauf halbfertige Agenten-Änderungen mitcommitten.

Ausdrücklich **nicht**: ein Abschnitt in `tasks/metrics-<datum>.md`. Diese Datei bleibt
gitignored (ADR-045-Invariante), ist tagesbasiert (mehrere Läufe überschrieben sich, AK1) und
gehört der Prozess-Ebene – die Ebenen-Trennung aus ADR-006 gilt für die Ablage weiter.

### E5 – Personenbezug wird per **Whitelist** ausgeschlossen, bewacht durch einen Guard

Die CSV entsteht durch **Aufnahme benannter Felder**, nicht durch Entfernen bekannter
Personenfelder. Eine Blacklist würde bei einem neuen Attribut in einer künftigen CLI-Version
lautlos Personendaten durchlassen; eine Whitelist lässt im selben Fall höchstens ein Feld
fehlen.

Zulässig sind ausschließlich: Lauf-Zeitstempel, Task-ID, Pipeline-Schritt, `model`,
`agent.name`, Metrikname, Werttyp, Wert. **Nie**: `user.email`, `user.id`, `user.account_id`,
`user.account_uuid`, `organization.id`, `session.id`.

Der **Roh-Output** des Console-Exporters enthält diese Felder und wird deshalb **nie** getrackt;
er ist ein temporäres Zwischenprodukt und nach der Ernte zu verwerfen oder gitignored abzulegen.
Gleiches gilt für Test-Fixtures: nur anonymisiert ins Repo.

Ein Guard in der Testsuite prüft fail-closed, dass eine erzeugte CSV **keines** der verbotenen
Felder enthält – auch dann, wenn die Roh-Eingabe sie trägt. Dieser Test ist die tragende
Sicherung, seit die frühere strukturelle Garantie („verlässt den Rechner nicht") entfallen ist.

## Alternativen

### Zu E3 – Eigener Wrapper-Einstiegspunkt (ursprüngliche Fassung dieser ADR, verworfen)

Ein Skript neben `run-pipeline.sh`, das aktiviert, die unveränderte Pipeline aufruft und erntet.

**Vorteile:** Gate `run-tests.sh:292` und ADR-045-Invariante bleiben unberührt; reversibel (Datei
löschen = Zustand vorher); hält die Orchestrierung frei von einer fremden Belangschicht.

**Nachteile:** zwei Einstiegspunkte, und der telemetriefreie ist der bequemere – die Historie
entsteht nur, wenn man an den richtigen Befehl denkt. Genau das widerspricht dem Zweck: eine
Kalibrierungs-Grundlage, die von Disziplin bei der Befehlswahl abhängt, hat Lücken genau dann,
wenn es eilig war. **Verworfen** auf Auftraggeber-Entscheidung (2026-09-11) zugunsten von
„Default an, abschaltbar".

### Zu E3 – Integration, aber Default aus (opt-in per Parameter/Datei)

**Vorteile:** ein Einstiegspunkt und trotzdem keine Verhaltensänderung für bestehende Läufe;
ADR-006 „Default aus" bliebe wörtlich gültig.

**Nachteile:** teilt den Kernnachteil der Wrapper-Variante – ohne bewusstes Zutun keine Daten.
Verworfen aus demselben Grund.

### Zu E4 – Gitignorete Ablage unter `tasks/` (erste Fassung, verworfen)

**Nachteile:** **stirbt mit dem Worktree** – gemessen: `git worktree remove` löscht die
gitignorete Datei ohne `--force` und ohne Warnung mit. Da CLAUDE.md dieses Aufräumen nach jedem
Merge vorschreibt, wäre die Historie systematisch und unbemerkt verloren. Verworfen.

### Zu E4 – Gitignorete Ablage im gemeinsamen git-Verzeichnis (zweite Fassung, verworfen)

**Vorteile:** überlebt `git worktree remove` (gemessen); `git status` bleibt sauber, die Datei
erscheint nicht einmal als ignoriert; kein `.gitignore`-Eintrag nötig; AK7 strukturell erfüllt.

**Nachteile:** die Historie bleibt **auf einem Rechner**. Sie ist nicht versioniert, nicht
teilbar, nicht wiederherstellbar, wenn der Klon verschwindet, und für niemanden außer dem
Betreiber sichtbar. Das ist zu wenig für eine Grundlage, auf der wiederkehrend Modell- und
Tier-Entscheidungen begründet werden sollen. **Verworfen** auf Auftraggeber-Entscheidung
(2026-09-11) zugunsten von „getrackt in Git, ohne Personendaten".

### Zu E4 – Ablage außerhalb des Repos (z. B. unter `$HOME`)

**Nachteile:** verliert die Bindung an das Repo, in dem gemessen wurde; bei mehreren Klonen
vermischen sich die Reihen. Teilt zudem den Kernnachteil der zweiten Fassung (nicht
versioniert, nicht teilbar).

### Zu E5 – Personenfelder per Blacklist entfernen statt per Whitelist aufnehmen

**Vorteile:** neue, unbekannte Attribute landen automatisch in der Ablage – kein Feld geht
verloren.

**Nachteile:** genau das ist das Risiko. Führt eine künftige CLI-Version ein weiteres
personenbezogene Attribut ein, wandert es lautlos in ein getracktes, gepushtes Artefakt – ein
Fehler, der sich nicht zurücknehmen lässt, weil die Git-Historie ihn konserviert. Bei einer
Whitelist ist der schlimmste Fall ein **fehlendes** Feld. Verworfen: der asymmetrische Schaden
entscheidet.

### Zu E2 – Lokaler OTLP-Empfänger (Collector-Container) auf `localhost`

**Vorteile:** strukturierte Daten statt Text-Parsing, kein Format-Drift-Risiko; der spätere Weg
zu einem echten Backend wäre nur eine Endpunkt-Änderung. Bleibt lokal, erfüllt AK5.

**Nachteile:** macht einen laufenden Container zur Vorbedingung. Läuft er nicht, gehen die Daten
**still** verloren – genau das Verhalten, das `spec-334` als Fehlerszenario ausschließt. Bei der
Messung in Task 334 lauschte auf 4317/4318 nichts; der Normalzustand ist „läuft nicht". Bei
Default an wäre ein stiller Datenverlust in jedem Lauf besonders schädlich.

### Zu E2 – Prometheus-Exporter

**Nachteile:** scheidet an der Prozess-Lebensdauer aus. Die Pipeline startet je Schritt einen
kurzlebigen `claude --print`-Prozess; dessen HTTP-Port stirbt mit ihm. Kein verlässlicher
Scrape-Zeitpunkt, ohne Scrape keine Persistenz.

## Begründung

**Vollständigkeit der Messreihe schlägt Reversibilität** – das ist die Umkehrung gegenüber der
ersten Fassung und der eigentliche Kern der Revision. Die erste Fassung hatte den Wrapper mit
dem Argument gewählt, er sei löschbar und lasse Gate und Invariante unberührt. Das bleibt
richtig, wiegt aber weniger als der Zweck: Eine Historie, die als Grundlage für Modell- und
Tier-Entscheidungen dienen soll, darf keine Lücken haben, die davon abhängen, welchen von zwei
Befehlen jemand unter Zeitdruck getippt hat. Der Preis – ein zu ersetzender Guard und eine zu
korrigierende ADR-Invariante – wird bewusst bezahlt und ist im selben PR fällig.

**Fehler sind Teil des Designs** trägt E2 und den fail-open-Teil von E3. Bei Default an ist
fail-open keine Höflichkeit mehr, sondern Bedingung: eine Messung, die einen erfolgreichen Lauf
scheitern lassen kann, wäre schlimmer als keine Messung. Und ein erkennbares Risiko
(Format-Drift, laut scheiternd) ist einem stillen (nicht laufender Collector) vorzuziehen.

**Eine Entscheidungsgrundlage muss haltbar und teilbar sein** trägt E4. Beide früheren Fassungen
scheiterten daran unterschiedlich weit: die erste starb mit dem Worktree, die zweite überlebte
zwar, blieb aber auf einem Rechner – nicht versioniert, nicht teilbar, verloren mit dem Klon.
Wenn diese Reihe künftig Modell- und Tier-Entscheidungen begründen soll, gehört sie dorthin, wo
im Projekt jede andere begründende Grundlage liegt: ins Repo, versioniert, neben dem Task, auf
den sie sich bezieht. Der Preis ist der Commit-Zwang im Lauf; er ist mit einem festen Ort im
Ablauf beherrschbar.

**Asymmetrischer Schaden entscheidet die Filter-Richtung** trägt E5. Getrackt und gepusht heißt:
ein Fehler ist nicht zurücknehmbar, weil die Git-Historie ihn konserviert. Eine Whitelist kann
ein Feld vergessen (Schaden: eine Spalte fehlt), eine Blacklist kann ein neues Personenfeld
durchlassen (Schaden: personenbezogene Daten dauerhaft im Repo). Bei so ungleichen Folgen ist
die Richtung nicht Geschmackssache.

**Der Wechsel der Sicherungsnatur ist der eigentliche Preis dieser Revision.** Vorher war
„keine Personendaten nach außen" strukturell garantiert – die Daten verließen den Rechner nicht,
es *konnte* nichts passieren. Jetzt hängt dieselbe Zusicherung an einem Filter im Code. Deshalb
ist der Guard aus E5 keine Fleißaufgabe, sondern die Bedingung, unter der diese Entscheidung
vertretbar ist. Ohne ihn wäre sie es nicht.

**Separation of Concerns** bleibt gewahrt, wenn auch anders als zuvor: Die Ernte-Logik gehört in
einen eigenen, testbaren Seam unter `scripts/lib/` (Muster wie `tier-select.sh`), nicht in den
Rumpf von `run-pipeline.sh`. Der Orchestrator ruft, er rechnet nicht. `metrics.sh` bleibt
unberührt – die Ebenen-Trennung aus ADR-006 gilt weiter für die *Ablage*, auch wenn der
*Auslöser* jetzt derselbe Lauf ist.

Die Abgrenzung in E1 ist keine Formalie: ohne sie unterläuft die Umsetzung eine bestehende
ADR-Ablehnung stillschweigend.

## Konsequenzen

**Positiv:**

- Kosten je Lauf, je Schritt und je Modell entstehen **ab dem nächsten Lauf ohne Zutun** –
  die Kalibrierung aus ADR-009 und die Tier-Wahl aus ADR-038 bekommen eine lückenlose
  empirische Grundlage.
- Der Sub-Agenten-Anteil wird sichtbar; er verursacht den Großteil der Last.
- Die Historie ist **versioniert, teilbar und wiederherstellbar** – sie überlebt nicht nur das
  Aufräumen von Worktrees, sondern auch den Verlust des Klons, und ist über den Task-Bezug im
  Dateinamen auffindbar.
- Ein Einstiegspunkt, ein Befehl. Keine Wahl, die man falsch treffen kann.
- Keine Infrastruktur, keine Secrets, kein Telemetrie-Backend – der Weg der Daten ist der
  ohnehin bestehende Git-Push, kein zusätzlicher Kanal.

**Negativ / Trade-offs:**

- **Jeder Lauf verhält sich ab jetzt anders.** Default an ist eine echte Verhaltensänderung;
  AK4 der Spec kippt von opt-in auf opt-out. Wer das nicht will, braucht den Parameter.
- **Zwei bestehende Zusicherungen werden gebrochen** (Gate `run-tests.sh:292`,
  ADR-045-Invariante). Beide sind im selben PR zu ersetzen bzw. zu korrigieren; ein
  gelöschter statt ersetzter Guard wäre die schlechtere Variante.
- **Abhängigkeit von einem Debug-Ausgabeformat.** Der Console-Exporter ist kein zugesagter
  Vertrag; ein CLI-Update kann ihn ändern. Beherrscht, nicht beseitigt – der Drift-Guard macht
  es zu einem laut scheiternden Fall. Bei Default an trifft ein solcher Bruch jeden Lauf, das
  Signal muss also eindeutig sein.
- **Keine `skill.name`-Attribution.** Die Zuordnung hängt an Marker-Zeilen der Pipeline; ändert
  sich deren Wortlaut, bricht die Zuordnung. Auch das gehört unter den Drift-Guard.
- **Die Kosten von `/pr-shepherd` fehlen in der Reihe.** Der Commit muss vor diesem Schritt
  liegen, weil der PR danach gemergt ist. Akzeptiert: `/pr-shepherd` verwaltet den Merge und ist
  der günstigste Schritt; die Lücke ist bekannt und dokumentiert statt unbemerkt. Wer sie
  schließen will, braucht einen Folge-PR nach dem Merge – eigenes Issue, nicht diese ADR.
- **Jeder Task-PR trägt ab jetzt eine Telemetrie-Datei.** Das Repo wächst um eine Datei je Lauf,
  und Diffs enthalten Messdaten neben dem fachlichen Inhalt. Bewusst in Kauf genommen (kleine
  CSV, hoher Nutzen); ein Aufräum-/Aggregationskonzept für viele Läufe ist offen.
- **Die Personendaten-Zusicherung hängt jetzt an Code, nicht an Struktur.** Ein Filter-Fehler
  ist nicht zurücknehmbar, weil die Git-Historie ihn konserviert. Der Whitelist-Guard aus E5 ist
  daher nicht optional. Der **Roh-Output** (mit `user.email` und Account-IDs) wird nie getrackt;
  Fixtures nur anonymisiert.
- **Der Lauf schreibt jetzt selbst in die Git-Historie.** Ein zusätzlicher Commit je Lauf im
  Feature-Branch, mit gezieltem Staging (nicht `factory-commit.sh`, das `git add -A` macht).
  Schlägt der Commit oder Push fehl, greift fail-open – dann fehlt der Messwert, aber der Lauf
  bleibt unberührt.

## Betroffene Stellen

- `scripts/run-pipeline.sh` – Aktivierung (`--no-telemetry` als Abschalt-Parameter im Muster
  von `--dry-run`), Marker-Zeile und Roh-Log-Sink in `run_skill`, `telemetry_persist()` mit
  **Commit/Push der CSV zwischen `/codify` und `/pr-shepherd`** sowie im EXIT-Trap für den
  Abbruchfall – alles fail-open (Exit-Code unberührt); der Commit trägt eine explizite
  Identität (`-c user.email=…`/`-c user.name=…`), statt sich auf ambiente Git-Konfiguration
  zu verlassen (Review-Runde 2, #334)
- **Neu:** `scripts/lib/telemetry-harvest.sh` – Ernte-/Auswertungs-Logik als eigener,
  testbarer Seam inklusive der **Whitelist**-Projektion aus E5
- `scripts/checks/tests/run-tests.sh` – die Assertion „OTEL ist opt-in" **ersetzt** (Default an
  + Parameter schaltet ab), zusätzlich Format-Drift-Guard samt anonymisierter Fixture
  (`scripts/checks/tests/fixtures/otel-console-sample.txt`), der Personendaten-Guard aus E5
  (verbotene Felder erscheinen nie in der CSV, auch nicht bei personenbehafteter Roh-Eingabe)
  und ein E2E-Verhaltenstest gegen den echten Orchestrator
- `docs/adr/045-prozess-messung-je-pipeline-lauf.md` – überholte OTEL-Invariante korrigieren,
  Verweis auf diese ADR
- `docs/specs/spec-334-*.md` – AK4 auf opt-out, AK7 auf die neue Ablage nachziehen
- **Doku:** `CLAUDE.md` bzw. `docs/factory/OPERATING.md` – Default an, Abschalt-Parameter,
  Ablageort
- **Unverändert (ausdrücklich):** `scripts/metrics.sh`, `config/otel.env.example`, ADR-006
  (Ebenen-Trennung und Option-B-Ablehnung gelten weiter)

## Revisionen

- **2026-09-11, E3 und E4 revidiert** (Auftraggeber-Entscheidung bzw. Messergebnis, noch vor
  dem Merge dieser ADR):
  - **E3:** von „eigener Wrapper-Einstiegspunkt, Gate und Invariante unberührt" zu
    „Integration in `run-pipeline.sh`, Default an, Abschaltung per Parameter". Grund:
    Vollständigkeit der Messreihe; ein optionaler zweiter Befehl erzeugt Lücken.
  - **E4 (erste Revision):** von „`tasks/telemetry-*.csv` mit `.gitignore`-Muster" zu
    „Unterverzeichnis des gemeinsamen git-Verzeichnisses". Grund: gemessen – `git worktree
    remove` löscht gitignorete Dateien ohne `--force` und ohne Warnung mit; die Historie hätte
    das nach CLAUDE.md vorgeschriebene Aufräumen nicht überlebt.
- **2026-09-11, E4 erneut revidiert + E5 neu** (Auftraggeber-Entscheidung, ebenfalls vor dem
  Merge):
  - **E4 (zweite Revision):** von „gitignoret im gemeinsamen git-Verzeichnis" zu
    „**getrackt** in Git, `tasks/telemetry-<task-id>-<zeitstempel>.csv`, im Lauf committet und
    gepusht". Grund: eine Historie auf einem Rechner ist nicht versioniert, nicht teilbar und
    mit dem Klon verloren – zu wenig als wiederkehrende Entscheidungsgrundlage. Folgen: Commit
    zwingend zwischen `/codify` und `/pr-shepherd` (danach ist der PR gemergt), gezieltes
    Staging statt `factory-commit.sh`, und die Kosten von `/pr-shepherd` fehlen in der Reihe.
  - **E5 (neu):** Personenbezug wird per Whitelist ausgeschlossen und durch einen Guard
    bewacht. Nötig geworden, weil mit „getrackt in Git" die frühere strukturelle Sicherung
    („die Daten verlassen den Rechner nicht") entfällt – die Zusicherung hängt jetzt an Code
    und muss getestet werden.

## Quelle

Anforderung, Lokal-Vorgabe und die Default-an-Entscheidung: Auftraggeber (Sessions
2026-09-10/11, Issue #334). Vertagt und bedingt gestellt von `spec-314` (#314).
Telemetrie-Ebene ursprünglich angestoßen durch Rene Lengwinat (Teams, 2026-06-17, via ADR-006).
