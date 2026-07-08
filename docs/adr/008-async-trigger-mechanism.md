# ADR 008: Async-Trigger – Pipeline-Start per GitLab-Event statt Terminal

## Status
**Accepted** (2026-06-19) — Option A (Scheduled-Poll). Entscheidung durch CM-Review (!25)
bestätigt, alle 5 Fragen geklärt, Vorbedingungen V-0…V-3 benannt. Umsetzung: Spur A
(Code, mock-getestet) in diesem MR; Spur B (GitLab-Admin-Setup) als Checkliste in der
MR-Beschreibung — End-to-End-Verifikation erst nach Spur B.

> **Update (2026-07-08, [ADR-012](012-github-platform-migration.md)):** Auf GitHub
> migriert. Option A (Scheduled-Poll) bleibt die Entscheidung; die Umsetzung nutzt jetzt
> einen GitHub Actions Scheduled Workflow (`.github/workflows/factory-poll.yml`), die
> `gh`-CLI für Issues/Labels und die Workflow-`concurrency`-Group statt `resource_group`.
> Der Budget-Guard und die Label-State-Maschine sind unverändert. Historischer Text unten
> beschreibt die GitLab-Variante.

## Datum
2026-06-17 (Entwurf) · 2026-06-19 (Accepted)

## Kontext

