# Security Review: Task 44

## Kritische Findings (Blocker)
Keine.

## Wichtige Findings
Keine.

## Hinweise
- [ ] [Information Disclosure / Pfadauflösung] `scripts/checks/import-context-limit-check.sh:140-146` (`repo_relative`) prüft den `@import`-Pfad nur lexikalisch (kein `/`-Präfix, kein `..`-Segment); `[ -f "$rel" ]` (Z. 210) folgt aber Symlinks. Eine im Repo committete Datei `x.md -> /etc/hosts`, per `@x.md` eingebunden, wird mitgezählt und erscheint mit ihrer Größe in der Beitragsliste. Mit diesem PR liefert das Orakel neben der Zeilen- auch die Bytezahl (`wc -c`, Z. 219; Ausgabe Z. 224, 238, 248-249). Kein ausnutzbares Risiko: Voraussetzung ist Schreibrecht auf das Repo, ausgegeben wird nur eine Größe, nie Inhalt, und das nur lokal bzw. im eigenen CI-Log. Empfehlung bei Gelegenheit: Symlinks ablehnen (`[ -L "$rel" ]` → fail-closed) oder den aufgelösten Pfad gegen `$ROOT` prüfen. **Out-of-Scope** (die lexikalische Prüfung stammt aus nothra/tch-gastro-services#319; dieser PR hängt nur die Bytezahl an), **Nitpick → `kleinfunde.md`**.
- [ ] [Robustheit Test-Fixtures] `scripts/checks/tests/run-tests.sh:7114` (`IC_STUB_44="$(mktemp -d)"`) und `:9493` (`TMP_LI_44="$(mktemp -d)"`) prüfen nicht, ob `mktemp` erfolgreich war, und haben keinen `trap` zum Aufräumen. Scheitert `mktemp`, schreibt `ic_wc_stub_44` nach `/wc` bzw. `li_copy_44` nach `/<name>/…`. Für einen Nicht-Root-Nutzer scheitert das am Dateisystem, die Tests werden rot. `rm -rf ""` ist harmlos. Bricht die Suite ab, bleiben Temp-Verzeichnisse liegen. Das ist das Muster der ganzen Suite (z. B. `TMP_IC`, `TMP_LNK_319`). **In Scope** (die zwei Stellen sind neu), **Nitpick**: blockiert nicht. Wer es härten will: `|| exit 2` hinter `mktemp -d`.

## Ergebnis
PASSED
