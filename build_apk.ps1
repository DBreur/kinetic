# Bumps the version in pubspec.yaml and builds a release APK.
#
#   .\build_apk.ps1                 # 1.0.0+1 -> 1.0.0+2
#   .\build_apk.ps1 -Bump patch     # 1.0.0+1 -> 1.0.1+2
#   .\build_apk.ps1 -Bump minor     # 1.0.0+1 -> 1.1.0+2
#   .\build_apk.ps1 -Bump major     # 1.0.0+1 -> 2.0.0+2
#   .\build_apk.ps1 -Clean          # also runs flutter clean first
#
# The APK is also copied to releases\kinetic-<version>-b<build>.apk.
param(
    [ValidateSet('build', 'patch', 'minor', 'major')]
    [string]$Bump = 'build',
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$pubspec = Join-Path $PSScriptRoot 'pubspec.yaml'
$content = [IO.File]::ReadAllText($pubspec)

$match = [regex]::Match($content, '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)[ \t]*(?=\r?$)')
if (-not $match.Success) { throw 'No "version: x.y.z+n" line found in pubspec.yaml' }

$major = [int]$match.Groups[1].Value
$minor = [int]$match.Groups[2].Value
$patch = [int]$match.Groups[3].Value
$build = [int]$match.Groups[4].Value + 1  # versionCode must always increase

switch ($Bump) {
    'major' { $major++; $minor = 0; $patch = 0 }
    'minor' { $minor++; $patch = 0 }
    'patch' { $patch++ }
}

$old = "$($match.Groups[1].Value).$($match.Groups[2].Value).$($match.Groups[3].Value)+$($match.Groups[4].Value)"
$new = "$major.$minor.$patch+$build"
$content = $content.Remove($match.Index, $match.Length).Insert($match.Index, "version: $new")
[IO.File]::WriteAllText($pubspec, $content)
Write-Host "Version: $old -> $new"

Push-Location $PSScriptRoot
try {
    if ($Clean) { flutter clean }
    flutter pub get
    flutter build apk --release --dart-define-from-file=dart_defines.json
    if ($LASTEXITCODE -ne 0) { throw "flutter build failed (exit $LASTEXITCODE)" }

    # Copy with a recognisable name, e.g. releases\kinetic-1.0.0-b5.apk
    $releases = Join-Path $PSScriptRoot 'releases'
    New-Item -ItemType Directory -Force $releases | Out-Null
    $apkName = "kinetic-$major.$minor.$patch-b$build.apk"
    $apkPath = Join-Path $releases $apkName
    Copy-Item (Join-Path $PSScriptRoot 'build\app\outputs\flutter-apk\app-release.apk') $apkPath -Force
    Write-Host "Built APK $new -> releases\$apkName"
} finally {
    Pop-Location
}
