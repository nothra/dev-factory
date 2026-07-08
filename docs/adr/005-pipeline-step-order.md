# ADR 005: Kanonische Pipeline-Reihenfolge – Security-Review als letztes Gate vor Merge

## Status
Accepted

## Datum
2026-06-16

## Kontext

Die Pipeline-Schritte `refactor` und `security-review` standen in drei Quellen in
widersprüchlicher Reihenfolge:

- `scripts/run-pipeline.sh` (ausgeführter Code): `test → security-review → refactor → codify`
- `CLAUDE.md` (Pipeline-Übersicht): `test → refactor → security-review → codify`, mit dem
  Kommentar „Security-Check vor Merge"
- `README.md` (Beispiel): `security-review → refactor`, und `/test` fehlte dort ganz

Die Reihenfolge in `run-pipeline.sh` existierte unverändert seit dem Initial-Commit des
Templates und war **nie über eine ADR entschieden**. Keine Spec, keine Guideline und keine
der Agent-Personas begründet sie. Die einzige dokumentierte *Absicht* (`CLAUDE.md`) widersprach
dem ausgeführten Code. Es brauchte eine bewusste Entscheidung, damit die Reihenfolge nicht
weiter zwischen den Quellen driftet.

## Entscheidung

Die kanonische Reihenfolge ist:

```
implement → review (↔ implement) → test → refactor → security-review → codify
```

**Security-Review ist das letzte Gate vor dem Merge** und läuft **nach** dem Refactoring.

Begründung: Das Security-Gate muss exakt den Code prüfen, der gemergt wird. Refactoring ist
eine Code-Änderung – es kann Security-Invarianten verletzen (z. B. eine Validierung beim
Extrahieren einer Methode verlieren), ohne dass die Tests das bemerken: „Tests grün"
garantiert *Verhalten*, nicht *Sicherheit*. Liefe der Security-Review vor dem Refactoring,
würde der finale, gemergte Code nie security-reviewed – eine echte Prozesslücke.

Das deckt sich mit der bereits dokumentierten Absicht in `CLAUDE.md` („Security-Check vor
Merge"). Geändert wird daher der Code (`run-pipeline.sh`) und das README-Beispiel; `CLAUDE.md`
war bereits korrekt.

## Alternativen

### Option B: Security-Review vor Refactoring (Status quo des Codes)
`test → security-review → refactor → codify`.
**Vorteil:** Fail-fast – Security-Probleme stoppen die Pipeline (`exit 1`), bevor Aufwand ins
Refactoring fließt.
**Nachteil:** Der finale, refaktorierte Code wird nie security-reviewed. Der Fail-fast-Vorteil
wiegt das nicht auf, zumal das Refactoring ohnehin durch das „Tests nach Refactoring"-Gate
abgesichert ist. Zudem war diese Reihenfolge nie bewusst als Fail-fast-Design entschieden,
sondern eine Scaffolding-Altlast. Abgelehnt.

## Konsequenzen

**Positiv:**
- Das Security-Gate deckt den finalen Merge-Code ab – keine ungeprüfte Code-Änderung vor Merge.
- Code, `CLAUDE.md` und README sind erstmals konsistent und die Reihenfolge ist dokumentiert
  entschieden.

**Negativ / Trade-offs:**
- Schlägt der Security-Review fehl, war ein vorheriges Refactoring evtl. umsonst. Akzeptiert –
  Korrektheit des Merge-Gates wiegt schwerer als gesparter Refactoring-Aufwand im Fehlerfall.

## Betroffene Stellen
- `scripts/run-pipeline.sh` – Phasen 4 (Refactoring) und 5 (Security Review) getauscht
- `README.md` – numeriertes Beispiel (inkl. ergänztem `/test`-Schritt) und Mermaid-Diagramm
- `CLAUDE.md` – bereits korrekt, keine Änderung
