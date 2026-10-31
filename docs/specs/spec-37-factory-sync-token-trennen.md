# Spec: FACTORY_SYNC_TOKEN vom Code des abgeholten Release trennen

> Issue #37 (Security-Review zu #24, Kategorie Secrets / Lieferkette). Betrifft Factory-ADR-063
> Nachtrag E4/E10/E12/E15 und `docs/factory/OPERATING.md` §0.6. Kein Verhalten des Update-PRs ändert
> sich für den Nutzer (spec-24 bleibt gültig); geändert wird, **was der Code eines noch ungeprüften
> Release vom Token erreichen kann**.

## Kontext

`factory-update.sh` holt eine neue Factory-Version ab. Dabei läuft Code des **noch nicht von einem
Menschen geprüften** Release (`factory-sync.sh` startet sich in der neuen Fassung neu) – im selben Job
und Prozessbaum, in dem danach das schreibberechtigte `FACTORY_SYNC_TOKEN` zum Pushen und zum Anlegen
des PRs benutzt wird. Das Entfernen des Tokens aus der Umgebung des Abholschritts (`env -u`) ist keine
Grenze. Belegte Angriffswege (Issue #37):

1. **Git-Konfiguration:** Release-Code schreibt `.git/config` (z. B. `core.fsmonitor`); das folgende
   `git add`/`git commit` des Elternprozesses führt den Befehl aus, mit dem Token in der Umgebung
   (lokal nachgestellt, auch mit `core.hooksPath=/dev/null`).
2. **Prozess-Umgebung:** Ein Kindprozess desselben Benutzers kann unter Linux `/proc/<ppid>/environ`
   lesen; Runner haben passwortloses `sudo` (die Programme `git` und `gh` lassen sich austauschen).
3. **Repository-Secret im PR-Workflow:** Der Update-PR kommt aus demselben Repo; `pull_request`-
   Workflows laufen mit den Workflow-Dateien **des PR** und sehen alle Repository-Secrets. Ein Release,
   das eine Datei unter `.github/workflows/` ändert, kann das Secret auslesen, bevor ein Mensch den PR
   geprüft hat.

Ein kompromittiertes Release (oder ein kompromittiertes Quell-Repo) kann so ein Token mit Schreibrecht
auf Code, PRs und Workflows des Konsumenten-Repos erbeuten – genau die Lieferkette, die die Gates und
das Review des Update-PRs absichern sollen.

**Primärer Nutzer:** der Maintainer eines Konsumenten-Repos, der `FACTORY_SYNC_TOKEN` hinterlegt und
sich darauf verlässt, dass ein Release dieses Token nicht erreicht, bevor er den PR geprüft hat.

## Scope

**Inbegriffen:**
- Alle drei oben genannten Angriffswege sind für Code des abgeholten Release **nicht mehr gangbar**.
- Das Token ist für `pull_request`-Workflows auf dem Update-Branch `chore/factory-update` nicht sichtbar.
- Das Verhalten des Update-PRs für Nutzer bleibt wie in spec-24 (AK2.2d, AK2.4, AK2.4b, AK-24a–f, F3,
  FS-T2.3, F-24.1–F-24.3).
- `OPERATING.md` §0.6 (Anlage des Tokens) und Factory-ADR-063 (E4/E12: **verbleibendes Risiko ehrlich
  benannt**) sind an den neuen Stand angepasst.
- Tests: Wiring-Tests am Workflow (wo das Token verfügbar ist, wo nicht), Verhaltenstests für
  Skript/Workflow, Mutationsbelege für die tragenden Prüfungen.
- Neue Dateien: je eine Zeile in `docs/factory/OWNERSHIP.md`.

**Nicht inbegriffen:**
- Prüfung der Release-Inhalte selbst (Signaturen, Review des Quell-Repos) – Lieferketten-Absicherung
  des Quell-Repos ist ein eigenes Thema.
- Ersatz des PAT durch eine GitHub App oder durch OIDC-/Deploy-Key-Verfahren (ggf. Folge-Issue, falls
  `/architecture` es als Ausweg nennt).
- Änderungen an Version-Erkennung, PR-Pflege, Branch-Besitz und Release-Notes (spec-24).
- Härtung anderer Workflows (`factory-ci.yml`, `factory-poll.yml`, `release.yml`) – nur, soweit sie
  `FACTORY_SYNC_TOKEN` verwenden (laut Repo-Stand: keiner).
- Anlegen/Rotieren des Tokens und Einrichten der GitHub-Environment-Regeln in einem echten
  Konsumenten-Repo – **menschlicher Schritt**, hier nur dokumentiert.

## Akzeptanzkriterien

> „Beleg" nennt, womit der AK nachgewiesen wird. Tests laufen offline (Stub-Protokoll, Fixture-Release,
> Wiring-Tests an der echten Workflow-Datei). Begriff **Release-Code** = jede Datei, die aus dem
> abgeholten Release stammt und beim Abholen ausgeführt wird (`factory-sync.sh` in neuer Fassung,
> Hooks, Skripte, die der Abholschritt aufruft).

