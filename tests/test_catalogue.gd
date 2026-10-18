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
		assets.append({"name": f, "browser_download_url": "https://x/" + f, "size": 10})
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
	print("%d/%d vérifications réussies" % [_total - _echecs, _total])
	quit()
