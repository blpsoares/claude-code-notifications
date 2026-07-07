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
#   Rodapé = projeto · branch · hora [· duração]
# Mascote no corpo, logo da Anthropic no cabeçalho, som por evento.
#
# Auto-configura o lado Windows na 1ª execução (copia assets + registra AppID),
# então funciona tanto como plugin quanto via install.sh.
#
# Variáveis (em ~/.claude/hooks/ccn.config ou no ambiente):
#   CCN_ENABLED=0        desliga as notificações
#   CCN_MIN_SECONDS=N    no Stop, só notifica se a resposta demorou >= N seg
#   CCN_SHOW_DURATION=0  não mostra a duração no rodapé
#   CCN_SOUND=...        evento ms-winsoundevent, ou 'silent'
#   CCN_SOUND_FILE=...   .wav próprio (tem prioridade sobre CCN_SOUND)
#   CCN_MAX_LEN=N        tamanho do trecho (padrão 220)
#
# Requisitos: WSL, powershell.exe no PATH, jq.

set -u

MAX_LEN="${CCN_MAX_LEN:-220}"
CONFIG="${CCN_CONFIG:-$HOME/.claude/hooks/ccn.config}"
AUMID="Claude.Code.Notifications"

command -v jq >/dev/null 2>&1 || exit 0
command -v powershell.exe >/dev/null 2>&1 || exit 0

# --- auto-setup do lado Windows (idempotente; roda 1x por versão de config) ---
ensure_setup() {
  [ -f "$CONFIG" ] && grep -q CCN_ALERT_WAV "$CONFIG" && return 0
  local assets la win_win win_wsl
  assets="${CLAUDE_PLUGIN_ROOT:-}"
  [ -n "$assets" ] && assets="$assets/assets"
  [ -d "$assets" ] || assets="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/assets"
  la="$(powershell.exe -NoProfile -Command '$env:LOCALAPPDATA' 2>/dev/null | tr -d '\r')"
  [ -z "$la" ] && return 0
  win_win="${la}\\claude-code-notifications"
  win_wsl="$(wslpath "$la" 2>/dev/null)/claude-code-notifications"
  mkdir -p "$win_wsl" "$(dirname "$CONFIG")" 2>/dev/null
  cp -f "$assets/claude-logo.png"     "$win_wsl/claude-logo.png" 2>/dev/null
  cp -f "$assets/anthropic.png"       "$win_wsl/anthropic.png"   2>/dev/null
  cp -f "$assets/sounds/Cloud.wav"    "$win_wsl/Cloud.wav"       2>/dev/null
  cp -f "$assets/sounds/Alert.wav"    "$win_wsl/Alert.wav"       2>/dev/null
  reg.exe add "HKCU\\Software\\Classes\\AppUserModelId\\$AUMID" /v DisplayName /d "Claude Code" /f >/dev/null 2>&1
  reg.exe add "HKCU\\Software\\Classes\\AppUserModelId\\$AUMID" /v IconUri /d "${win_win}\\anthropic.png" /f >/dev/null 2>&1
  { printf "CCN_APP_ID='%s'\n" "$AUMID"
    printf "LOGO_WIN='%s'\n" "${win_win}\\claude-logo.png"
    printf "CCN_DEFAULT_WAV='%s'\n" "${win_win}\\Cloud.wav"
    printf "CCN_ALERT_WAV='%s'\n" "${win_win}\\Alert.wav"; } > "$CONFIG"
}
ensure_setup

LOGO_WIN=""; CCN_APP_ID=""; CCN_DEFAULT_WAV=""; CCN_ALERT_WAV=""
[ -f "$CONFIG" ] && . "$CONFIG"
APP_ID="${CCN_APP_ID:-$AUMID}"

# desligado?
[ "${CCN_ENABLED:-1}" = "0" ] && exit 0

# --- payload -----------------------------------------------------------------
payload="$(cat)"
get() { printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null; }
event="$(get '.hook_event_name')"
transcript="$(get '.transcript_path')"
cwd="$(get '.cwd')"; [ -z "$cwd" ] && cwd="$PWD"

tjq() { [ -n "$transcript" ] && [ -f "$transcript" ] && jq -rs "$1" "$transcript" 2>/dev/null; }
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"; }

