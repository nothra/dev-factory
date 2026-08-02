# ADR 041: `config-validation-check.sh` als eigener CI-Required-Check

## Status

Accepted

## Datum

2026-08-02

## Kontext

`scripts/checks/config-validation-check.sh` validiert die geschichtete Factory-Config
(`factory.defaults.yml` * `factory.config.yml`) fail-closed (ADR-009 §B, ADR-010) —
u. a. gegen Tippfehler, unbekannte Keys und die Task-241/249-Policy-Constraints
(Mindest-Tier für `security-review`/`review`, `model_tiers.heavy` nicht override-bar).

Zur **Laufzeit** ist das Gate über `run-pipeline.sh` (`load_config`) verankert. In
**CI** läuft es an keiner Stelle als eigener, benannter Schritt — der einzige
CI-seitige Schutz war bislang eine einzelne Testzeile in
`scripts/checks/tests/run-tests.sh` ("Gate #249 AK5"), die *zufällig* das reale
`factory.config.yml` gegen das Gate laufen lässt. Diese Kopplung ist fragil: ein
künftiges Aufräumen der Testdatei könnte die Zeile entfernen, ohne dass der Verlust
des einzigen realen CI-Schutzes auffällt (Task 255, aufgefallen in der
Security-Review zu Task 249).

ADR-029 (`protect-main`-Ruleset) hält als Gegenmaßnahme zur eigenen Drift-Gefahr
bereits fest: *"Änderungen am Ruleset laufen über einen neuen ADR + den
dokumentierten `gh api`-Befehl."* Da diese Task den Job zusätzlich in die
`required_status_checks` aufnimmt (Entscheidung aus `/requirements`, s.
[spec-255](../specs/spec-255-config-validation-check-ci-verdrahten.md) AK6), greift
dieser Trigger — daher dieses ADR statt einer stillen Ruleset-Änderung.

## Entscheidung

1. **Neuer, eigener CI-Job `config-validation`** in `.github/workflows/factory-ci.yml`
   (Struktur analog zum bestehenden `issue-sync`-Job: `actions/checkout` + minimale
   Prerequisite-Bereitstellung, kein Node/pnpm-Setup). Er ruft
   `config-validation-check.sh` **explizit** mit den Pfaden der realen Repo-Dateien
   auf (`$GITHUB_WORKSPACE/factory.defaults.yml`, `$GITHUB_WORKSPACE/factory.config.yml`),
   unabhängig von `run-pipeline.sh` oder einer Test-Fixture.
2. **`required_status_checks` im `protect-main`-Ruleset** (ADR-029) wird um
   `{ "context": "config-validation" }` erweitert — der Job blockiert damit echte
   Merges nach `main`, nicht nur eine Anzeige. Angewendet über den in ADR-029
   dokumentierten `gh api -X PUT repos/nothra/tch-gastro-services/rulesets/19162920`-
   Befehl; das dort dokumentierte JSON wird im selben Zug aktualisiert.
