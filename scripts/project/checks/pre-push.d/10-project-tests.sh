#!/usr/bin/env bash
# 10-project-tests.sh – Projekt-Suite des Factory-Repos als lokales Push-Gate (Factory-ADR-064 D6)
#
# Die ausgelieferte Suite (scripts/checks/tests/run-tests.sh) ist konsumenten-neutral; alles, was ci.yml,
# release.yml, OWNERSHIP.md oder den Release-Stand dieses Repos voraussetzt, läuft nur hier. pre-push.sh führt dieses
# Skript über den Erweiterungspunkt scripts/project/checks/pre-push.d/ aus; in CI läuft dieselbe Suite als Job
# `project-self-test` in ci.yml. Der Exit-Code der Suite ist der des Hooks.
#
# Innerhalb der ausgelieferten Suite (FACTORY_SELF_TEST_RUN, gesetzt von scripts/checks/tests/run-tests.sh) wird nichts
# gestartet: dort ruft die Suite pre-push.sh echt gegen dieses Repo auf, und die Projekt-Suite liefe sonst verschachtelt
# mehrfach – ein Rot von ihr färbte außerdem unbeteiligte Gate-Tests falsch rot.

set -euo pipefail

if [ -n "${FACTORY_SELF_TEST_RUN:-}" ]; then
  echo "Projekt-Suite übersprungen (läuft innerhalb der ausgelieferten Self-Test-Suite)"
  exit 0
fi

ROOT="${FACTORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)}"
exec bash "$ROOT/scripts/project/tests/run-tests.sh"
