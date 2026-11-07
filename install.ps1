# Installe la Boite a Outils et ses programmes sur Windows.
#   Dans PowerShell :  irm https://aynide-glitch.github.io/install.ps1 | iex
# - installe GitHub CLI (acces aux versions privees) et FFmpeg
# - telecharge les versions deja compilees des programmes listes dans apps.tsv
# - si une version compilee manque, la compile sur ce PC (Git + outils C++ installes au besoin)
$ErrorActionPreference = "Stop"
$site = "https://aynide-glitch.github.io"
$tmp = Join-Path $env:TEMP ("bao-install-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Say($t) { Write-Host ""; Write-Host "== $t ==" -ForegroundColor Cyan }
function Fail($t) { Write-Host ""; Write-Host "ERREUR : $t" -ForegroundColor Red; Read-Host "Appuyez sur Entree pour fermer"; exit 1 }
function Get-Text($url) {
    $r = Invoke-WebRequest -UseBasicParsing $url
    return [Text.Encoding]::UTF8.GetString($r.RawContentStream.ToArray())
}
function Update-Path { $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User") }

# 1. GitHub CLI -----------------------------------------------------------------------------------------
Update-Path
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
    Say "Installation de GitHub CLI"
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Start-Process "https://cli.github.com"; Fail "winget est absent : installez GitHub CLI (cli.github.com) puis relancez." }
    winget install --id GitHub.cli --exact --silent --accept-package-agreements --accept-source-agreements
    Update-Path
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        $gh = Join-Path $env:ProgramFiles "GitHub CLI"
        if (Test-Path $gh) { $env:PATH = "$gh;$env:PATH" } else { Fail "GitHub CLI n'a pas pu etre installe." }
    }
}
gh auth status 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Say "Connexion a GitHub (le depot est prive)"
    Write-Host "Un code va s'afficher : copiez-le, appuyez sur Entree, puis collez-le dans la page qui s'ouvre."
    gh auth login --hostname github.com --git-protocol https --web
    if ($LASTEXITCODE -ne 0) { Fail "Connexion a GitHub impossible." }
}
gh auth setup-git 2>$null | Out-Null

# 2. FFmpeg ---------------------------------------------------------------------------------------------
$ffDir = Join-Path $env:APPDATA "BoiteAOutils\ffmpeg"
if (-not ((Test-Path (Join-Path $ffDir "ffmpeg.exe")) -and (Test-Path (Join-Path $ffDir "ffprobe.exe")))) {
    Say "Installation de FFmpeg"
    try {
        New-Item -ItemType Directory -Force -Path $ffDir | Out-Null
        $zip = Join-Path $tmp "ffmpeg.zip"
        Invoke-WebRequest -UseBasicParsing "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $zip
        $x = Join-Path $tmp "ffmpeg"
        Expand-Archive -Force $zip $x
        Get-ChildItem $x -Recurse -Include ffmpeg.exe, ffprobe.exe | ForEach-Object { Copy-Item $_.FullName $ffDir -Force }
        Write-Host "FFmpeg installe." -ForegroundColor Green
    } catch {
        Write-Host "FFmpeg n'a pas pu etre telecharge : la Boite a Outils proposera de l'installer (Reglages > FFmpeg)." -ForegroundColor Yellow
    }
}

# 3. Programmes de la liste -----------------------------------------------------------------------------
Say "Liste des programmes"
$lines = (Get-Text "$site/apps.tsv") -split "`r?`n"
$installed = @(); $failed = @()
$shell = New-Object -ComObject WScript.Shell
foreach ($line in $lines) {
    if ($line.Trim() -eq "" -or $line.StartsWith("#")) { continue }
    $f = $line -split "`t"
    if ($f.Count -lt 7) { continue }
    $id, $name, $repo, $asset, $exeName, $defs = $f[0], $f[1], $f[2], $f[4], $f[6], $(if ($f.Count -gt 7) { $f[7] } else { "" })
    Say $name
    $dir = Join-Path $env:LOCALAPPDATA ($exeName -replace '\.exe$', '')
    $target = Join-Path $dir $exeName
    $ok = $false
    try {
        $dl = Join-Path $tmp $id
        New-Item -ItemType Directory -Force -Path $dl | Out-Null
        gh release download --repo $repo --pattern $asset --dir $dl --clobber 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $dl $asset))) {
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $target } | Stop-Process -Force
            if (Test-Path $target) { Move-Item $target "$target.old-version" -Force }
            Expand-Archive -Force (Join-Path $dl $asset) $dir
            $ok = Test-Path $target
            if ($ok) { Write-Host "$name installe depuis la version compilee." -ForegroundColor Green }
        } else {
            Write-Host "Pas de version compilee pour $name : compilation sur ce PC (10 a 25 minutes)." -ForegroundColor Yellow
        }
    } catch { Write-Host ("Echec du telechargement : " + $_.Exception.Message) -ForegroundColor Yellow }
    if (-not $ok) {
        try {
            $script = Join-Path $tmp "build-app.ps1"
            Invoke-WebRequest -UseBasicParsing "$site/build-app.ps1" -OutFile $script
            $defList = @($defs -split '\s+' | Where-Object { $_ })
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Repo "https://github.com/$repo.git" -Branch main -Name ($exeName -replace '\.exe$', '') `
                -Product ($exeName -replace '\.exe$', '') -Target $target -Defines $defList -NoShortcuts
            $ok = Test-Path $target
        } catch { Write-Host ("Compilation impossible : " + $_.Exception.Message) -ForegroundColor Red }
    }
    if ($ok) {
        $installed += $name
        foreach ($folder in @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs"))) {
            $link = $shell.CreateShortcut((Join-Path $folder "$name.lnk"))
            $link.TargetPath = $target; $link.WorkingDirectory = $dir; $link.IconLocation = "$target,0"; $link.Save()
        }
        $key = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\" + ($exeName -replace '\.exe$', '')
        New-Item -Path $key -Force | Out-Null
        Set-ItemProperty -Path $key -Name DisplayName -Value $name
        Set-ItemProperty -Path $key -Name DisplayIcon -Value "$target,0"
        Set-ItemProperty -Path $key -Name Publisher -Value "Karim"
        Set-ItemProperty -Path $key -Name InstallLocation -Value $dir
        Set-ItemProperty -Path $key -Name UninstallString -Value "powershell.exe -NoProfile -Command `"Remove-Item -LiteralPath '$dir','$(Join-Path ([Environment]::GetFolderPath('Desktop')) "$name.lnk")','$(Join-Path ([Environment]::GetFolderPath('Programs')) "$name.lnk")','$key' -Recurse -Force`""
    } else { $failed += $name }
}
Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
Say "Termine"
foreach ($n in $installed) { Write-Host "OK : $n" -ForegroundColor Green }
foreach ($n in $failed) { Write-Host "ECHEC : $n (voir les messages ci-dessus)" -ForegroundColor Red }
Write-Host "Raccourcis crees sur le Bureau et dans le menu Demarrer."
if ($failed.Count -eq 0) { Start-Process (Join-Path $env:LOCALAPPDATA "BoiteAOutils\BoiteAOutils.exe") }