3. Die dadurch redundante AK5-Testzeile in `run-tests.sh` ("Gate #249 AK5: reales
   factory.config.yml … bleibt gültig") entfällt — der reale CI-Job übernimmt diese
   Absicherung jetzt strukturell statt zufällig.

## Alternativen

### Option A: Zusätzlicher Step im bestehenden `factory-self-test`-Job

**Vorteile:** kein zusätzlicher Job-Overhead, yq ist dort bereits vorhanden.
**Nachteile:** taucht im PR-Checks-UI nicht als eigener, benannter Required-Check
auf, sondern nur als Teilschritt eines Jobs, der schon andere Verantwortlichkeiten
(Self-Test-Suite) trägt — vermischt zwei Zwecke in einem Status-Kontext und macht
den Job bei einem Fehlschlag weniger eindeutig diagnostizierbar (welcher Teilschritt
ist gescheitert?). Verworfen, weil das genau die Sichtbarkeits-Lücke fortschreibt,
die dieses Issue schließen soll.

### Option B: Neuer eigener Job `config-validation` (gewählt)

**Vorteile:** klar benannter, isolierter Required-Check (Single Responsibility,
analog `issue-sync`); ein Fehlschlag ist im PR-UI eindeutig einem Gate zuordenbar;
kein Node/pnpm nötig, daher schnell (nur `checkout` + yq-Download).
**Nachteile:** minimale Redundanz beim yq-Setup (bereits in `factory-self-test`
vorhanden) — vernachlässigbarer Zeilenaufwand gegenüber dem Klarheitsgewinn.

### Option C: Nur CI-Job, kein Ruleset-Update (nicht required)

**Vorteile:** kleinerer, weniger riskanter Schritt (keine GitHub-Settings-Änderung).
**Nachteile:** löst das eigentliche Problem nicht vollständig — ein Job, der nicht
required ist, kann rot sein und der PR wird trotzdem mergebar bleiben (z. B. bei
`gh pr merge --auto`, das nur auf required Checks wartet). Verworfen: die
Motivation der Task ist strukturelle Absicherung, kein rein informativer Check.

## Begründung

Option B + Ruleset-Erweiterung erfüllt das Kernanliegen der Task (Task 255):
struktureller statt zufälliger Schutz. Die Kosten (ein zusätzlicher schlanker Job,
eine dokumentierte Ruleset-Änderung) sind gering und reversibel — passend zur
YAGNI-/Evolutionäre-Architektur-Leitlinie (`architecture-principles.md`): die
Entscheidung ist jederzeit über einen weiteren `gh api -X PUT`-Aufruf rückgängig
machbar.

## Konsequenzen

**Positiv:**
- Ein Policy-verletzender Override in `factory.config.yml` (z. B. ein erneuter
  Versuch, `model_tiers.heavy` zu remappen, Task 249) scheitert jetzt in CI **und**
  blockiert den Merge — unabhängig vom Fortbestand einer bestimmten Testzeile.
- Das Gate ist im PR-Checks-UI als eigener, sofort diagnostizierbarer Eintrag
  sichtbar.

**Negativ / Trade-offs:**
- Ein weiterer required Check erhöht (geringfügig) die Zeit bis ein PR mergebar
  ist (yq-Download, in der Praxis wenige Sekunden).
- Die Ruleset-Definition bleibt wie in ADR-029 beschrieben nur dokumentiert, nicht
  per Tooling gegen den Live-Stand abgeglichen — dieselbe bekannte Drift-Gefahr,
  hier zusätzlich gemildert durch die AK6-Verifikation (`gh api … --jq`-Abgleich)
  im selben PR.
- Die Nicht-Regression gegen das reale `factory.config.yml` läuft **doppelt**: als
  CI-Required-Check (Job `config-validation`) und als Behavior-Level-Test in
  `run-tests.sh` (AK2, realer Aufruf gegen `factory.defaults.yml`/`factory.config.yml`).
  Letzterer ist nicht Teil des lokalen `pre-push.sh`-Gates (das ruft nur `pnpm test`,
  nicht `run-tests.sh`) – lokales Feedback vor Push gibt es dafür nur manuell oder
  über den `factory-self-test`-CI-Job.

## Bezug zu anderen ADRs

- **ADR-029** (Branch-Protection-Ruleset `protect-main`): dieses ADR erweitert
  dessen `required_status_checks`-Liste um `config-validation`; ADR-029s
  dokumentiertes JSON wird im selben PR nachgezogen (siehe dortiger Abschnitt
  „Konfiguration (reproduzierbar)").
- **ADR-009 / ADR-010** (Geschichtete Config, fail-closed Validierung): dieses ADR
  ändert nichts an den Validierungsregeln selbst, nur an deren CI-Verdrahtung.
- **ADR-038** (Größenabhängige Modell-Tier-Wahl) / Task 241 / Task 249: die
  Policy-Constraints, die `config-validation-check.sh` durchsetzt und die dieser
  neue CI-Job jetzt strukturell schützt.
