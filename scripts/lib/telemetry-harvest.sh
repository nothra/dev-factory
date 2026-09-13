#!/usr/bin/env bash
# telemetry-harvest.sh – Ernte-Seam der Telemetrie-Persistenz je Pipeline-Lauf (ADR-049).
#
# Stellt EINE Funktion bereit: harvest_telemetry_csv() projiziert den Roh-Output des
# OTEL-Console-Exporters auf eine personenfreie CSV. Der Orchestrator (run-pipeline.sh)
# ruft sie – er rechnet nicht selbst (ADR-049 „Separation of Concerns"). Als reine
# Datei-in/stdout-Funktion ist sie ohne echten claude-Lauf gegen eine Fixture prüfbar.
#
# Verbindliche Grenzen aus ADR-049:
#   §E1 – Es wird NIE ein Wert selbst berechnet, geschätzt oder interpoliert. Übernommen
#         werden ausschließlich die von der CLI emittierten Ist-Werte; fehlt einer, bleibt
#         das Feld leer. Sobald hier gerechnet wird, ist es die von ADR-006 verbotene Option B.
#   §E2 – Fail-closed bei Format-Drift: wird kein Messwert erkannt, endet die Funktion
#         non-zero und gibt NICHTS aus. Ein unerkanntes Format ist ein Fehler, keine
#         Messung von 0.
#   §E5 – Die Projektion ist eine WHITELIST: nur die unten benannten Attribute werden
#         gelesen. Ein neues (womöglich personenbezogenes) Attribut einer künftigen
#         CLI-Version landet dadurch nie in der getrackten, gepushten Datei. Eine Blacklist
#         hätte den umgekehrten, nicht zurücknehmbaren Fehlerfall.
#   Sicherheitshärtung (Security-Review-Finding, Task 334): eine Feldnamen-Whitelist filtert
#         NICHT die Form des Werts. `telemetry_capture` schreibt den GESAMTEN
#         `claude --print`-Output mit, nicht nur den echten OTEL-Exporter-Anteil – ein
#         Agent, der (z. B. durch Prompt-Injection) eine Zeile ausgibt, die exakt der
#         erwarteten Blockstruktur entspricht, könnte sonst einen beliebigen Wert (auch
#         Personendaten) über ein erlaubtes Feld einschleusen. Empirisch belegt: ein
#         `model`-Feld mit einer E-Mail-Adresse wurde vor dieser Härtung klaglos übernommen.
#         Deshalb prüfen die vier gelesenen Attribute zusätzlich die WERTFORM (nicht nur das
#         Zeichen-Alphabet aus `clean()`): `query_source`/`type` exakt gegen die einzigen
#         bekannten CLI-Werte, `model`/`agent_name` gegen ein E-Mail-Muster und eine
#         Längengrenze. Nicht plausibel → Feld bleibt LEER (§E1 gilt auch hier).

