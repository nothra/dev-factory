# Spec: ownership-check.sh liest jeden getrackten Pfad ungequotet und überspringt keinen (#63)

## Kontext

`scripts/checks/ownership-check.sh` ordnet jede getrackte Datei genau einer Seite (`factory` | `project`) zu und ist
mit `--list factory` die Quelle der Liefermenge (Release-Manifest, filter-repo-Allowlist; Factory-ADR-063 D5,
Factory-ADR-064). Das Issue (gefunden im Review von nothra/tch-gastro-services#427) beschreibt: `git ls-files` gibt
Pfade mit Nicht-ASCII-Zeichen oktal-gequotet aus (`"docs/f\303\274r.md"`), der Check vergleicht den gequoteten String
mit den Mustern bzw. Lock-Pfaden und gibt ihn bei `--list` gequotet aus.

**Stand `main` (geprüft am 2026-11-25):** Der im Issue genannte Kern ist bereits behoben – seit #22 (PR #25) liest
`load_tracked_files` mit `git -c core.quotepath=false ls-files`; der Test „#22 F-22.3" in
`scripts/checks/tests/run-tests.sh` sichert Umlaut-Pfade **im Lock-Modus** gegen echtes git ab. Für den
**Tabellenmodus** fehlt ein solcher Test.

**Was noch falsch ist (reproduziert gegen echtes git, Tabellenmodus):** `core.quotepath=false` schaltet nur das
Quoten von Bytes > 0x7F ab. Pfade mit `"`, `\` oder Steuerzeichen (Tab, Zeilenumbruch) quotet git weiterhin
C-artig. Ergebnis in einem Wegwerf-Repo mit Muster `docs/**`:

| Pfad | Verhalten heute |
|------|-----------------|
| `docs/für.md` | ✓ richtig zugeordnet und unquotet gelistet |
| `docs/a"b.md`, `docs/a\b.md`, `docs/tab<TAB>x.md` | ✗ als `"docs/a\"b.md"` usw. „keiner Seite zugeordnet" (Falsch-Rot); im Lock-Modus „nicht getrackt" |
| `docs/a\|b.md` | **still übersprungen** – weder gezählt noch gemeldet noch gelistet (fail-open) |

Der letzte Fall ist der schwerere: Der Tabellenmodus zerlegt die Dateiliste mit `|` als Feldtrenner und wertet nur
Zeilen mit genau einem Feld aus. Eine getrackte Datei mit `|` im Namen fehlt damit in der Prüfung **und** in
`--list factory`, ohne dass der Check rot wird – sie würde nicht ausgeliefert, obwohl der Check „vollständig" meldet.

Heute latent: Das Repo enthält keinen solchen Pfad. Der Check ist aber ein Gate, das über Konsumenten-Repos läuft
(dort per `factory.lock` im Lock-Modus), und muss für jeden Pfad richtig oder laut falsch sein, nie still.

## Scope

**Inbegriffen:**
- `scripts/checks/ownership-check.sh`, Lesen der getrackten Dateien aus git (beide Modi): jeder Pfad kommt
  byte-genau so an, wie er im Index steht – unabhängig von `core.quotePath` und von Sonderzeichen im Namen.
- Tabellenmodus: kein getrackter Pfad wird übersprungen; jeder wird zugeordnet oder als Fund gemeldet.
- Pfade, die das zeilenbasierte Ausgabeformat nicht darstellen kann (Zeilenumbruch im Namen): fail-closed statt
  falscher oder zerteilter Ausgabe.
- Regressionstests in der ausgelieferten Suite `scripts/checks/tests/run-tests.sh` gegen echtes git (beide Modi).

**Nicht inbegriffen:**
- Das Format von `OWNERSHIP.md` (Muster mit `|` sind in einer Markdown-Tabelle nicht ausdrückbar; ein solcher Pfad
  darf über ein umfassendes Muster wie `docs/**` zugeordnet werden).
- Das Format von `factory.lock` und der Anpassungsstellen-Liste.
- Die Test-Eingabe `OWNERSHIP_FILE_LIST` (zeilenbasierte Dateiliste statt git): bleibt wie sie ist.
- Das zeilenbasierte Ausgabeformat von `--list` (Konsumenten lesen es zeilenweise).
- Andere Skripte, die `git ls-files` oder `git diff --name-only` lesen. Gleichartige Stellen, die `/implement`
  dabei auffallen, kommen nach der Schwelle in `git-workflow.md` in `kleinfunde.md` oder ein Issue, werden hier
  nicht umgestellt.

## Akzeptanzkriterien

> Gemeinsame Testbedingung: Wegwerf-Git-Repo mit **echtem** `git ls-files` (nicht `OWNERSHIP_FILE_LIST`), darin
> `core.quotepath true` explizit gesetzt (git-Default), eigene `OWNERSHIP.md` bzw. eigener `factory.lock`. Geprüft
> werden Exit-Code und Ausgabe des Checks.

- [ ] **AK1 – Tabellenmodus, Nicht-ASCII (Regression):** GIVEN eine getrackte Datei `docs/für.md` und ein
  Factory-Muster `docs/**`, WHEN `ownership-check.sh` ohne Parameter bzw. mit `--list factory` läuft, THEN Exit 0
  und `--list factory` nennt `docs/für.md` wörtlich (unquotet). (Heute schon grün – sichert den Fix aus #22 für den
  Tabellenmodus ab.)
- [ ] **AK2 – Tabellenmodus, von git weiterhin gequotete Zeichen:** GIVEN getrackte Dateien `docs/a"b.md`,
  `docs/a\b.md` und `docs/tab<TAB>x.md` unter dem Factory-Muster `docs/**`, WHEN der Check läuft, THEN Exit 0, und
  `--list factory` nennt alle drei byte-genau (ohne umschließende Anführungszeichen, ohne Escape-Sequenzen).
- [ ] **AK3 – Tabellenmodus, `|` im Pfad wird nicht übersprungen:** GIVEN eine getrackte Datei `docs/a|b.md` unter
  dem Factory-Muster `docs/**`, WHEN der Check läuft, THEN zählt die Erfolgszeile sie mit (Gesamtzahl = Zahl der
  getrackten Dateien), und `--list factory` nennt `docs/a|b.md`.
- [ ] **AK4 – Tabellenmodus, `|`-Pfad ohne Zuordnung wird gemeldet:** GIVEN eine getrackte Datei `x|y.md`, die kein
  Muster trifft, WHEN der Check läuft, THEN Exit 1 mit `✗ x|y.md: keiner Seite zugeordnet` (nicht still Exit 0).
- [ ] **AK5 – Lock-Modus, gequotete Zeichen:** GIVEN ein `factory.lock`, das `docs/a"b.md` und `docs/a\b.md` als
  Pfade führt, und beide Dateien sind getrackt, WHEN der Check läuft, THEN Exit 0 (kein „nicht getrackt"), und
  `--list factory` bzw. `--list project` nennen die Pfade byte-genau.
- [ ] **AK6 – Zeilenumbruch im Pfad, fail-closed:** GIVEN eine getrackte Datei, deren Name einen Zeilenumbruch
  enthält, WHEN der Check in einem der beiden Modi läuft (mit und ohne `--list`), THEN Exit 2 mit einer Meldung auf
  stderr, die das Problem benennt, und bei `--list` keine Pfadzeile auf stdout – nie ein zerteilter Pfad als zwei
  Listeneinträge.
- [ ] **AK7 – Mutationsbeleg:** GIVEN die Fassung von `main` vor diesem Fix, WHEN die Tests zu AK2–AK6 gegen sie
  laufen, THEN ist jeder davon rot. Kommando und Ergebnis stehen in der Task-Datei.
- [ ] **AK8 – keine Verhaltensänderung sonst:** GIVEN das Repo selbst (nur ASCII-Pfade ohne Sonderzeichen), WHEN
  der Check läuft, THEN sind Exit-Code, Erfolgszeile und `--list factory`/`--list project` identisch zum Stand vor
  dem Fix; die bestehenden Tests der Suite bleiben grün.

## Fehlerszenarien

- [ ] `git ls-files` schlägt fehl (kein Repo, kaputter Index) → weiterhin Exit 2 mit der bisherigen Meldung (AK
  bestehender Tests).
- [ ] Leere Dateiliste → weiterhin Exit 2 (fail-closed, bestehend).
- [ ] Pfad mit Zeilenumbruch → Exit 2 (AK6), auch wenn die Datei sonst zugeordnet wäre.

## Offene Fragen

- [x] **Ist das Issue durch #22 schon erledigt?** Für Umlaute ja, für `"`, `\`, Steuerzeichen und `|` nein (siehe
  Kontext). Die Task deckt den Rest ab; der Issue-Titel bleibt.
- [x] **Zeilenumbruch-Pfade: Exit 2 oder Fund (Exit 1)?** Entschieden (Ralf, 2026-11-25): Exit 2 wie in AK6 – der
  Pfad ist im zeilenbasierten Ausgabeformat nicht darstellbar, das ist ein Eingabeproblem, kein Zuordnungsfehler.
