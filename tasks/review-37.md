# Review: Task 37

> Iteration 3 (Circuit Breaker: dritte Anwendung auf diesen Branch). Der Code von `scripts/` und `.github/` ist seit
> Iteration 2 unverändert (`git diff 02b1e25..HEAD` berührt nur ADR-063, `OPERATING.md`, die Task-Datei und Doku-Guard-Anker in
> `factory-lock-tests.sh`) – kein ungelöster Konflikt, daher keine Eskalation nötig; Hinweis an den Menschen im Übergabetext.
> Runden 1–3 direkt im Orchestrator-Kontext. Testgruppe grün (463 / 0), Pre-Push-Gate am Rework-Commit grün.
> **Iteration 2 – umgesetzt:** ADR-063 E18 und `OPERATING.md` §0.6 nennen „keine geschützten Stellen im Manifest“; Doku-Guard-Anker
> in `ops_ok_37`/`adr_ok_37` mit je einer Mutation (erst rot, dann grün).

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_

## Nitpicks (optional)
- [ ] scripts/factory-update.sh:177 (`verify_bundle`, ~60 Zeilen) – Aufteilung in kleine Funktionen (Bundle laden, Manifest prüfen, Pfade/Modi prüfen, Hashes prüfen); Clean-Code-Pass, gehört zu `/refactor` (kein neues Verhalten).
- [ ] scripts/checks/tests/factory-lock-tests.sh (`PROT_37`) – einzeiliges, stark escaptes Fixture-Snippet als benannte Funktion lesbarer machen; `/refactor`.

## Positives
- Alle Findings aus Iteration 1 und 2 behoben und je mit Test plus Mutationsbeleg belegt; Doku (ADR-063 E17–E22, `OPERATING.md` §0.6, Spec AK-37d, CHANGELOG) deckt sich mit dem Code.
- Trennung von Token und Release-Code an Job-/Prozessgrenzen, fail-closed Prüfliste in `publish`, Commit per `commit-tree` neu erzeugt; Restrisiko im ADR ehrlich benannt.
- Menschliche Schritte (Environment `factory-update`, Secret-Umzug, Beleg am echten Repo Q-37.3) sind als solche markiert und nicht als erledigt ausgegeben.

## Empfehlung
APPROVED
