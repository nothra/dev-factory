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

## Querregel

`set -euo pipefail` ist Default, aber **`-e` bewusst weglassen, wo Befehls-Fehler explizit
ausgewertet werden** (z. B. API-Aufrufe, die fehlschlagen dürfen). Dann den Fehlerfall
*aktiv* behandeln (Rückgabewert prüfen), nicht auf `-e` verlassen.
