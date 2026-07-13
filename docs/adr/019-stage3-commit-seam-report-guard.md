# ADR 019: Stage-3 Commit-Seam & Report-Guard für `run_skill()`

## Status
Accepted

## Date
2026-07-12

## Kontext

Die Stage-3-Pipeline (`scripts/run-pipeline.sh`) ruft jeden Skill non-interaktiv über
`FACTORY_STAGE=3 claude --print … --max-turns N` auf. Permissions kommen ausschließlich aus
`.claude/settings.json`; ein Prompt kann nicht beantwortet werden, jede nicht erlaubte Aktion
blockiert den Schritt. Zwei Lücken traten beim Live-Lauf für #66 (nach #88) auf – Details in
`docs/specs/spec-91-stage3-commit-turn-budget.md`:

1. **Kein Commit/Push möglich.** #88 gab `Edit`/`Write` frei, aber ein `git commit`/`git push`
   matcht keinen Allow-List-Eintrag → Stage-3-Prompt → Interrupt. `/implement`, `/test`,
   `/refactor` schrieben korrekte Änderungen, konnten sie aber nicht committen; die Pipeline lief
   „erfolgreich" durch, ohne dass je etwas gepusht/gemergt worden wäre.
2. **Turn-Limit reißt nach fertigem Report.** `run_skill()` wertet jeden non-zero Exit von
   `claude --print` (inkl. „Reached max turns") als Fehlversuch. `/security-review` schrieb im
   1. Versuch einen vollständigen, korrekten `tasks/security-66.md` (PASSED), arbeitete danach
   aber weiter und riss das `max_turns: 8`-Limit → alle 3 Versuche „gescheitert" → Pipeline-Exit 1
   trotz inhaltlich fertigem Ergebnis.

Zwei Entscheidungen sind langfristig relevant und darum ADR-würdig: **(A) wie** ein
Stage-3-Agent an git schreiben darf (Permissions-Grenze) und **(B)** wann ein report-erzeugender
Skill-Lauf als erfolgreich gilt (Erfolgssemantik der Orchestrierung). Beide Design-Forks hat der
Mensch am 2026-07-12 entschieden (Wrapper-Skript bzw. Report-Guard + Budget); diese ADR hält sie
mit Alternativen fest.

## Decision

**1 · Commit/Push über einen Skript-Seam, nicht über die git-Permission-Fläche.**
Neues Skript **`scripts/factory-commit.sh "<message>"`** kapselt „commit + push des aktuellen
Feature-Branches" und sichert **fail-closed** ab:
- Verweigert Ausführung auf `main`/`master` (Exit ≠ 0) – doppelt gesichert zu `pre-push.sh`.
- Kein `--force`/Force-Push, keine destruktiven Ops (`reset --hard` o. Ä. sind nicht Teil).
- Ablauf: `git add` → `git commit -m "<message>"` → `git push` (Neuanlage via `-u origin HEAD`).
- „Nichts zu committen" ist kein harter Fehler (definierter Exit, klare Meldung), damit ein
  änderungsloser Schritt die Pipeline nicht abbricht.

Das Skript läuft über die **bestehende** `Bash(bash scripts/*)`-Erlaubnis → **keine** neue
git-Schreib-Permission in `.claude/settings.json`. Die Guard-Logik liegt an **einer**
auditierbaren Stelle (analog zum Issue-Seam, ADR-018). Die Message ist Pflicht-Argument – die
Commit-Message-Verantwortung (Conventional-Commit-Präfix) bleibt beim aufrufenden Skill.

**2 · Read-only-git in die Allow-List.** `Bash(git status:*)`, `Bash(git diff:*)`,
`Bash(git log:*)`, `Bash(git branch:*)`, `Bash(git rev-parse:*)` – rein lesend, damit
Diagnose-Kommandos keinen Interrupt auslösen. **Kein** pauschales `Bash(git *)`.

**3 · `pr-shepherd`-`gh`-Verben granular freigeben (für AC3).** Nur die von `pr-shepherd.md`
tatsächlich genutzten Verben: `gh pr view`, `gh pr checks`, `gh pr update-branch`, `gh pr merge`,
`gh run list`, `gh run rerun`. **Kein** pauschales `Bash(gh *)`. `gh pr merge --auto` bleibt
server-seitig durch CI **und** menschliches Approval gated – Auto-Merge vollzieht sich nicht ohne
grüne Gates.

**4 · Report-Guard in `run_skill()`.** Ein non-zero Exit (inkl. „Reached max turns") gilt als
**Erfolg**, wenn der zugehörige Report bereits mit gültigem Verdict geschrieben wurde – **nur**
für die zwei report-erzeugenden Skills:
- `review` → `tasks/review-<id>.md` enthält `APPROVED` oder `NEEDS_REWORK`.
- `security-review` → `tasks/security-<id>.md` enthält `PASSED` oder `NEEDS_FIXES`.

Die Verdict-Erkennung koppelt an dieselben verbindlichen Report-Werte, die `pipeline_summary()`
schon liest (`grep -oE "APPROVED|NEEDS_REWORK"` / `"PASSED|NEEDS_FIXES"`); sie wird in **einen**
Helper gezogen, damit Guard und Summary nicht auseinanderdriften (kanonische Quelle, ein Ort).
Für alle anderen Skills bleibt non-zero = Fehlversuch. Nach dem als-Erfolg-gewerteten Abbruch
läuft weiterhin `interrupt-check.sh` (kein stiller Übergang bei signalisiertem Interrupt).

**5 · Budget-Puffer.** `factory.defaults.yml`: `max_turns` von `8` auf **14** für `review` und
`security-review` (mit `@reason`) – zusätzlich zum Guard, nicht als Ersatz.

## Alternatives

### Frage A „Commit/Push-Mechanik": Option A – Wrapper-Skript (gewählt)
**Pros:** keine neue git-Permission-Fläche (läuft über `Bash(bash scripts/*)`); main/master- und
`--force`-Guard fail-closed an einer auditierbaren Stelle; unit-testbar mit git-Stub; passt zur
Factory-Philosophie „deterministische Skripte kapseln riskante Ops" und zum Seam-Muster (ADR-018).
**Cons:** Skills müssen den Wrapper aufrufen statt rohem git; ein neues Skript mehr.

### Frage A: Option B – granulare git-Allow-List (`Bash(git commit:*)`, `Bash(git push:*)`)
Näher am #88-Muster (reine Config). **Cons:** Prefix-Globs können `git push` **nicht** von
`git push --force <feature>` trennen → Schutz vor Force-Push/main hinge allein am pre-push-Hook;
die Guard-Absicht (kein Force außer Wegwerf-Refs) ließe sich in `settings.json` nicht ausdrücken;
Logik über mehrere Muster verstreut statt an einem Ort testbar.

### Frage A: Option C – pauschal `Bash(git *)` (verworfen)
**Cons:** öffnet die gesamte git-Oberfläche (inkl. `reset --hard`, `push --force`) – verletzt
fail-closed direkt; nicht vertretbar für einen non-interaktiven Agenten.

### Frage B „Turn-Limit": Option A – Report-Guard + moderat höheres Budget (gewählt)
**Pros:** behebt die **Wurzel** (Erfolg = fertiger Report, nicht = sauberer Exit) und gibt mit 14
Turns Luft; nutzt die bereits geparsten Verdict-Dateien; deterministisch mit Report-Fixtures testbar.
**Cons:** koppelt `run_skill()` an Report-Pfad/Verdict-Strings (bewusst zentralisiert, s. §4);
minimal mehr Logik in `run_skill()`.

### Frage B: Option B – nur `max_turns` anheben
**Pros:** trivialste Änderung (nur YAML). **Cons:** brittle – ein Lauf, der auch bei 14 Turns
nach dem Report weiterarbeitet, scheitert weiter (genau das Muster aus #66); behandelt das
Symptom, nicht die Ursache.

### Frage B: Option C – nur Report-Guard, `max_turns` bei 8
**Pros:** fixt die Wurzel, spart Tokens. **Cons:** knapper Puffer; ein Lauf, der den Report erst
spät fertigstellt, könnte vor dem Verdict abbrechen → Guard greift nicht. Der kleine Budget-Puffer
macht das robuster, ohne die Kosten stark zu erhöhen.

## Begründung

Beide gewählten Optionen folgen etablierten Factory-Prinzipien: **Seam statt breiter Fläche**
(ADR-018) hält die riskante Operation an einem testbaren, fail-closed Ort statt sie über
schwer absicherbare Permission-Globs zu verteilen; **fail-closed nur dort, wo es Korrektheit
schützt** (main/master, Force-Push, „gar kein Report"), sonst robust weiterlaufen („nichts zu
committen"). Der Report-Guard verschiebt die Erfolgssemantik vom Prozess-Artefakt (Exit-Code)
auf das inhaltliche Artefakt (fertiges Verdict) – das misst, was die Pipeline eigentlich meint.
Beide Änderungen sind **reversibel** (Skript/Config), rechtfertigen aber eine ADR, weil sie die
Permissions-Grenze und die Erfolgssemantik der Orchestrierung dauerhaft prägen.

## Consequences

**Positive:**
- Stage-3-Sub-Agenten committen/pushen ihre Arbeit selbstständig auf dem Feature-Branch; ein
  voller `PR_SHEPHERD=true`-Lauf braucht kein manuelles Nachziehen mehr.
- Keine neue git-Schreib-Permission-Fläche; Force-Push/main bleiben fail-closed (Skript + Hook).
- `review`/`security-review` scheitern nicht mehr an einem Turn-Limit, das erst nach dem fertigen
  Report reißt.
- Guard und `pipeline_summary` teilen eine Verdict-Erkennung (kein Drift).

**Negative / Trade-offs:**
- Neues Skript `scripts/factory-commit.sh`; Code-erzeugende Skills müssen es statt rohem git nutzen.
- `run_skill()` koppelt an Report-Pfade/Verdict-Strings (zentralisiert, aber vorhanden).
- Granulare `gh`-Freigabe muss gepflegt werden, wenn `pr-shepherd` neue `gh`-Verben nutzt.

## Betroffene Artefakte
- `scripts/factory-commit.sh` (neu) – Commit/Push-Seam, fail-closed gegen main/master & `--force`.
- `.claude/settings.json` – read-only-git + granulare `gh`-Verben in `allow`; `deny` unverändert
  (`.claude/**`, `.env*`). Kein `Bash(git *)`/`Bash(gh *)`.
- `scripts/run-pipeline.sh` – Report-Guard in `run_skill()`; geteilter Verdict-Helper mit
  `pipeline_summary()`.
- `factory.defaults.yml` – `review`/`security-review` `max_turns: 8 → 14` (mit `@reason`).
- Skill-Dateien `implement`/`test`/`refactor`/`bug-fix` – committen/pushen über `factory-commit.sh`.
- `scripts/checks/tests/run-tests.sh` – Tests für Wrapper (Happy-Path/main-Verweigerung/leer) und
  Report-Guard (Verdict da → Erfolg; ohne → Fehlschlag), git-Stub-Muster (#80).

## Implementierungs-Hinweise (für den Coding-Agenten)
- **TDD:** Wrapper und Guard sind reine Shell-Logik → Self-Tests in `run-tests.sh` zuerst
  (Red → Green), git via Stub (`GH_LOG`/PATH-Stub-Muster aus #80).
- **Portabilität:** nur POSIX-Shell/-Regex, kein PCRE; variable Werte als Daten (`grep -F --`,
  Integer-Guards) – `clean-code.md` „Portabilität in Gate-Skripten" + `bash-gotchas.md` + ADR-010.
- **`gh`-Verbliste** vor Umsetzung gegen die aktuelle `.claude/commands/pr-shepherd.md` gegenprüfen
  (Spec offene Frage 2) – nur tatsächlich genutzte Verben freigeben.
- **stdout/stderr-Hygiene** im Wrapper: Diagnostik auf stderr; Fehler weiterreichen, kein stiller
  „committed aber nicht gepusht"-Zustand.
