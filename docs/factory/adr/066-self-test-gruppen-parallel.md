# ADR 066: Testgruppen der ausgelieferten Suite als parallele Teilprozesse

## Status

Proposed (2026-11-10, Spec #52). Wird mit der Umsetzung auf Accepted gesetzt.

## Kontext

Die ausgelieferte Suite `scripts/checks/tests/run-tests.sh` läuft heute als **ein** Prozess: Alle
Abschnitte teilen die Zähler `PASS`/`FAIL` aus `lib/assert-helpers.sh`, und die Testgruppe
`factory-lock-tests.sh` (#23/#24/#37) wird am Ende per `source` eingebunden. Spec #52 verlangt, dass
diese Gruppe lokal höchstens 181 s braucht und die ganze Suite höchstens 240 s (Ausgangswerte
362 s und 566 s, macOS). Abdeckung darf dabei nicht verloren gehen.

**Messung für diese Entscheidung** (2026-11-10, macOS, 8 Kerne, Branch-Stand = `main` @ 8676a44;
Gruppe allein, Zeitmarke an jedem Abschnittskopf, die Zeit zählt bis zum nächsten Kopf):

| Teil | Dauer | Anteil |
|------|-------|--------|
| #23 Abholen, Lock, Integritäts-Gate | 66 s | 13 % |
| #24 Update-Workflow und Update-PR | 151 s | 30 % |
| #37 Token und Release-Code trennen | 287 s | 57 % |
| **Gruppe gesamt** (482 Assertions, alle grün) | **504 s** (`real`), 111 s user, 167 s sys, 55 % CPU | |

Die Maschine war bei dieser Messung langsamer als bei der Messung im Issue (504 s statt 362 s).
Für die Entscheidung zählen die Anteile.

Gemessen an einzelnen Helfern:

| Aufruf | Dauer | Aufrufe in der Gruppe |
|--------|-------|-----------------------|
| `world_23` (Kopie der Vorlage) | 0,3 s | 42 |
| `world_24` (+ Bare-Origin, Stub-Zustand) | 0,5 s | 58 |
| `upd_24` (ein Lauf von `factory-update.sh`) | **4,0 s** | 51 |
| `sync_23` (ein Lauf von `factory-sync.sh`) | 1,7 s | 29 |
| `hostile_37` (2 Abholungen, Klon, fetch, publish) | 7,1 s | 10 |
| `${adr_37//Muster/}` (70-KB-ADR, bash 3.2) | **8,4 s** pro Mutante | 4 |

Daraus folgt dreierlei:

1. **Die Fixtures sind schon billig.** `world_23` kopiert seit #23 eine fertige Vorlage. Eine
   gemeinsame Basis-Fixture (Ansatz 1 im Issue) spart deshalb fast nichts.
2. **Die Zeit liegt in den Läufen der getesteten Skripte.** Diese Läufe sind selbst der
   Prüfgegenstand der Assertions. Weniger Läufe hieße weniger Abdeckung, und die Spec verbietet
   Änderungen an den Skripten.
3. **Die Prosa-Guards lesen die ADR nur einmal.** Teuer ist die Mustersubstitution `${v//x/}`.
   bash 3.2 rechnet sie auf großen Strings quadratisch. Vier Mutanten kosten so ~23 s.

Selbst wenn Ansatz 1 und Ansatz 2 innerhalb der Gruppe ihr Maximum bringen (~45 s), wäre die Gruppe
nicht halbiert. Das Gesamtziel ist so erst recht nicht erreichbar: Der Rest der Suite (~204 s) liegt
außerhalb des Scopes. Das ist ein **Architekturmuster-Wechsel** der ausgelieferten Suite, deshalb
dieses ADR: Sie läuft nicht mehr als ein Prozess, sondern aus mehreren Teilprozessen. Der Wechsel
gilt bei allen Konsumenten.

## Entscheidung

**D1 · Teilprozesse statt `source`.** Die Gruppe wird in Teilgruppen (Shards) zerlegt. Jeder Shard
läuft als eigener `bash`-Prozess. `run-tests.sh` startet alle Shards **zu Beginn** im Hintergrund,
führt dann den eigenen Rest wie bisher aus und sammelt die Shards an der Stelle ein, an der heute
`factory-lock-tests.sh` gesourct wird. Dazu kommt ein neuer Helfer `lib/test-groups.sh` mit einer
Start-Funktion und einer Sammel-Funktion.

**D2 · Schnitt.** Die gemeinsamen Helfer (`git_23` … `mut_manifest_23`, gh-Stub, `world_24` & Co.,
die #37-Helfer) wandern in `lib/factory-lock-fixtures.sh`. Die Abschnitte werden zu eigenen Dateien,
etwa `factory-lock-23-tests.sh`, `factory-lock-24-tests.sh` und `factory-lock-37a/37b-tests.sh`.
#37 wird an einem Abschnittskopf geteilt, damit kein Shard deutlich über ~150 s (gemessen wie oben)
liegt. Den genauen Schnitt legt `/implement` nach Messung fest. Jeder Shard baut in seinem eigenen
`mktemp -d` eine eigene Vorlage und teilt keinen Zustand mit anderen Shards.

**D3 · Ergebnisvertrag.** Ein Shard schreibt seine Ausgabe in eine Log-Datei. Als **letzte Zeile**
schreibt er `RESULT <pass> <fail>` in eine eigene Ergebnisdatei. Die Sammel-Funktion wartet auf die
Shards in **Startreihenfolge** und gibt jedes Log zusammenhängend aus. Danach addiert sie die Zähler
auf `PASS`/`FAIL`. Damit bleibt die Assertion-Reihenfolge der Ausgabe unverändert (AK5, AK10).

**D4 · Fail-closed.** In drei Fällen zählt die Sammel-Funktion den Shard als **eine rote Assertion**
mit dem Namen des Shards und dem Grund: Die Ergebnisdatei fehlt, sie ist nicht wohlgeformt
(`^RESULT [0-9]+ [0-9]+$`), oder der Exit-Code ist ≠ 0 **und** `fail` ist 0. Ein fehlendes
Teilergebnis wird nie als grün gelesen (AK11). Das Log wird trotzdem ausgegeben.

**D5 · Aufräumen.** Jeder Shard räumt sein Temp-Verzeichnis per EXIT-Trap auf, heute steht dafür
nur ein `rm -rf` am Ende. `run-tests.sh` setzt einen Trap auf INT/TERM/EXIT: Er beendet laufende
Shards und entfernt Logs und Ergebnisdateien (AK14, F5).

**D6 · Schalter.** Standard ist parallel, und zwar überall: lokal, in CI und bei Konsumenten. Mit
`FACTORY_SELF_TEST_SERIAL=1` startet `run-tests.sh` jeden Shard und wartet sofort auf ihn. Es ist
derselbe Codepfad, nur ohne Überlappung, zum Debuggen und für ressourcenknappe Runner. Eine
konfigurierbare Zahl paralleler Jobs gibt es nicht (YAGNI). Es gibt nur wenige Shards, und
`ubuntu-latest` hat 4 vCPUs.

**D7 · Prosa-Mutanten linear.** `${v//literal/}` auf großen Texten wird durch einen Helfer ersetzt,
der ein festes Literal linear entfernt, z. B. per `awk` mit `index()`. Das Literal kommt per
`ENVIRON` statt `-v`, sonst greift die Escape-Verarbeitung. Ein schneller Test belegt auf kleinen
Eingaben, dass der Helfer exakt dasselbe Ergebnis liefert wie `${v//literal/}`, inklusive Literal am
Anfang, am Ende, mehrfach und gar nicht. Gleicher Prüfinhalt, AK6.

**D8 · Vorlagen-Kopie für `hostile_37` nur bei Bedarf.** Der gemeinsame Vorlauf von `hostile_37`
umfasst Skripte nach U, v1.1.0 abgeholt, committet und gepusht. Er lässt sich als Vorlage einmal je
Shard bauen und je Fall kopieren. Das spart ~2,5 s pro Aufruf. Umgesetzt wird es **nur**, wenn der
#37-Shard nach D1/D2/D7 der kritische Pfad über dem Ziel ist. Kopierte Klone tragen absolute
`file://`-Remotes und brauchen `git remote set-url` auf die eigene Kopie. Ein Fingerprint-Test
belegt, dass die Vorlage unverändert bleibt (AK8, F2).

## Alternativen

### Option A: Nur Aufwand senken, sequenziell (Ansätze 1–3 des Issues)

Vorteile: keine Strukturänderung, Ausgabe und Prozessmodell bleiben gleich, kein ADR nötig.
Nachteile: Laut Messung ist höchstens ~10 % zu holen. AK2 (−50 %) und AK3 (240 s) sind so nicht
erreichbar.

### Option B: Ganze Gruppe als **ein** Hintergrundprozess neben dem Rest

Vorteile: kleinster Eingriff, `factory-lock-tests.sh` bleibt eine Datei.
Nachteile: Die Gruppe allein dauert 362–504 s. Die Wanduhrzeit der Suite wäre damit mindestens die
der Gruppe, und AK2 und AK3 wären verfehlt.

### Option C (gewählt): Gruppe in Shards zerlegen, Shards parallel zum Rest

Vorteile: Die Wanduhrzeit sinkt auf etwa max(Rest der Suite, längster Shard). Jeder Shard bleibt für
sich lesbar und einzeln ausführbar (AK9). Der Ergebnisvertrag ist klein und fail-closed.
Nachteile: mehr Dateien, ein neuer Helfer, mehr gleichzeitige Prozesse. Ressourcenkonkurrenz kann
den Rest der Suite verlangsamen. Die Ausgabe der Shards erscheint erst beim Einsammeln, dann aber in
der bisherigen Reihenfolge.

### Option D: Getestete Skripte (`factory-update.sh`, `factory-sync.sh`) beschleunigen

Vorteile: Das trifft die eigentliche Ursache, 4 s bzw. 1,7 s pro Lauf.
Nachteile: Die Spec schließt Änderungen an den getesteten Skripten aus. Es wäre eine eigene
Änderung mit eigenem Risiko an sicherheitsrelevantem Code (Token-Trennung #37). Bleibt eine Option
für ein eigenes Issue.

### Option E: Allgemeiner Parallel-Runner für alle Abschnitte von `run-tests.sh`

Vorteile: größtes Potenzial.
Nachteile: Außerhalb des Scopes (Spec Q2). Die übrigen Abschnitte teilen Variablen und
Temp-Verzeichnisse über Abschnittsgrenzen hinweg. Der Umbau wäre groß und schwer zu prüfen.

## Begründung

Option C ist die einfachste Variante, die die Ziele der Spec erreichen kann. Die Messung zeigt, dass
sich der Aufwand ohne Abdeckungsverlust kaum senken lässt (Option A). Deshalb muss die Wanduhrzeit
über Überlappung sinken. Option B überlappt zu grob. Option E und Option D überschreiten den Scope.
Der Ergebnisvertrag (D3, D4) ist der einzige neue Vertrag. Er ist intern in der Suite, fail-closed
und mit Tests belegbar. Nach außen bleibt der Vertrag der Suite gleich: Ausgabe der Assertions,
Summenzeile, Exit-Code.

## Konsequenzen

- **Konsumenten** erhalten mit dem nächsten Factory-Update die neuen Dateien (Seite `factory`, im
  Manifest) und das parallele Verhalten. Ihr CI-Lauf wird kürzer, sobald die Gruppe dort mitläuft.
  `FACTORY_SELF_TEST_SERIAL=1` bleibt als Rückfall.
- **Restrisiko Gesamtziel:** Der Rest der Suite (~204 s bei der Messung im Issue) wird inhaltlich
  nicht beschleunigt und ist die Untergrenze der Wanduhrzeit. Bleiben durch Ressourcenkonkurrenz
  weniger als 36 s Luft, verfehlt die Suite AK3, obwohl AK2 erfüllt ist. In dem Fall wird eskaliert
  und der Scope nicht still erweitert.
- **Neue Pflicht für spätere Testgruppen:** Eine Gruppe, die als Shard läuft, darf keinen Zustand
  außerhalb ihres eigenen Temp-Verzeichnisses verändern und keine Variable des Haupt-Prozesses
  voraussetzen außer `FACTORY_ROOT`, `HAS_YQ`, `CHECKS_DIR`, `SCRIPTS_DIR` und den Helfern.
- **Fehlersuche:** Die Ausgabe eines roten Shards erscheint am Sammelpunkt, nicht live.
  `FACTORY_SELF_TEST_SERIAL=1` ändert daran nichts, es entfällt nur die Überlappung. Dafür nennt
  jede abgebrochene Gruppe ihren Namen (D4).
- **Bestehende Guards** sind mitzupflegen: die Liste ausgelieferter Testdateien (`SHIPPED_TESTS_28`
  in `run-tests.sh`), `OWNERSHIP.md` (neue Dateien auf der Seite `factory`), die
  Neutralitäts-/Fixture-Läufe (Factory-ADR-064 D6) und die Verweise auf `factory-lock-tests.sh` in
  ADR-063 und Spec #37. Die Verweise bleiben historisch richtig, ein Hinweis auf den neuen Ort genügt.
