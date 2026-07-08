# ADR 007: Post-Merge-Verifikation als CI-on-main-Pattern

## Status
Accepted

## Datum
2026-06-17

## Kontext

Die Factory-Pipeline (`run-pipeline.sh`) endet bei „merge-ready": implementiert,
reviewt, getestet, security-geprüft, codifiziert. Damit ist der **Code** verifiziert –
nicht aber das **Verhalten der laufenden Software** nach dem Deployment. „CI grün"
heißt „Tests bestanden im CI-Sandbox", nicht „funktioniert in der echten Umgebung".

Die Gap-Analyse benennt den fehlenden **Post-Merge Verify** als eigene Lücke (Issue #11):
„Kein Äquivalent – keine Verifikation nach dem Merge." Eine echte Dark Factory bestätigt
das Verhalten in der realen Umgebung, nicht nur im Test.

Offene Fragen beim Schneiden:
1. **Wo** läuft die Verifikation – als weitere `run-pipeline.sh`-Phase oder als CI-Job?
2. **Wie** verhält sich ein Template ohne Deploy-Umgebung?

## Entscheidung

**Post-Merge-Verifikation läuft als CI-Job, gated auf den Default-Branch** – d. h.
nach dem Merge auf `main`, nicht als Phase in `run-pipeline.sh`.

```yaml
post-merge-verify:
  stage: verify
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH && $CI_PIPELINE_SOURCE == "push"'  # nur nach Merge
```

`scripts/post-merge-verify.sh` macht einen Healthcheck gegen `FACTORY_HEALTHCHECK_URL`
(erwarteter Status via `FACTORY_HEALTHCHECK_STATUS`, Default 200). Bei Fehler wird über
`raise-interrupt.sh` ein **neuer Interrupt-Typ `POST_MERGE_FAIL`** ausgelöst (reuse des
Mechanismus aus ADR-004) und der Job läuft rot. Der Interrupt landet im append-only
`tasks/interrupt-log.jsonl` (aus #12) – damit ist Post-Merge-Versagen dieselbe
auditierbare Eskalationskette wie alle anderen Interrupts und Quelle für den künftigen
Incident-Response-Agenten (#15).

**Skelett-Charakter (bewusst):** Das Template hat kein Deploy-Ziel. `post-merge-verify.sh`
liefert daher das *Gerüst* – Healthcheck + Interrupt-Eskalation –, das adoptierte Projekte
über `FACTORY_HEALTHCHECK_URL` (und später eigene Smoke-Szenarien) konkretisieren.

**„skip vs. fail" – bewusste Abweichung von lint/test:** Ohne `FACTORY_HEALTHCHECK_URL`
wird **übersprungen** (laute Warnung, exit 0), nicht fail-closed. Begründung: Anders als
Lint/Test (die jedes Projekt hat) ist eine Healthcheck-URL nicht universell – ein Projekt
ohne HTTP-Deploy-Ziel hätte sonst dauerhaft rote `main`-Pipelines. Sobald eine URL gesetzt
ist, ist der Check ein echtes Gate.

## Alternativen

### Option B: Als Phase 8 in `run-pipeline.sh`
**Abgelehnt:** `run-pipeline.sh` läuft *vor* dem Merge. Zu diesem Zeitpunkt ist nichts
deployt – es gäbe nichts zu verifizieren. Post-Merge-Verifikation gehört zwingend hinter
den Merge, und der natürliche Trigger dafür ist die CI auf `main`.

### Option C: Fail-closed wie lint/test (exit 1 ohne URL)
**Abgelehnt:** würde jedes Template-Derivat ohne Deploy-Ziel mit dauerhaft roter
`main`-Pipeline bestrafen. Die Universalitäts-Annahme von lint/test gilt hier nicht.

### Option D: Externes Monitoring-Tool statt Skript
**Abgelehnt (für jetzt):** sinnvoll für Produktion, aber out-of-scope fürs Template. Das
Skript-Skelett ist der Einstiegspunkt; ein echtes Monitoring kann später andocken (#15).

## Konsequenzen

**Positiv:**
- Schließt die Lücke zwischen Code-Korrektheit (CI) und Laufzeit-Verhalten.
- Reuse statt Neubau: `raise-interrupt.sh` + Interrupt-Log sind die Eskalations-/Audit-Kette.
- Adoptierte Projekte erben den Hook automatisch; aktivieren = eine CI/CD-Variable setzen.

**Negativ / Trade-offs:**
- Skelett ohne echte Smoke-Szenarien – nur Healthcheck. Bewusst: Szenarien sind projektspezifisch.
- Der `POST_MERGE_FAIL`-Interrupt-Sentinel ist im CI-Workspace ephemer; die persistente Spur
  ist der Log-Eintrag (lokal) bzw. die rote Pipeline (CI). Für ein Skelett akzeptiert.

## Erweiterung: pluggbarer Check (#23)

Der reine HTTP-Healthcheck (`== $EXPECT`) belegt nur „Prozess lebt", nicht „funktioniert".
`FACTORY_HEALTHCHECK_CMD` ergänzt daher einen **beliebigen Smoke-Test, dessen Exit-Code das
Urteil ist** (0 = OK). Deckt nicht-HTTP-Projekte ab (CLI, Worker) und mehrstufige Szenarien.

**Vorrang:** Ist `CMD` gesetzt, gewinnt es; sonst `URL` (bequemer Default). Beides leer →
übersprungen (skip-vs-fail unverändert). Der Fehlerpfad ist für beide identisch — eine
gemeinsame `fail()`-Funktion löst den `POST_MERGE_FAIL`-Interrupt aus.

## Erweiterung: Retry/Poll gegen Deploy-Lag (#24)

Direkt nach dem Merge ist das Deployment evtl. noch nicht live — ein einzelner Check würde
dann einen `POST_MERGE_FAIL` auslösen, obwohl nur der Rollout nachhinkt (häufigste
Fehlalarm-Quelle im Betrieb). Der Check wird daher bis zu `FACTORY_HEALTHCHECK_RETRIES`-mal
(Default 3) wiederholt, mit linearem Backoff `FACTORY_HEALTHCHECK_INTERVAL` (Default 10s →
10/20/30s). **Erfolg beim ersten Versuch bleibt schnell** (kein künstliches Warten); erst wenn
alle Versuche scheitern, gilt es als fehlgeschlagen. Gilt für URL- und CMD-Check gleichermaßen.

## Betroffene Stellen
- `scripts/post-merge-verify.sh` – Healthcheck (URL) + Smoke-Command (CMD) + POST_MERGE_FAIL
- `.gitlab-ci.yml` – Stage `verify`, Job nur auf `$CI_DEFAULT_BRANCH` (push)
- `.claude/commands/post-merge-verify.md` – Skill-Wrapper
- `scripts/checks/tests/run-tests.sh` – Verhaltenstests (skip / URL-fail / CMD-ok / CMD-fail)
