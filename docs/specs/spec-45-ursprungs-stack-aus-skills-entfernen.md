# Spec: Ursprungs-Stack aus Skills und Agent-Personas entfernen (Rest von AK-K1)

## Kontext

AK-K1 aus spec-426 (nothra/tch-gastro-services#432) sollte die ausgelieferten Anweisungstexte der
Factory von Details des Ursprungs-Projekts befreien. Die damalige Suchliste (`pnpm`, `Neon`, `Vercel`,
`db:seed`, `Drizzle`) war zu kurz. In Dateien der Seite `factory` stehen deshalb noch Stack-Details
des Ursprungs-Projekts: Playwright, Next.js-Routen, Drizzle-Transaktionen, Vitest/esbuild,
projektspezifische Lesson-Themen.

Zwei dieser Stellen sind für jeden anderen Konsumenten **falsch, nicht nur unpassend**:
`/implement` und `/review` behaupten, ein Drift-Check auf `docs/routes.md` blockiere den Push. Das
zugehörige `routes-doc-check.sh` ist laut Factory-ADR-063 D3 projekteigen und existiert in der
Factory nicht. Ein Agent im Konsumenten folgt damit einer Regel für ein Gate, das es nicht gibt.

Zusätzlich verletzt der Herkunftsbegriff `Veranstaltung` in zwei Lessons die Regel C1 aus
`PROJECT-CONTEXT.md` → „Konventionen". Der C1-Guard in `scripts/project/tests/run-tests.sh` findet
ihn nicht, weil er nur ganze Wörter vergleicht (`VeranstaltungMetaForm.tsx`,
`deleteVeranstaltungAction`).

Der Zeitpunkt ist vorgegeben: **vor der Reintegration** des Ursprungs-Repos
(nothra/tch-gastro-services#428). Dort gingen die entfernten projektspezifischen Regeln sonst beim
ersten Factory-Update still verloren.

## Scope

**Inbegriffen:**

1. **Fundstellen generisch formulieren.** Projekt-Details ersetzt ein Verweis auf
   `PROJECT-CONTEXT.md` → „Lokale Umgebung & Oberflächentests" (Factory-ADR-063 D3) bzw. auf die
   projekteigenen Regeln in `CLAUDE.md`/`PROJECT-CONTEXT.md` des Konsumenten:
   - `.claude/commands/implement.md`: Oberflächentests (Playwright, `e2e/*.spec.ts`,
     `webServer`-Config) und die Routen-Doku-Regel (`app/**/page.tsx`, `docs/routes.md`,
     „der Drift-Check blockiert sonst den Push")
   - `.claude/commands/review.md`: Routen-Doku-Prüfpunkt in Runde 3
   - `.claude/commands/codify.md`: die Themenliste `frontend-react`, `next-auth`, `db-drizzle`
   - `docs/factory/agents/review-agent.md`: `runAtomic`, `db/atomic.ts`, `db.transaction()`,
     Lesson `db-drizzle.md`. Der generische Kern bleibt: Verhält sich neuer Code in der
     Zielumgebung wie im lokalen/CI-Testpfad?
   - `docs/factory/agents/coding-agent.md`: Playwright-E2E
   - `docs/factory/guidelines/testing-standards.md`: Erwähnung „TypeScript-/Vitest-spezifisch"
   - `scripts/checks/pre-push.sh`: Kommentare zu Check 2 (Typecheck) und Check 3 (Format), die
     Vitest, esbuild, ESLint, `tsc`/`next build`, Prettier und `pnpm build`/`pnpm format` nennen.
     Die qualifizierten Herkunftsverweise (`nothra/tch-gastro-services#<nr>`) dürfen bleiben.
   - `docs/factory/gitignore.factory`: das Muster `*.tmp.spec.tsx`
2. **Herkunftsbegriff aus den Lessons entfernen:** `docs/factory/lessons/testing.md` (Zeile mit
   `VeranstaltungMetaForm.tsx`) und `docs/factory/lessons/code-style.md` (Zeile mit
   `deleteVeranstaltungAction`) neutral formulieren, ohne Aussage und Lehre der Lesson zu ändern.
3. **C1-Guard auf Komposita erweitern (Entscheidung Q2):** Die langen Begriffe `Veranstaltung`,
   `Montagsrunde`, `Thekenwart`, `Heuchelheim`, `tch-gastro` werden auch als Teil eines Worts
   erkannt. Die kurzen Begriffe `TCH`, `Neon`, `Vercel` bleiben Ganzwort-Treffer.
4. **Neuer Stack-Begriff-Guard über die Anweisungstexte (Entscheidung Q1):**
   - **Geprüfte Dateien:** alle getrackten Dateien unter `.claude/commands/`,
     `docs/factory/agents/`, `docs/factory/guidelines/`, dazu `docs/factory/gitignore.factory` und
     `scripts/checks/pre-push.sh`.
   - **Begriffe (Groß-/Kleinschreibung egal):** `pnpm`, `db:seed`, `drizzle`, `playwright`,
     `docs/routes.md`, `db.transaction`, `runAtomic`, `vitest`, `esbuild`, `page.tsx`,
     `next-auth`, `frontend-react`.
   - **Ort:** die Projekt-Suite `scripts/project/tests/run-tests.sh` neben dem C1-Guard. Die
     Begriffsliste ist Wissen über das Ursprungs-Projekt und gehört nicht in die ausgelieferte
     Suite (Factory-ADR-064 D6).
5. **Übergabe ans Ursprungs-Repo (Entscheidung Q3):** ein Checklisten-Kommentar an
   nothra/tch-gastro-services#428. Er nennt die Regeln, die mit diesem PR aus den Factory-Dateien
   verschwinden und die das Ursprungs-Repo in seine projekteigenen Dateien übernehmen muss, damit
   sein Verhalten gleich bleibt.

**Nicht inbegriffen:**

- Die Übernahme der Regeln in `nothra/tch-gastro-services` selbst. Sie geschieht dort mit
  nothra/tch-gastro-services#428.
- ADRs, Lessons (außer den zwei C1-Treffern), `kleinfunde.md`, `OPERATING.md`, die ausgelieferte
  Suite `scripts/checks/tests/` mit ihren Fixtures und sonstige Skripte. Dort stehen die Begriffe als
  Historie, Begründung („kein pnpm-Default") oder Testdaten. Der neue Guard prüft sie nicht.
- Weitere Begriffe oder Werkzeugnamen, die die Liste oben nicht nennt (z. B. `.env.local`,
  `Prettier`, `tsc` als Guard-Begriffe). Die Kommentare in `pre-push.sh` werden zwar generisch
  formuliert, der Guard prüft aber nur die Liste aus Scope 4.
- Inhaltliche Änderungen an Gates: `pre-push.sh` ändert nur Kommentare, kein Verhalten.
- Eine neue Fassung des Abschnitts „Lokale Umgebung & Oberflächentests" in `PROJECT-CONTEXT.md`
  dieses Repos. Das Factory-Repo hat keine Oberfläche; Verweise zeigen auf den Abschnitt im
  Konsumenten.

## Begriffe

- **Anweisungstexte:** die Dateien aus Scope 4 („Geprüfte Dateien"). Ein Agent liest sie als
  Handlungsanweisung, deshalb gelten Aussagen darin für jeden Konsumenten.
- **Stack-Begriff:** ein Eintrag aus der Begriffsliste in Scope 4.
- **Langer / kurzer C1-Begriff:** siehe Scope 3.

## Akzeptanzkriterien

- [ ] **AK1 – Kein Gate-Versprechen ohne Gate:** GIVEN die geänderten Dateien
  `.claude/commands/implement.md` und `.claude/commands/review.md`, WHEN man sie nach `docs/routes.md`,
  `page.tsx`, `route.ts` und nach einer Aussage über einen Routen-Drift-Check durchsucht, THEN gibt
  es keinen Treffer. Eine projekteigene Zusatzregel ist nur noch als Verweis auf die projekteigenen
  Regeln des Konsumenten formuliert, ohne ein konkretes Gate zu nennen.
- [ ] **AK2 – Oberflächentests generisch:** GIVEN `.claude/commands/implement.md` und
  `docs/factory/agents/coding-agent.md`, WHEN man sie liest, THEN beschreiben sie Oberflächentests
  ohne Werkzeug-, Pfad- oder Config-Namen eines bestimmten Stacks. Für Werkzeug, Specs-Ort und Start
  des Dev-Servers verweisen sie auf `PROJECT-CONTEXT.md` → „Lokale Umgebung & Oberflächentests". Die
  bisherigen Pflichten bleiben inhaltlich erhalten: automatisiert je AK, interaktiv durchklicken,
  Stage-3-Regel, nicht in den pre-push-Gates.
- [ ] **AK3 – Review-Agent generisch:** GIVEN `docs/factory/agents/review-agent.md`, WHEN man den
  Prüfpunkt zur Treiber-/Infrastruktur-Kompatibilität liest, THEN fragt er weiter, ob sich neuer Code
  in der Zielumgebung wie im lokalen/CI-Testpfad verhält, und verweist für eine projektweite
  Atomaritäts-Klammer auf die projekteigenen Regeln. `runAtomic`, `db/atomic.ts`, `db.transaction()`
  und `db-drizzle.md` kommen nicht mehr vor.
- [ ] **AK4 – Codify-Themenliste:** GIVEN `.claude/commands/codify.md`, WHEN man die Regel zur
  Ablage einer Lesson liest, THEN nennt sie nur die Factory-Themen (`testing`, `build-tooling`,
  `code-style`, `factory-workflow`). Für Projekt-Themen verweist sie auf den Index „Projekt-Lessons"
  in `PROJECT-CONTEXT.md`; `frontend-react`, `next-auth` und `db-drizzle` kommen nicht mehr vor.
- [ ] **AK5 – pre-push.sh nur Kommentare:** GIVEN `scripts/checks/pre-push.sh`, WHEN man den Diff
  gegen `origin/main` betrachtet, THEN ändern sich ausschließlich Kommentarzeilen. Die Kommentare zu
  Check 2 und Check 3 nennen kein Werkzeug des Ursprungs-Stacks mehr (Vitest, esbuild, ESLint,
  `tsc`, `next build`, Prettier, `pnpm …`). Die ausgelieferte Suite bleibt grün.
- [ ] **AK6 – gitignore.factory:** GIVEN `docs/factory/gitignore.factory`, WHEN man es liest, THEN
  fehlt das Muster `*.tmp.spec.tsx`. Die daraus zusammengesetzte `.gitignore` dieses Repos enthält es
  ebenfalls nicht mehr, und die Guards zur Zusammensetzung bleiben grün.
- [ ] **AK7 – Lessons ohne Herkunftsbegriff:** GIVEN `docs/factory/lessons/testing.md` und
  `docs/factory/lessons/code-style.md`, WHEN man sie nach den langen C1-Begriffen durchsucht (auch als
  Wortteil), THEN gibt es keinen Treffer, und Aussage und Lehre der beiden Absätze sind unverändert.
- [ ] **AK8 – C1 erkennt Komposita:** GIVEN der C1-Guard, WHEN er eine Zeile mit
  `VeranstaltungMetaForm.tsx` bzw. `deleteVeranstaltungAction` prüft, THEN meldet er einen Treffer.
  Je langem C1-Begriff gibt es einen Negativtest mit einem Kompositum, der rot macht.
- [ ] **AK9 – C1 ohne Fehlalarm bei kurzen Begriffen:** GIVEN der erweiterte C1-Guard, WHEN er
  Zeilen mit `match`, `switch`, `watch` oder `neonatal` prüft, THEN meldet er keinen Treffer. Ein
  ganzes Wort `TCH`, `Neon` oder `Vercel` meldet er weiterhin.
- [ ] **AK10 – C1 behält Herkunftsverweise und Ausnahmen:** GIVEN ein qualifizierter Verweis
  `nothra/tch-gastro-services#<nr>` oder eine der vier erlaubten Stellen aus `PROJECT-CONTEXT.md` →
  „Konventionen", WHEN der erweiterte C1-Guard läuft, THEN ist das kein Treffer (Verhalten wie bisher).
- [ ] **AK11 – C1 grün auf dem Repo:** GIVEN der fertige Branch, WHEN die Projekt-Suite läuft, THEN
  ist der erweiterte C1-Guard grün, und seine fail-closed-Prüfung (liest wirklich die getrackten
  Dateien) gilt weiter.
- [ ] **AK12 – Stack-Guard findet jeden Begriff:** GIVEN der neue Stack-Begriff-Guard, WHEN je
  Stack-Begriff eine Zeile in einer geprüften Datei steht (in einer Wegwerf-Kopie, nicht im echten
  Baum), THEN ist der Guard rot und nennt Datei und Zeile. Groß-/Kleinschreibung spielt keine Rolle
  (`Playwright` und `playwright`, `Drizzle` und `drizzle`).
- [ ] **AK13 – Stack-Guard prüft nur die Anweisungstexte:** GIVEN ein Stack-Begriff in einer Datei
  außerhalb der geprüften Dateien (z. B. einer ADR oder einer Lesson), WHEN der Guard läuft, THEN ist
  das kein Treffer.
- [ ] **AK14 – Stack-Guard fail-closed:** GIVEN der Guard, WHEN er keine einzige geprüfte Datei
  findet (z. B. falsche Wurzel), THEN ist er rot statt still grün.
- [ ] **AK15 – Stack-Guard grün auf dem Repo:** GIVEN der fertige Branch, WHEN die Projekt-Suite
  läuft, THEN ist der Stack-Begriff-Guard grün.
- [ ] **AK16 – Übergabe-Kommentar:** GIVEN der PR vor dem Merge, WHEN man
  nothra/tch-gastro-services#428 öffnet, THEN steht dort ein Checklisten-Kommentar. Er nennt mindestens
  die Routen-Doku-Regel (inkl. Drift-Check `routes-doc-check.sh`), die `runAtomic`-Prüfung im Review,
  die Oberflächentest-Details (Playwright, `e2e/*.spec.ts`, `webServer`) und das Ignore-Muster
  `*.tmp.spec.tsx`, jeweils mit dem Ziel `CLAUDE.md`, `PROJECT-CONTEXT.md` bzw. `.gitignore.project`.
  Der PR-Body verlinkt den Kommentar.
- [ ] **AK17 – Ownership:** GIVEN der fertige PR, WHEN `ownership-check.sh` läuft, THEN ist er grün.
  Diese Spec ist über `docs/specs/**` bereits erfasst. Jede weitere neue getrackte Datei bekommt eine
  Zeile in `OWNERSHIP.md`.

## Fehlerszenarien

- [ ] Eine geprüfte Datei ist nicht lesbar oder die Liste der geprüften Dateien ist leer: Der Guard
  ist rot (AK14), nicht grün.
- [ ] Die Umformulierung in `implement.md`/`coding-agent.md` streicht eine Pflicht mit (z. B. die
  Stage-3-Regel „nicht still überspringen"): AK2 verlangt, dass alle bisherigen Pflichten erhalten
  bleiben. `/review` prüft das gegen den alten Wortlaut.
- [ ] Ein bestehender Guard der ausgelieferten Suite verankert sich am bisherigen Wortlaut einer
  geänderten Stelle (z. B. Abschnitt „Oberflächentests" oder Check-Kommentare in `pre-push.sh`): Er
  wird mit angepasst, nicht abgeschwächt. Die ausgelieferte Suite bleibt grün.
- [ ] Der Kommentar an nothra/tch-gastro-services#428 fehlt beim Merge: AK16 ist offen, die Task ist
  nicht fertig.

## Entscheidungen

- **Q1 – Guard-Umfang:** nur Anweisungstexte (Skills, Agent-Personas, Guidelines,
  `gitignore.factory`, `pre-push.sh`). ADRs, Lessons, Tests und Fixtures bleiben ausgenommen.
  (Entwickler, 2026-11-13)
- **Q2 – Komposita:** nur die langen C1-Begriffe werden auch als Wortteil erkannt; `TCH`, `Neon`,
  `Vercel` bleiben Ganzwort-Treffer. (Entwickler, 2026-11-13)
- **Q3 – Ursprungs-Repo:** Checklisten-Kommentar an nothra/tch-gastro-services#428 statt eines
  eigenen Issues. (Entwickler, 2026-11-13)

## Offene Fragen

- [ ] Keine. Ort und Form des Guards (eigene Prüfung oder Erweiterung des C1-Blocks, Darstellung der
  Begriffsliste) entscheidet `/implement`. Einen ADR-Trigger sehe ich nicht: kein neues Gate in den
  pre-push-/CI-Pfaden, nur eine weitere Prüfung in der bestehenden Projekt-Suite.
