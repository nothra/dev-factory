# ADR 042: Hook-Installation über eine gemeinsame Quelle (`install-hooks.sh`)

## Status
Accepted

## Date
2026-08-02

## Kontext

Issue #262 (Spec: `docs/specs/spec-262-flag-guard-commit-message.md`) verlangt einen
neuen `commit-msg`-Git-Hook (lehnt Commit-Messages ab, die wie `--help`/`-h` aussehen),
zusätzlich zu einem in derselben Task neu entstehenden `-h|--help`-Guard in
`scripts/factory-commit.sh`.

Bisher installiert ausschließlich `scripts/init-factory.sh` Git-Hooks – als Teil eines
**einmaligen** Projekt-Bootstraps (`pre-commit`/`pre-push` werden dort per Heredoc in
`.git/hooks` geschrieben). Zwei Probleme daraus:

1. **Retrofit-Lücke.** Dieses Repo wurde bereits am 2026-07-08 initialisiert. Ergänzt
   `init-factory.sh` künftig den `commit-msg`-Hook, schützt das dieses (und jedes andere
   bereits initialisierte) Repo **nicht rückwirkend** – niemand führt `init-factory.sh`
   ein zweites Mal auf einem bestehenden Projekt aus (es würde PROJECT-CONTEXT.md &Co.
   erneut templaten).
2. **Wiederholbarkeit.** Es gibt keinen Weg, Hooks nachträglich zu installieren oder zu
   aktualisieren (z. B. wenn ein künftiges Issue einen weiteren Hook oder eine geänderte
   Hook-Logik bringt), außer den Heredoc-Block manuell in `.git/hooks` nachzubauen.

Git-Worktrees teilen sich `.git/hooks` über das gemeinsame Git-Verzeichnis (bestätigt via
`git rev-parse --git-common-dir`) – ein einmal installierter Hook gilt sofort für alle
bestehenden und künftigen Worktrees dieses Repos. Es braucht also **keine**
Pro-Worktree-Logik, sondern einen wiederholt ausführbaren Installationsweg.

Damit ist eine Architektur-Entscheidung nötig: **Wie kommt die Hook-Installationslogik
(jetzt: `pre-commit` + `pre-push` + neu `commit-msg`) an zwei Aufrufstellen
(Neuprojekt-Bootstrap vs. nachträgliches Retrofit), ohne dass beide Stellen bei jeder
künftigen Hook-Änderung synchron gehalten werden müssen?**

## Decision

**`scripts/install-hooks.sh` wird die einzige Quelle für den Inhalt der Git-Hooks.**
Es ist ein eigenständiges, idempotentes Skript, das `pre-commit`, `pre-push` und
`commit-msg` in `.git/hooks` schreibt (analog zum bisherigen Heredoc-Muster in
`init-factory.sh`) und jederzeit erneut ausgeführt werden kann (Neuprojekt, Retrofit
eines bestehenden Repos, künftige Hook-Ergänzungen).

