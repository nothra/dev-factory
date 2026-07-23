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
