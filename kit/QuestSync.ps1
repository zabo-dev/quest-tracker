# Quest-Sync: lädt nach jedem /wp sync nur deinen Quest-Stand hoch (Level, Zone, Questlog, erledigte Quests), damit dein Kumpel sie mit seinen abgleichen kann.
# Läuft unsichtbar im Hintergrund, solange es gestartet ist. Beenden: im Task-Manager "Windows PowerShell" schließen.
$ErrorActionPreference = "Stop"
$Repo = "zabo-dev/quest-tracker"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$TokenFile = Join-Path $Here "token.txt"
$Log = Join-Path $Here "questsync.log"
function Write-Log($m) { "$(Get-Date -Format 'dd.MM. HH:mm:ss')  $m" | Add-Content -Path $Log -Encoding UTF8 }

if (-not (Test-Path $TokenFile)) {
  Add-Type -AssemblyName Microsoft.VisualBasic
  $t = [Microsoft.VisualBasic.Interaction]::InputBox("Füge den Token ein, den du von deinem Kumpel bekommen hast (beginnt mit github_pat_):", "Quest-Sync einrichten", "")
  if (-not $t) { exit }
  Set-Content -Path $TokenFile -Value $t.Trim() -Encoding ASCII
}
$Token = (Get-Content $TokenFile -Raw).Trim()
$Headers = @{ Authorization = "Bearer $Token"; Accept = "application/vnd.github+json"; "User-Agent" = "questsync" }

# find the WoW Forever SavedVariables file (default install folder first, then any drive)
$Candidates = @("C:\Program Files (x86)\World of Warcraft\_forever_", "C:\Program Files\World of Warcraft\_forever_") +
  (Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root "World of Warcraft\_forever_"; Join-Path $_.Root "Games\World of Warcraft\_forever_" })
function Find-File {
  foreach ($c in $Candidates) {
    $f = Get-ChildItem -Path (Join-Path $c "WTF\Account\*\SavedVariables\QuestShare.lua") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f) { return $f.FullName }
  }
}

Write-Log "gestartet"
$last = $null
while ($true) {
  try {
    $file = Find-File
    if ($file) {
      $stamp = (Get-Item $file).LastWriteTimeUtc
      if ($stamp -ne $last) {
        Start-Sleep -Seconds 2  # let WoW finish writing
        $bytes = [IO.File]::ReadAllBytes($file)
        $body = @{ message = "Quest-Sync $(Get-Date -Format 'dd.MM. HH:mm')"; content = [Convert]::ToBase64String($bytes) }
        try { $cur = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/contents/data/friend.lua" -Headers $Headers; $body.sha = $cur.sha } catch {}
        Invoke-RestMethod -Method Put -Uri "https://api.github.com/repos/$Repo/contents/data/friend.lua" -Headers $Headers -Body ($body | ConvertTo-Json) -ContentType "application/json" | Out-Null
        $last = $stamp
        Write-Log "hochgeladen ($([math]::Round($bytes.Length / 1KB)) KB)"
      }
    }
  } catch { Write-Log "Fehler: $($_.Exception.Message)" }
  Start-Sleep -Seconds 10
}
