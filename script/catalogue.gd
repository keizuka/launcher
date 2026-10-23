# catalogue.gd — Les jeux proposés et leurs versions publiées sur GitHub.
# catalogue.json : {"jeux": [{id, nom, description, image, depot: "owner/repo", prefixe_tag, executable: {linux, windows, macos}, package_android, statut}]}
# Une version = une release GitHub dont le tag commence par prefixe_tag (« rpg-ia-v »), avec un fichier
# par système : « …-linux.zip », « …-windows.zip », « …-macos.zip » (une app .app universelle),
# ou « …-android.apk » sur Android (les jeux sans APK ne sont pas listés sur téléphone).
#
# Statuts (facultatifs, « online » par défaut) :
#   online      visible et installable par les joueurs
#   bientot     visible, pas encore installable (« Bientôt »)
#   hors-ligne  visible, installation suspendue (« Hors ligne »)
#   dev         caché aux joueurs, visible seulement dans le launcher de développement
#
# En mode dev, un catalogue privé (catalogue.dev.json du dépôt launcher-dev) est fusionné par-dessus :
# il peut ajouter des jeux, changer leur statut et donner un dossier « local » à lancer sans publier.
class_name Catalogue
extends Node

signal termine(ok: bool, message: String)

const API := "https://api.github.com"
const STATUTS := ["online", "bientot", "hors-ligne", "dev"]
const CACHE_DEV := "user://catalogue-dev.json"   # copie du catalogue dev, utilisée hors ligne

var url_catalogue := "https://raw.githubusercontent.com/keizuka/launcher/main/catalogue.json"
var url_catalogue_dev := ""      # catalogue privé du mode dev (API GitHub « contents »)
var mode_dev := false
var url_api := API               # remplaçable pour les tests (serveur local)
var jeton := ""                  # jeton GitHub facultatif (dépôts privés)
var jeux: Array = []             # entrées du catalogue
var versions := {}               # id -> {tag, version, notes, date, fichier: {nom, url, taille}}
var lanceur := {}                # entrée « launcher » du catalogue (son propre dépôt)
var version_lanceur := {}        # dernière version publiée du launcher pour ce système
var erreur_dev := ""             # catalogue de développement injoignable (message affiché)

var _dev: Dictionary = {}        # contenu du catalogue dev, réécrit quand un statut change
var _dev_sha := ""

func systeme() -> String:
	match OS.get_name():
		"Android":
			return "android"
		"Windows":
			return "windows"
		"macOS":
			return "macos"
	return "linux"

# Requête de téléchargement d'un fichier de release : [url, en-têtes].
# Avec un jeton, l'URL d'API de l'asset : c'est la seule qui marche pour un dépôt privé
# (browser_download_url y répond 404). Un seul « Accept » binaire, sinon GitHub renvoie le JSON.
static func requete_fichier(fichier: Dictionary, entetes: PackedStringArray) -> Array:
	var h := PackedStringArray()
	var avec_jeton := false
	for e in entetes:
		if e.begins_with("Accept:"):
			continue
		if e.begins_with("Authorization:"):
			avec_jeton = true
		h.append(e)
	h.append("Accept: application/octet-stream")
	var api := str(fichier.get("api", ""))
	return [api if avec_jeton and api != "" else str(fichier.get("url", "")), h]

func entetes() -> PackedStringArray:
	var h := PackedStringArray(["User-Agent: launcher-keizuka", "Accept: application/vnd.github+json"])
	if jeton.strip_edges() != "":
		h.append("Authorization: Bearer " + jeton.strip_edges())
	return h

