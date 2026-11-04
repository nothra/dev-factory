# Spec: Worktree-Dateispiegelung über `start_work.copy_files` konfigurierbar

> Issue #47. Folgt Factory-ADR-063 Q4 (Ursprungs-spezifische Schritte von `start-work.sh` in die
> Config, wie `commands.install` und `start_work.hint`). Löst die feste `.env.local`-Spiegelung aus
> nothra/tch-gastro-services#236 ab, ohne deren Schutzlogik aufzugeben.

## Kontext

`scripts/start-work.sh` legt jede neue Task in einem eigenen Worktree an. Gitignorete lokale
Konfiguration wandert dabei nicht mit. Heute spiegelt das Skript deshalb genau eine Datei, die
`.env.local`, in den Worktree. Name und Begründung (WHY-Kommentare zu `pnpm test:e2e`, `dotenv`,
`CredentialsSignin`) kommen aus dem Ursprungs-Repo. Zusätzlich erscheint `start_work.hint` nur dann,
wenn genau diese Datei kopiert wurde.

Folgen für ein adoptierendes Projekt:
- Andere oder mehrere lokale Dateien (`.env`, `.dev.vars`, `config/local.yml`) werden nie gespiegelt.
- Ein Projekt ohne `.env.local` bekommt seinen konfigurierten Hinweis nie zu sehen.
- Skript, Hilfetext und Self-Tests tragen Ursprungs-Wortlaut (`pnpm db:seed`, Label `factory-pipeline`).

**Primärer Nutzer:** wer in einem Factory-nutzenden Repo `start-work.sh` aufruft und im neuen
Worktree sofort mit seiner lokalen Konfiguration arbeiten will. Sekundär: der Maintainer, der die
Liste der zu spiegelnden Dateien einmal in `factory.config.yml` festlegt.

