@echo off
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0QuestSync.ps1"
echo Quest-Sync laeuft jetzt im Hintergrund. Dieses Fenster kannst du schliessen.
timeout /t 4 >nul
