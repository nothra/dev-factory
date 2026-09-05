# Lessons: Code-Stil

> Ausgelagerte `/codify`-Learnings (Volltext) zu **Clean-Code-Muster (Naming, Kommentar-Ort)**.
> **Nicht** `@import`-geladen (ADR-037) – bei Bedarf gezielt lesen. Kanonische Quelle je
> Regel ist der jeweilige Eintrag hier; im @import-Pfad (`PROJECT-CONTEXT.md`) steht nur eine Index-Zeile.
> Neue Learnings kommen hierher (nicht in den @import-Pfad) – siehe `/codify` + ADR-037.

### WHAT-Kommentar am Modul-Level (aus #67, Refactoring-Finding)

Ein Kommentar `Die Route importiert nur diese Instanz und bleibt dünn.` beschrieb in der
**Modul-Definition** (`lib/rate-limit.ts`), wie ein externer Konsument (die Route) das Modul
nutzt. Das ist ein WHAT-Kommentar am falschen Ort: Er nennt, was der Code macht, nicht warum
er so entworfen wurde – und er beschreibt den Konsumenten statt das Modul selbst.

**Regel:** Kommentare in einer Modul-Definition beschreiben das WHY der **Modul-Entscheidung**
(z. B. fail-open, kein I/O, Singleton wegen Function-Instanz-Lebensdauer). Hinweise auf die
Nutzung durch Konsumenten gehören an die **Aufrufstelle** oder in die öffentliche Schnittstellen-
Dokumentation – nicht in die Modul-Implementierung. Bereits durch `clean-code.md` abgedecktes
Prinzip; hier als konkretes Muster festgehalten.

### Neue `lib/`-Module domänenspezifisch benennen, kein generisches `utils` (aus #105, Review-Finding)

