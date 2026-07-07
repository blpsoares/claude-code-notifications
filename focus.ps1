# claude-code-notifications — focus.ps1
# Acionado pelo protocolo claudecodenotify:// (clique/botão da notificação).
#   claudecodenotify://focus?title=<enc>            -> foca o terminal da sessão
#   claudecodenotify://answer?key=<1|2|3>&title=... -> foca e responde o prompt
#
# Método de foco SEGURO: WScript.Shell.AppActivate (não usa AttachThreadInput,
# não desestabiliza o Windows Terminal). No pior caso, só não foca.
param([string]$Uri)

function Get-Q([string]$name) {
  if ($Uri -match "$name=([^&]*)") { return [System.Uri]::UnescapeDataString($matches[1]) }
  return ""
}

$title = Get-Q 'title'
$key   = Get-Q 'key'
if ([string]::IsNullOrWhiteSpace($title)) { exit }

# procura (read-only) a janela cujo título contém o título da sessão,
# priorizando hosts de terminal conhecidos (WSL ou CMD — casa por título).
$order = 'WindowsTerminal','wt','alacritty','wezterm','conhost','cmd','powershell','pwsh','Code'
$target = Get-Process |
  Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$title*" } |
  Sort-Object { $i = [array]::IndexOf($order, $_.ProcessName); if ($i -lt 0) { 99 } else { $i } } |
  Select-Object -First 1
if (-not $target) { exit }

$wsh = New-Object -ComObject WScript.Shell
$wsh.AppActivate($target.Id) | Out-Null   # foco seguro por PID

# botão de ação: envia o dígito para o prompt de permissão do Claude Code
if ($key -match '^[123]$') {
  Start-Sleep -Milliseconds 250
  $wsh.SendKeys($key)
}
