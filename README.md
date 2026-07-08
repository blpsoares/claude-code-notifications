# claude-code-notifications

Notificações nativas do Windows para o Claude Code rodando no WSL.

Quando você sai para fazer outra coisa e fica na dúvida se o Claude ainda está
trabalhando ou já terminou, esta ferramenta resolve: quando o Claude termina de
responder (ou fica aguardando você), um toast do Windows aparece com o título da
sessão, um trecho da resposta e a logo do mascote.

<p align="center">
  <img src="assets/claude-logo.png" width="96" alt="Claude Code mascot">
</p>

## Recursos

- Toast nativo do Windows disparado a partir do WSL, sem aplicativos extras.
- Título: título da sessão (o mesmo da aba do terminal).
- Corpo: trecho da última resposta do Claude (ou a mensagem do prompt).
- Rodapé: projeto, branch git e hora.
- Mascote do Claude no corpo e logo da Anthropic no cabeçalho.
- Som padrão `Cloud` em todos os eventos (só muda se você trocar). Som de alerta
  distinto ao aguardar você é opcional (`CCN_ALERT=1`).
- Tempo da resposta no rodapé (ex.: `2m30s`).
- Filtro por duração: opcionalmente só notifica respostas que demoraram.
- Clicar na notificação foca a aba/janela da sessão (Windows Terminal via UI
  Automation, pelo título; fallback para outras janelas).
- Comando `/ccn` para configurar tudo sem editar arquivo.

Dispara em dois momentos:

| Evento | Quando | Corpo |
|--------|--------|-------|
| `Stop` | Claude termina de responder | trecho da última resposta |
| `Notification` | Claude fica aguardando você (ex.: pedido de permissão) | mensagem do Claude |

## Requisitos

- Windows 10/11 com WSL2
- `powershell.exe` acessível no PATH do WSL (padrão)
- `jq` (`sudo apt install jq`)

## Instalação

### Opção 1 — Plugin (recomendado)

No próprio Claude Code:

```
/plugin marketplace add blpsoares/claude-code-notifications
/plugin install claude-code-notifications@blpsoares
```

O hook é registrado automaticamente, sem mexer no `settings.json`. Na primeira
execução o script se auto-configura no lado Windows (copia os assets e registra
o AppID).

### Opção 2 — Manual (`install.sh`)

```bash
git clone https://github.com/blpsoares/claude-code-notifications.git
cd claude-code-notifications
bash install.sh
```

Depois abra o menu `/hooks` (ou reinicie) para recarregar. O instalador é
idempotente e faz backup do `settings.json`.

Não use as duas formas ao mesmo tempo. Se instalou pelo `install.sh` e depois
quer o plugin, rode `bash uninstall.sh` antes, para evitar notificação
duplicada.

## Como funciona

| Peça | Onde fica | Papel |
|------|-----------|-------|
| `scripts/notify.sh` | plugin (ou `~/.claude/hooks/`) | Hook `Stop`/`Notification`; lê o JSON do evento, extrai os dados e dispara o toast via `powershell.exe`. Auto-configura o Windows na primeira execução. |
| `claude-logo.png` / `anthropic.png` | `%LOCALAPPDATA%\claude-code-notifications\` | Mascote (corpo do toast) e logo Anthropic (ícone do cabeçalho). |
| `Cloud.wav` / `Alert.wav` | `%LOCALAPPDATA%\claude-code-notifications\` | Sons padrão: `Cloud` ao terminar, `Alert` ao aguardar você. |
| `scripts/ccn-config.sh` + `commands/ccn.md` | plugin | Implementam o comando `/ccn`. |
| AppID `Claude.Code.Notifications` | registro `HKCU` | AUMID registrado (nome "Claude Code" + ícone Anthropic). Sem isso o Windows descarta o toast. |
| `focus.ps1` / `focus.vbs` + protocolo `claudecodenotify://` | `%LOCALAPPDATA%\...` e `HKCU` | Clique na notificação foca a aba/janela da sessão. |
| `hooks/hooks.json` | plugin | Registra `Stop` + `Notification` automaticamente. No modo manual, vão para `~/.claude/settings.json`. |

## Comando `/ccn`

Com o plugin instalado, configure sem editar arquivo:

```
/ccn status              mostra a configuração atual
/ccn on | off            liga/desliga as notificações
/ccn test                dispara um toast de teste
/ccn threshold 30        só notifica no Stop se a resposta demorou >= 30s
/ccn duration on|off     mostra/oculta a duração no rodapé
/ccn buttons on|off      botões Sim / Sim sempre / Não no prompt de permissão
/ccn click on|off        clicar na notificação foca a aba/janela da sessão
/ccn sound <nome>        default | silent | im | mail | reminder | alarm | call
/ccn sound-file <path>   usa um .wav próprio
```

