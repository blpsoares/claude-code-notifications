# claude-code-notifications - focus.ps1
# Acionado pelo protocolo claudecodenotify:// ao clicar no toast/botões.
#   focus?title=<enc>            -> foca a aba/janela da sessão
#   answer?key=<1|always|esc>    -> foca e responde o prompt de permissão
#
# Seleciona a aba certa do Windows Terminal pelo título (UI Automation) e traz a
# janela para frente (foco seguro, sem AttachThreadInput). Para os botões, envia
# a tecla ao prompt com keybd_event (evento de teclado real, chega no terminal).
# Fallback: janela cujo título contenha o título da sessão. NUNCA encerra processos.
param([string]$Uri)

$title = ""
if ($Uri -match 'title=([^&]*)') { $title = [System.Uri]::UnescapeDataString($matches[1]) }
$key = ""
if ($Uri -match 'key=([^&]*)')   { $key   = [System.Uri]::UnescapeDataString($matches[1]) }
if ([string]::IsNullOrWhiteSpace($title)) { exit }

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
    if (IsIconic(h)) { ShowWindow(h, SW_RESTORE); }
    keybd_event(VK_MENU, 0, 0, IntPtr.Zero);          // "toque de ALT" destrava o foreground
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
    BringWindowToTop(h);
    SetForegroundWindow(h);
  }
  public static void SendDigit(char c) {
    byte vk = (byte)c;                                 // '1'=0x31, '2'=0x32
    keybd_event(vk, 0, 0, IntPtr.Zero);
    keybd_event(vk, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
  }
  public static void SendEsc() {
    keybd_event(0x1B, 0, 0, IntPtr.Zero);
    keybd_event(0x1B, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
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
    foreach ($t in $w.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tabCond)) {
      if ($t.Current.Name -like "*$title*") {
        try { $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select() } catch {}
        $targetHwnd = [IntPtr]$w.Current.NativeWindowHandle
        $targetWin = $w
        break
      }
    }
    if ($targetHwnd -ne [IntPtr]::Zero) { break }
  }
} catch { }

# 2) trazer a janela para frente
$focused = $false
if ($targetHwnd -ne [IntPtr]::Zero) {
  [Win]::Focus($targetHwnd); $focused = $true
} else {
  $p = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$title*" } | Select-Object -First 1
  if ($p) { [Win]::Focus($p.MainWindowHandle); $focused = $true }
}

# 3) resposta ao prompt de permissão
#    1 = Sim (1ª opção) · esc = Não/cancela.
#    always = "Sim, sempre": usa a opção "não perguntar de novo" SE existir no
#    prompt (lê o texto do terminal); senão, cai num Sim (tecla 1).
if ($focused -and -not [string]::IsNullOrWhiteSpace($key)) {
  Start-Sleep -Milliseconds 500
  $send = $null
  if ($key -eq 'esc') { $send = 'esc' }
  elseif ($key -eq '1') { $send = '1' }
  elseif ($key -eq 'always') {
    $send = '1'
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
  if ($send -eq 'esc') { [Win]::SendEsc() }
  elseif ($send) { [Win]::SendDigit([char]$send[0]) }
}
