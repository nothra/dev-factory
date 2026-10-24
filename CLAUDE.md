# dev-factory

Projekt-Regeln für Claude Code im **Factory-Repo selbst**. Der generische Teil (Factory-Prinzipien,
Pipeline, Guidelines, Guardrails) steht in `docs/factory/FACTORY.md` und gehört der Factory
(`docs/factory/OWNERSHIP.md`); hier stehen nur die Regeln dieses Repos.

@docs/factory/FACTORY.md

---

## Projekt-Kontext

@docs/factory/PROJECT-CONTEXT.md

---

## Projekt-Regeln (dev-factory)

- **Das Repo nutzt sich selbst:** Änderungen laufen über Issue → `start-work.sh` → Feature-Branch → PR
  (Squash). Direkt auf `main` zu pushen lehnt das Ruleset `protect-main` serverseitig ab.
- **Ownership pflegen:** Jede neue getrackte Datei braucht im selben PR eine Zeile in
  `docs/factory/OWNERSHIP.md` (Seite `factory` = wird ausgeliefert, `project` = gehört dem Repo).
- **Referenzen qualifizieren:** ein Verweis auf `nothra/tch-gastro-services` steht immer als
  `nothra/tch-gastro-services#<nr>`; unqualifiziertes `#<nr>` meint dieses Repo.
- **Keine projektspezifischen Begriffe** aus adoptierenden Projekten in Skripten, Skills, Guidelines,
  ADRs und Lessons (Liste und erlaubte Stellen: `PROJECT-CONTEXT.md` → „Konventionen").