# Télécharge le catalogue (et, en mode dev, le catalogue privé) puis la dernière version de chaque jeu.
func actualiser() -> void:
	var d = await _json(url_catalogue)
	if not d is Dictionary or not d.has("jeux"):
		termine.emit(false, "Catalogue introuvable (%s)." % url_catalogue)
		return
	jeux = d["jeux"]
	lanceur = d.get("launcher", {})
	erreur_dev = ""
	_dev = {}
	_dev_sha = ""
	if mode_dev and url_catalogue_dev != "":
		var dev := await _lire_dev()
		if not dev.is_empty():
			jeux = fusionner(jeux, dev.get("jeux", []))
			if dev.has("launcher"):
				lanceur = dev["launcher"]
	jeux = visibles(jeux, mode_dev)
	versions.clear()
	version_lanceur = {}
	var depots := {}
	var echecs := []
	for j in jeux:
		if str(j.get("depot", "")) != "":
			depots[j["depot"]] = true
	if not lanceur.is_empty():
		depots[lanceur["depot"]] = true
	for depot in depots:
		var releases = await _json("%s/repos/%s/releases?per_page=100" % [url_api, depot])
		if not releases is Array:
			echecs.append(depot)
			continue
		for j in jeux:
			if str(j.get("depot", "")) == depot:
				var v := derniere_version(releases, j.get("prefixe_tag", j["id"] + "-v"), systeme())
				if not v.is_empty():
					versions[j["id"]] = v
		if not lanceur.is_empty() and lanceur["depot"] == depot:
			version_lanceur = derniere_version(releases, lanceur.get("prefixe_tag", "launcher-v"), systeme())
	# Sur Android, seuls les jeux publiés en APK ont leur place dans la liste.
	if systeme() == "android":
		jeux = jeux.filter(func(j): return versions.has(j["id"]))
	if not echecs.is_empty():
		var m := "Versions illisibles pour %s (dépôt privé ? jeton GitHub ?)." % ", ".join(echecs)
		if erreur_dev != "":
			m += "  " + erreur_dev
		termine.emit(false, m)
		return
	var message := "%d jeu%s, %d version%s disponible%s." % [jeux.size(), "x" if jeux.size() > 1 else "",
		versions.size(), "s" if versions.size() > 1 else "", "s" if versions.size() > 1 else ""]
	if erreur_dev != "":
		message = "Catalogue de développement indisponible : " + erreur_dev
	termine.emit(erreur_dev == "", message)

# Fusionne les entrées du catalogue dev par-dessus celles du catalogue public (par id).
# Une entrée dev ne peut avoir que « id » et les champs à changer ; une nouvelle entrée est
# cachée aux joueurs par défaut (statut « dev »).
static func fusionner(base: Array, ajouts: Array) -> Array:
	var resultat := base.duplicate(true)
	var index := {}
	for i in resultat.size():
		index[str(resultat[i].get("id", ""))] = i
	for e in ajouts:
		if not e is Dictionary:
			continue
		var id := str(e.get("id", ""))
		if id == "":
			continue
		if index.has(id):
			var j: Dictionary = resultat[index[id]]
			for k in e:
				if k != "id":
					j[k] = e[k]
		else:
			var copie: Dictionary = e.duplicate(true)
			if not copie.has("statut"):
				copie["statut"] = "dev"
			resultat.append(copie)
			index[id] = resultat.size() - 1
	return resultat

# Les jeux que ce build a le droit de montrer : tout en dev, tout sauf « dev » pour les joueurs.
static func visibles(liste: Array, dev: bool) -> Array:
	var sortie := []
	for j in liste:
		var statut := str(j.get("statut", "online"))
		j["statut"] = statut
		if dev or statut != "dev":
			sortie.append(j)
	return sortie

static func statut(j: Dictionary) -> String:
	return str(j.get("statut", "online"))

static func libelle_statut(s: String) -> String:
	return {"online": "En ligne", "bientot": "Bientôt", "hors-ligne": "Hors ligne", "dev": "Caché aux joueurs"}.get(s, s)

# Change le statut d'un jeu : en mémoire, puis dans le catalogue dev (commit GitHub).
# Renvoie "" si tout est publié, sinon un message expliquant ce qui n'a pas marché.
func changer_statut(id: String, s: String) -> String:
	if not s in STATUTS:
		return "Statut inconnu : %s" % s
	for j in jeux:
		if j["id"] == id:
			j["statut"] = s
	if not _dev.has("jeux"):
		_dev["jeux"] = []
	var entree: Dictionary = {}
	for e in _dev["jeux"]:
		if str(e.get("id", "")) == id:
			entree = e
			break
	if entree.is_empty():
		entree = {"id": id}
		_dev["jeux"].append(entree)
	entree["statut"] = s
	return await _ecrire_dev()

