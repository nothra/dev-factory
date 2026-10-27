# Spec: @import-Deckel-Test der ausgelieferten Suite ohne Konsumenten-Dateien (#32)

## Kontext

Die ausgelieferte Self-Test-Suite (`scripts/checks/tests/run-tests.sh`) ist konsumenten-neutral
(Factory-ADR-064 D6): sie darf keine projekteigenen Dateien des echten Repos voraussetzen. Der Test
„#319: realer @import-Stand des Repos liegt unter dem Deckel" ruft `import-context-limit-check.sh` mit
`FACTORY_DIR="$FACTORY_ROOT"` auf. Das Check-Skript liest dabei `CLAUDE.md` und die darüber importierten
Dateien (u. a. `docs/factory/PROJECT-CONTEXT.md`) – beides Anpassungsstellen des Konsumenten (Seite `project`).

Folge: Fehlt `PROJECT-CONTEXT.md` oder reißt das Import-Set des Konsumenten den Deckel, wird
`factory-self-test` rot, obwohl alle Factory-Dateien intakt sind. Belegt durch einen Fixture-Lauf im
Review zu #28. Der AK6-Guard aus #28 sucht nur nach **direkten** Lesezugriffen auf projekteigene
Dateien (`$FACTORY_ROOT/<datei>`) und sieht diesen **indirekten** Leser (Aufruf eines Check-Skripts
gegen die Repo-Wurzel) nicht.

Warum das ein Fehler ist: Ob das Import-Set eines Konsumenten unter dem Deckel liegt, ist Sache des
Konsumenten (er hat den Hook `import-context-limit-check.sh` im pre-push ohnehin), nicht der
Factory-Suite.

## Scope

**Inbegriffen:**
- Die ausgelieferte Suite führt den „realer Stand"-Test des @import-Deckels nicht mehr gegen die echte
  Repo-Wurzel aus; die Prüfung des Deckel-Verhaltens selbst (Grenzwerte, Referenz-Formen, Confinement,
  fail-closed) bleibt vollständig erhalten und läuft gegen Fixtures.
- Die Kopplung „Deckel ist für den echten Repo-Stand grün" bleibt für dieses Repo (dev-factory)
  erhalten, an einer Stelle, die Konsumenten nicht erreicht.
- Der AK6-Guard aus #28 erkennt künftig auch **indirekte** Leser: Aufrufe von Check-Skripten, die
  `FACTORY_DIR`/`FACTORY_ROOT` auf die echte Repo-Wurzel setzen.

**Nicht inbegriffen:**
- Änderungen am Verhalten von `import-context-limit-check.sh` oder an `MAX_IMPORT_LINES`.
- Eine Neubewertung anderer Suite-Teile auf projekteigene Abhängigkeiten, die der erweiterte Guard
  nicht findet (eigenes Issue, falls der Guard beim Lauf weitere Treffer meldet – siehe AK4).
- Eine neue CI-Erzwingung des @import-Deckels (Zuständigkeit: nothra/tch-gastro-services#328).

## Akzeptanzkriterien

- [ ] **AK1** GIVEN ein Konsumenten-Repo, in dem `docs/factory/PROJECT-CONTEXT.md` fehlt oder dessen
  `CLAUDE.md`-Import-Set den Deckel überschreitet, aber alle Factory-Dateien intakt sind
  WHEN die ausgelieferte Suite läuft THEN ist keine Assertion allein deshalb rot (kein
  Falsch-Rot durch Konsumenten-Dateien).
  *Beleg: Fixture-Lauf der Suite in einer Repo-Kopie ohne `PROJECT-CONTEXT.md` bzw. mit aufgeblähtem
  `CLAUDE.md` – gleiche Assertion-Ergebnisse wie im unveränderten Repo.*
- [ ] **AK2** GIVEN die ausgelieferte Suite WHEN sie das Deckel-Verhalten prüft THEN laufen alle
  Verhaltensfälle (unter/über Grenze, Grenzwert ±1, Seite A/B, Referenz-Formen, Confinement,
  fail-closed, Konstanten-Herleitung) weiterhin und unverändert gegen Fixtures bzw. das Skript selbst;
  es entfällt ausschließlich der Aufruf gegen die echte Wurzel (Assertion-Anzahl sinkt um genau diesen
  Fall).
- [ ] **AK3** GIVEN dieses Repo (dev-factory) WHEN `scripts/project/tests/run-tests.sh` läuft THEN
  prüft sie, dass der reale @import-Stand unter dem Deckel liegt (Assertion mit demselben
  Aussagegehalt wie der entfallene Test, inkl. Ausgabe der Breakdown-Liste bei Rot).
  *Beleg: Mutation – `CLAUDE.md` des Repos über den Deckel aufblasen → Projekt-Suite rot.*
- [ ] **AK4** GIVEN der AK6-Guard aus #28 WHEN ein Test in einer ausgelieferten Test-Datei ein
  Check-Skript mit `FACTORY_DIR` (oder gleichwertiger Wurzel-Variable) auf die echte Repo-Wurzel
  aufruft THEN meldet der Guard das als Verstoß.
  *Beleg: Negativfall (Mutation: Aufruf `FACTORY_DIR="$FACTORY_ROOT" bash <check>` ergänzt → Guard rot),
  Aufruf mit Fixture-Wurzel bleibt grün (Kontrolle), unlesbare Quelle bleibt fail-closed (wie AK6 aus #28).*
- [ ] **AK5** GIVEN der erweiterte Guard WHEN er gegen die ausgelieferte Suite im Ist-Stand läuft THEN
  ist er grün – oder jeder weitere Treffer ist im selben PR behoben bzw. mit Issue-Nummer als
  Folgearbeit dokumentiert (kein stilles Erweitern, das den Push blockiert).
- [ ] **AK6** GIVEN die Gates WHEN `scripts/checks/pre-push.sh` und beide Suiten laufen THEN sind sie
  grün (Self-Test-Suite, Projekt-Suite, `bash -n`-Lint, Ownership-Check).

## Fehlerszenarien

- [ ] Die Projekt-Suite kann `CLAUDE.md` nicht lesen → Test ist rot mit klarer Meldung (fail-closed),
  nicht übersprungen.
- [ ] Der erweiterte Guard kann seine Quelldatei nicht lesen → rot (`UNLESBAR:`), nicht still grün.
- [ ] Der Guard-Ausdruck ist so formuliert, dass er sich nicht selbst als Treffer in der Test-Datei
  findet (Content-Scan-Guard, dessen Phrase in der gescannten Datei steht – Lesson aus
  nothra/tch-gastro-services#319).

## Offene Fragen

- [ ] Wo genau die „realer Stand"-Assertion künftig lebt (Projekt-Suite vs. Fixture-Lauf) und wie der
  erweiterte Guard indirekte Leser erkennt (Muster auf Aufrufzeile vs. Whitelist erlaubter
  Wurzel-Argumente) ist Lösungsentscheidung → `/architecture` bzw. `/implement`.
  Ob ein ADR-Trigger vorliegt, entscheidet der Architekt (Änderung einer Test-Zuordnung nach
  Factory-ADR-064 D6; vermutlich kein neuer ADR nötig).
- [ ] Gibt es außer Zeile 6346 weitere Aufrufe in ausgelieferten Test-Dateien, die Check-Skripte oder
  `pre-push.sh` gegen die echte Wurzel fahren? (Erste Suche nach `FACTORY_DIR="$FACTORY_ROOT"` fand nur
  diesen einen; AK5 sichert den Rest ab.)
