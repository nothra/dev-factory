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
