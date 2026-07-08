# claude-code-notifications - focus.ps1
# Acionado pelo protocolo claudecodenotify://focus?title=<enc> ao clicar no toast.
# Foca a ABA certa do Windows Terminal pelo título (UI Automation), RESTAURA a
# janela se estiver minimizada e a traz para frente de forma confiável mesmo
# sendo chamado por um processo em background (handler do protocolo).
# Fallback: qualquer janela cujo título contenha o título da sessão (VS Code,
# conhost, etc.). Sem AttachThreadInput. NUNCA encerra processos.
param([string]$Uri)

$title = ""
if ($Uri -match 'title=([^&]*)') { $title = [System.Uri]::UnescapeDataString($matches[1]) }
$key = ""
if ($Uri -match 'key=([^&]*)')   { $key   = [System.Uri]::UnescapeDataString($matches[1]) }
if ([string]::IsNullOrWhiteSpace($title)) { exit }

# Helpers Win32: restaurar (se minimizada) + trazer para frente. O "toque de ALT"
# destrava a restrição de foreground do Windows para processos em background,
# sem precisar de AttachThreadInput (que pode travar se a thread-alvo estiver presa).
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  const int SW_RESTORE = 9;
  const byte VK_MENU = 0x12;
  const uint KEYEVENTF_KEYUP = 0x2;
  public static void Focus(IntPtr h) {
    if (h == IntPtr.Zero) return;
    if (IsIconic(h)) { ShowWindow(h, SW_RESTORE); }   // restaura sem alterar posição
    keybd_event(VK_MENU, 0, 0, IntPtr.Zero);          // ALT down
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, IntPtr.Zero); // ALT up
    BringWindowToTop(h);
    SetForegroundWindow(h);
  }
}
"@ | Out-Null

# 1) Windows Terminal: selecionar a aba pelo título via UI Automation
$targetHwnd = [IntPtr]::Zero
$targetWin = $null
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
        try {
          $sel = $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
          $sel.Select()
        } catch { }
        $targetHwnd = [IntPtr]$w.Current.NativeWindowHandle
        $targetWin = $w
        break
      }
    }
    if ($targetHwnd -ne [IntPtr]::Zero) { break }
  }
} catch { }

# 2) trazer a janela para frente (restaura se minimizada)
$focused = $false
if ($targetHwnd -ne [IntPtr]::Zero) {
  [Win]::Focus($targetHwnd); $focused = $true
} else {
  # fallback: janela cujo título contém o título da sessão
  $p = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$title*" } | Select-Object -First 1
  if ($p) { [Win]::Focus($p.MainWindowHandle); $focused = $true }
}

# 3) botão de resposta: com a aba/janela CERTA já em foco, envia a tecla ao prompt.
#    1 = Sim (1ª opção) · esc = Não/cancela.
#    always = "Sim, sempre": usa a opção "não perguntar de novo" SE ela existir no
#    prompt (lê o texto do terminal); se só houver Sim/Não, cai num Sim (tecla 1).
if ($focused -and -not [string]::IsNullOrWhiteSpace($key)) {
  Start-Sleep -Milliseconds 400
  $wsh = New-Object -ComObject WScript.Shell
  $send = $null
  if ($key -eq 'esc') { $send = '{ESC}' }
  elseif ($key -eq '1') { $send = '1' }
  elseif ($key -eq 'always') {
    $send = '1'   # fallback: Sim
    try {
      if ($targetWin) {
        $tcCond = New-Object System.Windows.Automation.PropertyCondition(
          [System.Windows.Automation.AutomationElement]::ClassNameProperty, "TermControl")
        foreach ($tc in $targetWin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tcCond)) {
          if (-not $tc.Current.IsOffscreen) {
            $txt = ($tc.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)).DocumentRange.GetText(-1)
            if ($txt -match "(?i)don'?t ask again|n[ãa]o perguntar") { $send = '2' }
            break
          }
        }
      }
    } catch { }
  }
  if ($send) { $wsh.SendKeys($send) }
}
