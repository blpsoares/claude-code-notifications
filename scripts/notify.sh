#!/usr/bin/env bash
# claude-code-notifications — notify.sh
# Toast nativo do Windows (a partir do WSL) para eventos do Claude Code.
#
# Stop         -> "terminou de responder", corpo = trecho da última resposta.
# Notification -> "aguardando você", corpo = mensagem do Claude.
#
# Extrai do JSON do hook (stdin):
#   Título = título da sessão (custom-title renomeado, senão o ai-title)
#   Corpo  = trecho da resposta / mensagem
#   Rodapé = projeto · branch · hora
# Mascote do Claude no corpo, logo da Anthropic no cabeçalho, som padrão.
#
# Auto-configura o lado Windows na 1ª execução (copia logos + registra AppID),
# então funciona tanto instalado como plugin quanto via install.sh.
#
# Requisitos: WSL, powershell.exe no PATH, jq.

set -u

MAX_LEN="${CCN_MAX_LEN:-220}"
CONFIG="${CCN_CONFIG:-$HOME/.claude/hooks/ccn.config}"
AUMID="Claude.Code.Notifications"

command -v jq >/dev/null 2>&1 || exit 0
command -v powershell.exe >/dev/null 2>&1 || exit 0

# --- auto-setup do lado Windows (idempotente; roda 1x) -----------------------
ensure_setup() {
  [ -f "$CONFIG" ] && return 0
  local assets la win_win win_wsl
  # assets: via plugin root, senão relativo a este script
  assets="${CLAUDE_PLUGIN_ROOT:-}"
  [ -n "$assets" ] && assets="$assets/assets"
  [ -d "$assets" ] || assets="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets"
  la="$(powershell.exe -NoProfile -Command '$env:LOCALAPPDATA' 2>/dev/null | tr -d '\r')"
  [ -z "$la" ] && return 0
  win_win="${la}\\claude-code-notifications"
  win_wsl="$(wslpath "$la" 2>/dev/null)/claude-code-notifications"
  mkdir -p "$win_wsl" "$(dirname "$CONFIG")" 2>/dev/null
  cp -f "$assets/claude-logo.png" "$win_wsl/claude-logo.png" 2>/dev/null
  cp -f "$assets/anthropic.png"   "$win_wsl/anthropic.png"   2>/dev/null
  reg.exe add "HKCU\\Software\\Classes\\AppUserModelId\\$AUMID" /v DisplayName /d "Claude Code" /f >/dev/null 2>&1
  reg.exe add "HKCU\\Software\\Classes\\AppUserModelId\\$AUMID" /v IconUri /d "${win_win}\\anthropic.png" /f >/dev/null 2>&1
  { printf "CCN_APP_ID='%s'\n" "$AUMID"; printf "LOGO_WIN='%s'\n" "${win_win}\\claude-logo.png"; } > "$CONFIG"
}
ensure_setup

LOGO_WIN=""; CCN_APP_ID=""
[ -f "$CONFIG" ] && . "$CONFIG"
APP_ID="${CCN_APP_ID:-$AUMID}"

# --- payload -----------------------------------------------------------------
payload="$(cat)"
get() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }
event="$(get '.hook_event_name')"
transcript="$(get '.transcript_path')"
cwd="$(get '.cwd')"; [ -z "$cwd" ] && cwd="$PWD"

tjq() { [ -n "$transcript" ] && [ -f "$transcript" ] && jq -rs "$1" "$transcript" 2>/dev/null; }
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"; }

# --- título (custom-title renomeado tem precedência sobre o ai-title) ---------
title="$(tjq '([.[] | select(.type=="custom-title") | .customTitle] | last) // ([.[] | select(.type=="ai-title") | .aiTitle] | last) // empty')"
[ -z "$title" ] && title="$(basename "$cwd")"

# --- corpo -------------------------------------------------------------------
if [ "$event" = "Notification" ]; then
  body="$(get '.message')"; [ -z "$body" ] && body="Aguardando sua ação 👀"
else
  body="$(tjq '[.[] | select(.type=="assistant" and (.message.content|type=="array") and (.message.content|any(.type=="text")))] | last | .message.content | map(select(.type=="text")|.text) | join(" ")')"
  [ -z "$body" ] && body="Terminou de responder ✅"
fi
body="$(printf '%s' "$body" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
[ "${#body}" -gt "$MAX_LEN" ] && body="$(printf '%s' "$body" | cut -c1-"$MAX_LEN")…"

# --- rodapé ------------------------------------------------------------------
project="$(basename "$cwd")"
branch="$(tjq '[.[] | .gitBranch // empty] | last // empty')"
[ -z "$branch" ] && branch="$(git -C "$cwd" branch --show-current 2>/dev/null)"
footer="$project"
[ -n "$branch" ] && [ "$branch" != "HEAD" ] && footer="$footer · ⎇ $branch"
footer="$footer · $(date +%H:%M)"

# --- imagem (mascote no corpo) ----------------------------------------------
image=""
if [ -n "$LOGO_WIN" ]; then
  logo_uri="file:///$(printf '%s' "$LOGO_WIN" | sed 's#\\#/#g')"
  image="<image placement=\"appLogoOverride\" src=\"$(xml_escape "$logo_uri")\"/>"
fi

# --- som ---------------------------------------------------------------------
# Prioridade: CCN_SOUND_FILE (.wav custom) > CCN_SOUND (evento do Windows) > padrão.
# CCN_SOUND=silent deixa mudo. CCN_SOUND_FILE aceita caminho WSL ou Windows.
custom_wav=""
if [ -n "${CCN_SOUND_FILE:-}" ]; then
  case "$CCN_SOUND_FILE" in
    /*) custom_wav="$(wslpath -w "$CCN_SOUND_FILE" 2>/dev/null)";;
    *)  custom_wav="$CCN_SOUND_FILE";;
  esac
fi
if [ -n "$custom_wav" ] || [ "${CCN_SOUND:-}" = "silent" ]; then
  audio='<audio silent="true"/>'   # o wav custom é tocado separadamente
else
  audio="<audio src=\"$(xml_escape "${CCN_SOUND:-ms-winsoundevent:Notification.Default}")\"/>"
fi

# --- monta e dispara o toast -------------------------------------------------
xml="<toast>
  <visual><binding template=\"ToastGeneric\">
    ${image}
    <text>$(xml_escape "$title")</text>
    <text>$(xml_escape "$body")</text>
    <text placement=\"attribution\">$(xml_escape "$footer")</text>
  </binding></visual>
  ${audio}
</toast>"

b64="$(printf '%s' "$xml" | base64 -w0 2>/dev/null || printf '%s' "$xml" | base64 | tr -d '\n')"

powershell.exe -NoProfile -Command "
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType=WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType=WindowsRuntime]   | Out-Null
\$xml = [Windows.Data.Xml.Dom.XmlDocument]::new()
\$xml.LoadXml([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('$b64')))
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('$APP_ID').Show(\$toast)
" >/dev/null 2>&1

# som custom (.wav): toca destacado, sem bloquear o hook
if [ -n "$custom_wav" ]; then
  wav_esc="$(printf '%s' "$custom_wav" | sed "s/'/''/g")"
  setsid powershell.exe -NoProfile -Command "(New-Object Media.SoundPlayer '$wav_esc').PlaySync()" >/dev/null 2>&1 < /dev/null &
fi

exit 0
