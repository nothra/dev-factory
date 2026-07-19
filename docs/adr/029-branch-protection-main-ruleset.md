# ADR 029: Schutz des `main`-Branch via GitHub Repository-Ruleset

## Status

Accepted

## Date

2026-07-19

## Context

GitHub weist darauf hin, dass `main` (Default-Branch) ungeschützt ist. Bisher wird die
Regel „nie direkt auf `main`" nur **lokal** durchgesetzt:

- `scripts/checks/pre-push.sh` blockiert direkte Pushes auf `main`/`master`.
- Die Guardrails in `CLAUDE.md` und `docs/factory/guidelines/git-workflow.md` fordern
  den PR-Workflow ein.

Beides ist **umgehbar**: ein zweiter Clone ohne Hook, `git push --no-verify`, oder ein
CI-Token, das direkt pusht. Der Schutz ist damit Vertrauenssache, nicht fail-closed.

Zwei Rahmenbedingungen der Factory schränken die Lösung ein:

1. **Autonomer Merge.** `/pr-shepherd` mergt über `gh pr merge --auto --squash`. Jede
   Schutzmaßnahme muss diesen unbeaufsichtigten Fluss erhalten – insbesondere darf kein
   menschliches Approval erzwungen werden, sonst hängt jeder autonome Lauf.
2. **Kein garantiert sequenzieller Betrieb.** Zwar gilt Factory-Concurrency = 1 (ADR-008),
   aber der Mensch arbeitet zeitweise **parallel** zu einem laufenden Factory-Lauf am
   Entwicklungs-Workflow. `main` kann also während der laufenden Checks eines PR
   weiterziehen.

## Decision

`main` wird durch ein **Repository-Ruleset** namens `protect-main` geschützt (nicht durch
Classic Branch Protection), `enforcement: active`, **ohne Bypass-Actors** – die Regeln
gelten damit auch für Administratoren (`current_user_can_bypass: never`).

Regeln:

- **Pull Request erforderlich, 0 Approvals** – erzwingt den PR-Weg, erhält aber den
  autonomen Auto-Merge (kein Self-Approve nötig).
- **Merge-Methode ausschließlich `squash`** – nagelt die etablierte PR-Strategie fest.
- **Required Status Checks:** `lint`, `test`, `issue-sync`, `factory-self-test`,
  `pr-closes-issue`.
