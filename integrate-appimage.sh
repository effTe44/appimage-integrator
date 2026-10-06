#!/usr/bin/env bash
#
# integrate-appimage.sh — Intègre proprement une AppImage au bureau Kubuntu/KDE.
#
# Usage : ./integrate-appimage.sh /chemin/vers/monapp.AppImage
#
# Ce que fait le script :
#   1. Extrait le .desktop et l'icône embarqués dans l'AppImage, si présents.
#      À défaut, génère un .desktop minimal et cherche une icône dans les
#      emplacements usuels (usr/share/icons, usr/share/pixmaps).
#   2. Crée un dossier "<NomApp>" à côté de l'AppImage d'origine
#   3. Déplace l'AppImage et copie l'icône dans ce dossier
#   4. Génère le fichier .desktop dans ~/.local/share/applications
#      avec les bons chemins (Exec= et Icon=)

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "Usage : $0 /chemin/vers/monapp.AppImage" >&2
    exit 1
fi

APPIMAGE_PATH=$(realpath "$1")

if [ ! -f "$APPIMAGE_PATH" ]; then
    echo "Erreur : fichier introuvable : $APPIMAGE_PATH" >&2
    exit 1
fi

case "$APPIMAGE_PATH" in
    *.AppImage|*.appimage) ;;
    *) echo "Erreur : le fichier ne semble pas être une AppImage (.AppImage)" >&2; exit 1 ;;
esac

chmod +x "$APPIMAGE_PATH"

PARENT_DIR=$(dirname "$APPIMAGE_PATH")
ORIGINAL_NAME=$(basename "$APPIMAGE_PATH")

echo "Extraction des métadonnées (.desktop, icône)..."
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

(
    cd "$TMP_DIR"
    "$APPIMAGE_PATH" --appimage-extract
) || {
    echo "Erreur : impossible d'extraire l'AppImage (--appimage-extract a échoué)" >&2
    exit 1
}

# La plupart des runtimes créent "squashfs-root" (parfois un simple lien
# symbolique vers "AppDir" pour les runtimes plus récents) ; on retombe sur
# "AppDir" si "squashfs-root" n'existe pas du tout.
if [ -e "$TMP_DIR/squashfs-root" ]; then
    SQUASHFS_ROOT="$TMP_DIR/squashfs-root"
elif [ -d "$TMP_DIR/AppDir" ]; then
    SQUASHFS_ROOT="$TMP_DIR/AppDir"
else
    echo "Erreur : dossier d'extraction introuvable (ni squashfs-root ni AppDir)." >&2
    echo "Contenu de $TMP_DIR :" >&2
    ls -la "$TMP_DIR" >&2
    exit 1
fi

# Cherche le .desktop : d'abord à la racine (emplacement standard), sinon
# dans usr/share/applications (certaines AppImages non strictement
# conformes à la spec l'y placent quand même), sinon n'importe où.
DESKTOP_FILE=$(find -L "$SQUASHFS_ROOT" -maxdepth 1 -name "*.desktop" | head -n1)
if [ -z "$DESKTOP_FILE" ]; then
    DESKTOP_FILE=$( { find -L "$SQUASHFS_ROOT" -path "*/applications/*" -name "*.desktop"; } \
        2>/dev/null | head -n1) || true
fi
if [ -z "$DESKTOP_FILE" ]; then
    DESKTOP_FILE=$( { find -L "$SQUASHFS_ROOT" -name "*.desktop"; } 2>/dev/null | head -n1) || true
fi

if [ -n "$DESKTOP_FILE" ]; then
    HAS_DESKTOP=true
    echo "Fichier .desktop trouvé : ${DESKTOP_FILE#"$SQUASHFS_ROOT"/}"
else
    HAS_DESKTOP=false
    echo "Aucun .desktop trouvé dans l'AppImage : génération d'une entrée minimale."
    echo "Contenu extrait à la racine, pour vérification :"
    find -L "$SQUASHFS_ROOT" -maxdepth 1 -printf '  %f\n' 2>/dev/null || ls -la "$SQUASHFS_ROOT"
fi

# --- Nom de l'application ---
if [ "$HAS_DESKTOP" = true ]; then
    APP_NAME=$(grep -m1 "^Name=" "$DESKTOP_FILE" | cut -d= -f2-)
fi
if [ -z "${APP_NAME:-}" ]; then
    # Dérive un nom lisible depuis le nom de fichier : retire l'extension,
    # remplace tirets/underscores par des espaces.
    APP_NAME=$(echo "${ORIGINAL_NAME%.*}" | sed -E 's/[-_]+/ /g')
fi

# --- Icône ---
ICON_FILE=""
if [ "$HAS_DESKTOP" = true ]; then
    ICON_KEY=$(grep -m1 "^Icon=" "$DESKTOP_FILE" | cut -d= -f2-)
    if [ -n "$ICON_KEY" ]; then
        ICON_FILE=$(find -L "$SQUASHFS_ROOT" -maxdepth 1 -iname "${ICON_KEY}.*" | head -n1)
    fi
