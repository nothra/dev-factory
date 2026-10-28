## Codify-Report: Task 32

### Neue Regeln hinzugefügt
- docs/factory/lessons/testing.md (Nachtrag zu #28) + Index-Zeile in `PROJECT-CONTEXT.md` – wegen: (1) ein Gate, das seine Wurzel aus dem Skriptpfad ableitet, ist ein indirekter Leser, den kein Muster-Guard sieht (`#149`-Test rief `pre-push.sh` aus dem echten Repo); (2) Fixture-Läufe brauchen identischen Aufbau, sonst Rot aus dem Aufbau; (3) Mutation einer optionalen Regex-Gruppe ohne Zeilenanfangs-Anker bleibt grün (redundante Gruppe).

### Keine Änderungen nötig
- Review (APPROVED, nur Nitpicks) und Security-Review (PASSED) lieferten keine weiteren Fehlermuster. Kein Out-of-Scope-Fund, daher kein Issue und kein `kleinfunde.md`-Eintrag.

### Empfehlung für nächste Features
- Bei Test-Zuordnungen „ausgeliefert vs. repo-spezifisch" den Fixture-Lauf (mit/ohne Datei/aufgebläht) gleich in `/implement` fahren, nicht erst nach dem Guard-Bau – er fand hier den zweiten Leser.
