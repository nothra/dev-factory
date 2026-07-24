# ADR 040: Deterministische Endzustands-Verifikation der Pipeline (agenten-signal-unabhängiger Backstop)

## Status

Accepted

## Datum

2026-07-23

## Kontext

`scripts/run-pipeline.sh` orchestriert die Stage-3-Pipeline und meldet am Ende
„Pipeline erfolgreich abgeschlossen" / „Task N ist fertig". Diese Erfolgs-Ausgabe
hängt heute an zwei nicht vertrauenswürdigen Signalen:

1. **Exit-Code des Skill-Aufrufs:** `run_skill()` protokolliert `✓ /<skill> abgeschlossen`
   allein aufgrund des Exit-0 von `claude --print` (`run-pipeline.sh:250`).
2. **Report-Dateitext:** `pipeline_summary()` liest die Report-Dateien
   (task/review/security/codify) und spiegelt deren Inhalt (`run-pipeline.sh:319`).

Keines davon prüft den **realen** Endzustand des Repositories/PRs.

ADR-004 führte den Interrupt-Mechanismus ein: Ein Agent, der eine nicht
automatisierbare Entscheidung erkennt, ruft `raise-interrupt.sh` auf (Sentinel),
`interrupt-check.sh` stoppt die Pipeline deterministisch. ADR-004 benennt aber
selbst den offenen Trade-off:

> „Ob der Agent in Stage 3 tatsächlich `raise-interrupt.sh` aufruft, bleibt
> Model-Best-Effort."

Die deterministische Garantie lautet also nur: **„Sentinel existiert → Stopp."** Sie
sagt nichts über den Fall, in dem **kein** Signal gesetzt wird, der Agent aber die
Arbeit nicht abgeschlossen hat.