### Token und Release-Code trennen

- [ ] **AK-37a · Token nicht neben Release-Code** GIVEN ein Update-Lauf WHEN Release-Code ausgeführt
  wird (Abholschritt) THEN ist `FACTORY_SYNC_TOKEN` weder in der Umgebung dieses Schritts noch in der
  Umgebung eines seiner Eltern-/Geschwister-Prozesse im selben Job vorhanden (Schritt/Job-Grenze, nicht
  `env -u`). *Beleg: Wiring-Test an der echten Workflow-Datei – der Schritt/Job, der Release-Code
  ausführt, referenziert `secrets.FACTORY_SYNC_TOKEN` nicht (weder direkt noch über Step-`env`/Job-`env`);
  Mutationsbeleg: Secret in den Abholschritt eingefügt → Test rot.*
- [ ] **AK-37b · Kein Release-Code im Token-Schritt** GIVEN der Schritt, der `FACTORY_SYNC_TOKEN` hält
  (Push, PR anlegen/aktualisieren) WHEN er läuft THEN führt er **keinen** Code aus dem abgeholten
  Release aus – weder Skripte noch Git-Hooks noch Git-Konfiguration, die der Abholschritt geschrieben
  hat. *Beleg: E2E-Test mit Fixture-Release, dessen Abholcode `.git/config` (`core.fsmonitor`), einen
  Hook und `.git/info/`-Dateien schreibt: der Marker-Befehl läuft im Token-Schritt nicht (Stub-Protokoll
  ohne Marker); Mutationsbeleg: Schutz entfernt → Marker läuft, Test rot.*
- [ ] **AK-37c · Ergebnis wird als Daten übergeben** GIVEN der Abholschritt ist beendet WHEN der
  Token-Schritt beginnt THEN übernimmt er ausschließlich das Ergebnis (neuer Branch-Stand der
  abgeholten Dateien) als Daten über eine definierte Übergabe, und prüft vor dem Push, dass nur
  erwartete Pfade geändert sind. *Beleg: Test mit Fixture-Release, das zusätzlich eine unerwartete
  Datei (außerhalb der Übernahme-Liste) oder einen Symlink aus dem Repo heraus erzeugt → Lauf rot, kein
  Push; Mutationsbeleg: Prüfung entfernt → Test rot.*
- [ ] **AK-37d · Ergebnis identisch zu bisher** GIVEN dasselbe Fixture wie in spec-24 (AK2.2d, F3,
  AK-24a–d) WHEN der Update-Lauf mit der neuen Aufteilung läuft THEN sind Diff des Branches, PR-Body,
  Titel, Labels und die Zahl offener PRs unverändert gegenüber spec-24. *Beleg: die bestehenden
  Tests aus spec-24 laufen unverändert grün (kein Test abgeschwächt).*

### Token im Repository-Secret

