# Review: Task 66

Drei Personas (Logik, Code-Qualität, Architektur) gegen `git diff origin/main...HEAD`, Spec #66 und Factory-ADR-063
Nachtrag 2026-11-21 (E35–E40). Die Findings der Sub-Agenten sind vom Orchestrator am Code nachgeprüft; Einstufungen sind
dabei teils angepasst (Begründung je Finding).

## Umsetzung Runde 2 (`/implement`, 2026-11-21)

Alle drei wichtigen Findings sind behoben, die Nitpicks bis auf einen umgesetzt; die Lösung steht jeweils mit „→" am Eintrag.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [x] → Host-weiter Lock (`flock -w 900` auf `/tmp/factory-fetch.lock`, fd 9 bis Prozessende), neu ADR-063 **E41**;
  `FETCH_NET_ACTIVE` erst nach dem Lock, ein abgewiesener Lauf fasst Netz und Regeln nicht an. Tests `busy_66`
  (beide Modi) + 3 Mutanten (ohne Lock, Lock-Fehler ignoriert, Abräumen vor Lock), `lock_first_66`.
  [scripts/factory-update.sh:287 (`setup_fetch_network`), :301 (`teardown_fetch_network`); ADR-063 E38] **Parallele Läufe
  auf einem Docker-Host entfernen sich gegenseitig die Sperre (stilles Fail-open).** Netzname, Bridge und Regeln sind
  fest; `-C`/`-D` kann nicht unterscheiden, wessen Regel es ist. Szenario: Container von Lauf A führt Release-Code aus,
  Lauf B startet auf demselben Host → `remove_fetch_rules` löscht A's Regeln, `network rm` scheitert (A hängt am Netz),
  `network create` scheitert → B endet rot, sein EXIT-Trap räumt nochmals ab; A läuft ohne Sperre weiter. Variante ohne
  laufenden Container (A baut noch das Image): B entfernt A's Netz und legt ein eigenes an, A startet in B's Netz, B
  räumt nach seinem Ende ab, während A läuft. Die `concurrency`-Gruppe `factory-update` greift nur je Repo.
  *Einstufung:* von den Sub-Agenten als Kritisch bzw. Wichtig gemeldet; hier **Wichtig**, weil die ausgelieferten
  Workflows (`factory-update.yml`, `factory-ci.yml`) auf `ubuntu-latest` laufen (ein Job je Wegwerf-VM) – der Fall
  entsteht nur auf selbst gehosteten Runnern mit mehreren Instanzen an einem Docker-Daemon. E38 begründet das Abräumen
  aber gerade mit „langlebigen selbst gehosteten Runnern", und E39 schließt Fail-open aus. *Abhilfe (Entscheidung in
  `/implement`):* Host-weiter Lock (z. B. `flock` auf eine feste Datei, fail-closed, wenn nicht verfügbar) um
  Einrichten → Container → Abräumen, **oder** mindestens das Restrisiko „eine fetch-Ausführung je Docker-Host" in
  ADR-063 (Restrisiko 5) und `OPERATING.md` §0.6 ehrlich aufnehmen. Rein dokumentieren lässt das Fail-open bestehen.
- [x] → `blocked` verlangt curl-Exit 7, Meldung nennt den Exit; Fake-curl kennt Timeout (28); je Ziel ein Timeout-Fall
  rot + Mutant „jeder Fehler gilt als gesperrt"; E40 c ergänzt.
  [scripts/factory-update.sh:70 (`blocked` in `FETCH_SMOKE_SCRIPT`)] **Die Smoke-Probe unterscheidet „durch die Regel
  gesperrt" nicht von „ohnehin unerreichbar".** `! curl …` gilt bei jedem Fehler (Timeout, keine Route, Dienst fehlt) als
  gesperrt; eine Gegenprobe gibt es nur für den Gateway-Lauscher. Fehlen beide `DOCKER-USER`-Regeln (z. B. falsches
  iptables-Backend, Restrisiko 4) und antwortet `169.254.169.254` bzw. `168.63.129.16:80` auf einem künftigen Runner-Image
  nicht, bleibt der Job grün – AK4.3 wäre dann nicht belegt. *Abhilfe:* `REJECT` antwortet mit ICMP port-unreachable,
  `curl` endet dann mit Exit 7 (Connection refused); `blocked` sollte genau Exit 7 verlangen (Timeout = Exit 28 → rot).
  Das trifft alle drei Ziele (INPUT und DOCKER-USER sind `REJECT`) und ist ein Einzeiler plus Offline-Anker/Mutant.
