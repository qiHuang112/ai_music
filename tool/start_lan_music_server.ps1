param(
    [string]$Root = 'E:\music',
    [string]$HostAddress = '0.0.0.0',
    [int]$Port = 8787
)

$ErrorActionPreference = 'Stop'
$pythonLauncher = Get-Command py -ErrorAction SilentlyContinue
if ($null -eq $pythonLauncher) {
    throw 'Python launcher py.exe was not found.'
}
if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Music root does not exist: $Root"
}
if (Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue) {
    throw "TCP port $Port is already in use."
}

$server = Join-Path $PSScriptRoot 'lan_music_server.py'
Write-Host "Starting AI Music LAN library: http://$HostAddress`:$Port"
Write-Host "Music root: $Root"
& $pythonLauncher.Source -3 $server --root $Root --host $HostAddress --port $Port
exit $LASTEXITCODE
