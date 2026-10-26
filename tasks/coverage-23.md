# Coverage- und Testvollständigkeits-Report: Task 23

Stand: Branch `feature/23-…` nach `/test`. Werkzeug-Hinweis: Das Repo hat keine Abdeckungsmessung
(`commands.coverage` = die Self-Test-Suite, siehe `factory.config.yml`); bash 3.2 (macOS) kennt kein `BASH_XTRACEFD`.
Ein `bash -x`-Wrapper ließ sich hier nicht belastbar auswerten (Trace-Zeilen der Kind-Prozesse kamen ohne Zeilennummer an),
darum wurde die Wirksamkeit der Tests **per Mutationslauf** belegt: je fail-closed-Zweig ein Mutant (`die`/`fail_env` wird zum
No-op) gegen die #23-Testgruppe.

## Ergebnis
| Lauf | Ergebnis |
|---|---|
| ausgelieferte Suite (`scripts/checks/tests/run-tests.sh`) | **1875 grün, 0 rot** (davor 1847; +28 in `factory-lock-tests.sh`) |
| Projekt-Suite (`scripts/project/tests/run-tests.sh`) | **143 grün, 0 rot** |
| Lint (`bash -n` über alle getrackten `*.sh`) | grün |

## Mutationslauf (26 Mutanten in `factory-sync.sh`, `factory-integrity-check.sh`)
Erster Lauf: 14 Mutanten rot, **12 überlebten** – also ungetestete oder nur zufällig mitgetestete Zweige. Nach den neuen Tests
sind 11 davon rot; einer (`Manifest würde Projektbesitz`) war nur über eine Folgefehlermeldung zufällig rot und ist jetzt über
die Abwesenheit späterer Stufen („fehlt im Tag“) und Fixtures ohne die Datei im Repo wirksam gemacht.

| Zweig | Neuer Test (Block „/test-Ergänzungen“) | Mutant danach |
|---|---|---|
| Zielverzeichnis ist Symlink (`.claude` → außerhalb) | Verzeichnis außerhalb bleibt unberührt, Meldung | rot |
| Manifest liefert Anpassungsstelle/Projektbereich | Meldung „geschützte Stelle“ + keine spätere Stufe | rot |
| FACTORY.md-Versionszeile ≠ Tag (v3.0.0-Fixture) | Abbruch, Meldung, nichts geändert | rot |
| Zusammensetzen im Temp-Baum scheitert / Projekt-Fragment fehlt | Erstabholung, nichts geändert | rot |
| Datei im Manifest fehlt im Tag | Meldung „fehlt im Tag“ | rot |
| Hash-Werkzeug scheitert bei vorhandener Datei / im Gate | Abholung bzw. Gate Exit 2 mit Meldung | rot |
| `upstream.repo` leer (Abholung und `--ci`) | Exit 1 bzw. 2 mit Meldung | rot |
| Gate ohne `factory-sync.sh` | Exit 2 | rot |
| Klon scheitert / Schreibfehler | Meldung der Ursache geschärft | rot |

## Bewusst nicht abgedeckt (Restmutanten)
- `Sicherung von …` (Backup-Kopie scheitert) und `Löschen von …`: lassen sich ohne Fehlerinjektion in `cp`/`rm` nicht auslösen; der
  Rückbau selbst ist über den Schreibfehler-Test belegt.
- `entsprechen nach der Übernahme nicht …`: Verteidigung in der Tiefe – das Zusammensetzen im Temp-Baum (Phase 1) schließt den Fall
  vorher aus.
- Gate `jq nicht gefunden`: ohne eigenes PATH-Verzeichnis ohne `jq` nicht herstellbar (Vorbild: `ownership-check.sh`-Test aus #22
  nutzt dasselbe Muster; hier kein Mehrwert, die Prüfung steht vor jeder Nutzung).

## Akzeptanzkriterien → Tests
Alle 24 Kriterien der Spec (AK2.1a–c, AK2.2a/b/c/e, AK2.3, AK2.3b, AK2.5a–d, AK2.6, F2, AK2.8, AK-28a–c, FS-T2.1/2/4,
F-23.1–F-23.3) haben Happy-Path-, Fehler- und Gegenprobe-Tests in `scripts/checks/tests/factory-lock-tests.sh` (Zuordnung steht in
den Testnamen: `#23 <AK>`); AK-28a–c in Gruppe E von `run-tests.sh` bzw. der Projekt-Suite.