Beim Zentralisieren eines gemeinsamen Helfers entsteht der Reflex, ihn in ein
`lib/form-utils.ts` / `lib/helpers.ts` / `lib/utils.ts` zu legen – auch wenn ein Issue
diesen Namen bereits vorschlägt (in #105 lautete der Issue-Titel wörtlich „… in
`lib/form-utils.ts` zentralisieren"). Das kollidiert mit der etablierten `lib/`-Konvention:
alle Module tragen sprechende Domänennamen (`authz`, `money`, `credentials`, `rate-limit`,
`stage`). Ein generisches „utils" benennt die technische Kategorie statt der Verantwortung
und wird zur „Grabbelkiste", in der Unzusammenhängendes landet (clean-code.md: „Keine
generischen Namen … ohne Kontext").

**Regel:** Ein neues `lib/`-Modul nach seiner **Verantwortung** benennen, nicht nach der
technischen Kategorie – z. B. `form-errors.ts` (Zod-Fehlermeldung → Nutzertext), nicht
`form-utils.ts`. Ein im Issue vorgeschlagener generischer Name ist **kein** Freibrief:
er wurde als Platzhalter notiert, nicht als bindende Design-Entscheidung – im Zweifel im
Review hinterfragen und umbenennen (kostet 1 Datei + Imports). Landet später mehr im Modul,
das keine gemeinsame Verantwortung teilt, ist das ein Zeichen, es aufzuteilen, nicht ein
`utils` zu rechtfertigen.


### Fail-Safe/Guard symmetrisch auf ALLE Inputs einer Vergleichsoperation (aus #197, Review-Finding)

`select_tier(size, threshold, fallback)` sicherte zunächst nur `size` gegen „nicht bestimmbar"
(leer/nicht-numerisch → Fallback), nicht aber `threshold`. Bei nicht-numerischem `threshold` wird
`[ "$size" -ge "$threshold" ]` falsy → stille Ausgabe `light` – also ein **stilles Downgrade** genau
in der Fail-Safe-Linie, deren erklärter Zweck „nie still auf das schwächere Modell" ist. Real nur
erreichbar, wenn ein anderer Guard (hier das Config-Gate) umgangen wird – aber der eine abgesicherte
Input erweckt den Eindruck durchgängiger Absicherung, den der zweite bricht.

**Smell:** „Ich fange Input A gegen den Unbestimmbarkeits-Fall ab – speist die kritische Operation
(`-ge`, `-lt`, Division …) noch einen zweiten Input B, der denselben Fall auslösen kann?"

**Regel:** Trägt eine Funktion einen Fail-Safe für „Input nicht bestimmbar", gilt er **symmetrisch
für jeden Input**, der in dieselbe Vergleichs-/Rechenoperation fließt – sonst leckt die Invariante
über den ungeprüften Zweig. Die Guard-Klausel je Input duplizieren (`case "$x" in ''|*[!0-9]*) …`),
nicht nur für den „offensichtlich unsicheren" Wert. Jeder Guard bekommt zudem einen eigenen Test
(vgl. [`lessons/testing.md`](testing.md) → Exhaustiveness-Guards; bis #319 in
`testing-standards.md`).

### Magic-Number-Konsistenz-Bewertung braucht projektweiten Grep, nicht nur Datei-/PR-lokalen Vergleich (aus #142, Review→Refactor-Diskrepanz)

`/review` Runde 2 (Code-Qualität) bewertete das duplizierte Literal `2_147_483_647` in
`catalogItemSchema` (`priceCents`-Refine + neues `sortOrder`-Max) als „kein Finding" mit der
Begründung: „Kein neues Muster – `priceCents` nutzt bereits denselben Inline-Literal, Konsistenz
mit dem etablierten Muster ist ein triftiger Grund, dies nicht zu werten." Das war die falsche
Schlussfolgerung: Es existierte bereits eine zentrale Konstante `INT4_MAX` in `lib/money.ts`
(dokumentiert, in `app/veranstaltung/schema.ts` bereits genutzt) – der Review verglich nur
**innerhalb derselben Datei** und schloss daraus fälschlich auf „kein Bedarf für eine Konstante",
statt projektweit zu prüfen, ob eine passende Konstante schon existiert. Erst `/refactor` fand es
per Codebase-weitem Grep nach dem Zahlenwert.

**Smell:** Ein Review-Finding zu einem duplizierten Literal/Magic Number wird mit „konsistent zu
einem bestehenden Muster in derselben Datei/demselben PR" abgeschlossen, **ohne** dass zuvor
projektweit (nicht nur im Diff oder der betroffenen Datei) nach einer bereits existierenden
benannten Konstante für denselben Wert gesucht wurde.

**Regel:** Bevor ein Magic-Number-/Literal-Duplikations-Finding als „kein Fix nötig" abgeschlossen
wird, per `grep -rn` nach dem konkreten Wert **und** nach naheliegenden Domänennamen (z. B.
`INT4_MAX`, `MAX_*`) über die gesamte Codebase suchen – nicht nur gegen die geänderte Datei oder
denselben PR vergleichen. „Konsistent mit bestehendem Muster" ist nur dann ein gültiger Grund,
eine Konstante wegzulassen, wenn diese Suche keine bereits existierende zentrale Konstante zutage
fördert. Gilt für `/review` (Code-Qualität-Perspektive) ebenso wie für `/refactor`.

### Fix für einen falschen WHY-Kommentar deckt nur die gemeldete Zeile ab, nicht die kopierten Geschwister (aus #264, Review-Runde-1-Finding, Rezidiv in Runde 3)

Review-Runde 1 fand einen falschen WHY-Kommentar (behauptete eine Kausalkette – „Skript
kehrt vor Phase X zurück" –, die im Code nachweislich nicht existiert) an zwei Stellen
(`#101`, `#212 AK8`) und beide wurden korrigiert. Runde 3 fand **dieselbe falsche
Kausalkette** an einer dritten, strukturell identischen Stelle (Dry-Run-Ausnahme-Kommentar +
Spec-Prosa) wieder – copy-paste-verwandt zu den ersten beiden, aber beim Fixen in Runde 1
übersehen, weil dort nur die explizit gemeldete Zeile korrigiert wurde.

**Smell:** Ein Review-Finding korrigiert einen falschen WHY-Kommentar (falsche Kausalkette,
falsche Kontrollfluss-Behauptung) an genau der gemeldeten Stelle – ohne zu prüfen, ob
dieselbe Behauptung an weiteren, ähnlich aufgebauten Stellen im selben Diff/derselben Datei
wortgleich oder sinngleich wiederkehrt.

**Regel:** Beim Beheben eines falschen-WHY-Kommentar-Findings den zentralen Claim (Kern der
Kausalkette, z. B. „kehrt vor X zurück") per `grep -n` über die betroffene Datei **und** alle
im selben PR entstandenen Doku-/Spec-Stellen suchen, nicht nur die gemeldete Zeile fixen.
Gleiche Sweep-Pflicht wie bei Magic Numbers (oben, #142) und Terminologie (#144) – nur auf
Kommentar-Kausalketten statt Literale/Begriffe angewendet.

### Zähl-/Aufzählungs-nennender Modul-Header wird beim Hinzufügen einer Einheit zur Lüge (aus #207, Review-Finding W1)

Der Datei-Header von `scripts/lib/create-issue.sh` lautete „Diese Datei … stellt **EINE** Funktion
bereit:" und dokumentierte nur `create_issue`. Beim Hinzufügen der zweiten öffentlichen Funktion
`create_issue_idempotent` (#207) blieb der Header unverändert – er verschwieg die neue Funktion und
behauptete eine falsche Anzahl. Erst im Clean-Code-Review (W1) aufgefallen. Der Reflex ist, unten die
neue Funktion samt Doc-Kommentar zu ergänzen und den zusammenfassenden Header oben als „allgemeine
Einleitung" zu übersehen.

**Smell:** „Nennt der Modul-/Datei-Header eine **Anzahl** oder **Aufzählung** seiner öffentlichen
Einheiten (‚stellt EINE Funktion bereit', ‚die drei Helfer', ‚exportiert X und Y') – und füge ich
gerade eine weitere Einheit hinzu (oder entferne eine)?" Dann ist der Header Teil des Diffs.

**Regel:** Ein Header/Docstring, der Menge oder Anzahl der öffentlichen Einheiten eines Moduls
benennt, ist Teil des Vertrags und wird beim Hinzufügen/Entfernen einer Einheit **im selben Commit**
mitgepflegt (Zahlwort **und** Aufzählungsblock). Wo möglich, solche Header **zählungsfrei**
formulieren (z. B. „stellt folgende Funktionen bereit:"), damit sie nicht bei jeder Erweiterung
nachgezogen werden müssen. Dieselbe Drift-Klasse wie die ADR-Mechanik-Regel (#211/#55: eine
Code-Änderung, die eine beschreibende Doku betrifft, pflegt die Doku im selben PR mit) – hier auf
Modul-Docstring-Ebene statt ADR.

### Neue Verfügbarkeits-/Capability-Prüfung immer gegen bereits vorhandene im selben File abgleichen (aus #224, Review-Runde-1-Finding, unabhängig von allen drei Review-Perspektiven aufgegriffen)

In `scripts/checks/tests/run-tests.sh` wurde eine dritte, abweichende jq-Verfügbarkeitsprüfung
(`[ "$(command -v jq >/dev/null 2>&1; echo $?)" -eq 0 ]`) ergänzt, obwohl dieselbe Datei bereits
zwei etablierte Varianten kennt: eine Direktform (`if command -v jq >/dev/null 2>&1; then`) und
eine wiederverwendbare Variable (`command -v jq >/dev/null 2>&1 && HAS_JQ=1 || HAS_JQ=0`, danach
`if [ "$HAS_JQ" -eq 1 ]`). Die neue Variante war funktional identisch, aber eine unnötige dritte
Schreibweise für dieselbe Sache in derselben Datei – gefunden, weil **alle drei** unabhängigen
Review-Perspektiven (Logik, Code-Qualität, Architektur) denselben Punkt unabhängig voneinander
aufgriffen, nicht weil ein einzelner Reviewer besonders aufmerksam war.

**Smell:** „Prüfe ich hier, ob ein Tool/eine Capability verfügbar ist (`command -v`, Feature-Flag,
Versions-Check) – und tut das derselbe File/dasselbe Modul das nicht bereits woanders?"

**Regel:** Vor dem Hinzufügen einer neuen Verfügbarkeits-/Capability-Prüfung per `grep` im selben
File nach bereits vorhandenen Prüfungen derselben Sache suchen (z. B. `grep -n "command -v jq"
<file>`) und die bestehende Variable/Direktform wiederverwenden statt eine neue Schreibweise
einzuführen. Gilt insbesondere für Shell-Skripte mit wachsender Testsuite, wo Prüf-Idiome
(`HAS_JQ`, `HAS_YQ`, `skip_yq`) bereits etabliert sind – Konsistenz mit dem etablierten Idiom
schlägt eine lokal „einfachere" Neuerfindung.

### „Empirisch verifiziert" im Kommentar ohne tatsächliche Prüfung – Rezidiv trotz Fix an anderer Stelle (aus #268, Review-Runde 2 W3 + Runde 4 W1)

In Task 268 behauptete ein WHY-Kommentar „empirisch verifiziert" bzw. „empirisch mit git 2.51
verifiziert", obwohl die Reproduktion in der Sandbox durchgehend permission-blockiert war
(`git`-Aufrufe in Wegwerf-Repos) – die tatsächliche Grundlage war Codelesen +
Doku-Schlussfolgerung, keine echte Probe. Runde 2 (Finding W3) korrigierte das an einer Stelle
auf „analytisch begründet, in dieser Umgebung nicht reproduzierbar". **Zwei Runden später**
fand Runde 4 (Finding W1) exakt dasselbe Overclaiming-Muster an einer **anderen** Kommentarstelle
im selben Skript wieder – nicht weil der erste Fix falsch war, sondern weil die Korrektur nur die
gemeldete Zeile betraf, nicht das Muster als solches. Zusätzlich hatte sich eine falsche
Versionsangabe („git 2.51" statt der tatsächlich installierten 2.50.1 – nie durch `git --version`
geprüft, nur aus einer früheren, ebenfalls ungeprüften Notiz übernommen) unbemerkt auf sieben
Stellen über vier Dateien kopiert (Skript, Testdatei, Spec, ADR, Task-Datei zweifach).

**Smell:** Ein Kommentar/eine Notiz behauptet „empirisch verifiziert", „empirisch geprüft" oder
nennt eine konkrete Versionsnummer/einen konkreten Messwert als Beleg – wurde die zugrunde
liegende Prüfung (Befehl ausführen, Version abfragen) in **dieser** Session tatsächlich
ausgeführt, oder nur aus einer früheren Notiz/Annahme übernommen? Sandbox-/Permission-Blocker bei
`git`-Aufrufen in Wegwerf-Repos sind in diesem Projekt der Normalfall, nicht die Ausnahme (wiederholt
in #268 Runde 2–4 beobachtet).

**Regel:** Vor „empirisch verifiziert"/„empirisch geprüft" im Kommentar oder in Doku den
zugrunde liegenden Befehl in der aktuellen Session tatsächlich ausführen (z. B. `git --version`
für Versionsangaben). Ist die Reproduktion blockiert (Sandbox-Permission, Wegwerf-Repo), den
Kommentar auf „analytisch begründet – in dieser Umgebung nicht reproduzierbar: [Grund]"
formulieren, nie auf „empirisch" aufwerten. Nach dem Beheben eines solchen Findings zusätzlich
projektweit nach Kopien derselben Behauptung/Versionsangabe suchen (`grep -rn` auf die konkrete
Zahl/Formulierung) – dieselbe Sweep-Pflicht wie beim WHY-Kommentar-Fix oben (#264), hier speziell
für Evidenz-Überziehung statt Kausalketten.

### JSDoc auf einem geteilten Options-Interface, die einen konkreten Produktionswert nennt, driftet beim zweiten Konsumenten (aus #182, Review-Runde 1 W2 + Runde 2 Nitpick 1)

`RateLimiterOptions` in `lib/rate-limit.ts` wurde ursprünglich nur von einem Singleton
(`healthRateLimiter`, `limit: 30`) genutzt; das JSDoc auf dem `limit`-Feld nannte entsprechend
„(Produktion: 30)". Task #182 fügte einen zweiten Konsumenten mit abweichendem Wert hinzu
(`selfServiceVerzehrRateLimiter`, `limit: 60`) – das Feld-JSDoc wurde dabei nicht angepasst und
war ab da schlicht falsch für die Hälfte der Instanzen. Review-Runde 1 (W2) korrigierte das
`limit`-Feld auf einen Verweis statt eines Werts. Genau dieselbe Drift lag zeitgleich am
Nachbarfeld `windowMs` (ebenfalls „(Produktion: 60_000)") vor, obwohl beide Felder derselben
Options-Struktur angehören und vom selben Commit betroffen waren – erst Review-Runde 2 (Nitpick 1)
fiel das zweite Feld auf, weil der erste Fix nur die gemeldete Zeile behandelte, nicht das Muster
auf dem ganzen Interface.

**Smell:** „Ich instanziiere ein geteiltes Options-/Config-Interface ein zweites Mal mit einem
anderen konkreten Wert für ein Feld X – nennt das JSDoc von X (oder eines **Nachbarfelds
derselben Struktur**) bereits einen konkreten Produktionswert aus der ersten Instanziierung?"

**Regel:** JSDoc auf einem Feld eines wiederverwendbaren Options-/Config-Interfaces beschreibt
die **Bedeutung** des Felds, nie einen konkreten Wert – sobald absehbar ist (oder gerade passiert),
dass eine zweite Instanziierung einen anderen Wert nutzt. Verweis auf die Stelle, an der die
tatsächlichen Werte stehen (z. B. „die produktiven Werte stehen an den Singletons unten"), statt
eines Literals im Kommentar. Beim Beheben eines gemeldeten Falls **alle Felder derselben
Interface-Definition** auf denselben Drift-Typ prüfen, nicht nur das gemeldete – Spezialfall der
Sweep-Pflicht aus #264 (falscher WHY-Kommentar an kopierten Geschwisterstellen), hier auf
Nachbarfelder statt kopierte Dateien angewendet.

### TL;DR-Merksatz über einem umformulierten Absatz nicht mitgezogen (aus #322, Review-Runde-3-Finding)

Task #322 formulierte einen Doku-Abschnitt um: aus „Neue Claude-Session **je Task** ist
Empfehlung" (ein Satz pro Task) wurde die nuanciertere Regel „Regelfall: eine Session für
start-work.sh+/requirements, separate Empfehlung nur für `/implement`" (potenziell zwei Phasen,
zwei Empfehlungen). Der Detail-Absatz wurde korrekt umgeschrieben – aber der kurze
Merksatz-Bullet direkt darüber im selben Abschnitt („**Zwei unabhängige Maßnahmen**"-Liste), der
dieselbe Aussage als TL;DR zusammenfasst, blieb bei der alten, jetzt widersprüchlichen
„je Task"-Formulierung stehen. Der Widerspruch existierte ausschließlich innerhalb der eigenen,
in diesem PR neu verfassten Prosa – keine externe Referenz nötig, um ihn zu finden.

**Smell:** Ein Abschnitt hat eine kurze Zusammenfassungs-Zeile (Bullet, Fettdruck-Lead-in,
Überschrift) UND einen ausführlicheren Absatz darunter, der dieselbe Regel im Detail erklärt –
wird nur der Detail-Absatz umformuliert, bleibt die Zusammenfassung unangetastet und kann die
neue Nuance widersprechen.

**Regel:** Beim Umformulieren eines Absatzes im selben Abschnitt aktiv nach einer kurzen
Zusammenfassungs-Zeile suchen, die dieselbe Aussage bereits vor der Änderung auf den Punkt
gebracht hat (typischerweise die erste Zeile/der erste Bullet des Abschnitts) – und sie
mitziehen, auch wenn sie nicht als eigenes Finding gemeldet wurde. Diese Prüfung ist unabhängig
von der Cross-Datei-Sweep-Pflicht aus #211/#176/#264: hier reicht es, den umgebenden Abschnitt in
derselben Datei noch einmal komplett zu lesen, nicht nur die geänderte Zeile.

### Eine Erzwingungs-Behauptung ist eine Tatsachenbehauptung über Code – vor dem Schreiben den Enforcer lesen (aus #319, dreimal im selben PR)

Sätze der Form „X erzwingt Y", „geprüft von X", „X blockiert das fail-closed" lesen sich wie
Prosa, sind aber **überprüfbare Aussagen über fremden Code**. In #319 standen davon drei
gleichzeitig im selben PR, jede plausibel und jede falsch:

| Behauptung | Wirklichkeit | Prüfaufwand |
|------------|--------------|-------------|
| „Prettier erzwingt die Schluss-Newline" (Skript-Header) | `.prettierignore` deckt `docs/` **und** `CLAUDE.md` – kein Gate erzwingt sie | ein Blick in `.prettierignore`, den ich in derselben Session bereits geworfen hatte |
| „pre-push-Hook und Ruleset, **beide** fail-closed" (Kern-Kurzregel) | der Hook ist lokal und mit `--no-verify` umgehbar; die kanonische Quelle sagt das zwei Abschnitte weiter selbst | ein `grep` in `git-workflow.md` |
| „Erzwungen durch … `branch-name-check.sh`" (ADR-Tabelle) | ein Claude-Code-**PreToolUse**-Hook auf den Bash-Tool-Input; greift nicht bei `git worktree add -b`, nicht außerhalb von Claude Code, in keinem Push-/CI-Gate | `grep -rl branch-name-check` → eine einzige Verdrahtung |

Das Muster ist nicht Nachlässigkeit, sondern **Plausibilität statt Prüfung**: ein Skript namens
`branch-name-check.sh` *klingt* nach einem Gate, ein Formatter *klingt* nach Normalisierung. Die
Behauptung entsteht beim Schreiben der Begründung, nicht beim Lesen des Codes. Besonders bitter
ist der erste Fall – die widerlegende Information lag bereits im eigenen Sitzungsverlauf.

Verschärfend: solche Sätze landen bevorzugt in **ADR-Begründungen** und **Kern-Kurzregeln**, also
genau dort, wo sie eine Entscheidung tragen bzw. dauerhaft geladen werden. Eine überzeichnete
Erzwingung ist dabei gefährlicher als eine fehlende: Sie verleitet dazu, die Regel für abgesichert
zu halten und die Sorgfalt zu sparen („der Hook fängt das schon").

**Smell:** Im eigenen Text steht ein Enforcer-Name neben einem starken Verb (erzwingt, blockiert,
verhindert, prüft, fail-closed) – und ich habe den genannten Enforcer in dieser Session **nicht
geöffnet**.

**Regel:** Vor dem Schreiben einer Erzwingungs-Behauptung den Enforcer öffnen und zwei Fragen
beantworten: (1) *Wo* ist er verdrahtet (`grep -rl <name>` über `*.sh`, `*.yml`, `*.json` – ein
Hook, ein Push-Gate, ein CI-Job, ein Ruleset?) und (2) *was genau* lehnt er ab (der Scope steht
meist im eigenen Header)? Trägt er die Behauptung nicht, wird sie auf das eingeschränkt, was gilt.
Und wie bei der falschen Kausalkette aus #264 gilt: Ist eine solche Behauptung einmal falsch, per
Grep nach den **Geschwister-Stellen** suchen – sie treten in Rudeln auf, weil dieselbe Annahme
mehrere Absätze getragen hat.

### Massen-Ersetzung beim Extrahieren eines Helfers trifft den Rumpf des neuen Helfers (aus #319, /refactor-Selbstfund)

Wer eine wiederholte Codefolge in einen Helfer zieht und die Aufrufstellen per Regex/`sed`
ersetzt, hat nach dem Anlegen des Helfers **eine Fundstelle mehr** als vorher: dessen eigenen
Rumpf. Er enthält die extrahierte Folge ja gerade. Die Ersetzung macht daraus einen Aufruf – der
Helfer ruft sich selbst auf:

```bash
claude_fixture_319() {
  claude_fixture_319          # war: mklines_319 "$TMP/CLAUDE.md" 20
  ...
}
```

Der Schaden ist keine Fehlermeldung, sondern eine **Endlosschleife zur Laufzeit** – und wenn der
Helfer in einem selten laufenden Zweig sitzt, fällt sie erst dort auf.

**Smell:** Nach einer Massen-Ersetzung meldet die Kontrollzählung **null** verbliebene
Vorkommen des alten Musters – obwohl der neue Helfer es per Definition enthalten muss. „Zu gut,
um zu stimmen" ist hier ein wörtlich brauchbares Kriterium.

**Regel:** Beim Extrahieren per Massen-Ersetzung entweder den Helfer **nach** der Ersetzung
anlegen, oder das Muster so ankern, dass der Funktionsrumpf ausgenommen ist, oder nach der
Ersetzung gezielt gegenprüfen: „enthält der neue Helfer noch das Original?" (`sed -n
'/^name() {/,/^}/p'`). Die reine Zählung der ersetzten Stellen genügt **nicht** – sie zählt den
Selbsttreffer als Erfolg.
