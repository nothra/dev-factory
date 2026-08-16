# Lessons: Build & Tooling

> Ausgelagerte `/codify`-Learnings (Volltext) zu **pnpm, Turbopack/Vercel-Bundling, Typecheck-Gate, gitignore-Artefakte**.
> **Nicht** `@import`-geladen (ADR-037) – bei Bedarf gezielt lesen. Kanonische Quelle je
> Regel ist der jeweilige Eintrag hier; im @import-Pfad (`PROJECT-CONTEXT.md`) steht nur eine Index-Zeile.
> Neue Learnings kommen hierher (nicht in den @import-Pfad) – siehe `/codify` + ADR-037.

### Debug-/Lint-Artefakte nicht durch .gitignore gedeckt (aus #67)

Im Lint-Debugging entstanden `lint-out.tmp.txt` und `scripts/lint-debug.tmp.sh` im
Arbeitsbaum. `.gitignore` deckte `*.log` und `*-debug.log*` ab, aber keine `.tmp`-Muster.
Der Review musste explizit auf das Entfernungserfordernis hinweisen – ohne diesen Fund
wären die Dateien mit `git add .` ins Repo gewandert.

**Regel:** `.gitignore` enthält jetzt `*.tmp.txt` und `*.tmp.sh`. Neue Debugging-/Lint-
Hilfsskripte, die nicht eingecheckt werden sollen, immer nach einem dieser Muster benennen
(oder das Muster in `.gitignore` ergänzen), bevor sie erstellt werden – nicht nachträglich
aufräumen.

### Lint/Vitest fangen keine Typfehler – Gate-Lücke bis zum manuellen `pnpm build` (aus #137)

Review-Runde 1 fand einen Build-Break (fehlender `import type { CatalogCategory }`), den
`pnpm lint` und `pnpm test` beide grün durchließen: Vitest transpiliert über esbuild
(Typen werden vor der Ausführung gestrippt, kein Type-Check) und das ESLint-Setup hier
ist nicht typed-aware. Nur `tsc`/`next build` sieht diese Fehlerklasse – bis dahin blieb
der Fund nur durch einen manuellen `pnpm build` vor dem Merge sichtbar, kein
automatisiertes Gate deckte ihn ab.

**Regel:** `package.json` hat jetzt ein `"typecheck": "tsc --noEmit"`-Script, das
`scripts/checks/pre-push.sh` als eigenen Check ausführt (override via
`FACTORY_TYPECHECK_COMMAND`) – fail-closed: schlägt der Typecheck fehl, wird der Push
blockiert, keine stille Degradation. Beim Einführen eines neuen Gate-Checks immer sofort
`pnpm typecheck` (bzw. den neuen Befehl) gegen den **aktuellen** Baum laufen lassen, nicht
nur gegen den eigenen Diff – ein vorbestehender Verstoß anderswo im Repo (hier ein
stale `@ts-expect-error` in `db/veranstaltung.test.ts`, unabhängig von #137) blockiert
sonst sofort jeden Push auf jedem Branch, sobald das Gate scharf ist.

### pnpm@11: `overrides`/Settings gehören in `pnpm-workspace.yaml`, nicht ins `package.json`-`pnpm`-Feld (aus #167)

Zum Schließen zweier transitiv gepinnter Dependabot-Alerts (postcss `<8.5.10`, esbuild
`<0.25.0` – beide von `next`/`drizzle-kit` gepinnt, von `pnpm update` nicht wegräumbar) war ein
`pnpm.overrides`-Eintrag nötig. Der Reflex, ihn wie in pnpm ≤10 unter `"pnpm": { "overrides": … }`
in die **`package.json`** zu schreiben, führt in pnpm@11 zu einem **stillen No-op**: pnpm gibt nur
`[WARN] The "pnpm" field in package.json is no longer read by pnpm … The following keys were
ignored: "pnpm.overrides"` aus und **ignoriert die Overrides** – der Lockfile bleibt verwundbar,
obwohl „alles committed" aussieht. Das Repo hat bereits eine `pnpm-workspace.yaml` (für
`allowBuilds`); dort – und nur dort – liest pnpm@11 diese Settings.

