#!/usr/bin/env bash
#
# setup-context-menu.sh — Ajoute "Installer cette AppImage" au clic droit
# du gestionnaire de fichiers, en détectant l'environnement de bureau.
#
# Usage : ./setup-context-menu.sh [/chemin/vers/install-appimage.sh]
#   (par défaut, cherche install-appimage.sh dans le même dossier que ce script)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="${1:-$SCRIPT_DIR/integrate-appimage.sh}"

if [ ! -f "$INSTALL_SCRIPT" ]; then
    echo "Erreur : integrate-appimage.sh introuvable ($INSTALL_SCRIPT)" >&2
    echo "Indiquez son chemin : $0 /chemin/vers/integrate-appimage.sh" >&2
    exit 1
fi
INSTALL_SCRIPT=$(realpath "$INSTALL_SCRIPT")
chmod +x "$INSTALL_SCRIPT"

install_kde() {
    local version="$1"
    local dir dest

    if [ "$version" = "6" ]; then
        dir="$HOME/.local/share/kio/servicemenus"
    else
        dir="$HOME/.local/share/kservices5/ServiceMenus"
    fi
    mkdir -p "$dir"
    dest="$dir/install-appimage.desktop"

    cat > "$dest" <<EOF
[Desktop Entry]
Type=Service
X-KDE-ServiceTypes=KonqPopupMenu/Plugin
MimeType=application/x-executable;
Actions=integrateAppImage;

[Desktop Action integrateAppImage]
Name=Intégrer cette AppImage
Icon=application-x-executable
Exec=$INSTALL_SCRIPT %f
EOF

    # KDE exige que le .desktop lui-même soit exécutable pour être "de confiance",
    # sinon Dolphin refuse de le lancer avec une erreur de permission.
    chmod +x "$dest"

    echo "Service menu KDE Plasma $version créé : $dest"

    if command -v "kbuildsycoca$version" >/dev/null 2>&1; then
        "kbuildsycoca$version" >/dev/null 2>&1 || true
    fi
    echo "Relancez Dolphin (kquitapp$version dolphin, puis rouvrez-le) pour le voir apparaître."
}

install_nautilus() {
    local dir="$HOME/.local/share/nautilus/scripts"
    local dest="$dir/Intégrer cette AppImage"

    mkdir -p "$dir"
    cat > "$dest" <<EOF
#!/usr/bin/env bash
for f in "\$@"; do
    "$INSTALL_SCRIPT" "\$f"
done
EOF
    chmod +x "$dest"
    echo "Script Nautilus créé : $dest"
    echo "Clic droit sur un fichier > Scripts > 'Intégrer cette AppImage'."
}

# --- Détection de l'environnement ---
if command -v plasmashell >/dev/null 2>&1; then
    VERSION=$(plasmashell --version 2>/dev/null | grep -oE '[0-9]+' | head -n1)
    if [ -z "$VERSION" ]; then
        echo "KDE Plasma détecté mais impossible de lire sa version." >&2
        exit 1
    fi
    install_kde "$VERSION"

elif [ "${XDG_CURRENT_DESKTOP:-}" = "GNOME" ] || command -v nautilus >/dev/null 2>&1; then
    install_nautilus

else
    echo "Environnement de bureau non reconnu automatiquement (XDG_CURRENT_DESKTOP=${XDG_CURRENT_DESKTOP:-inconnu})."
    echo ""
    echo "Ce script gère KDE Plasma (5 et 6) et GNOME/Nautilus."
    echo "Pour XFCE (Thunar), Cinnamon (Nemo) ou MATE (Caja), l'ajout se fait via"
    echo "les 'actions personnalisées' du gestionnaire de fichiers, qui passent par"
    echo "une interface graphique différente — pas automatisable de la même façon."
    echo "Dites-moi lequel vous utilisez si vous voulez un script dédié."
    exit 1
fi
