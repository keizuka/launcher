# installateur.gd — Téléchargement, décompression, lancement et désinstallation des jeux.
# Les jeux vont dans <données du launcher>/jeux/<id>/ ; installes.json garde la version de chacun.
# Sur Android : le jeu est un APK téléchargé puis installé par le système (l'utilisateur confirme),
# et il se lance par son paquet Android ; sur ordinateur, le zip est extrait et l'exécutable lancé.
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
# Sur Android, télécharge l'APK et ouvre l'installateur système (voir _installer_apk).
func installer(jeu: Dictionary, version: Dictionary, entetes: PackedStringArray, sys: String) -> void:
	if occupe():
		return
	var id: String = jeu["id"]
	_en_cours = id
	if sys == "android":
		await _installer_apk(jeu, version, entetes)
		return
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

# Android : télécharge l'APK puis ouvre l'installateur système du téléphone (l'utilisateur confirme,
# et peut devoir autoriser d'abord les installations venant de ce launcher dans les réglages du téléphone).
func _installer_apk(jeu: Dictionary, version: Dictionary, entetes: PackedStringArray) -> void:
	var id: String = jeu["id"]
	var apk := "user://jeux/%s/%s.apk" % [id, version["version"]]
	DirAccess.make_dir_recursive_absolute(dossier_jeu(id))
	_telechargement = HTTPRequest.new()
	_telechargement.download_file = apk
	_telechargement.use_threads = true
	add_child(_telechargement)
	var url: String = version["fichier"]["url"]
	var r: Array
	if url.begins_with("file://") or url.begins_with("/"):
		DirAccess.copy_absolute(url.trim_prefix("file://"), ProjectSettings.globalize_path(apk))  # tests hors ligne
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
	var ancienne: Dictionary = installes.get(id, {})
	installes[id] = {"version": version["version"], "dossier": dossier_jeu(id), "executable": "",
		"apk": apk, "package": jeu.get("package_android", "")}
	_sauver()
	var ancien_apk: String = ancienne.get("apk", "")
	if ancien_apk != "" and ancien_apk != apk:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(ancien_apk))
	var err := ouvrir_installation_apk(apk)
	_terminer(id, err == "", err if err != "" else
		"%s %s : confirmez l'installation dans la fenêtre d'Android." % [jeu.get("nom", id), version["version"]])

# Android : ouvre l'installateur système du téléphone pour un APK. L'URI est donnée par le FileProvider
# que Godot embarque dans chaque APK (<paquet>.fileprovider) : sans cela, Android refuse le fichier.
static func ouvrir_installation_apk(apk: String) -> String:
	if OS.get_name() != "Android":
		return "L'installation d'APK est réservée à Android."
	var runtime = Engine.get_singleton("AndroidRuntime")
	var activite = runtime.getActivity() if runtime != null else null
	if activite == null:
		return "Activité Android introuvable."
	var f = JavaClassWrapper.wrap("java.io.File").File(ProjectSettings.globalize_path(apk))
	if not f.exists():
		return "Fichier APK introuvable."
	var ctx = activite.getApplicationContext()
	var FileProvider = JavaClassWrapper.wrap("androidx.core.content.FileProvider")
	var uri = FileProvider.getUriForFile(ctx, str(ctx.getPackageName()) + ".fileprovider", f)
	if uri == null or JavaClassWrapper.get_exception() != null:
		return "URI du fichier APK refusée."
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	var intent = Intent.Intent()
	intent.setAction(Intent.ACTION_VIEW)
	intent.setDataAndType(uri, "application/vnd.android.package-archive")
	intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK)
	activite.startActivity(intent)
	if JavaClassWrapper.get_exception() != null:
		return "Impossible d'ouvrir l'installateur Android : %s" % str(JavaClassWrapper.get_exception())
	return ""

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