`scripts/init-factory.sh` ruft für Schritt 5 („Git Hooks installieren") nur noch
`bash scripts/install-hooks.sh` auf, statt die Heredocs selbst zu enthalten. Die
Hook-Installationslogik existiert damit an **einer** Stelle; `init-factory.sh` bleibt für
alles andere (PROJECT-CONTEXT.md-Templating etc.) unverändert.

Für **dieses** Repo wird `scripts/install-hooks.sh` nach Merge dieser Task einmalig manuell
ausgeführt, um den `commit-msg`-Hook tatsächlich scharf zu schalten (siehe Spec, „Nicht
inbegriffen" – kein automatischer Aufruf durch `start-work.sh` o. Ä., da Hooks bereits
repo-weit über alle Worktrees geteilt werden).

**Fail-closed bei gesetztem `core.hooksPath`:** Ist die Git-Option gesetzt (in
JS-Projekten häufig, z. B. durch husky), führt Git **ausschließlich** Hooks aus diesem
Verzeichnis aus – eine Installation nach `.git/hooks` wäre wirkungslos, das Repo hielte
sich aber für geschützt. `install-hooks.sh` bricht in diesem Fall mit exit ≠ 0 und einer
Meldung ab, statt fremde Hook-Verwaltung zu überschreiben oder stillen Schein-Erfolg zu
melden. Welche der beiden Auflösungen richtig ist (Option entfernen oder die Factory-Checks
in den konfigurierten Pfad einbinden), entscheidet der Mensch pro Repo.

**Fail-open nur für ein fehlendes Prüfskript:** Der `commit-msg`-Hook prüft vor dem Aufruf,
ob `scripts/checks/commit-msg-check.sh` im Arbeitsbaum existiert, und beendet sich sonst mit
exit 0. Grund: Der Hook gilt dank gemeinsamem Git-Verzeichnis sofort für alle Branches und
Worktrees – auch für solche ohne das Skript (vor dem Merge angelegte Worktrees, ältere
Feature-Branches, `git bisect`). Ohne diese Ausnahme wäre dort **jeder** Commit mit
`No such file or directory` blockiert. Existiert das Skript, entscheidet weiterhin allein
sein fail-closed Ergebnis – die Ausnahme deckt ausschließlich den Nicht-vorhanden-Fall ab.

**Kommentarzeilen vor dem Vergleich verwerfen:** Git entfernt die `#`-Kommentarzeilen des
Editor-Templates erst **nach** dem `commit-msg`-Hook (`--cleanup`). Ein reiner Trim-Vergleich
griffe deshalb nur auf dem `-m`-Pfad; auf dem Editor-Pfad (`git commit` ohne `-m`, `-e`,
`--amend`, Merge, `-t <template>`) sähe der Hook `--help\n\n# Please enter …` und ließe den
Commit entstehen (empirisch mit git 2.50 verifiziert). `commit-msg-check.sh` verwirft daher
zuerst alle Zeilen, die mit dem konfigurierten Kommentar-Präfix beginnen
(`core.commentString`/`core.commentChar`, Default `#`), und trimmt erst danach.
**Restlücke:** Bei `core.commentChar=auto` wählt Git den Präfix pro Message aus einer
Kandidatenliste, ohne ihn festzuhalten – dort greift der Guard auf dem Editor-Pfad nur, wenn
Git tatsächlich `#` gewählt hat. Bewusst nicht nachgebaut (Heuristik ohne verlässliche Quelle);
der `-m`-Pfad und der Seam-Guard in `factory-commit.sh` bleiben davon unberührt.

**Bewusst nicht extrahiert:** Die beiden Literalstrings `--help`/`-h` selbst bleiben
**unabhängig** in `scripts/checks/commit-msg-check.sh` (Git-Hook, beliebige Commit-Messages)
und `scripts/factory-commit.sh` (eigenes CLI-Argument-Parsing) stehen. Eine gemeinsame
„Known-Flags"-Quelle für zwei Literale in zwei konzeptionell unterschiedlichen Skripten wäre
Over-Engineering (kein Kompromiss bei Clean Code heißt hier: keine Abstraktion für zwei
Zeilen Code an zwei unterschiedlichen Konzern-Grenzen). **Neu zu bewerten, sobald eine dritte
Stelle dazukommt** – konkret Issue **#131** („`start-work.sh`: `--help`/`-h` behandeln"): drei
Vorkommen sind der Punkt, an dem eine gemeinsame Quelle günstiger wird als die Duplikation.

Der `-h`/`--help`-Guard in `scripts/factory-commit.sh` berührt den Seam-Kontrakt aus
**ADR-019 §1** („Die Message ist Pflicht-Argument") – dort als Nachtrag (#262) präzisiert.

## Alternatives

### Option A: `install-hooks.sh` als Single Source, `init-factory.sh` ruft es auf (gewählt)
**Vorteile:**
- Eine Stelle für Hook-Inhalt – keine Drift zwischen Neuprojekt- und Retrofit-Pfad
  (passend zu den wiederholt aufgetretenen Drift-Lessons in diesem Projekt, z. B. #214).
- Löst das Retrofit-Problem für dieses und jedes andere bereits initialisierte Repo direkt
  und wiederholt ausführbar.
- Isoliert testbar (Positiv-/Negativ-Fall je Hook), ohne den kompletten
  `init-factory.sh`-Bootstrap in Tests mitzuschleifen.

**Nachteile:**
- `init-factory.sh` bekommt eine Laufzeit-Abhängigkeit auf ein weiteres Skript im selben
  Repo (marginal – beide liegen in `scripts/`, kein externer Bezug).

### Option B: Hook-Heredocs unabhängig in beiden Skripten duplizieren
**Vorteile:**
- Keine neue Abhängigkeit zwischen den Skripten; `init-factory.sh` bleibt monolithisch
  wie bisher.

**Nachteile:**
- Zwei Stellen, die bei jeder künftigen Hook-Änderung (weiterer Hook, geänderte Guard-Logik)
  synchron gehalten werden müssen – genau das Muster, das in diesem Projekt wiederholt zu
  Drift-Bugs geführt hat (`docs/factory/lessons/code-style.md`, `factory-workflow.md`).
- Löst das Retrofit-Problem nicht eleganter als Option A, verdoppelt aber den Wartungsaufwand.

### Option C: Nur `init-factory.sh` erweitern, kein separates Installer-Skript
**Vorteile:**
- Minimalster Diff für den Neuprojekt-Fall.

**Nachteile:**
- Verworfen bereits in `/requirements` (siehe Spec, Retrofit-Frage): löst die Retrofit-Lücke
  für bestehende Repos überhaupt nicht – die eigentliche Ursache dieses Issues (ein Commit
  entstand in einem Repo *ohne* den schützenden Hook) bliebe für alle bereits laufenden
  Projekte offen.

## Rationale

Option A gewinnt, weil sie die einzige Alternative ist, die (a) das Retrofit-Problem – den
eigentlichen Auslöser dieses Issues – tatsächlich löst, (b) keine Logik dupliziert, die laut
Projekt-Historie wiederholt auseinandergedriftet ist, und (c) sich sauber isoliert testen
lässt (idempotentes Skript statt vollständiger Bootstrap-Lauf).

## Consequences

**Positive:**
- Hook-Logik hat eine kanonische Quelle; künftige Hook-Änderungen (z. B. ein weiterer Guard)
  landen an einer Stelle und gelten für Neu- **und** Bestandsprojekte gleichermaßen.
- Dieses Repo lässt sich durch einmaligen Aufruf von `scripts/install-hooks.sh` retrofitten,
  ohne `init-factory.sh` erneut laufen zu lassen.

**Negative / Trade-offs:**
- `init-factory.sh` ist nicht mehr vollständig in sich geschlossen lesbar – wer die
  Hook-Installation nachvollziehen will, muss zusätzlich `install-hooks.sh` öffnen.
- Der `commit-msg`-Hook enthält eine bewusste Fail-open-Ausnahme (fehlendes Prüfskript →
  exit 0, siehe Decision). Auf einem Branch ohne `commit-msg-check.sh` greift der Flag-Guard
  also nicht – der Preis dafür, dass ein repo-weiter Hook keine älteren Branches blockiert.
- In Repos mit gesetztem `core.hooksPath` bleibt die Hook-Installation ein manueller
  Entscheidungsschritt (der Installer bricht dort ab).
- Die Ausführung von `scripts/install-hooks.sh` in diesem bestehenden Repo bleibt ein
  manueller Schritt nach dem Merge (keine Automatisierung, siehe Spec) – ein potenzieller
  „vergessen, auszuführen"-Fehlerpunkt, der außerhalb dieses PRs liegt. Getrackt als Issue
  **#265** (inkl. Vorschlag, die Hook-Präsenz im `pre-push`-Check fail-closed zu verifizieren),
  damit der Schritt nicht nur in der nach dem Merge kaum gelesenen Task-Datei steht.
- Ein `init-factory.sh`-Bootstrap, bei dem der Installer fail-closed abbricht, endet jetzt mit
  eigenem Banner und Exit ≠ 0 statt mit der Erfolgsmeldung – sonst hätte die Aufrufstelle den
  Fail-closed-Anspruch des Installers wieder aufgehoben.