**Zeitpunkt:** vor der Reintegration ins Ursprungs-Repo (spätestens mit
nothra/tch-gastro-services#428). Kommt der Schlüssel vorher, setzt das Ursprungs-Projekt bei der
Umstellung einmalig `start_work.copy_files: [".env.local"]` und behält sein Verhalten.

## Begriffe

- **Eintrag:** ein Element der Liste `start_work.copy_files`, ein Pfad relativ zur Repo-Wurzel.
- **Quelle:** `<FACTORY_DIR>/<Eintrag>`, also der Baum, in dem `start-work.sh` liegt (wie heute).
- **Ziel:** `<Worktree>/<Eintrag>`.
- **Opt-out:** `FACTORY_WT_SKIP_COPY=1`, oder als Alias der bisherige Name `FACTORY_WT_SKIP_ENV=1`.

## Scope

**Inbegriffen:**
- Neuer Config-Schlüssel `start_work.copy_files` (Liste von Pfaden), Default leere Liste, mit
  `@reason`/`@tradeoff` in `factory.defaults.yml` (Factory-ADR-011).
- Validierung des Schlüssels im Config-Gate (`config-validation-check.sh`).
- Spiegelung jedes Eintrags in den neuen Worktree mit der bisherigen Schutzlogik: nie überschreiben,
  Modus erhalten, Aufräumen bei Fehlschlag, kein Abbruch des Laufs.
- Fehlende Elternordner des Ziels innerhalb des Worktrees werden angelegt.
- Neuer Opt-out-Name `FACTORY_WT_SKIP_COPY`, alter Name `FACTORY_WT_SKIP_ENV` bleibt als Alias.
- `start_work.hint` wird unabhängig von der Kopie ausgegeben: immer, wenn er gesetzt ist.
- Ursprungs-Wortlaut entfernt aus `start-work.sh` (Kommentare, Meldungen, Hilfetext inkl.
  `factory-pipeline`) und aus den zugehörigen Self-Tests (Fixture ohne `pnpm db:seed`).
- Doku nachgezogen: `FACTORY.md` Kern-Kurzregel 8, `git-workflow.md` (Env-Schalter,
  Secret-Hygiene), `OPERATING.md` (Config-Knöpfe), `CHANGELOG.md` (Konsumenten-Hinweis inkl.
  Migrationszeile für Projekte, die die `.env.local`-Kopie behalten wollen), die Kommentare in
  `.gitignore`/`.gitignore.project`, die heute „start-work.sh spiegelt .env.local" behaupten.

**Nicht inbegriffen:**
- Verzeichnisse oder Glob-Muster als Eintrag – nur exakte Pfade zu einzelnen Dateien.
- Spiegelung im In-Place-Modus (`FACTORY_NO_WORKTREE=1`) – dort gibt es keinen neuen Baum.
- Synchronisation späterer Änderungen der Quelle in bestehende Worktrees.
- Eintrag `start_work.copy_files` in der `factory.config.yml` **dieses** Repos – das Factory-Repo
  hat keine lokale Konfiguration zu spiegeln; es bleibt beim Default.
- Umstellung der `factory.config.yml` des Ursprungs-Repos – Teil der Reintegration
  (nothra/tch-gastro-services#428), hier nur als CHANGELOG-Hinweis.
- Andere Schritte von `start-work.sh` (Issue-Anlage, Install, Push, Draft-PR).

## Akzeptanzkriterien

> Belege laufen offline in der ausgelieferten Suite `scripts/checks/tests/run-tests.sh` (bestehende
> Fixture der Gruppe „#236", in eine neutral benannte Gruppe überführt), mit neutralen Dateinamen und
> neutralem Hinweis-Wortlaut.

### Spiegelung

- [ ] **AK1 – Default kopiert nichts.** GIVEN `start_work.copy_files` ist nicht gesetzt (Default `[]`)
  und im Quellbaum liegt eine `.env.local` WHEN `start-work.sh` einen Worktree anlegt THEN entsteht im
  Worktree keine `.env.local`, der Output enthält keine Kopier-Meldung und der Lauf endet mit Exit 0.
- [ ] **AK2 – Genau die gelisteten Dateien.** GIVEN `copy_files` listet zwei Dateien, beide liegen im
  Quellbaum, und eine dritte, nicht gelistete gitignorete Datei liegt ebenfalls dort WHEN ein Worktree
  angelegt wird THEN liegen die beiden gelisteten Dateien byte-identisch im Worktree, die nicht
  gelistete nicht, und der Output nennt je kopierter Datei ihren Pfad.
- [ ] **AK3 – Modus bleibt erhalten.** GIVEN eine gelistete Quelle mit Modus `600` bzw. `664` WHEN sie
  gespiegelt wird THEN hat das Ziel denselben Modus (unabhängig von der `umask`).
- [ ] **AK4 – Nie überschreiben.** GIVEN am Zielpfad eines Eintrags liegt bereits eine Datei oder ein
  (auch defekter) Symlink WHEN ein Worktree-Lauf diesen Pfad spiegeln würde THEN bleibt das Ziel
  unverändert (byte-identisch bzw. derselbe Link), der Output warnt je betroffenem Eintrag, und die
  übrigen Einträge werden trotzdem gespiegelt. Ein **Mutationsbeleg** zeigt, dass der Test rot wird,
  wenn der Überschreib-Schutz entfernt wird.
- [ ] **AK5 – Unterordner.** GIVEN ein Eintrag `config/local.yml`, dessen Ordner `config/` im neuen
  Worktree nicht existiert WHEN der Eintrag gespiegelt wird THEN wird `config/` im Worktree angelegt und
  die Datei byte-identisch dorthin kopiert.
- [ ] **AK6 – Symlink als Quelle.** GIVEN eine gelistete Quelle ist ein Symlink auf eine reguläre
  Datei WHEN sie gespiegelt wird THEN liegt im Worktree eine echte Datei-Kopie (kein Symlink) mit dem
  Inhalt des Link-Ziels (bisheriges Verhalten bleibt gepinnt).

### Opt-out

- [ ] **AK7 – Neuer Schalter.** GIVEN `copy_files` listet eine vorhandene Datei WHEN `start-work.sh`
  mit `FACTORY_WT_SKIP_COPY=1` läuft THEN wird nichts gespiegelt, der Lauf endet mit Exit 0.
- [ ] **AK8 – Alter Name als Alias.** GIVEN wie AK7 WHEN stattdessen `FACTORY_WT_SKIP_ENV=1` gesetzt ist
  THEN verhält sich der Lauf wie in AK7.
- [ ] **AK9 – Opt-out sichtbar.** GIVEN `copy_files` ist nicht leer WHEN gespiegelt wird THEN nennt der
  Output den Opt-out-Schalter `FACTORY_WT_SKIP_COPY=1` (wie heute in der Ankündigungszeile).

### Hinweis

- [ ] **AK10 – Hinweis entkoppelt.** GIVEN `start_work.hint` ist gesetzt und `copy_files` ist leer
  WHEN `start-work.sh` durchläuft THEN enthält der Abschluss-Output den Hinweis-Wortlaut.
- [ ] **AK11 – Hinweis in jedem Modus.** GIVEN `start_work.hint` ist gesetzt WHEN `start-work.sh` im
  In-Place-Modus (`FACTORY_NO_WORKTREE=1`) bzw. mit Opt-out läuft THEN enthält der Abschluss-Output den
  Hinweis ebenfalls.
- [ ] **AK12 – Kein Hinweis ohne Eintrag.** GIVEN `start_work.hint` ist leer WHEN `start-work.sh`
  durchläuft (mit und ohne gespiegelte Dateien) THEN erscheint keine Hinweis-Zeile.

### Config-Gate

- [ ] **AK13 – Gültige Liste wird angenommen.** GIVEN eine `factory.config.yml` mit
  `start_work.copy_files: [".env.local", "config/local.yml"]` WHEN das Config-Gate läuft THEN ist es grün.
- [ ] **AK14 – Ungültige Einträge werden abgelehnt.** GIVEN `copy_files` enthält einen der folgenden
  Werte WHEN das Config-Gate läuft THEN schlägt es fehl und nennt Schlüssel und Grund – je Fall ein
  Test: absoluter Pfad (`/etc/passwd`), Pfad mit `..`-Segment (`../x`, `a/../../x`), leerer String,
  Nicht-String (Zahl, Bool, null), Wert statt Liste (`copy_files: ".env.local"`), Pfad mit
  abschließendem `/`.
- [ ] **AK15 – Konsument behält sein Verhalten.** GIVEN ein Projekt setzt
  `start_work.copy_files: [".env.local"]` WHEN `start-work.sh` einen Worktree anlegt THEN wird die
  `.env.local` wie bisher gespiegelt (Verhaltenstest gegen die echte Config-Schicht, nicht nur
  Gate-Grün – Lesson nothra/tch-gastro-services#348).

### Ursprungs-Wortlaut und Doku

- [ ] **AK16 – Kein Ursprungs-Wortlaut.** GIVEN der fertige Stand WHEN `scripts/start-work.sh` und die
  Testgruppe der Spiegelung nach `pnpm`, `db:seed`, `dotenv`, `CredentialsSignin`, `SEED_ADMIN` und
  `factory-pipeline` durchsucht werden THEN gibt es keinen Treffer (qualifizierte Herkunftsverweise
  `nothra/tch-gastro-services#<nr>` bleiben erlaubt).
- [ ] **AK17 – Doku stimmt.** GIVEN der fertige Stand WHEN `FACTORY.md` (Kern-Kurzregel 8),
  `git-workflow.md`, `OPERATING.md`, `.gitignore`-Kommentare und `factory.defaults.yml` gelesen werden
  THEN beschreibt keine Stelle mehr eine feste `.env.local`-Kopie, der Env-Schalter heißt
  `FACTORY_WT_SKIP_COPY` (Alias erwähnt), und `CHANGELOG.md` nennt die Änderung samt Migrationszeile
  `start_work.copy_files: [".env.local"]`.
- [ ] **AK18 – Gates grün.** Self-Test-Suite, Projekt-Suite, `bash -n` und das
  `@import`-Kontext-Limit bleiben grün.

## Fehlerszenarien

Jeder Fall: **kein Abbruch**, Lauf erreicht „Bereit!" mit Exit 0, übrige Einträge werden weiter
gespiegelt. Eine Warnung im Output gibt es in allen Fällen außer F1 und F7.

- [ ] **F1 – Quelle fehlt** (oder ist ein defekter Symlink): Eintrag wird übersprungen, kein Ziel entsteht.
  Ohne Warnung, wie heute bei fehlender `.env.local` – ein Projekt kann Dateien listen, die nicht jeder
  Entwickler hat.
- [ ] **F2 – Quelle ist ein Verzeichnis:** Warnung (Verzeichnisse sind kein erlaubter Eintrag),
  Eintrag wird übersprungen, kein Ziel entsteht.
- [ ] **F3 – Quelle nicht lesbar:** Warnung, kein Ziel bleibt zurück (Test übersprungen, wenn als root).
- [ ] **F4 – Kopie bricht nach dem Anlegen des Ziels ab** (Teilabbruch, `-p` misslingt): das
  unvollständige Ziel wird entfernt, damit AK4 es beim nächsten Lauf nicht konserviert.
- [ ] **F5 – Elternordner lässt sich nicht anlegen** (z. B. am Pfad liegt eine Datei): Warnung,
  Eintrag übersprungen.
- [ ] **F6 – Symlink in der Elternkette:** ist ein vorhandener Elternordner des Ziels im Worktree ein
  (getrackter) Symlink – egal wohin er zeigt –, wird der Eintrag nicht kopiert und gewarnt. So wird nie
  außerhalb des Worktrees geschrieben oder ein Ordner angelegt (Factory-ADR-063 E25).
- [ ] **F7 – Worktree-Pfad ist kein Verzeichnis** (Wiederverwendungs-Zweig trifft auf eine reguläre
  Datei): Spiegelung entfällt wirkungslos, wie heute (`-d`-Guard).
- [ ] **F8 – Config nicht lesbar / Gate ausgelassen:** ein ungültiger Eintrag (absolut, `..`) wird
  auch von `start-work.sh` selbst nicht kopiert (Defense in depth – das Gate läuft nur im
  pre-push-Hook, nicht vor `start-work.sh`). Elemente, die kein nicht leerer String ohne Steuerzeichen
  sind, und ein Wert, der keine Liste ist, werden gezählt gewarnt („N Einträge … übersprungen");
  eine nicht lesbare Liste (z. B. `yq` fehlt) wird gewarnt, nichts wird gespiegelt.
- [ ] **F9 – Eintrag ist im Worktree nicht gitignoret** (nachgezogen aus `/security-review` W1, 2026-11-04):
  Warnung, Eintrag übersprungen, kein Ziel entsteht – sonst committete `factory-commit.sh` (`git add -A`)
  die Kopie. Maßgeblich ist das Ignore-Ergebnis im Worktree (`git check-ignore`); ein Muster nur in der
  uncommitteten `.gitignore` des Quellbaums zählt nicht (Factory-ADR-063 E26). Geprüft wird der wörtliche
  Pfad (`./<eintrag>`): ein Eintrag mit führendem `:` (Pathspec-Magie) gilt nicht als ignoriert, nur weil
  der aufgelöste Name ohne `:` ignoriert wäre (Security-Nachlauf W2).

## Offene Fragen

- [x] Hinweis-Kopplung: **immer ausgeben, wenn gesetzt**, unabhängig von Kopie und Modus (entschieden 2026-11-01).
- [x] Env-Schalter: **`FACTORY_WT_SKIP_COPY`, `FACTORY_WT_SKIP_ENV` als Alias** (entschieden 2026-11-01).
- [x] Fehlende Unterordner: **innerhalb des Worktrees anlegen** (entschieden 2026-11-01).
- [x] Eintragsart: **nur einzelne Dateien, keine Verzeichnisse, keine Globs** (entschieden 2026-11-01).
- [x] ADR-Trigger: **Nachtrag 2026-11-01 zu Factory-ADR-063 (E23–E27)**, kein neues ADR
  (`/architecture`, 2026-11-01).
