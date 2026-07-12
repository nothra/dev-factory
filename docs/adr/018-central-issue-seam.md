# ADR 018: Zentraler Issue-Seam mit Label-Funktion (`create-issue`)

## Status
Accepted

## Datum
2026-07-12

## Kontext

Issues entstehen an mehreren Stellen der Factory, jede mit eigener `gh issue create`-Logik:

- `scripts/start-work.sh` legt seit #80 ein aus dem Branch-Typ abgeleitetes **Art-Label** an,
  mit fail-open-Fallback (Retry ohne Label + Warnung, falls das Label im Repo fehlt).
- `scripts/sync-issues.sh --create` legt fehlende Issues **ohne jedes Label** an
  (`sync-issues.sh:108`) → verletzt still die „genau ein Art-Label"-Konvention aus
  `git-workflow.md`.

Zwei Probleme: **(1) Duplikation** der Anlage-Logik, **(2) uneinheitliche Label-Vergabe** –
**Aspekt-Labels** (`security`/`tech-debt`/`test`) werden nirgends angeboten, obwohl gerade
`codify`/`review`/`security-review` begründete Aspekt-Empfehlungen treffen.

Diese Entscheidung ist nötig, weil zwei Fragen der Spec (`docs/specs/spec-82-issue-seam.md`)
langfristig wirken: **wo** die Issue-Anlage als Seam liegt und **ob der Seam Labels validiert**.
Die Frage „dürfen Skills autonom Issues anlegen?" wurde vom Menschen bereits mit **Ja**
entschieden (2026-07-12) und wird hier nur festgehalten.

## Decision

**1 · Ein zentraler Seam.** Neue sourcebare Bibliothek `scripts/lib/create-issue.sh` mit einer
Funktion:

```
create_issue <title> <body> <art-label> [aspekt-csv]   # → Issue-Nummer auf stdout, Exit 0
```

Jede Issue-Anlage läuft hierüber. Die bestehenden Aufrufer (`start-work.sh`,
`sync-issues.sh --create`) entfernen ihr eigenes `gh issue create` und rufen `create_issue`.
Neu: `scripts/lib/` als Ort für sourcebare Shell-Bibliotheken.

