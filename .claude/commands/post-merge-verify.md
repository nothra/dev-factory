# /post-merge-verify – Verhalten nach dem Merge prüfen

Verifiziert, dass die gemergte Änderung in der **echten Umgebung** funktioniert –
nicht nur im CI-Sandbox. CI-grün ≠ Produktion-grün (ADR-007).

> **Wann:** nach dem Merge auf `main` / nach einem Deployment. In der CI läuft das
> automatisch als `verify`-Stage auf dem Default-Branch.

## Kontext laden

- `docs/factory/PROJECT-CONTEXT.md` – Deploy-Ziel, Healthcheck-Endpunkt
- Konfiguration: `FACTORY_HEALTHCHECK_CMD` (beliebiger Smoke-Test, Vorrang) oder
  `FACTORY_HEALTHCHECK_URL` (+ `FACTORY_HEALTHCHECK_STATUS`, Default 200)
- Retry gegen Deploy-Lag: `FACTORY_HEALTHCHECK_RETRIES` (Default 3) + `FACTORY_HEALTHCHECK_INTERVAL`
  (Default 10s, linearer Backoff). Erfolg beim 1. Versuch bleibt schnell.

## Ablauf

Deterministisch – die Bash prüft, der Agent interpretiert nur das Ergebnis.

### Schritt 1: Healthcheck ausführen

```bash
bash scripts/post-merge-verify.sh <task-id>
```

- **URL nicht gesetzt:** wird übersprungen (exit 0). Das Template hat kein Deploy-Ziel –
  adoptierte Projekte setzen `FACTORY_HEALTHCHECK_URL` als CI/CD-Variable.
- **Healthcheck OK:** exit 0, fertig.
- **Healthcheck fehlgeschlagen:** das Skript löst einen `POST_MERGE_FAIL`-Interrupt aus
  (`raise-interrupt.sh`) und beendet mit exit 1 → CI rot, Eintrag im `interrupt-log.jsonl`.

### Schritt 2 (bei Fehler): Triagieren

- Ist das Deployment durchgelaufen? Richtige Version live?
- Healthcheck-Endpunkt korrekt / erreichbar?
- Echtes Regressions-Symptom → Rollback erwägen, dann erneut verifizieren.

### Schritt 3: Eigene Smoke-Szenarien (projektspezifisch)

Das Skript liefert das Healthcheck-Gerüst. Kritische Akzeptanzszenarien gegen die
laufende Umgebung ergänzt jedes Projekt selbst (z. B. Login-Flow, zentrale API-Route).

## Regeln

- Kein „grün durch Überspringen" verschleiern: ist keine URL konfiguriert, klar als
  übersprungen ausweisen (das tut das Skript).
- Fehler eskalieren immer über `raise-interrupt.sh` (Typ `POST_MERGE_FAIL`), nie still schlucken.

## Output

- Healthcheck-Ergebnis (OK / übersprungen / fehlgeschlagen)
- Bei Fehler: `POST_MERGE_FAIL`-Interrupt im `tasks/interrupt-log.jsonl` + rote Pipeline

## Hinweis für Stage 3 / CI

Läuft als `verify`-Stage in `.gitlab-ci.yml` automatisch auf dem Default-Branch
(nach Merge). Kein interaktiver Fluss nötig – Eskalation deterministisch über den
Interrupt-Mechanismus (ADR-004/ADR-007).