- [ ] **AK-37e · Secret für PR-Workflows unsichtbar** GIVEN ein `pull_request`-Workflow läuft auf dem
  Branch `chore/factory-update` mit einer vom Release geänderten Workflow-Datei WHEN er auf Secrets
  zugreift THEN ist `FACTORY_SYNC_TOKEN` nicht lesbar (leer), weil es **nicht als Repository-Secret**
  hinterlegt ist, sondern an einen Kontext gebunden, der nur dem Update-Job auf dem Standard-Branch
  offensteht. *Beleg: Wiring-Test – `factory-update.yml` bindet den Token-Schritt an diesen Kontext;
  `OPERATING.md` §0.6 verlangt Hinterlegung dort und ausdrücklich **kein** gleichnamiges
  Repository-Secret; Doku-Guard gegen die alte Anweisung („als Repository-Secret"). Dass GitHub das
  durchsetzt, belegt erst der erste echte Lauf (siehe Q-37.3).*
- [ ] **AK-37f · Kein Rückfall auf Repository-Secret** GIVEN ein Maintainer hat das Token noch als
  Repository-Secret hinterlegt (Bestand aus spec-24) WHEN der Update-Workflow läuft THEN endet er rot
  mit klarer Meldung (Token liegt als Repository-Secret, bitte verschieben; Verweis auf
  `OPERATING.md` §0.6) – oder der Betrieb ist anderweitig so abgesichert, dass dieses Secret für
  PR-Workflows nicht sichtbar bleibt (Q-37.4). *Beleg: Test am Prüfmechanismus bzw. Wiring-Test;
  Mutationsbeleg: Prüfung entfernt → Test rot.*

### Dokumentation und Restrisiko

- [ ] **AK-37g · OPERATING.md** GIVEN ein Maintainer richtet das Token ein WHEN er §0.6 folgt THEN sind
  Anlage des Contexts, Branch-Regel `main`, Hinterlegung des Secrets dort, der Umzug eines bestehenden
  Repository-Secrets und der Test-Lauf (`workflow_dispatch`) beschrieben. *Beleg: Doku-Guard-Anker auf
  die Schritte; Lesson `nothra/tch-gastro-services#265`-Muster (Anker an der Aufrufzeile, nicht an
  Fragmenten).*
- [ ] **AK-37h · ADR-063 ehrlich** GIVEN Factory-ADR-063 Nachtrag WHEN die Trennung umgesetzt ist THEN
  nennen E4/E12 die neue Aufteilung und das **verbleibende Risiko** (z. B.: ein Release, das den
  Abholschritt selbst manipuliert, kann das gebaute Ergebnis verfälschen – abgefangen nur durch AK-37c
  und das Review des Update-PRs; ein kompromittierter Update-Branch ist weiter sichtbar im PR). *Beleg:
  Doku-Guard-Anker; der ADR-Status wird im Umsetzungs-PR mitgezogen (Lesson
  `nothra/tch-gastro-services#197`).*

## Fehlerszenarien

- [ ] **F-37.1 · Übergabe scheitert** GIVEN der Abholschritt bricht ab oder liefert kein/ein
  unlesbares Ergebnis WHEN der Token-Schritt beginnt THEN ist der Lauf rot mit Meldung, ohne Push und
  ohne PR; ein bestehender Update-PR bleibt unverändert (wie F-24.1). *Beleg: Test mit abgebrochenem
  Abholschritt.*
- [ ] **F-37.2 · Token fehlt im Kontext** GIVEN `factory.lock` ist vorhanden und das Token ist im
  vorgesehenen Kontext nicht hinterlegt (leer, abgelaufen, falscher Kontext) WHEN der Workflow läuft
  THEN gilt FS-T2.3 unverändert (rot **vor jedem weiteren Schritt**, kein Rückfall auf `GITHUB_TOKEN`),
  und die Meldung nennt den Kontext als mögliche Ursache. *Beleg: Test für leer/abgelehnt; Meldung
  enthält den Kontextnamen.*
- [ ] **F-37.3 · Kein Lock** GIVEN das Repo hat kein `factory.lock` (Factory-Repo selbst) WHEN der
  Workflow läuft THEN bleibt es ein grüner No-op **ohne** Token-Zugriff und ohne Warten auf eine
  Freigabe des Kontexts (AK-24e). *Beleg: bestehender Test aus spec-24 bleibt grün; Wiring-Test: der
  No-op-Pfad läuft nicht in einem Job, der den Kontext bindet (sonst Freigabe nötig).*
- [ ] **F-37.4 · Fremd-Release-Datei im Token-Schritt** GIVEN das Ergebnis des Abholschritts enthält
  eine Datei `.github/workflows/**`, die den Token-Schritt selbst oder seinen Kontext ändert WHEN der
  Token-Schritt läuft THEN führt er sie nicht aus (der Lauf nutzt die Workflow-Fassung des Standard-
  Branches, nicht die des Ergebnisses). *Beleg: Wiring-Test (der Token-Schritt checkt `main` aus, nicht
  den Update-Branch; Mutationsbeleg).*

## Offene Fragen

> Technische Lösungen sind Sache von `/architecture`; die Vorschläge aus Issue #37 (Environment-Secret
> mit Branch-Regel `main`; Aufteilung auf zwei Jobs, Job 1 ohne Secret, `git bundle` als Artefakt,
> Job 2 mit Secret ohne Release-Code) sind **Eingaben**, keine Festlegung.

