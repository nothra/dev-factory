# Review: Task 24

Review-Iteration 2. Diff-Basis: `git diff origin/main...HEAD` (ce9edf7). Spec:
`docs/specs/spec-24-factory-update-workflow-update-pr.md`, Entscheidungen: Factory-ADR-063 Nachtrag 2026-10-30
(E10–E16). Drei Runden (Logik, Code-Qualität, Architektur) im Orchestrator-Kontext, ohne Fork-Delegation.
Ausgelieferte Suite `scripts/checks/tests/run-tests.sh` lokal: 2091 grün, 0 rot (Exit 0).

Iteration 1 (NEEDS_REWORK) ist vollständig abgearbeitet: K1 (Selbst-Ersatz), W1 (Marke im ganzen Body), N1–N3. Belege
im Rework-Commit ce9edf7: Aufrufzeile `main "$@"; exit $?` mit WHY-Kommentar; E2E-Fall aus dem Konsumenten-Checkout mit
verlängerter Zielversion plus Mutant ohne `exit` (rot); Testfall „Marke in den Notes eines abgelehnten PRs", der gegen
den alten `contains`-Code rot gewesen wäre; `ORIG_REF` neben `WORK`; Welt-Zähler `next_world_24`; Mutanten-Scaffold
`factory_scripts_24` (wiederverwendet statt kopiert).

## Kritische Findings (müssen behoben werden)
_(keine)_

## Wichtige Findings (sollten behoben werden)
- [ ] [docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md:582] **Die ADR beschreibt die Marken-Prüfung noch
  im alten Stand:** „ein geschlossener, nicht gemergter PR dieses Branches trägt **im Body** die Marke". Seit dem Rework
  zählt nur der Kopf des Bodys vor der ersten `## `-Überschrift (`scripts/factory-update.sh:129-131`). Dieser PR ändert
  also die Mechanik, die die ADR beschreibt, und sie muss im selben PR mitgehen (Lesson nothra/tch-gastro-services#211).
  **Fix:** E11.4 um „im Kopf des Bodys (vor der ersten Release-Überschrift aus E13), zitierte Release Notes zählen nicht"
  ergänzen. E13 nennt die feste Reihenfolge schon und ist damit der natürliche Verweis.
- [ ] [docs/specs/spec-24-factory-update-workflow-update-pr.md:130-131] **Spec und ADR versprechen mehr, als der
  Rework jetzt dokumentiert.** FS-T2.3 sagt: „abgelehnt (abgelaufen, **zu wenig Rechte**) … schlägt der Lauf **vor jedem
  weiteren Schritt** fehl". ADR E11.2 (Z. 570-572) sagt sinngemäß dasselbe. Seit N1 hält `OPERATING.md` §0.6 dagegen
  ehrlich fest, dass `permissions.push` vielleicht die Rolle des Token-Besitzers meldet. Ein Token mit zu knappen Rechten
  würde dann erst beim Push bzw. bei `gh pr create` rot. Die Task-Datei hakt FS-T2.3 trotzdem ohne Vorbehalt ab.
  Das ausgelieferte Betriebshandbuch und die Spec widersprechen sich damit (Lessons nothra/tch-gastro-services#253/#388:
  eine im selben PR entstandene Spec bekommt denselben Drift-Check, und eine Abschwächung gehört in die Spec).
  **Fix:** In der Spec bei FS-T2.3 einen Vorbehalt plus Q-Eintrag ergänzen: der Fall „zu wenig Rechte" ist offline
  nicht belegbar, rot bleibt der Lauf in jedem Fall, der Beleg am echten Repo folgt in T2a-4 (`nothra/tch-gastro-services#428`).
  ADR E11.2 entsprechend nachziehen und die Task-Datei bei FS-T2.3 auf die Einschränkung verweisen lassen.

## Nitpicks (optional)
- [ ] [scripts/factory-update.sh:159] Der PR-Body hängt die Release Notes aller übersprungenen Versionen ungekürzt an.
  GitHub begrenzt PR-Bodies auf 65 536 Zeichen. Bei sehr vielen bzw. langen Notes scheitert `gh pr create`/`gh pr edit`
  dann **nach** dem Push: der Lauf ist rot, der Branch ist gepusht, aber es gibt keinen PR. Ein Folgelauf heilt das nicht,
  solange die Notes zu lang bleiben. Heute unrealistisch, weil die Notes CHANGELOG-Abschnitte sind. Optional: Notes bei
  einer festen Grenze mit Verweis auf die Release-Seite kürzen.

## Positives
- K1 ist sauber gelöst und belegt: der Test lässt genau das Szenario aus dem Finding laufen (Skript aus `C1`,
  `factory-sync.sh` ersetzt es im Lauf, und die Zielversion trägt am alten Byte-Offset eine erkennbare Zeile). Der Mutant
  prüft per Zählung, dass genau die Aufrufzeile reduziert wurde (Lesson nothra/tch-gastro-services#310).
- Der Fix für W1 nutzt die feste Body-Reihenfolge aus `write_body` statt eines zweiten Formats. `split("\n## ")[0]` ist
  auch robust gegen `\r\n`-Bodies nach einer Bearbeitung in der Web-Oberfläche.
- Die Voraussetzungs-Assertion im neuen AK-24d-Fall belegt, dass die zitierte Marke wirklich im PR-Body steht. Sonst
  bliebe der Test aus dem falschen Grund grün (Lesson nothra/tch-gastro-services#214).
- N1 ist ehrlich formuliert statt wegbehauptet (Lesson nothra/tch-gastro-services#319); offen ist nur der Nachzug in Spec/ADR (s. o.).
- Unverändert gut aus Iteration 1: E11-Reihenfolge, `--force-with-lease` mit Race-Test, Credential-Helper ohne Token in
  argv/Config, Fork-Bedingung im Gate mit Mutationsbeleg und Wiring-Test, Doku und `OWNERSHIP.md` vollständig.
- Architektur: ADR-063 D2/E10, ADR-029 (Check-Name unverändert) eingehalten; keine Routen-Änderung, `docs/routes.md`
  nicht betroffen.

## Empfehlung
NEEDS_REWORK
