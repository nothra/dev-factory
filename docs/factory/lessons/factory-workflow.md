# Lessons: Factory-Workflow (Git/CI, Pipeline, Patch)

> Ausgelagerte `/codify`-Learnings (Volltext) zu **Git/CI, Pipeline-Skills, Patch-Workflow, Branch/Label, Review-Scope, Terminologie-Sweep, kanonische Quellen, Blocker**.
> **Nicht** `@import`-geladen (ADR-037) – bei Bedarf gezielt lesen. Kanonische Quelle je
> Regel ist der jeweilige Eintrag hier; im @import-Pfad (`PROJECT-CONTEXT.md`) steht nur eine Index-Zeile.
> Neue Learnings kommen hierher (nicht in den @import-Pfad) – siehe `/codify` + ADR-037.

### Agenten-Blockerverhalten (aus Task 002 / K-01, K-02)

Agenten wissen, dass sie bei fehlenden Voraussetzungen stoppen sollen – schreiben aber nicht **warum** sie stehen. Das macht Blockiergründe für den Menschen unsichtbar.

**Regel:** Wenn ein Agent pausiert oder abbricht (fehlende ADR, fehlende Task-Datei, Schreibfehler), muss er den Grund **explizit in der Task-Datei protokollieren** bevor er stoppt. Kein stilles Warten.

Format: `Blocker [Datum]: [Grund] – [was der Mensch tun muss]`

### Kanonische Quellen immer referenzieren (aus Task 002 / W-02, W-03)

Wenn eine Regel oder Liste an mehreren Stellen auftaucht (Skill + Persona + Spec), muss jede Kopie auf die kanonische Quelle verweisen. Fehlt der Verweis, entstehen beim nächsten Update inkonsistente Versionen.

**Regel:** Bei Änderungen an Regel-Listen: (1) Kanonische Quelle aktualisieren, (2) alle Kopien synchronisieren, (3) alte Formulierungen vollständig ersetzen – nie neben neuen stehen lassen.

### Fast-Forward-Pushes aus CI brauchen vollen Verlauf (aus Task 42, bei Live-Verifikation #40)

`actions/checkout@v4` klont per Default **shallow** (`fetch-depth: 1`). Ein normaler
`git push origin HEAD:<ziel>` auf ein **bereits existierendes** Branch-Ref wird dann serverseitig
als **non-fast-forward abgelehnt**, weil der Shallow-Clone den Fast-Forward nicht belegen kann –
selbst wenn das Ziel echter Vorfahr ist. Tückisch: Der **erste** Lauf geht durch, weil er das Ref
*neu anlegt* (Neuanlage kennt keinen FF-Check) – der Bug schlägt erst beim zweiten Promote zu.
Konkret aufgetreten im Deploy-Gate beim Promote `main`→`production`.

**Regel:** Für Fast-Forward-/Promote-Pushes aus GitHub Actions **`with: fetch-depth: 0`** am
Checkout setzen (voller Verlauf → echter FF-Guard, fail-closed). `--force` nur für **Wegwerf-Refs**
verwenden (z. B. `int`), nie für Deployment-/Prod-Refs.

### Branch-Typ und Label korrigieren wenn Scope über die initiale Annahme hinauswächst (aus #120)

Task #120 startete als `docs/`-Branch mit Label `documentation` (reine ADR-Frage), aber
`/architecture` bündelte zwei gekoppelte Concerns: ADR + konkreter Code (Enum-Migration,
Verzeichnis-Move, Tests). Branch-Typ und Label passten danach nicht mehr – was erst im
Review explizit auffiel.

**Regel:** Nach `/architecture` prüfen, ob der Branch-Typ den tatsächlichen Scope noch korrekt
abbildet. Enthält der Plan Code-Änderungen (Produktionscode, Migrationen, Tests) statt nur
Dokumentation, Branch und Label **vor `/implement`** anpassen:
```bash
# Branch umbenennen (lokal + remote)
git branch -m docs/<desc> feature/<desc>          # oder improvement/ für reine Umbenennungen
git push origin -u feature/<desc>
git push origin --delete docs/<desc>

# Label anpassen
gh issue edit <id> --add-label enhancement --remove-label documentation
```
Der PR-Body und die Task-Datei müssen den neuen Branch-Namen spiegeln. Kein Merge mit
irreführendem Branch-Typ – das verzerrt Metriken und die `git-workflow.md`-Konvention.