fi
# Icône à la racine (souvent présente même sans .desktop)
if [ -z "$ICON_FILE" ]; then
    ICON_FILE=$(find -L "$SQUASHFS_ROOT" -maxdepth 1 \( -iname "*.png" -o -iname "*.svg" \) | head -n1)
fi
# Emplacements usuels : usr/share/icons, usr/share/pixmaps (utile quand il
# n'y a pas de .desktop, l'icône n'étant alors pas forcément à la racine)
# Note : `|| true` empêche `set -e` d'arrêter le script quand rien n'est
# trouvé, ce qui est un cas normal (pas une erreur).
if [ -z "$ICON_FILE" ]; then
    ICON_FILE=$( { find -L "$SQUASHFS_ROOT" -path "*/icons/*" -o -path "*/pixmaps/*"; } \
        2>/dev/null | grep -iE '\.(png|svg)$' | sort -r | head -n1) || true
fi
# Dernier recours : n'importe quelle image dans toute l'archive extraite
if [ -z "$ICON_FILE" ]; then
    ICON_FILE=$( { find -L "$SQUASHFS_ROOT" -iname "*.png" -o -iname "*.svg"; } \
        2>/dev/null | head -n1) || true
fi

# Dossier de destination, à côté de l'AppImage, nommé d'après l'app
SAFE_NAME=$(echo "$APP_NAME" | tr ' /' '__')
DEST_DIR="$PARENT_DIR/$SAFE_NAME"
mkdir -p "$DEST_DIR"

echo "Déplacement de l'AppImage vers $DEST_DIR/"
mv "$APPIMAGE_PATH" "$DEST_DIR/"
NEW_APPIMAGE_PATH="$DEST_DIR/$ORIGINAL_NAME"
chmod +x "$NEW_APPIMAGE_PATH"

NEW_ICON_PATH=""
if [ -n "$ICON_FILE" ]; then
    ICON_EXT="${ICON_FILE##*.}"
    NEW_ICON_PATH="$DEST_DIR/${SAFE_NAME}.${ICON_EXT}"
    cp "$ICON_FILE" "$NEW_ICON_PATH"
    echo "Icône copiée vers $NEW_ICON_PATH"
else
    echo "Attention : aucune icône trouvée, icône générique utilisée."
fi
[ -z "$NEW_ICON_PATH" ] && NEW_ICON_PATH="application-x-executable"

APPS_DIR="$HOME/.local/share/applications"
mkdir -p "$APPS_DIR"
DESKTOP_DEST="$APPS_DIR/${SAFE_NAME}.desktop"

if [ "$HAS_DESKTOP" = true ]; then
    # On repart du .desktop ORIGINAL (Comment, Categories, Keywords,
    # GenericName, MimeType... sont donc préservés tels quels) et on ne
    # corrige que les chemins devenus invalides une fois l'app déplacée :
    # Exec, Icon, TryExec et Path.
    cp "$DESKTOP_FILE" "$DESKTOP_DEST"

    # Reconstruit Exec= en gardant les arguments/placeholders d'origine
    # (%U, %f...) mais en remplaçant le binaire appelé par l'AppImage.
    ORIG_EXEC=$(grep -m1 "^Exec=" "$DESKTOP_DEST" | cut -d= -f2-)
    EXEC_ARGS=$(echo "$ORIG_EXEC" | sed -E 's/^"[^"]*"//; s/^[^ ]+//')
    NEW_EXEC="\"$NEW_APPIMAGE_PATH\"${EXEC_ARGS}"

    sed -i \
        -e "s|^Exec=.*|Exec=${NEW_EXEC}|" \
        -e "s|^TryExec=.*|TryExec=${NEW_APPIMAGE_PATH}|" \
        -e "s|^Icon=.*|Icon=${NEW_ICON_PATH}|" \
        -e "/^Path=/d" \
        "$DESKTOP_DEST"

    # S'assure qu'un Name= existe (rare mais possible)
    grep -q "^Name=" "$DESKTOP_DEST" || sed -i "1a Name=${APP_NAME}" "$DESKTOP_DEST"
else
    # Pas de .desktop dans l'AppImage : on en génère un minimal.
    {
        echo "[Desktop Entry]"
        echo "Type=Application"
        echo "Name=${APP_NAME}"
        echo "Exec=\"${NEW_APPIMAGE_PATH}\" %U"
        echo "Icon=${NEW_ICON_PATH}"
        echo "Terminal=false"
        echo "Categories=Utility;"
    } > "$DESKTOP_DEST"
fi

# Ajoute une trace du fichier source, utile pour désinstaller plus tard
echo "X-AppImage-Source=$NEW_APPIMAGE_PATH" >> "$DESKTOP_DEST"

chmod +x "$DESKTOP_DEST"

command -v update-desktop-database >/dev/null 2>&1 && \
    update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true

echo ""
echo "Intégration terminée !"
echo "  Dossier app : $DEST_DIR"
echo "  Raccourci   : $DESKTOP_DEST"
if [ "$HAS_DESKTOP" = false ]; then
    echo "  (entrée .desktop générée automatiquement, l'AppImage n'en fournissait pas)"
fi
echo "  Cherchez « $APP_NAME » dans le menu des applications."
