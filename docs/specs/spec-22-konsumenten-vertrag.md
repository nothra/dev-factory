# Spec: Konsumenten-Vertrag (Ownership-Modus, konsumenten-neutrale Self-Tests) – T2a-1

> **Teil-Task T2a-1** von `nothra/tch-gastro-services#428` (Epic `nothra/tch-gastro-services#424`).
> Kriterien-Quelle ist `spec-428-factory-versioniert-per-factory-lock-einbinden.md` im Ursprungs-Repo
> (Branch `feature/428-factory-split-t2-factory-lock-einbinden`, bis zum Merge dort). Hier stehen die
> Kriterien AK2.15a–c und AK2.16a–b, verfeinert auf den Ist-Stand von v0.6.1. Entscheidung:
> Factory-ADR-063 (Nachtrag 2026-10-24, Q7/Q8). Reihenfolge strikt A → B → C → TCH-Erst-Einbindung;
> diese Task ist **A**.

## Kontext

Die Factory liefert Skripte und Self-Tests an Repos aus, die sie einbinden. v0.6.1 ist in so einem
Repo nicht lauffähig:

- `ownership-check.sh` verlangt `docs/factory/OWNERSHIP.md` und eine Tabelle mit Muster-Zeilen. Ein
  Konsument müsste eine Zuordnungstabelle pflegen, die die Factory selbst schon durch `factory.lock`
  kennt (Pfadmenge je Version).
- Die ausgelieferte Self-Test-Suite `factory-self-test` prüft teils den Zustand des Factory-Repos
  (`ci.yml`, `release.yml`, Dateizahlen, `OWNERSHIP.md`). In einem Konsumenten ist sie damit rot,
  ohne dass dort etwas kaputt wäre.

