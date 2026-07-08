' claude-code-notifications - focus.vbs
' Launcher que executa o focus.ps1 oculto (sem flash de janela).
' Registrado como handler do protocolo: wscript.exe focus.vbs "%1"
Set sh = CreateObject("WScript.Shell")
If WScript.Arguments.Count = 0 Then WScript.Quit
uri = WScript.Arguments(0)
ps1 = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\claude-code-notifications\focus.ps1"
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ """ & uri & """"
sh.Run cmd, 0, False
