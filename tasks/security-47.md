# Security Review: Task 47

> Diff `origin/main...HEAD` (frisch gefetcht), Schwerpunkt `scripts/start-work.sh` (`ensure_parent_dirs`,
> `copy_into_worktree`, Spiegel-Block), `scripts/lib/gate-config.sh` (`factory_cfg_list`,
> `factory_cfg_list_dropped`, `copy_entry_problem`), `scripts/checks/config-validation-check.sh` Regel 9.
> Bedrohungsmodell: `start_work.copy_files` steht in der committeten `factory.config.yml`; wer sie ändern kann,
> kann im selben Baum auch `scripts/start-work.sh` und `scripts/lib/gate-config.sh` ändern, die beim Aufruf
> **aus diesem Baum** gesourct werden. Ein Angreifer mit Schreibrecht auf den Quellbaum hat also schon
> Code-Ausführung. Relevant sind daher vor allem Fehlkonfiguration und Datenabfluss über den Folgeprozess
> (Commit/Push), weniger ein Ausbruch über die Pfadregel.

## Kritische Findings (Blocker)

Keine.

## Wichtige Findings

- [ ] [Sensitive Data Exposure] `scripts/start-work.sh:91-99` (`copy_into_worktree`) kopiert jede gelistete
  Datei, ohne zu prüfen, ob sie im **Ziel-Worktree** gitignoret ist. Die Doku nennt die Einträge „gitignorete
  lokale Dateien" (`factory.defaults.yml`, `git-workflow.md:353`), erzwungen wird das aber nirgends. Ist eine
  gelistete Datei nicht ignoriert (Tippfehler, `.env.development.local` neben `.env.local` im `.gitignore`,
  ein Ignore-Eintrag, den es nur im Quell-Branch gibt), liegt das Secret danach als untracked Datei im
  Worktree, und `scripts/factory-commit.sh:89` (`git add -A`) stagt, committet und pusht es im nächsten
  Pipeline-Schritt, ohne dass ein Mensch hinsieht. Vorher war das Risiko nicht da, weil nur `.env.local`
  kopiert wurde und die ausgelieferte `.gitignore.project` genau diese Datei abdeckt. Mit diesem PR ist die
  Liste frei wählbar. **Lösung:** in `copy_into_worktree` vor dem `cp` die Prüfung
  `git -C "$WORKDIR" check-ignore -q -- "$entry"` einbauen. Schlägt sie fehl: warnen
  („$entry ist im Worktree nicht gitignoret – nicht kopiert, damit es nicht committet wird") und überspringen.
  Fail-closed, eine Zeile, kein neues Werkzeug. Dazu einen Test (nicht ignorierte Quelle → keine Kopie +
  Warnung) und einen Satz in ADR E25/E26 und Spec. Das Config-Gate kann das nicht übernehmen, weil das
  Ignore-Ergebnis vom Ziel-Branch abhängt.
  *Repro (R6):* Wegwerf-Repo mit `.gitignore` = `.env.local`, Worktree auf `feature/x`, beide Dateien über
  `copy_into_worktree` gespiegelt, dann `git add -A; git status --short` im Worktree:
  ```
  ✓ .env.local kopiert (Quelle: …/repo)
  ✓ .env.development.local kopiert (Quelle: …/repo)
  A  .env.development.local
  check-ignore .env.development.local rc=1
  check-ignore .env.local rc=0
  ```

## Hinweise

- [ ] [Path Traversal / Quell-Elternkette, von `/review` weitergereicht] `scripts/start-work.sh:85,91`: Die Quelle
  wird über Symlinks aufgelöst (`[ -f ]` und `cp -p` ohne `-P` folgen Symlinks). Ein Eintrag, dessen Quelldatei oder
  dessen Quell-Elternkomponente ein Symlink nach außerhalb des Repos ist, kopiert daher den Inhalt der Datei außerhalb
  in den Worktree (R1/R2: `TOP-SECRET-OUTSIDE` landet als reguläre Datei `leak` bzw. `d/id_rsa` im Worktree, Modus
  600 bleibt erhalten). **Bewertung: kein eigenständiges Risiko.** (a) Ein lokaler, selbst angelegter Symlink
  (`.env.local -> ~/secrets/…`) ist ein legitimer Anwendungsfall, und hier zu folgen ist gewollt. (b) Ein
  **committeter** Symlink liegt auch im Ziel-Worktree. Dann greifen der `-e`/`-L`-Guard bzw. E25 und der Eintrag wird
  übersprungen (R2b: „leak existiert im Worktree bereits", „d ist im Worktree ein Symlink"). (c) Bleibt der Fall
  „Quellbaum steht auf einem fremden Branch mit Symlink und Config, neuer Worktree basiert auf `main`". Dort führt der
  Angreifer aber ohnehin den `start-work.sh` seines Branches aus. Die Schranke wäre also nur Kosmetik. Zusammen mit dem
  Wichtig-Finding oben (nicht gitignoret → `git add -A`) wäre (c) ein Exfiltrationsweg. Der Ignore-Check schließt ihn
  mit, und eine zusätzliche Symlink-Sperre auf der Quellseite ist danach nicht nötig. Für die Doku: E25 sollte
  ausdrücklich sagen, dass die Quellseite Symlinks bewusst folgt.
- [ ] [Path Traversal / Zielseite] E25 hält: Ein Symlink in der Ziel-Elternkette führt zum Überspringen, nichts wird
  außerhalb geschrieben (R3: `d übersprungen – d ist im Worktree ein Symlink`, `outside/` unverändert). Ein TOCTOU
  zwischen `ensure_parent_dirs` und `cp` (`start-work.sh:92-98`) bräuchte einen Prozess desselben Nutzers, der
  parallel im frischen Worktree Symlinks austauscht. Das liegt außerhalb des Bedrohungsmodells, kein Handlungsbedarf.
- [ ] [Output-/Terminal-Injection] `scripts/start-work.sh:47,99` (`warn_copy` und die Erfolgszeile nutzen
  `echo -e "… $entry …"`): Backslash-Sequenzen in einem **gültigen** Eintrag werden interpretiert. Der Validator
  verbietet nur echte Steuerzeichen, nicht die Zeichenfolge `\`+Buchstabe. R5: Der Eintrag `x\c` schneidet die
  Ausgabe nach `x` ab (die Meldung „kopiert (Quelle: …)" fehlt), und `y\e]0;PWNED\a` gibt ein echtes BEL-Byte (`\a`)
  aus. Mit `\0033` ließe sich auf demselben Weg ESC und damit eine Terminal-Escape-Sequenz erzeugen. Die Wirkung
  beschränkt sich auf die Anzeige im Terminal desjenigen, der die Config ohnehin committet hat. Einfacher Fix: die
  Meldungen mit `printf '  %b⚠  %s%b\n' "$YELLOW" "…$entry…" "$NC"` ausgeben (Farbcodes als `%b`, Eintrag als
  `%s`) oder `$(printf '%q' "$entry")` wie im Ungültig-Zweig (`:83`). Klasse B (`kleinfunde.md`), siehe unten.
- [ ] [Fehlermeldung] `scripts/checks/config-validation-check.sh:262-265`: Liefert `yq` bei Regel 9 einen Fehler,
  endet das Gate fail-closed (rc=1), meldet aber irreführend „ist keine Liste (Typ: )" (R7, yq-Stub). Das Gate
  läuft mit `set -uo pipefail` ohne `-e`. Sicher, nur die Diagnose ist ungenau. Kein Handlungsbedarf in diesem PR.
- [ ] [Hygiene, vorbestehend] `scripts/probe47.tmp.sh`, `scripts/review47.tmp.sh`, `scripts/review47b.tmp.sh`
  liegen weiter (gitignoret) im Baum. Das hat `/review` bereits gemeldet, hier nur zur Erinnerung: vor dem Merge
  manuell löschen. Die Repro-Sonde dieses Reviews hat sich selbst gelöscht.

## Ergebnis
PASSED

> Kein Blocker. Das Wichtig-Finding (fehlender `check-ignore` vor der Kopie) sollte **in diesem PR** behoben
> werden: Es ist eine Zeile, es ist fail-closed, und erst dieser PR öffnet den Abfluss über `git add -A`.

## Geprüft

| Katalogpunkt | Ergebnis | Beleg |
|---|---|---|
| Path-Traversal Eintrag (`..`, absolut, leer, `/`-Ende, Steuerzeichen) | blockiert in Gate (Regel 9) und Skript (`copy_entry_problem`, `:81-84`) | R7: `../x` → „'..'-Segment", rc=1 |
| Quell-Symlinks (Datei / Elternkette) | werden gefolgt, bewertet als Hinweis | R1, R2, R2b |
| Ziel-Elternkette mit Symlink / Nicht-Verzeichnis | übersprungen (E25), kein Schreiben außerhalb | R3 |
| Nie überschreiben (auch defekter Symlink) | `-e \|\| -L` (`:94`) | R2b |
| Argument-Injection (`-rf`, `--help`) | keine: `src`/`dst`/`dir` beginnen stets mit absolutem `$FACTORY_DIR`/`$WORKDIR` | R4: Dateien `-rf`, `--help` regulär kopiert |
| Glob / Leerzeichen (`*`, `a b`) | durchgehend gequotet, `IFS= read -r` | R4: `*` und `a b` als Literale kopiert |
| Newline im Eintrag | Gate lehnt ab, `factory_cfg_list` verwirft und zählt | Code + `/review`-Sonde |
| yq-Ausdruck-Injection | keine: Pfad ist Konstante `start_work.copy_files`, Index `$i` ist ein Zähler, Werte werden nie interpoliert | Code `gate-config.sh:40-56`, Gate `:262-276` |
| Modus der Kopie | `cp -p` erhält 600 | R1: `-rw-------` |
| Logs | nur Pfade und Quellbaum, nie Inhalte | Code `:83-106` |
| Aufräumen bei Teilfehler | `rm -f "$dst" \|\| true` nur nach eigenem Fehlschlag, vorbestehendes Ziel ausgeschlossen | Code `:100-106` |
| `.gitignore`-Abdeckung im Ziel | **nicht geprüft** → Wichtig-Finding | R6 |
| Doku Secret-Hygiene | `git-workflow.md:289`, FACTORY.md Kern-Kurzregel 8, `factory.defaults.yml` @tradeoff | gelesen |
| Fail-closed Gate Regel 9 | ja, auch bei yq-Fehler | R7: rc=1 |
| Unlesbare Config in `start-work.sh` | warnt, kopiert nichts (fail-safe) | Code + `/review`-Test |
| Credentials im Code | keine | Diff gelesen |
| Neue Dependencies | keine (yq gepinnt über `install-yq.sh`, unverändert) | Diff |

Repro-Sonde: `scripts/sec47.tmp.sh` (gitignoret, `*.tmp.*`). Sie arbeitete ausschließlich in `mktemp -d` unter
`$TMPDIR`, hat die Funktionen `warn_copy`/`ensure_parent_dirs`/`copy_into_worktree` unverändert aus
`start-work.sh` extrahiert und das Gate mit echten Defaults gegen Wegwerf-Overrides aufgerufen. Danach hat sie sich
per EXIT-Trap samt Temp-Verzeichnis gelöscht (`git status --ignored scripts/` zeigt sie nicht mehr).

### Out-of-Scope-Vorschläge (Anlage durch den Orchestrator)

- **Klasse B (`kleinfunde.md`)** – Titel: „start-work.sh: `echo -e` interpretiert Backslash-Sequenzen in
  copy_files-Einträgen". Body: „`warn_copy` und die Erfolgsmeldung in `copy_into_worktree`
  (`scripts/start-work.sh:47,99`) geben den Eintrag über `echo -e` aus. Ein gültiger Eintrag wie `x\c` schneidet die
  Meldung ab, `\a`/`\0033` erzeugen Steuerbytes im Terminal. Fix: Eintrag als `%s` über `printf` ausgeben oder mit
  `printf '%q'` quoten wie im Ungültig-Zweig (`:83`). Nur Anzeige, die Config-Hoheit liegt ohnehin beim Committer."
  (Nur falls der Fix nicht gleich mit dem Wichtig-Finding in diesem PR erledigt wird. Er berührt dieselbe Funktion.)
- Das Wichtig-Finding ist **in Scope** und gehört in diesen PR, nicht in ein Issue. Falls der Orchestrator es doch
  auslagert: **Klasse A (Issue, Label `security`)**, Titel „start-work.sh: copy_files kopiert nicht gitignorete
  Dateien – Secret kann per `git add -A` committet werden", Body = Text des Wichtig-Findings inkl. Repro R6.
