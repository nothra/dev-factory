# ADR 002: Technische Umsetzung des ADR-Trigger-Checks im Coding-Agenten

## Status
Proposed

## Datum
2026-06-11

## Kontext

Spec-002 definiert, dass der Coding-Agent bei vier Trigger-Kategorien
(Technologiewahl, Architekturmuster, Schnittstellen-Vertrag, langfristige/irreversible
Konsequenzen) die Implementierung pausieren und den Menschen fragen soll, ob ein ADR
erstellt werden soll.

Die offene Architektur-Frage (OQ-02 aus Spec-002) lautet: **Wie wird diese
Trigger-Erkennung technisch umgesetzt?**

Zwei plausible Ansätze standen zur Diskussion:

1. Die Heuristik ausschließlich in die Agenten-Persona (`coding-agent.md`) schreiben –
   der Agent trägt die gesamte Logik im Prompt-Gedächtnis.
2. Einen expliziten Prüfschritt im `/implement`-Skill vor der eigentlichen
   Implementierungsreihenfolge ergänzen – deterministisch orchestriert, nicht
   allein im Agenten-Verhalten verankert.

Das Kernprinzip der Factory ist entscheidend:
> Deterministische Skripte orchestrieren nicht-deterministische Agenten-Schritte –
> nie umgekehrt. Bash ruft Agenten auf. Agenten rufen keine Bash-Pipelines auf.

Die Frage, ob die Trigger-Erkennung im Skill (kontrollierter Einstiegspunkt) oder
nur in der Persona (reines Verhalten) sitzt, hat Konsequenzen für Deterministik,
Wartbarkeit und Reichweite der Lösung.

---

## Entscheidung

**Option B + A kombiniert (Skill-Prüfschritt als primärer Anker, Persona-Regel als
Sicherheitsnetz).**

- Der `/implement`-Skill erhält einen expliziten **Eingangs-Check als Schritt 0**,
  der die vier Trigger-Kategorien gegen die Task-Datei/Spec prüft, bevor Schritt 1
  ("Task + Spec vollständig lesen") beginnt.
- Die `coding-agent.md`-Persona erhält zusätzlich eine explizite Regel mit den vier
  Trigger-Kategorien und dem Stopp-und-Fragen-Verhalten (AK-11 aus Spec-002).

Die Persona-Regel wirkt als zweite Verteidigungslinie: auch außerhalb des
`/implement`-Skills (freier Chat, andere Skill-Aufrufe) greift das Verhalten.
Die Skill-Ebene ist der primäre, deterministisch verankerte Einstiegspunkt.

---

## Alternativen

### Option A: Nur Persona-Ergänzung (`coding-agent.md`)

Die vier Trigger-Kategorien und das Stopp-und-Fragen-Verhalten werden ausschließlich
in die Persona-Datei des Coding-Agents geschrieben. Kein Eingriff in den Skill.

**Vorteile:**
- Minimale Änderung: eine Datei, ein Ort
- Reichweite: gilt überall, wo die Persona geladen wird – auch im freien Chat
- Kein Änderungsrisiko am `/implement`-Skill-Ablauf

**Nachteile:**
- Widerspricht dem Factory-Kernprinzip: die Kontrolle liegt vollständig beim
  nicht-deterministischen Agenten. Ob und wann er den Check ausführt, ist Modell-
  entscheidung, nicht Skript-Entscheidung.
- Kein kontrollierbarer, sichtbarer Prüfpunkt: kein Audit-Trail, kein deterministischer
  "Schritt 0" der beim Code-Review oder in CI sichtbar wäre.
- Persona-Regeln werden bei längeren Sessions oder großen Kontextfenstern im Gewicht
  gegenüber dem direkten Task-Inhalt zurückgedrängt – Salienz-Problem.
- AK-09 (frühzeitiger Check im `/implement`-Skill) ist damit nicht erfüllbar.

**Fazit:** Zu wenig deterministisch für ein Safety-Gate. Allein nicht ausreichend.

---

### Option B: Eingangs-Check als Schritt 0 im `/implement`-Skill

Der Skill `/implement` bekommt einen expliziten ersten Prüfschritt, der vor dem
eigentlichen Implementierungsablauf liegt. Der Check ist im Skill-Prompt verankert
und damit von der Skill-Ausführung gesteuert – nicht von der freien Entscheidung
des Agenten.

