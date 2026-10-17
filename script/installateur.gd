# installateur.gd — Téléchargement, décompression, lancement et désinstallation des jeux.
# Les jeux vont dans <données du launcher>/jeux/<id>/ ; installes.json garde la version de chacun.
class_name Installateur
extends Node

signal progres(id: String, fraction: float, texte: String)
signal fini(id: String, ok: bool, message: String)

const REGISTRE := "user://installes.json"

var installes := {}            # id -> {version, dossier, executable}
var _telechargement: HTTPRequest = null
var _en_cours := ""

func _ready() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(REGISTRE)) if FileAccess.file_exists(REGISTRE) else null
	installes = d if d is Dictionary else {}

func _sauver() -> void:
	var f := FileAccess.open(REGISTRE, FileAccess.WRITE)
	f.store_string(JSON.stringify(installes, "\t"))

func occupe() -> bool:
	return _en_cours != ""

func dossier_jeu(id: String) -> String:
	return "user://jeux/%s" % id

# Installe (ou met à jour) un jeu : télécharge le zip de la version, l'extrait à la place de l'ancienne.
func installer(jeu: Dictionary, version: Dictionary, entetes: PackedStringArray, sys: String) -> void:
	if occupe():
		return
	var id: String = jeu["id"]
	_en_cours = id
	var zip := "user://telechargements/%s.zip" % id
	DirAccess.make_dir_recursive_absolute("user://telechargements")
	_telechargement = HTTPRequest.new()
	_telechargement.download_file = zip
	_telechargement.use_threads = true
	add_child(_telechargement)
	var url: String = version["fichier"]["url"]
	var r: Array
	if url.begins_with("file://") or url.begins_with("/"):
		DirAccess.copy_absolute(url.trim_prefix("file://"), ProjectSettings.globalize_path(zip))  # tests hors ligne
		r = [HTTPRequest.RESULT_SUCCESS, 200]
	else:
		var h := entetes.duplicate()
		h.append("Accept: application/octet-stream")
		if _telechargement.request(url, h) != OK:
			_terminer(id, false, "Téléchargement impossible.")
			return
		r = await _telechargement.request_completed
	_telechargement.queue_free()
	_telechargement = null
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		_terminer(id, false, "Téléchargement échoué (code %s)." % str(r[1]))
		return
	progres.emit(id, 0.95, "Installation…")
	var dossier := "%s/%s" % [dossier_jeu(id), version["version"]]
	var err := extraire(zip, dossier)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip))
	if err != "":
		_terminer(id, false, err)
		return
	var exe: String = jeu.get("executable", {}).get(sys, "")
	var chemin_exe := "%s/%s" % [dossier, exe]
	if exe == "" or not FileAccess.file_exists(chemin_exe):
		_terminer(id, false, "Exécutable « %s » absent de l'archive." % exe)
		return
	if sys == "linux":
		OS.execute("chmod", ["+x", ProjectSettings.globalize_path(chemin_exe)])
	elif sys == "macos":
		preparer_app_mac(ProjectSettings.globalize_path(chemin_exe))
	# L'ancienne version est supprimée une fois la nouvelle en place.
	var ancienne: Dictionary = installes.get(id, {})
	installes[id] = {"version": version["version"], "dossier": dossier, "executable": chemin_exe}
	_sauver()
	if not ancienne.is_empty() and ancienne.get("dossier", "") != dossier:
		supprimer_dossier(ancienne["dossier"])
	_terminer(id, true, "%s %s installé." % [jeu.get("nom", id), version["version"]])

func _terminer(id: String, ok: bool, message: String) -> void:
	_en_cours = ""
	fini.emit(id, ok, message)

func _process(_d: float) -> void:
	if _telechargement != null and _en_cours != "":
		var total := _telechargement.get_body_size()
		var recu := _telechargement.get_downloaded_bytes()
		if total > 0:
			progres.emit(_en_cours, 0.9 * recu / float(total), "Téléchargement : %.1f / %.1f Mo" % [recu / 1e6, total / 1e6])

# macOS : le zip ne garde pas les droits ; on rend exécutables les binaires de l'app et on retire
# l'attribut de quarantaine (sinon Gatekeeper peut refuser une app non notariée).
static func preparer_app_mac(exe: String) -> void:
	var app := app_mac(exe)
	if app == "":
		return
	for f in DirAccess.get_files_at(app.path_join("Contents/MacOS")):
		OS.execute("chmod", ["+x", app.path_join("Contents/MacOS").path_join(f)])
	OS.execute("xattr", ["-cr", app])

# « …/Jeu.app/Contents/MacOS/Jeu » -> « …/Jeu.app » (ou "" si ce n'est pas une app).
static func app_mac(exe: String) -> String:
	var app := exe.get_base_dir().get_base_dir().get_base_dir()
	return app if app.ends_with(".app") else ""

# Extrait un zip (chemins vérifiés : rien ne sort du dossier cible). "" si tout va bien.
static func extraire(zip: String, dossier: String) -> String:
	var z := ZIPReader.new()
	if z.open(ProjectSettings.globalize_path(zip)) != OK:
		return "Archive illisible."
	var base := ProjectSettings.globalize_path(dossier)
	DirAccess.make_dir_recursive_absolute(base)
	for f in z.get_files():
		if f.ends_with("/"):
			continue
		if f.begins_with("/") or ".." in f.split("/"):
			z.close()
			return "Archive refusée : chemin suspect « %s »." % f
		var cible := base.path_join(f)
		DirAccess.make_dir_recursive_absolute(cible.get_base_dir())
		var sortie := FileAccess.open(cible, FileAccess.WRITE)
		if sortie == null:
			z.close()
			return "Écriture impossible : %s" % cible
		sortie.store_buffer(z.read_file(f))
		sortie.close()
	z.close()
	return ""

func lancer(id: String) -> String:
	var j: Dictionary = installes.get(id, {})
	var exe := ProjectSettings.globalize_path(j.get("executable", ""))
	if exe == "" or not FileAccess.file_exists(exe):
		return "Jeu introuvable : réinstallez-le."
	var pid := OS.create_process(exe, [])
	dernier_pid = pid
	return "" if pid > 0 else "Le jeu n'a pas pu démarrer."

var dernier_pid := 0

func desinstaller(id: String) -> void:
	var j: Dictionary = installes.get(id, {})
	if j.is_empty():
		return
	supprimer_dossier(dossier_jeu(id))
	installes.erase(id)
	_sauver()

static func supprimer_dossier(chemin: String) -> void:
	var reel := ProjectSettings.globalize_path(chemin)
	if not reel.begins_with(OS.get_user_data_dir()):
		return  # garde-fou : on ne supprime que dans les données du launcher
	var dir := DirAccess.open(reel)
	if dir == null:
		return
	for f in dir.get_files():
		DirAccess.remove_absolute(reel.path_join(f))
	for sd in dir.get_directories():
		supprimer_dossier(reel.path_join(sd))
	DirAccess.remove_absolute(reel)