- [x] → `docker_calls_41` entfernt nur die bekannten Zeilen (`flock`, `network-*`, `sudo -n iptables`, `iptables -[ICD]`),
  alles andere bleibt im exakten Vergleich; neuer Mutant „zusätzlicher docker pull".
  [scripts/checks/tests/factory-lock-41-tests.sh:38 (`docker_calls_41`)] **Ein #41-Anker ist schwächer geworden (Spec
  AK2.2: „mindestens gleich streng").** Vorher wurde die ganze `calls.log` exakt verglichen (`info build run`), jetzt
  filtert `grep -xE 'info|build|run'` alles andere weg – ein zusätzlicher, vom Skript tolerierter Docker-Aufruf (z. B.
  `exec`, `cp`, `pull`) fiele nicht mehr auf. *Abhilfe:* nur die bekannten `network-*`- und `iptables …`-Zeilen
  herausfiltern (oder deren erwartete Folge mitvergleichen), alles Übrige bleibt im exakten Vergleich.

## Nitpicks (optional)

- [x] → Fake-`sudo` protokolliert `sudo -n <befehl>`, `via_sudo_66` zählt gegen, Mutant „ohne sudo".
  [scripts/checks/tests/lib/factory-lock-fixtures.sh:285–289, scripts/checks/tests/factory-lock-66-tests.sh:114] Der
  Fake-`sudo` protokolliert nur den Fall *ohne* `-n`; da der Fake-`iptables` im `PATH` liegt, bliebe ein Mutant
  `host_iptables() { iptables "$@"; }` (ganz ohne `sudo`) offline grün. Die Testbeschreibung „per sudo -n iptables"
  verspricht mehr, als geprüft wird. Auf dem echten Runner wäre der Mutant fail-closed (iptables ohne root scheitert),
  daher nur Nitpick. Vorschlag: Fake-`sudo` protokolliert `sudo -n iptables …`, Test prüft, dass jeder iptables-Aufruf
  darüber lief, plus Mutant „ohne sudo".
- [x] → zwei Fälle ersetzen den Wert (`factory-fetch`→`host`, `disable_ipv6=1`→`=0`) bei gleicher Anzahl.
  [scripts/checks/tests/factory-lock-41-tests.sh:~80] Die Wertprüfung des Verbots-Prüfers (`--network` nur mit
  `factory-fetch`) wird nie isoliert getroffen: jeder `bad_41`-Fall ergänzt ein zweites `--network`, das schon die
  Anzahlprüfung rot macht. Ein Fall, der `factory-fetch` durch `host` **ersetzt**, fehlt; ebenso für `--sysctl`.
- [x] → Helfer `fetch_rule <op> <regel>`.
  [scripts/factory-update.sh:268–296] `read -ra args <<< "$rule"; host_iptables <op> "${args[@]}"` steht dreimal – ein
  Helfer `fetch_rule <op> <regel>` würde es bündeln.
- [x] → Konstanten `SMOKE_LISTENER_TRIES`/`SMOKE_LISTENER_PAUSE`, Zählschleife, `SMOKE_GATEWAY` bei den Globals.
  [scripts/factory-update.sh:~318–324 (`start_gateway_listener`)] Wiederholungen/Wartezeit (`1..10`, `sleep 0.5`,
  `--max-time 2`) sind Magic Numbers, die Schleifenvariable `try` wird nicht genutzt; `SMOKE_GATEWAY` wird als
  Seiteneffekt gesetzt, steht aber nicht bei den übrigen Globals (`WORK`, `FETCH_NET_ACTIVE`, `SMOKE_LISTENER_PID`).
