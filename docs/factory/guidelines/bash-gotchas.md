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

## Querregel

`set -euo pipefail` ist Default, aber **`-e` bewusst weglassen, wo Befehls-Fehler explizit
ausgewertet werden** (z. B. API-Aufrufe, die fehlschlagen dürfen). Dann den Fehlerfall
*aktiv* behandeln (Rückgabewert prüfen), nicht auf `-e` verlassen.
