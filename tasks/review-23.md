# Review: Task 23

Review-Runde 2 (Diff `origin/main...HEAD`, Stand `06d5945`; Rework zu Runde 1 geprüft). Alle Findings der Runde 1 sind
behoben und durch Tests belegt (Symlink-Ziele rot→grün, echte Mutationsbelege, `pre-push.sh`-Verhaltenstest, OPERATING.md §5.5a).
Suiten grün (1843 + 143), Lint grün.

## Kritische Findings (müssen behoben werden)
_keine_

## Wichtige Findings (sollten behoben werden)
- [ ] `CHANGELOG.md` (Abschnitt „Unreleased“): Kein Eintrag zu #23 (Abholen per `factory-sync.sh <version> [--adopt]`, `factory.lock`, Integritäts-Gate lokal/CI, neuer Schlüssel `upstream.repo`). #22 hat seinen Eintrag im selben Abschnitt angelegt; der Abschnitt zum Tag ist Voraussetzung des Releases (Factory-ADR-063 D6) und `v0.7.0` fasst #23 und #24 zusammen. Ohne Eintrag fehlt dem Release die Beschreibung der Hauptneuerung.

## Nitpicks (optional)
- [ ] `scripts/factory-sync.sh` (`apply_version`, Berechnung von `removed.txt`): Die Pfade des **alten Locks**, die gelöscht werden, laufen durch `check_target_path`, aber nicht durch die Prüfung auf Projektbereiche/Anpassungsstellen (`fl_protected_findings`), die für das neue Manifest gilt. Ein von Hand editierter Lock mit gültigem Hash könnte so `README.md` zur „entfallenen“ Datei machen. Wirkung begrenzt (die CI-Stufe lehnt einen vom Manifest abweichenden Lock ab, die lokale Abholung läuft erst nach der Gate-Prüfung), Härtung wäre ein Zweizeiler plus Test.

## Positives
- Rework sauber und im Scope: Symlink-Prüfung jetzt für alle Schreibziele, vor `APPLYING=1` (nichts zurückzubauen), mit Test, der den Symlink-Inhalt gleich hält und so den Pfad wirklich erreicht.
- Mutationsbelege prüfen jetzt denselben Ausdruck auf Original und Mutante (`wired_23`, `ci_wired_23`).
- Hash-Vergleich und Soll-Tabelle einmalig in der Lib (`fl_manifest_tsv`, `fl_diff_hashes`); Sync und Gate nutzen dieselben Funktionen.
- Doku (`OPERATING.md` §5.5a) deckt Aufruf, `--adopt`, Gate-Stufen und Exit-Codes ab und korrigiert den veralteten Satz zur Self-Test-Suite.
- Alle Akzeptanzkriterien und Fehlerszenarien der Spec weiterhin mit Tests belegt.

## Empfehlung
NEEDS_REWORK
