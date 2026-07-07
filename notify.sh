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
# Logo do mascote do Claude no canto. Som padrão do Windows.
#
# Requisitos: WSL, powershell.exe no PATH, jq.

set -u

MAX_LEN="${CCN_MAX_LEN:-220}"
LOGO_WIN=""       # preenchido pelo config
CCN_APP_ID=""     # idem

# config gerado pelo install.sh (AppID registrado + caminho Windows da logo)
CONFIG="${CCN_CONFIG:-$HOME/.claude/hooks/ccn.config}"
[ -f "$CONFIG" ] && . "$CONFIG"

# AppID DEVE ser um AUMID registrado, senão o Windows descarta o toast.
APP_ID="${CCN_APP_ID:-Claude.Code.Notifications}"

command -v jq >/dev/null 2>&1 || exit 0
command -v powershell.exe >/dev/null 2>&1 || exit 0

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

# --- imagem (logo) -----------------------------------------------------------
image=""
if [ -n "$LOGO_WIN" ]; then
  logo_uri="file:///$(printf '%s' "$LOGO_WIN" | sed 's#\\#/#g')"
  image="<image placement=\"appLogoOverride\" src=\"$(xml_escape "$logo_uri")\"/>"
fi

# --- som (configurável via CCN_SOUND; 'silent' = mudo) -----------------------
sound_src="${CCN_SOUND:-ms-winsoundevent:Notification.Default}"
if [ "$sound_src" = "silent" ]; then
  audio='<audio silent="true"/>'
else
  audio="<audio src=\"$(xml_escape "$sound_src")\"/>"
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

exit 0