# harvest_telemetry_csv <roh-log> <lauf-zeitstempel> <task-id>
#
# stdout: CSV mit Kopfzeile, eine Zeile je (Schritt-Aufruf × Metrik × Modell × Herkunft ×
#         Werttyp). Exit 0 = mindestens ein Messwert erkannt; Exit 1 = Datei unlesbar oder
#         Format nicht erkannt (dann keine Ausgabe).
#
# Erwartetes Eingabeformat (gemessen gegen claude-CLI 2.1.267 am 2026-09-11, Fixture:
# scripts/checks/tests/fixtures/otel-console-sample.txt):
#   - Ein Metrik-Block beginnt mit `{` und endet mit `}` jeweils auf Spalte 0.
#   - `name: "claude_code.<metrik>"` im descriptor benennt die Metrik.
#   - Je Datenpunkt ein `attributes: { … }`-Block, danach `value: <zahl>,`.
#   - Die Schritt-Zuordnung kommt aus der Marker-Zeile, die run_skill() in den Roh-Log
#     schreibt (`→ Starte: /<skill> <id> …`) – NICHT aus dem Attribut `skill.name`, das auf
#     dem Aufrufweg der Pipeline (Skill-Datei-Text als Prompt) nachweislich fehlt.
harvest_telemetry_csv() {
  local raw_log="$1" run_timestamp="$2" task_id="$3"

  [ -r "$raw_log" ] || return 1

  awk -v ts="$run_timestamp" -v task="$task_id" '
    # Feldwerte, die in die CSV wandern, auf ein kollisionsfreies Alphabet zwingen: kein
    # Komma kann die Spaltenstruktur zerreißen, kein Zeilenumbruch die Zeile. Zugleich die
    # letzte Grenze gegen unerwartete Inhalte aus einem fremden Ausgabeformat.
    function clean(s) { gsub(/[^A-Za-z0-9._@:+-]/, "_", s); return s }

    # Wert hinter dem ersten Doppelpunkt einer `key: wert,`-Zeile, ohne Quotes und Komma.
    function attr_value(line,   v) {
      v = line
      sub(/^[^:]*:[[:space:]]*/, "", v)
      sub(/,[[:space:]]*$/, "", v)
      gsub(/^"|"$/, "", v)
      return v
    }

    # Werte-Whitelist (Security-Review-Finding): query_source/type sind vollständig
    # enumerierbar – der CLI kennt nur genau diese Werte, alles andere ist entweder Drift
    # (soll der Format-Guard laut melden, nicht dieser Filter kaschieren) oder eingeschleust.
    function plausible_query_source(v) { return (v == "main" || v == "subagent") ? v : "" }
    function plausible_value_type(v) {
      return (v == "input" || v == "output" || v == "cacheRead" || v == "cacheCreation") ? v : ""
    }
    # model/agent_name sind NICHT abschließend aufzählbar (Gateway-/Custom-Modellnamen,
    # beliebige Sub-Agent-Personas) – hier greift nur ein Mindestmaß: kein "@" (das konkret
    # belegte Signal für E-Mail-artige Werte) und eine großzügige Längengrenze gegen
    # überlange Freitext-Payloads.
    function plausible_free_text(v) {
      if (v == "") return v
      if (length(v) > 100) return ""
      if (v ~ /@/) return ""
      return v
    }

    BEGIN { step = "unbekannt"; seq = 0; n = 0 }

    # ── Schritt-Marker (AK3) ────────────────────────────────────────────────
    # Jeder Marker eröffnet einen eigenen Abschnitt: derselbe Skill kann mehrfach laufen
    # (Review-Rework-Schleife), und jeder Aufruf ist ein eigener claude-Prozess mit einem
    # eigenen, bei 0 startenden Counter. Ohne die laufende Nummer würden zwei Aufrufe
    # desselben Skills zu einer Zeile verschmelzen und der zweite Betrag verschwinden.
    /^→ Starte: \// {
      s = $0
      sub(/^→ Starte: \//, "", s)
      sub(/[^A-Za-z0-9_-].*$/, "", s)
      step = clean(s)
      seq++
      next
    }

    # ── Blockgrenzen des Console-Exporters ──────────────────────────────────
    /^\{/ { metric = ""; in_attrs = 0; next }
    /^\}/ { metric = ""; in_attrs = 0; next }

    /^[[:space:]]+name: "claude_code\./ { metric = attr_value($0); next }

    /^[[:space:]]+attributes: \{/ { model = ""; qsrc = ""; agent = ""; vtype = ""; in_attrs = 1; next }

    # ── Whitelist der gelesenen Attribute (§E5) ─────────────────────────────
    # Alles, was hier nicht steht, wird nie gelesen – insbesondere user.email, user.id,
    # user.account_id, user.account_uuid, organization.id und session.id.
    in_attrs && /^[[:space:]]+model: /          { model = plausible_free_text(clean(attr_value($0))); next }
    in_attrs && /^[[:space:]]+query_source: /   { qsrc  = plausible_query_source(clean(attr_value($0))); next }
    in_attrs && /^[[:space:]]+"agent\.name": /  { agent = plausible_free_text(clean(attr_value($0))); next }
    in_attrs && /^[[:space:]]+type: /           { vtype = plausible_value_type(clean(attr_value($0))); next }

    # ── Messwert ────────────────────────────────────────────────────────────
    /^[[:space:]]+value: / {
      in_attrs = 0
      if (metric != "claude_code.token.usage" && metric != "claude_code.cost.usage") next
      v = attr_value($0)
      if (v !~ /^[0-9]+(\.[0-9]+)?$/) next   # nie interpretieren, nur übernehmen (§E1)

      key = seq SUBSEP step SUBSEP metric SUBSEP model SUBSEP qsrc SUBSEP agent SUBSEP vtype
      if (!(key in maxv)) { order[++n] = key; maxv[key] = v }
      # Counter sind KUMULATIV: mehrere Export-Zyklen desselben Prozesses tragen denselben
      # (bzw. einen gewachsenen) Wert. Aufsummieren wäre Mehrfachzählung – gemessen am
      # 2026-09-11: zwei Zyklen eines Mini-Aufrufs lieferten identische Werte.
      else if (v + 0 > maxv[key] + 0) maxv[key] = v
      next
    }

    END {
      if (n == 0) exit 1
      print "run_timestamp,task_id,step_seq,step,metric,model,query_source,agent_name,value_type,value"
      for (i = 1; i <= n; i++) {
        split(order[i], f, SUBSEP)
        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n", \
          ts, task, f[1], f[2], f[3], f[4], f[5], f[6], f[7], maxv[order[i]]
      }
    }
  ' "$raw_log"
}
