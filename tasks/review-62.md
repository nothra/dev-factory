# Review: Task 62

> Runde 2 (2026-11-24, Re-Review nach Rework `4c2f230`). Docs-only-Diff (`CHANGELOG.md`, `docs/factory/OPERATING.md` §0.7 +
> §5.5a, Factory-ADR-029 Nachtrag, Factory-ADR-063 Rückverweise, Spec) gegen
> `docs/specs/spec-62-adr-029-nachtrag-factory-integrity.md`. Drei Runden (Logik, Qualität, Architektur). `pre-commit.sh` grün.
> Runde 1: NEEDS_REWORK (0 kritisch, 2 wichtig, 5 Nitpicks); beide wichtigen Findings und vier Nitpicks sind behoben, der
> fünfte bleibt bewusst offen (Stil der Nachbareinträge).

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

_(keine)_

## Nitpicks (optional)

- [ ] [docs/factory/adr/029-branch-protection-main-ruleset.md:233-240] Den eigentlichen Grund für „erst mergen" ausdrücklich
  nennen: Vor dem Einbindungs-Merge hilft den hängenden PRs ein Rebase nicht, weil `main` den Job noch nicht enthält. Erst nach
  dem Merge reicht das Rebasen als Abhilfe. Der Text ergibt das nur indirekt aus „Den Check meldet nur ein PR, dessen Branch
  den Job enthält". Ein Halbsatz genügt. Auf ihn verweist §0.7 („Abhilfe bei zu frühem Eintragen").
- [ ] [docs/factory/adr/029-branch-protection-main-ruleset.md:236-237] „Das gilt auch bei richtiger Reihenfolge für PRs, die
  beim Eintragen schon offen sind" ist etwas zu breit. Betroffen sind nur offene PRs, die **vor** der Einbindung abgezweigt
  sind. Später abgezweigte PRs enthalten den Job. §0.7 Schritt 4 formuliert das schon präzise.
- [ ] [docs/factory/OPERATING.md:253, docs/factory/adr/029-branch-protection-main-ruleset.md:238] „bei Factory-PRs über
  `/pr-shepherd`" ist im Konsumenten-Kontext mehrdeutig (PRs der Pipeline oder Update-PRs der Factory?). Präziser wäre
  „bei Pipeline-PRs".

## Außerhalb des Scopes

- **[docs/factory/OPERATING.md, Anhang „Branch-Protection richtig einordnen"]** (aus Runde 1, unverändert offen): Der Anhang
  nennt Branch-Protection optional bzw. mit niedriger Priorität. Das widerspricht ADR-029 und §0.7. Schwelle: Zweifelsfall,
  also Issue. **Issue weiterhin nicht angelegt**, weil die Anlage über `scripts/lib/create-issue.sh` nicht freigegeben ist.
  Sie muss vor dem PR nachgeholt werden (Labels `documentation` + `tech-debt`).

## Positives

- Die Aussage aus Runde 1 ist korrigiert: Es hängt jeder PR, dessen Branch den Job nicht enthält. Die Begründung
  (`pull_request` nimmt die Workflow-Datei aus dem PR-Stand) steht dabei. ADR, §0.7, CHANGELOG und Spec AK3/FS1 sagen jetzt
  dasselbe.
- Offene Alt-PRs stehen als eigener Schritt 4 mit Abhilfe in §0.7. Die Wirkung von `strict: false` ist im ADR erklärt.
- Die Aufteilung ist sauber: §0.7 enthält nur die Bedienschritte, Begründung, Abhilfe und Notfall stehen kanonisch im ADR.
  Das senkt das Drift-Risiko.
- „Release-Manifest" heißt jetzt überall gleich. ADR-063 hat an beiden Stellen einen Rückverweis. Die Decision-Liste in
  ADR-029 nennt `factory-integrity` mit Verweis auf den Nachtrag.
- Der UI-Hinweis „Name lässt sich eintippen" räumt das Missverständnis „muss vorher gelaufen sein" aus.
- Anker geprüft: `#07-required-check-factory-integrity-eintragen-je-konsumenten-repo-nach-dem-ersten-merge`,
  `#konfiguration-reproduzierbar` und der Rückbezug „Fail-closed statt Vertrauen" (ADR-029:112) lösen auf.
- Alle AKs bleiben erfüllt. Text konsumenten-neutral, Herkunftsverweise qualifiziert, keine neue getrackte Datei,
  `FACTORY.md` unverändert.

## Empfehlung
APPROVED
