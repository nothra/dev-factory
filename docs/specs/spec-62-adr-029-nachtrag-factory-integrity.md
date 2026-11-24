# Spec: Factory-ADR-029 – Nachtrag Required Check `factory-integrity` für Konsumenten-Repos (#62)

## Kontext

Konsumenten binden die Factory per `factory.lock` ein (Factory-ADR-063, E8). Der CI-Job `factory-integrity`
(`factory-ci.yml`, `factory-integrity-check.sh --ci`) prüft dort Datei-Hashes gegen das Lock und das Lock gegen das
Release-Manifest des Tags. Ein Gate, das den Merge nicht verhindern kann, schützt nichts: ohne Eintrag unter den Required
Checks von `protect-main` ließe sich ein PR mit lokal geänderter Factory-Datei oder manipuliertem Lock mergen. Lokale Hooks
sind per `--no-verify` umgehbar; das Ruleset ist die einzige serverseitige, auch für Admins gültige Durchsetzung
(Factory-ADR-029).

Factory-ADR-029 gehört der Factory und ist im Konsumenten hash-gesichert (nicht änderbar) – die Entscheidung gehört deshalb
in dieses Repo. Der Auslöser ist nothra/tch-gastro-services#428 (AK2.14c); Factory-ADR-063 verweist schon darauf
(„ADR-029 nachtragen"). Im Factory-Repo selbst ist `factory-integrity` ein No-op (kein `factory.lock`) und kein Required Check.

**Form (Entscheidung):** wie bei ADR-041 und ADR-064 ein Eintrag im Abschnitt „Bezug zu anderen ADRs" von
`docs/factory/adr/029-branch-protection-main-ruleset.md`; kein neuer ADR. Der Entwurf aus dem Issue (eigener ADR des
Konsumenten) dient nur als Textvorlage, Projekt-Kontext (Ruleset-ID `19162920`, „siebter Check", `#428`-Bestandszahlen) entfällt.

## Scope

**Inbegriffen:**
- Nachtrag in Factory-ADR-029 (Abschnitt „Bezug zu anderen ADRs") mit Entscheidung, Begründung, Reihenfolge,
  Fail-closed-Folge, Notfall und Soll-Ist-Abgleich.
- Neuer Schritt in `docs/factory/OPERATING.md` (Einrichtung im Konsumenten-Repo) mit Reihenfolge-Hinweis.
- Konsistenz mit dem ADR-Index `docs/factory/adr/README.md`.
- Eintrag in `CHANGELOG.md` → `Unreleased`, damit der nächste Release beides enthält.

**Nicht inbegriffen:**
- Änderung am Ruleset eines Repos (menschlicher Schritt im Konsumenten) oder am Ruleset des Factory-Repos.
- Änderung am Job `factory-integrity`, an Skripten oder Tests.
- Ein eigener neuer ADR; Umschreiben des JSON/der Check-Liste im Konfigurations-Abschnitt von ADR-029 (beschreibt das
  Ursprungs-Ruleset; der Nachtrag sagt das ausdrücklich und nennt nur das Delta).
- Neue getrackte Datei außer dieser Spec und der Task-Datei (beide Seite `project`, `docs/specs/**` bzw. `tasks/**`;
  `OWNERSHIP.md` braucht keine neue Zeile, vor dem PR zu bestätigen).

## Akzeptanzkriterien

- [ ] GIVEN `docs/factory/adr/029-branch-protection-main-ruleset.md` WHEN der Abschnitt „Bezug zu anderen ADRs" gelesen wird
  THEN steht dort ein Eintrag „Factory-ADR-063 / `factory-integrity`", der festhält: Für **Konsumenten-Repos** (mit
  `factory.lock`) ist der Job `factory-integrity` aus `factory-ci.yml` Required Check von `protect-main`; im Factory-Repo
  ist er No-op und **kein** Required Check (dort bleibt die Liste `lint`, `factory-self-test`, `pr-closes-issue`,
  `config-validation`, `project-self-test`).
- [ ] GIVEN der Nachtrag WHEN die Begründung gelesen wird THEN erklärt sie: ein nicht erzwingbares Gate schützt nichts
  (PR mit geänderter Factory-Datei bzw. manipuliertem Lock wäre mergebar); das Ruleset ist die einzige serverseitige, auch
  für Admins gültige Durchsetzung, lokale Hooks sind per `--no-verify` umgehbar.
- [ ] GIVEN der Nachtrag WHEN die Reihenfolge für Konsumenten gelesen wird THEN steht: erst Merge der Erst-Einbindung (der
  Check muss auf `main` existieren und mindestens einmal gelaufen sein), danach das Ruleset ändern; andernfalls hängt der
  nicht existierende Pflichtcheck jeden PR auf.
- [ ] GIVEN der Nachtrag WHEN die Fail-closed-Folge gelesen wird THEN steht: sind Factory-Repo, Tag oder Manifest nicht
  erreichbar, blockiert der Check alle PRs; Notfall: Check kurz aus dem Ruleset nehmen und den Vorfall dokumentieren.
- [ ] GIVEN der Nachtrag WHEN der Soll-Ist-Abgleich gelesen wird THEN gibt es einen `gh api …/rulesets/<id>`-Befehl
  (Repo und ID als Platzhalter, nicht die des Ursprungs-Projekts) und die Erwartung „Check-Liste + `factory-integrity`,
  sonst unverändert (`enforcement`, `bypass`, `strict`, `merge`)".
- [ ] GIVEN der Nachtrag WHEN er mit dem Rest von ADR-029 verglichen wird THEN widerspricht er ihm nicht: Status bleibt
  `Accepted`, das JSON im Konfigurations-Abschnitt bleibt unverändert und der Nachtrag benennt es als Stand des
  Ursprungs-Rulesets (Muster ADR-064).
- [ ] GIVEN `docs/factory/OPERATING.md` WHEN die Einrichtung eines Konsumenten-Repos gelesen wird THEN gibt es einen Schritt
  „Required Check `factory-integrity` eintragen (nach dem ersten Merge)" an der Stelle, die zum Abholen/Integritäts-Gate
  (§5.5a) bzw. zur Einmal-Einrichtung passt, mit Reihenfolge, Verweis auf den Nachtrag in Factory-ADR-029 und – falls
  das Inhaltsverzeichnis betroffen ist – aktualisiertem TOC.
- [ ] GIVEN `docs/factory/adr/README.md` WHEN Zeile 029 gelesen wird THEN stimmen Titel und Status mit dem ADR überein
  (Status `Accepted`; ein Nachtrag ändert den Status nicht).
- [ ] GIVEN `CHANGELOG.md` → `Unreleased` WHEN der nächste Release vorbereitet wird THEN steht dort ein Eintrag zu #62, der
  für Konsumenten den neuen Schritt (Required Check eintragen, Reihenfolge) benennt.
- [ ] GIVEN der Diff WHEN `bash scripts/checks/pre-commit.sh` und `pre-push.sh` laufen THEN sind alle Gates grün
  (insbesondere Ownership-, Import-Deckel- und Herkunftsbegriff-Prüfung; Verweise auf `nothra/tch-gastro-services` nur qualifiziert).

## Fehlerszenarien

- [ ] Konsument trägt den Check **vor** dem Merge der Erst-Einbindung ein → Anleitung warnt ausdrücklich, dass jeder PR
  (auch der Einbindungs-PR) hängt, und nennt die Behebung (Check wieder austragen).
- [ ] Factory-Repo/Tag/Manifest nicht erreichbar → Anleitung nennt das Notfallverfahren samt Dokumentationspflicht, ohne
  das Gate dauerhaft zu entschärfen.
- [ ] Verwechslung Factory-Repo vs. Konsument → Text trennt beide Fälle eindeutig (Check-Liste je Seite).

## Offene Fragen

- [x] Ort des OPERATING-Schritts: **entschieden (Mensch, 2026-11-24):** eigener Unterabschnitt **0.7** in §0
  („Einmal-Setup", nach 0.6), weil es ein einmaliger menschlicher Einrichtungsschritt ist (Muster 0.6); §5.5a verweist darauf.
- [x] Wording des Entwurfs („siebter Check"): **entschieden (Mensch, 2026-11-24):** nicht übernehmen, neutral formulieren
  („zusätzlich zu den bestehenden Checks"), da Konsumenten unterschiedliche Listen haben.
