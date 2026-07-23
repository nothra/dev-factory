# ADR 040: Idempotenter Issue-Seam für Pipeline-Retries

## Status
Accepted

## Datum
2026-07-23

## Kontext

`scripts/run-pipeline.sh` → `run_skill()` startet jeden Skill bei Exit ≠ 0 bis zu **3×** neu.
Jeder Retry ist eine komplett **neue `claude --print`-Session ohne Gedächtnis** – beabsichtigtes
Stage-3-Design, das aber **idempotente** Skill-Schritte voraussetzt.

Die autonomen Skills `/codify`, `/review`, `/security-review` legen Out-of-Scope-Funde als
GitHub-Issue an – über den zentralen Seam `create_issue` (ADR-018). `create_issue` legt
**bedingungslos** an: kein Vorab-Check auf ein bereits existierendes gleichnamiges Issue.
Trifft ein Retry auf denselben (deterministisch aus dem Report abgeleiteten) Fund, entsteht
ein **Duplikat**. Beobachtet in Task #187: **#204** und **#205** (Duplikat, geschlossen).

Dies ist die Fehlerklasse aus #185 („Retry ohne Gedächtnis baut auf halbfertigem Fremd-Stand
auf"), hier aber mit einem **GitHub-API-Seiteneffekt** statt einem Datei-Zustand.

Requirements (`docs/specs/spec-207-create-issue-idempotenz-guard.md`, Session 2026-07-23) hat
drei Verhaltensachsen fixiert: Match **nur gegen offene** Issues, **exakter** Titelvergleich,
Fehlerfall der Prüfung **fail-open**, Geltungsbereich **nur die 3 Pipeline-Aufrufer**
(`start-work.sh`/`sync-issues.sh` bleiben unverändert). Offen – und hier zu entscheiden – bleibt
der **Mechanismus** der Scope-Begrenzung, da alle Aufrufer denselben Seam nutzen.

## Decision

**1 · Separate Wrapper-Funktion, kein Umbau von `create_issue`.**
`scripts/lib/create-issue.sh` erhält eine **zweite** öffentliche Funktion mit identischer
Signatur:

```
create_issue_idempotent <title> <body> <art-label> [aspekt-csv]   # → Issue-Nummer auf stdout, Exit 0
```

Sie sucht ein **offenes** Issue mit **exakt** gleichem Titel; bei Treffer gibt sie dessen
Nummer zurück (Exit 0), sonst **delegiert** sie unverändert an `create_issue`. Das bestehende
`create_issue` bleibt **byte-identisch** – null Regressionsrisiko für die Bestands-Aufrufer
und die bestehende Seam-Test-Suite.

**2 · Scope-Begrenzung durch Funktionswahl (nicht durch Flag/Default).**
Nur die drei Skill-Snippets (`/codify`, `/review`, `/security-review`) rufen künftig
`create_issue_idempotent`. `start-work.sh` und `sync-issues.sh` rufen weiterhin `create_issue`.
Der Geltungsbereich ist damit **am Call-Site sichtbar und selbstdokumentierend**; es gibt kein
verstecktes Env-Flag, das versehentlich in Kindprozesse leckt, und keinen Default-Wechsel für
die Aufrufer, die wir bewusst unangetastet lassen.

**3 · Exakter Match trotz Teilstring-Suche.**
`gh issue list --search "in:title …"` ist eine **Volltext-/Teilstring**-Suche. Der exakte
Abgleich erfolgt **clientseitig**: die Suche verengt nur die Kandidatenmenge, danach wird jeder
Kandidatentitel per **exaktem Stringvergleich** gegen den Zieltitel geprüft. Genutzt wird die
in `gh` **eingebettete** JSON-Ausgabe (`--json number,title -q …`) – **keine** neue externe
`jq`-Abhängigkeit. Bei mehreren exakten Treffern gewinnt die **niedrigste** (älteste) Nummer.

**4 · Fail-open auf die Prüfung, fail-closed unverändert auf die Anlage.**
Kann der Lookup nicht durchgeführt werden (gh-Fehler, Auth, Netz, kein `gh`, unparsebare
Ausgabe), wird **regulär via `create_issue` angelegt** und eine Warnung auf **stderr**
ausgegeben – konsistent mit der bestehenden Label-Degradation (ADR-018 §3). Die
Anlage-Semantik von `create_issue` (Exit ≠ 0 nur, wenn gar kein Issue entsteht) bleibt.

**5 · stdout/stderr-Kontrakt unverändert (ADR-018 §2).**
`num=$(create_issue_idempotent …)` erhält auf **stdout ausschließlich** die reine Issue-Nummer
(bestehender Treffer oder neu angelegt); alle Diagnostik/Warnungen/Treffer-Hinweise gehen auf
**stderr**.

Diese ADR **erweitert** ADR-018 (ersetzt sie nicht): der zentrale Seam bleibt, bekommt eine
opt-in-Idempotenz-Variante daneben.

