# Security Review: Task 41

Geprüft: `git diff origin/main...HEAD`, Kernstellen `scripts/factory-update.sh` (Z. 56–68, 190–233, 392–421, 455–477),
`.github/workflows/factory-update.yml` (Job `fetch`), `.github/workflows/factory-ci.yml` (Job `fetch-container-smoke`),
`scripts/checks/tests/factory-lock-41-tests.sh`, `factory-lock-37a-tests.sh`. Statisch geprüft: Lokal war weder Docker
noch die Testgruppe ausführbar, weil die Freigabe fehlte. Annahmen über das Verhalten von Runner, Docker und
`upload-artifact` stehen beim jeweiligen Punkt.

**Bedrohungsmodell:** Release-Code ist feindlich und läuft im Container. Ziel ist das Runtime-Token
(`ACTIONS_RUNTIME_TOKEN`) auf dem Host oder eine Ausführung von Container-Daten auf dem Host.

**Ergebnis der Kernprüfung:** Die Grenze hält für alle Wege, die im Issue und in der Spec genannt sind.
- `$GITHUB_ENV` und `$GITHUB_PATH` sind weder als Variable noch als Mount im Container.
- `sudo` und `/proc` von `Runner.Worker` sind nicht erreichbar: eigener PID-Namensraum, `--cap-drop ALL`,
  `no-new-privileges`, Runner-UID statt root, kein Docker-Socket.
- Die Umgebung enthält nur `-e HOME=/tmp`.
- Der Checkout ist nur lesend eingebunden. `persist-credentials: false` im Job `fetch` ist durch `wf_ok_37` mit Mutation
  belegt, deshalb liegt kein `GITHUB_TOKEN` in `/src/.git/config`.
- Der Rückweg ist auf genau eine reguläre Datei beschränkt. Die Prüfung läuft erst, wenn alle Prozesse im Container
  beendet sind: Mit dem Ende von PID 1 beendet der Kernel den ganzen PID-Namensraum, und `--rm` läuft nicht im
  Hintergrund. Damit gibt es kein TOCTOU-Fenster vor dem Upload.
- Ein Hardlink aus `/out` auf eine Host-Datei scheitert an der Mount-Grenze (EXDEV).
- FIFO, Device-Dateien, Symlinks, Verzeichnisse und Zusatzeinträge weist `require_single_bundle` ab
  (`ls -A` = genau `update.bundle`, `-f`, `! -L`).
- Ein setuid-Bit auf der Datei bleibt wirkungslos: Sie gehört der Runner-UID, und der Host führt sie nicht aus.

Ein echter Rückkanal bleibt: Der Host wertet die Ausgabe des Containers aus (Finding W1).

## Kritische Findings (Blocker)
- keine

## Wichtige Findings
- [ ] [Rückweg / Workflow-Kommandos] `scripts/factory-update.sh:406` (`run_in_fetch_container` Z. 223): stdout und
  stderr des Containers gehen ungefiltert in das Log des Schritts. Der Runner liest dieses Log als Kanal für
  Workflow-Kommandos (`::add-matcher::<host-pfad>`, `::set-output`, `::save-state`, `::add-mask::`, Annotationen,
  `::stop-commands::`). Damit wertet der Host Daten aus dem Container aus, entgegen AK2.1 bzw. E32 („Rückweg nur als
  Daten“).
  - *Kein Weg zum Token bekannt:* `::set-env`/`::add-path` sind seit 2020 standardmäßig abgeschaltet, solange
    `ACTIONS_ALLOW_UNSECURE_COMMANDS` nicht gesetzt ist. Der Schritt hat keine `id`, `::set-output` läuft also ins Leere.
    Das ist eine Annahme über das Verhalten des Runners, nicht verifiziert.
  - *Es bleibt Restfläche:* `::add-matcher::` lässt den Runner eine beliebige Host-Datei als JSON lesen.
    Annotationen können das Log fälschen. Künftige Runner-Kommandos würden automatisch zur Angriffsfläche.
  - *Lösung (klein, im Skript):* Vor `docker run` den Kanal mit einem zufälligen, dem Container unbekannten Token
    sperren, danach wieder freigeben:
    `t="$(head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n')"; echo "::stop-commands::$t"; docker run …; rc=$?; echo "::$t::"`.
    Dazu ein Test, dass beide Zeilen den `run`-Aufruf umschließen. Alternativ die Ausgabe des Containers in eine Datei
    umleiten und nur gefiltert oder gar nicht ausgeben.
  - **In Scope** (Isolationsgrenze dieses PRs), Sicherheitsrisiko gering (Defense-in-Depth), kein Nitpick.

