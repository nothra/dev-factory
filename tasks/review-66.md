# Review: Task 66

Runde 2 (2026-11-21): drei Personas (Logik, Code-Qualität, Architektur) gegen `git diff origin/main...HEAD`
(Runde-2-Fix 63d456a), Spec #66 und Factory-ADR-063 Nachtrag 2026-11-21 (E35–E41). Die Findings der Sub-Agenten sind
vom Orchestrator am Code bzw. Text nachgeprüft, die Einstufungen teils angepasst (Begründung je Finding). Die Sub-Agenten
durften kein Bash ausführen; der Orchestrator hat die Gruppen selbst laufen lassen: `factory-lock-66-tests.sh` 77 grün,
`factory-lock-41-tests.sh` 93 grün.

**Runde-1-Findings:** alle drei wichtigen sind korrekt behoben (Lock-Reihenfolge Lock → `FETCH_NET_ACTIVE` → Abräumen,
abgewiesener Lauf fasst nichts an, Lauscher mit `9>&-`; Exit-7-Probe samt Timeout-Fällen und Mutant; `docker_calls_41`
wieder exakt bis auf bekannte Zeilen, Mutant `zusaetzlicher-docker-aufruf`). Die Nitpicks sind umgesetzt; der eine bewusst
nicht umgesetzte (`--name`/`docker rm -f`) ist als Restrisiko 5 tragfähig begründet und hiermit akzeptiert. Die ignorierten
Rückgabewerte in `setup_fetch_network` (`remove_fetch_rules; remove_fetch_network`, Skript ohne `set -e`) sind geprüft:
kein Fail-open (Altregeln sperren nur zusätzlich, ein verbliebenes Netz lässt `network create` scheitern → `die`).

## Umsetzung Runde 3 (`/implement`, 2026-11-21)

Alle Findings umgesetzt; offen bleibt allein die **Annahme von E41 durch den Menschen** (erstes wichtiges Finding,
Checkbox bleibt bis dahin offen).

- Wichtig 1 → Kopfzeile des Nachtrags: „Accepted … für E35–E40. **E41** ist **Proposed**“; E41 trägt denselben Status.
- Wichtig 2 → Restrisiko 6 „Gemeinsamer Docker-Daemon, getrenntes `/tmp`“ (nicht erkennbar, nicht fail-closed, Abhilfe beim
  Betreiber), Alternative „Namen je Lauf statt Lock“ mit Verwerfungsgrund (15-Zeichen-Bridge, fremde Reste, Regelsatz
  E36, Testumfang); `OPERATING.md` §0.6 mit demselben Satz. Doku-Guards um beide Stellen ergänzt.
- Exit 7 → Kommentar und E40 c nennen die Grenze (jeder gescheiterte `connect()` = 7) und warum stderr nicht geprüft wird.
- Lock bis Prozessende → Fake-`docker` (`run`, `network rm`) und Fake-`python3` vermerken, ob fd 9 offen ist; Tests
  `lock_held_66` (beide Modi), „Lauscher erbt den Lock nicht“, Mutanten `lock-vor-container-frei`, `lauscher-erbt-lock`.
  `run_66` startet das Skript mit `9>&-`, damit ein fd 9 der Testumgebung nichts grün färbt.
- `FACTORY_FETCH_LOCK` → Kommentar nennt die Wirkung auch in CI (keine Abweisung: gleiches Muster wie `FACTORY_DIR`).
- Schreibrecht → `OPERATING.md` §0.6 (Datei einmal mit passenden Rechten anlegen), E41 nennt die Voraussetzung.
- `E35–E41` → `OPERATING.md`, mit „Restrisiken 1–6“.
- Konsequenzen → `flock` als Voraussetzung, Gruppe `factory-lock-66-tests.sh` + Fixtures statt „oder neue Gruppe“.
- `make_out_dir` vor dem Lock → Kommentar in `mode_fetch_isolated`.
- `lock == 2` → `lock_first_66` prüft „flock direkt nach info“.
- `curl-Exit 28` → Prüfung je Ziel im Schleifenkörper, mit Ziel in der Meldung.
- `sleep` nach dem letzten Versuch → Schleife bricht vor dem `sleep` ab.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] [docs/factory/adr/063-factory-eigenes-repo-vendored-manifest.md:967, :1044] **E41 steht unter einem
  Menschen-Status, den es für E41 nicht gibt.** Die Kopfzeile des Nachtrags sagt „Status: Accepted (2026-11-21,
  Entscheidung Mensch)“ und nennt nur „Q1–Q5“. Angenommen hat der Mensch E35–E40 (Commit fa21f6d, Task-Datei „Offene
  Fragen“); E41 hat `/implement` aus dem Review heraus entschieden, das sagt E41 selbst. *Abhilfe:* E41 eigens als
  „Proposed – Annahme durch Mensch ausstehend“ kennzeichnen und die Annahme vor dem Merge einholen. **Eskalation an den
  Menschen:** Die Annahme von E41 kann kein Pipeline-Schritt ersetzen.
