# Clean Code Guidelines

Diese Regeln gelten für jeden Code, der in diesem Projekt entsteht.
Sie sind nicht optional – sie sind Teil des Quality Gates.

---

## Naming

**Variablen und Funktionen:**
- Namen beschreiben WAS, nicht WIE: `getUserById` nicht `dbQuery`
- Keine Abkürzungen außer allgemein bekannte: `url`, `id`, `dto`, `ctx`
- Booleans starten mit `is`, `has`, `can`, `should`: `isValid`, `hasPermission`
- Collections sind Plural: `users`, `orderItems`

**Klassen und Module:**
- Substantive, die eine klare Verantwortung benennen: `OrderService`, `UserRepository`
- Keine generischen Namen: nicht `Manager`, `Processor`, `Handler` ohne Kontext
- Keine technischen Suffixe wenn sie nichts sagen: `UserData` statt `UserObject`

**Funktionsnamen:**
- Verben: `calculateTotal`, `validateInput`, `sendEmail`
- Keine irreführenden Namen: wenn `getUser` auch Daten schreibt, ist das falsch

---

## Funktionen & Methoden

- **Eine Sache tun.** Wenn du "und" in der Beschreibung brauchst: aufteilen.
- **Länge:** Orientierung ~20 Zeilen. Kürzer ist fast immer besser.
- **Parameter:** max. 3. Bei mehr: Parameter-Objekt einführen.
- **Keine Flag-Parameter:** `sendEmail(user, true)` → was bedeutet `true`?
  Besser: `sendWelcomeEmail(user)` und `sendConfirmationEmail(user)`
- **Keine Side Effects** die nicht aus dem Namen erkennbar sind

---

## Kommentare

**Gute Kommentare** erklären das WHY:
```
// Preis wird auf 2 Nachkommastellen gerundet, da Kassensystem keine höhere
// Präzision unterstützt (ADR-007)
```

**Schlechte Kommentare** erklären das WHAT (steht schon im Code):
```
// Benutzer laden
User user = userRepository.findById(id);
```

**Keine auskommentierten Code-Blöcke.** Git hat eine History.

---

## Strukturregeln

- **Frühzeitig zurückkehren** (Guard Clauses statt tiefer if-else-Nesting):
  ```
  // Schlecht:
  if (user != null) {
    if (user.isActive()) {
      // ... 30 Zeilen
    }
  }

  // Gut:
  if (user == null) return Optional.empty();
  if (!user.isActive()) return Optional.empty();
  // ... 30 Zeilen
  ```

- **Keine Magic Numbers/Strings:**
  ```
  // Schlecht: if (status == 3)
  // Gut:      if (status == OrderStatus.SHIPPED)
  ```

- **Keine Code-Duplikation:** Wenn du Copy-Paste machst, extrahiere eine Funktion.

- **Separation of Concerns:** Business Logic nicht in Controller, UI nicht in Services.

---

## Was Clean Code nicht bedeutet

- Kein Over-Engineering: Nicht jede 3-Zeilen-Funktion braucht ein Interface
- Kein Premature Optimization: Erstmal lesbar, dann schnell (wenn nötig)
- Kein Gold-Plating: Nur implementieren was gebraucht wird (YAGNI)

---

## Portabilität in Gate-/Shell-Skripten

Quality-Gates (`scripts/checks/`) laufen lokal (macOS/BSD) **und** in CI (GNU/Alpine).
Nicht-portable Regex bricht still oder läuft ins Leere – ein Gate, das nicht greift,
ist gefährlicher als gar keins.

- **Nur POSIX-Regex in `grep -E`.** Kein `\s`, `\d`, `\w` (nutze `[[:space:]]`,
  `[[:digit:]]`); kein PCRE-Lookahead/-behind (`(?!…)`, `(?=…)`).
- Brauchst du Lookahead-Logik, nimm `awk` oder eine zweistufige Pipe statt `grep -P`
  (`grep -P` ist auf BSD-grep nicht verfügbar).
- Ein Gate-Regex gehört durch einen Test abgesichert, der das echte Gate gegen
  ein Positiv- **und** ein Negativ-Beispiel laufen lässt – sonst merkt niemand,
  wenn das Muster nicht mehr greift.
- **Config-/nutzerkontrollierte Werte als Daten behandeln, nie als Optionen/Code**
  (aus #36-Codify, ADR-010): Bei `grep -F`/`grep` mit variablem Suchwert immer `--`
  vor das Pattern setzen (`grep -qxF -- "$wert"`), sonst wird ein Wert wie `-x` als
  Option interpretiert. Werte vor arithmetischen Tests (`[ "$n" -lt 1 ]`) erst per
  `case "$n" in ''|*[!0-9]*)` als Integer absichern. Faustregel für Validierungs-Gates:
  fail-closed – im Zweifel ablehnen, nie still durchwinken.
