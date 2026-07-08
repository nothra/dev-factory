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

Dann: nächster Test. Immer.

---

## Warum Test-First?

- **Design:** Tests zwingen dich, aus Nutzerperspektive zu denken.
  Code der schwer zu testen ist, ist meistens schlecht designed.
- **Sicherheit:** Du weißt sofort wenn etwas kaputt geht.
- **Dokumentation:** Tests zeigen, wie der Code verwendet werden soll.
- **Fokus:** Du implementierst nur was wirklich gebraucht wird.

---

## Der erste Test

Bevor du Code schreibst, beantworte:
1. Was ist das einfachste Verhalten, das ich testen kann?
2. Was ist der Input? Was ist der erwartete Output?
3. Welcher Fehlerfall sollte als erstes behandelt werden?

Starte mit dem simpelsten Happy-Path-Test.

---

## Test-Granularität

**Unit Test** (die meisten Tests):
- Testet eine einzelne Einheit in Isolation
- Externe Abhängigkeiten werden gemockt
- Schnell (< 100ms pro Test)

**Integration Test** (weniger Tests):
- Testet das Zusammenspiel mehrerer Einheiten
- Echte Infrastruktur (z.B. echte DB im Test-Container)
- Langsamer, aber wichtig für Vertrauen

**Faustregel:** Wenn du mehr als 3 Klassen zusammen testen musst um
ein Verhalten zu testen – prüfe ob dein Design zu eng gekoppelt ist.

---

## Was TDD nicht bedeutet

- **Nicht:** "Ich schreibe Tests nach dem Code"
  → Das ist Test-after-Development, kein TDD
- **Nicht:** "Ich teste alles auf Unit-Ebene und mocke alles"
  → Integration Tests sind genauso wichtig
- **Nicht:** "100% Coverage ist das Ziel"
  → Coverage ist ein Indikator, kein Qualitätsbeweis

---

## Wenn TDD schwer fällt

Wenn du denkst "das kann ich nicht testen bevor ich es baue":
- Warum ist es schwer zu testen? → Design-Problem?
- Ist die Einheit zu groß? → Aufteilen?
- Braucht es zu viele Abhängigkeiten? → Dependency Injection fehlt?

Schwer zu testendes Design ist oft schlechtes Design.