Genau dieser Fall trat in #212 ein (Lauf `PR_SHEPHERD=true … 209`): `/pr-shepherd`
traf auf ein den Push-Gate blockierendes getracktes Artefakt und **fragte interaktiv
nach Freigabe**, statt zu eskalieren. Da niemand antwortete, endete der `--print`-Lauf
mit Exit 0, kein Sentinel wurde geschrieben – die Pipeline meldete Erfolg, obwohl der
PR (#210) Draft/ungemergt war und zwei Commits ungepusht vorlagen.

Verwandt mit #211 (dort las die Verdict-Erkennung Fließtext statt der Anker-Zeile).
Beide Vorfälle sind Instanzen desselben Musters: **Die Pipeline behauptet Erfolg auf
Basis eines Proxy-Signals statt des beobachteten realen Zustands.**

Es braucht einen **deterministischen, agenten-signal-unabhängigen Backstop**, der den
realen Endzustand verifiziert, bevor Erfolg gemeldet wird.

## Entscheidung

Eine neue **Endzustands-Verifikation** als eigenständiges, deterministisches Gate am
Ende von `run-pipeline.sh` – ausgeführt **unmittelbar vor** der Erfolgs-Ausgabe und
unabhängig von jedem Agenten-Signal:

1. **Quelle ist die beobachtete Realität, nicht Report-Text.** Der Zustand wird über
   `git`/`gh` gelesen:
   - **Beide Modi:** Working Tree sauber **und** keine ungepushten Commits
     (`git rev-list origin/<branch>..HEAD` leer).
   - **Zusätzlich bei `PR_SHEPHERD=true`:** PR **nicht** Draft **und** PR gemergt
     **oder** Auto-Merge scharfgeschaltet (`autoMergeRequest` gesetzt). „Merge-ready"
     zählt bewusst als Erfolg – die Pipeline wartet nicht aktiv auf server-seitige CI.

2. **Fail-closed.** Ist eine Invariante verletzt **oder** ein `git`/`gh`-Aufruf nicht
   verwertbar (Fehler, kein Upstream), gilt der Zustand als **nicht verifiziert**: die
   Erfolgs-Ausgabe unterbleibt, der konkrete reale Zustand wird gemeldet, und der Lauf
   endet mit Non-Zero-Exit.

3. **BLOCKED wird als Interrupt geloggt.** Eine Verifikations-Verletzung stoppt über
   denselben Mechanismus wie ADR-004: Aufruf von `raise-interrupt.sh <id>
   INCOMPLETE_OUTCOME "<realer Zustand>"`. Damit ist der Stopp deterministisch,
   erscheint im append-only `interrupt-log.jsonl` und zählt korrekt gegen die
   Autonomie-Rate (ADR-006) – ein Lauf, der menschliches Eingreifen brauchte, wird
   nicht als voll-autonom verbucht.

4. **`--dry-run` überspringt die Verifikation** (bzw. markiert sie als DRY-RUN) und
   bricht den Dry-Run nicht ab.

5. **Testbarkeit.** Die Verifikationslogik wird als reine, sourcebare Funktion
   ausgelagert (analog `scripts/lib/report-verdict.sh`, `tier-select.sh`), sodass sie
   im Shell-Test-Harness ohne echtes Repo/GitHub geprüft werden kann – `git`/`gh`
   werden als injizierbare Kommandos behandelt (Stub via PATH-Shim bzw. Parameter).

**Komplementär zur Agenten-Seite (nicht ersetzend):** Der Anker in
`.claude/commands/pr-shepherd.md` wird geschärft, sodass ein nicht autonom lösbarer
Blocker unter `FACTORY_STAGE=3` zu `raise-interrupt.sh` führt statt zu einer
interaktiven Frage (und kein autonomes `git rm --cached` o. Ä.). Das bleibt die
nicht-deterministische Schicht (Model-Best-Effort, ADR-004); die neue Verifikation ist
der deterministische Backstop, falls diese Schicht versagt. Defense in depth.

Diese Entscheidung **ändert ADR-004 nicht**, sondern ergänzt sie: ADR-004 stoppt *auf
Signal*, ADR-040 stoppt *auf beobachteten Zustand ohne Signal*.

## Alternativen

### Option A: Deterministische Endzustands-Verifikation via `git`/`gh` (gewählt)

**Vorteile:** Unabhängig vom Modellverhalten; prüft die echte Wahrheit
(Push-/PR-/Merge-Zustand); fail-closed; fängt **auch künftige, heute unbekannte**
Agenten-Fehlverhalten ab; testbar ohne echte Infrastruktur; konsistent mit dem
Factory-Muster „Skript garantiert, Agent signalisiert".
**Nachteile:** Zusätzliche `git`/`gh`-Abhängigkeit im Abschlusspfad; Verifikations-
Regeln müssen den beiden Modi (PR_SHEPHERD an/aus) folgen.

### Option B: Skill-Output/Transkript auf offene Freigabefragen parsen

`run-pipeline.sh` greppt den gestreamten Output nach „May I", „approval" etc. und
markiert BLOCKED.
**Nachteile:** Brüchig – exakt das Anti-Muster, das ADR-004 (Option A: stdout-Marker)
bereits verworfen hat. Frei-Text-Erkennung erzeugt False Positives/Negatives, ist
sprach-/formulierungsabhängig und prüft weiterhin nicht den realen Zustand.
**Abgelehnt.**

### Option C: Nur die Agenten-Seite härten (pr-shepherd eskaliert statt zu fragen)

**Nachteile:** Lässt den von ADR-004 benannten Model-Best-Effort-Spalt offen; #212
belegt, dass der Anker allein nicht genügt. Keine deterministische Garantie.
**Abgelehnt** als alleinige Maßnahme (bleibt aber als komplementäre Schicht, s. o.).

### Option D: Positives „Done"-Sentinel je Skill statt Exit-0-Vertrauen

Jeder Skill müsste ein Erfolgs-Sentinel schreiben; `run_skill()` verlangt es.
**Nachteile:** Schwergewichtiger (alle Skills + Persona anpassen), mehr bewegliche
Teile – und es verifiziert weiterhin nur, dass der Agent sich für fertig *hält*
(dasselbe unzuverlässige Signal), nicht den realen PR-/Push-Zustand. **Abgelehnt.**

## Begründung

Der wiederkehrende Fehler (#211, #212) ist, dass die Pipeline **Proxy-Signale** (Exit-
Code, Report-Text) mit **Wahrheit** verwechselt. Die einzige robuste Abhilfe ist, die
Wahrheit direkt zu beobachten – `git`/`gh` sind die kanonischen Quellen für Push-/PR-/
Merge-Zustand. Die Garantie liegt damit im Skript und ist unabhängig vom
Modellverhalten – dieselbe Trennung wie bei ADR-004 (Skript erkennt & stoppt
deterministisch) und ADR-019 (Report-Guard an einem Ort). Fail-closed folgt der
Factory-Grundhaltung für Gates: im Zweifel ablehnen, nie still durchwinken.

Die Wahl „merge-ready ODER gemergt" balanciert Determinismus gegen Praktikabilität:
Ein unbeaufsichtigter Lauf kann nicht beliebig auf server-seitige CI warten;
„Auto-Merge scharf + alles gepusht + kein Draft" ist ein wohldefinierter, prüfbarer
Übergabepunkt an GitHub.

## Konsequenzen

**Positiv:**

- Kein „Erfolg trotz Draft-PR / ungepushter Commits" mehr – deterministisch verhindert.
- Fängt generisch auch unbekannte künftige Fehlverhalten ab (nicht #212-spezifisch).
- Autonomie-Rate (ADR-006) bleibt ehrlich: verifikationsbedingte Stopps werden geloggt.
- Ohne echte Infrastruktur testbar (sourcebare Funktion, gestubbte `git`/`gh`).
- ADR-004/019 bleiben unverändert gültig; 040 ist eine additive Schicht.

**Negativ / Trade-offs:**

- `run-pipeline.sh` bekommt eine `gh`-Abhängigkeit auch im Nicht-PR_SHEPHERD-Abschluss
  (nur für die git-Invarianten; `gh` nur bei `PR_SHEPHERD=true`).
- Die Verifikationsregeln sind ein weiterer Ort, der mit dem PR-Lifecycle (Draft/
  Auto-Merge-Semantik, vgl. ADR-030) konsistent bleiben muss.
- „Merge-ready zählt als Erfolg" heißt: der finale server-seitige Merge kann noch
  scheitern (rote CI nach Übergabe). Das ist bewusst außerhalb des Pipeline-Laufs und
  wird von `/post-merge-verify` (ADR-007) abgedeckt.
