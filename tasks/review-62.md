# Review: Task 62

> Docs-only-Diff (`CHANGELOG.md`, `docs/factory/OPERATING.md` §0.7 + §5.5a, Factory-ADR-029 Nachtrag) gegen
> `docs/specs/spec-62-adr-029-nachtrag-factory-integrity.md`. Drei Runden (Logik, Qualität, Architektur), Review-Datum
> 2026-11-24. `pre-commit.sh` grün (Runde 2).

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] [docs/factory/OPERATING.md:253-254, docs/factory/adr/029-branch-protection-main-ruleset.md:233-235, CHANGELOG.md:25-26]
  Die Aussage „vorher eingetragen hängt jeder PR – auch der Einbindungs-PR" ist sachlich falsch. `factory-ci.yml:18-20` triggert
  auf `pull_request` ohne Pfadfilter, `factory-integrity` (`:81`) hat kein `if:`, und bei `pull_request` nimmt GitHub die
  Workflow-Datei aus dem PR-Stand. Der Einbindungs-PR bringt den Job mit und meldet den Check `factory-integrity` (Job-ID, kein
  `name:`) also selbst. Auf „Expected – Waiting for status" hängt jeder PR, **dessen Branch den Job noch nicht enthält**
  (vor der Einbindung abgezweigt). Auch „muss auf `main` mindestens einmal gelaufen sein" ist keine technische Voraussetzung:
  Im Ruleset kann man den Namen frei eintippen, die UI schlägt nur kürzlich gelaufene Checks vor. Die Reihenfolge „erst mergen"
  bleibt richtig, die Begründung muss aber präzise sein. Fix: an allen drei Stellen „jeder PR, dessen Branch
  `factory-integrity` noch nicht enthält" statt „jeder PR – auch der Einbindungs-PR"; Abhilfe „Branch gegen `main` rebasen"
  ergänzen (Behebung „Check austragen" bleibt als Alternative). **Spec mitziehen:** Fehlerszenario 1
  (`spec-62…md:71-72`, „auch der Einbindungs-PR") und AK3 (`:48-49`) tragen dieselbe Aussage; die Spec-Änderung sollte der
  Mensch bestätigen (Phase 1).
- [ ] [docs/factory/OPERATING.md:244-251] Es fehlt der Hinweis auf PRs, die beim Eintragen schon offen sind. Auch bei richtiger
  Reihenfolge hängen PRs, die vor dem Einbindungs-Merge abgezweigt sind; das Ruleset erzwingt mit `strict: false` kein Update.
  Abhilfe: gegen `origin/main` rebasen (bei Factory-PRs über `/pr-shepherd`). Gehört zu Fehlerszenario 1 der Spec, ein Satz in
  Schritt 2 oder im Absatz „Zu früh eingetragen" genügt.

## Nitpicks (optional)

- [ ] [docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md:266, :541] ADR-063 sagt noch „(ADR-029 nachtragen)"
  bzw. „trägt ihn T2a-4 ins Ruleset ein". Ein Rückverweis „(nachgetragen in Factory-ADR-029, 2026-11-24, #62)" schließt den
  Kreis (Nachtrags-Muster von ADR-063). Gleiche Datei-Familie, zwei Zeilen; kann in diesem PR mit.
- [ ] [docs/factory/OPERATING.md:256 vs. docs/factory/adr/029-branch-protection-main-ruleset.md:236] Begriff vereinheitlichen:
  „Manifest" vs. „Release-Manifest" (§5.5a und ADR nutzen „Release-Manifest").
- [ ] [docs/factory/OPERATING.md:244-258 / docs/factory/adr/029-branch-protection-main-ruleset.md:232-240] Reihenfolge,
  „zu früh eingetragen" und Notfall stehen inhaltlich doppelt, das kann auseinanderlaufen. Vorschlag: der ADR ist kanonisch
  für Entscheidung und Notfall-Regel, §0.7 behält die Bedienschritte und verweist für Notfall und Begründung auf den ADR (wie
  schon beim `gh api`-Befehl).
- [ ] [docs/factory/adr/029-branch-protection-main-ruleset.md:44-45] Die Decision nennt den Nachtrag ADR-041 inline in der
  Check-Liste, diesen nicht. Optional ein Halbsatz „im Konsumenten zusätzlich `factory-integrity` (s. Bezug zu anderen ADRs)".
  ADR-064 hat das auch nicht getan, das Muster ist also schon uneinheitlich.
- [ ] [docs/factory/adr/029-branch-protection-main-ruleset.md:223] Die Spec AK1 nennt „Factory-ADR-063 / …", der Eintrag
  heißt „ADR-063 / …". Folgt dem Stil der Nachbareinträge, nur ein formaler Unterschied, keine Änderung nötig.

## Außerhalb des Scopes

- **[docs/factory/OPERATING.md:657-676] Anhang „Branch-Protection richtig einordnen"** (älter als dieser PR, Schwelle:
  Zweifelsfall, deshalb Issue). Er nennt Branch-Protection „optionale `main`-Hygiene", „Priorität: niedrig", „Komfort
  obendrauf". Das widerspricht ADR-029 und jetzt auch direkt §0.7: Das Integritäts-Gate schützt nur mit Ruleset. Der Anhang
  ist zudem projektspezifisch (`production`-Branch, E2E-Deploy-Gate) in einer ausgelieferten Datei. Der Fix braucht mehr als
  zehn Zeilen und eine Entscheidung, was generisch bleibt. **Issue nicht angelegt:** Die Anlage über
  `scripts/lib/create-issue.sh` wurde in dieser Session nicht freigegeben. Vermerkt hier statt still verworfen
  (`kleinfunde.md`-Kopf). Vorbereiteter Aufruf (Labels `documentation` + `tech-debt`) liegt im Session-Scratchpad und muss
  nachgeholt werden.

## Positives

- Alle Akzeptanzkriterien sind formal abgedeckt. Factory-Repo und Konsument sind sauber getrennt, die Check-Liste des
  Factory-Repos ist identisch mit dem ADR-064-Eintrag.
- Das JSON bleibt unverändert und wird ausdrücklich als Stand des Ursprungs-Rulesets benannt. Status `Accepted` und
  ADR-Index-Zeile 029 stimmen.
- „Nachtrag statt neuer ADR" passt zur Gegenmaßnahme in ADR-029:144: Der neue ADR ist ADR-063 E8, dasselbe Muster wie bei
  ADR-041 und ADR-064.
- Der Text ist konsumenten-neutral: Platzhalter `<owner>/<repo>`/`<ruleset-id>` samt Befehl, der die ID liefert, und
  „zusätzlich zu den bestehenden Checks" statt einer Zählung. Herkunftsverweise sind nur qualifiziert.
- Der jq-Ausdruck des Soll-Ist-Abgleichs passt zur Form der Rulesets-API. Die Erwartung prüft ausdrücklich, dass
  `enforcement`, `bypass`, `strict` und `merge` unverändert bleiben.
- Die Exit-Codes und das No-op in §5.5a stimmen mit `factory-integrity-check.sh` überein. Die Anker `#07-…` und
  `#konfiguration-reproduzierbar` lösen auf.
- Das Notfallverfahren nennt die Dokumentationspflicht (Ursache, Zeitraum, gemergte PRs) und entschärft das Gate nicht
  dauerhaft.
- Keine neue Zeile in `OWNERSHIP.md` nötig (Spec/Task fallen unter `docs/specs/**` bzw. `tasks/**`). `FACTORY.md` bleibt
  unverändert, der Import-Deckel ist also nicht betroffen.

## Empfehlung
NEEDS_REWORK