**Vorteile:**
- Entspricht dem Factory-Kernprinzip: deterministischer Ablauf orchestriert
  den nicht-deterministischen Check. Der Prüfschritt ist Teil der Skill-Spezifikation.
- Klar sichtbarer Einstiegspunkt: jeder der den Skill liest, sieht Schritt 0.
- AK-09 und AK-10 (kein False-Positive bei rein funktionalen Tasks) sind direkt
  adressierbar: der Skill-Prompt kann die Heuristik präzise ausformulieren.
- Wartung an einer Stelle: Trigger-Kategorien ändern sich → eine Datei anpassen.

**Nachteile:**
- Greift nur beim Aufruf über `/implement`: freier Chat oder andere Skills
  lösen den Check nicht aus (eingeschränkte Reichweite).
- Kein AK-11 erfüllt, wenn die Persona-Datei nicht separat angepasst wird.

**Fazit:** Stärkste Option für die Deterministik. Allein aber unvollständig bzgl.
AK-11 (Reichweite außerhalb des Skills).

---

### Option C: Check-Skript (`scripts/checks/adr-trigger-check.sh`)

Ein Bash-Skript liest die Task-Datei nach Schlüsselwörtern und gibt einen
strukturierten Hinweis aus, ob ein ADR-Trigger vorliegen könnte.

**Vorteile:**
- Vollständig deterministisch und testbar (Unit-Tests für das Skript möglich)
- Kann in pre-commit oder CI eingebunden werden
- Keine Prompt-Abhängigkeit

**Nachteile:**
- Schlüsselwort-Matching ist oberflächlich: False Positives (jede Erwähnung von
  "API" triggert, obwohl es eine rein interne Hilfsmethode ist) und False Negatives
  (implizite Technologieentscheidungen werden nicht erkannt) sind strukturell
  unvermeidlich.
- Erfordert Pflegaufwand für die Schlüsselwortliste
- Adressiert nur den Eingangs-Check, nicht das kontinuierliche Verhalten während
  der Implementierung (AK-01 bis AK-04 erfordern kontextuelles Urteil)
- Erzeugt eine neue Skript-Abhängigkeit für ein Problem, das semantisches Verständnis
  erfordert – das ist ein Anwendungsfall für das Modell, nicht für grep

**Fazit:** Falsche Schicht für das eigentliche Problem. Abgelehnt.

---

## Begründung

Spec-002 fordert explizit beides: eine Regel in `coding-agent.md` (AK-11) **und**
einen Eingangs-Check im `/implement`-Skill (AK-09). Die Frage war nur, wie das
Gewicht zu verteilen ist.

Option B ist der primäre Anker, weil:

1. **Deterministik:** Der Skill-Prüfschritt ist Teil des definierten Ablaufs – er
   wird ausgeführt weil der Skill ihn vorschreibt, nicht weil das Modell sich
   erinnert. Das entspricht dem Factory-Kernprinzip.

2. **Salienz:** Prompt-Regeln in Persona-Dateien verlieren Gewicht, wenn der
   Kontext groß wird (lange Sessions, große Codebases). Ein expliziter Schritt 0
   im Skill ist unmittelbar im Fokus des Agenten, wenn `/implement` aufgerufen wird.

3. **Wartbarkeit:** Die vier Trigger-Kategorien sind an einem kanonischen Ort im
   Skill definiert. Änderungen an der Spec führen zu einer einzigen Dateianpassung.

Option A (Persona) ist das Sicherheitsnetz für Fälle außerhalb von `/implement`:
Sie erfüllt AK-11 und gibt dem Agenten das Hintergrundwissen, auch im freien Chat
oder bei anderen Skills korrekt zu reagieren. Beide Ebenen zusammen ergänzen sich
ohne sich zu duplizieren: der Skill ist der Kontrollpunkt, die Persona ist das
Verhaltensfundament.

Option C (Bash-Skript) wurde verworfen, da semantisches Kontexturteil – wann ist
eine "API" ein Schnittstellen-Vertrag zwischen Teams und wann eine interne Methode –
kein regex-lösbares Problem ist.

---

## Konsequenzen

**Positiv:**
- Deterministisch verankerte Trigger-Erkennung über den Skill-Einstiegspunkt
- Verhaltens-Sicherheitsnetz durch die Persona-Regel für Kontexte außerhalb `/implement`
- Klar definierter Wartungspunkt: Trigger-Kategorien ändern sich → Skill + Persona
- AK-09, AK-10, AK-11 aus Spec-002 sind vollständig erfüllbar