# Sur Android, le jeu est une application : on lance son paquet (il doit être installé).
func lancer(id: String) -> String:
	var j: Dictionary = installes.get(id, {})
	if OS.get_name() == "Android":
		if j.is_empty():
			return "Jeu introuvable : réinstallez-le."
		return lancer_paquet(str(j.get("package", "")))
	var exe := ProjectSettings.globalize_path(j.get("executable", ""))
	if exe == "" or not FileAccess.file_exists(exe):
		return "Jeu introuvable : réinstallez-le."
	var pid := OS.create_process(exe, [])
	dernier_pid = pid
	return "" if pid > 0 else "Le jeu n'a pas pu démarrer."

# Android : ouvre l'application correspondant au paquet (déjà installée par le système).
# Android 11+ filtre les paquets étrangers au launcher (le manifeste Godot n'a pas de <queries>) :
# un intent implicite ne résout plus rien. On vise donc l'activité launcher du jeu par un
# composant explicite, que le filtrage ne touche pas ; l'implicite reste en dernier recours.
static func lancer_paquet(paquet: String) -> String:
	if OS.get_name() != "Android":
		return "Le lancement par paquet est réservé à Android."
	if paquet.strip_edges() == "":
		return "Ce jeu n'a pas de paquet Android : lancez-le depuis l'écran d'accueil du téléphone."
	var runtime = Engine.get_singleton("AndroidRuntime")
	var activite = runtime.getActivity() if runtime != null else null
	if activite == null:
		return "Activité Android introuvable."
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	# Le template Godot nomme les activités de façon absolue et identique dans tous les jeux :
	# com.godot.game.GodotApp (+ l'alias exporté GodotAppLauncher). Les noms relatifs au paquet
	# restent en secours pour un jeu qui aurait renommé ses activités.
	for classe in ["com.godot.game.GodotAppLauncher", "com.godot.game.GodotApp",
			paquet + ".GodotAppLauncher", paquet + ".GodotApp"]:
		var intent = Intent.Intent()
		intent.setAction(Intent.ACTION_MAIN)
		intent.addCategory(Intent.CATEGORY_LAUNCHER)
		intent.setClassName(paquet, classe)
		intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
		activite.startActivity(intent)
		if JavaClassWrapper.get_exception() == null:
			return ""
	var intent = Intent.Intent()
	intent.setAction(Intent.ACTION_MAIN)
	intent.addCategory(Intent.CATEGORY_LAUNCHER)
	intent.setPackage(paquet)
	intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
	activite.startActivity(intent)
	if JavaClassWrapper.get_exception() != null:
		return "Le jeu n'est pas installé (désinstallé depuis le téléphone ?) : réinstallez-le."
	return ""

# Android : le paquet est-il encore installé ? L'utilisateur peut désinstaller hors du launcher,
# mais Android 11+ masque les paquets étrangers au launcher (pas de <queries> dans le manifeste
# Godot) : sans preuve possible du système, on fait confiance au registre — un lancement raté le
# signalera au joueur.
static func paquet_installe(paquet: String) -> bool:
	if OS.get_name() != "Android":
		return false
	# Android : confiance au registre installes.json. Sans <queries> dans le manifeste, le
	# paramètre (le paquet à vérifier) est justement ce que le système nous cache.
	return paquet != null

var dernier_pid := 0

func desinstaller(id: String) -> void:
	var j: Dictionary = installes.get(id, {})
	if j.is_empty():
		return
	# Sur Android, la désinstallation passe par le système (l'utilisateur confirme).
	if OS.get_name() == "Android" and str(j.get("package", "")) != "":
		_demande_desinstallation(str(j["package"]))
	supprimer_dossier(dossier_jeu(id))
	installes.erase(id)
	_sauver()

# Android : ouvre la désinstallation système du paquet (ACTION_DELETE).
static func _demande_desinstallation(paquet: String) -> void:
	if OS.get_name() != "Android":
		return
	var runtime = Engine.get_singleton("AndroidRuntime")
	var activite = runtime.getActivity() if runtime != null else null
	if activite == null:
		return
	var Uri = JavaClassWrapper.wrap("android.net.Uri")
	var Intent = JavaClassWrapper.wrap("android.content.Intent")
	var intent = Intent.Intent()
	intent.setAction(Intent.ACTION_DELETE)
	intent.setData(Uri.parse("package:" + paquet))
	intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
	activite.startActivity(intent)

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