## Personalização

Alternativa ao `/ccn`: as variáveis no `~/.claude/hooks/ccn.config`.

- `CCN_ENABLED=0` desliga as notificações.
- `CCN_MIN_SECONDS=30` no `Stop`, só notifica se a resposta demorou >= 30s
  (padrão `0`, sempre). Não afeta o `Notification`.
- `CCN_SHOW_DURATION=0` oculta a duração no rodapé.
- `CCN_CLICK=0` desativa o clique-para-focar.
- `CCN_BUTTONS=0` desativa os botões de resposta no prompt de permissão.
- `CCN_ALERT=1` usa um som de alerta distinto (`Alert.wav`) no `Notification`
  (aguardando você). Sem isso, o som é sempre o `Cloud`.

### Som

O som padrão é o `Cloud.wav` (empacotado, um toque suave). Para trocar:

Sons prontos do Windows, via `CCN_SOUND`:

```bash
CCN_SOUND='ms-winsoundevent:Notification.IM'
CCN_SOUND='ms-winsoundevent:Notification.Mail'
CCN_SOUND='ms-winsoundevent:Notification.Reminder'
CCN_SOUND='ms-winsoundevent:Notification.Looping.Alarm'
CCN_SOUND=silent
```

Som customizado (qualquer `.wav`), via `CCN_SOUND_FILE` (caminho Windows ou WSL):

```bash
CCN_SOUND_FILE='C:\Windows\Media\tada.wav'
CCN_SOUND_FILE='/home/voce/sons/ping.wav'
```

`CCN_SOUND_FILE` tem prioridade sobre `CCN_SOUND`. O Windows só toca arquivos
próprios via `<audio>`, então o `.wav` customizado é tocado à parte com o
`SoundPlayer`.

### Outros

- Tamanho do trecho: `CCN_MAX_LEN=120` (padrão `220`).

## Não aparece nada?

Na ordem mais comum:

1. Notificações silenciadas ou Não Perturbe (Assistente de Foco). É a causa mais
   comum. Vá em Configurações, Sistema, Notificações, garanta que estão ligadas
   e desative o Não Perturbe, inclusive as regras de ativar automaticamente (ao
   jogar, app em tela cheia, duplicar a tela), que silenciam tudo sem avisar.
2. Config não recarregada. Se acabou de instalar, abra o menu `/hooks` (ou
   reinicie).
3. AppID. O instalador registra o AUMID `Claude.Code.Notifications` para que o
   Windows aceite o toast; toasts de AppID não registrado são descartados.

## Clicar na notificação para ir até a sessão

Clicar no toast foca a aba/janela da sessão que disparou a notificação. Como
funciona:

- No Windows Terminal, a aba certa é localizada pelo título (o Claude escreve o
  nome da sessão no título da aba) via UI Automation e selecionada por API,
  independente da posição da aba. Depois a janela é trazida para frente.
- Fora do Windows Terminal (ex.: terminal integrado do VS Code), há um fallback
  que foca a janela cujo título contém o nome da sessão.

O clique usa apenas APIs seguras (UI Automation e ativação de janela), sem
manipulação de foco de baixo nível.

Para desativar o clique, defina `CCN_CLICK=0` no `ccn.config`.

### Botões de resposta (prompt de permissão)

No evento `Notification` (o Claude pedindo permissão), a notificação traz os
botões **Sim**, **Sim, sempre** e **Não**. Ao clicar, o handler primeiro
seleciona a aba certa (mesma UI Automation do clique) e só então envia a tecla —
por isso a resposta vai para a sessão correta, não para a aba que estiver ativa.

- **Sim** envia `1` (a 1ª opção é sempre "sim").
- **Não** envia `Esc` (cancela em prompts de 2 ou 3 opções).
- **Sim, sempre** decide no clique: lê o texto do prompt e, se existir a opção
  "não perguntar de novo", usa ela (`2`); se o prompt só tiver Sim/Não, cai num
  Sim (`1`). Assim nunca seleciona a opção errada.

É best-effort: depende do prompt ainda estar aberto. Desative com
`CCN_BUTTONS=0`.

## Desinstalar

```bash
bash uninstall.sh
```

Remove os hooks (com backup) e o AppID registrado.

## Licença

MIT. Veja [LICENSE](LICENSE).
