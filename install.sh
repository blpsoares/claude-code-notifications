#!/usr/bin/env bash
# claude-code-notifications — instalador
# Instala o hook de notificações WSL->Windows para o Claude Code.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
CONFIG="$HOOKS_DIR/ccn.config"
PROTOCOL="claudecodenotify"

info() { printf '\033[36m›\033[0m %s\n' "$1"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$1"; }
err()  { printf '\033[31m✗\033[0m %s\n' "$1" >&2; }

# --- pré-requisitos ----------------------------------------------------------
grep -qiE "microsoft|wsl" /proc/version 2>/dev/null || { err "Isto precisa rodar dentro do WSL."; exit 1; }
command -v jq >/dev/null 2>&1              || { err "jq não encontrado. Instale: sudo apt install jq"; exit 1; }
command -v powershell.exe >/dev/null 2>&1  || { err "powershell.exe não está no PATH do WSL."; exit 1; }
ok "Ambiente WSL + jq + powershell.exe"

# --- caminho Windows (LOCALAPPDATA) ------------------------------------------
LOCALAPPDATA_WIN="$(powershell.exe -NoProfile -Command '$env:LOCALAPPDATA' 2>/dev/null | tr -d '\r')"
WIN_DIR_WIN="${LOCALAPPDATA_WIN}\\claude-code-notifications"
WIN_DIR_WSL="$(wslpath "$LOCALAPPDATA_WIN")/claude-code-notifications"
LOGO_WIN="${WIN_DIR_WIN}\\claude-logo.png"
FOCUS_WIN="${WIN_DIR_WIN}\\focus.ps1"

# --- copia arquivos ----------------------------------------------------------
mkdir -p "$HOOKS_DIR" "$WIN_DIR_WSL"
install -m 0755 "$REPO_DIR/notify.sh" "$HOOKS_DIR/ccn-notify.sh"
cp -f "$REPO_DIR/focus.ps1"      "$WIN_DIR_WSL/focus.ps1"
cp -f "$REPO_DIR/claude-logo.png" "$WIN_DIR_WSL/claude-logo.png"
ok "Scripts instalados (hook em $HOOKS_DIR, handler em $WIN_DIR_WSL)"

# --- registra o AppID (AUMID) — sem isso o Windows descarta o toast ----------
AUMID="Claude.Code.Notifications"
AUMID_KEY="HKCU\\Software\\Classes\\AppUserModelId\\$AUMID"
reg.exe add "$AUMID_KEY" /v DisplayName /d "Claude Code" /f >/dev/null
reg.exe add "$AUMID_KEY" /v IconUri /d "$LOGO_WIN" /f >/dev/null
ok "AppID '$AUMID' registrado (nome + ícone no Centro de Notificações)"

# --- config (AppID + caminho da logo p/ o notify.sh) -------------------------
{ printf "CCN_APP_ID='%s'\n" "$AUMID"; printf "LOGO_WIN='%s'\n" "$LOGO_WIN"; } > "$CONFIG"
ok "Config gravado em $CONFIG"

# --- registra protocolo (clique/botões) --------------------------------------
CMD="powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"$FOCUS_WIN\" \"%1\""
reg.exe add "HKCU\\Software\\Classes\\$PROTOCOL" /ve /d "URL:Claude Code Notify" /f >/dev/null
reg.exe add "HKCU\\Software\\Classes\\$PROTOCOL" /v "URL Protocol" /d "" /f >/dev/null
reg.exe add "HKCU\\Software\\Classes\\$PROTOCOL\\shell\\open\\command" /ve /d "$CMD" /f >/dev/null
ok "Protocolo $PROTOCOL:// registrado (clicar foca o terminal / botões respondem)"

# --- merge dos hooks no settings.json (idempotente + backup) -----------------
[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"
cp -f "$SETTINGS" "$SETTINGS.bak.$(date +%s)"
HOOK_CMD="$HOOKS_DIR/ccn-notify.sh"
jq --arg cmd "$HOOK_CMD" '
  def clean(a): (a // []) | map(select(((.hooks // []) | any((.command // "") | test("ccn-notify"))) | not));
  .hooks.Stop         = clean(.hooks.Stop)         + [{"hooks":[{"type":"command","command":$cmd}]}]
  | .hooks.Notification = clean(.hooks.Notification) + [{"hooks":[{"type":"command","command":$cmd}]}]
' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
jq empty "$SETTINGS" && ok "Hooks Stop + Notification adicionados em $SETTINGS"

echo
ok "Instalado! Abra o menu /hooks no Claude Code (ou reinicie) para recarregar."
info "Teste: no Claude Code, envie uma mensagem — ao terminar, o toast aparece."
info "Desinstalar: bash \"$REPO_DIR/uninstall.sh\""