## Hinweise
- [ ] [Netz] `scripts/factory-update.sh:223`: Der Container läuft im Standard-Bridge-Netz (E31, Q3 bewusst so
  entschieden; die Abholung braucht Internet). Darüber erreicht er auch das Bridge-Gateway des Hosts (`172.17.0.1`) und
  die Link-Local-Dienste der Cloud: Azure IMDS `169.254.169.254` und WireServer `168.63.129.16`.
  - *Annahme, nicht verifiziert:* Die Agent-Regel von Azure, die den WireServer nur für root freigibt, greift auf
    `OUTPUT` per UID. Weitergeleiteter Container-Verkehr läuft daran vorbei.
  - Ein Weg zu `ACTIONS_RUNTIME_TOKEN` ist mir darüber nicht bekannt. Das Token liegt im Job-Message bzw. im Prozess
    `Runner.Worker`, nicht bei einem Netzdienst. Das ADR (Restrisiko 2) nennt den Punkt pauschal, aber ohne die
    Link-Local-Adressen.
  - *Härtung (optional):* Vor dem `docker run` `sudo iptables -I DOCKER-USER -d 169.254.0.0/16 -j REJECT` und dasselbe
    für `168.63.129.16/32` und das Bridge-Gateway setzen.
  - **Out-of-Scope** (Q3 bewusst entschieden, offline nicht testbar). Sicherheitsrisiko gering bis unbekannt, eher als
    Folge-Issue bzw. Restrisiko-Präzisierung im ADR.
  - **Ablage (ADR-043, Zweifelsregel → Issue): offen.** Die Anlage über `scripts/lib/create-issue.sh` (Titel „Fetch-Container
    vom Host-Gateway und Link-Local-Diensten abschotten", `enhancement` + `security`) brauchte eine Freigabe, die die
    Session nicht hatte. Vor dem Merge nachholen und die Nummer hier eintragen.
- [ ] [Restrisiko Kernel] Ein Ausbruch über einen Fehler im Kernel oder in Docker öffnet Weg 2 wieder: root auf dem
  Runner, dann der Speicher von `Runner.Worker`. Das ADR dokumentiert es ehrlich als Restrisiko 1. Die Optionen
  (`--cap-drop ALL`, `no-new-privileges`, Default-Seccomp/AppArmor, keine Runner-UID 0) sind für diesen Aufwand
  angemessen. **Kein Handlungsbedarf**, nur zur Kenntnis.
- [ ] [Lieferkette Image] `scripts/factory-update.sh:61,207`:
  - Die Basis ist per Digest gepinnt (TOFU). Der Digest ist nicht gegen die Registry verifiziert, das bestätigt erst
    der erste grüne Lauf von `fetch-container-smoke`.
  - `apt` ist ohne Versions-Pins, aber durch die Debian-Schlüssel der gepinnten Basis signiert geprüft.
  - Fehlende `--no-cache`/`--pull`-Optionen: Auf selbst gehosteten Runnern können veraltete Pakete aus dem Cache kommen.
    Cache-Poisoning setzt dort Docker-Zugriff voraus, also root-äquivalent, und damit ist die Grenze ohnehin offen.
  - Wichtiger: Der Inhalt des Images schwächt die Isolation nicht. Alle Sicherheitsoptionen kommen vom Host-Aufruf. Ein
    manipuliertes Image gefährdet nur die Integrität des Bundles, und die prüft `publish` (E18).
  - **In Scope, Nitpick** (schon im Review genannt).
- [ ] [Argumente / Pfade] `scripts/factory-update.sh:224`:
  - `-v "$ROOT:/src:ro"` und `-v "$out:/out"` parsen Doppelpunkte. Ein `ROOT` oder `out_dir` mit `:` würde die
    Mount-Spezifikation verändern, etwa `out_dir=/x:/etc` → Mount auf `/etc` mit ungültigem Modus, also Fehler.
  - `out_dir` kommt im Workflow nur aus dem festen `"$RUNNER_TEMP/fetch-out"`. `ROOT` ist der Workspace, und
    Repo-Namen enthalten kein `:`. Damit gibt es keinen Angreiferpfad.
  - `version` und `base_sha` sind vor jedem `docker`-Aufruf streng validiert (`^v[0-9]+\.[0-9]+\.[0-9]+$`, 40-hex,
    Test Z. 200). Sie gehen als Positionsargumente in `bash -c` (keine Injection). Im YAML stehen sie nur per `env:`,
    nicht als `${{ }}` in `run:`.
  - *Härtung:* `make_out_dir` könnte `:` und `,` im Pfad ablehnen.
  - **In Scope, Nitpick** (kein Sicherheitsrisiko).
- [ ] [Fail-closed / Sperre] `scripts/factory-update.sh:393`: Die Sperre `GITHUB_ACTIONS=true` für `fetch` ist eine
  Schutzschiene gegen Drift im Workflow, keine Sicherheitsgrenze. Ein Workflow, der `env -u GITHUB_ACTIONS … fetch`
  aufriefe, käme durch. Das fängt aber `wf_fetch_ok_41` (kein `run` ruft `factory-update.sh fetch` direkt auf; feste
  Schrittfolge des Jobs `fetch`, mit Mutationen belegt).
  - Ohne Docker bricht `require_docker` hart ab, einen stillen Rückfall gibt es nicht (Test F1 mit Mutation).
  - **Kein Handlungsbedarf.**
- [ ] [Meldungstext] `scripts/factory-update.sh:437`: Die Meldung von `mode_all` in CI empfiehlt noch
  `guard|preflight|fetch|publish verwenden`. `fetch` ist in CI jetzt verweigert, richtig wäre `fetch-isolated`.
  **In Scope, Nitpick** (kein Sicherheitsrisiko).
- [ ] [Rückweg / Ressourcen] Ein feindliches Release kann `/out/update.bundle` beliebig groß machen, auch als sparse
  Datei, oder das Log fluten. Das wäre nur ein DoS des Laufs (Platte, Artefakt-Kontingent mit `retention-days: 1`), kein
  Token-Leck. **Out-of-Scope, Nitpick** → `docs/factory/kleinfunde.md` („Fetch-Container kann Bundle und Log beliebig aufblähen").
- [ ] [Tests] Die Mutationsbelege decken die sicherheitstragenden Eigenschaften ab: exakter `docker run`-Vergleich plus
  unabhängiger Verbots-Prüfer, Root-Mutant, schreibbarer Checkout, Docker-Socket, `--pid/--network=host`,
  `-e ACTIONS_*`/`GITHUB_ENV`, `--env-file`, `$RUNNER_TEMP`-Mount, Digest, Build-Kontext, Rückweg-Prüfung,
  Workflow-Schrittfolge, `fetch` in `publish`, Sperre in CI. Dazu kommen die E2E-Nachbildung mit feindlicher Nutzlast
  und die Gegenprobe.
  - Lücke 1: Kein Test belegt den Kanal aus W1 (stdout).
  - Lücke 2: Kein Test zu FIFO bzw. Hardlink im Rückweg. Abgedeckt sind sie durch `-f` bzw. den Kernel (EXDEV).
  - Bekannt aus dem Review: Der Verbots-Prüfer erkennt getrennt übergebenes `--cgroupns host` nicht. Der exakte
    Vergleich fängt es.
  - **In Scope, Nitpick** (außer der Test zu W1, der gehört zu W1).

## Ergebnis
PASSED

Kein Blocker: Weder ein Weg zum Runtime-Token noch eine Host-Ausführung von Container-Daten ist belegbar. W1 sollte in
diesem PR behoben werden (kleine Änderung), blockiert den Merge aber nicht.
