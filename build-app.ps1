# Boite a Outils - compile an application of the toolbox from its source code and install it (Windows).
# Used for the toolbox itself and for Audionide, without GitHub Actions. Needs Git and the Visual Studio 2022 C++
# tools: when they are missing, the script offers to install them with winget.
#
#   powershell -ExecutionPolicy Bypass -File build-app.ps1 -Repo <url> -Branch main -Name Audionide -Product Audionide `
#              -Target C:\path\Audionide.exe [-Defines "-DX=1","-DY=2"] [-TagPrefix v0.3.]
param(
    [string]$Repo = "https://github.com/Aynide-glitch/boite-a-outils.git",
    [string]$Branch = "main",
    [string]$Name = "BoiteAOutils",
    [string]$Product = "BoiteAOutils",
    [string]$Target = "",
    [string[]]$Defines = @(),
    [string]$TagPrefix = "",
    [string]$BuildNumberVariable = "",
    [string]$DisplayName = "",
    [switch]$NoShortcuts
)

$ErrorActionPreference = "Stop"
# Name shown on the shortcuts (the script stays ASCII: Windows PowerShell 5 reads it as ANSI).
if ($DisplayName -eq "") {
    if ($Name -eq "BoiteAOutils") { $DisplayName = "Bo$([char]0xEE)te $([char]0xE0) Outils" } else { $DisplayName = $Name }
}
$Host.UI.RawUI.WindowTitle = "$Name - compilation locale"

function Stop-WithMessage([string]$text) {
    Write-Host ""
    Write-Host $text -ForegroundColor Red
    Read-Host "Appuyez sur Entree pour fermer"
    exit 1
}

function Require([string]$command, [string]$hint) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        Stop-WithMessage "Outil manquant : $command`n$hint"
    }
}

# ---- Prerequisites: Git and the Visual Studio 2022 C++ tools (with CMake), installed with winget when missing ----
function Update-PathFromRegistry {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:PATH = "$machine;$user"
}

$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
function Find-CppTools {
    if (-not (Test-Path $vswhere)) { return $null }
    $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($path) { return $path }
    return $null
}

function Use-BundledCMake {
    if (Get-Command cmake -ErrorAction SilentlyContinue) { return }
    $vs = Find-CppTools
    if ($vs) {
        $bundled = Join-Path $vs "Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin"
        if (Test-Path $bundled) { $env:PATH = "$bundled;$env:PATH" }
    }
}

function Install-Prerequisites([bool]$needGit, [bool]$needCpp) {
    Write-Host ""
    Write-Host "== Outils necessaires ==" -ForegroundColor Cyan
    if ($needGit) { Write-Host " - Git (telechargement du code)" }
    if ($needCpp) { Write-Host " - Build Tools Visual Studio 2022, 'Developpement Desktop en C++' (compilateur + CMake, environ 6 Go)" }
    $answer = Read-Host "Les installer automatiquement maintenant ? (O/n)"
    if ($answer -match '^[nN]') {
        Stop-WithMessage "Installation annulee. Git : https://git-scm.com/download/win`nBuild Tools : https://visualstudio.microsoft.com/fr/downloads/ (charge de travail 'Developpement Desktop en C++')"
    }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Start-Process "https://git-scm.com/download/win"
        Start-Process "https://visualstudio.microsoft.com/fr/downloads/"
        Stop-WithMessage "winget (App Installer) est absent : installez les outils depuis les pages ouvertes, puis relancez."
    }
    $common = @("--exact", "--silent", "--accept-package-agreements", "--accept-source-agreements")
    if ($needGit) {
        Write-Host "Installation de Git..." -ForegroundColor Cyan
        winget install --id Git.Git @common
    }
    if ($needCpp) {
        $workload = "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        $setup = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\setup.exe"
        $existing = $null
        if (Test-Path $vswhere) { $existing = & $vswhere -latest -products * -property installationPath }
        Write-Host "Installation des outils C++ (plusieurs minutes, Windows peut demander une autorisation)..." -ForegroundColor Cyan
        if ($existing -and (Test-Path $setup)) {
            # Visual Studio / Build Tools already there without the C++ workload: add it.
            $process = Start-Process $setup -ArgumentList "modify --installPath `"$existing`" $workload --passive --norestart" -Verb RunAs -PassThru -Wait
            if ($process.ExitCode -ne 0 -and $process.ExitCode -ne 3010) { Write-Host "Code de retour de l'installateur : $($process.ExitCode)" -ForegroundColor Yellow }
        } else {
            winget install --id Microsoft.VisualStudio.2022.BuildTools @common --override "--wait --passive --norestart $workload"
        }
    }
    Update-PathFromRegistry
}

Use-BundledCMake
$needGit = -not (Get-Command git -ErrorAction SilentlyContinue)
$needCpp = -not (Find-CppTools)
if ($needGit -or $needCpp) {
    Install-Prerequisites $needGit $needCpp
    Use-BundledCMake
}
Require git "Git n'a pas pu etre installe : https://git-scm.com/download/win (puis relancez)"
if (-not (Find-CppTools)) {
    Stop-WithMessage "Les outils C++ ne sont pas encore prets. Si Windows demande un redemarrage, redemarrez puis relancez.`nSinon : https://visualstudio.microsoft.com/fr/downloads/ (charge de travail 'Developpement Desktop en C++')"
}
Require cmake "CMake est introuvable : dans Visual Studio Installer, ajoutez 'Outils CMake C++ pour Windows', puis relancez."

$root = Join-Path $env:LOCALAPPDATA "$Name\source"
Write-Host "== Recuperation du code ($Branch) ==" -ForegroundColor Cyan
try {
    if (Test-Path (Join-Path $root ".git")) {
        git -C $root fetch --tags origin $Branch
        if ($LASTEXITCODE -ne 0) { throw "git fetch" }
        git -C $root checkout -B $Branch "origin/$Branch"
        git -C $root reset --hard "origin/$Branch"
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $root) | Out-Null
        git clone --branch $Branch $Repo $root
        if ($LASTEXITCODE -ne 0) { throw "git clone" }
    }
} catch {
    Stop-WithMessage "Impossible de recuperer le code. Le depot est prive : connectez-vous a GitHub quand Git le demande, puis relancez."
}
$commit = (git -C $root log -1 --format="%h").Trim()
Write-Host ("Version du code : " + (git -C $root log -1 --format="%h %s"))

