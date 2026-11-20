# Review: Task 41

Geprüft: `git diff origin/main...HEAD` (12 Dateien, +810/−15) gegen `docs/specs/spec-41-fetch-token-abschirmen.md` und
Factory-ADR-063 Nachtrag 2026-11-20 (E28–E34). Drei Runden: Logik, Code-Qualität, Architektur. Testgruppe
`factory-lock-41-tests.sh` lokal gelaufen: 78 grün, 0 rot.

## Kritische Findings (müssen behoben werden)

_(keine)_

## Wichtige Findings (sollten behoben werden)

- [ ] [scripts/factory-update.sh:67] Der Smoke-Befehl `FETCH_SMOKE_SCRIPT` prüft nur, ob die Werkzeuge da sind, dass
  kein root läuft und welche Umgebung und Mounts der Container hat. Die Schritte, die nur `fetch` im Container braucht,
  laufen dort nicht: `cp -a /src/. /tmp/work`, `git status` bzw. `require_clean_tree` in der Kopie und `git commit` als
  Runner-UID ohne passwd-Eintrag mit `HOME=/tmp`. Offline deckt sie nur der Fake im Modus `emulate` ab, und der läuft auf
  dem Host. Das Ziel von AK4.3 („sonst liefe der Container-Pfad erst beim Konsumenten zum ersten Mal") ist damit nur zum
  Teil erreicht. Vorschlag: Den Smoke harmlos um `cp -a /src/. /tmp/work && git -C /tmp/work status --porcelain >/dev/null
  && git -C /tmp/work -c user.name=smoke -c user.email=smoke@localhost commit --allow-empty -q -m smoke` erweitern. Das
  bleibt ohne Release und ohne Netz.
- [ ] [tasks/task-41-fetch-token-abschirmen.md] AK1.4 und AK4.3 sind noch offen und hängen am ersten grünen Lauf von
  `fetch-container-smoke`. Der Digest `sha256:a72b…` ist nicht gegen die Registry geprüft. Vor dem Merge muss dieser
  Job auf dem PR grün sein, sonst bleiben Checkboxen offen (Guardrail „keine offenen Checkboxen → kein Done").
  `/pr-shepherd` muss also auf den Job warten, auch wenn er kein Pflicht-Check im Ruleset ist.

## Nitpicks (optional)

- [ ] [scripts/factory-update.sh:65] `FETCH_CONTAINER_SCRIPT` schreibt `/out/update.bundle` fest, obwohl es die
  Konstante `FETCH_BUNDLE` gibt. `require_single_bundle` prüft gegen die Konstante. Ändert jemand nur eine der beiden
  Stellen, fällt das erst in E32 als „nicht genau die reguläre Datei" auf. Der Test schreibt den String bewusst fest,
  das ist in Ordnung.
- [ ] [scripts/checks/tests/factory-lock-41-tests.sh:104-105] Der unabhängige Verbots-Prüfer `run_forbidden_free_41`
  erkennt `--security-opt systempaths=unconfined` und `--cgroupns=host` nicht, wenn sie als getrenntes Argument kommen.
  Der exakte Vergleich `run_exact_41` fängt beide. Nur relevant, falls der exakte Vergleich einmal mit dem Skript
  mitgezogen wird.
- [ ] [scripts/factory-update.sh:207] `docker build` läuft ohne `--pull`/`--no-cache`. Auf einem selbst gehosteten
  Runner mit langlebigem Daemon kann die gecachte `apt-get install`-Schicht veraltete Pakete ohne Sicherheits-Updates
  liefern. Auf GitHub-gehosteten Runnern wirkungslos. Lösung: `--no-cache`, oder das Restrisiko „Image-Lieferkette" im
  ADR um diesen Fall ergänzen.
- [ ] [docs/specs/spec-41-fetch-token-abschirmen.md:65] AK1.3 sagt „Eingebunden sind nur ein eigens angelegtes
  Arbeitsverzeichnis und ein eigenes Ausgabeverzeichnis". Umgesetzt sind laut E30/E31 drei Mounts: Checkout nur lesend,
  `yq` nur lesend, `/out`. Das ADR erklärt die Abweichung, die Spec nicht. Ein Halbsatz mit Verweis auf E31 reicht.

## Positives

- Saubere Isolationsgrenze: Alle `docker run`-Optionen stehen an genau einer Stelle (`run_in_fetch_container`).
  `fetch-isolated` und `fetch-smoke` nutzen sie beide, und ein Test belegt, dass die Optionen gleich sind.
- Der Rückweg ist streng fail-closed: Das Ausgabeverzeichnis muss neu sein, danach muss genau eine reguläre Datei darin
  liegen (kein Symlink, kein Verzeichnis, kein Zusatzeintrag). Der Host ruft auf den Container-Daten kein `git` auf.
  Hardlinks über Bind-Mount-Grenzen lehnt der Kernel ohnehin ab (EXDEV).
- `fetch` ist in CI gesperrt (`GITHUB_ACTIONS=true`). Das nutzt aus, dass Docker die Variable nicht durchreicht.
  Elegant, und per Mutation belegt.
- Starke Tests: `docker run` wird gegen den exakten Aufruf aus E31 verglichen und zusätzlich unabhängig auf Verbotenes
  geprüft. Jede tragende Eigenschaft hat einen Mutationsbeleg, Mutanten, die nicht greifen, fallen selbst auf. Dazu
  kommt eine Ende-zu-Ende-Nachbildung des Containers mit feindlicher Nutzlast (`core.fsmonitor`, Hooks) und Gegenprobe
  mit durchgereichtem Token.
- Der Anker `wf_ok_37` wurde nicht ersatzlos entfernt. `wf_fetch_ok_41` prüft die ganze Schrittfolge des Jobs, ist also
  strenger (AK3.2).
- Die Doku ist vollständig: ADR-Nachtrag mit ehrlichem Restrisiko, E17-Berichtigung, OPERATING §0.6, Breaking-Hinweis im
  CHANGELOG, `OWNERSHIP.md` und Guard `#431 AK-F1` kennen den siebten Job.

## Empfehlung
APPROVED