- [x] [ADR-063 E41 :1044–1053, Restrisiken :1070ff., Alternativen :1055ff.] **Die Grenze des Locks ist kein benanntes
  Restrisiko, und die naheliegende Alternative fehlt.** Der Lock serialisiert je `/tmp`-Dateisystem, nicht je
  Docker-Daemon. Laufen Runner-Instanzen in eigenen Containern mit gemountetem Docker-Socket (je eigenes `/tmp`), greift er
  nicht. Dann besteht das stille Fail-open aus Runde 1 unverändert fort, und nichts erkennt es. E41 führt das nur als
  „Voraussetzung“. *Abhilfe:* Restrisiko 6 „gemeinsamer Daemon, getrenntes `/tmp`: nicht erkennbar, nicht fail-closed“
  aufnehmen. Unter Alternativen „Namen je Lauf“ ergänzen (Netz/Bridge je Lauf benannt, Regeln mit `-m comment`) und den
  Grund der Verwerfung nennen (u. a. Bridge-Name max. 15 Zeichen, Abräumen fremder Reste, Testumfang). `OPERATING.md`
  §0.6 erhält denselben Satz. Reine Doku-Änderung, kein Code.

## Nitpicks (optional)

- [x] [scripts/factory-update.sh:70–71; ADR-063 E40 c :1041–1043] **Exit 7 heißt nicht nur „abgewiesen“.**
  Kommentar und ADR sagen „ein Timeout (28) oder eine fehlende Route belegen die Regel nicht“ bzw. „ist rot“. curl
  meldet aber jeden gescheiterten `connect()` mit 7, auch ENETUNREACH/EHOSTUNREACH. Fehlte eine Regel auf einem Runner
  ohne Route zu IMDS, bliebe die Probe grün. *Einstufung:* Logik meldete Wichtig, Code-Qualität Nitpick; hier
  **Nitpick**: Die Probe läuft nur im Factory-CI auf `ubuntu-latest`, dort antworten IMDS und WireServer; eine fehlende
  Regel wäre also rot. Falsch ist die schriftliche Zusage, nicht das Verhalten. *Abhilfe:* den Satz auf „ein Timeout
  belegt die Regel nicht“ kürzen und die Grenze benennen. Davon abgeraten wird, stderr auf „Connection refused“ zu prüfen:
  Neuere curl-Versionen geben dort teils nur „Couldn't connect to server“ aus.
- [x] [scripts/factory-update.sh:95–96, :333; lib/factory-lock-fixtures.sh (Fake-`flock`)] **„Lock bis Prozessende
  gehalten“ hat keinen Mutanten.** Der Fake prüft nur die Argumente. Zwei Mutanten blieben offline grün: `exec 9>&-`
  direkt nach `setup_fetch_network` (der Lock fällt vor Container und Abräumen) und `9>&-` beim Lauscher entfernt (der
  Lauscher erbt den Lock). Beides sind tragende Eigenschaften von E41 (`lessons/testing.md`, Spec AK4.2). Vorschlag: Fake
  `docker run`/`python3` vermerkt, ob fd 9 offen ist (`{ : >&9; } 2>/dev/null`), dazu die zwei Mutanten.
- [x] [scripts/factory-update.sh:97–98] `FACTORY_FETCH_LOCK` heißt „nur für Tests“, wirkt aber auch in CI. Ein
  abweichender Wert hebelt die host-weite Serialisierung still aus. Das folgt zwar dem Muster `FACTORY_DIR`; der
  Kommentar sollte die Wirkung aber ehrlich nennen, oder das Skript weist den Wert in CI ab.
- [x] [scripts/factory-update.sh:281] `exec 9>>` braucht Schreibrecht. Legt eine Runner-Instanz unter einem anderen
  Benutzer die Datei mit 0644 an, endet jede andere Instanz mit Exit 1. Das ist fail-closed und als Voraussetzung
  genannt. Abhilfe: ein Satz in `OPERATING.md` §0.6 (Datei einmal mit passenden Rechten anlegen), oder `flock` auf einem
  nur lesend geöffneten fd.