# Same patch number as the latest published release, so an in-app updater still offers the next one.
$build = 0
if ($TagPrefix -ne "") {
    foreach ($tag in (git -C $root tag --list "$TagPrefix*")) {
        $n = 0
        if ([int]::TryParse(($tag.Substring($TagPrefix.Length)), [ref]$n) -and $n -gt $build) { $build = $n }
    }
}
$extra = @()
if ($BuildNumberVariable -ne "") { $extra += "-D$BuildNumberVariable=$build" }
$extra += $Defines | ForEach-Object { $_ -replace '\{BRANCH\}', $Branch -replace '\{COMMIT\}', $commit }

Write-Host "== Configuration ==" -ForegroundColor Cyan
cmake -S $root -B (Join-Path $root "build") -DCMAKE_BUILD_TYPE=Release @extra
if ($LASTEXITCODE -ne 0) { Stop-WithMessage "La configuration CMake a echoue (Visual Studio 2022 / Build Tools installes ?)." }

Write-Host "== Compilation (plusieurs minutes la premiere fois) ==" -ForegroundColor Cyan
cmake --build (Join-Path $root "build") --config Release --target $Product --parallel
if ($LASTEXITCODE -ne 0) { Stop-WithMessage "La compilation a echoue. Copiez les erreurs ci-dessus pour les signaler." }

$built = Join-Path $root "build\${Product}_artefacts\Release\$Product.exe"
if (-not (Test-Path $built)) { Stop-WithMessage "Executable introuvable : $built" }

if ($Target -eq "") { $Target = Join-Path $env:LOCALAPPDATA "$Name\$Product.exe" }
$running = Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Target }
if ($running) {
    Write-Host ""
    Write-Host "Compilation terminee. Fermez $Name pour installer la nouvelle version..." -ForegroundColor Yellow
    while (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $Target }) { Start-Sleep -Milliseconds 500 }
}

Write-Host "== Installation ==" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $Target) | Out-Null
if (Test-Path $Target) {
    $backup = "$Target.old-version"
    if (Test-Path $backup) { Remove-Item $backup -Force }
    Rename-Item $Target $backup
}
Copy-Item $built $Target -Force
Write-Host "$Name installe : $Target" -ForegroundColor Green
# Shortcuts (desktop + Start menu) and an entry in "Installed apps" with an uninstaller.
if (-not $NoShortcuts) {
    try {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($folder in @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs"))) {
            $link = $shell.CreateShortcut((Join-Path $folder "$DisplayName.lnk"))
            $link.TargetPath = $Target
            $link.WorkingDirectory = Split-Path $Target
            $link.IconLocation = "$Target,0"
            $link.Description = $DisplayName
            $link.Save()
        }
        Write-Host "Raccourcis crees sur le Bureau et dans le menu Demarrer." -ForegroundColor Green

        $installDir = Split-Path $Target
        $uninstaller = Join-Path $installDir "Desinstaller-$Name.ps1"
        $desktopLink = Join-Path ([Environment]::GetFolderPath("Desktop")) "$DisplayName.lnk"
        $menuLink = Join-Path ([Environment]::GetFolderPath("Programs")) "$DisplayName.lnk"
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$Name"
        @"
`$ErrorActionPreference = "SilentlyContinue"
Get-Process | Where-Object { `$_.Path -eq "$Target" } | Stop-Process -Force
Remove-Item -LiteralPath "$desktopLink", "$menuLink", "$Target", "$Target.old-version" -Force
Remove-Item -LiteralPath "$key" -Recurse -Force
Write-Host "$Name a ete desinstalle. Vos fichiers, reglages et videos ne sont pas touches."
Start-Sleep -Seconds 3
Remove-Item -LiteralPath `$MyInvocation.MyCommand.Path -Force
"@ | Set-Content -LiteralPath $uninstaller -Encoding UTF8

        New-Item -Path $key -Force | Out-Null
        $version = (Get-Item $Target).VersionInfo.ProductVersion
        if (-not $version) { $version = $commit }
        Set-ItemProperty -Path $key -Name DisplayName -Value $DisplayName
        Set-ItemProperty -Path $key -Name DisplayIcon -Value "$Target,0"
        Set-ItemProperty -Path $key -Name DisplayVersion -Value $version
        Set-ItemProperty -Path $key -Name Publisher -Value "Karim"
        Set-ItemProperty -Path $key -Name InstallLocation -Value $installDir
        Set-ItemProperty -Path $key -Name UninstallString -Value "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$uninstaller`""
        Set-ItemProperty -Path $key -Name NoModify -Value 1 -Type DWord
        Set-ItemProperty -Path $key -Name NoRepair -Value 1 -Type DWord
    } catch {
        Write-Host ("Raccourcis non crees : " + $_.Exception.Message) -ForegroundColor Yellow
    }
}

Start-Process $Target
Start-Sleep -Seconds 2
