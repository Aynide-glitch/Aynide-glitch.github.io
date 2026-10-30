# Installe la Boite a Outils sur Windows : outils manquants (Git, compilateur C++), code, compilation,
# raccourcis sur le Bureau et dans le menu Demarrer.
#   Dans PowerShell :  irm https://aynide-glitch.github.io/install.ps1 | iex
$ErrorActionPreference = "Stop"
$script = Join-Path $env:TEMP "bao-build-app.ps1"
Invoke-WebRequest -UseBasicParsing "https://aynide-glitch.github.io/build-app.ps1" -OutFile $script
$target = Join-Path $env:LOCALAPPDATA "BoiteAOutils\BoiteAOutils.exe"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Repo "https://github.com/Aynide-glitch/boite-a-outils.git" `
    -Branch main -Name BoiteAOutils -Product BoiteAOutils -Target $target -Defines "-DBAO_BUILD_TESTS=OFF"
