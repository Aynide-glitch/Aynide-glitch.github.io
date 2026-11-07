#!/bin/bash
# Installe la Boite a Outils et ses programmes sur macOS (Apple Silicon ou Intel).
#   bash -c "$(curl -fsSL https://aynide-glitch.github.io/install.sh)"
# - installe les dependances (GitHub CLI, FFmpeg) sans Homebrew ni mot de passe
# - telecharge les versions deja compilees des programmes listes dans apps.tsv
# - si une version compilee manque, la compile sur ce Mac (outils Apple + CMake installes au besoin)
set -u
SITE="https://aynide-glitch.github.io"
HOME_DIR="$HOME/.boite-a-outils"
BIN="$HOME_DIR/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$BIN"
export PATH="$BIN:/opt/homebrew/bin:/usr/local/bin:$PATH"

say()  { printf '\n\033[1;36m== %s ==\033[0m\n' "$1"; }
ok()   { printf '\033[32m%s\033[0m\n' "$1"; }
warn() { printf '\033[33m%s\033[0m\n' "$1"; }
fail() { printf '\n\033[1;31mERREUR : %s\033[0m\n' "$1"; read -r -p "Appuyez sur Entree pour fermer" _ </dev/tty; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Ce script est pour macOS."
ARCH="$(uname -m)"; [ "$ARCH" = "arm64" ] && GHARCH="arm64" || GHARCH="amd64"
[ "$ARCH" = "arm64" ] && FFARCH="arm64" || FFARCH="amd64"

# 1. GitHub CLI (acces aux versions privees) -------------------------------------------------------------
if ! command -v gh >/dev/null 2>&1; then
    say "Installation de GitHub CLI"
    URL="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -o "https://[^\"]*macOS_${GHARCH}\.zip" | head -1)"
    [ -n "$URL" ] || fail "Impossible de trouver GitHub CLI (connexion ?)."
    curl -fsSL "$URL" -o "$TMP/gh.zip" || fail "Telechargement de GitHub CLI impossible."
    unzip -q -o "$TMP/gh.zip" -d "$TMP/gh" && cp "$(find "$TMP/gh" -name gh -type f | head -1)" "$BIN/gh" && chmod +x "$BIN/gh" || fail "Installation de GitHub CLI impossible."
    xattr -cr "$BIN/gh" 2>/dev/null
fi
if [ -z "${GH_TOKEN:-}" ] && ! gh auth status >/dev/null 2>&1; then
    say "Acces a tes depots prives"
    echo "Colle un jeton GitHub limite a tes depots (voir ci-dessous), ou laisse vide pour te connecter par le navigateur."
    echo "  Jeton : github.com > Settings > Developer settings > Personal access tokens > Fine-grained tokens > Generate new token"
    echo "  Proprietaire : ton compte perso (pas une organisation) | Depots : Audionide + boite-a-outils | Contents : Read-only"
    printf "Jeton (rien ne s'affiche) : "; read -rs TOKEN </dev/tty; echo
    if [ -n "$TOKEN" ]; then
        export GH_TOKEN="$TOKEN"
        gh api repos/Aynide-glitch/boite-a-outils --silent >/dev/null 2>&1 || fail "Ce jeton ne donne pas acces a Aynide-glitch/boite-a-outils (Contents: Read-only, depot ajoute ?)."
    else
        gh auth login --hostname github.com --git-protocol https --web </dev/tty || fail "Connexion a GitHub impossible."
    fi
fi
gh auth setup-git >/dev/null 2>&1

# 2. FFmpeg (conversion) ---------------------------------------------------------------------------------
FF_DIR="$HOME/Library/Application Support/BoiteAOutils/ffmpeg"
if [ ! -x "$FF_DIR/ffmpeg" ] || [ ! -x "$FF_DIR/ffprobe" ]; then
    say "Installation de FFmpeg"
    mkdir -p "$FF_DIR"
    FF_OK=1
    for tool in ffmpeg ffprobe; do
        if curl -fsSL "https://ffmpeg.martin-riedl.de/redirect/latest/macos/$FFARCH/release/$tool.zip" -o "$TMP/$tool.zip" \
            && unzip -q -o "$TMP/$tool.zip" -d "$FF_DIR"; then
            chmod +x "$FF_DIR/$tool"; xattr -cr "$FF_DIR/$tool" 2>/dev/null
        else
            FF_OK=0
        fi
    done
    [ "$FF_OK" = 1 ] && ok "FFmpeg installe." || warn "FFmpeg n'a pas pu etre telecharge : la Boite a Outils proposera de l'installer (Reglages > FFmpeg)."
fi

# 3. Programmes de la liste -----------------------------------------------------------------------------
say "Liste des programmes"
curl -fsSL "$SITE/apps.tsv" -o "$TMP/apps.tsv" || fail "Liste des programmes introuvable ($SITE/apps.tsv)."
DEST="/Applications"; [ -w "$DEST" ] || { DEST="$HOME/Applications"; mkdir -p "$DEST"; }

ensure_build_tools() {
    if ! xcode-select -p >/dev/null 2>&1; then
        echo "Les outils de developpement d'Apple sont necessaires : une fenetre va proposer de les installer."
        xcode-select --install
        fail "Terminez l'installation des outils Apple, puis relancez cette commande."
    fi
    if ! command -v cmake >/dev/null 2>&1; then
        say "Installation de CMake"
        V="$(curl -fsSL https://api.github.com/repos/Kitware/CMake/releases/latest | grep -o '"tag_name": *"v[0-9.]*"' | grep -o '[0-9][0-9.]*' | head -1)"
        curl -fsSL "https://github.com/Kitware/CMake/releases/download/v$V/cmake-$V-macos-universal.tar.gz" -o "$TMP/cmake.tgz" || fail "CMake introuvable."
        mkdir -p "$HOME_DIR/cmake" && tar -xzf "$TMP/cmake.tgz" -C "$HOME_DIR/cmake" --strip-components=1 || fail "Installation de CMake impossible."
        export PATH="$HOME_DIR/cmake/CMake.app/Contents/bin:$PATH"
    fi
}

add_to_dock() {
    local app="$1"
    if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "$app"; then
        defaults write com.apple.dock persistent-apps -array-add "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$app</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
        DOCK_CHANGED=1
    fi
}

DOCK_CHANGED=0
INSTALLED=(); FAILED=()
while IFS=$'\t' read -r id name repo masset wasset mapp wexe defs <&3; do
    case "$id" in ''|\#*) continue ;; esac
    say "$name"
    target="$DEST/$mapp"
    installed=0
    # a) version deja compilee
    if [ -n "$masset" ] && gh release download --repo "$repo" --pattern "$masset" --dir "$TMP/$id" --clobber </dev/null >/dev/null 2>&1; then
        rm -rf "$TMP/$id/stage"; mkdir -p "$TMP/$id/stage"
        if ditto -x -k "$TMP/$id/$masset" "$TMP/$id/stage" && [ -d "$TMP/$id/stage/$mapp" ]; then
            [ -d "$target" ] && mv "$target" "$TMP/$id/old.app"
            mv "$TMP/$id/stage/$mapp" "$target" && installed=1
            xattr -cr "$target" 2>/dev/null
            codesign --force --deep -s - "$target" >/dev/null 2>&1
            [ "$installed" = 1 ] && ok "$name installe depuis la version compilee."
        fi
    else
        warn "Pas de version compilee pour $name : compilation sur ce Mac (10 a 25 minutes)."
    fi
    # b) sinon : compilation locale
    if [ "$installed" = 0 ]; then
        ensure_build_tools
        curl -fsSL "$SITE/build-app.sh" -o "$TMP/build-app.sh"
        # shellcheck disable=SC2086
        if bash "$TMP/build-app.sh" "https://github.com/$repo.git" main "${mapp%.app}" "${mapp%.app}" "$target" $defs </dev/tty; then installed=1; fi
    fi
    if [ "$installed" = 1 ] && [ -d "$target" ]; then INSTALLED+=("$name"); add_to_dock "$target"; else FAILED+=("$name"); fi
done 3< "$TMP/apps.tsv"
[ "$DOCK_CHANGED" = 1 ] && killall Dock 2>/dev/null

say "Termine"
for n in "${INSTALLED[@]+"${INSTALLED[@]}"}"; do ok "OK : $n"; done
for n in "${FAILED[@]+"${FAILED[@]}"}"; do warn "ECHEC : $n (voir les messages ci-dessus)"; done
echo "Les programmes sont dans $DEST (Launchpad, Spotlight, Dock)."
[ ${#FAILED[@]} -eq 0 ] && open "$DEST/BoiteAOutils.app" 2>/dev/null
exit 0
