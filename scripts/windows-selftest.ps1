# Install the U-file NSIS installer on a Windows runner and run the app's
# own end-to-end check (src/selftest.ts): organize, undo, duplicates, Recycle
# Bin, FilmCraft editing and export. Also checks the Explorer context menu
# the installer registers. Writes the report and screenshots to $Out.
#
#   scripts/windows-selftest.ps1 <setup.exe> <fixtures-dir> <output-dir>
param(
  [Parameter(Mandatory)] [string] $Installer,
  [Parameter(Mandatory)] [string] $Fixtures,
  [Parameter(Mandatory)] [string] $Out
)
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $Out | Out-Null
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

function Save-Screen([string] $path) {
  try {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bitmap.Dispose()
  } catch {}
}

Write-Output '== install'
Start-Process -FilePath $Installer -ArgumentList '/S' -Wait
$exe = Get-ChildItem -Path $env:LOCALAPPDATA -Filter 'U-file.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { throw 'FAIL: U-file.exe was not installed' }
Write-Output "installed: $($exe.FullName)"

# The Explorer "U-file로 정리" entry must start the installed program.
$command = (Get-ItemProperty 'HKCU:\Software\Classes\Directory\shell\U-file\command').'(default)'
if ($command -notlike "*`"$($exe.FullName)`" --organize*") { throw "FAIL: context menu runs: $command" }
Write-Output "ok: context menu runs $command"

Write-Output '== test files'
$base = Join-Path $HOME 'Download\ufile-selftest'
$data = Join-Path $base 'data'
$saved = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads\U-file'
Remove-Item -Recurse -Force $base, $saved -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $data | Out-Null
Copy-Item (Join-Path $Fixtures '*') $data
New-Item -ItemType File (Join-Path $base 'RUN_SELFTEST') | Out-Null

Write-Output '== run'
$app = Start-Process -FilePath $exe.FullName -PassThru
$report = Join-Path $saved 'U-file-selftest.json'
$progress = Join-Path $base 'progress.log'
for ($round = 1; $round -le 120; $round++) {
  Start-Sleep -Seconds 20
  Save-Screen (Join-Path $Out ('screen-{0:d3}.png' -f $round))
  if (Test-Path $report) { Copy-Item $report (Join-Path $Out 'selftest.json'); break }
  if ($app.HasExited) { Write-Output "FAIL: U-file exited (code $($app.ExitCode))"; break }
  # The page logs as soon as it loads; silence after 2 minutes means it never ran.
  if ($round -ge 6 -and -not (Test-Path $progress)) { Write-Output "FAIL: the app's page did not start the self-test"; break }
}
Save-Screen (Join-Path $Out 'screen-final.png')
Write-Output '== progress.log'
if (Test-Path $progress) { Get-Content $progress -Encoding utf8; Copy-Item $progress $Out } else { Write-Output '(none)' }
if (-not $app.HasExited) { Stop-Process -Id $app.Id -Force -ErrorAction SilentlyContinue }

$result = Join-Path $Out 'selftest.json'
if (-not (Test-Path $result)) { throw 'FAIL: the self-test did not finish within 40 minutes' }
Get-Content $result -Encoding utf8
if (-not (Get-Content $result -Raw -Encoding utf8 | ConvertFrom-Json).ok) { throw 'FAIL: a self-test step failed' }
Write-Output '== all checks passed'
