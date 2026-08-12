# Bash-Gotchas (codifiziert aus echten Bugs)

Stolpersteine, die in den Factory-Skripten wiederholt zu „Tests grün, Verhalten falsch"
geführt haben. Beim Schreiben/Reviewen von Bash gegen diese Liste prüfen.

> Bewusst **nicht** per `@import` in `CLAUDE.md` geladen (Kontext schlank halten). Beim
> Arbeiten an Shell-Skripten gezielt lesen.

---

## 1. `if cmd; then …; fi` ohne `else` setzt `$?` auf 0

Ein `if`-Statement ohne `else` liefert exit 0, wenn die Bedingung falsch ist. Das
**überschreibt den Exit-Code des Befehls** – ihn danach noch zu lesen, ergibt 0.

```bash
# FALSCH – $? ist hier 0, nicht der echte Fehlercode:
if mycmd; then return 0; fi
reason="mycmd endete mit exit $?"      # → "exit 0", obwohl mycmd fehlschlug

# RICHTIG – im else-Zweig abgreifen:
if mycmd; then return 0; else rc=$?; reason="exit $rc"; fi
# oder mit &&:
mycmd && return 0
reason="exit $?"                        # korrekter Code
```

**Bit uns 2×:** `post-merge-verify.sh` (#23 und nochmal #24, CMD-Exit-Code wurde als 0 gemeldet).

---

## 2. `grep -c` bei 0 Treffern: zweizeiliger Wert UND non-zero-Exit

`grep -c` gibt bei 0 Treffern `0` aus **und** endet exit 1. Das macht **zwei** Fallen auf:

1. `|| echo 0` hängt ein **zweites** `0` an → `"0\n0"`, bricht Zahl-/Tabellen-Logik.
2. Lässt man das `|| echo 0` einfach weg, schluckt nichts mehr den exit 1 → unter
   `set -e` **bricht die Zuweisung ab** (genau die Querregel unten).

```bash
# FALSCH (Falle 1): n = "0\n0"
n=$(grep -c foo file || echo 0)

# FALSCH (Falle 2): bricht unter `set -e` ab, wenn 0 Treffer
n=$(grep -c foo file 2>/dev/null); n=${n:-0}

# RICHTIG: non-zero schlucken (|| true), Leerwert separat abfangen
n=$(grep -c foo file 2>/dev/null || true); n=${n:-0}
```

**Bit uns:** `metrics.sh`/`interrupt-log`-Zählung (#12); und Falle 2 nochmal in
`run-pipeline.sh` `pipeline_summary` — eingeführt **beim Fix von Falle 1** (#33). Lehrstück:
der naive Fix einer Gotcha lief direkt in die nächste.

---

## 3. `grep -q` in einer Pipe + `set -o pipefail` → SIGPIPE-Falschrot

`grep -q` beendet sich beim ersten Treffer sofort und schließt die Pipe. Der Producer links
bekommt SIGPIPE (exit 141); mit `pipefail` färbt das die ganze Pipe rot – obwohl der Match
erfolgreich war.

```bash
# FALSCH (unter set -o pipefail):
producer | grep -q muster            # exit 141, wenn producer noch schreibt

# RICHTIG – Output erst einfangen, dann greppen:
out=$(producer)
printf '%s' "$out" | grep -q muster
```

**Bit uns:** Test-Suite-Fälle (#23, #24 – Vorrang-/Guard-Checks wurden fälschlich rot).

**Verschärfung bei Negation (aus #284):** Wird das Pipe-Ergebnis zusätzlich negiert
(`! producer | grep -q muster`, etwa um „Muster NICHT gefunden" zu prüfen), kippt die
SIGPIPE-Falle von Falschrot in **Falschgrün**: Im Fund-Fall liefert die Pipe unter `pipefail`
exit 141 (SIGPIPE des Producers), die vorangestellte Negation macht daraus 0 – der Guard meldet
„nicht gefunden", obwohl das Muster da war. Betroffen ist damit ausgerechnet der Fall, den der
Guard fangen soll; ein still versagender Guard ohne sichtbaren Fehlschlag. Fix bleibt identisch:
Producer-Output zuerst einfangen (Variable/Here-String), dann greppen – keine Pipe, die ein
SIGPIPE erzeugen kann. In #284 bewusst so konstruiert (Here-String statt Pipe für
`poll_trigger_guard`), bevor die Falle zuschlagen konnte.

---

## 4. `"${arr[@]}"` bei leerem Array unter `set -u` → „unbound variable" (bash < 4.4 / macOS 3.2)

Auf **bash < 4.4** – und der macOS-Default ist **3.2.57** (`/usr/bin/env bash`) – wirft ein
**leeres** Array, das mit `"${arr[@]}"` expandiert wird, unter `set -u` **„unbound variable"**.
(Ab bash 4.4 ist das behoben.) Der Guard ist die `+`-Alternativ-Expansion:

```bash
# FALSCH – crasht unter set -u auf bash 3.2, wenn opts leer ist:
local -a opts=()
[ -n "$repo" ] && opts=(--repo "$repo")
gh issue create "${opts[@]}" --title "$t"        # opts leer → unbound variable

# RICHTIG – `+`-Guard: expandiert zu nichts, wenn das Array leer/ungesetzt ist:
gh issue create ${opts[@]+"${opts[@]}"} --title "$t"
```

**Zwei Ebenen, die das tückisch machen:**

1. **Command-Substitution unterdrückt `set -e`, aber NICHT `set -u`.** Auf bash 3.2 (kein
   `inherit_errexit`) läuft der Code in `num=$(create_issue …)` **ohne** errexit – ein
   `-e`-abhängiger Bug bleibt dort also stumm. **nounset gilt trotzdem.** Darum schlägt genau
   der Array-Guard-Bug auch im gefangenen Aufruf zu, während ein errexit-Bug sich versteckt.
2. **Eine gesourcte Lib immer unter den Shell-Optionen der echten Aufrufer testen**
   (`set -euo pipefail`). Ein Test-Harness, das ohne `set -u` sourct (`bash -c 'source …'`
   ohne `set -u`), ist **nachsichtiger als die Produktion** und übersieht genau diese Klasse.
   Faustregel: Wenn die Aufrufer `set -euo pipefail` setzen, muss mindestens ein Test die
   Funktion unter `set -euo pipefail` fahren – inkl. der Grenzfälle mit leeren Arrays.

**Bit uns:** #82 (`create-issue.sh`) – der no-repo-Pfad (`repo_args` leer, der dokumentierte
gh-Auto-Erkennungs-Pfad, den die Skills nutzen) crashte unter `set -u` auf bash 3.2. Der
„deckende" Test lief ohne `set -u` und übersah es; erst der **unabhängige Review** fand den
Bug. `${#arr[@]}` und `${arr[@]+"${arr[@]}"}` sind unter `set -u` sicher – die eine leere
Expansion war vergessen worden.

> Kein zuverlässiges Gate: unguarded `"${arr[@]}"` maschinell zu finden erzeugt zu viele
> False-Positives (Nutzung innerhalb `[ ${#arr[@]} -gt 0 ]`-Guards ist sicher). Bleibt eine
> Review-/Checklisten-Regel – ein Gate, das nicht verlässlich greift, ist schlechter als keins.

---

## 5. Shell-Test-Isolation: alle `source`-Abhängigkeiten mitkopieren

Tests, die ein Skript in ein isoliertes Temp-Verzeichnis kopieren, müssen **alle** Dateien
mitkopieren, die das Skript direkt oder transitiv per `source`/`. ` einbindet.

Fehlt eine Source-Abhängigkeit, bricht das Skript unter `set -euo pipefail` **sofort beim
`source`-Aufruf** ab – noch vor dem eigentlich getesteten Code. Der Test schlägt fehl, aber
aus dem **falschen Grund** (fehlende Datei statt echtem Bug) – was den echten Befund verdeckt.

```bash
# FALSCH – report-verdict.sh fehlt im Temp-Verzeichnis:
cp scripts/run-pipeline.sh "$tmp/"
bash "$tmp/run-pipeline.sh" …      # → sofortiger Abbruch: source scripts/lib/report-verdict.sh

# RICHTIG – alle Source-Abhängigkeiten mitkopieren:
cp scripts/run-pipeline.sh "$tmp/"
mkdir -p "$tmp/scripts/lib"
cp scripts/lib/report-verdict.sh "$tmp/scripts/lib/"
bash "$tmp/run-pipeline.sh" …
```

**Faustregel:** Nach jedem `cp <skript> $tmp`: `grep -E '^\. |source ' "$skript"` prüfen –
alle gefundenen relativen Pfade müssen ebenfalls in `$tmp` landen.

**Bit uns:** #91 – 3 Self-Tests liefen nach dem Patch rot, weil `run-pipeline.sh` neu
`scripts/lib/report-verdict.sh` sourct und die Testaufbauten die Kopie fehlten.

---

## 6. `printf '%f'` ist locale-abhängig – Zahlenformatierung in `jq`/`awk` statt bash

`bash printf '%.1f'` parst sein `%f`-Argument über `strtod()`, das **locale-abhängig** ist.
Unter einer Locale mit Komma-Dezimaltrenner (z. B. `de_DE.UTF-8`) schlägt das Parsen eines
Punkt-Dezimalwerts wie `"1.6436..."` fehl (`printf: ... invalid number`). `printf` fällt dann
**still auf `0,0` zurück** – kein non-zero Exit (erst recht nicht wenn `metrics.sh` mit
`set -uo pipefail` ohne `-e` läuft), kein sichtbarer Fehler im Report.

```bash
# FALSCH – schlägt unter de_DE-Locale fehl:
avg_h=$(jq -r '((add/length)/3600)' <<< "$prs")   # liefert "1.6436..."
printf '%.1f h' "$avg_h"   # → "printf: invalid number: 1.6436..." stderr, Output "0,0 h"

# RICHTIG – Formatierung komplett in jq (Punkt-Dezimaltrenner, immer locale-unabhängig):
avg_h=$(jq -r '((add/length)/3600 * 10 | round) / 10 | tostring' <<< "$prs")
echo "${avg_h} h"   # → "1.6 h", unabhängig von LC_NUMERIC/LC_ALL
```

**Alternativen:**
- `LC_NUMERIC=C printf '%.1f h' "$value"` – Quick-Fix; funktioniert nicht, wenn der Aufrufer
  `LC_NUMERIC` global per `export` setzt. Strukturell schwächer als Umzug in `jq`.
- `awk 'BEGIN{printf "%.1f h\n", v}' v="$value"` – `awk` nutzt i. d. R. den C-Locale für
  `printf`, aber das ist nicht portabel garantiert.

**`jq tostring` bei ganzzahligem Ergebnis:** `2.0` → `"2"` (kein `.0`), `"2.0"` → `"2.0"`.
Falls ein festes `x.x`-Format nötig ist, mit `if . == floor then tostring + ".0" else tostring end`
erzwingen. In rein indikativen KPI-Reports (wie Lead-Time) ist das YAGNI.

**Bit uns:** `metrics.sh` (#96) – Lead-Time zeigte unter `de_DE.UTF-8` `0,0 h` statt dem
korrekten Wert; beobachtet bei Task 67.

---

## 7. Substring-Match in strukturellen Guards: spezifischen String verwenden

`grep -q 'pnpm test'` trifft auch die Zeile `COVERAGE_CMD="…:-pnpm test:coverage"` als
Substring. Wird der Coverage-Befehl auf z. B. `pnpm coverage` geändert, bleibt der Guard
fälschlich grün (false positive). Das Gate prüft dann nicht mehr, was es zu prüfen vorgibt.

```bash
# FALSCH – 'pnpm test' trifft als Substring auch 'pnpm test:coverage':
grep -q 'pnpm test' run-pipeline.sh      # schlägt nicht an, obwohl coverage-Zeile fehlt

# RICHTIG – immer den spezifischsten (längsten) String verwenden:
grep -q 'pnpm test:coverage' run-pipeline.sh   # trifft nur die Coverage-Zeile
grep -qF -- 'pnpm test:coverage' run-pipeline.sh  # -F: kein Regex, kein Fehlinterpretieren
```

**Faustregel:** Prüft ein Guard auf einen Befehlsstring, immer **den vollständigen,
spezifischsten String** nehmen – nie eine Abkürzung, die als Substring einer längeren
Variante aufgehen könnte. Zur Absicherung: einen Test mit Negativ-Beispiel schreiben
(geänderter Befehl → Guard schlägt an).

**Bit uns:** #101 – `grep -q 'pnpm test'` im Default-Guard deckte `pnpm test:coverage`
implizit ab; eine Änderung des Coverage-Befehls wäre unentdeckt geblieben.

---

## 8. `${VAR-default}` vs `${VAR:-default}`: leerer Wert als bewusster Opt-out

`${VAR:-default}` (Doppelpunkt-Bindestrich) nimmt den Default, wenn `VAR` **unset ODER leer**
ist. `${VAR-default}` (nur Bindestrich) nimmt den Default **nur bei unset** – ein bewusst
`VAR=""` gesetzter Wert bleibt leer. Wer will, dass ein *leer gesetzter* Env-Wert ein Gate
**deaktiviert** (echter Opt-out), muss `-` nehmen. Mit `:-` fällt der leere Wert still auf den
enforcing Default zurück – der vermeintliche Opt-out verpufft, das Gate bleibt scharf.

```bash
# Ziel: unset → Default-Gate scharf; FACTORY_X="" → Gate bewusst aus.

# FALSCH – :- behandelt "" wie unset, fällt auf den Default zurück (kein Opt-out):
CMD="${FACTORY_X:-pnpm gate}"     # FACTORY_X="" → CMD="pnpm gate" (Gate läuft doch)

# RICHTIG – einfaches - : unset → Default (fail-closed), "" → leer → else-Zweig (aus):
CMD="${FACTORY_X-pnpm gate}"      # FACTORY_X="" → CMD="" → Gate deaktiviert
if [ -n "$CMD" ]; then eval "$CMD"; else echo "Gate deaktiviert (FACTORY_X leer)"; fi
```

**Faustregel:** Soll ein leerer Env-Wert ein bewusster Opt-out sein → `${VAR-default}`
(einfacher Bindestrich). Soll leer wie unset behandelt werden (immer Default) → `${VAR:-default}`.
Die Wahl explizit im WHY-Kommentar begründen; sie ist auf den ersten Blick unsichtbar.

**Struktur-Guard darauf abstimmen (Querbezug §7 + PROJECT-CONTEXT #114):** Ein Struktur-Test,
der so ein Gate absichert, muss den **vollständigen `${VAR-default}`-Ausdruck** pinnen
(`grep -qF '${FACTORY_X-pnpm gate}'`), nicht nur den Bezeichner `FACTORY_X` – der steht meist
auch in der Kommentar-Prosa und matcht dann fälschlich. Das pinnt zugleich den **Default-Literal**,
den ein Verhaltens-Test **nicht** abdeckt: wer im Test den Override immer explizit setzt
(`FACTORY_X=false/true/""`), prüft nie den unset-Default. Ein versehentlich auf `true` geänderter
Default (Gate per Default aus) bliebe sonst grün.

**Bit uns:** #149 – Format-Gate in `pre-push.sh`. Erst `:-` gewählt (leerer Override sollte
deaktivieren, tat es aber nicht → Test rot); auf `-` korrigiert. Der Struktur-Grep matchte
anfangs die Kommentar-Prosa (`format:check`); erst der Grep auf `${FACTORY_FORMAT_COMMAND-pnpm format:check}`
pinnte Default + Semantik code-eindeutig.

---

## 9. `commit-msg`-Hook: Git säubert Kommentarzeilen erst NACH dem Hook – jeder Aufrufpfad hinterlässt anderen Rohinhalt

Ein `commit-msg`-Hook bekommt den Pfad zur Message-**Datei** übergeben, bevor Git irgendetwas
daraus entfernt (`--cleanup`). Was in dieser Datei tatsächlich steht, hängt vom Aufrufpfad ab –
ein Hook, der nur den `-m`-Fall testet, übersieht mindestens zwei weitere:

```bash
# `-m` (kein Editor): Datei enthält NUR die Message – der einfache Fall.
git commit -m "--help"                     # Datei: "--help\n"

# Editor-Pfad (kein -m/-e/--amend/Merge): Datei enthält die Message PLUS das
# unbearbeitete Template – jede Zeile mit Kommentar-Präfix (Default '#').
git commit                                 # Datei: "--help\n\n# Please enter …\n#\n# On branch …\n"

# Verbose-Pfad (`-v`/`--verbose`, mit ODER ohne -m): Git hängt den Diff UNTER der
# Scissors-Zeile ("# ---- >8 ----") an – OHNE Kommentar-Präfix. Ein Filter, der nur
# präfigierte Zeilen verwirft, lässt den unpräfigierten Diff in der Message stehen.
git commit -v                              # Datei: "--help\n…\n# ---- >8 ----\ndiff --git a/x b/x\n@@ …\n+x\n"
```

Ein reiner Trim-Vergleich (`TRIMMED = message`) greift nur auf dem `-m`-Pfad. Ein Filter, der
nur Kommentarzeilen verwirft, greift auf dem Editor-Pfad, aber nicht mehr auf dem Verbose-Pfad
– der Diff ist nicht präfigiert. Beide Lücken wurden empirisch erst in **zwei separaten**
Review-Runden gefunden (Editor-Pfad, dann Verbose-Pfad), weil sie wie derselbe Fix aussehen,
aber unterschiedliche Zeilen im Guard betreffen.

**Faustregel:** Beim Schreiben eines `commit-msg`-Hooks (oder eines anderen Hooks, der eine
von Git verwalteten Datei roh liest) **vor der ersten Implementierung** alle bekannten
Aufrufpfade auflisten und je einen End-to-End-Test dagegen schreiben – nicht nur den, an den
man zuerst denkt (meist `-m`). Für `commit-msg` mindestens: `-m`, Editor ohne `-m`, `-v`/
`--verbose`, `--cleanup=scissors`. Ein Filter muss zusätzlich an einer strukturellen
Abbruchmarke (hier: der Scissors-Zeile) stoppen, nicht nur zeilenweise nach Präfix filtern –
sonst rutscht unpräfigierter Inhalt unterhalb der Abbruchmarke durch.

**Bit uns:** #262 – Editor-Pfad-Lücke in Review-Runde 2 gefunden und gefixt, Verbose-Pfad-Lücke
(dieselbe Fehlerklasse, andere Ursache) erst in Review-Runde 3.

---

## 10. `git diff --cached --quiet` beweist nicht „kein `git add`" – vergleicht Index gegen HEAD, nicht gegen leer

Ein Test will belegen, dass ein Guard `git add` verhindert hat, und prüft dafür
`git diff --cached --quiet` (exit 0 = „nichts staged"). Das stimmt nur, solange kein
nachfolgender Commit lief. Läuft trotz entferntem Guard die volle Kette `git add -A && git
commit`, ist der Index nach dem Commit identisch mit dem **neuen** HEAD – der Vergleich liefert
wieder „keine Differenz" und die Assertion bleibt grün, obwohl `git add` (und sogar der Commit)
tatsächlich passiert ist.

```bash
# FALSCH – vergleicht Index gegen HEAD, nicht gegen "nichts staged":
git diff --cached --quiet                  # exit 0 auch nach vollem add+commit (Index==neuer HEAD)

# RICHTIG – prüft direkt, dass die Datei nie den Tracked-Zustand verlassen hat:
[ "$(git status --porcelain -- datei.txt)" = "?? datei.txt" ]   # nur wahr, wenn `git add` NIE lief
```

**Faustregel:** Soll ein Test beweisen, dass ein bestimmter Git-Schritt (hier: `add`) NICHT
gelaufen ist, den Zustand direkt gegen das erwartete Ergebnis dieses Schritts prüfen (Datei
bleibt `??` untracked), nicht über einen Index-vs-HEAD-Vergleich, der auch durch einen ganz
anderen, weiter gelaufenen Schritt (ein Commit) wieder "leer" werden kann.

**Bit uns:** #262 – die Assertion „führt kein `git add` aus" wäre bei entferntem Guard trotzdem
grün geblieben, weil der nachfolgende Commit den Index wieder mit HEAD in Deckung gebracht hätte.

---

## Querregel

`set -euo pipefail` ist Default, aber **`-e` bewusst weglassen, wo Befehls-Fehler explizit
ausgewertet werden** (z. B. API-Aufrufe, die fehlschlagen dürfen). Dann den Fehlerfall
*aktiv* behandeln (Rückgabewert prüfen), nicht auf `-e` verlassen.