# --- Catalogue de développement ---

func _lire_dev() -> Dictionary:
	var url := url_catalogue_dev
	if url.begins_with("file://") or url.begins_with("/") or url.begins_with("user://") or url.begins_with("res://"):
		var d = JSON.parse_string(FileAccess.get_file_as_string(url.trim_prefix("file://")))
		if d is Dictionary:
			_dev = d
			_dev_sha = ""
			return d
		erreur_dev = "fichier illisible (%s)" % url
		return {}
	var r = await _json(url)
	if r is Dictionary and r.has("content"):
		_dev_sha = str(r.get("sha", ""))
		var texte := Marshalls.base64_to_utf8(str(r["content"]).replace("\n", ""))
		var d = JSON.parse_string(texte)
		if d is Dictionary:
			_dev = d
			_ecrire_cache(texte)
			return d
	erreur_dev = "jeton GitHub requis, ou dépôt privé injoignable."
	# Repli : la dernière copie connue, pour pouvoir travailler et changer les statuts hors ligne.
	var cache := FileAccess.get_file_as_string(CACHE_DEV)
	var c = JSON.parse_string(cache) if cache != "" else null
	if c is Dictionary:
		_dev = c
		return c
	return {}

func _ecrire_cache(texte: String) -> void:
	var f := FileAccess.open(CACHE_DEV, FileAccess.WRITE)
	if f != null:
		f.store_string(texte)
		f.close()

func _ecrire_dev() -> String:
	var texte := JSON.stringify(_dev, "  ")
	_ecrire_cache(texte)
	var url := url_catalogue_dev
	if url.begins_with("file://") or url.begins_with("/") or url.begins_with("user://"):
		var f := FileAccess.open(url.trim_prefix("file://"), FileAccess.WRITE)
		if f == null:
			return "écriture impossible dans %s ; statut gardé en local." % url
		f.store_string(texte)
		f.close()
		return ""
	if jeton.strip_edges() == "":
		return "statut gardé en local ; ajoutez un jeton GitHub pour publier."
	if _dev_sha == "":
		var relu = await _json(url)
		if relu is Dictionary:
			_dev_sha = str(relu.get("sha", _dev_sha))
	var h := HTTPRequest.new()
	add_child(h)
	var corps := JSON.stringify({
		"message": "launcher dev : statuts du catalogue",
		"content": Marshalls.utf8_to_base64(texte),
		"sha": _dev_sha,
		"branch": "main",
	})
	var err := h.request(url, entetes(), HTTPClient.METHOD_PUT, corps)
	if err != OK:
		h.queue_free()
		return "statut gardé en local ; publication impossible (requête refusée)."
	var r: Array = await h.request_completed
	h.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or (r[1] != 200 and r[1] != 201):
		return "statut gardé en local ; GitHub a répondu %d." % r[1]
	var rep = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	if rep is Dictionary:
		_dev_sha = str(rep.get("content", {}).get("sha", _dev_sha))
	return ""

# --- Versions publiées ---

# La release la plus récente (par numéro de version) qui a un fichier pour ce système.
static func derniere_version(releases: Array, prefixe: String, sys: String) -> Dictionary:
	var meilleure := {}
	for r in releases:
		var tag: String = r.get("tag_name", "")
		if not tag.begins_with(prefixe) or r.get("draft", false):
			continue
		var fichier := {}
		for a in r.get("assets", []):
			var nom: String = str(a.get("name", "")).to_lower()
			var conforme := nom.ends_with("-android.apk") if sys == "android" else nom.ends_with("-%s.zip" % sys)
			if conforme:
				fichier = {"nom": a["name"], "url": a["browser_download_url"], "api": str(a.get("url", "")),
					"taille": int(a.get("size", 0))}
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