Ohne diese Task bleibt jede spätere Einbindung (T2a-4, TCH) an diesen beiden Stellen rot.
`factory.lock` selbst und das Abhol-Werkzeug entstehen erst in T2a-2 (#23); hier wird nur der
**lesende** Vertrag festgelegt.

## Scope

**Inbegriffen:**
- `ownership-check.sh` kennt zwei Modi: mit `factory.lock` im Repo-Wurzelverzeichnis gilt der Lock,
  ohne Lock gilt `OWNERSHIP.md` (Verhalten wie bisher).
- `OWNERSHIP.md` wird in diesem Repo projekteigen (Seite `project`) und ist nicht mehr Teil des
  Release-Manifests.
- Die Factory liefert die Liste ihrer Anpassungsstellen selbst mit (Entscheidung 2026-10-24, Q-22.1).
- Die Self-Test-Suite wird konsumenten-neutral. Prüfungen, die das Factory-Repo voraussetzen, wandern
  nach `scripts/project/tests/` und laufen nur dort.
- Vorher/Nachher-Liste der Testgruppen im PR als Beleg, dass nichts ersatzlos entfällt.

**Nicht inbegriffen:**
- Erzeugen, Schreiben und Aktualisieren von `factory.lock`, Abholen einer Version, Release-Manifest-
  Format, Änderungs-Gate `factory-integrity` (T2a-2, #23).
- Update-PR-Workflow (T2a-3, #24).
- Erst-Einbindung in TCH, Entfernen von TCHs `OWNERSHIP.md` (AK2.15d, T2a-4, `nothra/tch-gastro-services#428`).
- Hash-Prüfung der Dateien gegen den Lock. Der Ownership-Check liest nur die **Pfadmenge**.
- Ein Release. In #22 wird keine Version veröffentlicht (Entscheidung 2026-10-24, Q-22.3).
- Neue Prüfungen oder neues Verhalten der Factory über Konsumenten-Vertrag hinaus.

## Akzeptanzkriterien

### Ownership-Modus (AK2.15)

- [ ] **AK2.15a** GIVEN ein Repo mit `factory.lock` WHEN `ownership-check.sh` läuft THEN gilt als Seite
  `factory` genau die Pfadmenge des Locks und alles andere als `project`; der Check braucht keine
  `docs/factory/OWNERSHIP.md` und ist grün, ohne dass das Projekt eine Zuordnungstabelle pflegt.
  *Beleg: Fixture-Repo mit Lock, ohne `OWNERSHIP.md`.*
- [ ] **AK2.15a-2** GIVEN ein Repo mit `factory.lock` WHEN `ownership-check.sh --list factory` bzw.
  `--list project` läuft THEN gibt es die Lock-Pfadmenge bzw. deren Komplement unter den getrackten
  Dateien aus, bei jeder Datei genau einer Seite zugeordnet. *Beleg: Test für beide Seiten.*
- [ ] **AK2.15a-3** GIVEN ein Repo mit `factory.lock` **und** `OWNERSHIP.md` WHEN der Check läuft THEN
  entscheidet allein der Lock (kein Mischmodus); der Check meldet den Modus auf der Ausgabe.
  *Beleg: Fixture mit widersprüchlicher Tabelle, Ergebnis folgt dem Lock.*
- [ ] **AK2.15b** GIVEN dasselbe WHEN ein Lock-Pfad nicht existiert oder ein Pfad einer Anpassungsstelle
  im Lock steht THEN schlägt der Check fehl (Exit 1) und nennt den Pfad. *Beleg: zwei Negativtests,
  je einer pro Fall, jeder mit pfadspezifischem Signal.*
- [ ] **AK2.15b-2** GIVEN die mitgelieferte Liste der Anpassungsstellen (`scripts/checks/customization-points.txt`,
  ADR 064 D4) WHEN sie gelesen wird THEN enthält sie mindestens `CLAUDE.md`, `factory.config.yml`,
  `docs/factory/PROJECT-CONTEXT.md`, `README.md`, `CHANGELOG.md`, `.claude/settings.project.json`,
  `.gitignore.project`, `.github/workflows/ci.yml` und `.github/workflows/release.yml` (Stand
  `PROJECT-CONTEXT.md` „Eigene Anpassungsstellen"); jeder Eintrag steht in `OWNERSHIP.md` auf Seite
  `project`. Die Liste ist eine **Teilmenge** der `project`-Zeilen, nicht deren Gesamtheit (`tasks/**`,
  `docs/specs/**` sind keine Anpassungsstellen). *Beleg: Drift-Guard je Richtung (Eintrag aus der
  Liste auf `factory` setzen / Anpassungsstelle aus der Liste streichen).*
- [ ] **AK2.15c** GIVEN das Factory-Repo (kein Lock) WHEN der Check läuft THEN gilt weiter die Tabelle
  `OWNERSHIP.md` wie bisher (gleiche Meldungen, gleiche Exit-Codes, `--list` unverändert).
  *Beleg: alle bestehenden Ownership-Tests bleiben unverändert grün.*
- [ ] **AK2.15d-0** GIVEN dieses Repo WHEN das Release-Manifest (`factory-release-manifest.sh`) für
  Seite `factory` erzeugt wird THEN enthält es `docs/factory/OWNERSHIP.md` nicht; die Datei steht in
  `OWNERSHIP.md` auf Seite `project`. *Beleg: Manifest-Liste vorher/nachher.*

### Self-Test-Suite (AK2.16)

- [ ] **AK2.16a** GIVEN ein Repo mit eingebundener Factory WHEN die ausgelieferte Self-Test-Suite
  (`factory-self-test`) läuft THEN ist sie grün, ohne dass der Zustand des Factory-Repos vorausgesetzt
  wird (kein Bezug auf dessen `ci.yml`, `release.yml`, Dateizahlen, `OWNERSHIP.md`).
  *Beleg: Lauf der ausgelieferten Suite in einem Fixture, das nur die Dateien der Seite `factory`
  enthält, plus eigene Anpassungsstellen.*
- [ ] **AK2.16b** GIVEN die Factory-Repo-spezifischen Prüfungen WHEN sie geschnitten werden THEN laufen
  sie nur im Factory-Repo (`scripts/project/tests/`), und keine Prüfung ist dabei ersatzlos entfallen.
  *Beleg: Vorher/Nachher-Liste der Testgruppen im PR und Zählvergleich der Assertions
  (Summe vorher = Summe ausgelieferte Suite + `scripts/project/tests/`).*
- [ ] **AK2.16b-2** GIVEN `scripts/project/tests/` WHEN CI und `pre-push.sh` im Factory-Repo laufen THEN
  führen beide diese Tests mit aus (lokal über `scripts/project/checks/pre-push.d/`, in CI über einen Job
  in `ci.yml`; ADR 064 D6), sodass der Schnitt im Factory-Repo keinen Gate-Verlust bedeutet.
  *Beleg: Wiring-Test an der echten Aufrufzeile, nicht am Dateinamen-Fragment.*
- [ ] **AK2.16b-3** GIVEN `scripts/project/tests/` WHEN das Release-Manifest erzeugt wird THEN steht
  dort nichts auf Seite `factory`; jede neue Datei hat eine Zeile in `OWNERSHIP.md`. *Beleg:
  `ownership-check.sh` ist grün.*

## Fehlerszenarien

- [ ] **F-22.1** `factory.lock` ist vorhanden, aber nicht lesbar, leer oder ohne Pfadeintrag → Exit 2
  (fail-closed, wie bei unlesbarer Tabelle), keine stille Rückkehr in den Tabellenmodus.
- [ ] **F-22.2** Die Liste der Anpassungsstellen fehlt oder ist nicht lesbar → Exit 2 mit klarer
  Meldung, nicht „keine Anpassungsstelle verletzt".
- [ ] **F-22.3** Lock-Pfad mit Sonderzeichen (`.`, `+`, `[`) oder Leerzeichen → wörtlich verglichen,
  keine Muster-Auswertung (der Lock nennt Pfade, keine Globs).
- [ ] **F-22.4** Lock nennt einen Pfad doppelt → Meldung mit Pfad, Exit 1, kein stilles Zusammenfassen.
- [ ] **F-22.5** Eine in den Konsumenten-Schnitt verschobene Prüfung hängt von einer gesourcten Lib oder
  einem Fixture ab, das mit ausgeliefert werden muss → Test schlägt rot fehl, statt dass die Suite im
  Konsumenten beim `source` lautlos abbricht.

## Offene Fragen

- [x] **Q-22.1 · Anpassungsstellen im Lock-Modus:** → feste Liste im Factory-Release (entschieden 2026-10-24);
  Ort und Format: `scripts/checks/customization-points.txt`, ein Pfad je Zeile (ADR 064 D4).
- [x] **Q-22.2 · Beleg für AK2.16b:** → Testgruppen-Liste und Zählvergleich im PR (entschieden
  2026-10-24). Ein zusätzlicher Konsumenten-Fixture-Lauf bleibt bei AK2.16a und ist kein eigener
  Aufwandsblock.
- [x] **Q-22.3 · Release:** → in #22 wird kein Release veröffentlicht (entschieden 2026-10-24).
  **Widerspruch zum Issue-Text** (#22: „Je Factory-Task ein Release (nächste MINOR-Version)") und zu
  spec-428 Q1 (Release `v0.7.0` vor dem TCH-PR): Der Issue-Body von #22 muss angepasst werden, sonst
  steht dort eine Regel, die diese Spec überstimmt. Wann das Release kommt (nach #23 oder #24), ist
  für #23/#24 zu klären.
- [x] **Q-22.4 · Lock-Format:** → JSON, identisch mit dem Release-Manifest `factory-release.json`
  (`schema` 1); #23 schreibt den Lock als Kopie, #22 liest `files[].path` per `jq` (ADR 064 D1).
  Ohne `jq` im Lock-Modus Exit 2 (F-22.1).
- [ ] **Q-22.5 · Abstimmung mit dem Update-Weg:** Ändert ein Konsument seine `OWNERSHIP.md` nach
  AK2.15d weg (Lock-Modus), muss die Abholung (#23) wissen, dass `OWNERSHIP.md` im Release nicht mehr
  geliefert wird. Prüfen, dass #23 `OWNERSHIP.md` nicht als zu liefernde Datei erwartet.
