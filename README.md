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
- 🖱️ **Clique** na notificação → **foca o terminal** da sessão (WSL ou CMD —
  casa pela correspondência de título da janela).
- ✅ **Botões de ação** quando o Claude pede permissão: **Sim / Sempre / Não**
  respondem o prompt direto pela notificação.

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
| `focus.ps1` | `%LOCALAPPDATA%\claude-code-notifications\` | Handler do protocolo `claudecodenotify://`; foca o terminal e (nos botões) responde o prompt. |
| `claude-logo.png` | idem | Logo exibida no toast. |
| protocolo `claudecodenotify://` | registro `HKCU` | Faz o clique/botões chamarem o `focus.ps1`. |
| hooks `Stop` + `Notification` | `~/.claude/settings.json` | Disparam o hook nos eventos do Claude Code. |

O foco de janela usa `WScript.Shell.AppActivate` (método seguro do Windows).
**Não** usa o truque `AttachThreadInput` de "roubo de foco" — no pior caso a
janela só não é focada; nada é derrubado.

## ⚙️ Personalização

- **Tamanho do trecho**: variável `CCN_MAX_LEN` (padrão `220`). Ex.: no
  `~/.claude/hooks/ccn.config` adicione `CCN_MAX_LEN=120`.
- **Textos/emojis dos botões**: edite a função `a()` em `notify.sh` e reinstale.

## 🖱️ Sobre os botões de ação (permissão)

Ao clicar num botão, o handler foca o terminal da sessão e envia a tecla ao
prompt. As teclas foram escolhidas para funcionar **tanto no prompt de 2 opções
(yes/no) quanto no de 3 opções**:

| Botão | Tecla | Vale para |
|-------|-------|-----------|
| ✅ Sim | `1` | a opção 1 é sempre "Yes" nos dois formatos |
| ⏭️ Sempre | `2` | só existe no prompt de 3 opções (nos de 2, é ignorado) |
| 🚫 Não | `Esc` | cancela/rejeita o prompt independente do nº de opções |

> Não dá para saber pelo evento quantas opções o prompt tem, por isso o "Não"
> usa `Esc` (rejeição universal) em vez de um número fixo.

É **best-effort**: depende do terminal ainda estar no prompt de permissão. Se a
sessão já tiver seguido em frente, a tecla é ignorada.

## 🩺 Não aparece nada?

Na ordem mais comum:

1. **Notificações silenciadas / Assistente de Foco (Não Perturbe).** É o
   suspeito nº 1. Vá em **Configurações → Sistema → Notificações**, garanta que
   estão **ligadas** e que o **Assistente de Foco** está desativado (ou libere o
   app "Claude Code" na lista de prioridade).
2. **Config não recarregada.** Se você acabou de instalar, abra o menu
   **`/hooks`** no Claude Code uma vez (ou reinicie) pra recarregar o
   `settings.json`.
3. **AppID.** Este projeto registra o AUMID `Claude.Code.Notifications` para que
   o Windows aceite e exiba o toast — toasts de AppIDs não registrados são
   descartados silenciosamente. O `install.sh` já cuida disso.

## 🗑️ Desinstalar

```bash
bash uninstall.sh
```

Remove os hooks (com backup), desregistra o protocolo e apaga o script do hook.

## 📄 Licença

MIT — veja [LICENSE](LICENSE).
