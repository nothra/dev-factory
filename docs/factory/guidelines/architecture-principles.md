# Architektur-Prinzipien

Universelle Grundsätze, die für alle Projekte gelten.
Projektspezifische Entscheidungen werden in `docs/adr/` dokumentiert.

---

## Kernprinzipien

### Separation of Concerns
Jede Schicht/Komponente hat eine klar definierte Verantwortung.
- Business Logic gehört in die Domain/Service-Schicht
- Datenbankzugriff gehört in die Persistence-Schicht
- HTTP-Details gehören in die Controller/Adapter-Schicht
- Kein Mixing: kein SQL in Controllern, keine HTTP-Details in Services

### Dependency Rule (Clean Architecture)
Abhängigkeiten zeigen immer nach innen (zur Domain):
```
Adapter/UI → Anwendungsschicht → Domain
             ↑
         Infrastruktur
```
Die Domain kennt keine Infrastruktur-Details.
Interfaces definiert die Domain, implementiert die Infrastruktur.

### Abhängigkeiten explizit machen (Dependency Injection)
- Abhängigkeiten werden injiziert, nicht selbst erzeugt
- `new` in Business Logic ist ein Warnsignal
- Erleichtert Testbarkeit massiv

---

## SOLID-Kurzfassung

| Prinzip | Bedeutung | Häufigster Verstoß |
|---------|-----------|-------------------|
| **S**RP | Eine Klasse, eine Verantwortung | God Classes |
| **O**CP | Offen für Erweiterung, geschlossen für Änderung | Switch/Case statt Polymorphismus |
| **L**SP | Unterklassen ersetzen Basisklassen | Vererbung für Code-Reuse (falsch) |
| **I**SP | Kleine, fokussierte Interfaces | Dicke Interfaces mit vielen Methoden |
| **D**IP | Abhängigkeit von Abstraktionen | Direkte Instanziierung von Implementierungen |

---

## Fehlerbehandlung

- **Fehler sind Teil des Designs** – nicht nachträglicher Gedanke
- Fehler auf der richtigen Ebene behandeln: nicht überall fangen, auf der richtigen Ebene entscheiden
- Exceptions für außergewöhnliche Zustände, nicht für Control Flow
- Fachliche Fehler als explizite Return-Typen (Result, Optional, Either)
- Niemals leere Catch-Blöcke: `catch (Exception e) {}`

---

## API-Design

- APIs sind Verträge – Breaking Changes erfordern Versionierung
- Inputs validieren an der System-Grenze (nicht tief im Core)
- Fehlermeldungen sind für Konsumenten, nicht für Entwickler
- Idempotenz wo möglich (besonders bei State-ändernden Operationen)

---

## Performance & Skalierung

- Premature Optimization vermeiden (zuerst korrekt, dann schnell)
- N+1-Queries aktiv verhindern (besonders bei ORM-Nutzung)
- Caching ist eine architektonische Entscheidung → ADR
- Asynchrone Verarbeitung hat Komplexitätskosten → bewusst einsetzen

---

## Evolutionäre Architektur

- Reversible Entscheidungen: schnell treffen, günstig zu ändern
- Irreversible Entscheidungen: langsam, mit ADR, mit Alternativen
- Faustregel: Je größer die Auswirkung einer Entscheidung, desto mehr Zeit ins Design
- Architektur emergiert – kein Big Design Up Front für unbekannte Anforderungen
