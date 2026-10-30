#!/bin/bash
# Installe la Boite a Outils sur macOS (/Applications + Dock).
#   Dans le Terminal :  curl -fsSL https://aynide-glitch.github.io/install.sh | bash
set -e
curl -fsSL https://aynide-glitch.github.io/build-app.sh -o /tmp/bao-build-app.sh
bash /tmp/bao-build-app.sh https://github.com/Aynide-glitch/boite-a-outils.git main BoiteAOutils BoiteAOutils /Applications/BoiteAOutils.app \
    -DBAO_BUILD_TESTS=OFF < /dev/tty
