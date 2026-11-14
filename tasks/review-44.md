# Review: Task 44

> Iteration 2, drei Runden (Logik · Code-Qualität · Architektur) auf dem Rework-Commit `d45b7a8`.
> Läufe: ausgelieferte Suite 2555 grün / 0 rot, Projekt-Suite 249 grün / 0 rot, `factory-lock-44-tests.sh` 15 grün / 0 rot,
> `import-context-limit-check.sh` 575/750 Zeilen, 29.990/38.000 Bytes. `bash -n`, `ownership-check.sh` und `pre-push.sh`
> hat die Review-Sandbox nicht freigegeben, das prüft `/test`.
>
> Iteration 1 (NEEDS_REWORK): beide kritischen und alle vier wichtigen Findings sind behoben und hier nachgeprüft:
> - K1: alle Portabilitäts-Verweise in `scripts/` und den Guidelines zeigen auf `bash-gotchas.md § 20`. Übrig sind nur
>   Treffer in ADR-Entscheidungstexten (010, 019, 045). Die bleiben laut Plan unverändert, und der Verweis-Stub in
>   `clean-code.md:113-115` fängt sie auf.
> - K2: F7 und CHANGELOG nennen das Rot von `pre-push` Check 6 und die neuen Grenzen.
> - W1–W4: `INDEX.md`-Kopf korrigiert. Die Negativkontrolle läuft jetzt real (Manifest ohne `PROJECT-CONTEXT.md`, Sync
>   grün, Guard gegen den Konsumenten meldet `fehlt-uebersicht:neu-44.md`). Der Mutationsbeleg prüft die Meldung, der
>   Trigger nennt `/security-review`.
> - Messwerte und Konstanten sind nach dem Rework neu hergeleitet (29.990 → 37.487 → 38.000, im Kommentar und im
>   ADR-047-Nachtrag gleich).

## Kritische Findings (müssen behoben werden)

_keine_

## Wichtige Findings (sollten behoben werden)

_keine_

## Nitpicks (optional)
- [ ] [tasks/task-44-lessons-index-ausliefern.md, „Offene Fragen" und „Review-Findings"] Zwei Checkboxen sind noch offen: die E5-Frage (`/architecture` optional) und „Offen gelassen (Nitpicks)". Laut Guardrail gilt die Task mit offenen Checkboxen nicht als Done. Vor dem Merge abhaken oder in Fließtext umwandeln. Die E5-Frage ist durch die geschriebenen Nachträge faktisch entschieden.
- [ ] [docs/factory/adr/037-lessons-auslagern-aus-import-kontext.md:121-122] Im Nachtrag bricht „Abgesichert durch" mitten im Satz in eine neue Zeile um, ein Rest der Einfügung. Rein kosmetisch, Markdown rendert es korrekt.
- [ ] Offen aus Iteration 1, bewusst verschoben (die Begründung in der Task-Datei trägt): `@./`-Variante im AK4-Guard, `is_count`-Helfer, beide Grenzen in einem Lauf melden, Wortlaut „Kern-Kurzregeln"/„Factory-Issue #44" in `codify.md`. Das sind Kandidaten für `/refactor`; ein falsches Grün entsteht dadurch nicht.

## Out-of-Scope
- **Issue (Schwelle A) – weiterhin nicht angelegt:** „@import-Deckel je Projekt einstellbar machen". Die Grenzen in `import-context-limit-check.sh:73-78` sind fest und aus dem schlanken Projektteil dieses Repos hergeleitet. Für die Projektdateien eines Konsumenten bleiben rund 299 Zeilen / 14.700 Bytes. Das Skript gehört der Seite `factory` und wird beim Sync überschrieben. Die autonome Anlage über `scripts/lib/create-issue.sh` ist in diesem Review erneut gescheitert, weil die Sandbox `source` abgelehnt hat. Labels: nur `enhancement`. Das in Iteration 1 genannte `factory-pipeline` ist in diesem Repo kein Aspekt-Label (`labels.aspects_extra` ist leer). **Bitte manuell über den Seam anlegen, bevor `/codify` läuft.**
- **Kleinfund (Schwelle B):** bereits in Iteration 1 in `docs/factory/kleinfunde.md` eingetragen, unverändert gültig.

## Positives
- Der Rework ist gezielt und vollständig: jedes Finding aus Iteration 1 hat eine nachprüfbare Änderung. Ein bewusst offen gelassenes Finding ist begründet.
- Die AK7-Negativkontrolle bildet jetzt den realen Release-Ablauf ab (Manifest aus `--list factory`). Sie belegt damit genau die Lücke, die #44 schließt: Die Lesson kommt an, der Trigger nicht.
- Die Guard-Verschärfungen haben je einen eigenen pfadspezifischen Negativtest: `tf` (das Link-Ziel ist eine fremde Datei) und `le` (leeres Lesson-Verzeichnis, mit Abwesenheits-Assertion auf das Glob-Literal). Der Modul-Header nennt den Helfer.
- Der ADR-047-Nachtrag begründet, warum der Trigger jetzt `/security-review` nennt (die ADR-010-Regel verlässt den Dauerkontext). Die Änderung ist byte-neutral, der Abstand zu AK17 ist sogar größer geworden.
- `INDEX.md` erklärt die Übersichtszeile in `FACTORY.md` für maßgeblich. Damit gibt es für den Trigger je Lesson-Datei eine einzige Quelle.
- Der `codify.md`-Patch ist angewendet, und `tasks/patch-44.diff` ist entfernt (toter Patch-Zweig vermieden).

## Empfehlung
APPROVED