- **`strict_required_status_checks_policy: false`** (kein „up-to-date"-Zwang).
- **Force-Push und Löschung blockiert** (`non_fast_forward`, `deletion`).

Bewusst **nicht** required: `gate` (Deploy-Gate) und `post-merge-verify`. Beide laufen erst
auf `push`→`main` (nach dem Merge); auf einem PR erzeugt `gate` **keinen** Check und
`post-merge-verify` nur einen `skipped`-Check. Als required würden sie den Merge dauerhaft
auf „Expected – Waiting for status" blockieren.

Die exakte Ruleset-Definition wird **in diesem ADR eingebettet** (reproduzierbarer Record,
siehe [Konfiguration](#konfiguration-reproduzierbar)) und **manuell per `gh api`**
angewendet und verifiziert. Es wird **kein** IaC-Sync-/Drift-Check-Tooling gebaut.

## Alternatives

### A. Durchsetzungs-Mechanismus

**Option A1 – Classic Branch Protection.**
Pro: breit bekannt, simple UI. Contra: älteres Modell, Bypass nur über das grobe
„Include administrators"-Flag, nicht layerbar, GitHub-Roadmap zeigt auf Rulesets.

**Option A2 (gewählt) – Repository Ruleset.**
Pro: modern, granulare Bypass-Actors, mehrere Rulesets layerbar, in Settings → Rules
sichtbar, per JSON/API reproduzierbar. Contra: etwas komplexeres JSON.

### B. Required Reviews

**Option B1 (gewählt) – 0 Approvals.**
Pro: autonomer Auto-Merge bleibt intakt; die fachliche Vier-Augen-Prüfung liefern
`/review` und `/security-review` in der Pipeline. Contra: kein GitHub-seitiger
Freigabezwang.

**Option B2 – ≥ 1 Approval.**
Pro: harte, plattform-erzwungene Freigabe. Contra: bricht den autonomen Merge – GitHub
lässt kein Self-Approve zu, die Factory committet als der einzige Maintainer. Bräuchte
einen zweiten Account/Bot plus eine Pipeline-Pause. Für Solo-/Kleinteam unverhältnismäßig.

### C. `strict` (Branch up-to-date vor Merge)

**Option C1 – `strict: true`.**
Pro: jeder PR wird gegen den exakt aktuellen `main` getestet. Contra: bei parallelem
Factory- **und** Handbetrieb stallt der Auto-Merge, sobald `main` während der Checks
weiterzieht („Update branch" nötig) – genau der reale Betriebsfall hier.

**Option C2 (gewählt) – `strict: false`.**
Pro: Auto-Merge bleibt robust, auch wenn `main` parallel weiterläuft. Contra: ein PR kann
gegen einen leicht veralteten `main` mergen (Risiko semantischer Konflikt). Mitigiert
durch: GitHub blockt **textuelle** Konflikte weiterhin, und der Factory-Flow rebased vor
jedem Push (`git rebase origin/main`), sodass der Branch praktisch frisch ist.

### D. Speicherung der Ruleset-Definition

**Option D1 (gewählt) – im ADR eingebettet, manuell angewandt.**
Pro: reproduzierbarer, versionierter Record ohne zusätzliches Tooling; die Task bleibt
docs-only; YAGNI. Contra: milde Drift-Möglichkeit (jemand editiert das Ruleset in der UI),
ADR kann veralten.

**Option D2 – vollständiges IaC.**
JSON-Datei im Repo + Apply-Skript + CI-Drift-Check (analog `routes-doc-check.sh`).
Pro: versioniert, PR-reviewbar, Drift wird erzwungen. Contra: erhebliche Tooling-
Komplexität für eine Config, die sich ~jährlich ändert; GitHub bietet **kein** natives
„Ruleset aus Repo-Datei anwenden" → alles Eigenbau (Skript, Auth, Sync-Job). Klares
Over-Engineering für eine reversible, selten geänderte Entscheidung.

## Rationale

- **Fail-closed statt Vertrauen:** Server-seitige Durchsetzung schließt die Lücke der rein
  lokalen Hooks. Der `pre-push.sh`-Hook bleibt als **schnelles lokales Feedback** erhalten
  (defense in depth) – doppelte Absicherung, kein Widerspruch.
- **Drei Stellschrauben für Factory-Kompatibilität:** `0 Approvals` + `squash-only` +
  `strict: false` sind exakt die Parameter, die den autonomen Auto-Merge und den parallelen
  Handbetrieb erhalten. Ohne sie würde der Schutz die Factory blockieren.
- **Korrektheits-Kern (verifiziert):** Nur `pull_request`-getriggerte Jobs dürfen required
  sein. `gate`/`post-merge-verify` laufen erst nach dem Merge; belegt an den Check-Runs der
  PRs #147/#150/#152 (dort erscheint `gate` gar nicht, `post-merge-verify` nur `skipped`).
- **YAGNI bei der Speicherung:** Branch-Protection ändert sich praktisch nie – die Kosten
  eines IaC-Sync-Pipelines übersteigen den Nutzen. Reversible Entscheidung → günstig
  halten (`architecture-principles.md` → „Evolutionäre Architektur").

## Consequences

**Positive:**

- Direkte Pushes auf `main`, Force-Pushes und Löschung sind server-seitig fail-closed
  unterbunden – auch für Admins.
- Der `pr-closes-issue`-Pflichtcheck erzwingt die `Closes #<id>`-Guardrail (ADR-013) nun
  auch auf der Plattform, nicht nur per Konvention.
- `gh pr merge --auto --squash` wird sinnvoll: Auto-Merge wartet jetzt real auf grüne
  required Checks, statt sofort zu mergen.
- Die Squash-Strategie ist plattformseitig erzwungen (Merge-/Rebase-Buttons entfallen).

**Negative / Trade-offs:**

- `strict: false` erlaubt einen Merge gegen leicht veralteten `main` (semantisches
  Konfliktrisiko; siehe Mitigation oben).
- Kein plattform-erzwungenes menschliches Approval – die Prüftiefe hängt an den
  Pipeline-Schritten `/review` und `/security-review`.
- Die Ruleset-Definition ist nur im ADR dokumentiert, nicht per Tooling gegen den
  Live-Stand abgeglichen: eine manuelle UI-Änderung erzeugt stille Drift. Gegenmaßnahme:
  Änderungen am Ruleset laufen über einen neuen ADR + den dokumentierten `gh api`-Befehl.

## Konfiguration (reproduzierbar)

Kanonischer Stand des Rulesets (ID `19162920`, Repo `nothra/tch-gastro-services`):

```json
{
  "name": "protect-main",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "bypass_actors": [],
  "rules": [
    { "type": "deletion" },
    { "type": "non_fast_forward" },
    {
      "type": "required_status_checks",
      "parameters": {
        "strict_required_status_checks_policy": false,
        "do_not_enforce_on_create": false,
        "required_status_checks": [
          { "context": "lint" },
          { "context": "test" },
          { "context": "issue-sync" },
          { "context": "factory-self-test" },
          { "context": "pr-closes-issue" }
        ]
      }
    },
    {
      "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false,
        "allowed_merge_methods": ["squash"]
      }
    }
  ]
}
```

Anwenden bzw. aktualisieren (Datei enthält obiges JSON):

```bash
# Neu anlegen:
gh api -X POST repos/nothra/tch-gastro-services/rulesets --input ruleset-main.json
# Bestehendes Ruleset aktualisieren:
gh api -X PUT  repos/nothra/tch-gastro-services/rulesets/19162920 --input ruleset-main.json
```

Verifizieren (Soll-Ist-Abgleich der Kernparameter):

```bash
gh api repos/nothra/tch-gastro-services/rulesets/19162920 --jq \
  '{enforcement, bypass: (.bypass_actors|length),
    checks: [.rules[]|select(.type=="required_status_checks").parameters.required_status_checks[].context],
    strict: (.rules[]|select(.type=="required_status_checks").parameters.strict_required_status_checks_policy),
    merge: (.rules[]|select(.type=="pull_request").parameters.allowed_merge_methods)}'
```

## Bezug zu anderen ADRs

- **ADR-008** (Async-Start/`factory-poll`): der autonome Trigger, dessen Auto-Merge dieses
  Ruleset bewusst nicht bricht.
- **ADR-013** (Issue-pro-Task): der `pr-closes-issue`-Pflichtcheck setzt die
  `Closes #<id>`-Invariante durch.
- **ADR-017** (Prod-Migration im Deploy-Gate): das `gate`/`production`-Promote bleibt
  unberührt – dieses Ruleset zielt nur auf `main` (`~DEFAULT_BRANCH`).
