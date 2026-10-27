# Spec: Ausgelieferte Self-Test-Suite liest keine projekteigenen Dateien mehr

> Task #28 · Issue nothra/dev-factory#28 · Herkunft: Review Task #22 (PR #25), Konsumenten-Vertrag
> (`spec-22`, Factory-ADR-064). Vor der Erst-Einbindung (T2a-2 #23 / T2a-3 #24) zu klären.

## Kontext

Die Self-Test-Suite `scripts/checks/tests/run-tests.sh` wird an Konsumenten ausgeliefert und läuft dort als
`factory-self-test`. Sie soll dort nur rot werden, wenn die Factory-Dateien defekt sind – nicht, weil eine
projekteigene Datei anders aussieht. Das Issue nennt drei Fundstellen, an denen die Suite projekteigene
Dateien liest:

| # | Fundstelle | Stand heute |
|---|------------|-------------|
| 1 | `docs/factory/PROJECT-CONTEXT.md` als Eingabe des Label-Drift-Guards (`PCX_431`, `#431 AK-I2`) | **offen** – liest die echte Datei des Repos |
| 2 | `.gitignore.project`, `.claude/settings.project.json` als Fixture der Compose-Tests | **erledigt** durch Factory-Issue #23 (AK-28a): `fixture_431()` baut die Projekt-Fragmente selbst |
| 3 | `factory.config.yml` (nur Config-Validierung, `CFG_431`) | laut Issue vertretbar |

Das Kriterium „Factory-Repo-spezifisch" in Factory-ADR-064 D6 ist bereits um „prüft den Zustand
projekteigener Dateien des echten Repos" ergänzt (Nachtrag aus #23, AK-28c). Die ADR-Frage des Issues ist
damit beantwortet.

Das im Issue beschriebene Risiko (ein Konsument mit eigener `labels.aspects_extra` ohne Beschreibung in
seiner `PROJECT-CONTEXT.md` bekommt `factory-self-test` rot) ist **zu belegen, nicht anzunehmen**: Die
Mutationsfälle prüfen nur „Meldung enthalten" (`assert_contains_286`). Offen ist, ob die echte Datei die
Fälle in irgendeinem Konsumenten-Zustand kippen kann (z. B. Datei fehlt oder enthält bereits die
Mutations-Marke).

## Scope

**Inbegriffen:**
- Der Label-Drift-Guard (`#431 AK-I2`) liest `PROJECT-CONTEXT.md` nicht mehr aus dem echten Repo, sondern
  aus einer vom Test selbst gebauten Fixture.
- Der Beleg, dass die Fundstelle (2) und die D6-Erweiterung bereits erledigt sind (Verweis auf AK-28a/28c).
- Eine Regel gegen Rückfall: die Suite enthält keine Lesezugriffe auf projekteigene Dateien des echten Repos
  außerhalb der benannten, begründeten Ausnahme (Fundstelle 3).

**Nicht inbegriffen:**
- Änderungen an `label_drift_431` selbst (Verhalten bleibt) und am Inhalt der Guard-Prüfungen.
- Fundstelle (3): Die Validierung der echten `factory.config.yml` bleibt (Konsument prüft seine eigene
  Config; vertretbar laut Issue).
- Verschieben weiterer Testgruppen in `scripts/project/tests/run-tests.sh` (nur falls ein AK es verlangt).
- Die Erst-Einbindung (#23/#24) und jede Änderung am Factory-Repo-eigenen Label-Bestand.

## Akzeptanzkriterien

- [ ] **AK1** GIVEN ein Repo, dessen `docs/factory/PROJECT-CONTEXT.md` projekteigene Aspekt-Labels
  beschreibt, nicht beschreibt oder fehlt WHEN die ausgelieferte Self-Test-Suite läuft THEN ist der
  Label-Drift-Block (`#431 AK-I2`) grün, weil er seine `PROJECT-CONTEXT.md` aus einer Fixture bezieht und
  die des Repos nicht liest. *Beleg: Suite-Lauf in einem Fixture-Repo mit verändertem und mit fehlendem
  `PROJECT-CONTEXT.md`.*
- [ ] **AK2** GIVEN die Fixture WHEN die drei Mutationsfälle laufen (Config-Label ohne Beschreibung,
  generisches Label ohne Tabellenzeile, projekteigenes Label in der generischen Tabelle) THEN schlägt der
  Guard in jedem Fall mit derselben Meldung an wie vorher. *Beleg: die drei bestehenden Assertions bleiben
  mit unverändertem Ausdruck erhalten; Vorher/Nachher-Zählung der Assertions in Task-Datei und PR.*
- [ ] **AK3** GIVEN die Fixture enthält ein Label mit Beschreibung WHEN der Guard gegen die zugehörige Config
  läuft THEN meldet er keine Abweichung (Positivkontrolle – sonst bewiese die Mutation nicht, dass die
  Fixture lesbar ist).
- [ ] **AK4** GIVEN ein Konsument mit eigenem `labels.aspects_extra` in `factory.config.yml` WHEN die Suite
  läuft THEN bleibt sie grün. *Beleg: Suite-Lauf im Fixture-Repo mit eigenem `aspects_extra`-Eintrag ohne
  Beschreibung in dessen `PROJECT-CONTEXT.md`.*
- [ ] **AK5** GIVEN die Suite im Factory-Repo WHEN sie läuft THEN bleibt der Zustand des echten
  `PROJECT-CONTEXT.md`-Labelbereichs weiter geprüft – in der Projekt-Suite
  `scripts/project/tests/run-tests.sh`; kein Guard entfällt ersatzlos. *Beleg: Vorher/Nachher-Liste der
  verschobenen bzw. ersetzten Assertions.*
- [ ] **AK6** GIVEN die ausgelieferte Suite WHEN man sie nach Lesezugriffen auf projekteigene Dateien
  des echten Repos durchsucht (`PROJECT-CONTEXT.md`, `.gitignore.project`, `.claude/settings.project.json`,
  `CLAUDE.md`, `README.md`, `CHANGELOG.md`) THEN gibt es keinen außer der begründeten Ausnahme
  `factory.config.yml`. *Beleg: ein Guard-Test mit je einem Negativfall (Mutation: Lesezugriff ergänzen →
  rot) und Fail-closed bei unlesbarer Quelle.*
- [ ] **AK7** GIVEN Fundstelle (2) und Factory-ADR-064 D6 WHEN diese Task abgeschlossen wird THEN verweist
  die Task-Datei auf AK-28a/28c (spec-23) als Beleg der Erledigung, und Factory-ADR-064 D6 wird nicht
  doppelt geändert.

## Fehlerszenarien

- [ ] **FS1** Die Fixture-`PROJECT-CONTEXT.md` lässt sich nicht bauen (Schreibfehler im Temp-Verzeichnis) →
  die Suite bricht mit klarer Meldung ab, nicht still grün.
- [ ] **FS2** Die Fixture weicht vom Tabellenformat ab, das `label_drift_431` liest (`| \`label\` |`) →
  die Positivkontrolle (AK3) wird rot, statt dass die Mutationen aus dem falschen Grund bestehen.
- [ ] **FS3** `yq` fehlt → der Block wird wie bisher per `skip_yq` sichtbar übersprungen (kein stilles Grün).

## Offene Fragen

- [x] **Q1** Scope: entschieden (Ralf, 2026-10-27) – nur (1) auf Fixtures umstellen; (3) die Validierung der
  echten `factory.config.yml` bleibt.
- [ ] **Q2** Ist das Risiko aus dem Issue real? Zu belegen vor der Umsetzung (Hypothese: nein, weil die
  Assertions nur „enthalten" prüfen – dann ist die Umstellung Härtung, kein Fehlerbehebung).
- [ ] **Q3** Wohin gehört der Zustandsprüfung der echten `PROJECT-CONTEXT.md` im Factory-Repo (AK5):
  Projekt-Suite oder bestehender Guard `customization-points`? Entscheidung beim Architekten, falls ADR-Trigger.
