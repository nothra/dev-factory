# Testing Standards

Regeln für Test-Qualität und Test-Aufbau in diesem Projekt.

> **Ausgelagert nach [`lessons/testing.md`](../lessons/testing.md)** (ADR-047, #319): die drei
> `/codify`-artigen Einträge „Exhaustiveness-Guards (`never`-Check)", „Mock-Default mit leerem
> Array verdeckt Mapping-Code" und „Coverage-Ausgabe nur in ignorierte Pfade (ADR-040)".
> Sie gelten unverändert weiter; „Laden bei" steht kanonisch im Lessons-Index
> (`PROJECT-CONTEXT.md` → `lessons/testing.md`), nicht hier. Die ADR-040-Regel selbst bleibt
> zusätzlich als Kurzregel unter „Coverage-Anforderungen" in dieser Datei – nur ihre Begründung
> und der Vorfall stehen in der Lesson.

---

## Test-Aufbau: Arrange-Act-Assert

**ARRANGE** (Testdaten + Abhängigkeiten aufbauen) → **ACT** (die zu testende Aktion ausführen)
→ **ASSERT** (Ergebnis prüfen). Keine Logik zwischen Arrange und Act. Kein Assert vor dem Act.

**Gegen einen erwarteten Wert prüfen, nicht gegen das Objekt-under-Test selbst.** Eine Assertion,
die den Soll-Wert aus derselben Quelle liest, die die Funktion verarbeitet, ist (fast)
tautologisch – sie kann nur fehlschlagen, wenn die Testdaten selbst inkonsistent sind, und belegt
das Verhalten nicht:

```ts
// Schlecht: liest den Soll-Wert aus dem Objekt, das getestet wird
expect(firstIssueMessage(result.error)).toBe(result.error.issues[0].message);

// Gut: fixe, unabhängig erwartete Meldung – das Literal stammt aus der Custom-Message
const result = z.object({ name: z.string({ error: "Name fehlt" }) }).safeParse({ name: 123 });
expect(firstIssueMessage(result.error)).toBe("Name fehlt");
```

Faustregel: Der erwartete Wert im `toBe(...)` ist ein **Literal** (oder unabhängig konstruiert),
nie ein erneuter Zugriff auf das Ergebnis/Argument der Act-Zeile.

---

## Test-Namen

Format: `should_[erwartetes Ergebnis]_when_[Bedingung]` – z. B. `should_returnEmpty_when_userNotFound`,
`should_throwException_when_emailIsInvalid`. Alternativ (Behavior-Style):
`given_[Zustand]_when_[Aktion]_then_[Ergebnis]`.

---

## Was testen? Was nicht?

**Testen:** Business Logic (immer), Edge Cases und Boundary Values, Fehlerfälle und
Error-Handling, Public API / Public Methods.

**Nicht testen:** private Methoden direkt (über die Public API testen), Getter/Setter ohne Logik,
Framework-Code (ist bereits getestet), Konfigurationsklassen ohne Logik.

---

## Mocking-Regeln

**Mocken: JA** – externe Systeme (HTTP-Clients, Message Queues, externe APIs) und Infrastruktur
(Datenbank für Unit Tests, Filesystem, Zeit/`Clock`).

**Mocken: NEIN** – interne Klassen derselben Schicht, Domain-Objekte (Value Objects, Entities),
einfache Utilities ohne Side Effects.

**Faustregel:** Wenn du interne Klassen mockst – überprüfe dein Design.

---

## Test-Isolation

- Jeder Test ist unabhängig – keine Abhängigkeit von der Test-Reihenfolge
- Kein geteilter mutable State zwischen Tests
- Test-Daten werden pro Test aufgebaut, nicht geteilt
- Bei Datenbank-Tests: Rollback nach jedem Test oder Test-Container

---

## Flaky Tests: Zero Tolerance

Flaky Tests (manchmal grün, manchmal rot) sind sofort zu beheben oder zu löschen: kein `sleep()`
in Tests (stattdessen deterministische Mocks), kein `new Date()` ohne `Clock`-Mock, kein
Verlassen auf Netzwerk-Verbindungen in Unit Tests, keine Test-Reihenfolge-Abhängigkeiten.

---

## Coverage-Anforderungen

- Minimum: siehe `PROJECT-CONTEXT.md`. **Neuer Code: 100 % Coverage erwartet** (wird im Review geprüft)
- Coverage ist ein Hinweis auf ungetestete Pfade – kein Qualitätsbeweis. Lieber 80 % mit guten
  Tests als 100 % mit sinnlosen Tests
- **Coverage-Ausgabe nur in `.gitignore`-abgedeckte Pfade** schreiben – `coverage/` (Default von
  `pnpm test:coverage`) bzw. `.coverage-tmp<id>/` für isolierte Läufe, nie ein Ad-hoc-Pfad im
  Projektbaum (ADR-040). Begründung + Vorfall: [`lessons/testing.md`](../lessons/testing.md)
