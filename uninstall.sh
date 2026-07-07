#!/usr/bin/env bash
# claude-code-notifications — desinstalador
set -euo pipefail

HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
PROTOCOL="claudecodenotify"
ok() { printf '\033[32m✓\033[0m %s\n' "$1"; }

# remove hooks ccn do settings.json (preserva o resto), com backup
if [ -f "$SETTINGS" ]; then
  cp -f "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
  jq '
    def clean(a): (a // []) | map(select(((.hooks // []) | any((.command // "") | test("ccn-notify"))) | not));
    .hooks.Stop = clean(.hooks.Stop) | .hooks.Notification = clean(.hooks.Notification)
    | if (.hooks.Stop | length) == 0 then del(.hooks.Stop) else . end
    | if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
  ' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
  ok "Hooks removidos do settings.json"
fi

# desregistra protocolo
reg.exe delete "HKCU\\Software\\Classes\\$PROTOCOL" /f >/dev/null 2>&1 || true
ok "Protocolo $PROTOCOL:// desregistrado"

# remove script do hook (deixa a logo/handler no Windows; inofensivos)
rm -f "$HOOKS_DIR/ccn-notify.sh" "$HOOKS_DIR/ccn.config"
ok "Scripts do hook removidos"

echo; ok "Desinstalado. Abra /hooks ou reinicie o Claude Code para recarregar."
