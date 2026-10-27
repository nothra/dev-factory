# Review: Task 28

## Kritische Findings (müssen behoben werden)
_keine_

## Wichtige Findings (sollten behoben werden)
_keine im Scope._ Außerhalb des Scopes, oberhalb der Schwelle (funktionaler Defekt mit reproduzierbarem Auslöser) → Issue #32:
`scripts/checks/tests/run-tests.sh:6346` ruft `import-context-limit-check.sh` gegen den echten Repo-Stand auf und liest damit
`CLAUDE.md` und `docs/factory/PROJECT-CONTEXT.md` indirekt. Beleg: Fixture-Lauf ohne `PROJECT-CONTEXT.md` → Test
`#319: realer @import-Stand …` rot. Der AK6-Guard erfasst nur direkte Pfadzugriffe, nicht diesen Weg. Spec-28 schließt weitere
Umzüge ausdrücklich aus („Nicht inbegriffen"), daher kein Blocker für diesen PR.

## Nitpicks (optional)
- [ ] scripts/checks/tests/run-tests.sh (Fixture-Block): FS1 (Fixture nicht schreibbar → Abbruch mit Exit 2) ist im Code, aber ohne Test
- [ ] scripts/checks/tests/run-tests.sh (AK6-Guard): erkennt nur `$FACTORY_ROOT|$REPO_ROOT|$FACTORY_DIR`-Pfade; ein neuer Variablenname würde nicht erfasst (Grenze im Kommentar benennen)

## Positives
- AK1/AK4 belegt per Suite-Lauf in Kopien des Repos: (a) `PROJECT-CONTEXT.md` fehlt, (b) Datei verändert plus eigenes
  `aspects_extra: [eigen-label]` ohne Beschreibung → in beiden Fällen sind alle `#431 AK-I2`- und `#28`-Assertions grün.
  Die übrigen Rotbefunde der Kopien (`#149`, `#426`, `#22`, `AK-L1`) treten in (a) und (b) identisch auf und kommen vom Kopier-Aufbau
  (kein Git-Verlauf, Pfad unter `/private/tmp`), nicht von dieser Änderung; einziger Unterschied ist `#319` in (a), siehe oben.
- Die drei Mutations-Assertions behalten ihren Ausdruck; Positivkontrolle (AK3) schützt vor Falsch-Grün (FS2).
- AK6-Guard baut sein Muster zur Laufzeit zusammen (kein Selbsttreffer), je Datei ein Mutationsfall plus Ausnahme-Kontrolle und fail-closed.
- AK5: der echte Labelbereich bleibt in der Projekt-Suite geprüft; Vorher/Nachher-Zählung steht in der Task-Datei (1887 → 1898, 143 → 145).
- Kein ADR-Trigger; ADR-064 D6 unverändert; keine neue getrackte Datei (OWNERSHIP unberührt).

## Empfehlung
APPROVED
