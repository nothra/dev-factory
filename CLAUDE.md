# TCH Gastro Services

Projekt-Regeln für Claude Code. Der generische Teil (Factory-Prinzipien, Pipeline, Guidelines,
Guardrails) steht in `docs/factory/FACTORY.md` und gehört der Factory (`docs/factory/OWNERSHIP.md`);
hier stehen nur die Regeln, die TCH-spezifisch sind.

@docs/factory/FACTORY.md

---

## Projekt-Kontext

@docs/factory/PROJECT-CONTEXT.md

---

## Projekt-Regeln (TCH)

- **Routen-Doku bei jeder Routen-Änderung aktualisieren.** Wird eine Seite (`app/**/page.tsx`)
  oder ein API-Route-Handler (`app/api/**/route.ts`) hinzugefügt, entfernt oder in Pfad/Zugriff
  geändert, ist [`docs/routes.md`](docs/routes.md) im selben PR mitzupflegen (Pfad, Funktion,
  Zugriff). Der Drift-Check `scripts/project/checks/pre-push.d/routes-doc-check.sh` blockiert einen Push fail-closed,
  wenn Doku und `app/`-Baum auseinanderlaufen. Analog zu „Entscheidungen dokumentieren". (aus #145)
