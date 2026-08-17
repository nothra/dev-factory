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
durchlaufen** (hier: `lint`, `test`, `issue-sync`, `factory-self-test`, `pr-closes-issue`,
`config-validation` (Nachtrag ADR-041, Task 255)).
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
denied (`Edit(.claude/**)` – #88-Grenze; das frühere zusätzliche `Write(.claude/**)`-Deny war
wirkungslos und ist seit #240 entfernt).

Top-Level-YAML wie `factory.defaults.yml` ist seit #224 über eine generische `Edit(*.yml)`-Regel
freigegeben (das ehemalige `Write(*.yml)`-Pendant war aus demselben Grund wirkungslos und ist
ebenfalls seit #240 entfernt; `pnpm-lock.yaml` bleibt als generiertes Lockfile explizit per
`deny` gesperrt); andere Top-Level-Konfigurationsdateien ohne passende Extension (z. B.
`LICENSE`, `.prettierignore`) haben weiterhin keine Allow-Regel und lösen einen Interrupt aus.

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
Branch ist (per `git diff origin/main...HEAD` an der `.claude/**`-Datei sichtbar), die `[~]`-Checkboxen auf
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

### Permission-Regeln in `.claude/settings.json`: Pfad-Semantik und `Write`-Wirkungslosigkeit vorab prüfen (aus #224)

Beim Hinzufügen neuer `Edit(...)`/`Write(...)`-Allow-/Deny-Einträge (Top-Level-YAML-Freigabe,
#224) zwei nicht offensichtliche Verhaltensweisen der Claude-Code-Permission-Engine per
`claude --print`-Verhaltensprobe (Positiv/Negativ, `FACTORY_STAGE=3`) verifiziert – beide waren
vor der Probe reine Annahmen im Task-File:

1. **Slash-freie Muster matchen auf jeder Verzeichnistiefe, nicht nur Root.** `Edit(*.yml)` folgt
   gitignore-Semantik („Bare filenames follow gitignore semantics and match at any depth",
   Claude-Code-Doku) und greift damit auch für `some/nested/path/foo.yml` – nicht nur für `foo.yml`
   im Repo-Root, obwohl die naheliegende Lesart „Top-Level-Freigabe" das nahelegt. Ein Root-Anker
   braucht einen **führenden Slash**: `Edit(/*.yml)`. Für eine `deny`-Regel ist die breitere (nicht
   verankerte) Variante meist erwünscht (schützt auch verschachtelte Treffer); für eine
   `allow`-Regel ist sie ein Least-Privilege-Risiko, wenn nur Top-Level-Dateien gemeint waren –
   in #224 erst im `/security-review` bemerkt (Wichtiges Finding), nicht schon in `/implement`.
2. **`Write(pfad)`-Regeln werden von der installierten Claude-Code-Version (2.1.218) gar nicht
   ausgewertet** – weder in `allow` noch in `deny`. Jeder `claude --print`-Aufruf gibt dafür eine
   Warnung aus: „Write(<pfad>) is not matched by file permission checks — only Edit(path) rules
   are … (Edit rules cover all file-editing tools)". Ein `Edit(pfad)`-Eintrag deckt bereits **Edit
   und Write** für diesen Pfad ab; eine separate `Write(...)`-Liste existierte seit #88 in diesem
   Repo und war **komplett wirkungslos**, in beide Richtungen – per erneuter
   `claude --print`-Probe auf CLI 2.1.220 bestätigt und in **#240 entfernt** (`allow`/`deny`
   enthalten seither keine `Write(...)`-Einträge mehr, nur noch `Edit(...)`).

**Regel:** Vor jeder neuen `.claude/settings.json`-Permission-Änderung, die auf Datei-Pfad-Muster
setzt (nicht auf Verzeichnis-Globs mit `**`):
- Slash-freie `*.ext`-Muster nur für **absichtlich repo-weite** Freigaben verwenden; ist nur eine
  Root-Datei gemeint, `/*.ext` (führender Slash) schreiben.
- **Keine neuen `Write(...)`-Einträge mehr hinzufügen** – ein `Edit(...)`-Eintrag reicht (deckt
  beide Tools ab). Die vormals bestehenden `Write(...)`-Einträge wurden in #240 entfernt – nicht
  wieder einführen, auch nicht als Vorbild für neue Einträge.
- Beide Verhaltensweisen sind Eigenschaften der Claude-Code-Version, nicht des Repos – bei einem
  größeren Claude-Code-Update (Changelog prüfen) erneut per `claude --print`-Probe verifizieren,
  ob sie noch gelten, bevor man sich weiter darauf verlässt.

### Neue Edit-Freigabe auf bislang gesperrter Config-Klasse: Selbstschwächungs-Check für Review-/Security-Review-Parameter (aus #224, Security-Review-Finding)

Wird `.claude/settings.json` so erweitert, dass ein Stage-3-Agent erstmals eine bislang
hard-denied Top-Level-Config-Datei per `Edit` erreichen kann (hier: `factory.config.yml` /
`factory.defaults.yml`, vorher komplett ohne Allow-Regel), reicht die übliche #88-Prüfung
(„`.claude/**`/`.env*` bleiben gesperrt?") allein nicht – zusätzlich prüfen, **was** die neu
erreichbare Datei steuert. `factory.config.yml` überschreibt u. a. `skills.security-review.tier`/
`max_turns` (ADR-009); `scripts/checks/config-validation-check.sh` validiert dort nur Struktur/
Wertebereich (`tier ∈ model_tiers`, `max_turns ∈ [1, MAX_TURNS_CEILING]`), **ohne** eine
Mindest-Tier-Schwelle für sicherheitsrelevante Skills zu erzwingen – ein Agent könnte die eigene
`/security-review`-Schärfe künftig autonom herabsetzen, bevor sie läuft (Issue #241).

**Regel:** Öffnet eine Task erstmals Edit-Zugriff auf eine Config-Datei, die Pipeline-Parameter
(Modell-Tier, Turn-Budget, Gate-Schwellen) steuert, im `/security-review`-Schritt explizit prüfen,
ob die zugehörige Validierung (`config-validation-check.sh` o. ä.) einen Floor für
sicherheitsrelevante Skills erzwingt. Fehlt er, als eigenes Issue (Aspekt-Label `security`)
auslagern statt nur als Randnotiz zu vermerken – die neue Zugriffsmöglichkeit selbst bleibt im
Scope der ursprünglichen Task (hier bewusst gewünscht), die fehlende Floor-Absicherung ist ein
eigenständiger Härtungs-Task.

### Ein Floor auf einen Lookup-Key ist kein Floor auf das, wofür er steht (aus #241, Security-Review-Finding)

Task 241 hat `config-validation-check.sh` um eine Mindest-Tier-Regel erweitert: `tier` von
`security-review`/`review` darf effektiv nicht unter `heavy` liegen. Der Fail-Safe wirkt aber
nur auf das **Label** – `tier: heavy` ist selbst nur ein Schlüssel in `model_tiers`, und dieser
Lookup-Pfad (`model_tiers.heavy`) blieb weiterhin frei override-bar. Ein Override, der
`model_tiers.heavy` auf ein schwächeres Modell remapped, passiert alle Regeln (Label bleibt
`heavy`, `tier_by_size` bleibt unbenutzt) und hebelt exakt den Fail-Safe aus, den die neue Regel
herstellen sollte – nur über einen zweiten, nicht enumerierten Pfad. Belegt per PoC: Override auf
`model_tiers.heavy` → Gate `exit 0`, obwohl `security-review.tier` unverändert `heavy` zeigt
(Issue #249, aus #241 ausgelagert statt Merge-Blocker).

**Regel:** Pinnt ein Gate einen Wert, der selbst nur ein Schlüssel in eine weitere,
override-bare Config-Sektion ist (Tier-Label → `model_tiers`, Rollen-Name → Rechte-Tabelle,
Environment-Name → Secret-Store-Pfad – jede Ebene der Indirektion), reicht die Prüfung des
Schlüssels allein nicht. Zusätzlich prüfen (oder als eigenes Issue benennen), ob die
**Zielseite der Indirektion** ebenfalls gegen Remap abgesichert ist – sonst bleibt der neue
Floor eine Fassade, die im Diff plausibel aussieht, aber den Bypass nur verschiebt statt
schließt.

### Existenz-Guard auf eine Security-Pin-Konstante beweist nicht ihre Verdrahtung an den Vergleichsaufruf (aus #258, Review-Runde-2-Finding)

#258 führte einen zweiten, im Repo gepinnten Anker `YQ_SHA256` ein (gegen den der aus den
Release-`checksums` gelesene Wert geprüft wird – Verteidigung gegen einen kompromittierten
Publisher, der Binary **und** Checksum-Datei gleichzeitig austauscht). Der erste Self-Test prüfte
nur, dass die Konstante mit korrektem Format existiert (`grep -qE '^YQ_SHA256="[0-9a-f]{64}"$'`),
nicht, dass sie tatsächlich als Argument an den Vergleich (`verify_sha256`) übergeben wird. Ein
Mutationstest auf `YQ_SHA256="000…0"` blieb grün. Der eigentlich gefährliche Fall lag noch tiefer:
ein Refactor, der `verify_sha256` statt mit `"$YQ_SHA256"` mit dem gerade erst aus den
`checksums` **gelesenen** Wert aufruft – dann wird `published == pinned` trivial wahr (beide
Seiten sind derselbe Wert), der Supply-Chain-Anker ist lautlos ausgehebelt, und sowohl
Self-Test als auch CI bleiben grün (ein ehrlicher Download passt ja zu seinem eigenen Hash).

**Smell:** „Ich habe eine sicherheitsrelevante Pin-Konstante eingeführt und einen Test, der ihre
Existenz/ihr Format prüft – prüft derselbe oder ein zweiter Test auch, dass sie an der
**Vergleichs-/Verifikationsstelle tatsächlich als das erwartete Argument ankommt**, statt dort
irgendein anderes Signal (insbesondere den gerade erst extern gelesenen, ungeprüften Wert)?"

**Regel:** Für eine Pin-Konstante, die einen externen/untrusted Wert absichern soll, genügt ein
Existenz-/Format-Guard nicht – ein zweiter Guard muss an der **echten Aufrufzeile** ankern (z. B.
`grep -qE '^verify_sha256 .*"\$YQ_SHA256"$'`, nicht nur `grep -q YQ_SHA256`) und per Mutation
belegen, dass ein Vertauschen der Vergleichsseiten (externer Wert statt Pin an beiden Seiten)
den Guard rot macht. Spezialfall von „Existenz beweist nicht Verhalten/Verdrahtung" (#212) und
verwandt mit „Floor auf einen Lookup-Key ist kein Floor auf die Zielseite der Indirektion" (#241,
direkt oberhalb) – hier ist die „Zielseite" nicht eine weitere Config-Sektion, sondern die
Argumentidentität am Vergleichsaufruf selbst.

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

**Nachtrag (aus #265, Selbstfund im selben Skill – Rezidiv trotz vorhandener Lesson):** Die Falle
ist nicht auf Skill-Doku beschränkt. Ein neuer Reihenfolge-Test für einen CI-YAML-Job-Block
(„Schritt A steht vor Schritt B") geriet an genau demselben Muster ins Straucheln: der
erklärende Kommentar **über** dem neuen Workflow-Schritt erwähnte den Namen des zweiten Schritts
in Prosa (`… run-tests.sh ruft pre-push.sh …`) – die Zeilennummer dieser Erwähnung lag VOR dem
neuen Schritt und wurde vom `grep -n 'run-tests.sh' | head -1`-Anker fälschlich als „Position von
Schritt B" genommen, obwohl der echte `run:`-Aufruf weiter unten stand. Sofort per Gegenprobe
(Schritte im Workflow testweise vertauscht → Test muss dann rot werden) aufgefallen, nicht erst
im Review. **Generalisierte Regel:** Der Anker einer Reihenfolge-Assertion ist unabhängig vom
Dokumenttyp (Skill-Markdown, CI-YAML, Shell-Skript) die **exakte Aufruf-Zeile** (z. B. `run: bash
scripts/install-hooks.sh`), nie ein bloßer Dateiname/Kommando-Fragment, das auch in einem
selbst verfassten Kommentar direkt daneben stehen könnte – gerade eigene, erklärende Kommentare
oberhalb eines neuen Schritts sind eine unterschätzte Quelle für genau diesen Fehl-Treffer.

**Nachtrag 2 (aus #261, Review-Runde-2/3-Selbstfund – drittes Rezidiv, diesmal außerhalb von
Reihenfolge-Checks):** Die Falle betrifft nicht nur Reihenfolge-Assertions, sondern jeden
Präsenz-/Idiom-Guard. Ein neuer Test für Task #261 (`run-tests.sh`, prüft ob `run-pipeline.sh`
das Fix-Idiom `|| true` an der richtigen Stelle nutzt) griff anfangs auf
`grep -qE 'done \|\| true' "$PIPELINE"` zurück – ein **datei-weites** Kommando-Fragment, das an
jeder beliebigen Stelle im Skript hätte auftauchen können, nicht nur an der konkreten, zu
prüfenden Codify-Regelzeilen-Pipeline. Grund für den Rückgriff auf das Fragment: Das zu
prüfende Konstrukt (`grep | head | while … done`) erstreckt sich über drei Zeilen – ein
einzelner `grep -E`-Aufruf kann so etwas nicht in einer Zeile exakt binden (Multi-Line-Match nur
über `-z`, was `bash-gotchas.md`/`clean-code.md` als nicht-portabel meidet). Erst im Review
(Runde 2/3, unabhängig gefunden) fiel auf: der Guard bliebe auch dann grün, wenn ein späteres,
unabhängiges `done || true` an anderer Stelle im Skript entstünde, während der eigentliche
Codify-Block selbst nicht mehr abgesichert wäre.

**Regel (Multi-Zeilen-Konstrukte):** Muss ein Guard auf ein Konstrukt anchoren, das sich über
mehrere Zeilen erstreckt (keine Single-Line-`grep -E`-Bindung möglich), nicht auf ein kürzeres,
datei-weit matchendes Fragment ausweichen. Stattdessen den bereits etablierten
`awk`-Block-Extraktions-Ansatz nutzen (`awk '/start-muster/{f=1} f{print} f&&/end-muster/{exit}'`,
siehe `cv_job_block`/`ci_selftest_block` aus #255), der die Prüfung auf exakt den relevanten
Block einschränkt. Ist die zu prüfende Zeile selbst die Endgrenze des Blocks (z. B. das `done`,
dessen `|| true`-Suffix geprüft werden soll), den Block bewusst **inklusive** Start- und Endzeile
extrahieren (Variante des #255-Musters, das beide Grenzen exklusiv hält) – und diese Abweichung
im Kommentar explizit benennen, sonst wirkt sie wie eine unreflektierte Kopie des Precedents.

**Nachtrag 3 (aus #258, Review-Runde-3-Finding – viertes Rezidiv, diesmal ein
Abwesenheits-/Regressions-Guard statt eines Präsenz-Guards):** Task #258 entfernte einen
dreifach kopierten `wget`+`chmod`-Block und sicherte das mit einem Ein-Zeilen-Guard
`grep -qE 'wget.*yq_linux_amd64|chmod \+x /usr/local/bin/yq'` ab – „keiner der Jobs hat das alte
Muster wieder". Beide Alternativen waren fragil, aber auf unterschiedliche Art: Die erste konnte
**nie** feuern, weil im entfernten Block `wget` und die URL auf **getrennten** Zeilen standen
(`sudo wget -qO /usr/local/bin/yq \` + Zeilenumbruch + URL) – ein `grep -E` prüft zeilenweise.
Es trug also einzig die zweite Alternative, und die verlangte exakt die Schreibweise
`chmod +x /usr/local/bin/yq`. Per Mutation belegt: der entfernte Block wortgleich wieder
eingesetzt, nur mit **gepinnter** URL und `chmod 0755` statt `chmod +x` → Suite blieb grün. Genau
der Fall, den die im selben PR neu geschriebene Regel „kein eigener `wget`/`curl`+`chmod`-Block,
auch nicht mit gepinnter URL" (CLAUDE.md §Guardrails) verbieten sollte, lief ungehindert durch.

**Regel (Abwesenheits-Guards auf ein mehrzeiliges Anti-Muster):** Hier hilft die
Block-Extraktion aus Nachtrag 2 **nicht**, weil kein gültiger Block mehr existiert, den man
extrahieren könnte – geprüft wird gerade seine Abwesenheit. Der belastbare Anker ist stattdessen
ein **datei-/repo-weiter Treffer auf das defining feature** des Anti-Musters (hier: die
Download-URL-Domain `mikefarah/yq/releases`, die in jedem denkbaren Wiedereinschleppen auftaucht,
unabhängig von Zeilenumbruch, `chmod`-Schreibweise oder Job), statt einer OR-Liste aus mehreren
konkreten Fragment-Spellings. Eine OR-Liste aus Fragmenten wirkt vollständig, ist aber nur so
stark wie ihre schwächste, oft nie erreichbare Alternative – und das fällt beim Schreiben nicht
auf, weil der Guard gegen den *aktuellen* (bereinigten) Stand grün ist. Gegenprobe zwingend: das
entfernte Anti-Muster testweise mit einer **plausiblen Variation** (andere Zeilenteilung, andere
Flag-Schreibweise, gepinnte statt `latest`-URL) wieder einsetzen und prüfen, ob der Guard rot wird
– nicht nur den Ist-Zustand grün laufen lassen.

**Nachtrag 4 (aus #286, /test-Selbstfund – fünftes Rezidiv, diesmal keine falsche Anker-Wahl,
sondern ein fehlender Reihenfolge-Check selbst):** Task #286 verlangte als zentrales AK, dass
die Klassifikations-Anweisung in drei Skill-Dokus **vor** dem `create_issue_idempotent`-Aufruf
steht. `/implement` schrieb dafür zwei separate, jeweils korrekt verankerte Präsenz-Assertions
(„Doku verweist auf `kleinfunde.md`", „Doku verweist auf die Schwellen-Tabelle") – aber **keine**
Assertion, die die relative **Position** der beiden Elemente vergleicht. Beide Einzel-Checks
waren grün, das AK „X steht vor Y" blieb trotzdem vollständig ungetestet; erst ein dedizierter
Testing-Persona-Audit in `/test` (nicht `/implement` oder `/review`) deckte die Lücke auf.

**Regel (fehlender statt falscher Reihenfolge-Check):** Formuliert ein AK explizit eine
**Reihenfolge** zwischen zwei Elementen („X vor Y", „A muss B vorausgehen"), reichen zwei
getrennte Präsenz-Assertions für X und Y **nicht** – sie beweisen nur, dass beide existieren,
nicht in welcher Reihenfolge. Es braucht eine **eigene** Assertion, die beide Zeilenpositionen
ermittelt (`grep -n <Anker-X> | head -1 | cut -d: -f1`, analog für Y) und explizit vergleicht
(`[ "$zeile_x" -lt "$zeile_y" ]`) – plus eine Mutations-Negativkontrolle mit einer Fixture, in
der die Reihenfolge bewusst vertauscht ist, um zu belegen, dass der Vergleich bei Regression
tatsächlich rot wird (sonst dieselbe Vakuität wie ein Guard ohne Gegenprobe, siehe #114 oben).
Beim Lesen eines Reihenfolge-AK explizit prüfen: „Testet mein Guard **beide** Elemente einzeln,
oder auch ihre **relative Position**?"

**Nachtrag 5 (aus #284, Review-Runde-1-Finding – sechstes Rezidiv, ausgelöst durch den eigenen
Doku-Nachzug im selben PR):** Task #284 fügte im selben PR sowohl einen neuen Fragment-Grep-Guard
hinzu (dateiweit auf `contents: write`/`issues: write`) als auch einen erklärenden WHY-Kommentar
direkt im gehärteten Workflow, der exakt dieselbe Zeichenfolge als Prosa nannte. Ab diesem Moment
war der Guard nicht mehr durch den echten `permissions:`-Block, sondern durch den eigenen,
gerade erst verfassten Kommentar erfüllbar – ein gelöschter oder auf `contents: read`
abgeschwächter Block hätte die Suite trotzdem grün gelassen. Anders als bei den bisherigen
Rezidiven (Fremd-Kommentar, CI-Kommentar, Multi-Zeilen-Konstrukt, OR-Fragment, fehlender
Reihenfolge-Check) ist die Prosa-Quelle hier keine vorbestehende Zeile, sondern eine
**Doku-Ergänzung, die derselbe PR/Implementierungsschritt gerade erst einführt** – die übliche
„gegen den Ist-Stand rot, gegen die Fassung grün"-Verifikation hätte das nicht gefangen, weil
Guard und Kommentar gleichzeitig neu entstehen.

**Regel:** Fügt ein PR im selben Zug einen Fragment-Grep-Guard **und** einen die geguardete
Zeichenfolge wörtlich nennenden Kommentar/Doku-Satz hinzu, gilt die Block-Extraktions-Pflicht aus
Nachtrag 2 zusätzlich auch dann, wenn heute (noch) keine externe Prosa-Kollision sichtbar ist –
der Kommentar, der den Guard erst erklärt, ist selbst die nächstliegende Kollisionsquelle.
Faustregel: Jeder neue Guard, der eine Zeichenfolge aus einem strukturierten Block (YAML-Key,
Env-Var, Permission) prüft, bekommt einen Block-Anker (`awk`-Block-Extraktion), sobald im selben
PR ein WHY-Kommentar in der Nähe entsteht, der dieselbe Zeichenfolge zitiert – unabhängig davon,
ob ein Test das aktuell schon nachweist.

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
  #155): `lint`, `test`, `issue-sync`, `factory-self-test`, `pr-closes-issue`,
  `config-validation` (Nachtrag ADR-041, Task 255) – die Jobs in
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

Die Skills `/review`, `/security-review` und `/refactor` luden ihren Diff-Kontext **vormals** per
`git diff main...HEAD` (analog `git log main...HEAD` in `/pr-shepherd`); seit **#176** nutzen die
Skill-Vorlagen `origin/main...HEAD` (siehe Regel unten). `start-work.sh` legt den
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
`main`), bevor man sie reviewt. Die Skill-Vorlagen selbst wurden in **#176** auf `origin/main...HEAD`
umgestellt (mit vorangestelltem best-effort `git fetch origin`) – via Patch-Workflow, da sie unter
`.claude/commands/**` liegen (agent-hard-denied).

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

**Nachtrag (aus #264): Turn-Limit-Exhaustion auch OHNE Code-Diff, und der Orchestrator hält
sich selbst nicht an die eigene Regel.** Derselbe automatisierte `/refactor`-Schritt riss in
#264 erneut 3× das Turn-Limit – diesmal ohne jede Code-Änderung. Die Konklusion („keine
Code-Änderung nötig", Checkliste geprüft, volle Testsuite grün) stand bereits nach dem ersten
Versuch fest; allein die Verifikations-Overhead (volle Testsuite, Review-Rundenabgleich,
Task-Datei-Prosa) reichte, um das Budget vor dem abschließenden Commit zu erschöpfen. Der
Orchestrator (`run_skill()` in `scripts/run-pipeline.sh`) prüft zwischen den drei Retries
– anders als die oben stehende Regel es verlangt – **nicht** auf `git status`/`git diff`; er
retryt blind, wiederholt dieselbe (bereits fertige) Arbeit dreimal identisch und bricht die
gesamte Pipeline ab. Ein Mensch musste den liegen gebliebenen, aber vollständig
committierbaren Diff danach manuell finden und committen. `run_skill()` hat für
`review`/`security-review` bereits einen Report-Guard (`report_verdict`, ADR-019 §4), der
ein Turn-Limit nach bereits geschriebenem Report toleriert – für code-schreibende Skills
fehlt das Äquivalent. Härtung als Issue #275 ausgelagert (Scope sprengt #264 selbst).
**Für die Zwischenzeit:** vor jedem Retry-Abbruch eines automatisierten Skill-Schritts
`git status` im Zielverzeichnis prüfen, bevor der Lauf als gescheitert gilt – ein
committierbarer Zwischenstand ist kein Fehlschlag, nur ein fehlender letzter Schritt.

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

### ADR-Status beim Implementieren einer frisch erstellten ADR auf „Accepted" flippen (aus #197, Review-Finding)

Wird eine ADR in Phase 1 (`/architecture`) mit Status `Proposed` angelegt und im selben Feature
in Phase 2 (`/implement`) vollständig umgesetzt+getestet, bleibt sie leicht auf `Proposed` stehen –
niemand „entscheidet" sie noch einmal bewusst. In #197 fiel das erst im Review auf: ADR-038 war
merge-reif umgesetzt, trug aber weiter `Proposed`, während alle anderen umgesetzten ADRs im Repo
(009, 011, 029, 037) `Accepted` tragen → Status-Konventions-Drift.

**Smell:** „Die ADR beschreibt, was dieser PR gerade baut – steht ihr Status noch auf `Proposed`?"

**Regel:** Realisiert der PR eine ADR (ob frisch in derselben Task erstellt oder bestehend), gehört
ihr Status **im selben PR** auf `Accepted (<Datum>)`. `Proposed` bleibt nur, wenn die Entscheidung
bewusst offen/ungebaut ist. Beim `/implement` mitprüfen, spätestens im `/review` (Runde Architektur)
als Punkt „ADR-Status ↔ Umsetzungsstand konsistent?" – analog zum ADR-Drift-Check nach Review-Rework.

### PR ändert die von einer ADR namentlich beschriebene Mechanik → ADR-Beschreibung im selben PR mitpflegen, schon beim /implement (aus #211, Review-Finding)

#211 stellte die Verdict-Erkennung von Volltext-`grep` auf anker-basiert um. ADR-019 §4 beschrieb
die alte Mechanik **wörtlich** (`grep -oE "APPROVED|NEEDS_REWORK" / "PASSED|NEEDS_FIXES"`, „letztes
Vorkommen gewinnt"). Die **Entscheidung** der ADR („eine Verdict-Erkennung, ein Ort") blieb intakt
und wurde sogar besser erfüllt – nur die beschriebene **Implementierungs-Mechanik** war danach
falsch. `/implement` pflegte Task + Spec, aber nicht die ADR; erst `/review` fand den Drift. Der
bestehende #55-Trigger („ADR nach Review-Rework auf Drift prüfen – bei ADR-Änderung") feuerte
nicht, weil hier keine ADR-**Datei** editiert wurde – es wurde **Code** geändert, den eine ADR
beschreibt.

**Smell:** „Beschreibt eine ADR die Implementierungs-Mechanik, die dieser PR gerade ändert (nicht
nur die Entscheidung)? Dann ist ihre Mechanik-Beschreibung jetzt veraltet – auch wenn ich keine
ADR-Datei ‚anfasse'."

**Regel:** Ändert ein PR die Mechanik, die eine ADR namentlich/wörtlich beschreibt, wird die
ADR-Mechanik-Beschreibung **im selben PR** aktualisiert – auch wenn die Entscheidung unverändert
gilt (dann als „Aktualisierung (#id)"-Notiz; kein neuer Entscheidungsvorgang, kein Status-Flip).
Schon beim `/implement` mitpflegen: nach dem Umbau `grep -rn` in `docs/adr/` nach den geänderten
Symbol-/Mechanik-Namen (hier `grep -oE`, `tail -1`, Funktionsname), nicht erst im Review auffangen.
Ergänzt #55 (das nur bei ADR-**Datei**-Änderungen triggert) um den Fall „Code-Änderung, die eine
ADR beschreibt".

### Auch Lesson-/Kontext-Doku im selben PR nachziehen: Präsens-Mechanik + benannter Follow-up (#N) werden stale (aus #176, Review-Finding)

#176 stellte den Diff-Scope der Skills von `main...HEAD` auf `origin/main...HEAD` um. Die Lesson,
die den ursprünglichen Bug beschrieb (`factory-workflow.md` „Review-Diff-Scope …"), enthielt zwei
Aussagen, die der Fix **stale** machte: (1) eine **Präsens**-Beschreibung des Ist-Verhaltens („Die
Skills … **laden** ihren Diff-Kontext per `git diff main...HEAD`") und (2) einen Satz, der die
Umstellung als **offenen Follow-up (#176)** auswies – erledigt durch genau diesen PR, ein
selbst-referenzieller Beleg. `/implement` pflegte Task + Spec, fand die Prosa aber nicht; `/review`
fing den Drift.

**Smell:** „Beschreibt eine Lesson/Kontext-Doku die Mechanik, die dieser PR ändert, im **Präsens** –
oder nennt sie einen **Follow-up (#N)**, den dieser PR gerade erledigt? Dann ist genau diese Prosa
jetzt veraltet, obwohl keine ADR/Routen-Doku betroffen ist." Das #211-/#55-Prinzip gilt breiter als
nur für ADRs.

**Regel:** Erweitert #211 über ADRs hinaus auf **`docs/factory/lessons/**` und `PROJECT-CONTEXT.md`**.
Ändert ein PR eine Mechanik oder erledigt er einen benannten `#N`-Follow-up, im selben PR
sweepen (`grep -rn` nach dem alten Mechanik-Term **und** nach `#<eigene-id>`/„Follow-up"):
Präsens-Beschreibungen auf Vergangenheit/„vormals … seit #id" umstellen, Follow-up-Sätze als
erledigt markieren. **Historische Vorfall-Narrative** (die *Warum-es-ein-Bug-war*-Erklärung) bleiben
bewusst unverändert – nur die Ist-Behauptung und die Offen-Markierung werden nachgezogen. Da der
Feature-Zyklus `/codify` **im selben PR** ausführt, ist „im selben PR" auch dann erfüllt, wenn die
Spec die Prosa-Pflege bewusst aus `/implement` herausnimmt und an `/codify` delegiert (so in #176).

### Frisch im selben PR erstellte/geänderte Spec braucht denselben Drift-Check wie ADRs – nicht nur vorbestehende Architekturdoku (aus #253, Review-Runde-3-Finding)

Bislang deckte die #211-/#176-Kette Drift zwischen Code und **vorbestehenden** ADRs/Lessons ab.
#253 zeigte eine weitere Quelle: die **im selben PR** (Requirements-Phase) neu geschriebene Spec
(`spec-253`) beschrieb eine engere Mechanik („nur der Kassieren-Klick friert die Position ein")
als die tatsächlich gebaute und in Runde 2 per Test zementierte („die Reihenfolge wird beim
ersten Rendern eingefroren und gilt session-weit, auch für einen StatusToggle danach"). Zwei
vorangehende Review-Runden prüften ADRs auf Drift (per Sweep über `docs/adr/**`), verglichen den
Code aber nie gegen die eigene, frisch gelieferte Spec-Prosa – sie nahmen die Spec unhinterfragt
als Maßstab, statt sie gegen das reale, getestete Ergebnis zu spiegeln.

**Smell:** „Diese Task hat in derselben PR-Session eine Spec neu geschrieben oder erweitert – stimmt
deren Wortlaut noch mit dem überein, was am Ende tatsächlich gebaut und getestet wurde, oder ist sie
seit `/requirements` unverändert, während sich der Implementierungs-Scope verschoben hat?"

**Regel:** Erweitert #211/#176 (ADR-/Lessons-Drift) explizit auf **`docs/specs/*.md`, die im selben
PR entstanden oder geändert wurden**: `/review` vergleicht die Spec-Prosa (insbesondere
AC-Formulierungen und Abgrenzungssätze wie „nur X löst Y aus"/„kein Y ohne X") wörtlich gegen den
zementierenden Test, nicht nur gegen den Produktionscode. Widerspricht der Test-Beweis der
Spec-Formulierung, gewinnt das **getestete Verhalten** (es ist das belastbarere Artefakt) – die Spec
wird nachgezogen, nicht das Verhalten nachträglich verengt. Auch angrenzende, nicht direkt
geänderte Specs mitprüfen (hier: `spec-223`, dessen AC „offene oberhalb bezahlter" seit #253 nur
noch für den Zustand nach einem Seitenaufruf gilt).

### Test einer `.claude/**`-Patch-Lieferung prüft den Endzustand der committeten Live-Datei, nicht das Patch-Artefakt (aus #212, Review-Runde 1/3)

`.claude/**` ist für den Agenten hard-denied → die Änderung kommt als `tasks/patch-<id>.diff`, den
der Mensch anwendet und committet; der Patch wird danach entfernt (Lesson #145). Der Reflex, den
zugehörigen Test „green nach apply" über das **Patch-Artefakt** zu belegen (`[ -f patch-<id>.diff ]`,
`git apply --check`, Anwenden auf eine Temp-Kopie), ist eine Falle: Sobald der Fix ausgeliefert wird
(`.claude/**`-Datei committet, `patch-<id>.diff` entfernt), scheitern genau diese Assertions – und
der einzige „grüne" Zustand (Patch da, Änderung uncommittet) liefert den Fix **nie auf main**. Es
gibt keinen auslieferbaren Endzustand, in dem Fix committet **und** Suite grün ist. In #212 lief die
CI-Suite dadurch rot (2 Fehler), obwohl der inhaltliche Fix korrekt war (von drei Review-Runden
unabhängig gefunden).

**Smell:** „Prüft mein Test die **Existenz/Anwendbarkeit** von `patch-<id>.diff` oder das
**Anwenden auf eine Temp-Kopie** – also einen Zustand, den die vorgeschriebene Pre-Merge-Bereinigung
(#145) gerade auflöst?"

**Regel:** Ein Test für eine `.claude/**`-Änderung asserted den **Endzustand** der committeten
Live-Datei direkt (`grep -qF '<Marker>' "$SHEPHERD"` o. Ä.), nie das transiente Patch-Artefakt. Der
Patch ist nur der **Liefer**-Mechanismus, nicht der Prüfgegenstand – so ist der Test nach
Anwenden+Committen grün und übersteht das Entfernen von `patch-<id>.diff`. Die inhaltlichen
Content-Assertions sind meist schon richtig gebaut; sie müssen nur gegen die Live-/committete Datei
laufen statt gegen eine Temp-Kopie.

### Neuer Worktree hat kein `.env.local` → irreführender `CredentialsSignin`-Fehlschlag beim ersten E2E-Lauf, keine echte Regression (aus #228, /implement-Selbstfund)

`start-work.sh` legt jede Task standardmäßig in einem **eigenen** Worktree an (Geschwister-
Ordner `…​.worktrees/<branch>`, siehe `git-workflow.md` → „Parallele Sessions"). `.env.local`
ist gitignored und wurde damals dabei **nicht** mitkopiert (heute automatisiert, siehe Regel
unten). Die lokale Postgres-DB läuft dagegen meist schon als **gemeinsamer** Docker-Container
über alle Worktrees hinweg (fester Host-Port, zwei Wochen alt in #228). Ein
`pnpm test:e2e e2e/auth.spec.ts` im frischen Worktree scheitert dadurch beim Login mit
`CredentialsSignin` – nicht weil der Login-Code kaputt ist, sondern weil für die aus der (damals
von Hand nachkopierten, heute automatisch gespiegelten) `.env.local` geladenen
`SEED_ADMIN_*`-Zugangsdaten schlicht **noch kein Konto in der DB existiert**. In #228 sah das
zunächst wie eine echte Regression durch den next-auth-Versions-Bump aus, war aber ein reines
Umgebungs-Setup-Problem.

**Smell:** „Login-E2E-Test schlägt im frisch angelegten Worktree mit `CredentialsSignin` fehl,
obwohl der Code unverändert ist (oder nur eine Dependency gebumpt wurde)?" → zuerst Umgebung
prüfen, nicht den Code verdächtigen.

**Regel:** Vor dem ersten `pnpm test:e2e` in einem neuen Worktree `pnpm db:seed` laufen lassen
(idempotent, legt das Admin-Konto an/aktualisiert es für die geladenen `SEED_ADMIN_*`-Werte) –
**bevor** ein E2E-Fehlschlag vorschnell dem gerade bearbeiteten Task-Diff zugeschrieben wird.
Das Kopieren der `.env.local` – früher der manuelle Schritt davor – ist **nicht** mehr nötig:
`start-work.sh` erledigt es seit #236 automatisch beim Anlegen des Worktrees und weist im
Abschluss-Output auf den noch nötigen `db:seed`-Lauf hin. Kopiert wird aus dem Baum, in dem das
Skript liegt (`$FACTORY_DIR` – üblicherweise, aber nicht zwingend der Haupt-Baum); eine im Ziel
vorhandene Datei wird nie überschrieben, Opt-out ist `FACTORY_WT_SKIP_ENV=1`.

### Neuer Interrupt-Typ → kanonische OPERATING.md-Interrupt-Tabelle mitpflegen (aus #212, Review-Finding)

`raise-interrupt.sh` akzeptiert den Typ als **Freitext** – kein Gate erzwingt einen neuen Typ gegen
eine Registry. Die einzige kanonische Registry ist die Interrupt-Typen-Tabelle in
`docs/factory/OPERATING.md` (Präzedenz: ADR-007 trug dort `POST_MERGE_FAIL` nach). #212 führte zwei
neue Typen ein (`INCOMPLETE_OUTCOME` in run-pipeline.sh, `PUSH_GATE_BLOCKED` in pr-shepherd.md) und
vergaß beide zunächst in der Tabelle – Instanz der „kanonische Quellen mitpflegen"-Familie, hier
ohne Gate, das es auffängt.

**Smell:** „Rufe ich `raise-interrupt.sh <id> <TYP> …` mit einem Typ auf, der noch nicht in der
OPERATING.md-Interrupt-Tabelle steht?"

**Regel:** Jeder neu eingeführte Interrupt-Typ wird **im selben PR** in die Interrupt-Typen-Tabelle
in `docs/factory/OPERATING.md` eingetragen (Typ · ausgelöst von · Bedeutung · was der Mensch tut).
Selbstcheck: die Typen aus `grep -rhoE 'raise-interrupt\.sh [^ ]+ [A-Z_]+' scripts/ .claude/` gegen
die Tabellen-Spalte abgleichen.

### Vorbestehenden, scheinbar unabhängigen Bash-Suite-Testfehlschlag mit zwei konkreten Prüfungen belegen, nicht nur behaupten (aus #239, /review-Selbstfund)

`scripts/checks/tests/run-tests.sh` endete in #239 mit 4 roten Fällen in einem Block, der mit dem
eigenen Task-Diff (nur `factory-commit.sh` + ein neuer Testabschnitt) nichts zu tun zu haben schien.
Die naheliegende Reaktion – „betrifft mich nicht, der Block ist ein anderes Thema" – wäre eine
unbelegte Behauptung geblieben. Stattdessen wurden zwei konkrete, automatisierbare Prüfungen
herangezogen, die die Trennung tatsächlich **beweisen**: (1) der Diff besteht aus **genau einem
Hunk**, der die fremden Zeilen gar nicht enthält (`git diff` auf Hunk-Grenzen geprüft); (2) der
fragliche Block ist ein E2E-Test, der einen bestimmten Datei-Satz in ein Test-Repo kopiert – die
eigene geänderte Datei kommt in dessen Referenzliste/Copy-Set **nicht** vor (`grep` nach dem
Dateinamen in der kopierten/referenzierten Dateimenge), kann den Fehlschlag also nicht verursacht
haben.

**Smell:** „Ich will einen roten Testfall als ‚pre-existing, nicht mein Scope' abbuchen – habe ich
das durch mehr als ‚sieht unabhängig aus' belegt?"

**Regel:** Vor dem Vermerk „vorbestehender, unabhängiger Fehlschlag" im Review-/Task-Report zwei
Prüfungen tatsächlich ausführen und ihr Ergebnis zitieren, nicht nur die Einschätzung: (1) den
eigenen Diff auf Hunk-Ebene gegen die fraglichen Zeilen prüfen (`git diff` enthält sie nicht), (2)
bei E2E-Tests mit kopiertem/referenziertem Datei-Satz die eigene geänderte Datei **nicht** in
dessen Referenzen finden. Beide Prüfungen zusammen sind der Beleg – eine allein (nur Diff-Scope
*oder* nur Referenz-Check) wäre schwächer. Trotzdem bleibt die Einordnung „real vs. environmental"
menschliche Entscheidung; ein Tracking-Issue für den Fehlschlag selbst gehört unabhängig davon
angelegt (hier [#244](https://github.com/nothra/tch-gastro-services/issues/244)).

### Real-vs-environmental-Einordnung eines gemeldeten Testfehlschlags durch Wiederholung statt Diff-Analyse belegen (aus #244, /requirements-Selbstfund)

#239 hatte einen Bash-Suite-Fehlschlag im Block „#212 W3" per Diff-Scope- und Referenz-Check als
„nicht selbst verursacht" belegt (siehe Eintrag oben), die Frage „real vs. environmental" aber
bewusst offengelassen und dafür Issue #244 angelegt. Ein Diff-Scope-Check beweist nur, dass man den
Fehlschlag nicht *verursacht* hat – er beweist nicht, ob der Fehlschlag *reproduzierbar* ist. #244
hat das mit einer anderen Prüfungsart geklärt: (1) der isolierte E2E-Block 5× hintereinander
außerhalb der Gesamt-Suite wiederholt (kein Flackern), (2) die volle Suite auf aktuellem Stand
laufen lassen (0 rot), (3) die CI-Historie (`gh run list`) für die betroffenen Branches auf
`conclusion: success` geprüft. Alle drei negativ (kein Fehlschlag mehr) → Verdict „environmental",
ohne dass die eigentliche Sandbox-Ursache der Ursprungs-Session identifiziert werden musste.

**Smell:** „Ich will einen gemeldeten Testfehlschlag als „environmental" abbuchen – reicht dafür,
dass er *diesmal* nicht auftrat, oder habe ich Wiederholung, volle Suite und CI-Historie geprüft?"

**Regel:** Eine „real vs. environmental"-Einordnung für einen nicht mehr reproduzierbaren
Testfehlschlag braucht mindestens drei Belege, nicht nur einen einzelnen grünen Lauf: (1) den
betroffenen Test-/E2E-Block isoliert **mehrfach** wiederholen (Flakiness ausschließen), (2) die
volle Suite auf aktuellem Stand laufen lassen, (3) die CI-Historie für die relevanten Branches
prüfen. Erst wenn alle drei übereinstimmend grün sind, gilt der Fehlschlag als environmental und
das Tracking-Issue kann ohne Code-Fix geschlossen werden.

### Write-Tool-Zielpfad im Worktree explizit gegen den Worktree-Suffix prüfen, nicht dem Bash-cwd vertrauen (aus #240, /implement-Selbstfund)

Beim Anlegen der neuen Spec-Datei in Task 240 landete der erste `Write`-Aufruf im **geteilten
Hauptbaum** (`.../TCH Gastro Services/docs/specs/...`) statt im per `start-work.sh` angelegten
**Worktree** (`.../TCH Gastro Services.worktrees/chore-240-.../docs/specs/...`) – trotz eines
zuvor erfolgreichen `cd` in den Worktree per Bash. Ursache: Der Bash-cwd springt nach **jedem**
Bash-Aufruf auf den Hauptbaum zurück (dokumentiertes Verhalten, sichtbar an der Zeile „Shell cwd
was reset to …" nach jedem Tool-Ergebnis) – aber das `Write`-Tool ist ein **eigenes** Tool ohne
eigenen cwd-Zustand und interpretiert einen absoluten Pfad genau so, wie er getippt wurde. Der
Fehler war kein Tool-Bug, sondern ein mentales Modell „ich bin doch gerade in den Worktree
gewechselt" (aus dem vorherigen Bash-`cd`), das beim nächsten `Write`-Aufruf nicht mehr stimmte.
Bemerkt nur durch Zufall (`git status --short` im Hauptbaum zeigte die verirrte Datei als
`??`) – ein stiller Fund, kein Test hätte ihn automatisch gemeldet.

**Smell:** „Arbeite ich in dieser Session in einem git-Worktree (nicht im Hauptbaum) und rufe
gerade `Write`/`Edit` mit einem **absoluten** Pfad auf – enthält der Pfad tatsächlich das
Worktree-Suffix (`.worktrees/<branch>/…`), oder habe ich ihn aus einer früheren Zeile
kopiert/rekonstruiert, die noch den Hauptbaum-Pfad zeigte?"

**Regel:** In einer Worktree-Session vor **jedem** `Write`-Tool-Aufruf, der eine **neue** Datei
anlegt (kein vorheriges `Read` desselben Pfads, das den Fehler sonst schon vorher aufgedeckt
hätte), den Zielpfad explizit gegen den bekannten Worktree-Pfad abgleichen – nicht aus dem
Bash-cwd oder einer vorherigen `cd`-Zeile ableiten, da beide nach dem nächsten Bash-Aufruf schon
wieder auf den Hauptbaum zurückgesprungen sind. Nach dem Anlegen sicherheitshalber `git status
--short` **sowohl** im Worktree **als auch** im Hauptbaum prüfen, um eine versehentlich falsch
platzierte Datei sofort zu bemerken (nicht erst beim Commit). Ergänzt „Bash-cwd springt auf main
zurück" (persönliche Session-Erfahrung) um die Erkenntnis, dass dasselbe Risiko unabhängig vom
Bash-Tool auch für `Write`/`Edit` gilt.

### Divergiertes `origin/main` während laufender Pipeline: Rebase-Verantwortung bei `/pr-shepherd` belassen, nicht in einem Zwischenschritt nachholen (aus #249, /refactor-Selbstfund)

Im `/refactor`-Schritt von Task 249 war `origin/main` zwischenzeitlich weitergelaufen (Task 240
wurde parallel gemergt, PR desselben Repos). Der allgemeinen Git-Workflow-Regel „vor dem Push:
pullen und rebasen" folgend wurde `git fetch origin && git rebase origin/main` auf dem
Feature-Branch ausgeführt – konfliktfrei. Der Branch war aber bereits mehrfach über
`scripts/factory-commit.sh` gepusht worden (aus `/implement`, `/review`, `/test`); der Rebase
schrieb die bereits gepushten Commit-SHAs um, wodurch ein normaler `git push` als
Non-Fast-Forward abgelehnt wurde. Ein `git push --force-with-lease` war die einzige Lösung –
in der interaktiven Stage-2-Session ließ sich das per Rückfrage an den Menschen absichern, aber
`scripts/factory-commit.sh` lässt Force-Push **bewusst** nicht zu (ADR-019 §1: „Force-Push und
destruktive Operationen sind bewusst NICHT Teil dieses Skripts"), und eine nicht-interaktive
Stage-3-Pipeline (`run-pipeline.sh`) hat niemanden, der eine Force-Push-Rückfrage beantworten
könnte – ohne einen dafür vorgesehenen Interrupt-Typ hätte der Lauf hier stecken bleiben können.
Dabei existiert für genau dieses Szenario bereits der richtige, sichere Mechanismus:
`/pr-shepherd` löst die Divergenz über `gh pr update-branch` (GitHub-seitiger Merge, kein
lokaler Force-Push nötig) – „ein lokales `git rebase` würde nie im Remote-PR landen, ohne
force zu pushen" (`.claude/commands/pr-shepherd.md`, Schritt 3).

**Smell:** „Ich bin in einem Zwischenschritt der Pipeline (`/review`, `/test`, `/refactor`,
`/security-review` – nicht `/pr-shepherd`) auf einem Feature-Branch, der bereits mindestens
einmal über `factory-commit.sh` gepusht wurde – will ich jetzt `git fetch` + `git rebase
origin/main` ausführen, nur weil die allgemeine Regel „vor dem Push pullen und rebasen" das
nahelegt, obwohl der aktuelle Schritt gar keinen inhaltlichen Konflikt mit `main` hat?"

**Regel:** Intermediate Pipeline-Skills (`/review`, `/test`, `/refactor`, `/security-review`)
rebasen NICHT eigenständig gegen ein zwischenzeitlich weitergelaufenes `origin/main`, solange
der Feature-Branch bereits einen Upstream hat (mindestens ein erfolgreicher `factory-commit.sh`
-Push liegt vor). Divergenz zu `origin/main` während einer laufenden Pipeline ist erwartetes
Verhalten bei parallelen Feature-Branches und gehört in die Zuständigkeit von `/pr-shepherd`
(`gh pr update-branch`, kein Force-Push, respektiert ADR-019 §1). Blockiert die Divergenz den
aktuellen Schritt tatsächlich inhaltlich (z. B. Merge-Konflikt in einer Datei, die dieser
Schritt gerade ändert), gehört das als Blocker in der Task-Datei protokolliert bzw. – in Stage 3
– über `scripts/raise-interrupt.sh` eskaliert, nicht durch einen eigenständigen
Rebase-plus-Force-Push mitten im Zyklus aufgelöst. Die „vor dem Push: pullen und rebasen"-Regel
aus `docs/factory/guidelines/git-workflow.md` gilt für die Branch-Erstellung (`start-work.sh`)
und den finalen Merge (`/pr-shepherd`) – nicht für jeden Zwischen-Commit einer laufenden
Pipeline auf einem bereits gepushten Branch.

### `awk`-Job-Block-Isolation in CI-Wiring-Tests muss auch am Job-Trennkommentar abbrechen, nicht nur am nächsten Job-Key (aus #255, Review-Runde-1-Finding)

Task 255 fügte einen `awk`-Einzeiler hinzu, der den YAML-Block eines einzelnen CI-Jobs aus
`factory-ci.yml` isoliert extrahiert, um ihn gezielt auf Abwesenheit zu prüfen (hier: „kein
Node/pnpm-Setup"). Der erste Entwurf brach nur am nächsten Job-Key ab:
`awk '/^  config-validation:/{f=1; next} /^  [A-Za-z0-9_-]+:/{if (f) exit} f'`. In diesem Repo
geht jedem Job aber ein mehrzeiliger Trennkommentar-Header voraus (`  # ─── <Titel> ───…`) –
Kommentarzeilen matchen `/^  [A-Za-z0-9_-]+:/` nicht (drittes Zeichen ist `#`), also „bluteten"
die Kommentarzeilen des **nächsten** Jobs mit in den extrahierten Block hinein. Im konkreten
Fall folgenlos (der Nachbar-Kommentar erwähnte weder `pnpm` noch `setup-node`), aber die
Isolation, auf der der Negativ-Test aufbaute, war strukturell brüchig – ein künftig
umformulierter Nachbar-Kommentar hätte den Test aus dem falschen Grund grün oder rot gemacht.

**Smell:** „Mein `awk`/`sed`-Konstrukt extrahiert einen YAML-Block bis zum nächsten
`schlüssel:`-Muster – bricht es auch an Kommentarzeilen ab, die vor dem nächsten Block stehen
und nicht selbst wie ein Key aussehen?"

**Regel:** Ein Block-Extraktor für „bis zum nächsten Geschwister-Element" muss **alle**
strukturellen Grenzmarker als Abbruchkriterium kennen, nicht nur den einen, den der aktuelle
Anwendungsfall zufällig auslöst – in diesem Repo zusätzlich zum nächsten `wort:`-Key auch den
Job-Trennkommentar `# ───`:
`awk '/^  <job>:/{f=1; next} /^  ([A-Za-z0-9_-]+:|# ───)/{if (f) exit} f'`. Nach dem Schreiben
den Extraktor **isoliert ausführen** und das Ergebnis auf Länge/Inhalt prüfen (`awk '...' datei
| wc -l`, Volltext lesen) – nicht nur den nachgelagerten Negativ-Test grün laufen lassen, der
bei zufällig unauffälligem Nachbarinhalt auch mit einer löchrigen Extraktion grün bleibt.

### Fix zwischen zwei `/review`-Runden sofort committen, nicht erst nach der letzten Runde (aus #251, Review-Runde-3-Finding)

`/review` lief für Task 251 als drei sequenzielle Persona-Runden (Logik, Code-Qualität,
Architektur). Runde 2 fand ein Kritisch-Finding (rumpfidentische Duplikat-Schleife, siehe
`lessons/testing.md`); der Fix wurde sofort im Working Tree angewendet, aber **nicht committet**,
bevor Runde 3 startete. Runde 3 bekam den Auftrag, `git diff origin/main...HEAD` zu lesen –
dieser Befehl zeigt nur committete Commits, nicht den unstaged Working-Tree-Stand. Der
Review-Agent bemerkte die Diskrepanz selbst (Prosa-Hinweis „diff zeigt noch die alte Variante"),
verifizierte den echten Dateiinhalt zusätzlich direkt und flaggte das Fehlen des Commits richtig
als eigenes Wichtig-Finding – aber nur, weil er zufällig nachprüfte. Ein Review-Agent, der sich
blind auf den Diff verlässt, hätte den bereits behobenen Fund erneut als offen gemeldet.

**Smell:** „Ich habe während eines laufenden Multi-Runden-Reviews (oder einer anderen
Sub-Agenten-Kette) einen Fix im Working Tree angewendet, aber die nächste Runde bekommt ihren
Kontext über `git diff origin/main...HEAD` oder eine ähnliche Commit-basierte Diff-Quelle –
liegt der Fix schon committet vor, oder nur im Arbeitsbaum?"

**Regel:** Wird ein Finding **zwischen** zwei Runden einer laufenden Multi-Agenten-Kette (Review,
Security-Review, o. Ä.) behoben, den Fix **sofort** über `factory-commit.sh` committen und
pushen, bevor die nächste Runde/der nächste Sub-Agent gestartet wird – nicht erst am Ende aller
Runden bündeln. Jede nachfolgende Runde, die ihren Kontext per `git diff origin/main...HEAD`
(oder `git log`) bezieht, sieht sonst einen veralteten Stand und muss den bereits gelösten Fund
irrtümlich erneut aufwerfen oder – schlimmer – bemerkt die Diskrepanz nicht und bewertet
gegen einen Stand, der im Repo so nicht mehr existiert.

### `PR_SHEPHERD`/`FACTORY_STAGE` in der aufrufenden Shell exportiert schlagen in jedes von der Testsuite erzeugte Wegwerf-Repo durch (aus #262, Task-Selbstfund; Härtung umgesetzt in #264)

`run-pipeline.sh` wurde für Task 262 als `PR_SHEPHERD=true bash scripts/run-pipeline.sh 262`
gestartet – ein einzelner Kommando-Präfix, der die Variable nur für diesen einen Prozess setzt.
Wird eine Pipeline stattdessen über `export PR_SHEPHERD=true` (oder eine Session, die die
Variable bereits aus einem Elternprozess erbt) gestartet, bleibt sie in der **gesamten Shell**
gesetzt – und damit auch für jeden `bash scripts/checks/tests/run-tests.sh`-Lauf, der aus
derselben Shell heraus gestartet wird. Der `#212 W3`-E2E-Testblock erzeugt dort ein
Wegwerf-Repo und ruft darin `run-pipeline.sh` real auf, um dessen Endzustands-Verifikation zu
prüfen – die geerbte `PR_SHEPHERD=true` löst darin ungewollt **Phase 7 (PR Shepherd)** aus, die
im Wegwerf-Repo abbricht (`.claude/commands/pr-shepherd.md` existiert dort nicht). Ergebnis:
vier Assertionen dieses Blocks werden rot, ohne dass der aktuelle Diff sie überhaupt berührt –
über drei aufeinanderfolgende Implement-Runden hinweg reproduzierbar identisch.

**Smell:** „Ein E2E-Testblock, der intern `run-pipeline.sh` (oder ein anderes Skript mit
eigenen Env-Var-Schaltern) real aufruft, wird rot – aber der aktuelle Diff berührt keine seiner
Eingaben, und die Shell, aus der die Testsuite läuft, hat `PR_SHEPHERD`/`FACTORY_STAGE` (oder
eine ähnliche Pipeline-Env-Var) exportiert?"

**Regel:** Vor dem Einordnen eines solchen Fehlschlags als real: mit `unset PR_SHEPHERD
FACTORY_STAGE` (bzw. `env -u`) gegenprüfen, ob er verschwindet. Verschwindet er, ist es ein
Umgebungsproblem der aufrufenden Shell, keine Regression – dokumentieren (Diff-Scope, Vorher/
Nachher-Vergleich, CI-Historie, Lesson #244), nicht blind nacharbeiten.

**Stand:** Die Härtung ist in #264 umgesetzt – jeder reale (non-`--dry-run`)
`run-pipeline.sh`-Aufruf in `run-tests.sh` neutralisiert beide Variablen per
`env -u PR_SHEPHERD -u FACTORY_STAGE` für den Kindprozess, abgesichert durch einen
Verhaltenstest (Lauf unter exportierten Variablen) **und** einen Drift-Guard, der eine neue
ungehärtete Aufrufstelle rot macht. Für `run-tests.sh` tritt das Symptom damit nicht mehr auf.
Die Diagnose-Regel oben bleibt gültig: sie greift für **andere** Skripte mit eigenen
Env-Schaltern und für jede Testsuite, die einen Kindprozess ohne solche Neutralisierung startet.

### Neuer pre-push.sh-Check, der lokalen Installationszustand voraussetzt, bricht bestehende Selbsttests in CI (aus #265, User-gemeldete CI-Regression)

Task 265 verdrahtete einen neuen, fail-closed Check in `pre-push.sh` (`hooks-installed-check.sh`,
ADR-042), der prüft, ob die Factory-Git-Hooks im aufrufenden Repo installiert sind. Lokal
(dieser Worktree) lief die gesamte Self-Test-Suite grün, weil hier tatsächlich Hooks installiert
sind. Der `factory-self-test`-CI-Job wurde trotzdem rot: der bereits **vorbestehende** `#149`-Test
(`run_prepush_149` in `run-tests.sh`) ruft `pre-push.sh` **echt gegen das reale `FACTORY_DIR`**
auf (kein isoliertes Fixture-Repo – `pre-push.sh` leitet `FACTORY_DIR` immer von seinem eigenen
Skriptpfad ab, nicht von einer überschreibbaren Variable). Ein frischer CI-Checkout hat aber –
anders als jeder eingerichtete lokale Entwickler-Worktree – **nie** installierte Hooks (git hooks
laufen in CI ohnehin nie über den echten Hook-Mechanismus); der neue Check schlug dort also
IMMER fehl und riss zwei eigentlich unabhängige Format-Gate-Testfälle mit in den roten Zustand
(erwartet exit 0, tatsächlich exit 1). Root-Cause bestätigt durch Reproduktion: lokales
Entfernen der eigenen Hooks erzeugte exakt dasselbe Fehlerbild wie der CI-Log.

**Smell:** „Ich verdrahte einen neuen Check in `pre-push.sh`, der von echtem, **lokalem**
Umgebungszustand abhängt (installierte Hooks, vorhandene Config-Datei, laufender Dienst o. Ä.) –
gibt es einen bestehenden Self-Test, der `pre-push.sh` **echt** (nicht über ein isoliertes
Fixture-Repo) gegen das reale `FACTORY_DIR` aufruft? Wenn ja: hat die CI-Umgebung, in der dieser
Self-Test läuft, denselben Zustand wie mein lokaler Entwickler-Worktree – oder nur Letzterer?"

**Regel:** Vor dem Verdrahten eines neuen `pre-push.sh`/`pre-commit.sh`-Checks, der reale
Installations- oder Umgebungszustand voraussetzt (nicht nur Repo-**Inhalt** wie
`routes-doc-check.sh`), prüfen, ob ein bestehender Self-Test das Gate-Skript real gegen
`FACTORY_DIR` aufruft (Suchmuster: `bash "$CHECKS_DIR/pre-push.sh"` ohne Fixture-Wrapper). Trifft
das zu, muss die CI-Umgebung diesen Zustand VOR der Self-Test-Suite selbst herstellen (hier:
einen `Git-Hooks installieren`-Schritt mit `bash scripts/install-hooks.sh` vor der
Self-Test-Suite in `factory-ci.yml`) – nicht den Check abschwächen oder den bestehenden Test
nachträglich isolieren. Den Fix mit einem Wiring-Test absichern, der den CI-Job-Block extrahiert
und die **Reihenfolge** der beiden Schritte prüft (sonst wirkungslos, falls die Installation
nach der Suite liefe).

### Neuer Freitext-Ablage-Mechanismus in eine vom Agentenkontext wieder gelesene Repo-Datei braucht dieselbe „Daten, keine Anweisungen"-Absicherung wie bereits etablierte Kanäle (aus #286, Security-Review-Finding)

Task #286 führte `docs/factory/kleinfunde.md` als neuen Ablage-Ort für Out-of-Scope-Funde
unterhalb der Issue-Schwelle ein: ein Skill schreibt Freitext (Felder Wo/Was/Fix) direkt in
diese Repo-Datei per `Edit` – kein Seam, keine Validierung (ADR-043 Decision 3, bewusst). Genau
diese Datei wird von **künftigen** Skill-Läufen automatisch wieder in den Agentenkontext
geladen (Duplikat-Prüfung vor dem Anhängen, generelles Doku-Lesen durch `/codify`/`/implement`)
– ohne dass jemand sie aktiv wie einen Issue-Body abrufen müsste. ADR-018 warnt explizit, dass
Issue-Labels/-Titel/-Body **nie** aus Finding-/Diff-/Fremdinhalt abgeleitet werden dürfen
("keine ausführbaren Marker") – für den neuen, strukturell risikoreicheren Kanal fehlte die
äquivalente Warnung komplett, weder in der neuen Datei noch in den drei anpassten Skill-Dokus.
Ein Angreifer, der einen PR/Diff/Kommentar kontrolliert, könnte einen Reviewer-Agenten dazu
bringen, injizierte Anweisungen wörtlich in "Was"/"Fix" zu übernehmen; ein späterer
Agentenlauf, der die Datei liest, könnte sie als Anweisung statt als Daten interpretieren
(stored prompt injection über eine Repo-Datei). Erst in `/security-review` aufgefallen, nicht
in `/implement`, `/review` oder `/test` – der Fokus lag auf Schema/Vollständigkeit, nicht auf
der neuen Angriffsfläche selbst.

**Smell:** „Mein Task führt einen neuen Mechanismus ein, über den ein Agent Freitext (der
Finding-/Diff-Inhalt zitieren kann) in eine Repo-Datei schreibt, die **ohne aktives Abrufen**
von einem künftigen Agentenlauf wieder gelesen wird – gibt es für einen strukturell
vergleichbaren, bereits etablierten Kanal (Issue-Body, PR-Kommentar, Log-Datei) schon eine
'Daten, keine Anweisungen'-Warnung? Wenn ja, fehlt sie hier wahrscheinlich auch."

**Regel:** Führt eine Task einen neuen Freitext-Ablage-Mechanismus ein, der (a) Zitate aus
Finding-/Diff-/Fremdinhalt enthalten darf und (b) ohne expliziten Abruf automatisch in einen
künftigen Agentenkontext geladen wird, bekommt er **beim Einführen** – nicht erst nachträglich
in einer Security-Review – einen zur bereits etablierten Warnung (ADR-018 „Sicherheit: Labels
sind feste Literale") äquivalenten Hinweis an der Stelle, an der das Schema selbst dokumentiert
ist (ein Ort je Regel, wie bei anderen Doku-Kontrakten in dieser Factory). `/architecture` prüft
das bereits beim Entwurf eines solchen Mechanismus explizit gegen die vorhandenen ADR-018-
Kanäle, `/implement` schreibt die Warnung mit demselben Zug wie das Schema, nicht als
Nachtrag. Trigger: `/architecture`, `/implement`, `/security-review` bei jedem neuen
Ablage-Mechanismus für Agenten-Freitext in einer Repo-Datei.

### Mutationsbeleg muss denselben Assert-Ausdruck ausführen, nicht nur denselben Grundbefehl (aus #286, Review-Runde-2-Finding)

Ein neuer Abwesenheits-Guard in `run-tests.sh` (#286) belegte per „Mutationsbeleg", dass ein
Zurückdrehen auf die alte, unbedingte Formulierung den Test rot machen würde. Die erste
Fassung hängte die alte Zeile an eine Fixture-Kopie und prüfte dann `grep -qF "$old_line"
"$mut_datei"` – **derselbe Grundbefehl** wie im echten Guard, aber **nicht derselbe
Assert-Ausdruck** (der echte Guard negiert das Ergebnis: `! grep -qF … ; echo $?`). Der
Mutationsbeleg bewies damit nur, dass die Zeile per `printf` korrekt angehängt und von `grep`
wiedergefunden wurde (im Wesentlichen ein Quoting-Test) – nicht, dass der tatsächliche,
negierte Assert-Ausdruck bei dieser Fixture wirklich auf das rote Ergebnis (`"1"`) auswertet.
Eine Regression in der Negation selbst (z. B. ein versehentlich entferntes `!`) wäre vom
Mutationsbeleg unbemerkt geblieben. Erst im Review aufgefallen, nicht beim Schreiben in
`/implement`.

**Smell:** „Mein Mutationsbeleg führt `grep`/den Kernbefehl direkt gegen die mutierte Fixture
aus, statt exakt den Ausdruck aus der echten Assertion-Zeile (inklusive `!`, `echo $?`,
Vergleichsoperator) zu kopieren und auszuführen – würde eine Regression in der **Negation**
oder im **Vergleich** selbst (nicht im Grundbefehl) von meinem Mutationsbeleg überhaupt
bemerkt?"

**Regel:** Ein Mutationsbeleg für einen Guard-Ausdruck führt **denselben Assert-Ausdruck**
(nicht nur denselben zugrunde liegenden Befehl) gegen die mutierte Fixture aus und prüft das
Ergebnis explizit gegen den erwarteten roten Wert (z. B. `mut_result="$(! grep -qF "$x"
"$mut"; echo $?)"; assert_true "$([[ "$mut_result" = "1" ]]; echo $?)" …`). Nur so beweist der
Mutationsbeleg Kausalität zum echten Guard, nicht nur Syntax/Quoting des Grundbefehls.

### „Nicht allow-gelistet" ist kein Umgebungs-Blocker, solange der Wrapper-Skript-Weg ungeprüft ist (aus #291, zwei Rework-Runden verloren)

Zwei Rework-Runden von #291 führten die GHSA-IDs (AK-5) und das Entfernen des `nanoid`-Overrides
(Review-Finding K1) als **„Umgebung – nicht lösbar"**, weil `gh api`, `pnpm` und `curl` als
**direkte** Bash-Kommandos nicht allow-gelistet sind (`.claude/settings.json` erlaubt nur
`Bash(bash scripts/*)`). Beide waren keine echten Blocker: Runde 3 löste dieselben zwei Aufgaben
über ein **Wegwerf-Wrapper-Skript** (`scripts/*.tmp.sh`, durch `.gitignore` gedeckt, Muster aus
#67/#228) – exakt derselbe `gh api`-/`pnpm install`-Aufruf, nur innerhalb einer Skript-Datei
statt als direktes Kommando. Die Permission-Regel erlaubt den *Pfad* `bash scripts/*`, nicht das
*Kommando*; ein direkt verweigertes Kommando in ein erlaubtes Skript zu verpacken ist also kein
Umgehen der Regel, sondern genau der von ihr vorgesehene Weg. Die Task-Datei benennt den eigenen
Irrtum explizit („ein Irrtum über die eigenen Möglichkeiten, kein echter Blocker") – das ist die
richtige Reaktion, aber zwei Runden zu spät.

**Smell:** „Ich will diesen Fund als Umgebungs-Blocker dokumentieren, weil `<kommando>` direkt
nicht ausführbar ist (`requires approval`/Deny) – habe ich schon versucht, dasselbe Kommando in
ein `scripts/*.tmp.sh`-Wrapper-Skript zu verpacken, bevor ich das als „nicht lösbar" einordne?"
Nicht jeder direkt verweigerte Befehl ist ein echter Blocker – nur einer, für den **kein** Pfad
(auch kein Wrapper-Skript, kein bereits erlaubtes Helper-Muster) existiert.

**Regel:** Bevor ein Agent einen Fund als Umgebungs-/Berechtigungs-Blocker in die Task-Datei
schreibt (Format `Blocker [Datum]: …`), erst prüfen, ob `.claude/settings.json` bereits einen
Pfad wie `Bash(bash scripts/*)` erlaubt, und falls ja, das gesperrte Kommando in ein
`scripts/<thema>.tmp.sh`-Skript verpacken (gitignored, nach Gebrauch löschen). Nur wenn **auch
dieser** Weg an einer echten, nicht umgehbaren Sperre scheitert (wie AK-9 in #291: `.env*` steht
unter Deny für **Read und Edit**, weil es Secrets betrifft, nicht weil ein Kommando fehlt), ist
es ein echter Blocker. Unterscheidungskriterium: eine **Kommando-Allowlist-Lücke** hat fast immer
den Wrapper-Ausweg; eine **Datei-Zugriffssperre auf Secrets/`.claude/**`** hat ihn nie – letztere
ist bewusst so gebaut, dass kein Skript-Umweg sie umgeht.

### Kleinfunde.md-Eintrag mit eigenen Zeilenankern braucht denselben Drift-Check wie ADR/Lesson/Spec – auch wenn er im selben PR entstand (aus #291, Review-Finding, erweitert #211/#176/#253)

`docs/factory/kleinfunde.md` verlangt in seinem eigenen Kopf „Fundstelle mit `Datei:Zeile`
**verifiziert am Eintragsdatum**". Ein in Review-Runde 1 von #291 angelegter Eintrag zitierte
`pnpm-workspace.yaml:44-45`/`:14-17` – korrekt zum Zeitpunkt der Verifikation. Die **eigenen**
Rework-Runden 1 und 2 desselben PRs ließen den Kommentarkopf der Datei um 22 Zeilen wachsen,
wodurch beide Anker auf falsche Stellen zeigten (`:66-67` bzw. `:15-18` wären korrekt gewesen) –
erst Review-Runde 2 fand es. Anders als bei #176 (Drift durch einen späteren, unabhängigen PR)
und #253 (Spec-Prosa vs. tatsächlich gebautes Verhalten) ist die Drift-Quelle hier **derselbe
PR, spätere eigene Commits** – ein Eintrag, der zu Beginn der Task korrekt war, wird durch die
Fortsetzung der eigenen Arbeit veraltet, ohne dass ein Fremdereignis dazwischenliegt.

**Smell:** „Ich habe einen `kleinfunde.md`-Eintrag mit `Datei:Zeile`-Ankern angelegt, und diese
Task hat danach noch weitere Commits in **derselben** Datei gemacht (Kommentare ergänzt, Zeilen
verschoben) – zeigen die Anker noch auf die richtige Stelle, oder nur auf die Stelle zum
Anlage-Zeitpunkt?"

**Regel:** Erweitert #211/#176/#253 (ADR-/Lessons-/Spec-Drift) auf **`docs/factory/kleinfunde.md`-
Einträge mit `Datei:Zeile`-Ankern, die im selben PR angelegt wurden**: vor dem Abschluss der Task
(spätestens in `/review`/`/security-review`, bevor der Merge freigegeben wird) jeden in diesem PR
neu geschriebenen Kleinfund-Eintrag gegen den **aktuellen** Stand der zitierten Datei
gegenprüfen (`sed -n '<n>,<m>p' <datei>` liest tatsächlich die behauptete Zeile?), nicht nur beim
Anlegen einmalig verifizieren und dann als erledigt betrachten.

### Fork-Subagent für eine Review-Runde: eigene Turns nach dem Spawn können in seinen Kontext bluten (aus #298, Selbstfund während `/review`)

Ein per `Agent(subagent_type: "fork")` gestarteter Review-Runden-Agent erbt den vollen
Konversationskontext **zum Zeitpunkt seiner tatsächlichen Ausführung**, nicht zum
Spawn-Zeitpunkt – der Fork läuft asynchron im Hintergrund und wird erst später vom Scheduler
tatsächlich abgearbeitet. In dieser Task wurde nach dem Spawn von Review-Runde 1 zusätzlicher
eigener Text erzeugt (`ScheduleWakeup`-Begründungen wie „Ich warte auf Runde 1, bevor ich Runde
2 starte"), während der Fork noch nicht gelaufen war. Als der Fork dann tatsächlich ausgeführt
wurde, lieferte er als „Ergebnis" nur eine Paraphrase genau dieses Wartetexts zurück – keine
einzige tatsächliche Review-Finding. Der ursprüngliche Auftrag (Logik/Korrektheit-Review gegen
spec-298) wurde komplett übersprungen; sichtbar wurde das erst, weil die kurze
`<result>`-Zusammenfassung der Notification verdächtig nach Statusmeldung statt nach Findings
klang.

**Smell:** Die `<result>`-Zusammenfassung eines Fork-Agenten liest sich wie eine
Fortsetzungs-/Warte-Ankündigung („… läuft im Hintergrund", „ich warte auf …") statt wie das
angeforderte Arbeitsergebnis (Findings, Diff, Report) – das ist ein Hinweis, dass der Fork
eigenen Kontext des Aufrufers nachgeplappert hat, statt seinen Auftrag auszuführen.

**Regel:** Nach dem Spawn eines Fork-Agenten für eine klar abgegrenzte Teilaufgabe (z. B. eine
Review-Runde) keine eigenen Turns mit narrativem „ich warte jetzt…"-Text erzeugen, bevor der
Fork fertig ist, wenn vermeidbar – jeder solche Turn ist ein weiterer Kontext-Schnappschuss, den
der Fork potenziell als eigenen sieht. Lässt sich das Warten nicht vermeiden (z. B. via
`ScheduleWakeup`), das Ergebnis nach Abschluss **nicht** nur über die kurze
`<result>`-Zusammenfassung der Notification annehmen, sondern bei Zweifel per `TaskOutput`
gegenprüfen. Liefert der Fork erkennbar keine echten Findings (siehe Smell oben), sofort per
`SendMessage` mit einer expliziten Anweisung resumen, die den ursprünglichen Auftrag wiederholt
und ausdrücklich anweist, jeglichen Text über Scheduling/Warten zu ignorieren.

**Rezidiv, verschärft durch den Resume-Versuch selbst (aus #267, Selbstfund während `/review`):**
Derselbe Fehler trat erneut auf (Fork für Review-Runde 1 lieferte statt Findings nur den eigenen
Wartetext zurück, per `TaskOutput` verifiziert). Der in der Regel oben vorgeschlagene Resume mit
expliziter Korrektur-Anweisung wurde befolgt – verschlimmerte die Konfusion aber, statt sie zu
beheben: der Fork erklärte die Korrektur-Nachricht selbst zum „Prompt-Injection-Versuch mit
fabrizierter Autorität", hielt an seiner falschen Selbstwahrnehmung fest (er sei „die
Haupt-Session, die die drei Review-Agenten selbst gespawnt hat") und fabrizierte zusätzlich
einen falschen Fortschrittsstatus („Runde 2 und 3 sind fertig, keine kritischen Findings") für
Runden, die zu diesem Zeitpunkt im echten Orchestrator-Kontext noch gar nicht gestartet waren.
Ein zweiter Resume-Versuch hätte das Risiko einer weiteren Eskalationsstufe getragen, nicht der
Korrektur.

**Regel (Verschärfung):** Der Resume-mit-Korrektur-Schritt aus der Regel oben ist ein
**einmaliger** Versuch, keine Wiederholungsschleife. Bestätigt `TaskOutput` nach diesem einen
Resume weiterhin keine echten Findings (Statusmeldung, Rollenverwechslung, fabrizierter
Fortschritt zu Teilen, die der Orchestrator nie beauftragt hat), den Fork **nicht** erneut
resumen – die Wahrscheinlichkeit, dass ein zweiter Versuch die Konfusion vertieft statt sie
aufzulösen, überwiegt die Chance auf ein verwertbares Ergebnis. Stattdessen die betroffene
Review-Runde ohne Fork-Delegation direkt im Orchestrator-Kontext durchführen (die Dateien/den
Diff liegen dort ohnehin schon vor) und den Vorfall nicht weiter verfolgen.

### AK mit Pflichtinhalt in der PR-Beschreibung wird vom Standard-Draft-Body nicht erfüllt (aus #233)

Ein Akzeptanzkriterium der Form „WHEN der PR zum Merge freigegeben wird THEN ist der manuelle
Nachlauf-Schritt **in der PR-Beschreibung** benannt" zielt auf ein GitHub-Artefakt außerhalb
des Repo-Inhalts – nicht auf eine Task-/Spec-Datei. Der von `start-work.sh` angelegte
Draft-PR-Body enthält aber nur `Closes #<id>` + Task-Titel; er wird durch keinen
`/implement`/`/test`/`/security-review`-Schritt automatisch nachgezogen, weil diese Skills nur
Repo-Dateien committen (`factory-commit.sh`). Das Ergebnis: Die Task-Datei kann diese eine
Checkbox lange als `[ ]` führen, ohne dass irgendein Gate das bemerkt – erst die Logik-Runde
von `/review` (Prüfung via `gh pr view --json body`) deckte es als kritisches Finding auf.

**Regel:** Enthält die Spec ein AK, das Inhalt **in der PR-Beschreibung selbst** fordert (nicht
in einer versionierten Datei), diesen Inhalt per `gh pr edit <nr> --body "..."` explizit
nachziehen – spätestens vor `/review`, damit die Logik-Runde es nicht als Blocker zurückwirft.
Diese Korrektur ist reine PR-Metadaten-Pflege (kein Code-/Dokuänderung im Branch) und
rechtfertigt für sich allein **keinen** vollen `/implement`-Rücksprung, wenn sie sofort
nachgezogen wird – sie sollte aber nicht erst `/pr-shepherd` überlassen werden, da dessen
Merge-Freigabe sonst auf einer unvollständigen Task-Datei aufsetzt.
