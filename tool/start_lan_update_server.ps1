param(
    [string]$Root = 'E:\ai_music_updates',
    [int]$Port = 8788
)
$ErrorActionPreference = 'Stop'
$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($null -eq $pythonLauncher) { throw 'Python launcher py.exe was not found.' }
New-Item -ItemType Directory -Force -Path $Root | Out-Null
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
    throw "TCP port $Port is already in use."
}
& $pythonLauncher.Source -3 (Join-Path $PSScriptRoot 'lan_update_server.py') --root $Root --port $Port
exit $LASTEXITCODE
