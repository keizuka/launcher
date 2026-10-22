#!/usr/bin/env bash
# Publie une version du launcher : export Linux, licences, zip, release GitHub.
#
#   ./tools/publier_launcher.sh [version] [options]
#     --dev            build de développement (préréglage « Linux (dev) », dépôt privé launcher-dev)
#     --local <dossier> fabrique seulement le zip dans ce dossier, sans rien publier (essai)
#     --notes "texte"  nouveautés de la release (sinon : les derniers commits)
#
# La version par défaut est celle de project.godot. Le launcher public va dans keizuka/launcher
# (tags launcher-v<version>) ; la version dev dans keizuka/launcher-dev (tags launcher-dev-v<version>).
set -euo pipefail
racine="$(cd "$(dirname "$0")/.." && pwd)"
version=""; dev=0; dossier_local=""; notes=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--dev) dev=1; shift ;;
		--local) dossier_local="$2"; shift 2 ;;
		--notes) notes="$2"; shift 2 ;;
		-*) echo "Option inconnue : $1" >&2; exit 1 ;;
		*) version="${1#v}"; shift ;;
	esac
done
[[ -n "$version" ]] || version=$(grep -oP 'config/version="\K[^"]+' "$racine/project.godot")
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Version invalide : $version (ex. 0.6.0)" >&2; exit 1; }

preset="Linux"; id="launcher"; depot="keizuka/launcher"; prefixe="launcher-v"
if [[ $dev == 1 ]]; then
	preset="Linux (dev)"; id="launcher-dev"; depot="keizuka/launcher-dev"; prefixe="launcher-dev-v"
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/linux"
echo "→ Export $preset…"
godot --headless --path "$racine" --export-release "$preset" "$tmp/linux/launcher.x86_64" 2>&1 \
	| grep -E "^ERROR|SCRIPT ERROR" | grep -v CUDA || true
[[ -f "$tmp/linux/launcher.x86_64" ]] || { echo "Export $preset échoué" >&2; exit 1; }

echo "→ Licences…"
mkdir -p "$tmp/linux/licences"
cp "$racine/tools/licences/"*.txt "$tmp/linux/licences/"
if [[ -f "$racine/CREDITS.md" ]]; then cp "$racine/CREDITS.md" "$tmp/linux/licences/"; fi

sortie="${dossier_local:-$tmp/zips}"; mkdir -p "$sortie"; sortie="$(cd "$sortie" && pwd)"
archive="$sortie/$id-$version-linux.zip"
(cd "$tmp/linux" && zip -qr9 "$archive" .)
echo "  $(basename "$archive") : $(du -h "$archive" | cut -f1)"

if [[ -n "$dossier_local" ]]; then
	echo "Zip prêt dans $dossier_local (rien n'a été publié)."
	exit 0
fi
[[ -n "$notes" ]] || notes=$(git -C "$racine" log --pretty='- %s' -n 8)
titre="Launcher $version"; [[ $dev == 1 ]] && titre="Launcher dev $version"
gh release create "$prefixe$version" "$archive" --repo "$depot" --title "$titre" --notes "$notes"
echo "Publié : https://github.com/$depot/releases/tag/$prefixe$version"
