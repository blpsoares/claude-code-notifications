# claude-code-notifications - focus.ps1
# Acionado pelo protocolo claudecodenotify://focus?title=<enc> ao clicar no toast.
# Foca a ABA certa do Windows Terminal pelo título (UI Automation), depois traz
# a janela para frente. Fallback: foca qualquer janela cujo título contenha o
# título da sessão (VS Code, conhost, etc.). Métodos seguros (sem AttachThreadInput).
param([string]$Uri)

$title = ""
if ($Uri -match 'title=([^&]*)') { $title = [System.Uri]::UnescapeDataString($matches[1]) }
if ([string]::IsNullOrWhiteSpace($title)) { exit }

$wsh = New-Object -ComObject WScript.Shell

# 1) Windows Terminal: selecionar a aba pelo título via UI Automation
$focusedPid = 0
try {
  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $winCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "CASCADIA_HOSTING_WINDOW_CLASS")
  $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)
  $tabCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::TabItem)
  foreach ($w in $wins) {
    $tabs = $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)
    foreach ($t in $tabs) {
      if ($t.Current.Name -like "*$title*") {
        $sel = $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $sel.Select()
        $focusedPid = $w.Current.ProcessId
        break
      }
    }
    if ($focusedPid) { break }
  }
} catch { }

# 2) trazer a janela para frente
if ($focusedPid) {
  $wsh.AppActivate([int]$focusedPid) | Out-Null
} else {
  # fallback: janela cujo título contém o título da sessão
  $p = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$title*" } | Select-Object -First 1
  if ($p) { $wsh.AppActivate($p.Id) | Out-Null }
}
