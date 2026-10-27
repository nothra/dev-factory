# Coverage- und Testvollständigkeits-Report: Task 28

Stand: Branch `test/28-…` nach `/test`. Das Repo hat keine Abdeckungsmessung (`commands.coverage` = die Self-Test-Suite,
siehe `factory.config.yml`); die Wirksamkeit der neuen Tests wurde per Mutationslauf belegt.

## Ergebnis
| Lauf | Ergebnis |
|---|---|
| ausgelieferte Suite | **1901 grün, 0 rot** (vor Task 1887; +14) |
| Projekt-Suite | **145 grün, 0 rot** (vor Task 143) |
| Lint (`bash -n` über alle getrackten `*.sh`) | grün |

## AK-Abdeckung
| AK/FS | Test |
|---|---|
| AK1, AK4 | Fixture ohne Labelzeile (`#28 AK1/AK4`); zusätzlich Suite-Läufe in Repo-Kopien (`PROJECT-CONTEXT.md` fehlt / verändert + eigenes `aspects_extra`): Label-Drift-Block grün (siehe `review-28.md`) |
| AK2 | drei Mutations-Assertions, Ausdruck unverändert |
| AK3, FS2 | Positivkontrolle; Fixture ohne Backtick-Tabellenzeile → Abweichung gemeldet (neu) |
| AK5 | Projekt-Suite `#28 AK5` (2 Assertions) |
| AK6 | je ein Mutationsfall pro Projektdatei (6), je Repo-Wurzel-Variable (`REPO_ROOT`, `FACTORY_DIR`; neu), Ausnahme-Kontrolle, fail-closed |
| FS1 | im Code (Abbruch Exit 2), nicht automatisiert testbar ohne den Suite-Kopf zu zerlegen – bewusst offen |
| FS3 | bestehender `skip_yq`-Zweig |

## Mutationslauf (`project_reads_28`, 4 Mutanten)
| Mutant | Ergebnis |
|---|---|
| `CLAUDE.md` aus dem Muster | CLAUDE-Mutationstest rot |
| fail-closed (unlesbar) entfernt | fail-closed-Test rot |
| Ausnahme `factory.config.yml` entfernt | Gesamtguard und Ausnahme-Kontrolle rot |
| `FACTORY_ROOT` nicht erkannt | alle sechs Mutationstests rot |

Alle Mutanten wurden erkannt. Offene Grenze: indirekte Lesezugriffe über Check-Skripte (Issue #32).
