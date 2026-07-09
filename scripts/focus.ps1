# claude-code-notifications - focus.ps1
# Acionado pelo protocolo claudecodenotify:// ao clicar no toast/botões.
#   focus?title=<enc>            -> foca a aba/janela da sessão
#   answer?key=<1|always|esc>    -> foca e responde o prompt de permissão
#
# 1) Seleciona a aba do Windows Terminal pelo título (UI Automation).
# 2) Traz a janela para frente mesmo sem foco / em outra tela (SwitchToThisWindow).
# 3) Dá foco de teclado ao pane (UIA SetFocus) e envia a tecla com scan code
#    (keybd_event + MapVirtualKey) — sem isso a tecla não chega no ConPTY.
# Só envia a tecla se confirmar que o terminal virou foreground (senão não envia,
# para não digitar na janela errada). Sem AttachThreadInput. NUNCA encerra processos.
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
  [DllImport("user32.dll")] public static extern void SwitchToThisWindow(IntPtr h, bool fAltTab);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, IntPtr extra);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint uCode, uint uMapType);
  const int SW_RESTORE = 9;
  const byte VK_MENU = 0x12;
  const uint KEYEVENTF_KEYUP = 0x2;
  public static void Focus(IntPtr h) {
    if (h == IntPtr.Zero) return;
    if (IsIconic(h)) { ShowWindow(h, SW_RESTORE); }
    keybd_event(VK_MENU, 0, 0, IntPtr.Zero);
    keybd_event(VK_MENU, 0, KEYEVENTF_KEYUP, IntPtr.Zero);
    SwitchToThisWindow(h, true);
    BringWindowToTop(h);
    SetForegroundWindow(h);
  }
  public static bool IsFg(IntPtr h) { return GetForegroundWindow() == h; }
  static void Tap(byte vk) {
    byte scan = (byte)MapVirtualKey(vk, 0);
    keybd_event(vk, scan, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(40);
    keybd_event(vk, scan, KEYEVENTF_KEYUP, IntPtr.Zero);
  }
  public static void SendDigit(char c) { Tap((byte)c); }
  public static void SendEsc() { Tap(0x1B); }
}
"@ | Out-Null

# 1) selecionar a aba pelo título via UI Automation
$targetHwnd = [IntPtr]::Zero
$targetWin = $null
try {
  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $winCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty, "CASCADIA_HOSTING_WINDOW_CLASS")
  $tabCond = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::TabItem)
  foreach ($w in $root.FindAll([System.Windows.Automation.TreeScope]::Children, $winCond)) {
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
} catch {}

# fallback: janela cujo título contém o título da sessão
if ($targetHwnd -eq [IntPtr]::Zero) {
  $p = Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$title*" } | Select-Object -First 1
  if ($p) { $targetHwnd = $p.MainWindowHandle }
}
if ($targetHwnd -eq [IntPtr]::Zero) { exit }

# 2) trazer para frente, com verificação (essencial quando está sem foco / outra tela)
$fg = $false
for ($i = 0; $i -lt 12 -and -not $fg; $i++) {
  [Win]::Focus($targetHwnd)
  Start-Sleep -Milliseconds 90
  $fg = [Win]::IsFg($targetHwnd)
}

# 3) responder o prompt — só se o terminal está mesmo em foco
if ((-not [string]::IsNullOrWhiteSpace($key)) -and $fg) {
  # pane ativo (TermControl visível)
  $pane = $null
  try {
    $tcCond = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ClassNameProperty, "TermControl")
    foreach ($tc in $targetWin.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tcCond)) {
      if (-not $tc.Current.IsOffscreen) { $pane = $tc; break }
    }
  } catch {}
  if ($pane) { try { $pane.SetFocus() } catch {} }   # foco de teclado no pane
  Start-Sleep -Milliseconds 350

  $send = $null
  if ($key -eq 'esc') { $send = 'esc' }
  elseif ($key -eq '1') { $send = '1' }
  elseif ($key -eq 'always') {
    $send = '1'
    if ($pane) {
      try {
        $txt = ($pane.GetCurrentPattern([System.Windows.Automation.TextPattern]::Pattern)).DocumentRange.GetText(-1)
        if ($txt -match "(?i)don'?t ask again|n[ãa]o perguntar") { $send = '2' }
      } catch {}
    }
  }
  if ($send -eq 'esc') { [Win]::SendEsc() }
  elseif ($send) { [Win]::SendDigit([char]$send[0]) }
}
