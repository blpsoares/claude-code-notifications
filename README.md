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
- Som distinto por evento: `Cloud` ao terminar, `Alert` ao aguardar você.
- Tempo da resposta no rodapé (ex.: `2m30s`).
- Filtro por duração: opcionalmente só notifica respostas que demoraram.
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
| `hooks/hooks.json` | plugin | Registra `Stop` + `Notification` automaticamente. No modo manual, vão para `~/.claude/settings.json`. |

## Comando `/ccn`

Com o plugin instalado, configure sem editar arquivo:

```
/ccn status              mostra a configuração atual
/ccn on | off            liga/desliga as notificações
/ccn test                dispara um toast de teste
/ccn threshold 30        só notifica no Stop se a resposta demorou >= 30s
/ccn duration on|off     mostra/oculta a duração no rodapé
/ccn sound <nome>        default | silent | im | mail | reminder | alarm | call
/ccn sound-file <path>   usa um .wav próprio
```

## Personalização

Alternativa ao `/ccn`: as variáveis no `~/.claude/hooks/ccn.config`.

- `CCN_ENABLED=0` desliga as notificações.
- `CCN_MIN_SECONDS=30` no `Stop`, só notifica se a resposta demorou >= 30s
  (padrão `0`, sempre). Não afeta o `Notification`.
- `CCN_SHOW_DURATION=0` oculta a duração no rodapé.

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

## Clicar na notificação para focar o terminal ou responder permissão

Foi avaliado e removido de propósito. O Windows Terminal roda todas as abas numa
única janela e não expõe API para ativar uma aba específica; só é possível focar
a janela, não a aba. Além disso, botões de resposta enviariam a tecla para a aba
que estivesse ativa, podendo responder a sessão errada. Por segurança e
confiabilidade, o projeto foca no que funciona de forma consistente: avisar você
na hora certa.

## Desinstalar

```bash
bash uninstall.sh
```

Remove os hooks (com backup) e o AppID registrado.

## Licença

MIT. Veja [LICENSE](LICENSE).
