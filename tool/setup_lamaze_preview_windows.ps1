param(
    [string]$Root = 'E:\AIModels\LamazeAudio'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$CosyVoiceUrl = 'https://github.com/FunAudioLLM/CosyVoice.git'
$CosyVoiceCommit = '074ca6dc9e80a2f424f1f74b48bdd7d3fea531cc'
$SftRepo = 'FunAudioLLM/CosyVoice-300M-SFT'
$SftRevision = 'fbb71de2afe387ed854eebd80b9f3d078c6b9869'
$InstructRepo = 'FunAudioLLM/CosyVoice-300M-Instruct'
$InstructRevision = '706bee1915e9fd1f1214929e2a0509c874cff433'
$VscoUrl = 'https://github.com/sgossner/VSCO-2-CE.git'
$VscoCommit = '6dd651d55dde97fd4028699be9d4481f26917891'
$SfizzUrl = 'https://github.com/sfztools/sfizz/releases/download/1.2.3/sfizz-1.2.3-win64.zip'

function Assert-LastExitCode {
    param([string]$Action)
    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE"
    }
}

function Ensure-PinnedRepository {
    param(
        [string]$Url,
        [string]$Path,
        [string]$Commit,
        [string]$Branch = ''
    )

    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
            throw "$Path exists but is not a Git repository"
        }
        $actualCommit = (git -C $Path rev-parse HEAD).Trim()
        Assert-LastExitCode "Read repository commit for $Path"
        if ($actualCommit -ne $Commit) {
            throw "$Path does not match pinned commit $Commit; found $actualCommit"
        }
        return
    }

    if ($Branch) {
        git clone --branch $Branch --single-branch $Url $Path
    } else {
        git clone --recursive $Url $Path
    }
    Assert-LastExitCode "Clone $Url"
    git -C $Path checkout $Commit
    Assert-LastExitCode "Checkout pinned commit for $Path"
    git -C $Path submodule update --init --recursive
    Assert-LastExitCode "Initialize submodules for $Path"
}

function Get-RequiredFileHash {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required file is missing: $Path"
    }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git is required'
}
if (-not (Get-Command py -ErrorAction SilentlyContinue)) {
    throw 'Python launcher is required'
}

$drive = Get-PSDrive -Name E
if ($drive.Free -lt 100GB) {
    throw 'E: must have at least 100GB free'
}

New-Item -ItemType Directory -Path $Root -Force | Out-Null
$CosyVoiceRoot = Join-Path $Root 'CosyVoice'
$VscoRoot = Join-Path $Root 'VSCO-2-CE'
$ModelsRoot = Join-Path $Root 'models'
$SftModel = Join-Path $ModelsRoot 'CosyVoice-300M-SFT'
$InstructModel = Join-Path $ModelsRoot 'CosyVoice-300M-Instruct'
$VenvRoot = Join-Path $Root 'venv-py310'
$Python = Join-Path $VenvRoot 'Scripts\python.exe'

Ensure-PinnedRepository -Url $CosyVoiceUrl -Path $CosyVoiceRoot -Commit $CosyVoiceCommit
Ensure-PinnedRepository -Url $VscoUrl -Path $VscoRoot -Commit $VscoCommit -Branch 'SFZ'

$installedPythons = (py -0p | Out-String)
Assert-LastExitCode 'List installed Python versions'
if ($installedPythons -notmatch '-3\.10-') {
    winget install --id Python.Python.3.10 --exact --scope user --silent --accept-package-agreements --accept-source-agreements
    Assert-LastExitCode 'Install Python 3.10'
}
py -3.10 -c "import sys; assert sys.version_info[:2] == (3, 10)"
Assert-LastExitCode 'Verify Python 3.10'

if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) {
    py -3.10 -m venv $VenvRoot
    Assert-LastExitCode 'Create Python 3.10 virtual environment'
}

& $Python -m pip install --upgrade 'pip==24.3.1'
Assert-LastExitCode 'Install pinned pip'

$requirementsPath = Join-Path $CosyVoiceRoot 'requirements.txt'
$requirementsHash = Get-RequiredFileHash $requirementsPath
$dependencyMarker = Join-Path $Root 'requirements-py310.sha256'
$installedHash = if (Test-Path -LiteralPath $dependencyMarker) {
    (Get-Content -LiteralPath $dependencyMarker -Raw).Trim()
} else {
    ''
}
if ($installedHash -ne $requirementsHash) {
    & $Python -m pip install --upgrade 'setuptools==65.5.0' 'wheel==0.45.1'
    Assert-LastExitCode 'Install pinned Python build tools'
    & $Python -m pip install --no-deps --no-build-isolation 'openai-whisper==20231117'
    Assert-LastExitCode 'Bootstrap pinned OpenAI Whisper'
    & $Python -m pip install -r $requirementsPath
    Assert-LastExitCode 'Install CosyVoice dependencies'
    & $Python -m pip install 'huggingface_hub==0.30.2'
    Assert-LastExitCode 'Install Hugging Face downloader'
    [IO.File]::WriteAllText($dependencyMarker, "$requirementsHash`n")
}

New-Item -ItemType Directory -Path $ModelsRoot -Force | Out-Null
$downloadScript = Join-Path $Root 'download_models.py'
$downloadCode = @'
import os

os.environ["HF_HUB_DOWNLOAD_TIMEOUT"] = "120"
os.environ["HF_HUB_ETAG_TIMEOUT"] = "120"