**Ergänzung (aus #155): Ist der Draft-PR schon offen, schließt *jede* Rename-Variante ihn.**
`start-work.sh` legt den Draft-PR sofort an – bei einer Branch-Typ-Korrektur ist er also meist
bereits offen. Sowohl das obige `git push origin --delete <old>` **als auch** die GitHub-
Branch-Rename-API (`gh api -X POST repos/<owner>/<repo>/branches/<old>/rename -f new_name=<new>`)
**retargeten den offenen PR nicht**, sondern schließen ihn (beobachtet in #155: Draft-PR #156
wurde geschlossen, sein Head zeigte weiter auf `<old>`; ein `gh pr reopen` scheitert, weil das
Head-Ref weg ist). **Regel:** Bei bereits offenem PR die Umbenennung als **PR-Ersatz** einplanen:
(1) Remote-Branch umbenennen bzw. neu pushen, (2) **neuen** PR aus `<new>` erstellen – Draft +
`Closes #<id>`, (3) auf dem alten PR einen Breadcrumb-Kommentar auf den neuen setzen,
(4) lokalen Worktree-Branch nachziehen (`git fetch -p && git branch -m <old> <new> && git branch
-u origin/<new>`), (5) Task-Datei + neuen PR-Body auf den neuen Branch-Namen ziehen. Nicht darauf
verlassen, dass ein Rename den PR erhält.

### Branch-Protection required Checks: nur `pull_request`-getriggerte Jobs (aus #155)

Beim Einrichten des `main`-Rulesets (bzw. Classic Branch Protection) darf ein CI-Job, der **nur
auf `push`→`main`** läuft (hier `gate`/Deploy-Gate und `post-merge-verify`, per `on:`/`if:` auf
den main-Push beschränkt), **nicht** als *required status check* gesetzt werden. Auf einem PR
erzeugt ein solcher Job **keinen** Check-Run (oder nur `skipped`) → der required Check bleibt
dauerhaft auf „Expected – Waiting for status" und **blockiert den Merge für immer**. Tückisch:
der Job **erscheint** in der Check-Run-Liste des PR-Head-Commits als `skipped` (bei `if:`-Skip),
was fälschlich „läuft ja" suggeriert; ein Job, der per Event gar nicht getriggert wird (`gate`),
fehlt komplett.

**Regel:** Als required nur Jobs setzen, die auf `pull_request`-Events **bis zum Ende
durchlaufen** (hier: `lint`, `test`, `issue-sync`, `factory-self-test`, `pr-closes-issue`).
Vor dem Scharfschalten gegen **echte PR-Check-Runs** verifizieren, nicht gegen die Job-Namen im
Workflow-YAML: `gh api repos/<owner>/<repo>/commits/<pr-head-sha>/check-runs --jq '.check_runs[].name'`.
Post-Merge-/Deploy-Gates gehören in `/post-merge-verify` bzw. das Deploy-Gate, nicht in die
required-Checks-Liste. Kanonische Entscheidung: [ADR-029](../../adr/029-branch-protection-main-ruleset.md).

### Report-Guard: Stale-Verdict bei Pipeline-Re-Lauf (aus #91, Review-Finding)

Der `run_skill()`-Report-Guard in `run-pipeline.sh` liest bei non-zero Exit die Report-Datei
(`tasks/review-<id>.md` / `tasks/security-<id>.md`) und akzeptiert den Verdict **ohne zu prüfen,
ob der Report in diesem Lauf entstanden ist**. Reports sind versioniert – auf einem Re-Lauf-Branch
kann ein älterer `APPROVED`/`PASSED` bereits committet sein. Schlägt der `claude`-Aufruf sofort
fehl (Rate-Limit, Auth-Fehler, Crash), liest der Guard den **alten** Verdict und gibt `return 0` –
ohne dass in diesem Lauf ein Review stattfand (fail-open statt fail-closed).

**Regel (Issue #92):** Report-Datei im Preflight für die aktuelle Task entfernen – analog zum
Stale-Sentinel-Cleanup (`INTERRUPT-*.md`). Alternativ: mtime/Hash vor dem `claude`-Aufruf merken,
Verdict nur honorieren wenn die Datei sich danach verändert hat. Bis dahin: Pipeline-Re-Läufe auf
Branches mit bereits committetem Report manuell prüfen (ADR-019 §4 ergänzen).

### `.claude/**`-Änderungen erfordern Patch-Workflow (aus #91)

Änderungen an `.claude/settings.json` und `.claude/commands/*.md` sind für einen Agenten hard
denied (`Edit(.claude/**)` / `Write(.claude/**)` – #88-Grenze). Auch `factory.defaults.yml`
(root `*.yml`) und andere Konfigurationsdateien außerhalb von `scripts/*`/`pnpm`-Scope sind nicht
in der Allow-Liste und lösen einen Interrupt aus.

**Regel:** Enthält eine Task solche Änderungen, liefert der Agent sie als **Patch-Datei**
(`tasks/patch-<id>.diff`, erstellt via `git diff`) und protokolliert den Blocker explizit in der
Task-Datei. Der Mensch wendet den Patch mit `git apply tasks/patch-<id>.diff` an und erteilt dem
Agenten danach ggf. einen expliziten Bash-Grant für die Ausführung. Kein stilles Warten –
Blocker immer mit Datum + Grund + erforderliche Aktion des Menschen notieren
(Muster: `Blocker [Datum]: [Grund] – [was der Mensch tun muss]`).

**Patch NICHT von Hand schreiben (aus #94).** Der Agent kann die `.claude/**`-Datei nicht
editieren – der Reflex, den Unified-Diff dann direkt zu tippen, produziert **korrupte Patches**:
falsche Hunk-Header-Zählung (`@@ -a,b +c,d @@`) und leere Kontextzeilen ohne führendes Leerzeichen
brechen `git apply` („corrupt patch at line N"). Stattdessen den Diff **programmatisch** erzeugen:
Original in eine Temp-Kopie lesen, dort die Änderung anwenden (Python/sed im Scratchpad – **kein**
`.claude/**`-Write), und den Patch via `git diff --no-index` oder `difflib.unified_diff` generieren
(Pfad-Header auf `a/.claude/… b/.claude/…` setzen).

**Regel:** Patch immer read-only mit `git apply --check tasks/patch-<id>.diff` verifizieren, bevor
er dem Menschen übergeben wird; zusätzlich auf Temp-Kopien anwenden und die Akzeptanz-Assertions
(Grep/JSON-Validität) dagegen laufen lassen – so ist „Green nach Apply" belegt, ohne die
hard-denied Datei anzufassen.

**Nach dem Anwenden: Task-Datei + Patch-Datei abgleichen (aus #145, Review-Finding W1).** Wird der
gelieferte Patch vom Menschen **angewendet und committet**, ist der Branch-Zustand nicht mehr
identisch mit dem, was die Task-Datei behauptet: Die AC-Checkboxen stehen weiter auf `[~]` „als
Patch geliefert – Mensch wendet an", der Blocker fordert weiter `git apply`, und `tasks/patch-<id>.diff`
liegt als **totes Artefakt** herum – `git apply --check` darauf schlägt jetzt fehl („patch does not
apply"), weil die Änderung schon im Baum ist. Das verstößt gegen die Guardrails „Task-Datei final
vor Merge abschließen" und „keine offenen Checkboxen → kein Done". **Regel:** Sobald der Patch im
Branch ist (per `git diff main...HEAD` an der `.claude/**`-Datei sichtbar), die `[~]`-Checkboxen auf
`[x]` setzen, den Blocker als **erledigt [Datum]** markieren (Historie behalten, nicht löschen) und
die stale `tasks/patch-<id>.diff` **entfernen** – alles vor `/pr-shepherd`/Merge, committet über
`factory-commit.sh`.

**Programmatischer Patch: UTF-8 nutzen + bei Semantik-Änderung die ganze Datei sweepen (aus #158).**
Zwei Fallen tauchten beim `.claude/**`-Patch von `pr-shepherd.md` auf und kosteten einen **zweiten**
Human-Apply-Zyklus (Review-Findings W1/N2/N7):
1. **ASCII-Faltung in den Replacement-Strings.** Beim Tippen des difflib-Skripts entstand der Reflex,
   Umlaute ASCII zu falten (`waehlen`/`wuerde`), um „Encoding-Ärger" zu vermeiden. Unnötig: die Datei
   ist UTF-8, `open(..., encoding="utf-8")` + `difflib` + UTF-8-Write handhaben `ä/ö/ü/ß/→/„"`
   problemlos. Die ASCII-Fassung wurde zum Review-Nitpick. **Regel:** Replacement-Strings immer in
   **korrektem UTF-8** schreiben, nie ASCII-falten; das umgebende Fließtext-Deutsch nutzt ohnehin
   Umlaute – ein ASCII-Kommentar daneben ist sofort inkonsistent.
2. **Ganzdatei-Sweep bei Semantik-Änderung, nicht nur die geänderten Zeilen.** Der Patch benannte den
   Schritt-6-Header um (`… dann Auto-Merge freigeben` → `… Merge freigeben`) und fügte einen
   Direct-Merge-Zweig hinzu – ließ aber **abhängige Beschreibungen desselben Schritts anderswo in der
   Datei** stehen: das committete Notiz-Template (`Auto-Merge freigegeben – alle Gates grün`), die
   `## Output`- und `## Hinweis für Stage 3`-Abschnitte, eine Regel-Zeile. Im neuen Direct-Merge-Pfad
   ist „Auto-Merge freigegeben" **faktisch falsch** – und das Notiz-Template landet per Squash-Merge
   auf `main` (dort nur per neuem PR korrigierbar). Verwandt mit dem #144-Terminologie-Sweep, aber der
   Auslöser ist hier eine **Verhaltens-/Semantik-Änderung** (nicht nur ein Term-Rename): Ändert ein
   Patch, **was** ein Schritt tut oder wie er heißt, die ganze Skill-Datei nach nun veralteten
   Beschreibungen dieses Schritts durchsuchen – **Header, Zusammenfassungs-/Output-Abschnitte,
   Regeln und committete Templates** – und im selben Patch mitziehen. Sonst folgt ein vermeidbarer
   zweiter Patch-/Apply-Zyklus. Faustregel: `git grep -n <alter-Begriff> <skill-datei>` nach dem
   ersten Draft, bewusste Ausnahmen (z. B. Skill-Titel „…bis Auto-Merge" = Gesamtziel) begründen.

### Notiz-vor-Merge bei Squash-Strategie (aus #114)

Ein Skill-Schritt, der eine Notiz in eine versionierte Datei (Task-Datei, Changelog) schreibt
und **danach** `gh pr merge --auto --squash` ausführt, produziert einen Verlust: Bei
Squash-Merge landet nur committeter+gepushter Inhalt auf `main`. Eine nur lokal geschriebene
Abschlussnotiz wird durch den Merge nie übernommen – und nach dem Merge liegt die Datei auf
`main`, wo Direkt-Commits verboten sind (Änderung nur noch über einen neuen PR, für ein Häkchen
unverhältnismäßig). Aufgetreten bei #112/#114 in `/pr-shepherd` Schritt 6, wo das Merge-Kommando
sogar **vor** der Notiz stand.

**Regel:** Schreibt ein Schritt eine Notiz, die mit-gemergt werden soll, gilt die Reihenfolge
**(1) Notiz schreiben → (2) committen + pushen (Feature-Branch, via `scripts/factory-commit.sh`,
nicht rohes `git commit`/`git push`, ADR-019) → (3) erst dann Auto-Merge freigeben**. Der
commit+push-Schritt muss im Skill sichtbar **vor** dem `gh pr merge --auto --squash`-Kommando
stehen. Ein Konsistenz-Test in `scripts/checks/tests/run-tests.sh` sichert die Reihenfolge ab
(grep auf `factory-commit.sh` vor dem Freigabe-Kommando). Verwandt mit der CLAUDE.md-Guardrail
„Task-Datei final auf dem Feature-Branch abschließen – vor dem Merge" (aus #63).

### Reihenfolge-Guards: Kommando ≠ Prosa-Erwähnung (aus #114, Implement-Selbstfund)

Ein Self-Test, der die **Reihenfolge** zweier Elemente in einer Skill-Doku prüft (Kommando A
vor Kommando B), greppt naheliegend nach der kurzen Kommandoform. Kommt dieselbe Zeichenkette
im Dokument aber **auch als Prosa-Verweis** vor, matcht `grep -n … | head -1` den *frühesten*
Treffer – und das ist womöglich die Erwähnung, nicht das Kommando. Konkret in #114: die
Reihenfolge-Assertion prüfte gegen `gh pr merge --auto`; diese kurze Form steht schon in
`pr-shepherd.md` Schritt 4 als Prosa-Hinweis (Zeile 68), lange **vor** dem echten Freigabe-
Kommando in Schritt 6 → falsches FAIL. Aufgefallen erst bei der Verifikation gegen die
**gepatchte Temp-Kopie** (nicht schon am Rot-gegen-Unpatched).

**Regel:** Reihenfolge-/Positions-Guards gegen die **distinktive, vollständige** Kommandoform
prüfen (hier `gh pr merge --auto --squash`), nicht gegen ein Präfix, das auch als Fließtext
auftaucht. Und: den Guard nicht nur „rot gegen den Ist-Stand" verifizieren, sondern zusätzlich
**grün gegen die gepatchte/gewünschte Fassung** (Temp-Kopie) – nur so fällt ein Fehl-Match auf,
der zufällig trotzdem rot war. Ergänzt `clean-code.md` „Ein Gate-Regex gehört durch einen Test
abgesichert … Positiv- **und** Negativ-Beispiel"; der subtile Fall hier ist ein *legitimer*
Prosa-Treffer, der nicht matchen darf.

### App-Router erzeugt Routen aus mehr als `page.tsx`/`route.ts` (aus #145)

Beim Erstellen der Routen-Übersicht (`docs/routes.md`) und des Drift-Checks
(`scripts/checks/routes-doc-check.sh`) fiel auf: der Next.js App Router erzeugt Routen **nicht nur**
aus `page.tsx` (Seite) und `route.ts` (Handler), sondern auch aus **Metadaten-Dateikonventionen** –
`app/manifest.ts` → `/manifest.webmanifest`, ebenso `sitemap.ts`, `robots.ts`, `icon.*`,
`apple-icon.*`, `opengraph-image.*`. Diese haben **keinen** `page.tsx`/`route.ts` und sind bewusst
**außerhalb** des Drift-Check-Sets (er greppt nur `page.tsx`/`api/**/route.ts`); im aktuellen Baum
existiert nur `manifest.ts`, in `docs/routes.md` als **Prosa-Notiz** geführt (keine parsebare
Tabellenzeile, sonst meldete der Check Fehl-Drift).

**Regel:** Der Drift-Check deckt `page.tsx` + `app/api/**/route.ts` ab – **nicht** die
Metadaten-Routen. Wird künftig eine solche Datei (`sitemap.ts`, `robots.ts`, `icon.tsx`, …)
hinzugefügt, den entsprechenden Pfad **manuell** in die Prosa-Notiz von `docs/routes.md` aufnehmen
(kein Automatismus fängt das). Wer den Drift-Check erweitern will, muss das Ableitungs-Muster für
diese Konventionen separat definieren **und** per Fixture testen (analog zum bestehenden
Route-Group-/`_private`-Fall in `run-tests.sh`).

### Terminologie-Sweep: `-w`-Grep ist blind für Komposita, und Pfad-Beispiele sind nicht „neutral" (aus #144)

Bei einer reinen Begriffs-Vereinheitlichung (hier „Abend" → „Veranstaltung" in `docs/`) traten
zwei Muster auf, die eine gleichartige Folge-Task (**#148**: Rollen-Rename `abrechner` →
`veranstalter` in README/spec-49/50/54) direkt wieder trifft:

1. **`git grep -w -i <wort>` übersieht Komposita.** Der `-w`-Wortgrenzen-Grep (aus dem
   Akzeptanzkriterium) fand `Abend`, `Abend-Ebene` (Bindestrich = Wortgrenze) und die
   Dateinamen-Links – aber **nicht** `abendweit` oder `Veranstaltungsabend` (Substring ohne
   Wortgrenze). Ein durchgestrichenes „abendweit" blieb so bis Review-Runde 1 unentdeckt.
2. **Ein Code-Pfad-/Route-Beispiel im Fließtext ist bei der Ersetzung nicht automatisch neutral.**
   `app/abend/[token]/` wurde beim Implementieren „naheliegend" zu `app/veranstaltung/[token]/` –
   aber `app/veranstaltung/` ist laut ADR-024 D1 der **authentifizierte** Bereich, während die
   dort beschriebene **öffentliche** F7-Route als `theke/[token]` beschlossen war (ADR-023 D6).
   Die „neutrale" Ersetzung war dadurch **irreführender** als das Original (Review-Runde 3).

**Regel:** Bei Terminologie-Sweeps:
- **Zweifach verifizieren:** `git grep -w -i <alt>` (Prosa-Wort inkl. Bindestrich-Komposita)
  **und** ein Substring-Sweep `git grep -i <alt>` (fängt `…<alt>`/`<alt>…`-Komposita), jeweils
  die bewussten Ausnahmen herausfiltern (Dateinamen-Links, historische Zitate). `-w` allein
  genügt nie als Abschluss-Beleg.
- **Homograph-/Wortstamm-Falle (bestätigt an #148, Rollen-Rename `Abrechner` → `Veranstalter`):**
  Der Ziel-Begriff kann einen **anderen** Begriff mit gemeinsamem Wortstamm haben, der erhalten
  bleiben muss (hier Rolle `Abrechner` vs. Tätigkeit `Abrechnung`/`Abrechnungsvorgang`, gemeinsamer
  Stamm `Abrechn-`). **Nie auf den Stamm ersetzen** (`s/Abrechn.../` hätte die Tätigkeit
  mitverändert), sondern den **distinktesten vollständigen Token** wählen (`Abrechner`, nicht
  `Abrechn`) und den zu erhaltenden Homograph per **Count-Assertion vor/nach** absichern
  (`git grep -c -i abrechnung <dateien>` unverändert). Groß/Klein bewusst nutzen, wenn nur eine
  Schreibweise die Rolle meint (hier Groß-`Abrechner`) und die Kleinschreibung nur in erlaubten
  historischen Code-Pointern (`` `abrechner` → `veranstalter` ``) vorkommt.
- **Pfad-/Route-/Identifier-Beispiele** vor der Ersetzung gegen die ADRs prüfen: der
  „offensichtliche" Entitäts-Begriff kann mit einem bereits belegten Segment kollidieren
  (authentifiziert vs. öffentlich). Den **faktisch korrekten** Bezeichner wählen, nicht den
  mechanisch naheliegenden.
- **Own-Voice-Prosa von historischen Zitaten trennen:** In Records, die einen vergangenen
  Zustand dokumentieren (hier spec-127), die technische Aussage erhalten und nur die
  Terminologie angleichen – keine Falschbehauptung über den alten Wortlaut erzeugen; jede
  angefasste Historie-Stelle in der Task-Datei begründen.
- **Scope-Grep gegen die Ausgabe prüfen, nicht gegen den Exit-Code:** `git diff --name-only`
  liefert **immer** Exit 0. Ein Guard `git diff … && echo BETROFFEN` feuert deshalb falsch –
  auf `| wc -l` (Zeilenzahl) testen, nicht auf `&&`/`||`.

### Repo-Setting „Allow auto-merge" muss aktiv sein, sonst scheitert `--auto` (aus #155/#158)

`/pr-shepherd` gibt den Merge über `gh pr merge --auto --squash` frei. Das setzt das
**repo-weite** Setting *Allow auto-merge* (`allow_auto_merge`) voraus – ist es deaktiviert,
lehnt GitHub **jeden** `--auto`-Aufruf grundsätzlich ab (`enablePullRequestAutoMerge`), nicht
nur im CLEAN-Fall. In Session #155 war es aus und wurde einmalig aktiviert:

```bash
gh api -X PATCH repos/nothra/tch-gastro-services -F allow_auto_merge=true
```

**Regel:** Bleibt beim Merge-Freigabe-Schritt jeder `--auto`-Aufruf mit
`enablePullRequestAutoMerge` hängen, zuerst dieses Repo-Setting prüfen
(`gh repo view --json autoMergeAllowed` bzw. das API-Feld `allow_auto_merge`) – ein
deaktiviertes Setting hätte auch die Stage-3-Pipeline blockiert. Abzugrenzen vom
CLEAN-Fall (bereits mergebarer PR): den behandelt der Direct-Merge-Fallback aus
[ADR-030](../../adr/030-pr-shepherd-direct-merge-fallback.md).

### Doku über „die Gates": required CI-Checks ≠ lokale pre-push-Gates nicht vermischen (aus #160)

Beim Neu-Ausrichten von `CONTRIBUTING.md` (Onboarding-Doku) entstand der Reflex, „die Gates"
als **eine** Liste aufzuzählen – und `Typecheck` unter die **required CI-Checks** zu schreiben.
Falsch: Das Repo hat **zwei getrennte Ebenen**, die sich überschneiden, aber nicht deckungsgleich
sind (Review-Runde 1 fand es):

- **Required CI-Checks** (branch-ruleset `protect-main`, auf `pull_request` bis zum Ende laufend,
  #155): `lint`, `test`, `issue-sync`, `factory-self-test`, `pr-closes-issue` – die Jobs in
  `.github/workflows/factory-ci.yml`.
- **Lokale pre-push-Gates** (`scripts/checks/pre-push.sh`): Tests **plus** `Typecheck` (#137),
  `Format:check`, `Routen-Doku-Drift` (#145), Branch-Name – ein **Superset**, das nur lokal läuft
  und **keinen** CI-Check erzeugt.

`Typecheck`/`Format`/`Routen-Drift` als „required Check" zu bezeichnen ist also faktisch falsch –
für ein Onboarding-Dokument, dessen einziger Zweck Genauigkeit ist, ein echter Fehler. Verwandt
mit #155 (required Checks gegen **echte** PR-Check-Runs verifizieren, nicht gegen Job-Namen im
YAML) – hier die Doku-Variante: nicht gegen die pre-push-Gate-Liste verwechseln.

**Regel:** Beschreibt Doku „die Qualitäts-Gates", die beiden Ebenen **getrennt** benennen und
jede gegen ihre Quelle prüfen: required CI-Checks gegen die `pull_request`-Jobs in
`factory-ci.yml` (bzw. `gh api repos/<owner>/<repo>/commits/<pr-head-sha>/check-runs`), lokale
Gates gegen `scripts/checks/pre-push.sh`. Ein Gate, das nur in `pre-push.sh` steht (Typecheck,
Format, Routen-Drift), ist **kein** required CI-Check und darf nicht so genannt werden. Im Zweifel
allgemein formulieren („grüne CI-Gates") statt eine falsche Einzelaufzählung zu riskieren.

### Review-Diff-Scope: `git diff main...HEAD` zeigt Fremd-PRs, wenn lokales `main` hinter `origin/main` liegt (aus #161)

Die Skills `/review`, `/security-review` und `/refactor` laden ihren Diff-Kontext per
`git diff main...HEAD` (analog `git log main...HEAD` in `/pr-shepherd`). `start-work.sh` legt den
Feature-Branch aber in einem Worktree an, der auf **`origin/main`** basiert – das **lokale**
`main`-Ref im Haupt-Baum wird dabei **nicht** aktualisiert. Der Drei-Punkt-Operator difft gegen die
**Merge-Basis** von `main` und `HEAD`. Liegt lokales `main` hinter `origin/main` (Normalfall direkt
nach `start-work.sh`, sobald seit dem letzten lokalen `main`-Pull fremde PRs auf `origin/main`
gemergt wurden), ist die Merge-Basis ein **alter** Commit → der Diff enthält alle zwischenzeitlich
gemergten **fremden** PRs zusätzlich zur eigenen Task. Konkret in #161: die bereits gemergten
#170-Dateien (`proxy.ts`, `lib/prefetch-session.ts`, spec-170 …) tauchten im Review-, Security- und
Refactor-Scope auf. Tückisch: Der Review würde fremden, längst gemergten Code mitprüfen und die
Änderungs-Statistik verfälschen; ein Fehl-Finding auf Fremdcode ist die Folge.

**Regel:** Den Task-Scope in `/review`/`/security-review`/`/refactor` gegen **`origin/main`**
bestimmen – nach `git fetch origin` mit `git diff origin/main...HEAD` (bzw.
`git log origin/main...HEAD`), nicht gegen das lokale `main`. Erscheinen Dateien im Diff, die
erkennbar nichts mit der Task zu tun haben, **zuerst die Scope-Referenz prüfen** (stale local
`main`), bevor man sie reviewt. Die Skill-Vorlagen selbst auf `origin/main...HEAD` umzustellen ist
als Follow-up erfasst (#176) – sie liegen unter `.claude/commands/**` (agent-hard-denied) und
brauchen daher den Patch-Workflow.

### ADR nach Review-Rework auf Drift prüfen – nicht nur `docs/routes.md` (aus #55, Review-Runde-2-Finding)

Ein ADR wird in `/architecture` **vor** der Implementierung geschrieben und beschreibt geplante
Funktionen konkret (hier ADR-033 D6: „`setStatus` bleibt für Theke/Sonderfälle bestehen",
„`logEreignis(...)`"). Ein Review-Runde-1-Fix (W2/W3) entfernte beide Funktionen als tote Code
(YAGNI) – der ADR-Text wurde dabei **nicht** nachgezogen und behauptete in Runde 2 weiterhin, die
gelöschten Funktionen seien Teil der Architektur. Der bestehende Guardrail „Routen-Doku bei jeder
Routen-Änderung aktualisieren" deckt nur `docs/routes.md` ab; ein technisches ADR, das während des
Rework-Zyklus (Review ↔ Implement) faktisch überholt wird, hat keinen äquivalenten Drift-Check.

**Regel:** Ändert ein Review-Fix die im referenzierten ADR **konkret benannte** Architektur (Funktions-
Existenz, Modulgrenzen, Datenfluss), das ADR **im selben Fix-Commit** auf den Ist-Stand ziehen – nicht
erst wenn ein späteres Review es bemerkt. Faustregel vor dem Schließen eines Findings: `git grep -n
<entfernter-Funktionsname> docs/adr/<aktuelle-adr>.md` – ein Treffer bedeutet Doku-Drift. Analog zum
Terminologie-Sweep (#144): der Auslöser ist eine **Verhaltens-/Architektur-Änderung**, nicht nur ein
Term-Rename.

### `/refactor` Turn-Limit-Exhaustion: Retry ohne Gedächtnis baut auf halbfertigem Fremd-Stand auf (aus #185)

Der automatisierte `/refactor`-Schritt lief 3× ins Turn-Limit (`get_max_turns`,
`token-efficiency.md` §6) ohne Commit. Jeder Wiederholungsversuch startete in einer **frischen
Session ohne Gedächtnis** der vorherigen Läufe – fand im Arbeitsbaum aber den **halbfertigen**
Zwischenstand des vorigen Versuchs vor (Datei teilweise umgebaut, Imports teilweise angepasst)
und musste dessen Absicht erst rekonstruieren, statt auf einem klaren Ausgangspunkt aufzusetzen.
Fertiggestellt wurde am Ende menschlich, im selben Scope, den die Versuche selbst schon
vorgezeichnet hatten (Duplikat-Extraktion aus `berichtModell.ts` in `berichtXlsx.ts`/
`berichtPdf.ts` + zwei tote Branches entfernen, siehe oben „Keine Fallbacks für vom Typsystem
bereits ausgeschlossene Fälle").

**Regel:** Bricht ein automatisierter Skill-Schritt wiederholt am Turn-Limit ohne Commit ab,
vor dem nächsten Retry **den Arbeitsbaum auf unstaged/uncommitted Diff prüfen** (`git status`/
`git diff`) – ein halbfertiger Fremd-Stand ist kein sauberer Ausgangspunkt für eine
gedächtnislose Session. Optionen statt „einfach nochmal starten": (1) den Diff verwerfen und mit
vollem Turn-Budget neu beginnen (`git checkout -- <dateien>`, nur wenn der Zwischenstand
erkennbar nutzlos ist), oder (2) den noch offenen Scope **explizit** in der Task-Datei
festhalten (was genau noch zu tun ist), damit die nächste Session nicht rät. Reißt derselbe
Skill wiederholt das Turn-Limit: prüfen, ob der Änderungsumfang (hier: 3 neue Module + Tests
für ein Renderer-Feature) für einen einzelnen automatisierten `/refactor`-Lauf zu groß ist,
statt endlos zu wiederholen.

### Verlustfreie Doku-Migration/Split: skriptbasiert + Byte-Reconstruction-Assertion (aus #196)

Task #196 verschob 45 `/codify`-Learnings (~978 Zeilen) aus dem @import-Pfad in 7 thematische
`lessons/`-Dateien. Ein „von Hand" verschobener Block dieser Größe lädt zu stillen Verlusten/
Vertippern ein – und das AC „verlustfrei" ist dann nur behauptet, nicht belegt.

**Regel:** Große Doku-Migrationen/Splits **skriptbasiert** durchführen und die Verlustfreiheit
**beweisen**, nicht behaupten:
1. Quelle an stabilen Marken splitten (hier `### `-Header), Einträge über eine explizite
   Reihenfolge-Map auf Zieldateien verteilen (kein Fuzzy-Matching auf Titeltext).
2. **Byte-Reconstruction-Assertion:** die Zielstücke wieder zusammensetzen und gegen den
   kanonischen Ausgangszustand (`git show origin/main:<datei>`) auf **Byte-Gleichheit** prüfen.
   Diese Assertion ist der „Test" des Verlustfrei-AC – sie fällt bei jedem verlorenen/veränderten
   Zeichen. Zusätzlich Count-Assertion (N rein → N raus) und Header-Set-Gleichheit (Index-Zeilen
   ≡ Original-Header, fängt Dublette **und** Lücke).
3. **Relative Links re-basen:** Wandern Dateien eine Verzeichnisebene tiefer, brechen relative
   Markdown-Links. Vor/nach dem Move `git grep -n '](\.\./'` (analog `](./`, `](docs/`) und die
   Tiefe anpassen (hier `](../adr/` → `](../../adr/`); beide Zielpfade auf Existenz prüfen).
4. Formatierung am Ende gegen das Projekt-Gate prüfen (`prettier --check`), nicht raten.

Verwandt mit dem #144-Terminologie-Sweep (zweifach verifizieren), aber der Auslöser ist hier eine
**Verschiebung** großer Blöcke – der entscheidende Beleg ist die Byte-Reconstruction gegen
`origin/main`, nicht ein Grep-Zähler allein.
