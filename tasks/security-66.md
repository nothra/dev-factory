# Security Review: Task 66

Geprüft: `git diff origin/main...HEAD`, Kernstellen `scripts/factory-update.sh` (Z. 75–107 Konstanten und Smoke-Skript,
Z. 118–122 `cleanup`, Z. 267–345 `run_in_fetch_container` und Netz-Sperre, Z. 521–547 Modi), `.github/workflows/factory-ci.yml`
(Job `fetch-container-smoke`), `.github/workflows/factory-update.yml` (Job `fetch`, unverändert),
`scripts/checks/tests/lib/factory-lock-fixtures.sh` (Fakes), `scripts/checks/tests/factory-lock-66-tests.sh`, Factory-ADR-063
Nachtrag 2026-11-21 (E35–E41, Restrisiken 1–6), `docs/factory/OPERATING.md` §0.6. Testgruppe `factory-lock-66-tests` lokal
ausgeführt: 84 grün, 0 rot. Docker und iptables waren lokal nicht verfügbar. Aussagen über das Verhalten von Docker, iptables
und Runner sind deshalb statisch geprüft; Annahmen stehen beim jeweiligen Punkt.

**Bedrohungsmodell (aus `tasks/security-41.md`, erweitert um #66):** Release-Code ist feindlich und läuft im Container. Ziel
dieses PRs: Er erreicht weder den Host (Bridge-Gateway und jede andere Host-Adresse) noch IMDS (`169.254.0.0/16`) noch den
WireServer `168.63.129.16` außer DNS, und auch nicht über IPv6. Datenabfluss ins Internet bleibt bewusst offen (Restrisiko 1).

**Ergebnis der Kernprüfung:** Die Sperre hält, solange der Container unter einem laufenden Skript lebt.
- *Regelreihenfolge:* `INPUT -i factory-fetch0 -j REJECT` fängt allen Verkehr zu Host-Adressen ab, über jedes Protokoll und
  jeden Port. In `DOCKER-USER` (erster Sprung aus `FORWARD`) stehen die beiden `RETURN` für Port 53 vor dem `REJECT` auf
  `168.63.129.16/32`. Die Regeln werden unter dem Lock in umgekehrter Folge an den Kettenanfang gesetzt (Z. 314–316) und
  danach einzeln per `-C` geprüft (Z. 317–319). Erst dann startet der Container (Reihenfolge in Z. 524–527 bzw. 540–544).
- *Kein TOCTOU, das ausnutzbar wäre:* Zwischen `network create` und den Regeln hängt noch kein Container am Netz. Einen
  Container in dieses Fenster zu bringen oder eine Regel davor einzufügen, setzt Docker- oder root-Zugriff voraus. Damit
  wäre die Grenze ohnehin offen.
- *Aus dem Container nicht aufhebbar:* Die Regeln liegen im Netz-Namensraum des Hosts. Der Container hat `--cap-drop ALL`
  (kein `NET_ADMIN`, kein `NET_RAW`) und `no-new-privileges`, und `/proc/sys` ist in Docker nur lesend eingebunden. Damit
  kann er auch `disable_ipv6` nicht zurücksetzen. Das Netz hat ohnehin kein IPv6 (E35/E37).
- *Fail-closed:* Lock, `network create`, jedes `iptables -I` und jedes `-C` enden bei Fehler in `die` (Z. 284–287,
  311–319). Eine fehlende Kette `DOCKER-USER` (z. B. Docker mit `"iptables": false` oder nftables-Backend) lässt `-I`
  scheitern. Einen Rückfall auf das Standard-Netz gibt es nicht. Das Skript läuft ohne `set -e` (Z. 41). Die einzigen
  ignorierten Rückgaben sind `remove_fetch_rules`/`remove_fetch_network` beim Abräumen der Reste (Z. 312). Scheitert
  dort das Netz, scheitert anschließend auch `network create` (fail-closed). Bleibt eine alte Regel stehen, ist das
  restriktiv. Zur Folge für einen noch laufenden verwaisten Container siehe W1.
- *Injection:* Die Gateway-Adresse aus `docker network inspect` wird vor jeder Verwendung streng geprüft
  (`^[0-9]{1,3}(\.[0-9]{1,3}){3}$`, Z. 334). Sie geht gequotet an `python3`/`curl` und als Positionsargument in `bash -c`
  (`"$1"`, `"$2"` im Smoke-Skript). Die Regeln sind Konstanten (Z. 89–95). Die Wortzerlegung per `read -ra` (Z. 280)
  betrifft nur diese Konstanten. `FACTORY_FETCH_LOCK` steht nur gequotet in einer Umleitung (Z. 285).
- *sudo* wird nur für `iptables` und nur mit `-n` aufgerufen (Z. 278). Der Fake-`sudo` belegt per Mutation, dass jeder
  Aufruf darüber läuft.
- *Keine Secrets* in neuen Argumenten, Meldungen oder Logs. Der Container bekommt weiter nur `-e HOME=/tmp`.
- *CI:* In `factory-ci.yml` ändert sich nur ein Kommentar. Es kommen keine neuen Actions, Images oder Permissions hinzu.
  `python3` und `flock` sind auf `ubuntu-latest` vorhanden. macOS ist kein Ziel, denn ohne `iptables` endet der Lauf
  ohnehin rot.

## Kritische Findings (Blocker)
- keine

## Wichtige Findings
- [ ] [Fail-open beim Abräumen / verwaister Container] `scripts/factory-update.sh:324–327` (`teardown_fetch_network`) und
  `:312` (Abräumen der Reste in `setup_fetch_network`): Beide entfernen **zuerst die Regeln** und versuchen erst danach,
  das Netz zu löschen. Hängt dann noch ein Container an `factory-fetch`, scheitert `docker network rm`, und das Skript
  meldet nur das. Der Container läuft danach **ohne Sperre** weiter und erreicht Host, IMDS und WireServer. Das ist genau
  der Zustand, den der PR verhindern soll.
  - *Weg 1 (Signal):* Das Skript wird per Signal beendet. Der EXIT-Trap läuft (ADR-063 Restrisiko 5 setzt das selbst
    voraus) und entfernt die Regeln. Der Container lebt weiter, denn `--rm` greift erst an seinem Ende, und er ist kein
    Kind des Skripts. Die Bash als PID 1 im Container ignoriert SIGINT und SIGTERM ohne eigenen Handler, auch wenn
    `docker run` sie weiterreicht. Feindlicher Release-Code muss dafür nichts tun außer nicht zu enden: Der Job `fetch`
    hat kein `timeout-minutes` (`factory-update.yml:83 ff.`), also bricht der Runner nach 360 min ab. Ob das Signal
    das Skript selbst erreicht, hängt davon ab, wie der Runner bzw. der Dienst abbricht (z. B. `systemctl stop` auf dem
    selbst gehosteten Runner: ja). Annahme, nicht verifiziert.
  - *Weg 2 (deterministisch, ohne Signal-Annahme):* Das Skript stirbt ohne Trap (SIGKILL, Absturz des Runners), und der
    Container verwaist. Auf diesem Host bleiben die Regeln zunächst stehen (fail-safe). Der **nächste** `fetch`-Lauf
    nimmt den Lock und entfernt in Z. 312 die „Reste", also genau diese Regeln. `docker network rm` scheitert am noch
    angehängten Container, danach scheitert `network create`, und der Lauf endet per `die`, ohne die Regeln neu zu
    setzen. Der verwaiste Container läuft von da an ungesperrt.
  - *Folge:* Auf GitHub-gehosteten Runnern ist das Fenster bis zur Entsorgung der VM kurz. Auf langlebigen, selbst
    gehosteten Runnern bleibt es unbegrenzt offen. ADR-063 Restrisiko 5 und OPERATING §0.6 nennen den verwaisten
    Container, aber nur als Grund für rote Folgeläufe („auf Wegwerf-Runnern folgenlos"). Dass er dabei die Sperre
    verliert, steht dort nicht.
  - *Lösung (klein, im Skript):* Vor dem Entfernen der Regeln, beim Abräumen der Reste wie im Trap, erst alle Container
    am Netz entfernen: `docker ps -aq --filter network=factory-fetch` → `docker rm -f`. Unter dem Lock gehören sie nur
    toten oder dem eigenen Lauf. Ergänzend oder alternativ: Regeln nur entfernen, wenn kein Container mehr angehängt ist,
    sonst stehen lassen und warnen (fail-safe). Optional bekommt der Container einen festen `--name` für ein gezieltes
    `docker rm -f` im Trap, und der Job `fetch` ein `timeout-minutes`. Tests: Fake-`docker` mit „Container hängt
    noch am Netz" → kein `iptables -D`, bevor der Container entfernt ist, plus Mutant mit der alten Reihenfolge. Restrisiko
    5 im ADR und in OPERATING §0.6 entsprechend korrigieren.
  - **In Scope** (Lebenszyklus E38 ist Gegenstand dieses PRs, kleine Änderung). Sicherheitsrisiko real, aber an einen
    verwaisten Container gebunden. Auf GitHub-gehosteten Runnern gering. Blockiert den Merge nicht. Wird es hier nicht
    behoben: **Out-of-Scope-Kandidat (A) → Issue** (siehe Antwort).

## Hinweise
- [ ] [Lock-Datei in `/tmp`] `scripts/factory-update.sh:101, 285`: `exec 9>>` auf `/tmp/factory-fetch.lock`, eine feste
  Datei in einem für alle beschreibbaren Verzeichnis.
  - *Symlink:* Unter Ubuntu verhindert `fs.protected_symlinks=1`, dass das Skript in `/tmp` (Sticky-Bit) einem fremden
    Symlink folgt. Selbst ohne diesen Schutz öffnet `>>` nur zum Anhängen, ohne Kürzen und ohne Schreiben. Es entsteht
    also kein Schaden an einer Zieldatei.
  - *Vorbelegung:* Ein anderer lokaler Nutzer kann die Datei ohne Schreibrecht anlegen (`fs.protected_regular`) oder den
    `flock` halten. Folge ist nur ein DoS (fail-closed nach höchstens 900 s), keine Umgehung der Sperre. Das ist in
    OPERATING §0.6 beschrieben.
  - **Kein Handlungsbedarf.**
- [ ] [`FACTORY_FETCH_LOCK`-Override] `scripts/factory-update.sh:97–101`: Die Variable wirkt auch in Produktion. Abweichende
  Werte heben die Serialisierung auf, mit derselben Wirkung wie Restrisiko 6. Das Setzen verlangt aber Kontrolle über
  Workflow oder Runner-Umgebung, also mehr, als ein Angreifer damit gewinnt. Kommentar und ADR nennen es. **Kein
  Handlungsbedarf.**
- [ ] [sudo ist root-äquivalent] OPERATING §0.6 verlangt „passwortloses `sudo`". Wer das auf selbst gehosteten Runnern auf
  `iptables` einschränkt, gewinnt keine Grenze: `iptables --modprobe=<programm>` führt ein beliebiges Programm als root
  aus. Das ändert am Risiko nichts, denn die Runner-UID ist mit Docker-Zugriff ohnehin root-äquivalent. Ein Satz dazu in
  OPERATING verhinderte nur falsche Sicherheit. **Out-of-Scope-Kandidat (B), Nitpick** → `docs/factory/kleinfunde.md`
  (Datei `docs/factory/OPERATING.md`).
- [ ] [Lauscher der Smoke-Probe] `scripts/factory-update.sh:337`: `python3 -m http.server` auf `<gateway>:18066` ist für
  andere Schnittstellen des Hosts erreichbar (z. B. Container auf `docker0`), weil `INPUT` nur `factory-fetch0` sperrt.
  Er läuft aber nur im Job `fetch-container-smoke` der Factory-CI (Wegwerf-VM), liefert ein leeres Verzeichnis
  (`$WORK/listener`), erbt den Lock nicht (`9>&-`) und wird im Trap beendet. **Kein Handlungsbedarf.**
- [ ] [DNS am WireServer / Tunnel] Die `RETURN`-Ausnahme für `168.63.129.16:53` (Z. 91–92) ist als Exfil- oder Tunnelkanal
  ohne Belang, denn das Internet ist ohnehin offen (Restrisiko 1). Übrig bleibt die Angriffsfläche des Azure-Resolvers
  (Restrisiko 2, bewusst angenommen). Andere Ports am WireServer (z. B. 80, 32526) sperrt das folgende `REJECT` auf
  `/32`. **Kein Handlungsbedarf.**
- [ ] [Umfang der Sperre] Über DNAT veröffentlichte Ports anderer Container auf derselben Docker-Instanz laufen durch
  `FORWARD`, nicht durch `INPUT`. Die `INPUT`-Regel fängt sie nicht, und `DOCKER-USER` sperrt nur IMDS und WireServer.
  Ob Dockers Isolationsketten diesen Weg zwischen Bridges abweisen, hängt von der Docker-Version ab und ist nicht
  verifiziert. Der Job `fetch` hat keine Service-Container, und auf GitHub-gehosteten Runnern läuft dort nichts. Auf
  selbst gehosteten Runnern fällt der Fall unter Restrisiko 3 (private Netze bleiben erreichbar). **Kein Handlungsbedarf**
  über die Restrisiko-Formulierung hinaus. Eine Präzisierung („auch veröffentlichte Ports anderer Container auf dem Host")
  wäre ehrlicher, ist aber optional.
- [ ] [Grenzen der Smoke-Probe] Exit 7 belegt die Regel nur, wenn das Ziel ohne Regel antwortet. ADR-063 E40 c nennt diese
  Grenze, und der Host-Lauscher wird per Gegenprobe vom Host geprüft (Z. 338–343). `iptables -C` prüft nur, ob eine Regel
  vorhanden ist, nicht ihre Position. Unter dem Lock stehen die Regeln aber am Kettenanfang, und etwas davor einzufügen
  verlangt root. **Kein Handlungsbedarf.**
- [ ] [Tests] Die Fakes protokollieren jeden `iptables`-Aufruf samt `sudo -n`, den Zustand der Ketten und das Netz beim
  `run` sowie den Lock zu `run`, `network rm` und dem Lauscher. Die Mutationen decken die tragenden Eigenschaften aus
  E40 b ab. Lücke: Kein Test bildet einen noch am Netz hängenden Container beim Abräumen nach. Der Test gehört zu W1.
  **In Scope, Teil von W1.**

## Ergebnis
PASSED

Kein Blocker: Für einen laufenden Lauf ist keine Umgehung der Sperre belegbar. Injection, Fail-closed beim Einrichten,
IPv6 und die Capabilities halten. W1 (Regeln werden entfernt, obwohl ein verwaister Container noch am Netz hängt) sollte in
diesem PR behoben werden, weil die Änderung klein ist und den Lebenszyklus dieses PRs betrifft. Den Merge blockiert W1 nicht.

**Issue zu W1 noch nicht angelegt (2026-11-22):** Der Aufruf von `create_issue_idempotent` brauchte in dieser Sitzung eine
Freigabe, die nicht erteilt werden konnte. Wird W1 nicht in diesem PR behoben, das Issue vor dem Merge von Hand anlegen:
Titel „Container am Netz factory-fetch vor dem Entfernen der Netz-Sperre beenden", Labels `bug` + `security`, Body =
W1 oben (Weg 2 als deterministischer Beleg, Lösung, Tests und Korrektur von Restrisiko 5).

Hinweis „sudo ist root-äquivalent" als Kleinfund in `docs/factory/kleinfunde.md` eingetragen.