- [x] → Gateway-Formprüfung: Fall „keine IPv4-Adresse" + Mutant. „python3 fehlt" bleibt ohne Test: `python3` liegt auf
  macOS und Linux im System-`PATH`, ein `PATH` ohne es bräuchte eine nachgebaute Werkzeugliste – Aufwand ohne Gegenwert.
  [scripts/factory-update.sh:~313–316] Zwei `die`-Pfade ohne Test/Mutant: „python3 fehlt" und die Gateway-Regex-Prüfung
  (der Fall „leeres Gateway" ist getestet, ein Mutant ohne Regex fehlt) – vgl. `lessons/testing.md`, Mutationslauf je `die`.
- [x] → `FAKE_GATEWAY_66` in den Fixtures, die Gruppe nutzt sie.
  [scripts/checks/tests/factory-lock-66-tests.sh, lib/factory-lock-fixtures.sh] Das Gateway `172.30.66.1` steht
  zweimal hart (Default des Fake-`docker network inspect` und `GATEWAY_66`) – eine Konstante teilen.
- [ ] → **bewusst nicht umgesetzt:** `--name`/`docker rm -f` änderte den exakten #41-Aufruf und die Aufräumlogik; mit dem
  Lock (E41) kann kein paralleler Lauf mehr in die Lücke fallen. Als Restrisiko 5 in ADR-063 (Nachtrag 2026-11-21) und
  in `OPERATING.md` §0.6 (Abhilfe von Hand) benannt.
  [scripts/factory-update.sh:104–108 (`cleanup`)] Bei Abbruch (SIGTERM an das Skript) räumt der EXIT-Trap die Regeln ab,
  während der Container noch laufen kann (`--rm` greift erst beim Ende; kein `--name`, kein `docker rm -f` im Cleanup).
  Auf Wegwerf-VMs folgenlos, auf selbst gehosteten Runnern verschärft es das Nebenläufigkeits-Finding. Mit `--name`
  und `docker rm -f` vor `teardown_fetch_network` erledigt (mit dem Lock-Fix zusammen betrachten).
- [x] → beide Sätze in §0.6, dazu Restrisiko 4 (DNS-Resolver auf dem Host) und 5 im ADR.
  [scripts/factory-update.sh:287; docs/factory/OPERATING.md §0.6] Hängt ein verwaister Container noch an
  `factory-fetch`, scheitert jeder weitere Lauf (fail-closed, korrekt), bis jemand von Hand aufräumt; ein Satz dazu in
  §0.6 fehlt. Ebenso ein Hinweis für selbst gehostete Runner, dass ein DNS-Upstream auf einer Host-Adresse durch die
  `INPUT`-Regel gesperrt wird (deckt Restrisiko 4 nur implizit ab).
- [x] → Kommentar an `FETCH_SMOKE_SCRIPT`.
  [scripts/factory-update.sh:74] `! grep -vE … /proc/net/if_inet6 2>/dev/null` ist korrekt (nur `lo` → bestanden,
  Datei fehlt → bestanden), lässt aber auch einen Lesefehler still bestehen; ein Kommentar dazu reicht.
- [x] → Halbsatz „Hilfsschritte … ausgenommen", Lock in die Reihenfolge aufgenommen.
  [ADR-063 E39] Die „feste Reihenfolge" nennt Hilfsschritte (`make_out_dir`, `make_work_dir`, `start_gateway_listener`)
  nicht; ein Halbsatz „Hilfsschritte ausgenommen" beseitigt die wörtliche Abweichung.

## Positives

- Regeln als **ein** Array an **einer** Stelle (E36); die Tests schreiben die erwarteten Regeln unabhängig hin, statt sie
  aus dem Skript zu lesen.
- Der Fake bildet Ketten und Netz als Zustand ab – geprüft wird, was beim `docker run` tatsächlich steht, nicht nur die
  Log-Reihenfolge; `-I` mit Erfolg ohne Wirkung (`noop-ipt-I`) wird über `-C` erkannt.
- Fail-closed sauber: `FETCH_NET_ACTIVE` wird vor dem ersten Schritt gesetzt, der EXIT-Trap ist in beiden Modi vor
  `setup_fetch_network` aktiv, Abräumfehler sind nur Warnung (E38), kein Rückfall aufs Standard-Netz (E39).
- Alle acht Mutationen aus E40 (b) sind belegt, dazu weitere (falsche Bridge, Netz mit IPv6, fehlendes Abräumen, jedes
  Probe-Ziel, DNS-Ausnahme für alle Ports).
- Die Gegenprobe des Hosts auf den Lauscher gibt der Gateway-Probe erst Aussagekraft.
- Der #41-Verbots-Prüfer ist an anderer Stelle sogar strenger geworden (`--sysctl*`, `--add-host`, `--network` ≠
  `factory-fetch`).
- Doku konsistent: ADR, `OPERATING.md` §0.6, CHANGELOG (Breaking-Hinweis), Skript-Header, `factory-ci.yml`-Kommentar,
  `tasks/security-41.md`. Projektregeln eingehalten: neue Testgruppe über `scripts/checks/tests/**` in `OWNERSHIP.md`
  und per Glob in `run-tests.sh`; keine Herkunftsbegriffe; die ausgelieferte Suite bleibt konsumenten-neutral
  (`tasks/security-41.md` wird nur gelesen, wenn vorhanden).

## Empfehlung
NEEDS_REWORK
