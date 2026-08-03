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
(vgl. `testing-standards.md`).

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
