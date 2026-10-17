#!/usr/bin/env bash
# Publie une version d'un jeu Godot pour le launcher : export Linux + Windows (+ macOS si le préréglage
# existe), un zip par système, release GitHub.
#
#   ./tools/publier_jeu.sh <dossier du projet> <id> <version> [options]
#     --depot owner/repo   dépôt PUBLIC qui reçoit les versions (défaut : keizuka/launcher)
#     --notes "texte"      nouveautés affichées dans le launcher (sinon : les derniers commits)
#     --local <dossier>    fabrique seulement les zips dans ce dossier, sans rien publier (essai)
#
# Le projet doit avoir des préréglages d'export nommés « Linux » et « Windows » (export_presets.cfg),
# et le catalogue (catalogue.json du dépôt) doit contenir le jeu avec son id.
set -euo pipefail
projet="$(cd "$1" && pwd)"; id="$2"; version="${3#v}"; shift 3
depot="keizuka/launcher"; notes=""; local_dir=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--depot) depot="$2"; shift 2 ;;
		--notes) notes="$2"; shift 2 ;;
		--local) local_dir="$2"; shift 2 ;;
		*) echo "Option inconnue : $1" >&2; exit 1 ;;
	esac
done
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]] || { echo "Version invalide : $version (ex. 0.3.1)" >&2; exit 1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
sortie="${local_dir:-$tmp/zips}"; mkdir -p "$sortie"; sortie="$(cd "$sortie" && pwd)"
exe_linux=$(grep -A12 'name="Linux"' "$projet/export_presets.cfg" | grep -oP 'export_path="\K[^"]+' | xargs basename)
exe_windows=$(grep -A12 'name="Windows"' "$projet/export_presets.cfg" | grep -oP 'export_path="\K[^"]+' | xargs basename)
systemes="linux windows"
grep -q 'name="macOS"' "$projet/export_presets.cfg" && systemes="$systemes macos"
for sys in $systemes; do
	case $sys in
		linux) preset=Linux; exe="$exe_linux" ;;
		windows) preset=Windows; exe="$exe_windows" ;;
		macos) preset=macOS; exe="app.zip" ;;
	esac
	mkdir -p "$tmp/$sys"
	echo "→ Export $preset…"
	godot --headless --path "$projet" --export-release "$preset" "$tmp/$sys/$exe" 2>&1 | grep -E "^ERROR|SCRIPT ERROR" | grep -v CUDA || true
	[[ -f "$tmp/$sys/$exe" ]] || { echo "Export $preset échoué" >&2; exit 1; }
	if [[ $sys == macos ]]; then
		# Godot livre l'app .app (universelle, signée ad hoc) dans un zip : on l'ouvre pour y joindre les licences.
		(cd "$tmp/$sys" && unzip -q app.zip && rm app.zip)
		ls -d "$tmp/$sys"/*.app >/dev/null 2>&1 || { echo "Export macOS : pas d'app .app" >&2; exit 1; }
	fi
	# Licences et crédits livrés avec l'exécutable (moteur, plugins, polices, contenus).
	mkdir -p "$tmp/$sys/licences"
	cp "$(dirname "$0")/licences/"*.txt "$tmp/$sys/licences/" 2>/dev/null || true
	if [[ -f "$projet/CREDITS.md" ]]; then cp "$projet/CREDITS.md" "$tmp/$sys/licences/"; fi
	find "$projet/addons" "$projet/assets/polices" -maxdepth 2 2>/dev/null \( -iname 'LICENSE*' -o -iname 'OFL.txt' \) 2>/dev/null | while read -r f; do
		nom="$(basename "$f")"; cp "$f" "$tmp/$sys/licences/$(basename "$(dirname "$f")")-${nom%.txt}.txt"
	done || true
	(cd "$tmp/$sys" && zip -qr9 "$sortie/$id-$version-$sys.zip" .)
	echo "  $id-$version-$sys.zip : $(du -h "$sortie/$id-$version-$sys.zip" | cut -f1)"
done
if [[ -n "$local_dir" ]]; then
	echo "Zips prêts dans $local_dir (rien n'a été publié)."
	exit 0
fi
if [[ -z "$notes" ]]; then
	notes=$(git -C "$projet" log --pretty='- %s' -n 8)
fi
tag="$id-v$version"
fichiers=()
for sys in $systemes; do fichiers+=("$sortie/$id-$version-$sys.zip"); done
gh release create "$tag" "${fichiers[@]}" \
	--repo "$depot" --title "$(basename "$projet") $version" --notes "$notes"
echo "Publié : https://github.com/$depot/releases/tag/$tag — le launcher le proposera à la prochaine vérification."
