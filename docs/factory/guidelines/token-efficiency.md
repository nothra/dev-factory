# Token- & Kosten-Effizienz

Jeder Agenten-Aufruf kostet Token – und Token kosten Geld (besonders in Stage 3,
wo pro Feature mehrere Sessions hintereinander laufen). Diese Regeln halten den
Verbrauch niedrig, ohne die Qualität zu senken.

> Faustregel: Nicht das größere Kontextfenster füllen, sondern dem Modell den
> kürzesten Weg zur richtigen Information geben.

---

## 1. Frischer Kontext pro Aufgabe

- Starte nach jeder abgeschlossenen Story/Task eine **neue Session**.
- Alter Gesprächsverlauf, der nichts mehr zur aktuellen Aufgabe beiträgt, wird
  sonst bei jedem Schritt erneut mitgeschleppt und neu bezahlt.
- Die Task-Datei ist das Gedächtnis – nicht der Chat-Verlauf.

---

## 2. Übergabe statt Historie

- Am **Ende einer Session** einen kurzen Handover-Prompt erzeugen lassen:
  Was wurde gemacht, was ist offen, was muss die nächste Session wissen.
- Die nächste Session startet mit Handover + Task-Datei – **nicht** mit dem
  kompletten alten Transcript.
- Ergebnis: schlanker Einstieg, kein wiederholtes Einlesen von Ballast.

---

## 3. Helfer-Dokumente statt Suchen

- Lass das Modell Navigations-Hilfen pflegen: z.B. eine `dependencies.md` mit
  Story-/Modul-Abhängigkeiten, eine kurze Architektur-Übersicht, ein Index der
  wichtigsten Einstiegspunkte.
- Solche Dokumente sind billig zu lesen und ersparen dem Modell, sich die
  Struktur jedes Mal neu zu erschließen.

---

## 4. Gezielt lesen statt Full-Scan

- Konkrete Dateien/Pfade referenzieren statt „lies das ganze Repo".
- Gezielte Suche (Grep/Glob) vor dem Öffnen ganzer Verzeichnisbäume.
- Ein versehentlicher Full-Scan eines großen Projekts ist der teuerste
  Einzelfehler – aktiv vermeiden, gerade wenn das Projekt wächst.

---

## 5. Kontext-Dateien schlank halten

- `CLAUDE.md`, `PROJECT-CONTEXT.md` und die Guidelines werden bei **jeder**
  Session geladen. Jede Zeile darin wird dauerhaft mitbezahlt.
- Nur aufnehmen, was wirklich projektweit gilt. Veraltetes raus.

---

## 6. Vorhandene Stellschrauben der Pipeline nutzen

`scripts/run-pipeline.sh` bringt bereits Kostenhebel mit – nutze sie bewusst:

- **Modell-Tiers:** schweres Reasoning auf das starke Modell, leichte Schritte
  auf ein günstigeres (`CLAUDE_MODEL_HEAVY` / `CLAUDE_MODEL_LIGHT`). Faustregel:
  das günstigste Modell, das die Aufgabe zuverlässig löst – aber bei teuren
  Fehlern (übersehene Bugs, Security) lohnt das stärkere Modell, weil ein Miss
  teurer ist als der Token-Aufpreis.
  Welche Modelle den Tiers zugeordnet sind und welcher Skill welches Tier fährt,
  ist **kanonisch** in `factory.defaults.yml` definiert (`model_tiers` +
  `skills.*.tier`, geschichtet per `factory.config.yml`, ADR-009) – dort
  nachschlagen statt hier zu duplizieren. `review`/`implement`/`bug-fix` wählen
  das Tier zudem **größenabhängig** (`skills.*.tier_by_size`, ADR-038): kleiner
  Lauf → günstiges Tier, großer → starkes; bei unbestimmbarer Größe fällt es
  fail-safe auf das starke Tier zurück.
- **Turn-Limits:** pro Skill begrenzt (`get_max_turns`) – verhindert ausufernde
  Agenten-Loops.
- **`--dry-run`:** Ablauf und geplante Aufrufe prüfen, bevor echte Token fließen.

---

## Was hier (noch) nicht steht

Weitere projektspezifische Kniffe zur Vermeidung teurer Full-Scans gehören als
`/codify`-Learning in die thematisch passende Datei unter `docs/factory/lessons/`
(Volltext, **nicht** @import) plus eine Index-Zeile in `PROJECT-CONTEXT.md` (ADR-037),
sobald sie konkret benannt sind – nicht als vage Allgemeinplätze hier.
