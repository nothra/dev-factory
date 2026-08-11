# ADR 043: Schwelle für die autonome Issue-Anlage der Review-Skills

## Status

Accepted

> **Schränkt [ADR-018](018-central-issue-seam.md) §5 ein** (#286): Die dort
> festgehaltene Mensch-Entscheidung „`codify`/`review`/`security-review` dürfen autonom Issues
> anlegen" gilt weiter, aber nicht mehr unbedingt – unterhalb einer Schwelle entsteht statt
> eines Issues ein Eintrag in einer Sammeldatei. Der Seam `create_issue`/
> `create_issue_idempotent` selbst bleibt unverändert.

## Datum

2026-08-11

## Kontext

ADR-018 §5 hält fest, dass die drei Skills Out-of-Scope-Funde **autonom** als GitHub-Issue
anlegen dürfen, „statt nur eine Empfehlung in eine Datei zu schreiben". Die Skill-Dokus setzen
das ohne Schwelle um ([`review.md:66`](../../.claude/commands/review.md),
[`security-review.md:62`](../../.claude/commands/security-review.md),
[`codify.md:53`](../../.claude/commands/codify.md)).

Bei sieben Skills pro Task erzeugt das im Schnitt mehr als ein neues Factory-Issue pro Task.
Messung aus #286 (Stand 2026-08-06, `main`): Juli 2026 stehen 38 App-Commits gegen 57
Factory-/CI-Commits; über die letzten 20 Commits 3 gegen 17. Die #268-Kette erzeugte fünf
Folge-Issues zu einem einzigen Git-Hook, von denen drei auf einer in diesem Repo nicht
existierenden Prämisse beruhten und als *not planned* geschlossen wurden.

Die Entscheidung ist architektonisch relevant, weil sie eine in einer ADR festgehaltene
Mensch-Entscheidung einschränkt und weil die Frage „deterministischer Seam oder Agenten-Prosa"
für den neuen Ablage-Pfad genauso gestellt werden muss, wie ADR-018 sie für die Issue-Anlage
gestellt hat. Vorentschieden ist bereits (in `/requirements` mit dem Menschen abgestimmt, siehe
[`spec-286`](../specs/spec-286-kleinfunde-sammeldatei.md)): die Schwellen-Tabelle lebt in
`docs/factory/guidelines/git-workflow.md`, das Eintrags-Schema trägt keine laufende Nummer, und
es entsteht kein Mechanismus gegen „Datei, die niemand liest".

## Decision

**1 · Die autonome Issue-Anlage wird bedingt, nicht abgeschafft.** ADR-018 §5 bleibt gültig für
alle Funde **oberhalb** der Schwelle. Die drei Skills klassifizieren jeden Out-of-Scope-Fund
gegen die Tabelle in `git-workflow.md` §„Zentraler Anlage-Weg (ADR-018)": Merge-Blocker im
aktuellen PR → sofort beheben; echtes Sicherheitsrisiko → Issue über den Seam; funktionaler
Defekt mit reproduzierbarem Auslöser → Issue; alles andere → Sammeldatei.

**2 · Die Schwelle ist einseitig fail-safe.** Bei nicht eindeutiger Zuordnung gilt „im Zweifel
Issue". Ein zu großzügig gezogener Sammeldatei-Pfad ließe echte Sicherheitsfunde in einer
Textdatei verschwinden – der teuerste denkbare Fehler dieser Entscheidung. Der umgekehrte
Fehler (ein Nitpick wird Issue) kostet nur, was heute ohnehin der Normalfall ist.

**3 · Kein Seam für die Sammeldatei.** Der Eintrag entsteht als direkter `Edit` des Agenten
nach dem in `docs/factory/kleinfunde.md` selbst dokumentierten Schema – **kein** neues
`scripts/lib/add-kleinfund.sh` analog zum Issue-Seam. Begründung unten.

**4 · Die Datei trägt ihren eigenen Schema-Kontrakt.** `kleinfunde.md` dokumentiert im Kopf,
welche Felder ein Eintrag hat (Wo mit `Datei:Zeile` + Verifikationsdatum, Was, Fix mit
Aufwandsschätzung, Herkunft). Die drei Skill-Dokus **verweisen** darauf und wiederholen weder
Schema noch Schwellen-Tabelle. Ein Ort je Regel, drei dünne Referenzen.

**5 · Die Durchsetzungsebene ist ehrlich benannt: Prompt, nicht Laufzeit.** Skills sind
Anweisungstexte, keine ausführbare Logik – es gibt keinen Punkt, an dem die Klassifikation
technisch erzwungen werden könnte. Absicherbar ist nur, dass die Anweisung vorhanden **und**
die alte unbedingte Formulierung verschwunden ist. Genau das leistet der Doku-Guard in
`scripts/checks/tests/run-tests.sh` (Präsenz + Abwesenheit, Anker an der echten
Anweisungszeile, Rotfärbung per Mutation belegt).

## Alternatives

### Frage „Ablage-Mechanismus": Option A – Agenten-`Edit` nach dokumentiertem Schema (gewählt)

**Vorteile:** Kein neuer Code, keine neue Testfläche – passt zum Ziel der Task, Factory-Apparat
zu reduzieren, statt ihn zu vermehren. Der Wert eines Eintrags liegt in der Fix-Skizze, also in
formulierter Prosa mit Markdown-Links; die schreibt ein Agent besser als eine
Shell-Argumentliste. Die Duplikat-Frage bleibt dort, wo sie entscheidbar ist (siehe Begründung).
`Edit(docs/**)` ist in `.claude/settings.json:58` bereits freigegeben – kein Rechte-Nachzug.

**Nachteile:** Schema-Einhaltung und Duplikat-Vermeidung hängen am Prompt. Die Datei kann formal
driften; auffallen würde das erst beim Lesen.

### Frage „Ablage-Mechanismus": Option B – Seam `scripts/lib/add-kleinfund.sh` (verworfen)

Symmetrisch zu ADR-018: `add_kleinfund <titel> <wo> <was> <fix> <herkunft>`, sourcebar, mit
deterministischer Duplikat-Prüfung und erzwungenem Schema.

**Vorteile:** Ein Aufrufmuster für beide Zweige der Schwelle (`create_issue_idempotent` oben,
`add_kleinfund` unten). Schema erzwungen statt erbeten. Echte Verhaltenstests mit Fixture-Datei
statt eines Doku-Greps – die stärkere Testebene. Entspricht dem Kernprinzip „deterministische
Skripte orchestrieren nicht-deterministische Agenten-Schritte".

**Nachteile, die den Ausschlag geben:** Der Duplikat-Schlüssel ist hier **nicht
maschinenentscheidbar**. `create_issue_idempotent` kann auf einen exakten offenen Issue-Titel
prüfen; ein Kleinfund ist über `Datei:Zeile` identifiziert, und die Datei sagt in ihrem eigenen
Kopf, dass Zeilennummern driften. Ein Grep auf `Datei:Zeile` verfehlt das gedriftete Duplikat,
ein Grep auf den bloßen Dateipfad über-matcht – die Einträge 1 und 2 der bestehenden Datei
betreffen beide `install-hooks.sh` und sind trotzdem verschiedene Funde. Der Seam wäre also
gerade in seiner Kernfunktion schwächer als das Urteil eines lesenden Agenten. Dazu: mehrzeilige
Markdown-Prosa mit Links durch Shell-Argumente zu fädeln ist fehleranfällig, und das Skript
plus Tests wäre neuer Factory-Apparat in einer Task, deren Zweck dessen Reduktion ist (YAGNI).

### Frage „ADR-Form": Option A – eigene ADR, die ADR-018 §5 einschränkt (gewählt)

**Vorteile:** Folgt dem etablierten Muster des Repos – ADR-040 erweitert ADR-018 ebenfalls über
eine eigene ADR plus Hinweis im Status-Block von ADR-018. Die Begründung (Messung, #268-Kette)
bekommt einen eigenen Ort, statt einen fremden ADR-Text zu überwuchern. Die ursprüngliche
Entscheidung bleibt als Historie lesbar.

**Nachteile:** Wer nur ADR-018 liest, braucht den Statusblock-Verweis, um die Einschränkung zu
sehen. Dritte ADR im Umfeld desselben Seams.

### Frage „ADR-Form": Option B – ADR-018 §5 direkt umschreiben (verworfen)

**Vorteile:** Eine Stelle, kein Verweis-Hopping.

**Nachteile:** Überschreibt eine dokumentierte Mensch-Entscheidung samt Datum; ADRs sind
Entscheidungs-Historie, keine laufend gepflegte Prozess-Doku. Die Messung, die die Einschränkung
trägt, hätte in ADR-018 keinen sinnvollen Platz.

### Frage „Ort der Schwellen-Tabelle": in `git-workflow.md`, nicht in dieser ADR (gewählt)

In `/requirements` entschieden, hier nur festgehalten mit Begründung: `git-workflow.md` trägt
bereits Anlage-Weg und Label-Konvention kanonisch, und alle drei Skill-Dokus verlinken schon
heute dorthin. Eine ADR ist der falsche Ort für eine Regel, die im Betrieb nachgeschlagen wird –
sie dokumentiert, **dass** und **warum** entschieden wurde, nicht die operative Tabelle.
Verworfen wurden: Tabelle in `kleinfunde.md` (Prozessregel in einer laufend mutierenden Liste)
und in `OPERATING.md` (dritter Verweis-Ort neben `git-workflow.md` und ADR-018).

## Begründung

Die tragende Einsicht ist der Unterschied im **Duplikat-Schlüssel**: Was ADR-018 zu Recht in
einen Seam gezogen hat – wiederholte `gh`-Aufrufe mit Label-Flags, Fallback-Logik und exakter
Titel-Prüfung –, existiert hier nicht. Es gibt kein externes System, keine Flags, keine Labels,
und die Identität eines Eintrags ist per Konstruktion unscharf. Ein Seam würde Determinismus an
der einzigen Stelle versprechen, an der er nicht einlösbar ist, und dafür genau die Sorte
Apparat hinzufügen, deren Wachstum diese Task bremsen soll. Das Kernprinzip
„Skripte orchestrieren Agenten" adressiert die **Orchestrierung** von Schritten, nicht jeden
Schreibvorgang innerhalb eines Schritts.

Die Schwelle selbst ist die ganze Wirkung dieser Entscheidung. Deshalb ist sie asymmetrisch
gebaut: die Zeile „echtes Sicherheitsrisiko → weiter Issue" und die Zweifelsregel sind nicht
verhandelbar, und der Nachweis dafür steht in den Akzeptanzkriterien, nicht in der Prosa.

Die Entscheidung ist **reversibel**: Fällt die Erzeugungsrate nicht wie erwartet, oder driftet
die Sammeldatei formal auseinander, kann Option B nachgezogen werden, ohne dass die dann
vorhandenen Einträge oder die Schwellen-Tabelle sich ändern müssten.

## Konsequenzen

**Positiv**

- Die Erzeugungsrate neuer Factory-Issues sinkt auf die Klassen, die einen Pipeline-Lauf über
  sieben Skills tatsächlich rechtfertigen.
- Funde gehen nicht verloren: unterhalb der Schwelle sind sie in `kleinfunde.md` verzeichnet,
  mit verifizierter Fundstelle und Fix-Skizze, und werden mitgenommen, wenn die betroffene
  Datei ohnehin angefasst wird.
- Ein Ort je Regel: Schwelle in `git-workflow.md`, Schema in `kleinfunde.md`, Begründung hier.

**Negativ / bewusst in Kauf genommen**

- **Die Klassifikation ist prompt-durchgesetzt, nicht laufzeit-erzwungen.** Ein Agent, der die
  Anweisung ignoriert, legt weiter ein Issue an (oder umgekehrt). Der Doku-Guard sichert nur die
  Anweisung selbst gegen Regression, nicht deren Befolgung. Diese Grenze ist strukturell, nicht
  behebbar, solange Skills Prompts sind.
- **`kleinfunde.md` hat keinen Leser-Zwang.** Bewusst kein Zähl-Check und keine
  Erinnerungszeile (#286 „Nicht inbegriffen"). Wächst die Datei ungelesen, ist das der
  vorhersehbare Preis; das Gegenmittel wäre neuer Apparat.
- **Formale Drift der Datei ist möglich**, weil das Schema nicht erzwungen wird.
- Der Statusblock von ADR-018 bekommt einen zweiten Erweiterungs-Hinweis (nach ADR-040) – wer
  ADR-018 isoliert liest, muss beiden folgen.

**Betroffene Artefakte**

- `docs/factory/guidelines/git-workflow.md` – Schwellen-Tabelle + Zweifelsregel als neuer
  Unterabschnitt; die bestehende Prosa bei `:157-158` („ebenso legen die Skills … autonom
  darüber an") auf den bedingten Stand nachziehen.
- `docs/adr/018-central-issue-seam.md` – Hinweis im Statusblock, §5 auf diese ADR verweisen.
- `.claude/commands/{review,security-review,codify}.md` – Klassifikations-Anweisung **vor** dem
  `create_issue_idempotent`-Block, Verweis auf Schwelle und Sammeldatei. Änderung läuft über den
  Patch-Workflow (`Edit(.claude/**)` steht in `settings.json:72` auf `deny`).
- `docs/factory/kleinfunde.md` – Schema-Kontrakt im Kopf, Einträge ohne laufende Nummer.
- `scripts/checks/tests/run-tests.sh` – Doku-Guard (Präsenz + Abwesenheit + Verweis-Ziel).
- **Unberührt:** `scripts/lib/create-issue.sh` – der Seam ändert weder Signatur noch Verhalten.