`run-pipeline.sh` startet heute ausschließlich manuell (`bash scripts/run-pipeline.sh <id>`).
Das **definierende L4-Merkmal** („Systems Orchestrator") ist die **asynchrone, event-getriggerte
Ausführung**: die Pipeline startet, wenn ein Issue erstellt/gelabelt wird – nicht, wenn jemand
ein Terminal öffnet (Issue #10, Stufe 2).

Voraussetzung erfüllt: CI-Gates (#8) sind da. Damit ist Async-Trigger entblockt.

### Entscheidungstreiber

| Treiber | Warum kritisch |
|---|---|
| **Kosten** | Ein async-getriggerter Lauf = 6+ Claude-Sessions. Unkontrolliert teuer. |
| **Auth** | Claude CLI braucht Credentials im Runner (API-Key/OAuth/Gateway-Base-URL). |
| **Infra** | Braucht es einen extern erreichbaren Endpunkt – oder geht es repo-intern? |
| **Latenz** | Sofort (Webhook) vs. bis-zu-Poll-Intervall (Scheduled). |
| **Sicherheit** | Wer darf einen teuren Lauf auslösen? Idempotenz gegen Doppel-Trigger. |

## Optionen

### Option A — Scheduled Pipeline + Issue-Polling  *(Empfehlung)*

GitLab Scheduled Pipeline (z. B. alle 15 min) läuft ein Poll-Skript, das Issues mit Label
`factory::run` sucht und für jedes neue `run-pipeline.sh` anstößt.

- **+** Repo-intern, kein externer Endpunkt, GitLab-nativ. Im Template sofort lauffähig.
- **+** Leicht abschaltbar (Schedule löschen), leicht zu auditieren.
- **+** Der Poll selbst ist billig – teuer wird nur der Claude-Lauf, und der feuert nur bei gelabeltem Issue.
- **−** Nicht echt event-driven (Latenz ≤ Poll-Intervall).
- **−** Braucht eine Label-Statemaschine gegen Doppel-Trigger (s. u.).

### Option B — Webhook → Pipeline-Trigger-Token

GitLab Issue-Webhook → Endpunkt → ruft Pipeline-Trigger-API mit Token.

- **+** Echt event-driven, sofort.
- **−** Braucht einen extern erreichbaren, abgesicherten Endpunkt (Hosting + Secret + Token-Mgmt).
- **−** Mehr bewegliche Teile, nicht self-contained – für ein **Template** eine schwere Abhängigkeit.

### Option C — Status quo (manuell)

`bash run-pipeline.sh <id>`. **−** Kein L4-Async – verfehlt den Zweck von #10. Nur als Baseline gelistet.

## Empfehlung (zur Bestätigung)

**Option A** als Template-Default: self-contained, opt-in über Label, mit Budget-Guard.
**Option B** als dokumentierter Upgrade-Pfad für Teams, die sofortiges Triggern brauchen und
einen Endpunkt hosten können. Damit bleibt das Template leichtgewichtig, ohne die schnelle
Variante zu verbauen.

## Querschnitts-Themen (gelten unabhängig von A/B)

- **Kosten-Guard (Pflicht):** async-Lauf nur per explizitem Label + Obergrenze (z. B. max. N
  Auto-Läufe/Tag oder Concurrency-Cap). Kein Auto-Trigger ohne Deckel.
- **Auth:** Credentials als *masked* CI/CD-Variable (`ANTHROPIC_API_KEY`/OAuth) **oder** –
  elegant – über die **Gateway-Base-URL aus Renes Track** (#17/OTEL-Gateway): das Gateway hält
  die Credentials, der Runner kennt nur die URL. Verzahnt Async-Trigger mit der Gateway-Arbeit.
- **Idempotenz / Label-Statemaschine:** `factory::run` → `factory::running` →
  `factory::done` | `factory::interrupted` | `factory::failed`. Verhindert, dass derselbe
  Issue mehrfach feuert. Der Endzustand unterscheidet sauberen Abschluss (`done`),
  menschliche Entscheidung (`interrupted`, Sentinel vorhanden) und echten Pipeline-Fehler
  (`failed`) — sonst maskiert ein Crash als „menschliche Entscheidung nötig".
- **Stale-Reaper (`FACTORY_RUN_TIMEOUT`, Default 3600s):** ein durch CI-Kill/Timeout auf
  `running` hängengebliebener Lauf würde den Concurrency-Guard dauerhaft blockieren. Der Poll
  setzt verwaiste `running`-Issues (älter als Timeout) auf `interrupted` zurück und prüft vor
  dem Trigger, dass der `run→running`-Flip wirklich gesetzt ist.
- **Tageskappe zählt `done` + `interrupted` + `running` von heute** — ein interrupted Lauf hat
  bereits Sessions verbraucht und darf nicht aus der Kappe fallen (sonst leckt der Deckel).
- **Fail-closed ist laut:** „nichts zu tun" beendet mit exit 0; „Zustand nicht ermittelbar"
  (API-Fehler) beendet mit exit 3 (roter Job), nie als stiller Leerlauf.
- **Interrupt-Propagation:** async-Läufe ehren den Interrupt-Mechanismus (ADR-004) – bereits
  task-isoliert, kein Umbau nötig.
- **Komposition:** Async-Trigger reiht sich vor `pr-shepherd` (#7, Auto-Merge) ein → ein
  gelabeltes Issue kann theoretisch bis zum Merge durchlaufen. Bewusst erst nach stabilem
  Kosten-Guard freischalten.

## Geklärt (CM-Review !25)

1. **Poll-Intervall:** 15 min Default, per `FACTORY_POLL_INTERVAL` konfigurierbar. Leerläufe ~gratis, Latenz beim async-Use-Case egal.
2. **Budget-Guard:** alle drei kombiniert, **fail-closed** — Label `factory::run` als einzige Eintrittstür + **Concurrency-Cap = 1** + harte Tageskappe `FACTORY_MAX_RUNS_PER_DAY` (konservativ, z. B. 5). Guard greift **vor** dem ersten Claude-Lauf. Nicht verhandelbar.
3. **Auth:** masked `ANTHROPIC_API_KEY` als Default, Gateway-Base-URL (#17) als dokumentierter Upgrade-Pfad über **eine** Env-Var. Bewusst **nicht** auf #17 warten (keine Track-Kopplung).
4. **Branch/MR:** bestehenden `start-work.sh`-Pfad → `run-pipeline.sh` → bei **Draft-MR stoppen**; Auto-Merge via `pr-shepherd` (#7) erst nach stabilem Guard. Reuse ist nicht gratis — siehe Vorbedingung V-1.
5. **Runner:** Custom-Image mit claude-CLI Pflicht (V-2); shared Runner ok, wenn er das Image zieht; self-hosted als Upgrade.

## Vorbedingungen & unterschätzte Aufwände (CM-Review !25 — aus dem Code geprüft)

Diese drei sind **keine Mechanik** und müssen vor `Accepted` als echter Aufwand eingeplant sein —
sonst stimmt das „dann ist es nur noch Mechanik" nicht:

- **V-1 · `start-work.sh` ist nicht CI-ready.** Lokale Annahmen: `git checkout main` + `pull --rebase`
  scheitern im Runner (shallow single-ref, kein `GIT_DEPTH: 0`); `git push -u` braucht ein Token mit
  `write_repository` (CI_JOB_TOKEN reicht nicht); kein Dedup (Branch+MR pro Lauf). → CI-Hardening oder
  schlanker CI-nativer Pfad.
- **V-2 · Eigenes Runtime-Image nötig.** lint/test laufen auf nacktem `alpine` ohne claude-CLI. Async
  braucht ein Custom-Image mit CLI (kaniko → Registry, analog `factory-selftest`). Das ist der eigentliche
  Setup-Aufwand, nicht die Runner-Wahl.
- **V-3 · Label-State + Tageskappe von Grund auf.** Labels sind greenfield (`grep -r "factory::"` leer).
  Scheduled Pipelines haben **kein Gedächtnis** → die Tageskappe braucht eine **API-basierte Zählquelle**
  (z. B. heute auf `::done` gesetzte Issues), kein zurückcommittetes State-File (race-anfällig).

**Auth als Gate, nicht Querschnitt (V-0):** headless gibt es kein interaktives OAuth — ohne masked Key/
Gateway läuft *gar nichts*. Gehört als Vorbedingung vor alles andere.

**Idempotenz ist eine echte Race-Condition:** zwischen „Poll liest `factory::run`" und „flippt auf
`::running`" kann der nächste Poll dasselbe Issue sehen → Doppel-Trigger. Braucht **zwei** Mechanismen:
GitLab-`resource_group` am Trigger-Job (Scheduled Pipelines überlappen nie) **und** den In-Skript-Check
„läuft schon eins?". Concurrency-Cap = 1 ist also zweiteilig.

**Doktrin-Spannung (in der Umsetzung aufzulösen):** „Eine Task = eine manuell gestartete Session"
(CLAUDE.md / git-workflow) vs. „Pipeline startet die Session". Kein Code-Widerspruch, aber explizit
auflösen, damit adoptierende Teams nicht zwei gegenläufige Regeln lesen.

**Günstig zu unseren Gunsten:** weder `.gate-rules` noch `post-merge-verify` triggern auf `schedule` —
ein neuer Scheduled-Poll-Job ist kollisionsfrei additiv einbaubar.

## Konsequenzen (erwartet, bei Option A)

**Positiv:** L4-Async erreicht; Trigger repo-intern + abschaltbar; verzahnt mit Gateway (#17) und pr-shepherd (#7).
**Negativ / Trade-offs:** Latenz bis Poll-Intervall; Scheduled Pipeline läuft auch leer (billig);
echte Kostenkontrolle hängt am Guard – ohne den ist Async-Trigger bewusst NICHT zu aktivieren.

## Betroffene Stellen (bei Umsetzung)
- `scripts/` – Poll-/Trigger-Skript (z. B. `scripts/factory-poll.sh`)
- `.gitlab-ci.yml` – Scheduled-Pipeline-Job + Trigger des Feature-Laufs
- GitLab – Schedule + Labels (`factory::run` / `::running` / `::done` / `::interrupted` / `::failed`)
- Doku in README/CLAUDE.md + Kosten-Guard prominent
