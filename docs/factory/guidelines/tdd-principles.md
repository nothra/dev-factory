# TDD-Prinzipien

Test-Driven Development ist in dieser Factory kein optionaler Prozess –
es ist die einzige Art, wie Produktionscode entsteht.

---

## Der Zyklus: Red → Green → Refactor

```
RED:      Schreibe einen Test der fehlschlägt
          → Der Test beschreibt das gewünschte Verhalten
          → Er muss aus dem richtigen Grund fehlschlagen

GREEN:    Schreibe das Minimum um den Test grün zu machen
          → Kein "sauberer" Code nötig – erst mal funktionieren
          → Keine anderen Tests kaputt machen

REFACTOR: Bereinige den Code ohne neues Verhalten
          → Tests müssen weiterhin grün bleiben
          → Jetzt Clean Code anwenden
```

Dann: nächster Test. Immer. Starte mit dem simpelsten Happy-Path-Test (Input, erwarteter
Output), danach die Fehlerfälle.

---

## Test-Granularität

**Unit Test** (die meisten Tests): testet eine einzelne Einheit in Isolation, externe
Abhängigkeiten werden gemockt, schnell (< 100 ms pro Test).

**Integration Test** (weniger Tests): testet das Zusammenspiel mehrerer Einheiten gegen echte
Infrastruktur (z. B. echte DB im Test-Container) – langsamer, aber wichtig für Vertrauen.

**Faustregel:** Wenn du mehr als 3 Klassen zusammen testen musst, um ein Verhalten zu testen –
prüfe, ob dein Design zu eng gekoppelt ist.

---

## Was TDD nicht bedeutet

- **Nicht:** Tests nach dem Code schreiben → das ist Test-after-Development, kein TDD
- **Nicht:** alles auf Unit-Ebene testen und alles mocken → Integration Tests sind genauso wichtig
- **Nicht:** 100 % Coverage als Ziel → Coverage ist ein Indikator, kein Qualitätsbeweis

---

## Wenn TDD schwer fällt

Schwer zu testendes Design ist meistens schlechtes Design. Wenn du denkst „das kann ich nicht
testen, bevor ich es baue": Ist die Einheit zu groß (aufteilen)? Braucht sie zu viele
Abhängigkeiten (fehlt Dependency Injection)? Erst das Design prüfen – nicht den Test weglassen.