- [ ] **Q-37.1 · Beide Maßnahmen oder eine?** Deckt allein die Aufteilung auf zwei Jobs AK-37a–c ab und
  allein der Kontext AK-37e, oder sind beide nötig? (Aus Sicht der Anforderung: **beide Angriffsflächen
  müssen geschlossen sein**, AK-37a–c **und** AK-37e.) In `/architecture` klären.
- [ ] **Q-37.2 · Übergabeformat und Prüfung:** Wie kommt das Ergebnis des Abholschritts in den
  Token-Schritt (Artefakt, Bundle, Patch), und welche Prüfung vor dem Push reicht für AK-37c?
- [ ] **Q-37.3 · Beleg am echten Repo:** Wie wird die Durchsetzung durch GitHub (Secret im Kontext für
  PR-Workflows unsichtbar) einmal real nachgewiesen? Vorschlag: im ersten echten Konsumenten
  (`nothra/tch-gastro-services#428`) ein Test-PR, dessen Workflow `${{ secrets.FACTORY_SYNC_TOKEN }}`
  ausgibt (maskiert → leer erwartet). Menschlicher Schritt, vom Maintainer zu bestätigen.
- [ ] **Q-37.4 · Umgang mit Bestand (AK-37f):** Bricht der Workflow hart ab, wenn ein
  Repository-Secret gleichen Namens erkannt wird, oder genügt Dokumentation? (Die Erkennung selbst ist
  mit einem Token nicht verlässlich möglich – ggf. nur Hinweis in §0.6; AK-37f dann herabstufen.)
- [ ] **Q-37.5 · Kosten für Konsumenten:** Ein Environment mit Deployment-Branch-Regel ist je
  Konsumenten-Repo einmal einzurichten (Plan-abhängig? Environments mit Branch-Regeln sind für private
  Repos nicht in jedem GitHub-Plan verfügbar). Ist das für alle Konsumenten tragbar, oder braucht ein
  Fallback (z. B. Organisations-Secret mit Repository-Auswahl) einen eigenen Pfad?
- [ ] **Q-37.6 · Konkurrenz mit Concurrency-Gruppe:** Zwei Jobs/Artefakte dürfen die bestehende
  Concurrency-Regel (`factory-update`, höchstens ein Lauf, kein Abbruch) nicht aufweichen
  (spec-24 F3). In `/architecture` mitprüfen.

## Größe

8 Kriterien + 4 Fehlerszenarien = 12, unter der Schwelle von 25 AK (Lesson
`nothra/tch-gastro-services#369`). Erwartet: `factory-update.yml` (Aufteilung), `factory-update.sh` bzw.
ein zusätzliches Skript für Übergabe/Prüfung, Tests in `scripts/checks/tests/factory-lock-tests.sh`,
`OPERATING.md` §0.6, ADR-063 Nachtrag, ggf. Zeile in `OWNERSHIP.md` je neuer Datei.

## Zuordnung

| Quelle | Hier |
|---|---|
| Issue #37, Angriffsweg 1 (Git-Konfiguration) | AK-37b, AK-37c |
| Issue #37, Angriffsweg 2 (`/proc`, `sudo`) | AK-37a |
| Issue #37, Angriffsweg 3 (PR-Workflow sieht Secret) | AK-37e, AK-37f, F-37.4 |
| Issue #37, Vorschlag 3 (ADR ehrlich) | AK-37h |
| spec-24 (Verhalten unverändert) | AK-37d, F-37.2, F-37.3 |
