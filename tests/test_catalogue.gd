# Détection des versions par système : un APK sur Android, un zip sur ordinateur.
# godot --headless --path . -s tests/test_catalogue.gd
extends SceneTree

var _echecs := 0
var _total := 0

func verifier(cond: bool, message: String) -> void:
	_total += 1
	if not cond:
		_echecs += 1
		printerr("ÉCHEC : ", message)

func _release(tag: String, fichiers: Array, draft := false) -> Dictionary:
	var assets := []
	for f in fichiers:
		assets.append({"name": f, "browser_download_url": "https://x/" + f, "url": "https://api/assets/" + f, "size": 10})
	return {"tag_name": tag, "draft": draft, "published_at": "2026-10-17", "body": "", "assets": assets}

func _init():
	var releases := [
		_release("rpg-ia-v0.5.0", ["rpg-ia-0.5.0-linux.zip", "rpg-ia-0.5.0-windows.zip"]),
		_release("rpg-ia-v0.6.1", ["rpg-ia-0.6.1-linux.zip", "rpg-ia-0.6.1-windows.zip",
			"rpg-ia-0.6.1-android.apk"]),
		_release("rpg-ia-v0.7.0", ["rpg-ia-0.7.0-linux.zip", "rpg-ia-0.7.0-android.apk"], true),
	]
	var android := Catalogue.derniere_version(releases, "rpg-ia-v", "android")
	verifier(android.get("version", "") == "0.6.1",
		"Android : 0.6.1 attendu (brouillon écarté), obtenu « %s »" % android.get("version", ""))
	verifier(android.get("fichier", {}).get("nom", "") == "rpg-ia-0.6.1-android.apk",
		"Android : le fichier doit être l'APK, obtenu « %s »" % android.get("fichier", {}).get("nom", ""))
	var linux := Catalogue.derniere_version(releases, "rpg-ia-v", "linux")
	verifier(linux.get("version", "") == "0.6.1", "Linux : 0.6.1 attendu")
	verifier(linux.get("fichier", {}).get("nom", "") == "rpg-ia-0.6.1-linux.zip",
		"Linux : le fichier doit être le zip")
	# Une version plus récente publiée sans APK : Android garde la dernière qui en a un.
	var suites: Array = releases.duplicate()
	suites.append(_release("rpg-ia-v0.8.0", ["rpg-ia-0.8.0-linux.zip"]))
	var android2 := Catalogue.derniere_version(suites, "rpg-ia-v", "android")
	verifier(android2.get("version", "") == "0.6.1",
		"Android : 0.6.1 conservé face à un 0.8.0 sans APK, obtenu « %s »" % android2.get("version", ""))
	var vide := Catalogue.derniere_version([_release("apoapsis-v1.0.0", ["apoapsis-1.0.0-linux.zip"])],
		"apoapsis-v", "android")
	verifier(vide.is_empty(), "Android : aucune version sans APK")

	# Catalogue dev : fusion par id, jeux cachés aux joueurs, visibles en mode dev.
	var base := [{"id": "a", "nom": "A"}, {"id": "b", "nom": "B", "statut": "bientot"}]
	var dev := [{"id": "b", "statut": "dev"}, {"id": "c", "nom": "C", "depot": "x/y"}]
	var fusion := Catalogue.fusionner(base, dev)
	verifier(fusion.size() == 3, "fusion : 3 entrées attendues, obtenu %d" % fusion.size())
	verifier(fusion[1]["statut"] == "dev" and fusion[1]["nom"] == "B",
		"fusion : l'entrée dev change le statut sans perdre le nom")
	verifier(Catalogue.statut(fusion[2]) == "dev", "fusion : une nouvelle entrée est cachée par défaut")
	verifier(Catalogue.visibles(fusion, false).size() == 1,
		"joueurs : seuls les jeux en ligne sont visibles, obtenu %d" % Catalogue.visibles(fusion, false).size())
	verifier(Catalogue.visibles(fusion, true).size() == 3, "mode dev : tous les jeux sont visibles")
	verifier(Catalogue.visibles([{"id": "a", "statut": "hors-ligne"}], false).size() == 1,
		"joueurs : un jeu hors ligne reste visible")
	# Téléchargement : URL d'API avec un jeton (dépôt privé), URL publique sans ; un seul Accept binaire.
	var fichier: Dictionary = linux["fichier"]
	var sans := Catalogue.requete_fichier(fichier, PackedStringArray(["User-Agent: l", "Accept: application/vnd.github+json"]))
	verifier(sans[0] == "https://x/rpg-ia-0.6.1-linux.zip", "sans jeton : URL publique, obtenu « %s »" % sans[0])
	var avec := Catalogue.requete_fichier(fichier,
		PackedStringArray(["User-Agent: l", "Accept: application/vnd.github+json", "Authorization: Bearer t"]))
	verifier(avec[0] == "https://api/assets/rpg-ia-0.6.1-linux.zip", "avec jeton : URL d'API, obtenu « %s »" % avec[0])
	var accepts := 0
	for e in avec[1]:
		if e.begins_with("Accept:"):
			accepts += 1
			verifier(e == "Accept: application/octet-stream", "en-tête Accept binaire attendu, obtenu « %s »" % e)
	verifier(accepts == 1, "un seul en-tête Accept, obtenu %d" % accepts)
	verifier("Authorization: Bearer t" in avec[1], "le jeton est transmis")
	print("%d/%d vérifications réussies" % [_total - _echecs, _total])
	quit()