- [x] [docs/factory/OPERATING.md:209] „Details: … (E35–E40)“, obwohl der Absatz den Lock aus E41 beschreibt →
  „E35–E41“.
- [x] [ADR-063 Konsequenzen :1085–1093] Der Abschnitt ist veraltet. `flock` fehlt als Voraussetzung des Runners, und
  „Tests in … oder einer neuen Gruppe“ ist überholt: `factory-lock-66-tests.sh` gibt es inzwischen.
- [x] [scripts/factory-update.sh:519] In `fetch-isolated` legt `make_out_dir` das Verzeichnis vor dem Lock an. Nach einem
  abgewiesenen Lauf bleibt es leer liegen, ein Retry mit demselben Pfad scheitert dann an „existiert schon“. In CI ist
  der Pfad je Lauf frisch, daher nur lokal relevant; ein Satz in der Meldung oder im Kommentar genügt.
- [x] [scripts/checks/tests/factory-lock-66-tests.sh:196] `lock == 2` koppelt an die Zeilennummer, setzt also voraus,
  dass `info` Zeile 1 ist. Robuster ist die Prüfung „flock direkt nach info“.
- [x] [scripts/checks/tests/factory-lock-66-tests.sh:266] Die Meldungsprüfung `curl-Exit 28` greift nur auf die Ausgabe
  des letzten Schleifendurchlaufs (WireServer) zu. Sie sollte in den Schleifenkörper.
- [x] [scripts/factory-update.sh:337] Nach dem letzten gescheiterten Versuch folgt noch ein `sleep` vor dem `die`.

## Positives

- Saubere Schichtung in Abschnitt 5b: `host_iptables` → `fetch_rule` → Einrichten/Abräumen; Regeln weiter als ein Array an
  einer Stelle (E36).
- E41 ist an E38/E39 angebunden. Der Lock steht in der festen Reihenfolge, und `acquire_fetch_lock` deckt beide
  Fehlerquellen (Datei, `flock`) mit einem `die` ab, dessen Meldung sagt, warum Netz und Regeln unberührt bleiben.
- Starke Mutationsbelege für den Lock: `ohne Lock`, `Fehler ignoriert` und `abraeumen-vor-lock` treffen je einen eigenen
  Pfad. `busy_66` belegt Verhalten: Fremder Zustand wird vorbelegt und muss unverändert bleiben.
- `via_sudo_66` gleicht die Zählungen ab und fängt so auch gemischte Mutanten. Die Wert-Ersetzungsfälle im
  Verbots-Prüfer sind über `! cmp` gegen wirkungslose Mutanten abgesichert.
- Timeout und Abweisung sind im Fake-curl zustandsbasiert getrennt, je Ziel gibt es einen roten Timeout-Fall.
- Projektregeln eingehalten: `ownership-check.sh` grün, keine Herkunftsbegriffe, ausgelieferte Suite konsumenten-neutral.

## Empfehlung
NEEDS_REWORK

Beide wichtigen Findings sind reine ADR-/Doku-Änderungen; der Code ist nach Runde 2 in Ordnung. Das erste braucht die
Annahme von E41 durch den Menschen. Das ist Iteration 2 von höchstens 3 (Circuit Breaker): Bleibt nach der nächsten Runde
etwas offen, wird eskaliert.

---

## Archiv Runde 1 (2026-11-21, abgeschlossen)

Runde 1 empfahl NEEDS_REWORK mit 0 kritischen, 3 wichtigen Findings und 10 Nitpicks. Umgesetzt in 63d456a, Bewertung
oben. Im Einzelnen:

- Wichtig: parallele Läufe entfernen sich gegenseitig die Sperre → Lock E41.
- Wichtig: Die Smoke-Probe trennt „gesperrt“ nicht von „unerreichbar“ → Exit 7.
- Wichtig: Der #41-Anker `docker_calls_41` war schwächer geworden → exakter Vergleich bis auf bekannte Zeilen.
- Nitpicks: Fake-`sudo`-Protokoll, Wert-Ersetzung im Verbots-Prüfer, Helfer `fetch_rule`, Konstanten für den Lauscher,
  Gateway-Formprüfung, `FAKE_GATEWAY_66`, zwei Sätze in `OPERATING.md` §0.6, Kommentar zu `/proc/net/if_inet6`,
  Hilfsschritte in E39 → alle umgesetzt.
- `--name`/`docker rm -f` bei Abbruch: nicht umgesetzt, als Restrisiko 5 akzeptiert.

Der Volltext von Runde 1 steht in der Git-Historie dieser Datei (Commit 63d456a).