**Negativ / Trade-offs:**
- Zwei Dateien müssen konsistent gehalten werden (Skill und Persona). Bei einer
  Änderung der Trigger-Kategorien besteht das Risiko, dass nur eine der beiden
  angepasst wird → Drift. Mitigation: Spec-002 als Single Source of Truth für
  die Kategorienliste; beide Dateien referenzieren sie explizit.
- Reichweite außerhalb `/implement` bleibt Model-Best-Effort (nicht deterministisch):
  Wer den Skill nicht nutzt und direkt mit dem Coding-Agenten im Chat arbeitet,
  verlässt sich auf die Persona-Regel. Das ist bewusst akzeptiert.

---

## Implementierungs-Hinweise für den Coding-Agenten

### Änderung 1: `/implement`-Skill (`skills/implement.md` oder äquivalente Datei)

Füge **vor dem ersten Implementierungsschritt** einen expliziten Prüfschritt ein:

```
## Schritt 0 – ADR-Trigger-Check (vor jedem anderen Schritt ausführen)

Prüfe die Task-Datei und Spec auf die vier Trigger-Kategorien aus Spec-002:

| # | Kategorie | Ausgelöst wenn... |
|---|-----------|-------------------|
| 1 | Technologiewahl | Framework, Datenbank, Messaging-System oder externe Bibliothek mit starker Bindewirkung wird eingeführt oder gewechselt |
| 2 | Architekturmuster | Entscheidung zwischen Schichtungsansätzen, CQRS, Event-Driven, Monolith vs. Microservice |
| 3 | Schnittstellen-Vertrag | Neue oder geänderte API zwischen Teams oder Services (REST, gRPC, Event-Schema) |
| 4 | Irreversible Konsequenz | Datenmigration, öffentliche API, Lizenzwahl, Security-Architektur, Persistenz-Strategie |

**Wenn mindestens eine Kategorie zutrifft:**
Stoppe. Benenne die konkrete Entscheidung und die zutreffende Kategorie. Frage:
„Dies ist eine [Kategoriename] (Trigger-Kategorie [N]). Soll ich `/architecture`
aufrufen, bevor ich weitermache?"

**Wenn keine Kategorie zutrifft:**
Fahre direkt mit Schritt 1 fort. Kein Hinweis nötig.

**Wenn du unsicher bist:**
Frage den Menschen explizit: „Ich bin unsicher, ob dies ADR-würdig ist.
Handelt es sich um [Kategorie X]?"

**Wenn der Mensch bestätigt:**
Rufe `/architecture` auf (oder weise den Menschen explizit an, dies zu tun).
Warte, bis eine ADR-Datei existiert. Implementiere den betroffenen Teil nicht
ohne ADR.

**Wenn der Mensch ablehnt:**
Protokolliere in der Task-Datei:
`Nicht-ADR [Datum]: [Entscheidung] – bewusst kein ADR (Begründung: [kurze Begründung])`
Frage in derselben Task-Session nicht erneut für dieselbe Entscheidung nach.
```

### Änderung 2: `docs/factory/agents/coding-agent.md`

Ergänze unter "Deine Regeln" die folgende Regel (ersetzt die bestehende
"Bei Architektur-Zweifel stoppen"-Regel oder ergänzt sie):

```
- **ADR-Trigger aktiv prüfen.** Bei Technologiewahl, Architekturmuster,
  Schnittstellen-Vertrag oder irreversiblen Konsequenzen: Implementierung stoppen,
  Kategorie benennen, Mensch fragen. Bei Bestätigung `/architecture` delegieren –
  nie selbst eine ADR erstellen und nie ohne ADR weitermachen.
  Bei Ablehnung: Nicht-ADR in der Task-Datei protokollieren.
```

### Änderung 3: `docs/factory/agents/architect-agent.md` (optional, AK-12)

Ergänze unter "Leitfragen" oder "Deine Regeln" einen Hinweis:

```
- Du kannst vom Coding-Agenten delegiert werden. In diesem Fall startest du den
  ADR-Entwurf auf Basis der erkannten Trigger-Kategorie (Spec-002) und der
  vorliegenden Task-Datei/Spec.
```

### Konsistenz-Hinweis

Die kanonische Kategorienliste lebt in Spec-002 (`docs/specs/spec-002-adr-auto-detection.md`).
Skill und Persona referenzieren sie inhaltlich – bei Änderungen der Kategorien
beide Dateien synchron aktualisieren.
