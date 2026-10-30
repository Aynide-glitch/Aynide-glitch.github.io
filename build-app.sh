#!/bin/bash
# Boite a Outils - compile an application of the toolbox from its source code and install it (macOS).
# Needs the Xcode command line tools and CMake (installed with Homebrew when available).
#
#   build-app.sh <repo-url> <branch> <name> <product> <target.app> [cmake -D options...]
# "{BRANCH}" and "{COMMIT}" in the options are replaced.
set -u
REPO="${1:-https://github.com/Aynide-glitch/boite-a-outils.git}"
BRANCH="${2:-main}"
NAME="${3:-BoiteAOutils}"
PRODUCT="${4:-BoiteAOutils}"
TARGET="${5:-/Applications/$PRODUCT.app}"
shift 5 2>/dev/null || shift $#
DEFINES=("$@")

fail() {
    echo ""
    echo "ERREUR : $1"
    read -r -p "Appuyez sur Entree pour fermer" _
    exit 1
}

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! xcode-select -p >/dev/null 2>&1; then
    echo "Les outils de developpement d'Apple sont necessaires : une fenetre va proposer de les installer."
    xcode-select --install
    fail "Relancez la compilation une fois l'installation des outils terminee."
fi
if ! command -v cmake >/dev/null 2>&1; then
    if command -v brew >/dev/null 2>&1; then
        echo "== Installation de CMake (Homebrew) =="
        brew install cmake || fail "Installation de CMake impossible."
    else
        fail "CMake est introuvable. Installez Homebrew (https://brew.sh) puis relancez, ou installez CMake depuis https://cmake.org/download/."
    fi
fi

ROOT="$HOME/Library/Application Support/$NAME/source"
echo "== Recuperation du code ($BRANCH) =="
if [ -d "$ROOT/.git" ]; then
    git -C "$ROOT" fetch --tags origin "$BRANCH" || fail "Impossible de recuperer le code (connexion GitHub ?)."
    git -C "$ROOT" checkout -B "$BRANCH" "origin/$BRANCH" && git -C "$ROOT" reset --hard "origin/$BRANCH"
else
    mkdir -p "$(dirname "$ROOT")"
    git clone --branch "$BRANCH" "$REPO" "$ROOT" || fail "Impossible de recuperer le code. Le depot est prive : connectez-vous a GitHub quand Git le demande."
fi
COMMIT="$(git -C "$ROOT" log -1 --format=%h)"
echo "Version du code : $(git -C "$ROOT" log -1 --format='%h %s')"

ARGS=()
for d in "${DEFINES[@]+"${DEFINES[@]}"}"; do
    d="${d//\{BRANCH\}/$BRANCH}"
    ARGS+=("${d//\{COMMIT\}/$COMMIT}")
done

echo "== Configuration =="
cmake -S "$ROOT" -B "$ROOT/build" -DCMAKE_BUILD_TYPE=Release "${ARGS[@]+"${ARGS[@]}"}" || fail "La configuration CMake a echoue."
echo "== Compilation (plusieurs minutes la premiere fois) =="
cmake --build "$ROOT/build" --config Release --target "$PRODUCT" --parallel "$(sysctl -n hw.ncpu)" || fail "La compilation a echoue. Copiez les erreurs ci-dessus pour les signaler."

BUILT="$(find "$ROOT/build/${PRODUCT}_artefacts" -maxdepth 2 -name "$PRODUCT.app" -type d | head -1)"
[ -n "$BUILT" ] || fail "Application introuvable dans $ROOT/build/${PRODUCT}_artefacts"

if pgrep -f "$TARGET/Contents/MacOS" >/dev/null 2>&1; then
    echo ""
    echo "Compilation terminee. Fermez $NAME pour installer la nouvelle version..."
    while pgrep -f "$TARGET/Contents/MacOS" >/dev/null 2>&1; do sleep 1; done
fi

echo "== Installation =="
mkdir -p "$(dirname "$TARGET")"
if [ -d "$TARGET" ]; then
    rm -rf "$TARGET.old-version"
    mv "$TARGET" "$TARGET.old-version"
fi
cp -R "$BUILT" "$TARGET" || fail "Copie impossible vers $TARGET"
xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
echo "$NAME installe : $TARGET (Launchpad, Spotlight)"
# Icon in the Dock, once.
if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "$TARGET"; then
    defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$TARGET</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
    killall Dock 2>/dev/null
    echo "Icone ajoutee au Dock."
fi
open "$TARGET"
sleep 2