## Alternatives

### Mechanismus – Option A: separate Wrapper-Funktion (gewählt)
**Pros:** `create_issue` bleibt unverändert (null Regression, Bestands-Tests unberührt); Scope
sichtbar am Call-Site; kein Env-Leak; testbar mit gh-Stub wie der bestehende Seam; folgt der
ADR-018-Linie „dünner, testbarer Seam". **Cons:** zweiter Einstiegspunkt in der Lib; drei
Skill-Snippets müssen auf die neue Funktion umgestellt werden (`.claude/**`-Patch-Workflow).

### Mechanismus – Option B: Env-/Positions-Flag in `create_issue`
`FACTORY_ISSUE_DEDUP=1 create_issue …` bzw. ein 5. Argument aktiviert den Guard **innerhalb**
von `create_issue`. **Pros:** ein Einstiegspunkt. **Cons:** verändert den Kontrakt der
Bestands-Funktion; ein neuer bedingter Zweig, der nur von manchen Aufrufern durchlaufen wird
(beide Zustände müssen getestet werden); ein Env-Flag ist „spooky action at a distance" und
kann in Kindprozesse/gleiche Shell (start-work sourct den Seam) unbeabsichtigt durchschlagen.

### Mechanismus – Option C: Guard in `create_issue`, Default-an, Nicht-Ziele opten aus
**Pros:** ein Pfad. **Cons:** invertiert den sicheren Default; erzeugt Churn genau bei den
Aufrufern (`start-work`/`sync-issues`), die laut Requirements **unangetastet** bleiben sollen.
Widerspricht der Scope-Entscheidung. **Verworfen.**

### Mechanismus – Option D: Guard nur in der Skill-Prosa (jedes Snippet macht `gh issue list`)
**Pros:** kein Lib-Umbau. **Cons:** LLM-getrieben, nicht robust/deterministisch testbar; in
drei Skills dupliziert (Drift); widerspricht dem ADR-018-Grund, die Anlage-Logik zu
zentralisieren. **Verworfen.**

### Match-Zustand – offen vs. offen+geschlossen
Nur **offen** (gewählt, Requirements): ein erledigtes/abgelehntes Issue blockiert einen
wiederkehrenden Fund nicht. offen+geschlossen würde legitime Neuanlagen unterdrücken.

## Begründung

Option A ist die YAGNI- und ADR-018-konsistente Wahl: die kleinste Änderung, die das Problem
löst, ohne den bewährten Bestandspfad anzufassen. Die Scope-Begrenzung „nur 3 Aufrufer" wird
nicht über verstecktes Verhalten, sondern über **explizite Funktionswahl** erreicht – das ist
lesbar, testbar und driftfrei. Fail-open folgt derselben Guardrail-Faustregel wie ADR-018 §3:
die Issue-*Anlage* (ein realer Fund darf nicht verloren gehen) wiegt schwerer als das seltene
Duplikat, das ein nicht durchführbarer Lookup zulässt. Der exakte, clientseitige Titelvergleich
verhindert False-Positives der Teilstring-Suche (Spec AC5) und vermeidet zugleich eine neue
externe Abhängigkeit.

## Consequences

**Positive:**
- Pipeline-Retries erzeugen keine Duplikat-Issues mehr für die drei autonomen Aufrufer (Spec AC4).
- `create_issue` und dessen Kontrakt/Tests bleiben unverändert – kein Regressionsrisiko.
- Geltungsbereich am Call-Site sichtbar; keine Env-Kopplung, kein Default-Wechsel.
- Deterministisch mit gh-Stub testbar (Treffer / kein Treffer / Teilstring / Lookup-Fehler).

**Negative / Trade-offs:**
- Zweiter Einstiegspunkt in `create-issue.sh` (bewusst; DRY bleibt durch Delegation gewahrt).
- Restlücke: erzeugt ein Retry durch Agenten-Nichtdeterminismus einen **abweichenden** Titel,
  greift der exakte Match nicht (Spec: kein Fuzzy-Matching – akzeptiert).
- Drei Skill-Snippets (`.claude/commands/*.md`) müssen umgestellt werden → `.claude/**`-Änderung
  erfordert den Patch-Workflow (aus #91).

## Betroffene Artefakte
- `scripts/lib/create-issue.sh` – neue Funktion `create_issue_idempotent` (Lookup + Delegation)
- `.claude/commands/codify.md`, `review.md`, `security-review.md` – Snippet auf `create_issue_idempotent` umstellen
- `scripts/checks/tests/run-tests.sh` – Tests für den Guard (offener Treffer, geschlossen ignoriert, Teilstring kein Treffer, Lookup-Fehler → fail-open, stdout=Nummer)
- `docs/adr/018-central-issue-seam.md` – wird durch diese ADR erweitert (Querverweis)
- ggf. `docs/factory/PROJECT-CONTEXT.md` (Index) via `/codify`
