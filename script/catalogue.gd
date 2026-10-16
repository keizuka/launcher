# catalogue.gd — Les jeux proposés et leurs versions publiées sur GitHub.
# catalogue.json : {"jeux": [{id, nom, description, image, depot: "owner/repo", prefixe_tag, executable: {linux, windows}}]}
# Une version = une release GitHub dont le tag commence par prefixe_tag (« rpg-ia-v »), avec un fichier
# .zip par système : « …-linux.zip », « …-windows.zip ».
class_name Catalogue
extends Node

signal termine(ok: bool, message: String)

const API := "https://api.github.com"

var url_catalogue := "https://raw.githubusercontent.com/keizuka/jeux/main/catalogue.json"
var url_api := API             # remplaçable pour les tests (serveur local)
var jeton := ""                # jeton GitHub facultatif (dépôts privés)
var jeux: Array = []           # entrées du catalogue
var versions := {}             # id -> {tag, version, notes, date, fichier: {nom, url, taille}}

func systeme() -> String:
	return "windows" if OS.get_name() == "Windows" else "linux"

func entetes() -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: launcher-keizuka", "Accept: application/vnd.github+json"])
	if jeton.strip_edges() != "":
		h.append("Authorization: Bearer " + jeton.strip_edges())
	return h

# Télécharge le catalogue puis la dernière version de chaque jeu.
func actualiser() -> void:
	var d = await _json(url_catalogue)
	if not d is Dictionary or not d.has("jeux"):
		termine.emit(false, "Catalogue introuvable (%s)." % url_catalogue)
		return
	jeux = d["jeux"]
	versions.clear()
	var depots := {}
	for j in jeux:
		depots[j["depot"]] = true
	for depot in depots:
		var releases = await _json("%s/repos/%s/releases?per_page=100" % [url_api, depot])
		if not releases is Array:
			termine.emit(false, "Impossible de lire les versions de %s (dépôt privé ? limite de l'API GitHub ?)." % depot)
			return
		for j in jeux:
			if j["depot"] == depot:
				var v := derniere_version(releases, j.get("prefixe_tag", j["id"] + "-v"), systeme())
				if not v.is_empty():
					versions[j["id"]] = v
	termine.emit(true, "%d jeu%s, %d version%s disponible%s." % [jeux.size(), "x" if jeux.size() > 1 else "",
		versions.size(), "s" if versions.size() > 1 else "", "s" if versions.size() > 1 else ""])

# La release la plus récente (par numéro de version) qui a un fichier pour ce système.
static func derniere_version(releases: Array, prefixe: String, sys: String) -> Dictionary:
	var meilleure := {}
	for r in releases:
		var tag: String = r.get("tag_name", "")
		if not tag.begins_with(prefixe) or r.get("draft", false):
			continue
		var fichier := {}
		for a in r.get("assets", []):
			if str(a.get("name", "")).to_lower().ends_with("-%s.zip" % sys):
				fichier = {"nom": a["name"], "url": a["browser_download_url"], "taille": int(a.get("size", 0))}
		if fichier.is_empty():
			continue
		var version := tag.trim_prefix(prefixe)
		if meilleure.is_empty() or comparer(version, meilleure["version"]) > 0:
			meilleure = {"tag": tag, "version": version, "notes": r.get("body", ""), "date": str(r.get("published_at", "")).left(10),
				"fichier": fichier}
	return meilleure

# « 1.10.0 » > « 1.9.2 » : comparaison nombre par nombre. Renvoie -1, 0 ou 1.
static func comparer(a: String, b: String) -> int:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0

func _json(url: String):
	if url.begins_with("file://") or url.begins_with("res://") or url.begins_with("user://") or url.begins_with("/"):
		return JSON.parse_string(FileAccess.get_file_as_string(url.trim_prefix("file://")))
	var h := HTTPRequest.new()
	add_child(h)
	var err := h.request(url, entetes())
	if err != OK:
		h.queue_free()
		return null
	var r: Array = await h.request_completed
	h.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return null
	return JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
