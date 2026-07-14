# Testing Standards

Regeln für Test-Qualität und Test-Aufbau in diesem Projekt.

---

## Test-Aufbau: Arrange-Act-Assert

```
// ARRANGE: Testdaten und Abhängigkeiten aufbauen
User user = new User("test@example.com", Role.ADMIN);
UserService service = new UserService(mockRepository);

// ACT: Die zu testende Aktion ausführen
Optional<User> result = service.findByEmail("test@example.com");

// ASSERT: Ergebnis prüfen
assertThat(result).isPresent();
assertThat(result.get().getRole()).isEqualTo(Role.ADMIN);
```

Keine Logik zwischen Arrange und Act. Kein Assert vor dem Act.

**Gegen einen erwarteten Wert prüfen, nicht gegen das Objekt-under-Test selbst.**
Eine Assertion, die den Soll-Wert aus derselben Quelle liest, die die Funktion verarbeitet,
ist (fast) tautologisch – sie kann nur fehlschlagen, wenn die Testdaten selbst inkonsistent
sind, und belegt das Verhalten nicht:
```ts
// Schlecht: liest den Soll-Wert aus dem Objekt, das getestet wird
expect(firstIssueMessage(result.error)).toBe(result.error.issues[0].message);

// Gut: fixe, unabhängig erwartete Meldung (hier via deterministische Custom-Message)
const result = z.object({ name: z.string({ error: "Name fehlt" }) }).safeParse({ name: 123 });
expect(firstIssueMessage(result.error)).toBe("Name fehlt");
```
Faustregel: Der erwartete Wert im `toBe(...)` ist ein **Literal** (oder unabhängig
konstruiert), nie ein erneuter Zugriff auf das Ergebnis/Argument der Act-Zeile.

---

## Test-Namen

Format: `should_[erwartetes Ergebnis]_when_[Bedingung]`

Beispiele:
- `should_returnEmpty_when_userNotFound`
- `should_throwException_when_emailIsInvalid`
- `should_calculateCorrectTotal_when_discountApplied`

Alternativ (Behavior-Style): `given_[Zustand]_when_[Aktion]_then_[Ergebnis]`

---

## Was testen? Was nicht?

**Testen:**
- Business Logic (immer)
- Edge Cases und Boundary Values
- Fehlerfälle und Error-Handling
- Public API / Public Methods

**Nicht testen:**
- Private Methoden direkt (über Public API testen)
- Getter/Setter ohne Logik
- Framework-Code (Spring, Hibernate etc.) – das ist getestet
- Konfigurationsklassen ohne Logik

---

## Mocking-Regeln

**Mocken: JA**
- Externe Systeme: HTTP-Clients, Message Queues, externe APIs
- Infrastruktur: Datenbank (für Unit Tests), Filesystem, Zeit (`Clock`)

**Mocken: NEIN**
- Interne Klassen derselben Schicht
- Domain-Objekte (Value Objects, Entities)
- Einfache Utilities ohne Side Effects

**Faustregel:** Wenn du interne Klassen mocks – überprüfe dein Design.

---

## Test-Isolation

- Jeder Test ist unabhängig – keine Abhängigkeit von Test-Reihenfolge
- Keine geteilten mutable State zwischen Tests
- Test-Daten werden pro Test aufgebaut, nicht geteilt
- Bei Datenbank-Tests: Rollback nach jedem Test oder Test-Container

---

## Flaky Tests: Zero Tolerance

Flaky Tests (manchmal grün, manchmal rot) sind sofort zu beheben oder zu löschen:
- Kein `sleep()` in Tests – stattdessen deterministische Mocks
- Kein `new Date()` ohne `Clock`-Mock
- Kein Verlassen auf Netzwerk-Verbindungen in Unit Tests
- Keine Test-Reihenfolge-Abhängigkeiten

---

## Coverage-Anforderungen

- Minimum: siehe `PROJECT-CONTEXT.md`
- Coverage ist ein Hinweis auf ungetestete Pfade – kein Qualitätsbeweis
- Lieber 80% Coverage mit guten Tests als 100% mit sinnlosen Tests
- Neuer Code: 100% coverage erwartet (wird im Review geprüft)