# --- duração do turno (do último prompt humano até agora; só no Stop) ---------
turn_secs=""
if [ "$event" != "Notification" ]; then
  start_ts="$(tjq '[.[] | select(.type=="user") | select((.message.content|tostring)|test("tool_result")|not) | .timestamp] | last // empty')"
  if [ -n "$start_ts" ]; then
    se="$(date -d "$start_ts" +%s 2>/dev/null || true)"
    [ -n "$se" ] && turn_secs=$(( $(date +%s) - se ))
    [ -n "$turn_secs" ] && [ "$turn_secs" -lt 0 ] && turn_secs=""
  fi
fi

# --- filtro por duração (só Stop) --------------------------------------------
min_s="${CCN_MIN_SECONDS:-0}"
if [ "$event" != "Notification" ] && [ -n "$turn_secs" ] \
   && [ "$min_s" -gt 0 ] && [ "$turn_secs" -lt "$min_s" ]; then
  exit 0
fi

# --- título ------------------------------------------------------------------
title="$(tjq '([.[] | select(.type=="custom-title") | .customTitle] | last) // ([.[] | select(.type=="ai-title") | .aiTitle] | last) // empty')"
[ -z "$title" ] && title="$(basename "$cwd")"

# --- corpo -------------------------------------------------------------------
if [ "$event" = "Notification" ]; then
  body="$(get '.message')"; [ -z "$body" ] && body="Aguardando sua ação"
else
  body="$(tjq '[.[] | select(.type=="assistant" and (.message.content|type=="array") and (.message.content|any(.type=="text")))] | last | .message.content | map(select(.type=="text")|.text) | join(" ")')"
  [ -z "$body" ] && body="Terminou de responder"
fi
body="$(printf '%s' "$body" | tr '\n' ' ' | sed 's/  */ /g; s/^ //; s/ $//')"
[ "${#body}" -gt "$MAX_LEN" ] && body="$(printf '%s' "$body" | cut -c1-"$MAX_LEN")…"

# --- rodapé: projeto · branch · hora [· duração] -----------------------------
fmt_dur() { if [ "$1" -ge 60 ]; then printf '%dm%02ds' "$(($1/60))" "$(($1%60))"; else printf '%ds' "$1"; fi; }
project="$(basename "$cwd")"
branch="$(tjq '[.[] | .gitBranch // empty] | last // empty')"
[ -z "$branch" ] && branch="$(git -C "$cwd" branch --show-current 2>/dev/null)"
footer="$project"
[ -n "$branch" ] && [ "$branch" != "HEAD" ] && footer="$footer · ⎇ $branch"
footer="$footer · $(date +%H:%M)"
if [ "${CCN_SHOW_DURATION:-1}" != "0" ] && [ -n "$turn_secs" ]; then
  footer="$footer · $(fmt_dur "$turn_secs")"
fi

# --- imagem (mascote no corpo) ----------------------------------------------
image=""
if [ -n "$LOGO_WIN" ]; then
  logo_uri="file:///$(printf '%s' "$LOGO_WIN" | sed 's#\\#/#g')"
  image="<image placement=\"appLogoOverride\" src=\"$(xml_escape "$logo_uri")\"/>"
fi

# --- som (padrão depende do evento; overrides globais preservados) -----------
# Prioridade: CCN_SOUND_FILE > CCN_SOUND > som padrão do evento
# (Stop = Cloud, Notification = Alert). CCN_SOUND=silent deixa mudo.
if [ "$event" = "Notification" ]; then ev_default="$CCN_ALERT_WAV"; else ev_default="$CCN_DEFAULT_WAV"; fi
custom_wav=""
if [ -n "${CCN_SOUND_FILE:-}" ]; then
  case "$CCN_SOUND_FILE" in
    /*) custom_wav="$(wslpath -w "$CCN_SOUND_FILE" 2>/dev/null)";;
    *)  custom_wav="$CCN_SOUND_FILE";;
  esac
elif [ -z "${CCN_SOUND:-}" ] && [ -n "$ev_default" ]; then
  custom_wav="$ev_default"
fi
if [ -n "$custom_wav" ] || [ "${CCN_SOUND:-}" = "silent" ]; then
  audio='<audio silent="true"/>'
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
