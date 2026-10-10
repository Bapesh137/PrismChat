[CmdletBinding()]
param(
    [string]$Version,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"
$projectDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$repositoryDir = [System.IO.Path]::GetFullPath((Join-Path $projectDir ".."))
$targetDir = if ($env:CARGO_TARGET_DIR) {
    [System.IO.Path]::GetFullPath($env:CARGO_TARGET_DIR)
} else {
    Join-Path $projectDir "target"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $cargoToml = Get-Content -LiteralPath (Join-Path $projectDir "Cargo.toml") -Raw
    $match = [regex]::Match($cargoToml, '(?m)^version\s*=\s*"([^"]+)"')
    if (-not $match.Success) { throw "Could not read the package version from Cargo.toml" }
    $Version = $match.Groups[1].Value
}
$Version = $Version -replace '^v', ''
if ($Version -notmatch '^[0-9A-Za-z][0-9A-Za-z._-]*$') { throw "Invalid release version: $Version" }

$releaseDir = Join-Path $targetDir "releases"
$bundleName = "PrismChat-$Version-windows-x86_64"
$stageDir = Join-Path $releaseDir $bundleName
$releaseRoot = [System.IO.Path]::GetFullPath($releaseDir).TrimEnd('\') + '\'
$stageFull = [System.IO.Path]::GetFullPath($stageDir)
if (-not $stageFull.StartsWith($releaseRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to package outside the release directory"
}

if (-not $SkipBuild) {
    Push-Location $projectDir
    try {
        & cargo build --release --locked
        if ($LASTEXITCODE -ne 0) { throw "cargo build failed with exit code $LASTEXITCODE" }

        $cmakeDir = Join-Path $targetDir "frontend-release"
        & cmake --fresh -S frontend -B $cmakeDir -G "Visual Studio 17 2022" -A x64
        if ($LASTEXITCODE -ne 0) { throw "CMake configure failed with exit code $LASTEXITCODE" }
        & cmake --build $cmakeDir --config Release --target PrismChatUi PrismNotifier PrismChatLauncher --parallel
        if ($LASTEXITCODE -ne 0) { throw "CMake build failed with exit code $LASTEXITCODE" }
    } finally {
        Pop-Location
    }
}

$backend = Join-Path $targetDir "release\PrismChat.exe"
$frontendRelease = Join-Path $targetDir "frontend-release\Release"
$ui = Join-Path $frontendRelease "PrismChatUi.exe"
$notifier = Join-Path $frontendRelease "PrismNotifier.exe"
$launcher = Join-Path $frontendRelease "Start-PrismChat.exe"
foreach ($required in @($backend, $ui, $notifier, $launcher)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) { throw "Missing build output: $required" }
}

if (Test-Path -LiteralPath $stageFull) { Remove-Item -LiteralPath $stageFull -Recurse -Force }
New-Item -ItemType Directory -Path $stageFull -Force | Out-Null
Copy-Item -LiteralPath $backend, $ui, $notifier, $launcher -Destination $stageFull

$windeployqt = Get-Command windeployqt.exe -ErrorAction SilentlyContinue
if (-not $windeployqt) { $windeployqt = Get-Command windeployqt -ErrorAction SilentlyContinue }
if (-not $windeployqt) { throw "windeployqt was not found in PATH" }
$windeployqtPath = $windeployqt.Source
& $windeployqtPath --release --compiler-runtime --qmldir (Join-Path $projectDir "qml") (Join-Path $stageFull "PrismChatUi.exe")
if ($LASTEXITCODE -ne 0) { throw "windeployqt failed for PrismChatUi" }
& $windeployqtPath --release --compiler-runtime --no-translations (Join-Path $stageFull "PrismNotifier.exe")
if ($LASTEXITCODE -ne 0) { throw "windeployqt failed for PrismNotifier" }

$smokeStdOut = Join-Path $stageFull "smoke-test.stdout.log"
$smokeStdErr = Join-Path $stageFull "smoke-test.stderr.log"
$uiProcess = Start-Process -FilePath (Join-Path $stageFull "PrismChatUi.exe") `
    -WorkingDirectory $stageFull -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $smokeStdOut -RedirectStandardError $smokeStdErr
try {
    if ($uiProcess.WaitForExit(8000)) {
        $details = if (Test-Path -LiteralPath $smokeStdErr) {
            (Get-Content -LiteralPath $smokeStdErr -Raw).Trim()
        } else {
            ""
        }
        throw "PrismChatUi exited during startup with code $($uiProcess.ExitCode). $details"
    }
} finally {
    if (-not $uiProcess.HasExited) {
        Stop-Process -Id $uiProcess.Id -Force
        $uiProcess.WaitForExit()
    }
}
Remove-Item -LiteralPath $smokeStdOut, $smokeStdErr -Force -ErrorAction SilentlyContinue

$licenseDir = Join-Path $stageFull "licenses"
New-Item -ItemType Directory -Path $licenseDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $repositoryDir "LICENSE") -Destination $licenseDir
Copy-Item -LiteralPath (Join-Path $repositoryDir "THIRD_PARTY_NOTICES.md") -Destination $licenseDir
Copy-Item -LiteralPath (Join-Path $repositoryDir "LICENSES") -Destination $licenseDir -Recurse
Copy-Item -LiteralPath (Join-Path $projectDir "qml\assets\NotoEmoji-LICENSE.txt") -Destination $licenseDir
Copy-Item -LiteralPath (Join-Path $projectDir "qml\assets\NotoSansCJK-LICENSE.txt") -Destination $licenseDir

& python (Join-Path $projectDir "packaging\generate-rust-licenses.py") --manifest (Join-Path $projectDir "Cargo.toml") --output (Join-Path $licenseDir "rust-dependencies")
if ($LASTEXITCODE -ne 0) { throw "Could not collect Rust dependency licenses" }

$elementCallDir = Join-Path $projectDir "frontend\third_party\element-call"
$elementLicenseDir = Join-Path $licenseDir "element-call-package"
foreach ($name in @("LICENSE", "LICENSE.md", "LICENSE.txt", "NOTICE", "NOTICE.md", "NOTICE.txt", "package.json")) {
    $source = Join-Path $elementCallDir $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        New-Item -ItemType Directory -Path $elementLicenseDir -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $elementLicenseDir
    }
}

$qtRoot = if ($env:QT_ROOT_DIR) {
    [System.IO.Path]::GetFullPath($env:QT_ROOT_DIR)
} else {
    [System.IO.Directory]::GetParent([System.IO.Directory]::GetParent($windeployqtPath).FullName).FullName
}
$qtSbom = Join-Path $qtRoot "sbom"
if (Test-Path -LiteralPath $qtSbom -PathType Container) {
    $qtSbomDestination = Join-Path $licenseDir "qt-sbom"
    New-Item -ItemType Directory -Path $qtSbomDestination -Force | Out-Null
    Get-ChildItem -LiteralPath $qtSbom -Filter "*.spdx" -File | Copy-Item -Destination $qtSbomDestination
}

$archive = Join-Path $releaseDir "$bundleName.zip"
if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force }
Compress-Archive -LiteralPath $stageFull -DestinationPath $archive -CompressionLevel Optimal
$checksum = Get-FileHash -LiteralPath $archive -Algorithm SHA256
$checksumPath = "$archive.sha256"
[System.IO.File]::WriteAllText($checksumPath, "$($checksum.Hash.ToLowerInvariant())  $([System.IO.Path]::GetFileName($archive))`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "Created $archive"
Write-Host "Created $checksumPath"
