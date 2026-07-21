# ADR 037: `/codify`-Learnings aus dem @import-Kontext in `docs/factory/lessons/` auslagern

## Status

Accepted

## Kontext

Der bei **jeder** Session und **jedem** Pipeline-Agenten per `@import` geladene Kontext
(`CLAUDE.md` + `PROJECT-CONTEXT.md` + 5 Guidelines) umfasst **2.068 Zeilen**. Dominant: der
Abschnitt „Bekannte Stolpersteine" in `PROJECT-CONTEXT.md` mit **45 `/codify`-Learnings
(~978 Zeilen ≈ 47 % des gesamten @import-Kontexts)**. Ein Stage-3-Lauf sind ~7 sequenzielle
Agenten, die diesen Ballast je komplett neu laden — davon ist für eine konkrete Task fast
alles irrelevant (z. B. Turbopack/pdfkit #193, pnpm@11 #167, aria-modal #134).

Ursache ist eine **Governance-Lücke**: `/codify` hängt jedes Feature-Learning an den
@import-Pfad an; keines wird je ausgelagert. Das widerspricht `token-efficiency.md` §5
(„Kontext-Dateien schlank halten … jede Zeile wird dauerhaft mitbezahlt"). Das Muster
„nicht importiert, gezielt bei Bedarf gelesen" existiert bereits für `token-efficiency.md`
und `bash-gotchas.md`. Spec: `docs/specs/spec-196-import-kontext-verschlanken.md`.

## Entscheidung

1. **Neues Verzeichnis `docs/factory/lessons/`** — **nicht** `@import`-eingebunden. Es nimmt
   den **Volltext** aller Stolperstein-Learnings auf, thematisch getrennt in **7 Dateien**:

   | Datei | Thema | Zugeordnete Learnings (Herkunft) |
   |-------|-------|----------------------------------|
   | `frontend-react.md` | React/UI, client components, route-neutrale UI-Bausteine | #49, #52, #53(W1), #134, #54, #183, #188(×2) |
   | `next-auth.md` | Next.js-Framework, `proxy.ts`, NextAuth/Session, öffentliche Routen | #48(proxy), #48(JWT), #63, #164/#170 |
   | `db-drizzle.md` | Drizzle ORM, Migrationen, IDOR, Soft-Delete, Joins, guarded UPDATE, Zod-Obergrenzen | #48(Migration), #50, #49(Zod), #51(IDOR), #51(Soft-Delete), #53(K1), #55(guarded) |
   | `testing.md` | Vitest, Coverage, Guard-Tests, Zod-Meldungs-Tests | #48(vitest), #51(guard-clause), #117, #116 |
   | `build-tooling.md` | pnpm, Turbopack/Vercel-Bundling, Typecheck-Gate, gitignore-Artefakte | #67(gitignore), #137, #167, #193 |
   | `code-style.md` | Clean-Code-Muster (Naming, Kommentar-Ort) | #67(WHAT-Kommentar), #105 |
   | `factory-workflow.md` | Git/CI, Pipeline-Skills, Patch-Workflow, Branch/Label, Review-Scope, Terminologie-Sweep, kanonische Quellen, Blocker | Task002(×2), #40/42, #120, #155, #91(×2), #114(×2), #52-Import?, #145, #144, #155/158, #160, #161, #55(ADR-Drift), #185 |

   > Die exakte Zuordnung je Eintrag ist in `/implement` beim Verschieben verbindlich; die
   > Tabelle ist die Leitlinie. Jede Lesson bleibt **inhaltlich unverändert** (verlustfreies
   > Verschieben, kein Umschreiben).

2. **`PROJECT-CONTEXT.md` behält (im @import) statt des Volltexts:**
   - eine kurze Einleitung + Verweis auf `docs/factory/lessons/`,
   - einen **schlanken Index**: pro Learning **eine Zeile** (Titel + Herkunfts-Issue),
     gruppiert nach den 7 Dateien, **je Gruppe/Zeile mit einem „Laden bei"-Trigger** (Skill +
     Situation) – das „wann reinschauen" aus der Spec. Der Trigger ist das Auswahlkriterium für
     das bedarfsgesteuerte Laden: Ein Skill öffnet nur die Lessons, deren Trigger zum laufenden
     Skill **und** zur Domäne der Task passt (nicht alle `lessons/` vorsorglich). Homogene Domänen-
     Dateien tragen den Trigger am Gruppen-Header; `factory-workflow.md` (gemischte Auslöser) je Zeile,
   - **4 Kern-Kurzregeln** als Einzeiler (die praktisch jede Feature-Task betreffen), jeweils
     mit Verweis auf ihre Lesson als kanonische Quelle:
     1. Drizzle `.returning()` bei UPDATE/DELETE → Rückgabetyp `T | undefined` (nicht `T`).
     2. IDOR: DELETE/UPDATE auf Zeilen-Tabellen führen den **Parent-Key** im `WHERE` mit.
     3. Soft-Delete: nach jedem Laden by ID **`active` prüfen**, bevor geschrieben wird.
     4. Zod: Felder auf `int4`/`text` bekommen eine **Obergrenze** (`.max`/`.refine`).

3. **`/codify`-Skill (`.claude/commands/codify.md`) wird angepasst:** neue Learnings werden in
   die thematisch passende `docs/factory/lessons/<thema>.md` (Volltext) **plus** eine
   Index-Zeile **mit „Laden bei"-Trigger** (Skill + Situation) in `PROJECT-CONTEXT.md`
   geschrieben — **nicht mehr** in den @import-Volltext. Da `.claude/**` agent-hard-denied ist,
   erfolgt die Änderung über den **Patch-Workflow** (`tasks/patch-196.diff`, Human-Apply).

## Alternativen

### Option A: Volltext in `lessons/` auslagern, Index + 4 Kernregeln inline (gewählt)
Vorteile: @import schrumpft drastisch (~978 → ~60–80 Zeilen Index/Kernregeln);
verlustfrei (AC3); gezieltes Nachlesen je Domäne; folgt dem etablierten
„nicht-importiert"-Muster; heilt die Governance-Lücke an der Quelle (`/codify`).
Nachteile: Agent muss die passende Lesson-Datei aktiv öffnen; Index-Pflege bei jedem
`/codify` (durch Skill-Anpassung abgedeckt).

### Option B: Alten Volltext behalten, nur konsolidieren/kürzen
Vorteile: kein Struktur-Umbau; keine `.claude/**`-Patch-Runde.
Nachteile: bleibt im @import-Pfad → das Grundproblem (Dauerkosten pro Agent) bleibt;
Governance-Lücke ungeschlossen — wächst mit dem nächsten `/codify` weiter. Verworfen.

### Option C: Eine einzige `lessons.md` statt thematischer Dateien
Vorteile: einfachster Umbau; ein Verweis.
Nachteile: eine 978-Zeilen-Datei muss ganz gelesen werden, sobald irgendein Learning
gebraucht wird — verfehlt das Ziel „kürzester Weg zur relevanten Information". Verworfen
zugunsten der thematischen Trennung.

## Begründung

Option A ist die einzige, die AC1 (Volltext raus) **und** AC5 (`/codify`-Governance) erfüllt
und dabei AC3 (kein Verlust) wahrt. Die thematische Trennung (statt einer Sammeldatei)
maximiert den Nutzen des gezielten Nachlesens: eine DB-Task lädt `db-drizzle.md`, eine
UI-Task `frontend-react.md`. Die 4 inline verbleibenden Kernregeln sind bewusst auf
Data-Layer/Validierung beschränkt — die Klasse Regeln, die faktisch **jede** Feature-Task
berührt (jede Server Action validiert per Zod und schreibt via Drizzle).

## Konsequenzen

- Neuer Dauer-@import-Kontext sinkt von 2.068 auf ~1.150 Zeilen (die ~978 Volltext-Zeilen
  weichen ~60–80 Zeilen Index + Kernregeln). Exakte Zahl wird im PR dokumentiert (AC2).
- **Neue Konvention:** `/codify`-Learnings leben in `docs/factory/lessons/` + Index, nicht im
  @import-Volltext. Diese ADR ist die kanonische Quelle der Konvention.
- Die kanonische Quelle je Regel verschiebt sich von „Bekannte Stolpersteine" nach
  `lessons/<thema>.md`; bestehende Cross-Verweise (`[[…]]`, „siehe #NN", ADR-Verweise)
  müssen beim Verschieben nachgezogen werden (AC6).
- Guidelines-Dateien und ihre `@import`-Einbindung bleiben unverändert.
- Kein Produktverhalten betroffen (reine Kontext-/Doku-Umschichtung).
