# claude-code-notifications

Notificações nativas do **Windows** para o **Claude Code** rodando no **WSL**.

Sabe quando você sai pra fazer outra coisa e fica na dúvida se o Claude ainda
está trabalhando ou já terminou faz tempo? Isso resolve: quando o Claude termina
de responder (ou fica aguardando você), um **toast do Windows** aparece com o
título da sessão, um trecho da resposta e a logo do mascote.

<p align="center">
  <img src="assets/claude-logo.png" width="96" alt="Claude Code mascot">
</p>

## ✨ O que faz

- 🔔 **Toast nativo do Windows** disparado a partir do WSL (sem apps extras).
- 🏷️ **Título** = título da sessão (o mesmo da aba do terminal).
- 💬 **Corpo** = trecho da última resposta do Claude (ou a mensagem do prompt).
- 📌 **Rodapé** = projeto · branch git · hora.
- 🐤 **Logo** do mascote do Claude no canto.
- 🔊 **Som** padrão do Windows (configurável, ou mudo).

Dispara em dois momentos:

| Evento | Quando | Corpo |
|--------|--------|-------|
| `Stop` | Claude termina de responder | trecho da última resposta |
| `Notification` | Claude fica aguardando você (ex.: pedido de permissão) | mensagem do Claude |

## 📦 Requisitos

- Windows 10/11 com WSL2
- `powershell.exe` acessível no PATH do WSL (padrão)
- `jq` (`sudo apt install jq`)

## 🚀 Instalação

### Opção 1 — Plugin (recomendado)

No próprio Claude Code:

```
/plugin marketplace add blpsoares/claude-code-notifications
/plugin install claude-code-notifications@blpsoares
```

O hook é registrado automaticamente — **sem mexer no `settings.json`**. Na 1ª
execução o script se auto-configura no lado Windows (copia as logos e registra
o AppID). Pronto.

### Opção 2 — Manual (`install.sh`)

```bash
git clone https://github.com/blpsoares/claude-code-notifications.git
cd claude-code-notifications
bash install.sh
```

Depois abra o menu **`/hooks`** (ou reinicie) para recarregar. O instalador é
**idempotente** e faz **backup** do `settings.json`.

> ⚠️ Não use as duas ao mesmo tempo — se instalou pelo `install.sh` e depois quer
> o plugin, rode `bash uninstall.sh` antes (evita notificação duplicada).

## 🧠 Como funciona

| Peça | Onde fica | Papel |
|------|-----------|-------|
| `scripts/notify.sh` | plugin (ou `~/.claude/hooks/`) | Hook `Stop`/`Notification`; lê o JSON do evento, extrai os dados e dispara o toast via `powershell.exe`. Auto-configura o Windows na 1ª execução. |
| `claude-logo.png` / `anthropic.png` | `%LOCALAPPDATA%\claude-code-notifications\` | Mascote (corpo do toast) e logo Anthropic (ícone do cabeçalho). |
| AppID `Claude.Code.Notifications` | registro `HKCU` | AUMID registrado (nome "Claude Code" + ícone Anthropic). **Sem isso o Windows descarta o toast.** |
| `hooks/hooks.json` | plugin | Registra `Stop` + `Notification` automaticamente (plugin). No modo manual, vão para `~/.claude/settings.json`. |

## ⚙️ Personalização

Adicione as variáveis no `~/.claude/hooks/ccn.config`:

### 🔊 Som

O som **padrão** é o `Cloud.wav` (empacotado no plugin — um toque suave e aéreo).
Para trocar:

**Sons prontos do Windows** via `CCN_SOUND`:

```bash
CCN_SOUND='ms-winsoundevent:Notification.IM'          # mensagem
CCN_SOUND='ms-winsoundevent:Notification.Mail'        # e-mail
CCN_SOUND='ms-winsoundevent:Notification.Reminder'    # lembrete
CCN_SOUND='ms-winsoundevent:Notification.SMS'         # SMS
CCN_SOUND='ms-winsoundevent:Notification.Looping.Alarm'  # alarme (chama atenção)
CCN_SOUND='ms-winsoundevent:Notification.Looping.Call'   # chamada
CCN_SOUND=silent                                       # mudo
```

**Som customizado (qualquer `.wav`)** via `CCN_SOUND_FILE` (aceita caminho
Windows ou WSL):

```bash
CCN_SOUND_FILE='C:\Windows\Media\tada.wav'
CCN_SOUND_FILE='/home/voce/sons/ping.wav'
```

`CCN_SOUND_FILE` tem prioridade sobre `CCN_SOUND`. (`.wav` — o Windows só toca
arquivos de som próprios via `<audio>`; o custom é tocado à parte com o
`SoundPlayer`.)

### Outros

- **Tamanho do trecho**: `CCN_MAX_LEN=120` (padrão `220`).

## 🩺 Não aparece nada?

Na ordem mais comum:

1. **Notificações silenciadas / Não Perturbe (Assistente de Foco).** É o
   suspeito nº 1. Vá em **Configurações → Sistema → Notificações**, garanta que
   estão **ligadas** e desative o **Não Perturbe** — inclusive as regras de
   *ativar automaticamente* (ao jogar / app em tela cheia / duplicar a tela),
   que silenciam tudo sem avisar.
2. **Config não recarregada.** Se você acabou de instalar, abra o menu
   **`/hooks`** no Claude Code uma vez (ou reinicie).
3. **AppID.** O `install.sh` registra o AUMID `Claude.Code.Notifications` para
   que o Windows aceite o toast (toasts de AppID não registrado são descartados
   silenciosamente).

## ❓ E clicar na notificação pra ir pro terminal / responder permissão por ali?

Foi avaliado e **removido de propósito**. O Windows Terminal roda todas as abas
numa **única janela** e **não expõe API para ativar uma aba específica** — só dá
pra focar a *janela*, não a aba. Como consequência:

- "Pular pra aba da sessão" só funcionaria se aquela aba já fosse a ativa.
- Botões de resposta enviariam a tecla para **qualquer aba que estivesse ativa**,
  podendo responder a **sessão errada**.

Por segurança e confiabilidade, o projeto foca no que funciona 100%: **avisar
você na hora certa**.

## 🗑️ Desinstalar

```bash
bash uninstall.sh
```

Remove os hooks (com backup) e o AppID registrado.

## 📄 Licença

MIT — veja [LICENSE](LICENSE).