**2 · Interface-Kontrakt (Testbarkeit):** Nutzdaten (die Issue-Nummer) gehen **ausschließlich
auf stdout**, alle Diagnostik/Warnungen auf **stderr**. So bleibt `num=$(create_issue …)` sauber.
Exit ≠ 0 nur, wenn **gar kein Issue** entsteht (fail-closed auf die Anlage). `gh` bleibt über
einen Stub testbar (Muster `GH_LOG` aus `run-tests.sh`, #80).

**3 · Labels: fail-open, ohne harte Validierung.** Der Seam prüft übergebene Labels **nicht**
gegen eine erlaubte Menge. Er reicht Art- + Aspekt-Labels an `gh` durch und **degradiert**
robust, falls ein Label im Repo fehlt:

```
create mit  Art + allen Aspekt-Labels
  └─ scheitert? → create nur mit Art-Label            (Aspekte fallen weg, Warnung nennt sie)
       └─ scheitert? → create ohne Label              (Warnung; Anlage darf nicht scheitern)
```

Das **verpflichtende Art-Label** wird also nie durch ein fehlendes Aspekt-Label mitgerissen.
Die kanonische Label-Liste bleibt allein in `git-workflow.md` → „GitHub-Labels"; der Seam
dupliziert sie nicht.

**Eine Ausnahme – der reservierte `factory::`-Präfix (Security-Review #82, H-1):** Der Seam
**verwirft** übergebene Labels mit `factory::`-Präfix (Art wie Aspekt, Warnung auf stderr).
Das ist bewusst **keine** Taxonomie-Allowlist (die bleibt abgelehnt, s. o.), sondern eine
schmale **Denylist eines einzigen, privilegienrelevanten Präfix**: `factory::run`/`::running`/
`::done`/… steuern die autonome Pipeline (ADR-008) und werden **ausschließlich** von ihr via
`gh issue edit` gesetzt – nie über den allgemeinen Anlage-Seam. Da neu auch Skills autonom über
den Seam anlegen (§5), verhindert der Guard, dass ein Label aus versehentlich untrusted Inhalt
je einen ungewollten Pipeline-Lauf triggert. Der `factory::`-Präfix ist stabil und in
`git-workflow.md` bereits als „nicht frei vergeben" dokumentiert → kein Drift-Risiko.

**4 · Repo-Bezug ohne neue Duplikation.** Der Seam leitet den Repo-Slug **nicht** selbst ab
(bewusst außerhalb des Scopes), sondern liest ihn aus der Umgebung (`FACTORY_REPO`, sonst der
schon vom Aufrufer gesetzte `REPO`); ist nichts gesetzt, überlässt er `gh` die Auto-Erkennung
aus dem Arbeitsverzeichnis. Die Slug-Ableitung selbst zu konsolidieren ist ein eigener Task.

**5 · Skills legen autonom an (Mensch-Entscheidung, hier dokumentiert).**
`codify`/`review`/`security-review` dürfen bei einem Fund `create_issue` **autonom** aufrufen
und Art- + Aspekt-Labels mitgeben, statt nur eine Empfehlung in eine Datei zu schreiben. Die
jeweilige Skill-Doku wird entsprechend angewiesen.

## Alternatives

### Frage „Seam-Ort": Option A – sourcebare Lib `scripts/lib/create-issue.sh` (gewählt)
**Pros:** DRY; ein Ort für Label-/Fallback-Logik; über `source` unit-testbar mit gh-Stub;
klarer Funktions-Kontrakt (stdout=Nummer). **Cons:** neues Verzeichnis `scripts/lib/`;
Aufrufer müssen die Lib sourcen.

### Frage „Seam-Ort": Option B – eigenständiges Skript `scripts/create-issue.sh` (Subprozess)
**Pros:** keine Source-Kopplung, per `$(bash create-issue.sh …)` aufrufbar.
**Cons:** Rückgabe nur über stdout/Exit; Env-Weitergabe umständlicher; ein Prozess-Fork je
Aufruf; schlechter testbar als eine gesourcte Funktion.

### Frage 2 „Label-Validierung": Option A – fail-open pass-through (gewählt)
**Pros:** keine Duplikation der kanonischen Label-Liste (die liegt in `git-workflow.md`; eine
Kopie im Seam wäre genau der bekannte „kanonische Quellen driften"-Stolperstein); der Seam
bleibt eine dünne, robuste Hülle; entspricht dem etablierten #80-Verhalten (fail-open aufs
Label). **Cons:** ein Tippfehler im Label wird nicht hart abgelehnt, sondern nur als Warnung
sichtbar (das Issue entsteht trotzdem, ggf. ohne das falsche Label).

### Frage 2 „Label-Validierung": Option B – fail-closed gegen Allowlist
**Pros:** „gates over trust" – falsche Labels werden hart abgelehnt. **Cons:** dupliziert die
kanonische Label-Liste in Shell (Drift-Risiko, bekannter Stolperstein); fail-closed auf einem
kosmetischen Wert (Label) riskiert, die Issue-Anlage selbst zu blockieren – das wäre
schlimmer als ein fehlendes Aspekt-Label.

### Frage 2 „Label-Validierung": Option C – Soft-Warn gegen bekannte Menge (verworfen)
Mittelweg: nicht blockieren, aber warnen, wenn ein Label nicht in der bekannten Menge liegt.
**Cons:** braucht trotzdem eine Kopie/Referenz der Liste im Seam → dieselbe Drift-Gefahr wie B,
ohne den Schutz von B. Der Nutzen (Warnung) wird bereits durch die fail-open-Warnung bei
`gh`-Ablehnung erreicht.

## Begründung

Option A/A treffen die YAGNI-Linie der Factory: ein dünner, gut testbarer Seam, der genau die
schon bewährte #80-Logik zentralisiert und um Aspekt-Labels erweitert. Die Entscheidung gegen
harte Label-Validierung folgt zwei bestehenden Prinzipien direkt: „kanonische Quellen immer
referenzieren" (keine zweite Label-Liste) und die Guardrail-Faustregel „fail-closed nur dort,
wo es die Korrektheit schützt" – die Issue-*Anlage* ist wichtiger als die Label-*Kosmetik*,
darum fail-open aufs Label, fail-closed nur auf das Entstehen des Issues.

## Consequences

**Positive:**
- Eine Stelle für Issue-Anlage + Label-Politik; `sync-issues.sh` erzeugt keine label-losen
  Issues mehr (Schema-Verletzung behoben).
- Aspekt-Labels (Art + n Aspekt) sind einheitlich verfügbar – Voraussetzung dafür, dass
  `codify`/`review`/`security-review` klassifizierte Issues autonom anlegen.
- Klarer stdout/stderr-Kontrakt → mit gh-Stub deterministisch testbar.
- Das verpflichtende Art-Label überlebt ein fehlendes Aspekt-Label (gestufte Degradation).

**Negative / Trade-offs:**
- Neues Verzeichnis `scripts/lib/`; Aufrufer koppeln per `source`.
- Kein harter Schutz gegen Label-Tippfehler (bewusst; nur Warnung).
- Autonome Issue-Anlage durch Skills kann – falsch angewendet – Issue-Rauschen erzeugen; die
  Skill-Doku muss die Konvention (genau ein Art-Label) klar anweisen.

## Betroffene Artefakte
- `scripts/lib/create-issue.sh` (neu)
- `scripts/start-work.sh` (nutzt Seam; optional `--labels`/`FACTORY_ASPECT_LABELS` für Aspekte)
- `scripts/sync-issues.sh` (nutzt Seam; Art-Label `enhancement` als Default)
- `scripts/checks/tests/run-tests.sh` (Seam-Tests: Art, Aspekt-CSV, fehlendes Label, stdout=Nummer)
- Skill-Dateien `codify`/`review`/`security-review` (Anweisung: `create_issue` mit Labels aufrufen)
- `docs/factory/guidelines/git-workflow.md` (Verweis auf den Seam als kanonischen Anlage-Weg)
