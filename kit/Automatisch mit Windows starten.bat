@echo off
set "LNK=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\Quest-Sync.lnk"
powershell -NoProfile -Command "$s=(New-Object -ComObject WScript.Shell).CreateShortcut($env:LNK); $s.TargetPath='powershell.exe'; $s.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0QuestSync.ps1\"'; $s.WindowStyle=7; $s.Save()"
echo Fertig: Quest-Sync startet ab jetzt mit Windows.
pause
