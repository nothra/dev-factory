# ADR 030: pr-shepherd – Direct-Merge-Fallback bei bereits mergebarem PR

## Status

Accepted

## Date

2026-07-19

## Context

`/pr-shepherd` gibt den Merge in Schritt 6 ausschließlich über
`gh pr merge --auto --squash` frei. Auto-Merge ist bei GitHub aber **nur** für PRs
vorgesehen, die noch auf etwas warten (laufende required Checks, ausstehende
Reviews). Ist der PR bereits mergebar – alle required Checks grün, keine
Konflikte, `mergeStateStatus: CLEAN` – lehnt GitHub `--auto` ab:

```
GraphQL: Pull request is in clean status (enablePullRequestAutoMerge)
```

Das ist kein Randfall: Schritt 6 pusht **direkt davor** die Abschlussnotiz
(#114-Reihenfolge). Bei schnellem CI – typisch für Docs-/ADR-PRs mit nur `lint`/
`test`/`issue-sync`/… als required Checks (ADR-029) – laufen die Checks dieses
Push durch, **bevor** der `--auto`-Aufruf erfolgt. Der PR ist dann `CLEAN` und
`--auto` scheitert, obwohl der PR sauber mergebar ist.

**Beobachtet** an PR #157 (Task #155): `mergeStateStatus: CLEAN`, `--auto`
abgelehnt, Schritt 6 gescheitert, obwohl nichts inhaltlich falsch war.

Rahmenbedingungen (unverändert):

1. **Autonomer, unbeaufsichtigter Fluss.** Schritt 6 läuft ohne Menschen. Ein
   Merge-Aufruf, der bei einem sauberen PR hart fehlschlägt, blockiert jeden
   autonomen Lauf mit schnellem CI.
2. **`main` ist fail-closed durch das Ruleset `protect-main` geschützt**
   (ADR-029). Kein Merge-Weg – weder `--auto` noch direkt – kann die required
   Checks umgehen; die Merge-Freigabe ist nur ein *Auslöser*, keine
   Autorisierung.
3. **`.claude/commands/pr-shepherd.md` ist für den Agenten hard-denied** (#88) –
   die Änderung läuft über den Patch-Workflow (#94).

## Decision

Schritt 6 liest **vor** dem Merge-Aufruf den Merge-Zustand des PR und wählt den
Merge-Modus danach – ein einziger, präziser Verzweigungspunkt:

- **`mergeStateStatus == CLEAN`** → **direkter** `gh pr merge --squash` (ohne
  `--auto`). Genau dieser Zustand ist es, den GitHub für `--auto` ablehnt.
- **jeder andere Zustand** (`BLOCKED`, `UNSTABLE`, `BEHIND`, `HAS_HOOKS`,
  `UNKNOWN`, …) → `gh pr merge --auto --squash` wie bisher. GitHub wartet dann
  server-seitig auf die laufenden Checks.

`CLEAN` ist die einzige direkte Bedingung; alle übrigen Zustände fallen
**fail-closed** auf `--auto` zurück. „Im Zweifel `--auto`" ist sicher, weil
`--auto` nie an einem noch nicht grünen PR mergt.

Reproduzierbarer Kern (eingebettet als Record; die kanonische Fassung lebt in
`.claude/commands/pr-shepherd.md` Schritt 6):

```bash
# Reihenfolge #114 unverändert: Abschlussnotiz via factory-commit.sh
# committen + pushen ist bereits VOR diesem Block passiert.
MERGE_STATE="$(gh pr view --json mergeStateStatus -q .mergeStateStatus)"
if [ "$MERGE_STATE" = "CLEAN" ]; then
  # Bereits mergebar → --auto würde GitHub mit
  # "Pull request is in clean status" ablehnen. Direkt squash-mergen.
  gh pr merge --squash
else
  # Checks laufen noch (BLOCKED/UNSTABLE/UNKNOWN/…) → auf die Checks warten.
  # Fail-closed: alles außer CLEAN nutzt --auto, mergt also nie einen rot/
  # unfertigen PR.
  gh pr merge --auto --squash
fi
```

Ein **Konsistenz-Test** in `scripts/checks/tests/run-tests.sh` (analog zu den
#114-/#117-Guards) sichert die Entscheidung ab: er weist im Schritt-6-Abschnitt
(a) die Zustandsprüfung `mergeStateStatus` und (b) den Direct-Merge-Zweig
`gh pr merge --squash` (ohne `--auto`) nach – jeweils gegen ein Positiv- **und**
ein Negativ-Beispiel, und ohne die bestehende #114-Reihenfolge-Assertion zu
brechen.

## Alternatives

### Option A: `CLEAN` → direkt, sonst `--auto` (gewählt)

**Pros:**
- Trifft exakt die eine Bedingung, für die `--auto` von GitHub abgelehnt wird –
  kein Ratespiel über weitere Zustände.
- Fail-closed: jeder unklare/nicht-grüne Zustand nutzt `--auto`, das nie einen
  roten PR mergt. Das Ruleset (ADR-029) bleibt die verbindliche Grenze.
- Minimaler Eingriff in ein hard-denied Skill, gut per Grep-Guard testbar.

**Cons:**
- Zwei Merge-Kommandos im Skill statt einem (etwas mehr Doku-Fläche, der neue
  Order-Guard muss den Direct-Merge-Grep von der `--auto`-Zeile abgrenzen).

### Option B: Immer `--auto` versuchen, bei „clean status"-Fehler auf direkten Merge zurückfallen

**Pros:**
- Kein vorheriger Statusabruf nötig.

**Cons:**
- Steuerung über das **Parsen einer Fehlermeldung** (`Pull request is in clean
  status`) – brüchig gegenüber GitHub-Wortlaut-Änderungen, schwer als Doku-Guard
  festzunageln.
- Ein fehlgeschlagenes Kommando als **Normalpfad** verwischt echte Fehler
  (Auth, Konflikt) mit dem Erwartungsfall.

### Option C: Immer direkt `gh pr merge --squash`, nie `--auto`

**Pros:**
- Ein einziges Kommando, kein Verzweigen.

**Cons:**
- Verliert das server-seitige Warten auf laufende Checks: bei noch nicht grünem
  CI schlägt der direkte Merge sofort fehl → der autonome Lauf müsste selbst
  pollen/warten. Der Wert von `--auto` (unbeaufsichtigtes Warten) ginge verloren.

## Rationale

Option A gewinnt, weil sie den **präzisen** Auslöser des Problems adressiert
(`CLEAN`) und in allen übrigen Fällen den bewährten `--auto`-Pfad behält. Die
Entscheidung ist strikt fail-closed: die Merge-Modus-Wahl kann den Schutz von
`main` nicht schwächen – das Ruleset prüft die required Checks unabhängig vom
gewählten Kommando. Option B koppelt Verhalten an einen Fehlerstring (fragil),
Option C opfert das autonome Warten – beide verschlechtern Robustheit bzw.
Autonomie gegenüber A.

## Consequences

**Positive:**
- `/pr-shepherd` schließt schnelle PRs (Docs/ADR) zuverlässig ab, statt an einem
  sauberen PR zu scheitern – die Hauptursache eines manuellen Eingriffs entfällt.
- Verhalten bleibt fail-closed; `main`-Schutz (ADR-029) unangetastet.
- Der Konsistenz-Test verankert die Entscheidung gegen späteres versehentliches
  Zurückdrehen.

**Negative / Trade-offs:**
- Schritt 6 enthält jetzt zwei Merge-Kommandos; der #114-Reihenfolge-Guard und
  der neue Direct-Merge-Guard müssen den vollständigen `--auto --squash`-String
  von der reinen `--squash`-Zeile sauber unterscheiden (Lehre #114: Kommando ≠
  Prosa/Teil-Match).
- Die Änderung an `.claude/commands/pr-shepherd.md` läuft über den Patch-Workflow
  (hard-denied, #88/#94) – ein manueller Apply-Schritt durch den Menschen bleibt.

**Nebenbefund (dokumentarisch):** Das repo-weite Setting *Allow auto-merge*
(`allow_auto_merge`) muss aktiv sein, sonst scheitert `gh pr merge --auto`
grundsätzlich (in Session #155 via `gh api -X PATCH .../repo -F
allow_auto_merge=true` aktiviert). Als Stolperstein in `PROJECT-CONTEXT.md`
festgehalten – hätte auch die Stage-3-Pipeline blockiert.
