# Security Review: Task 37

Geprüft: `git diff origin/main...HEAD` (Stand `f5ff601`) – Schwerpunkt `scripts/factory-update.sh` (396 Zeilen, vier Modi),
`.github/workflows/factory-update.yml` (vier Jobs), `scripts/lib/factory-lock.sh` (Manifest-Validierung, Pfadregeln),
ADR-063 Nachtrag 2026-10-31 E17–E22 samt Restrisiko-Abschnitt, `docs/factory/OPERATING.md` §0.6. Analyse im Orchestrator-Kontext
(keine Fork-Delegation). Bedrohungsmodell: ein Release der Factory ist kompromittiert (böser Tag/Asset); das Konsumenten-Repo
führt `factory-update.yml` täglich mit einem schreibfähigen Fine-grained PAT aus. Angreifer-Ziele: Token entwenden, Schadcode
am Review vorbei in `main` bringen, den Token-Job zu eigener Ausführung bewegen.

## Kritische Findings (Blocker)

_keine_

## Wichtige Findings

_keine_

## Hinweise

- [ ] **[Lieferkette / CI] Runtime-Token des `fetch`-Jobs gegen Release-Code nicht abgeschirmt – eigenes Issue #41.**
  Im Job `fetch` läuft der Code des ungeprüften Release; im selben Job folgt `actions/upload-artifact@v4` mit dem Runtime-Token
  des Laufs. Release-Code kann über `$GITHUB_ENV`/`$GITHUB_PATH` die Umgebung der Folgeschritte beeinflussen. Das Token ist auf den
  Lauf begrenzt, schreibt aber Caches im Scope von `main`, die `pull_request`-Workflows lesen – relevant nur, wo ein Konsument
  Caches nutzt (das Factory-Repo selbst: keine). **Nicht empirisch nachgestellt** (daher Hinweis, nicht Wichtig). Der ADR-Restrisiko-
  Abschnitt (E22, Punkte 1–4) benennt diesen Weg nicht; Vorschlag in #41: als fünften Punkt aufnehmen und den Konsumenten-Hinweis
  in OPERATING.md §0.6 ergänzen. Kein Blocker für #37: das Token selbst bleibt unerreichbar, das ist die Aufgabe der Task.
- [ ] **[Konfiguration] Schutz hängt an der Branch-Regel `main` des Environments und ist nicht prüfbar.** Ohne die Regel könnte ein
  `pull_request`-Workflow `environment: factory-update` deklarieren und das Secret lesen. Im ADR als Restrisiko 4 benannt, in
  OPERATING.md §0.6 als Einrichtungsschritt und Real-Repo-Beweis (Q-37.3) geführt – bleibt ein menschlicher Schritt, bevor das
  Release ausgeliefert wird.
- [ ] **[Lieferkette] Zusammengesetzte Ziele werden nur per Pfad geprüft.** `.claude/settings.json` und `.gitignore` dürfen sich
  ändern, der Inhalt nicht; ein böses Release kann dort Hooks/Permissions eintragen, die nach dem Merge auf Entwickler-Rechnern
  laufen. Im ADR (Restrisiko 3) als „Prüfung ist das Review des PRs" benannt; bewusst akzeptiert.
- [ ] **[Lieferkette] Actions per Tag (`@v4`) statt per SHA** (`checkout`, `upload-artifact`, `download-artifact`; alle von GitHub).
  Entspricht der Konvention des Repos (14× `checkout@v4`), `download-artifact` läuft im Token-Job. Kein Handlungsbedarf in #37.
- [ ] **[Lokal] Kurzform ohne Modus ist keine Token-Grenze.** Lokal erbt der abgeholte Code Anmeldedaten von `gh auth`/Keychain; in CI
  ist sie verweigert (`GITHUB_ACTIONS=true`), im Kopf als „nur Tests/lokal" gekennzeichnet.
- [ ] **[Inhalte] Release-Notes gelangen ungeprüft in den PR-Body** (`write_body`): Markdown/`@mention`-Einschleusung durch ein böses
  Release. Bestand aus #24, nicht durch #37 verändert; nur Anzeige, keine Ausführung.

## Geprüft ohne Befund

- **Token-Fluss:** `FACTORY_SYNC_TOKEN` steht nur in `preflight` und `publish` (je Environment `factory-update`), nicht in `guard`
  und `fetch`; `fetch` hat kein Environment, `contents: read`, `persist-credentials: false`. Push über Credential-Helper – Token weder
  in argv noch in `.git/config`. Kein Schreiben des Werts in Logs (`die`-Meldungen zitieren nur `gh`-Fehlertext).
- **Handover-Eingaben:** `version`/`base_sha` kommen als Job-Output, laufen über `env:` (keine Expression-Injection im `run:`), und
  werden vor jeder Nutzung gegen `^v\d+\.\d+\.\d+$` bzw. 40-Hex geprüft; `tag_name` ist durch `CANDIDATES_JQ` auf SemVer begrenzt
  (kein Zeilenumbruch in `$GITHUB_OUTPUT`). `publish` liest nur Outputs von `preflight`, nie von `fetch`.
- **Bundle-Prüfung (E18):** genau ein Commit auf `origin/main`; Modi 120000/160000 (auch Typwechsel) abgelehnt; Pfade ⊆ alter Lock ∪
  neues Manifest ∪ zusammengesetzte Ziele ∪ Lock (case-sensitiv, `.git`-Pfade nie erlaubt); Manifest ohne geschützte Stellen;
  `factory.lock` byte-gleich dem frisch geholten Manifest; Hash je Manifest-Datei. Quarantäne wird nie ausgecheckt oder ausgeführt,
  Inhalte nur über `git cat-file`. Der Commit wird per `commit-tree` mit fester Identität neu erzeugt, gepusht per SHA mit Lease.
- **Pfad-Traversal im Token-Job:** `verify_hashes` schreibt Manifest-Pfade unter `$WORK/quarantine`; `fl_validate_manifest` lehnt
  absolute Pfade, `.`/`..`-Segmente, `//`, Backslash, Steuerzeichen und Duplikate ab, geschrieben werden nur reguläre Dateien
  (keine Symlinks), `fl_hash_paths` setzt `./` vor.
- **Hooks/Selbst-Ersatz:** ref-schreibende und prüfende git-Aufrufe laufen mit `core.hooksPath=/dev/null`; `main "$@"; exit $?`
  schützt vor dem Weiterlesen der ersetzten Datei.
- **guard:** Repository-Secret gleichen Namens → rot ohne Wert in der Meldung; Org-Secret gleichen Namens wird mit erfasst.
- **Job-Verkettung:** fehlender Lock, fehlende neue Version oder fehlgeschlagenes `fetch` überspringen `publish`.
- **Tests:** jede `die`-Verzweigung von `fetch`/`publish` mit Meldung + Abwesenheit der Folgestufen und Mutationsbeleg abgedeckt
  (482 grün laut `/test`); Quellcode zwischen `/refactor` und diesem Review unverändert.

## Ergebnis
PASSED