from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="FunAudioLLM/CosyVoice-300M-SFT",
    revision="fbb71de2afe387ed854eebd80b9f3d078c6b9869",
    local_dir=r"E:\AIModels\LamazeAudio\models\CosyVoice-300M-SFT",
    max_workers=1,
)
snapshot_download(
    repo_id="FunAudioLLM/CosyVoice-300M-Instruct",
    revision="706bee1915e9fd1f1214929e2a0509c874cff433",
    local_dir=r"E:\AIModels\LamazeAudio\models\CosyVoice-300M-Instruct",
    max_workers=1,
)
'@
if ($Root -ne 'E:\AIModels\LamazeAudio') {
    $escapedRoot = $Root.Replace('\', '\\')
    $downloadCode = $downloadCode.Replace('E:\\AIModels\\LamazeAudio', $escapedRoot)
}
[IO.File]::WriteAllText($downloadScript, $downloadCode, [Text.UTF8Encoding]::new($false))
& $Python $downloadScript
Assert-LastExitCode 'Download pinned CosyVoice models'

$SfizzArchive = Join-Path $Root 'sfizz-1.2.3-win64.zip'
$SfizzRoot = Join-Path $Root 'sfizz-1.2.3'
if (-not (Test-Path -LiteralPath $SfizzArchive -PathType Leaf)) {
    Invoke-WebRequest -UseBasicParsing -Uri $SfizzUrl -OutFile $SfizzArchive
}
if (-not (Test-Path -LiteralPath $SfizzRoot -PathType Container)) {
    Expand-Archive -LiteralPath $SfizzArchive -DestinationPath $SfizzRoot
}
$SfizzExe = Get-ChildItem -LiteralPath $SfizzRoot -Recurse -Filter 'sfizz_render.exe' |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $SfizzExe) {
    throw 'sfizz_render.exe was not found in the pinned release'
}

$ffmpegCommand = Get-Command ffmpeg -ErrorAction SilentlyContinue
if (-not $ffmpegCommand) {
    winget install --id Gyan.FFmpeg.Essentials --exact --scope user --silent --accept-package-agreements --accept-source-agreements
    Assert-LastExitCode 'Install FFmpeg'
    $ffmpegPackageRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    $ffmpegExe = Get-ChildItem -LiteralPath $ffmpegPackageRoot -Recurse -Filter 'ffmpeg.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $ffmpegExe) {
        throw 'FFmpeg was installed but ffmpeg.exe could not be located'
    }
    $env:Path = "$(Split-Path -Parent $ffmpegExe);$env:Path"
    $ffmpegCommand = Get-Command ffmpeg -ErrorAction Stop
}
$ffprobeCommand = Get-Command ffprobe -ErrorAction Stop

$requiredModelFiles = @('cosyvoice.yaml', 'llm.pt', 'flow.pt', 'hift.pt', 'spk2info.pt')
foreach ($modelPath in @($SftModel, $InstructModel)) {
    foreach ($filename in $requiredModelFiles) {
        Get-RequiredFileHash (Join-Path $modelPath $filename) | Out-Null
    }
}

$requiredPatches = @(
    'UprightPiano.sfz',
    'ViolinEnsSusVib-Quiet.sfz',
    'CelloEnsSusVib-Quiet.sfz'
)
$patchHashes = [ordered]@{}
foreach ($filename in $requiredPatches) {
    $patchHashes[$filename] = Get-RequiredFileHash (Join-Path $VscoRoot $filename)
}

$cudaCode = 'import json, torch; print(json.dumps(dict(available=torch.cuda.is_available(), name=torch.cuda.get_device_name(0) if torch.cuda.is_available() else None)))'
$cudaJson = (& $Python -c $cudaCode | Select-Object -Last 1)
Assert-LastExitCode 'Check PyTorch CUDA support'
$cuda = $cudaJson | ConvertFrom-Json
if (-not $cuda.available) {
    throw 'PyTorch CUDA is unavailable'
}
if ($cuda.name -ne 'NVIDIA GeForce RTX 3060 Ti') {
    throw "Expected NVIDIA GeForce RTX 3060 Ti; found $($cuda.name)"
}

$runtimeSources = [ordered]@{
    generatedAtUtc = [DateTime]::UtcNow.ToString('o')
    root = $Root
    python = $Python
    cosyVoice = [ordered]@{
        path = $CosyVoiceRoot
        commit = $CosyVoiceCommit
        license = 'Apache-2.0'
    }
    models = [ordered]@{
        sft = [ordered]@{ path = $SftModel; repo = $SftRepo; revision = $SftRevision; license = 'Apache-2.0' }
        instruct = [ordered]@{ path = $InstructModel; repo = $InstructRepo; revision = $InstructRevision; license = 'Apache-2.0' }
    }
    vsco2Ce = [ordered]@{
        path = $VscoRoot
        commit = $VscoCommit
        license = 'CC0-1.0'
        patchHashes = $patchHashes
    }
    sfizz = [ordered]@{
        executable = $SfizzExe
        archiveSha256 = Get-RequiredFileHash $SfizzArchive
        version = '1.2.3'
        license = 'BSD-2-Clause'
    }
    ffmpeg = [ordered]@{
        executable = $ffmpegCommand.Source
        ffprobe = $ffprobeCommand.Source
    }
    cuda = $cuda
    freeBytesOnE = (Get-PSDrive -Name E).Free
}
$runtimeManifest = Join-Path $Root 'runtime-sources.json'
[IO.File]::WriteAllText(
    $runtimeManifest,
    ($runtimeSources | ConvertTo-Json -Depth 8),
    [Text.UTF8Encoding]::new($false)
)

Write-Output ($runtimeSources | ConvertTo-Json -Depth 8 -Compress)
