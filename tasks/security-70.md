# Security Review: Task 70

> Umfang: `git diff origin/main...HEAD` – `scripts/checks/pre-commit.sh` (Gate-Logik), `scripts/checks/tests/run-tests.sh`
> (Block „Factory-Issue #70"), `docs/factory/kleinfunde.md`, Spec/Task/Review-Datei. Threat Surface: lokales,
> per `--no-verify` umgehbares Feedback-Gate; fail-closed schützt `main` allein das Ruleset `protect-main`
> (Factory-ADR-029). Der Fix verbessert die Sicherheit: das Credential-Gate (Check 4) war bei großem Diff fail-open.

## Kritische Findings (Blocker)

_Keine._

## Wichtige Findings

_Keine._

## Hinweise

- [x] [Fail-closed / Restpfad] Ein Here-String braucht in bash eine Temp-Datei (bash 3.2 immer, bash ≥ 5.1 ab
  Pipe-Puffergröße – beim ≥ 1-MiB-Diff also immer). Kann bash sie nicht anlegen, scheitert die Umleitung mit Status 1,
  und `if grep -q … <<< "$STAGED_DIFF"` landet im „✓"-Zweig. Nicht ausnutzbar: bash fällt bei nicht beschreibbarem
  `TMPDIR` auf `/tmp` bzw. `/var/tmp` zurück, und wer die Umgebung des Committers kontrolliert, kann das Gate ohnehin
  per `--no-verify` überspringen. Die Temp-Datei legt bash mit Modus 0600 an und löscht sie sofort – kein Leck des
  Diff-Inhalts (der Secrets enthalten kann) an andere Nutzer. Ursprünglich als „kein Handlungsbedarf" eingestuft.
  **Nachtrag 2026-11-25: behoben (AK10).** Auf Ralfs Entscheidung im selben PR geschlossen: `diff_check` wertet den
  `grep`-Exit-Code je Check aus (`grep -c`; nur Exit 1 mit Ausgabe „0" ist „kein Treffer"), alles andere blockiert mit
  „Prüfung nicht ausführbar". Getestet per `grep`-Stub mit Exit 2 und mit Exit 1 ohne Ausgabe; der Probelauf mit
  unbrauchbarem `TMPDIR` selbst bleibt ungeprüft, der Stub bildet sein Verhalten (Status 1, keine Ausgabe) nach.
- [x] [Sensitive Data / Logging] `STAGED_DIFF` wird nie ausgegeben; die Meldungen nennen nur den Check, nicht die
  Fundstelle. Der neue Lesefehler-Zweig gibt nur einen festen Text aus, `git`-stderr geht unverändert ans Terminal.
  Kein Leck.
- [x] [Injection] Alle Regex sind feste Literale, der Diff-Inhalt ist nur Daten (grep/awk-Eingabe per Here-String),
  kein `eval`, keine Expansion von Diff-Inhalt in Kommandos. Die Klammer-Schreibweise im Debug-Muster (Semikolon als Zeichenklasse) ändert die
  Treffermenge nicht (eine Klasse mit einem Zeichen ist äquivalent).
- [x] [Credentials im Code] Die Test-Trigger (`password = '…'`, Konfliktmarker, Debug-Statement) werden zur Laufzeit
  zusammengesetzt; der Wert `geheim12345` ist eine offensichtliche Test-Fixture, kein echtes Secret.
- [x] [Testcode] Der git-Stub in AK7 schreibt `$(command -v git)` in einfache Anführungszeichen; ein git-Pfad mit `'`
  bräche nur den Test, ohne Sicherheitsfolge. Wegwerf-Verzeichnis per `mktemp -d`, am Ende `rm -rf` – kein Risiko.
- [x] [Verfügbarkeit] Der ganze Staged-Diff liegt im Speicher. Bei Commit-Diffs unkritisch; es gibt keinen fremden
  Angreifer, der die Diffgröße steuert.
- [x] [Dependencies] Keine neuen Abhängigkeiten (nur `git`, `grep`, `awk`, die schon vorher genutzt wurden).
- [x] [Error Handling] Lesefehler bei `git diff --cached` → eigene Meldung + `exit 1` vor jedem Check (fail-closed,
  AK7 getestet). Keine internen Details über `git`-stderr hinaus.

## Ergebnis
PASSED
