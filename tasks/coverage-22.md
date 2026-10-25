# Coverage- und Testvollständigkeits-Report: Task 22

Stand: Branch `feature/22-…` nach `/test` (PR #25). Werkzeug-Hinweis: Das Repo hat keine Abdeckungsmessung
(`commands.coverage` = die Self-Test-Suite, siehe `factory.config.yml`); bash 3.2 (macOS) kennt kein `BASH_XTRACEFD`.
Die Zeilenabdeckung von `scripts/checks/ownership-check.sh` wurde darum per `bash -x` in einem Wrapper gemessen, der Trace und stderr trennt.

## Ergebnis
| Lauf | Ergebnis |
|---|---|
| ausgelieferte Suite (`scripts/checks/tests/run-tests.sh`) | **1672 grün, 0 rot** |
| Projekt-Suite (`scripts/project/tests/run-tests.sh`) | **133 grün, 0 rot** |
| ausgelieferte Suite im Konsumenten-Fixture (Hooks installiert) | **1672 grün, 0 rot** |
| Lint (`bash -n` über alle getrackten `*.sh`) | grün |

Zählvergleich: 1762 (vorher) + 43 neu = 1805 = 1672 + 133.

## Zeilenabdeckung `ownership-check.sh` (Produktionscode dieser Task)
- Ausführbare Zeilen (ohne Kommentare, Klammerzeilen und den unveränderten awk-Block des Tabellenmodus): 90.
- Vor `/test`: 70 ausgeführt; 20 nicht ausgeführt. Davon 13 Messartefakte (Funktionsköpfe und `case`-Muster erscheinen im `xtrace` nicht), **7 echte Lücken** in 4 fail-closed-Pfaden.
- Nach `/test`: alle 4 Pfade sind durch Tests belegt (Mutationsbeleg unten); offen bleibt nur, was `xtrace` nicht anzeigt.

| Lücke (Zeile) | Neuer Test (`scripts/checks/tests/run-tests.sh`, Block „Konsumenten-Vertrag“) | Mutation (Skript-Kopie) |
|---|---|---|
| unbekannter Parameter → Exit 2 (44) | „#22 /test: unbekannter Parameter → Exit 2 (auch mit Lock)“ + Meldung | `exit 2` → `exit 0`: Test rot |
| Dateiliste nicht lesbar → Exit 2 (50–51) | Lock-Modus und Tabellenmodus je Exit 2 + Meldung | `exit 2` → `exit 0`: beide rot |
| `git ls-files` scheitert → Exit 2 (56–57) | Lock-Modus ohne git-Repo und ohne Dateiliste | `exit 2` → `exit 0`: Test rot |
| `comm` scheitert selbst → Exit 2 (113–114) | PATH-Stub mit fehlschlagendem `comm` („Messung brechen“) | `exit 2` → `return 0`: Test rot |

## Akzeptanzkriterien → Tests (Happy Path / Fehlerfall / Grenzfall)
| AK | Tests |
|---|---|
| AK2.15a, a-2, a-3 | Lock ohne `OWNERSHIP.md` (Verteilung, Moduszeile); `--list factory`/`project` exakt; widersprüchliche Tabelle neben dem Lock |
| AK2.15b | Lock-Pfad ohne Datei (Exit 1, Pfad), Anpassungsstelle im Lock (Exit 1, Pfad), je mit „Gegen-Signal fehlt“; CRLF-Liste, Randleerraum, leere Liste (Exit 2); 300 Funde (Schlusszeile nennt 300) |
| AK2.15b-2 | Drift-Guard beide Richtungen mit Negativtest und Wirkungs-Kontrolle; Mindestinhalt der Liste; fehlende Quellen → Exit 2 (Projekt-Suite) |
| AK2.15c | alle bisherigen Tabellen-Tests, jetzt gegen den Lock eines Konsumenten isoliert (`NO_LOCK_FILE`); Kontrolle „ohne Lock keine Moduszeile“ |
| AK2.15d-0 | `OWNERSHIP.md` auf Seite `project`, nicht `factory` (Projekt-Suite); Manifest-Test mit `factory.lock` im Arbeitsbaum |
| AK2.16a | Fixture-Lauf (1672/0), im PR belegt; Lib/Fixtures sind Seite `factory` (3 Tests) |
| AK2.16b, b-3 | Zählvergleich; `ownership-check.sh` grün; `scripts/project/**` auf Seite `project` |
| AK2.16b-2 | Wiring an echten Aufrufzeilen (Hook, CI-Job), Hook-Exit-Code grün/rot, Mutationen, Kopplungsschutz `FACTORY_SELF_TEST_RUN` |
| F-22.1 | leer, kein JSON, `files` leer, Schema ≠ 1, Eintrag ohne Pfad, nicht lesbar, kein `jq` (PATH-Stub), hängender Symlink – alle ohne Rückfall in den Tabellenmodus |
| F-22.2 | fehlende Liste, leere Liste → Exit 2 |
| F-22.3 | `+`, `[`, Leerzeichen wörtlich; `.`/`*` kein Muster; Umlaut-Pfade gegen echtes `git` |
| F-22.4 | doppelter Lock-Pfad → Exit 1, Pfad genannt |
| F-22.5 | beide Suiten ohne `assert-helpers.sh` → Exit 2 mit Dateiname; Lib/Fixtures auf Seite `factory` |

## Testqualität (Stichproben und Befunde)
- Verhalten statt Implementierung: alle neuen Tests laufen über das echte Skript, der Umlaut-Test über echtes `git ls-files`.
- Isolation: je Test ein eigenes `mktemp`-Fixture; Lock-Variablen werden vom Konsumenten-Lock entkoppelt; Umlaut-Fixture setzt `core.quotepath=true`.
- Messung brechen (Lesson #319): `jq` und `comm` per PATH-Stub; nicht nur der Input.
- Determinismus: keine Uhr, keine Netzwerkzugriffe; der einzige Umweltbezug (`--follow`-Historie) ist hinter einem Shallow-Klon-Skip.
- Unverändert offen (kein Fund dieser Task): Pfade mit Zeilenumbruch im Lock, Leerzeilen in `OWNERSHIP_FILE_LIST`, Tabellenmodus-Test für Umlaut-Pfade (siehe `tasks/review-22.md`, Nitpicks).

Kein Produktionscode wurde in diesem Schritt geändert.
