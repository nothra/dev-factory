# Spec: Update-Workflow mit Update-PR – T2a-3

> **Teil-Task T2a-3** von `nothra/tch-gastro-services#428` (Epic `nothra/tch-gastro-services#424`).
> Kriterien-Quelle ist `spec-428-factory-versioniert-per-factory-lock-einbinden.md` im Ursprungs-Repo
> (Branch `feature/428-factory-split-t2-factory-lock-einbinden`, bis zum Merge dort). Hier stehen die
> Kriterien AK2.2d, AK2.4, AK2.4b, F1, F3 und FS-T2.3, verfeinert auf den Ist-Stand nach #23, plus die
> Fälle, die spec-428 offen lässt (AK-24a–f, F-24.1–F-24.3). Entscheidung: Factory-ADR-063 D2 und
> Nachtrag 2026-10-25 (E1–E9). Reihenfolge strikt A (#22) → B (#23) → **C (diese Task)** → Release
> `v0.7.0` → Erst-Einbindung im ersten Konsumenten (`nothra/tch-gastro-services#428`).

## Kontext

Seit #23 kann ein Projekt eine Factory-Version **abholen** (`factory-sync.sh <version>`) und ist durch
das Integritäts-Gate gegen lokale Änderungen geschützt. Eine neue Version kommt aber nur an, wenn ein
Mensch bemerkt, dass es sie gibt, und die Abholung von Hand startet. So läuft ein Konsument still hinter
der Factory her: Fixes und Regeln aus späteren Versionen erreichen ihn nicht, und der Abstand wächst, bis
die Hebung über mehrere Versionen auf einmal geht.

Diese Task schließt die Lücke: Ein täglicher Workflow im Konsumenten-Repo bemerkt eine neue Version und
legt dafür **einen** Pull Request an. Der Mensch entscheidet per Review und Merge, die Gates des
Projekts entscheiden, ob die Version passt. Das Factory-Repo braucht dafür weder Schreibrechte in fremde
Repos noch ein Register seiner Konsumenten (Pull statt Push, Factory-ADR-063 D2).

**Primärer Nutzer:** der Entwickler eines Konsumenten-Repos, der den Update-PR prüft und merged.

## Scope

**Inbegriffen:**
- Übernommener Workflow `.github/workflows/factory-update.yml`: täglich und per `workflow_dispatch`,
  höchstens ein Lauf gleichzeitig.
- Ermitteln der neuesten veröffentlichten Version im Quell-Repo (`upstream.repo`) und Vergleich mit
  `factory.lock`; bei neuerer Version Abholung über das bestehende `factory-sync.sh <version>` (#23).
- Pflege **eines** festen Branches `chore/factory-update` mit **einem** PR, Release Notes im PR-Body.
- PR-Erstellung und Push mit dem Fine-grained PAT `FACTORY_SYNC_TOKEN`; kein Auto-Merge.
- Verhalten ohne `factory.lock` (Factory-Repo selbst): No-op.
- Offline-Self-Test gegen ein Fixture-Release (lokales Upstream-Repo mit Tags, Manifeste und Release-Daten
  als Dateien), wie in #23 (Factory-ADR-063 Nachtrag E9).
- `docs/factory/OPERATING.md`: Anlage des Tokens, nötige Rechte, Ablaufdatum, Rotation, Verhalten bei
  abgelaufenem Token.
- Je neue Datei eine Zeile in `docs/factory/OWNERSHIP.md`.

**Nicht inbegriffen:**
- Anlegen des Tokens und Hinterlegen als Secret – **menschlicher Schritt** im Konsumenten-Repo
  (spec-428 Q3); hier nur dokumentiert.
- Das Release `v0.7.0` (eigener Release-PR nach dieser Task, gemeinsam für #23 und #24).
- Erst-Einbindung im ersten Konsumenten, `factory-integrity` als Required Check in dessen Ruleset,
  erster echter Lauf des Workflows (T2a-4, `nothra/tch-gastro-services#428`).
- Auto-Merge, automatisches Rebasen des Update-PRs auf `main` (bleibt bei `/pr-shepherd` bzw. dem
  Menschen), Benachrichtigung über andere Kanäle als den PR.
- Pre-Releases, Drafts und Downgrades: der Workflow hebt nur auf eine höhere, veröffentlichte Version.
- Fund-Ablage ins Factory-Repo, `--init` (T2b, `nothra/tch-gastro-services#441`). Das Recht
  *issues:write* auf `nothra/dev-factory` ist dort nötig, nicht hier.
- Änderungen an `factory-sync.sh` über das hinaus, was der Workflow aufrufen muss.

## Akzeptanzkriterien

> Nummerierung folgt spec-428 (AK2.x); neu sind AK-24a–e. „Beleg" nennt, womit der AK im Test
> nachgewiesen wird. Alle Tests laufen **offline** gegen ein Fixture-Upstream (lokales Git-Repo mit
> Tags, Manifeste und Release-Daten als Dateien) und einen gestubbten GitHub-Zugriff; die Umlenkung
> folgt den Seams aus #23 (Detail in `/architecture`).
>
> Begriffe: **N** = Version laut `factory.lock`; **neueste Version** = höchste Version nach SemVer unter
> den veröffentlichten Releases des Quell-Repos (kein Draft, kein Pre-Release), deren Release das Asset
> `factory-release.json` trägt.

### Update-PR

- [ ] **AK2.2d** GIVEN `factory.lock` nennt N und N+1 ist veröffentlicht WHEN der Workflow läuft
  (Schedule oder `workflow_dispatch`) THEN entsteht ohne menschliches Zutun ein PR von
  `chore/factory-update` nach `main`, der übernommene Dateien, zusammengesetzte Dateien und
  `factory.lock` auf N+1 hebt (Ergebnis von `factory-sync.sh N+1`, sonst keine Änderung), und dessen
  Body die Release Notes von N+1 zeigt. *Beleg: Fixture mit zwei Tags; Diff des Branches == Diff einer
  direkten Abholung; Body enthält den Notes-Text des Fixtures. Wiring-Test: `schedule` und
  `workflow_dispatch` in `factory-update.yml`.*
- [ ] **AK2.4** GIVEN ein Update-PR WHEN er entsteht THEN sind Push und PR-Erstellung mit
  `FACTORY_SYNC_TOKEN` ausgeführt, nicht mit `GITHUB_TOKEN` (sonst lösen sie keine
  `pull_request`-Workflows aus, die Gates liefen nicht); der Workflow merged nie und aktiviert kein
  Auto-Merge. *Beleg: Wiring-Test an den echten Aufrufzeilen (Token-Quelle, kein `gh pr merge`, kein
  `--auto`); Stub-Protokoll des E2E-Tests enthält keinen Merge-Aufruf. Dass die Gates tatsächlich
  laufen, belegt erst der erste echte Lauf in T2a-4.*
- [ ] **AK2.4b** GIVEN die neueste Version ist N (schon eingebunden) oder kleiner als N, oder es gibt
  kein veröffentlichtes Release WHEN der Workflow läuft THEN bleibt alles unverändert (kein Push, kein
  PR, kein Kommentar), und der Lauf ist grün mit Hinweis. *Beleg: je Fall ein Test; Stub-Protokoll ohne
  schreibenden Aufruf.*
- [ ] **F3** GIVEN N+1 und danach N+2 erscheinen, bevor der Update-PR gemergt ist WHEN der Workflow
  nach jedem Release läuft THEN gibt es höchstens **einen** offenen Update-PR; er zeigt auf N+2, sein
  Branch ist von `main` aus neu aufgebaut (enthält N+1 nicht als Zwischenstand), Titel und Body nennen
  N+2. *Beleg: Fixture mit drei Tags, zwei Läufe; Anzahl offener PRs = 1, Lock im Branch = N+2.*
- [ ] **AK-24a · Release Notes über mehrere Versionen** GIVEN die Hebung überspringt Versionen (N → N+2)
  WHEN der PR-Body entsteht THEN zeigt er die Release Notes **jeder** Version in (N, N+2], neueste
  zuerst, je mit Versionsüberschrift. *Beleg: Fixture mit drei Tags.*

### Bestehender PR und Branch

- [ ] **AK-24b · Gleiche Version bleibt unberührt** GIVEN ein offener Update-PR steht schon auf der
  neuesten Version WHEN der Workflow läuft THEN wird der Branch nicht neu aufgebaut und nicht gepusht
  (auch nicht, wenn ein Mensch dort eigene Commits ergänzt hat oder `main` weitergelaufen ist), der PR
  bleibt unverändert, der Lauf ist grün. *Beleg: Branch mit zusätzlichem Fremd-Commit; Commit-SHA des
  Branches vor/nach gleich.*
- [ ] **AK-24c · Neuere Version ersetzt Fremd-Commits sichtbar** GIVEN der Update-PR trägt menschliche
  Commits und eine noch neuere Version erscheint WHEN der Workflow den Branch neu aufbaut THEN sind diese
  Commits nicht mehr auf dem Branch, und der PR-Body nennt das (Hinweis, dass der Branch dem Workflow
  gehört und bei jeder neuen Version neu aufgebaut wird). *Beleg: Test mit Fremd-Commit und
  Versionssprung; Hinweistext im Body.*
- [ ] **AK-24d · Abgelehnte Version wird nicht erneut angeboten** GIVEN ein Update-PR für Version V wurde
  ohne Merge geschlossen und V ist weiterhin die neueste Version WHEN der Workflow läuft THEN entsteht
  kein neuer PR, kein Push, der Lauf ist grün mit Hinweis auf den geschlossenen PR. GIVEN danach
  erscheint eine Version > V THEN entsteht wieder ein PR (AK2.2d). *Beleg: zwei Tests.*

- [ ] **AK-24f · Update-PR besteht `pr-closes-issue`** GIVEN ein Update-PR (Head-Branch
  `chore/factory-update` im selben Repo) ohne Closing-Keyword WHEN der Required Check `pr-closes-issue`
  läuft THEN ist er grün mit eigener Meldung; GIVEN ein PR aus einem **Fork** mit demselben Branch-Namen
  oder ein PR von einem anderen Branch ohne Keyword THEN bleibt er rot wie bisher. *Beleg: drei Tests am
  Gate + Mutationsbeleg (Fork-Bedingung entfernt → Test rot); Wiring-Test für das Env im Job
  (Factory-ADR-063 E14, entschieden 2026-10-30).*

### Factory-Repo selbst

- [ ] **AK-24e · No-op ohne Lock** GIVEN das Repo hat kein `factory.lock` (Factory-Repo selbst) WHEN der
  Workflow läuft THEN ist er ein No-op mit Hinweis und grün, **ohne** `FACTORY_SYNC_TOKEN` zu verlangen
  und ohne Netzzugriff auf das Quell-Repo. Ein vorhandener, aber unlesbarer Lock gilt nicht als „kein
  Lock" (F-24.3). *Beleg: Test ohne Lock und ohne Token; Stub-Protokoll ohne Netzaufruf.*

## Fehlerszenarien

- [ ] **F1** GIVEN die neue Version macht die Gates des Konsumenten rot WHEN der Update-PR existiert THEN
  bleibt er offen und rot; `main` ist unverändert und arbeitsfähig. Der Workflow liest den CI-Status
  nicht und schreibt nie auf `main` (einziges Schreibziel ist `chore/factory-update`). *Beleg:
  Wiring-Test (kein Push-Ziel außer dem festen Branch); E2E-Test: `main` vor/nach gleich.*
- [ ] **FS-T2.3** GIVEN `factory.lock` ist vorhanden und `FACTORY_SYNC_TOKEN` fehlt, ist leer oder wird
  abgelehnt (abgelaufen, zu wenig Rechte) WHEN der Workflow läuft THEN schlägt der Lauf **vor jedem
  weiteren Schritt** fehl, mit klarer Meldung (Token fehlt/ungültig, Verweis auf `OPERATING.md`) –
  auch wenn keine neue Version vorliegt. Es gibt keinen Push, keinen halben PR und keinen Rückfall auf
  `GITHUB_TOKEN`. *Beleg: je ein Test für fehlendes und abgelehntes Token; Mutationsbeleg
  (Token-Prüfung entfernt → Test rot).*
- [ ] **F-24.1 · Abholung scheitert** GIVEN `factory-sync.sh` bricht ab (lokale Änderung an einer
  übernommenen Datei auf `main` (F2), Hash-Abweichung, Manifest fehlt (FS-T2.1/.2/.4)) WHEN der Workflow
  läuft THEN ist der Lauf rot mit der Meldung von `factory-sync.sh`; kein Push, kein PR, ein bestehender
  Update-PR bleibt unverändert. *Beleg: Stub lässt die Abholung scheitern; Branch-SHA und PR vor/nach
  gleich.*
- [ ] **F-24.2 · Quell-Repo nicht erreichbar** GIVEN die Liste der Releases lässt sich nicht lesen (Netz,
  API-Fehler, ungültige Antwort) WHEN der Workflow läuft THEN ist der Lauf rot (fail-closed, nicht „keine
  neue Version"), nichts geändert.
- [ ] **F-24.3 · Lock unlesbar** GIVEN `factory.lock` ist vorhanden, aber kein gültiges JSON oder ohne
  gültige `version` WHEN der Workflow läuft THEN ist der Lauf rot, nichts geändert (kein Rückfall auf
  den No-op aus AK-24e; vgl. F-23.2).

## Offene Fragen

- [x] **Q-24.1 · Verhalten im Factory-Repo** → No-op, grün, ohne Token (entschieden 2026-10-30, AK-24e).
- [x] **Q-24.2 · Wann prüft der Lauf das Token?** → bei vorhandenem Lock immer und vor allem anderen,
  auch ohne neue Version; ein abgelaufenes Token fällt am nächsten Tag auf, nicht erst beim nächsten
  Release (entschieden 2026-10-30, FS-T2.3).
- [x] **Q-24.3 · Wem gehört der Branch?** → dem Workflow. Gleiche Version: unberührt; neuere Version:
  Neuaufbau, Fremd-Commits entfallen sichtbar (entschieden 2026-10-30, AK-24b/c).
- [x] **Q-24.4 · Abgelehnte Version** → wird nicht erneut angeboten, erst eine neuere (entschieden
  2026-10-30, AK-24d).
- [x] **Q-24.5 · Für `/architecture`:** → Factory-ADR-063 Nachtrag 2026-10-30, E10–E14, E16. Wo liegt die Logik (eigenes Skript vs. Inline-Schritte im
  Workflow) und wie wird sie offline testbar (Seam für die Release-Liste, Stub für `gh`)? Woran erkennt
  der Lauf „PR für Version V geschlossen" und „Branch steht auf V" (Lock im Branch, PR-Titel,
  Label)? Welche Art-/Aspekt-Labels trägt der PR (kanonisch: `git-workflow.md` → „GitHub-Labels")?
  Draft oder bereit zum Review? Woraus kommen die Release Notes (Release-Body der Version)? Diese
  Details erweitern Factory-ADR-063 D2 → Nachtrag, kein neuer ADR.
- [x] **Q-24.6 · Token-Rechte:** → Contents, Pull requests, Workflows (je read/write) auf dem
  Konsumenten-Repo; *issues:write* auf `nothra/dev-factory` erst in T2b (Factory-ADR-063 E15). spec-428 Q3 nennt *contents:write* + *pull-requests:write* im
  Konsumenten-Repo. Reicht das für das Lesen der Releases von `nothra/dev-factory` (öffentlich) und ggf.
  für das Pushen von Workflow-Dateien (`.github/workflows/**` ändert sich mit jeder Version, die einen
  Workflow ändert → braucht vermutlich zusätzlich *workflows:write*)? In `/architecture` klären und in
  `OPERATING.md` festhalten.

## Größe

6 Kriterien aus spec-428 + 6 neue (AK-24a–f) + 3 neue Fehlerszenarien = 15, deutlich unter der Schwelle von 25 AK
(Lesson `nothra/tch-gastro-services#369`). Erwartet wenige neue Dateien (Workflow, ggf. Skript, Tests)
plus `OPERATING.md` und `OWNERSHIP.md`.

## Zuordnung zu spec-428

| spec-428 | Hier |
|---|---|
| AK2.2d, AK2.4, AK2.4b | gleich (verfeinert) |
| F1, F3, FS-T2.3 | gleich (verfeinert; FS-T2.3 auch ohne neue Version) |
| neu | AK-24a–f, F-24.1–F-24.3 |