**Regel:** In diesem Projekt (pnpm@11) gehören `overrides` und andere pnpm-Settings in
**`pnpm-workspace.yaml`** (Top-Level-Key `overrides:`), nicht in ein `pnpm`-Feld der
`package.json`. Bei Security-Overrides die **konditionale** Selektor-Form nutzen
(`"postcss@<8.5.23": "^8.5.23"`), damit spätere legitime Parent-Upgrades nicht blockiert werden,
und den Grund + GHSA + Entfern-Kriterium als Kommentar danebenschreiben. **Nachweis ist Pflicht**,
weil die Fehl-Platzierung still durchgeht: nach `pnpm install` die im **Lockfile aufgelöste**
Version belegen (`pnpm why <paket>` bzw. Lockfile-Prüfung) – ergänzend die Dependabot-API, aber
**nicht** `pnpm audit`: das ist in dieser Umgebung wegen des Gzip-Decoding-Bugs nicht belastbar
(eigener Eintrag unten, #228). Nicht auf die Abwesenheit einer Fehlermeldung vertrauen.

**Ziel-Range immer als Caret innerhalb derselben Major-Linie** (`^1.1.18`, nicht `>=1.1.18`, aus
#291): Ein offenes `>=` lässt pnpm auf die neueste Major springen und schiebt damit einen
Major-Bump in einen Baum, der ihn nicht angefordert hat – `">=2.1.4"` hob die von `minimatch@3`
erwartete `brace-expansion@1.1.15` über die Major-Grenze auf 2.x, und der Alt-Eintrag
`"uuid@<11.1.1": ">=11.1.1"` löst bis heute auf **14.0.1** auf, obwohl `exceljs` `^8.3.2`
deklariert. Trägt ein Paket Advisories in zwei Major-Linien, brauchen die Selektoren **disjunkte**
Grenzen (`brace-expansion@<1.1.18` **und** `brace-expansion@>=2.0.0 <2.1.4`) – ohne die untere
Schranke greift der 2er-Selektor auch auf 1.1.x.

**Overrides sind „sticky", aber nicht automatisch No-ops, sobald die Parents nachziehen** – die
Vermutung ist zu messen, nicht anzunehmen (aus #291, das den Follow-up #169 erledigt): `esbuild@<0.25.0`
sah wie ein No-op aus, ist aber keiner (ohne den Eintrag kommt `esbuild@0.18.20` zurück, durch
Entfernen + Neuinstallation belegt); `nanoid@<3.3.17` dagegen ist einer, weil sein einziger
Konsument `postcss@8.5.26` selbst `^3.3.17` deklariert. Methode für beide Fälle: Eintrag entfernen,
neu auflösen, aufgelöste Version prüfen. Und das Entfern-Kriterium nur dort in den Kommentar
schreiben, wo es erreichbar ist – `next` pinnt `postcss` **exakt** auf `8.4.31`, dieser Override
wird also dauerhaft gebraucht.

### Turbopack/Vercel: Node-Libs mit Laufzeit-`fs.readFileSync(__dirname + …)` externalisieren (aus #193)

Der PDF-Abschlussbericht warf auf Vercel HTTP 500 (Safari: leere Seite), während Excel und der
lokale vitest-Lauf grün blieben. Ursache: `pdfmake` → `pdfkit` lädt seine Standard-Font-Metriken
zur **Laufzeit** über `fs.readFileSync(__dirname + "/data/Helvetica.afm")`. Bündelt Turbopack
pdfkit in den Route-Chunk (Default-Verhalten für node_modules ohne Ausnahme), ersetzt es
`__dirname` durch den Build-Sentinel `/ROOT/…` – einen absoluten Pfad, der zur Laufzeit **nicht
existiert** → ENOENT beim ersten Font-Zugriff → 500. vitest lädt die Renderer-Quelle direkt
(echtes `__dirname`), darum grün; der Fehler existiert **nur** im gebündelten Serverless-Output.
Excel (`exceljs`) funktioniert, weil es keine `__dirname`-basierten Datei-Reads zur Laufzeit macht.

Zwei tückische Punkte: (1) Die naheliegende Hypothese „die `.afm`-Dateien fehlen im File-Tracing"
war **falsch** – der `nft.json`-Trace **enthielt** sie bereits; das Problem war der **falsche
Pfad** (`/ROOT/…`) im gebündelten Code, nicht eine fehlende Datei. `outputFileTracingIncludes`
allein hätte den Bug daher **nicht** behoben (liefert die Datei aus, korrigiert aber nicht den
Pfad). (2) Der Fehler ist ein reiner **Bundling-Defekt**: kein Quell-Unit-Test unterscheidet
Vorher/Nachher, weil die Quelle unverändert grün ist.

**Regel:** Ein Node-Paket, das Datendateien zur **Laufzeit** über `fs.readFileSync(__dirname + …)`
(oder gleichwertig) lädt – Font-Metriken (pdfkit), Templates, WASM, ICU-/Locale-Daten –, gehört in
`next.config.ts` unter **`serverExternalPackages`**. Dann bleibt es in `node_modules` mit korrektem
Laufzeit-`__dirname`, und das File-Tracing (@vercel/nft) zieht die Datendateien an ihren echten
Pfad. **Verifikation immer am gebauten `.next/server`-Chunk, nicht nur an vitest** (fail-closed):
`grep -o '/ROOT/node_modules[^"]*' .next/server/chunks/*.js` muss nach dem Fix **0** tote
Sentinel-Pfade liefern, und die Paket-JS müssen im Route-`nft.json` erscheinen (extern). Ein
vitest-Config-Guard (`next.config.test.ts`: `serverExternalPackages` enthält das Paket) hält die
Externalisierung fest; das echte Laufzeitverhalten deckt `/post-merge-verify` ab. Direkte Anwendung
der #164-Lehre: nicht der gemeldeten Ursache glauben, sondern am realen Artefakt (Build-Output,
Response-Header) messen.

### Verschachtelte alte `@types/node`-Kopie kollidiert mit dem generischen `Buffer`-Typ bei TS≥5.7 (aus #189)

`berichtXlsx.test.ts` rief erstmals `workbook.xlsx.load(buffer)` auf (Zurücklesen eines
gerenderten `exceljs`-Reports zur Zellwert-Prüfung). `pnpm typecheck` schlug fehl:
„Argument of type 'Buffer\<ArrayBufferLike\>' is not assignable to parameter of type 'Buffer'" –
obwohl `buffer` exakt der `Buffer`-Rückgabetyp der eigenen `berichtXlsx()`-Funktion war. Ursache:
`exceljs` hat `fast-csv` (eigene Dependency) im Baum, welches wiederum eine **alte,
verschachtelte** `@types/node@14`-Kopie mitbringt (`declare class Buffer extends Uint8Array {}`,
nicht generisch). Ab TS 5.7 lädt `@types/node@20`s eigenes `buffer.buffer.d.ts` einen
**generischen** `Buffer<TArrayBuffer extends ArrayBufferLike = ArrayBufferLike>`. `skipLibCheck:
true` lässt die inkonsistente Merge dieser zwei Deklarationen für den globalen `Buffer`-Typ
durchgehen (keine Fehlermeldung an der Quelle), aber an der **Aufrufstelle** ist der resultierende
Typ nicht mehr sauber zuweisbar – ein reiner Typsystem-Artefakt, keine Laufzeit-Inkompatibilität
(dieselbe Node-`Buffer`-Klasse). Der naheliegende Fix `buffer as unknown as Buffer` griff **nicht**
(der eigene `Buffer`-Bezeichner ist ja Teil derselben kaputten Merge); erst der Umweg über die
Funktionssignatur selbst löste es zuverlässig.

**Smell:** „`tsc` meldet `Buffer<ArrayBufferLike>` nicht zuweisbar zu `Buffer`, obwohl beide Seiten
offensichtlich derselbe Wert sind, und ein einfacher `as Buffer`-Cast ändert nichts?" → Verdacht auf
verschachtelte, ältere `@types/node`-Kopie einer transitiven Dependency (`pnpm ls --depth=Infinity
@types/node` bzw. `find node_modules/.pnpm -maxdepth 1 -iname "@types+node@*"` zeigt mehrere
Versionen).

**Regel:** Bei genau diesem Fehlerbild **nicht** `as unknown as Buffer` versuchen (trifft dieselbe
kaputte globale Merge), sondern über die **Ziel-Funktionssignatur selbst** casten:
`buffer as unknown as Parameters<typeof workbook.xlsx.load>[0]` – das ist immer strukturell
korrekt, unabhängig davon, welche Gestalt der ambiente `Buffer`-Typ gerade hat. Kein
Produktionscode-Fix nötig (Laufzeitverhalten korrekt, reines Typsystem-Artefakt einer fremden
Dependency-Kette); den Grund als Kommentar direkt an der Cast-Stelle festhalten, damit der nächste
Leser nicht erneut recherchiert.

### `pnpm audit` scheitert in dieser Sandbox an einem Gzip-Decoding-Bug – manueller `curl`-Workaround liefert echte Advisory-Daten (aus #228, /security-review-Selbstfund)

`pnpm audit` bricht hier reproduzierbar mit `ERR_PNPM_AUDIT_BAD_RESPONSE` ab
(„returned invalid JSON … Unexpected token"). Ursache: Der Registry-Endpoint
(`https://registry.npmjs.org/-/npm/v1/security/advisories/bulk`) liefert den Body **gzip-
komprimiert, aber ohne `Content-Encoding`-Header** – pnpms HTTP-Client dekomprimiert deshalb
nicht und versucht, die rohen Gzip-Bytes als JSON zu parsen. `spec-228` sah dafür bereits ein
Ersatzkriterium vor (Lockfile-Check statt `pnpm audit`) – das reicht als Nachweis, ist aber
schwächer als eine echte Advisory-Abfrage. Auch `curl --compressed` scheitert bei **kleinen**
Antworten (z. B. `{}`), weil der Server dort tatsächlich unkomprimiertes JSON sendet und
`--compressed` nichts falsch macht – nur bei **größeren**, wirklich gzip-komprimierten
Antworten (viele Advisories) tritt derselbe fehlende-Header-Bug auch gegen `curl` auf.

**Smell:** „`pnpm audit` liefert `ERR_PNPM_AUDIT_BAD_RESPONSE` – bevor ich das Lockfile-
Ersatzkriterium als einzigen Nachweis akzeptiere: gibt es einen Weg, echte Advisory-Daten zu
bekommen?"

**Regel:** Den Registry-Endpoint direkt abfragen und **bedingungslos manuell entpacken**
(`gunzip`), unabhängig davon, ob `curl --compressed` scheinbar schon ein Ergebnis liefert:
```bash
curl -s -X POST https://registry.npmjs.org/-/npm/v1/security/advisories/bulk \
  -H "Content-Type: application/json" \
  -d '{"<paket>":["<version>"]}' -o /tmp/audit.bin
file /tmp/audit.bin   # "gzip compressed data" → gunzip nötig; "JSON data" → direkt lesbar
gunzip -c /tmp/audit.bin 2>/dev/null || cat /tmp/audit.bin
```
`{}` heißt **0 Advisories** für exakt diese Version – ein stärkerer Nachweis als das
Lockfile-Ersatzkriterium und über den einzelnen Task hinaus für jeden `/security-review`
nutzbar, der eine Dependency-Version gegen bekannte CVEs verifizieren muss.

### `pnpm audit` zeigt bei Paketen mit mehreren parallel gepflegten Major-Linien nur eine Range-Gruppe – Treffer gegen die volle GHSA-Liste verifizieren (aus #231, /security-review-Selbstfund)

Anders als in #228 lief `pnpm audit` hier durch (kein Gzip-Fehler) und meldete 2 „High"-Findings
für `brace-expansion` mit „Vulnerable versions >=4.0.0 <5.0.8/5.0.9" – obwohl `pnpm why
brace-expansion` klar `1.1.18` als aufgelöste Version zeigte. Ursache: `brace-expansion`
pflegt mehrere Major-Linien parallel (`1.x`/`2.x`/`3.x`/`4.x`-`5.x`, je mit eigenem
`maintenance-vN`-Dist-Tag), und **beide** gemeldeten GHSAs (GHSA-mh99-v99m-4gvg,
GHSA-rgw5-rvv9-x895) haben in Wahrheit **vier** Vulnerable-Range-Einträge (einen je
Major-Linie) – `pnpm audit`s Terminal-Ausgabe zeigte aber nur die `4.x`/`5.x`-Gruppe, nicht die
für die aufgelöste `1.x`-Linie zutreffende. Erst der Abgleich gegen die volle
GHSA-Advisory-Liste (`curl -s https://api.github.com/advisories/<GHSA-ID>` → Feld
`vulnerabilities[]`, alle Einträge, nicht nur den ersten) zeigte: `1.1.18` ist für **beide**
CVEs bereits gepatcht (Patch-Grenzen `1.1.17` bzw. `1.1.18`) – ein reines
Anzeige-Artefakt, keine echte Schwachstelle.

**Smell:** „`pnpm audit` meldet eine Vulnerable-Range, die zur per `pnpm why <paket>`
aufgelösten Version nicht passt (Major-Sprung zwischen gemeldeter Range und Ist-Version)?" →
Verdacht auf ein Paket mit mehreren parallel gepflegten Major-Linien; die Terminal-Ausgabe
zeigt dann ggf. nur eine von mehreren Range-Gruppen.

**Regel:** Bei jedem `pnpm audit`-Finding **zuerst** `pnpm why <paket>` gegen die gemeldete
Vulnerable-Range abgleichen. Liegt die aufgelöste Version außerhalb der in `pnpm audit`
gezeigten Range-Gruppe (z. B. andere Major-Linie), nicht vorschnell „nicht betroffen"
annehmen, sondern die **volle** GHSA-Advisory-Liste abfragen (`curl -s
https://api.github.com/advisories/<GHSA-ID>`, Feld `vulnerabilities[]` komplett auswerten,
nicht nur den ersten Eintrag) und die aufgelöste Version gegen **jeden** dort gelisteten
`vulnerable_version_range`/`first_patched_version` prüfen – erst danach als False Positive
oder echtes Finding einordnen.

