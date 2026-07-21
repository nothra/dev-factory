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
(`"postcss@<8.5.10": ">=8.5.10"`), damit spätere legitime Parent-Upgrades nicht blockiert werden,
und den Grund + GHSA + Entfern-Kriterium als Kommentar danebenschreiben. **Nachweis ist Pflicht**,
weil die Fehl-Platzierung still durchgeht: nach `pnpm install` mit `pnpm audit` **und** `pnpm why
<paket>` belegen, dass die verwundbare Version wirklich aus dem Baum ist – nicht auf die Abwesenheit
einer Fehlermeldung vertrauen. Overrides sind „sticky": Sobald die Parents die Patches selbst
mitbringen, werden sie zu No-ops und sollten entfernt werden (Follow-up-Issue #169).

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

