# claude-code-notifications

Notificações nativas do **Windows** para o **Claude Code** rodando no **WSL**.

Sabe quando você sai pra fazer outra coisa e fica na dúvida se o Claude ainda
está trabalhando ou já terminou faz tempo? Isso resolve: quando o Claude termina
de responder (ou fica aguardando você), um **toast do Windows** aparece com o
título da sessão, um trecho da resposta e a logo do mascote.

<p align="center">
  <img src="claude-logo.png" width="96" alt="Claude Code mascot">
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

```bash
git clone https://github.com/blpsoares/claude-code-notifications.git
cd claude-code-notifications
bash install.sh
```

Depois, abra o menu **`/hooks`** no Claude Code uma vez (ou reinicie) para
recarregar as configurações. Pronto — na próxima resposta o toast aparece.

O instalador é **idempotente** (pode rodar de novo sem duplicar nada) e faz
**backup** do seu `settings.json` antes de mexer.

## 🧠 Como funciona

| Peça | Onde fica | Papel |
|------|-----------|-------|
| `ccn-notify.sh` | `~/.claude/hooks/` | Hook `Stop`/`Notification`; lê o JSON do evento, extrai os dados e dispara o toast via `powershell.exe`. |
| `claude-logo.png` | `%LOCALAPPDATA%\claude-code-notifications\` | Logo exibida no toast. |
| AppID `Claude.Code.Notifications` | registro `HKCU` | AUMID registrado (nome + ícone). **Sem isso o Windows descarta o toast.** |
| hooks `Stop` + `Notification` | `~/.claude/settings.json` | Disparam o hook nos eventos do Claude Code. |

## ⚙️ Personalização

Adicione as variáveis no `~/.claude/hooks/ccn.config`:

- **Som**: `CCN_SOUND='ms-winsoundevent:Notification.Default'` (padrão). Use
  `CCN_SOUND=silent` para toast mudo, ou outro
  [evento de som do Windows](https://learn.microsoft.com/windows/apps/design/shell/tiles-and-notifications/toast-audio).
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
