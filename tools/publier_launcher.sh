#!/usr/bin/env bash
# Publie une version du launcher : export(s), licences, zip, release GitHub.
#
#   ./tools/publier_launcher.sh [version] [options]
#     --dev             build de développement (Linux seul, préréglage « Linux (dev) »,
#                       dépôt privé launcher-dev, tags launcher-dev-v<version>)
#     --local <dossier> fabrique seulement les archives dans ce dossier, sans publier (essai)
#     --notes "texte"   nouveautés de la release (sinon : les derniers commits)
#
# Version publique : tous les systèmes dont le projet a un préréglage (Linux, Windows, macOS, Android).
# La version par défaut est celle de project.godot.
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

id="launcher"; depot="keizuka/launcher"; prefixe="launcher-v"
systemes="linux windows macos android"
if [[ $dev == 1 ]]; then
	id="launcher-dev"; depot="keizuka/launcher-dev"; prefixe="launcher-dev-v"; systemes="linux"
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sortie="${dossier_local:-$tmp/zips}"; mkdir -p "$sortie"; sortie="$(cd "$sortie" && pwd)"
fichiers=()

exporter() {  # $1 preset, $2 chemin de sortie
	echo "→ Export $1…"
	godot --headless --path "$racine" --export-release "$1" "$2" 2>&1 \
		| grep -E "^ERROR|SCRIPT ERROR" | grep -v CUDA || true
	[[ -f "$2" ]] || { echo "Export $1 échoué" >&2; exit 1; }
}

licences() {  # $1 dossier de l'archive
	mkdir -p "$1/licences"
	cp "$racine/tools/licences/"*.txt "$1/licences/"
	[[ -f "$racine/CREDITS.md" ]] && cp "$racine/CREDITS.md" "$1/licences/"
	return 0
}

# Export système par système.
if [[ $dev == 1 ]]; then
	mkdir -p "$tmp/linux"
	exporter "Linux (dev)" "$tmp/linux/launcher.x86_64"
	licences "$tmp/linux"
	(cd "$tmp/linux" && zip -qr9 "$sortie/$id-$version-linux.zip" .)
	fichiers+=("$sortie/$id-$version-linux.zip")
	echo "  $(basename "${fichiers[-1]}") : $(du -h "${fichiers[-1]}" | cut -f1)"
else
	mkdir -p "$tmp/linux"
	exporter "Linux" "$tmp/linux/launcher.x86_64"
	licences "$tmp/linux"
	(cd "$tmp/linux" && zip -qr9 "$sortie/$id-$version-linux.zip" .)
	fichiers+=("$sortie/$id-$version-linux.zip")
	echo "  $(basename "${fichiers[-1]}") : $(du -h "${fichiers[-1]}" | cut -f1)"

	mkdir -p "$tmp/windows"
	exporter "Windows" "$tmp/windows/launcher.exe"
	licences "$tmp/windows"
	(cd "$tmp/windows" && zip -qr9 "$sortie/$id-$version-windows.zip" .)
	fichiers+=("$sortie/$id-$version-windows.zip")
	echo "  $(basename "${fichiers[-1]}") : $(du -h "${fichiers[-1]}" | cut -f1)"

	mkdir -p "$tmp/macos"
	exporter "macOS" "$tmp/macos/app.zip"
	(cd "$tmp/macos" && unzip -q app.zip && rm app.zip)
	licences "$tmp/macos"
	(cd "$tmp/macos" && zip -qr9 "$sortie/$id-$version-macos.zip" .)
	fichiers+=("$sortie/$id-$version-macos.zip")
	echo "  $(basename "${fichiers[-1]}") : $(du -h "${fichiers[-1]}" | cut -f1)"

	if ! grep -q 'name="Android"' "$racine/export_presets.cfg"; then
		echo "  (pas de préréglage Android : APK non construite)"
	elif [[ -z "${ANDROID_HOME:-}" && ! -d "$HOME/.local/opt/android-sdk" ]]; then
		echo "  (SDK Android absent : APK non construite)"
	elif [[ ! -f "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/.local/share/godot/keystores/debug.keystore}" ]]; then
		echo "  (pas de keystore Android : APK non construite)"
	else
		# Godot 4.7 lit le certificat de signature dans ces variables. Par défaut : le keystore
		# « debug » déjà utilisé par les versions précédentes, pour que Android accepte la mise à jour
		# (un autre certificat obligerait à désinstaller l'ancienne version).
		export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$HOME/.local/share/godot/keystores/debug.keystore}"
		export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-androiddebugkey}"
		export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-android}"
		mkdir -p "$tmp/android"
		exporter "Android" "$tmp/android/launcher.apk"
		cp "$tmp/android/launcher.apk" "$sortie/$id-$version-android.apk"
		fichiers+=("$sortie/$id-$version-android.apk")
		echo "  $(basename "${fichiers[-1]}") : $(du -h "${fichiers[-1]}" | cut -f1)"
	fi
fi

if [[ -n "$dossier_local" ]]; then
	echo "Archives prêtes dans $dossier_local (rien n'a été publié)."
	exit 0
fi
[[ -n "$notes" ]] || notes=$(git -C "$racine" log --pretty='- %s' -n 8)
titre="Launcher $version"; [[ $dev == 1 ]] && titre="Launcher dev $version"
gh release create "$prefixe$version" "${fichiers[@]}" --repo "$depot" --title "$titre" --notes "$notes"
echo "Publié : https://github.com/$depot/releases/tag/$prefixe$version"
