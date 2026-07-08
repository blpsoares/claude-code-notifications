#!/usr/bin/env bash
# claude-code-notifications — ccn-config.sh
# Configura o plugin editando ~/.claude/hooks/ccn.config. Usado pelo /ccn.
set -u

CONFIG="${CCN_CONFIG:-$HOME/.claude/hooks/ccn.config}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

set_kv() {
  touch "$CONFIG"
  grep -v "^$1=" "$CONFIG" > "$CONFIG.tmp" 2>/dev/null || true
  printf "%s='%s'\n" "$1" "$2" >> "$CONFIG.tmp"
  mv "$CONFIG.tmp" "$CONFIG"
}
unset_kv() {
  [ -f "$CONFIG" ] || return 0
  grep -v "^$1=" "$CONFIG" > "$CONFIG.tmp" 2>/dev/null || true
  mv "$CONFIG.tmp" "$CONFIG"
}
val() { [ -f "$CONFIG" ] && sed -n "s/^$1='\(.*\)'$/\1/p" "$CONFIG" | tail -1; }

usage() {
  cat <<'EOF'
Uso: /ccn <comando>

  status              mostra a configuração atual
  on | off            liga/desliga as notificações
  test                dispara um toast de teste
  threshold <seg>     só notifica no Stop se a resposta demorou >= seg (0 = sempre)
  duration on|off     mostra/oculta a duração no rodapé
  buttons on|off      botões Sim / Sim sempre / Não no prompt de permissão
  click on|off        clicar na notificação foca a aba/janela da sessão
  sound <nome>        som: default | silent | im | mail | reminder | alarm | call
                            ou um ms-winsoundevent:... completo
  sound-file <path>   usa um .wav próprio (caminho Windows ou WSL)
EOF
}

cmd="${1:-status}"
case "$cmd" in
  status)
    echo "claude-code-notifications — configuração:"
    echo "  ativo:      $([ "$(val CCN_ENABLED)" = "0" ] && echo não || echo sim)"
    t="$(val CCN_MIN_SECONDS)"; echo "  threshold:  ${t:-0}s"
    echo "  duração:    $([ "$(val CCN_SHOW_DURATION)" = "0" ] && echo oculta || echo visível)"
    echo "  botões:     $([ "$(val CCN_BUTTONS)" = "0" ] && echo não || echo sim)"
    echo "  clique:     $([ "$(val CCN_CLICK)" = "0" ] && echo não || echo sim)"
    sf="$(val CCN_SOUND_FILE)"; se="$(val CCN_SOUND)"
    if [ -n "$sf" ]; then echo "  som:        arquivo $sf"
    elif [ -n "$se" ]; then echo "  som:        $se"
    else echo "  som:        padrão (Cloud)"; fi
    ;;
  on)  unset_kv CCN_ENABLED; echo "Notificações ligadas." ;;
  off) set_kv CCN_ENABLED 0; echo "Notificações desligadas." ;;
  threshold)
    n="${2:-}"; case "$n" in ''|*[!0-9]*) echo "Informe os segundos, ex.: /ccn threshold 30"; exit 1;; esac
    if [ "$n" = "0" ]; then unset_kv CCN_MIN_SECONDS; echo "Threshold removido (notifica sempre)."
    else set_kv CCN_MIN_SECONDS "$n"; echo "Só notifica respostas com >= ${n}s."; fi
    ;;
  duration)
    case "${2:-}" in
      on)  unset_kv CCN_SHOW_DURATION; echo "Duração visível no rodapé." ;;
      off) set_kv CCN_SHOW_DURATION 0; echo "Duração oculta." ;;
      *)   echo "Use: /ccn duration on|off"; exit 1 ;;
    esac
    ;;
  buttons)
    case "${2:-}" in
      on)  unset_kv CCN_BUTTONS; echo "Botões de resposta ligados." ;;
      off) set_kv CCN_BUTTONS 0; echo "Botões de resposta desligados." ;;
      *)   echo "Use: /ccn buttons on|off"; exit 1 ;;
    esac
    ;;
  click)
    case "${2:-}" in
      on)  unset_kv CCN_CLICK; echo "Clique-para-focar ligado." ;;
      off) set_kv CCN_CLICK 0; echo "Clique-para-focar desligado." ;;
      *)   echo "Use: /ccn click on|off"; exit 1 ;;
    esac
    ;;
  sound)
    s="${2:-}"
    case "$s" in
      default)  unset_kv CCN_SOUND; unset_kv CCN_SOUND_FILE; echo "Som padrão restaurado." ;;
      silent)   unset_kv CCN_SOUND_FILE; set_kv CCN_SOUND silent; echo "Som desativado (mudo)." ;;
      im)       unset_kv CCN_SOUND_FILE; set_kv CCN_SOUND "ms-winsoundevent:Notification.IM"; echo "Som: IM." ;;
      mail)     unset_kv CCN_SOUND_FILE; set_kv CCN_SOUND "ms-winsoundevent:Notification.Mail"; echo "Som: Mail." ;;
      reminder) unset_kv CCN_SOUND_FILE; set_kv CCN_SOUND "ms-winsoundevent:Notification.Reminder"; echo "Som: Reminder." ;;
      alarm)    unset_kv CCN_SOUND_FILE; set_kv CCN_SOUND "ms-winsoundevent:Notification.Looping.Alarm"; echo "Som: Alarm." ;;
      call)     unset_kv CCN_SOUND_FILE; set_kv CCN_SOUND "ms-winsoundevent:Notification.Looping.Call"; echo "Som: Call." ;;
      ms-winsoundevent:*) unset_kv CCN_SOUND_FILE; set_kv CCN_SOUND "$s"; echo "Som: $s." ;;
      *) echo "Som desconhecido. Use: default, silent, im, mail, reminder, alarm, call, ou ms-winsoundevent:..."; exit 1 ;;
    esac
    ;;
  sound-file)
    f="${2:-}"; [ -z "$f" ] && { echo "Informe o caminho do .wav"; exit 1; }
    unset_kv CCN_SOUND; set_kv CCN_SOUND_FILE "$f"; echo "Som: arquivo $f"
    ;;
  test)
    printf '{"hook_event_name":"Stop","cwd":"%s"}' "$PWD" | bash "$DIR/notify.sh"
    echo "Toast de teste disparado."
    ;;
  help|-h|--help) usage ;;
  *) echo "Comando desconhecido: $cmd"; echo; usage; exit 1 ;;
esac
