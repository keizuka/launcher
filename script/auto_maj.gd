# auto_maj.gd — Le launcher se met à jour lui-même. Il est exporté en un seul fichier (données intégrées) :
# la nouvelle version est téléchargée, l'exécutable en cours est renommé en « .old » (permis même sous Windows
# pour un programme lancé), la nouvelle prend sa place et est relancée ; la copie « .old » est supprimée au
# démarrage suivant.
class_name AutoMaj
extends Node

signal progres(fraction: float, texte: String)
signal echec(message: String)

static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))

# Seulement pour le launcher exporté sur ordinateur : lancé depuis Godot, il n'y a pas d'exécutable à
# remplacer. Sur Android, le launcher se met à jour avec son APK (voir _mettre_a_jour_launcher).
static func possible() -> bool:
	return OS.has_feature("template") and OS.get_name() != "Android" and OS.get_name() != "iOS"

static func nettoyer() -> void:
	if possible():
		var ancien := OS.get_executable_path() + ".old"
		if FileAccess.file_exists(ancien):
			DirAccess.remove_absolute(ancien)
		var app := Installateur.app_mac(OS.get_executable_path())
		if app != "" and DirAccess.dir_exists_absolute(app + ".old"):
			OS.execute("rm", ["-rf", app + ".old"])  # seulement l'ancienne app laissée par la mise à jour

func appliquer(v: Dictionary, executable: String, entetes: PackedStringArray, args_relance: PackedStringArray) -> void:
	var cible := OS.get_executable_path()
	var dossier := cible.get_base_dir()
	var app := Installateur.app_mac(cible)
	if app != "":
		dossier = app.get_base_dir()  # sous macOS on remplace le paquet .app entier
	# Le dossier doit être modifiable (pas Program Files sans droits, pas un dossier système).
	var essai := dossier.path_join(".test_ecriture")
	var f := FileAccess.open(essai, FileAccess.WRITE)
	if f == null:
		echec.emit("Le dossier du launcher (%s) n'est pas modifiable : déplacez-le dans vos documents, puis réessayez." % dossier)
		return
	f.close()
	DirAccess.remove_absolute(essai)
	var zip := "user://maj_launcher.zip"
	var url: String = v["fichier"]["url"]
	if url.begins_with("file://") or url.begins_with("/"):
		DirAccess.copy_absolute(url.trim_prefix("file://"), ProjectSettings.globalize_path(zip))
	else:
		var h := HTTPRequest.new()
		h.download_file = zip
		h.use_threads = true
		add_child(h)
		var e := entetes.duplicate()
		e.append("Accept: application/octet-stream")
		if h.request(url, e) != OK:
			echec.emit("Téléchargement impossible.")
			return
		progres.emit(0.1, "Téléchargement du launcher %s…" % v["version"])
		var r: Array = await h.request_completed
		h.queue_free()
		if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
			echec.emit("Téléchargement du launcher échoué (code %s)." % str(r[1]))
			return
	progres.emit(0.8, "Installation du launcher %s…" % v["version"])
	var temp := "user://maj_launcher"
	Installateur.supprimer_dossier(temp)
	var err := Installateur.extraire(zip, temp)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(zip))
	var nouveau := ProjectSettings.globalize_path(temp.path_join(executable))
	if err != "" or not FileAccess.file_exists(nouveau):
		echec.emit(err if err != "" else "Archive du launcher incomplète.")
		return
	if app != "":
		_remplacer_app(app, nouveau, args_relance, temp)
		return
	var ancien := cible + ".old"
	if FileAccess.file_exists(ancien):
		DirAccess.remove_absolute(ancien)
	if DirAccess.rename_absolute(cible, ancien) != OK:
		echec.emit("Impossible de remplacer le launcher en cours d'exécution.")
		return
	if DirAccess.copy_absolute(nouveau, cible) != OK:
		DirAccess.rename_absolute(ancien, cible)  # on remet l'ancien en place
		echec.emit("Copie de la nouvelle version impossible.")
		return
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", cible])
	# Licences livrées avec la nouvelle version.
	var lic := ProjectSettings.globalize_path(temp.path_join("licences"))
	if DirAccess.dir_exists_absolute(lic):
		DirAccess.make_dir_recursive_absolute(dossier.path_join("licences"))
		for x in DirAccess.get_files_at(lic):
			DirAccess.copy_absolute(lic.path_join(x), dossier.path_join("licences").path_join(x))
	Installateur.supprimer_dossier(temp)
	OS.create_process(cible, args_relance)
	get_tree().quit()

# macOS : « Launcher.app » devient « Launcher.app.old », la nouvelle app prend sa place et est relancée.
func _remplacer_app(app: String, nouveau_exe: String, args_relance: PackedStringArray, temp: String) -> void:
	var nouvelle_app := Installateur.app_mac(nouveau_exe)
	var ancien := app + ".old"
	if DirAccess.dir_exists_absolute(ancien):
		OS.execute("rm", ["-rf", ancien])
	# mv : fonctionne aussi d'un volume à l'autre (données du launcher → Applications).
	if nouvelle_app == "" or OS.execute("mv", [app, ancien]) != 0:
		echec.emit("Impossible de remplacer l'application du launcher (déplacez-la dans Applications ou vos documents).")
		return
	if OS.execute("mv", [nouvelle_app, app]) != 0:
		OS.execute("mv", [ancien, app])
		echec.emit("Installation de la nouvelle version impossible.")
		return
	Installateur.preparer_app_mac(app.path_join("Contents/MacOS").path_join(nouveau_exe.get_file()))
	Installateur.supprimer_dossier(temp)
	OS.create_process(app.path_join("Contents/MacOS").path_join(nouveau_exe.get_file()), args_relance)
	get_tree().quit()
