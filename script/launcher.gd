# launcher.gd — Écran du launcher : la liste des jeux à gauche, la fiche du jeu choisi à droite
# (installer, mettre à jour, jouer, désinstaller, nouveautés de la version).
extends Control

const REGLAGES := "user://reglages.json"
const VERIFICATION_AUTO_S := 1800.0   # nouvelle vérification toutes les 30 minutes

var catalogue := Catalogue.new()
var installateur := Installateur.new()
var auto_maj := AutoMaj.new()
var _bandeau_maj: HBoxContainer
var _liste: VBoxContainer
var _etat: Label
var _choisi := ""
var _cadre: PanelContainer
var _fond: TextureRect
var _fiche: VBoxContainer
var _image: TextureRect
var _nom: Label
var _description: Label
var _versions: Label
var _boutons: HBoxContainer
var _barre: ProgressBar
var _barre_texte: Label
var _notes: RichTextLabel
var _reglages: PanelContainer
var _champ_catalogue: LineEdit
var _champ_jeton: LineEdit
var _champ_catalogue_dev: LineEdit
var _statut_ligne: HBoxContainer
var _statut_choix: OptionButton
var _statut_aide: Label
var _corps: BoxContainer
var _tete: BoxContainer
var _defil: ScrollContainer
var _images := {}            # url -> Texture2D (vignettes du catalogue)
var _attente_auto := VERIFICATION_AUTO_S

func _ready() -> void:
	get_tree().root.theme = ThemeLauncher.creer()
	RenderingServer.set_default_clear_color(ThemeLauncher.FOND)
	# Build « dev » (préréglage d'export avec la fonctionnalité « dev ») ou option --mode-dev :
	# les jeux cachés aux joueurs apparaissent, les statuts se modifient, les builds locales se lancent.
	catalogue.mode_dev = OS.has_feature("dev") or "--mode-dev" in OS.get_cmdline_user_args()
	if catalogue.mode_dev:
		catalogue.url_catalogue_dev = "https://api.github.com/repos/keizuka/launcher-dev/contents/catalogue.dev.json"
	add_child(catalogue)
	add_child(installateur)
	add_child(auto_maj)
	AutoMaj.nettoyer()
	_lire_reglages()
	_options_ligne_de_commande()
	# Téléphone/tablette : l'interface 1180×720 étirée à l'écran (comme les jeux de Keizuka).
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	_construire()
	# Un téléchargement lancé avant la fermeture reprend : on sélectionne ce jeu pour voir sa barre.
	_choisi = installateur.jeu_en_cours()
	get_viewport().size_changed.connect(_maj_fond)
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		get_window().size_changed.connect(_ajuster_orientation)
		_ajuster_orientation.call_deferred()
	catalogue.termine.connect(_sur_catalogue)
	installateur.progres.connect(func(id: String, f: float, t: String):
		if id == _choisi:
			_barre.visible = true
			_barre.value = f
			_barre_texte.text = t)
	installateur.fini.connect(func(id: String, ok: bool, m: String):
		_etat.text = m
		_etat.add_theme_color_override("font_color", ThemeLauncher.TEXTE if ok else ThemeLauncher.DANGER)
		_barre.visible = false
		_barre_texte.text = ""
		_maj_liste()
		_maj_fiche()
		if _auto_suivant.is_valid():
			_auto_suivant.call())
	auto_maj.progres.connect(func(_f: float, t: String): _etat.text = t)
	auto_maj.echec.connect(func(m: String):
		_etat.text = m
		_etat.add_theme_color_override("font_color", ThemeLauncher.DANGER)
		_maj_bandeau_launcher())
	if "--apres-maj" in OS.get_cmdline_user_args():
		_etat.text = "Launcher mis à jour : version %s." % AutoMaj.version()
		print("APRES MAJ version ", AutoMaj.version())
	_verifier()

func _process(delta: float) -> void:
	_attente_auto -= delta
	if _attente_auto <= 0.0 and not installateur.occupe():
		_attente_auto = VERIFICATION_AUTO_S
		_verifier()

# --- Interface ---

func _construire() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Fond Keizuka Production, assombri pour que le texte reste lisible.
	_fond = TextureRect.new()
	_fond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fond)
	_maj_fond()
	var voile := ColorRect.new()
	voile.color = Color(ThemeLauncher.FOND, 0.62)
	voile.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	voile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(voile)
	var marge := MarginContainer.new()
	marge.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for c in ["left", "right", "top", "bottom"]:
		marge.add_theme_constant_override("margin_" + c, 20)
	add_child(marge)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	marge.add_child(col)
	var tete := BoxContainer.new()
	_tete = tete
	col.add_child(tete)
	var ligne_titre := HBoxContainer.new()
	ligne_titre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ligne_titre.add_theme_constant_override("separation", 14)
	tete.add_child(ligne_titre)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/images/icone.png")
	logo.custom_minimum_size = Vector2(56, 56)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.tooltip_text = "Keizuka Production"
	ligne_titre.add_child(logo)
	var titre := Label.new()
	titre.text = "Mes jeux — mode dev" if catalogue.mode_dev else "Mes jeux"
	titre.tooltip_text = "Launcher version %s%s" % [AutoMaj.version(), " (dev)" if catalogue.mode_dev else ""]
	titre.theme_type_variation = "Titre"
	if catalogue.mode_dev:
		titre.add_theme_color_override("font_color", ThemeLauncher.LAITON)
	titre.add_theme_font_size_override("font_size", 40)
	titre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ligne_titre.add_child(titre)
	var boutons_tete := HBoxContainer.new()
	boutons_tete.add_theme_constant_override("separation", 8)
	tete.add_child(boutons_tete)
	var verif := Button.new()
	verif.text = "Vérifier les mises à jour"
	verif.pressed.connect(_verifier)
	boutons_tete.add_child(verif)
	var regl := Button.new()
	regl.text = "Réglages"
	regl.pressed.connect(func(): _reglages.visible = not _reglages.visible)
	boutons_tete.add_child(regl)

	_etat = Label.new()
	_etat.theme_type_variation = "Discret"
	_etat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_etat)
	_bandeau_maj = HBoxContainer.new()
	_bandeau_maj.visible = false
	col.add_child(_bandeau_maj)
	_reglages = PanelContainer.new()
	_reglages.visible = false
	col.add_child(_reglages)
	var rg := GridContainer.new()
	rg.columns = 2
	_reglages.add_child(rg)
	var l1 := Label.new()
	l1.text = "Catalogue"
	rg.add_child(l1)
	_champ_catalogue = LineEdit.new()
	_champ_catalogue.text = catalogue.url_catalogue
	_champ_catalogue.custom_minimum_size = Vector2(620, 0)
	rg.add_child(_champ_catalogue)
	var l2 := Label.new()
	l2.text = "Jeton GitHub (facultatif)"
	if catalogue.mode_dev:
		var ld := Label.new()
		ld.text = "Catalogue dev (privé)"
		rg.add_child(ld)
		_champ_catalogue_dev = LineEdit.new()
		_champ_catalogue_dev.text = catalogue.url_catalogue_dev
		_champ_catalogue_dev.placeholder_text = "Fichier catalogue.dev.json du dépôt privé (API GitHub)"
		_champ_catalogue_dev.custom_minimum_size = Vector2(620, 0)
		rg.add_child(_champ_catalogue_dev)
	rg.add_child(l2)
	_champ_jeton = LineEdit.new()
	_champ_jeton.secret = true
	_champ_jeton.placeholder_text = "Requis pour le catalogue dev et les dépôts privés" if catalogue.mode_dev else "Seulement pour un jeu dans un dépôt privé où vous êtes invité"
	_champ_jeton.text = catalogue.jeton
	rg.add_child(_champ_jeton)
	rg.add_child(Control.new())
	var enreg := Button.new()
	enreg.text = "Enregistrer"
	enreg.pressed.connect(func():
		catalogue.url_catalogue = _champ_catalogue.text.strip_edges()
		if _champ_catalogue_dev != null:
			catalogue.url_catalogue_dev = _champ_catalogue_dev.text.strip_edges()
		catalogue.jeton = _champ_jeton.text.strip_edges()
		_sauver_reglages()
		_reglages.visible = false
		_verifier())
	rg.add_child(enreg)

	var corps := BoxContainer.new()
	_corps = corps
	corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corps.add_theme_constant_override("separation", 16)
	col.add_child(corps)
	var defil := ScrollContainer.new()
	_defil = defil
	defil.custom_minimum_size = Vector2(330, 0)
	defil.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	corps.add_child(defil)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 8)
	defil.add_child(_liste)

	_cadre = PanelContainer.new()
	# Panneau de la fiche : fond un peu transparent pour laisser voir le fond du launcher.
	_cadre.add_theme_stylebox_override("panel", ThemeLauncher.boite(Color(ThemeLauncher.SURFACE, 0.72), ThemeLauncher.LIGNE, 10, 16))
	_cadre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cadre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corps.add_child(_cadre)
	_fiche = VBoxContainer.new()
	_fiche.add_theme_constant_override("separation", 10)
	_cadre.add_child(_fiche)
	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(0, 220)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_image.clip_contents = true
	_fiche.add_child(_image)
	_nom = Label.new()
	_nom.theme_type_variation = "Titre"
	_nom.add_theme_font_size_override("font_size", 32)
	_fiche.add_child(_nom)
	_description = Label.new()
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fiche.add_child(_description)
	_versions = Label.new()
	_versions.theme_type_variation = "Discret"
	_fiche.add_child(_versions)
	# Mode dev : le statut public du jeu se choisit ici (et se publie dans le catalogue dev).
	_statut_ligne = HBoxContainer.new()
	_statut_ligne.add_theme_constant_override("separation", 10)
	_statut_ligne.visible = false
	_fiche.add_child(_statut_ligne)
	var etiquette := Label.new()
	etiquette.text = "Statut public :"
	_statut_ligne.add_child(etiquette)
	_statut_choix = OptionButton.new()
	for s in Catalogue.STATUTS:
		_statut_choix.add_item(Catalogue.libelle_statut(s))
	_statut_choix.item_selected.connect(func(i: int): _changer_statut(Catalogue.STATUTS[i]))
	_statut_ligne.add_child(_statut_choix)
	_statut_aide = Label.new()
	_statut_aide.theme_type_variation = "Discret"
	_statut_aide.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_statut_aide.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_statut_ligne.add_child(_statut_aide)
	_boutons = HBoxContainer.new()
	_fiche.add_child(_boutons)
	_barre = ProgressBar.new()
	_barre.max_value = 1.0
	_barre.step = 0.001
	_barre.show_percentage = false
	_barre.custom_minimum_size = Vector2(0, 10)
	_barre.visible = false
	_fiche.add_child(_barre)
	_barre_texte = Label.new()
	_barre_texte.theme_type_variation = "Discret"
	_fiche.add_child(_barre_texte)
	_notes = RichTextLabel.new()
	_notes.bbcode_enabled = true
	_notes.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_fiche.add_child(_notes)
	_maj_fiche()

func _verifier() -> void:
	_etat.text = "Recherche des nouveautés…"
	_etat.add_theme_color_override("font_color", ThemeLauncher.DISCRET)
	catalogue.actualiser()

func _sur_catalogue(ok: bool, message: String) -> void:
	_etat.text = message
	_etat.add_theme_color_override("font_color", ThemeLauncher.DISCRET if ok else ThemeLauncher.DANGER)
	var a_maj := catalogue.jeux.filter(func(j): return _etat_jeu(j["id"]) == "maj")
	if not a_maj.is_empty():
		_etat.text = "Mise à jour disponible : " + ", ".join(a_maj.map(func(j): return j["nom"]))
		_etat.add_theme_color_override("font_color", ThemeLauncher.LAITON)
	_maj_bandeau_launcher()
	# Aucun jeu n'est présélectionné : le fond du launcher se voit, la fiche s'ouvre au premier clic.
	_maj_liste()
	_maj_fiche()
	if _auto_suivant.is_valid() and not _auto_lance:
		_auto_lance = true
		_auto_suivant.call()

# Bandeau « nouvelle version du launcher » quand le dépôt du launcher a plus récent que nous.
func _maj_bandeau_launcher() -> void:
	for c in _bandeau_maj.get_children():
		c.queue_free()
	var v: Dictionary = catalogue.version_lanceur
	var plus_recent := not v.is_empty() and Catalogue.comparer(v["version"], AutoMaj.version()) > 0
	_bandeau_maj.visible = plus_recent
	if not plus_recent:
		return
	var l := Label.new()
	l.text = "Nouvelle version du launcher : %s (vous avez %s)." % [v["version"], AutoMaj.version()]
	l.add_theme_color_override("font_color", ThemeLauncher.LAITON)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bandeau_maj.add_child(l)
	# Sur Android, la mise à jour passe par le téléchargement de l'APK (comme pour les jeux).
	var mise_a_jour := AutoMaj.possible() or catalogue.systeme() == "android"
	var b := Button.new()
	b.text = "Mettre à jour le launcher" if mise_a_jour else "Mise à jour : téléchargez-la sur GitHub"
	b.disabled = not mise_a_jour or installateur.occupe()
	b.pressed.connect(_mettre_a_jour_launcher)
	_bandeau_maj.add_child(b)

func _mettre_a_jour_launcher() -> void:
	for b in _bandeau_maj.get_children():
		if b is Button:
			b.disabled = true
	if catalogue.systeme() == "android":
		installateur.installer({"id": "launcher", "nom": "Launcher"}, catalogue.version_lanceur,
			catalogue.entetes(), "android")
		return
	var exe: String = catalogue.lanceur.get("executable", {}).get(catalogue.systeme(), "")
	# On relance avec les mêmes options (adresse du catalogue, tests), plus --apres-maj.
	var args := PackedStringArray(["--"])
	var a := OS.get_cmdline_user_args()
	for i in a.size():
		if a[i] == "--auto":
			continue
		if i > 0 and a[i - 1] == "--auto":
			continue
		args.append(a[i])
	args.append("--apres-maj")
	auto_maj.appliquer(catalogue.version_lanceur, exe, catalogue.entetes(), args)

# "absent", "a_jour", "maj" ou "indisponible" (aucune version pour ce système)
func _etat_jeu(id: String) -> String:
	var v: Dictionary = catalogue.versions.get(id, {})
	var i: Dictionary = installateur.installes.get(id, {})
	# Android : le jeu peut avoir été désinstallé hors du launcher.
	if not i.is_empty() and OS.get_name() == "Android" and not Installateur.paquet_installe(str(i.get("package", ""))):
		i = {}
	if i.is_empty():
		return "absent" if not v.is_empty() else "indisponible"
	if not v.is_empty() and Catalogue.comparer(v["version"], i["version"]) > 0:
		return "maj"
	return "a_jour"

func _maj_liste() -> void:
	for c in _liste.get_children():
		c.queue_free()
	for j in catalogue.jeux:
		var id: String = j["id"]
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = id == _choisi
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 64)
		b.icon = _vignette(j.get("icone", j.get("image", "")))
		b.expand_icon = true
		var badge := _badge_jeu(j)
		b.text = "  %s\n  %s" % [j["nom"], badge[0]]
		if badge[1].a > 0.0:
			b.add_theme_color_override("font_color", badge[1])
		b.pressed.connect(func():
			_choisi = id
			_maj_liste()
			_maj_fiche())
		_liste.add_child(b)

# [texte, couleur] du sous-titre d'un jeu : le statut public d'abord, l'état d'installation ensuite.
func _badge_jeu(j: Dictionary) -> Array:
	match Catalogue.statut(j):
		"bientot":
			return ["Bientôt", ThemeLauncher.LAITON]
		"hors-ligne":
			return ["Hors ligne", ThemeLauncher.DANGER]
		"dev":
			return ["DEV — caché aux joueurs", ThemeLauncher.LAITON]
	var etat := _etat_jeu(j["id"])
	return [{"absent": "Non installé", "a_jour": "À jour", "maj": "Mise à jour !", "indisponible": "Bientôt"}[etat],
		ThemeLauncher.LAITON if etat == "maj" else Color.TRANSPARENT]

func _jeu(id: String) -> Dictionary:
	for j in catalogue.jeux:
		if j["id"] == id:
			return j
	return {}

func _maj_fiche() -> void:
	for c in _boutons.get_children():
		c.queue_free()
	var j := _jeu(_choisi)
	if j.is_empty():
		# Rien de choisi : la fiche se cache et le fond du launcher occupe l'écran. Le message
		# « Aucun jeu » n'apparaît que si le catalogue est réellement vide ou injoignable.
		_cadre.visible = catalogue.jeux.is_empty()
		_statut_ligne.visible = false
		if _cadre.visible:
			_nom.text = "Aucun jeu"
			_description.text = "Le catalogue est vide ou injoignable. Vérifiez votre connexion, ou l'adresse du catalogue dans les réglages."
			_versions.text = ""
			_notes.text = ""
			_image.texture = null
		return
	_cadre.visible = true
	_nom.text = j["nom"]
	_description.text = j.get("description", "")
	_image.texture = _vignette(j.get("image", ""))
	_image.visible = _image.texture != null
	var v: Dictionary = catalogue.versions.get(_choisi, {})
	var i: Dictionary = installateur.installes.get(_choisi, {})
	var statut := Catalogue.statut(j)
	var local := str(j.get("local", ""))
	var lignes := []
	if catalogue.mode_dev or statut != "online":
		lignes.append("Statut : %s" % Catalogue.libelle_statut(statut))
	lignes.append("Installée : %s   ·   Dernière version : %s%s" % [i.get("version", "aucune"),
		v.get("version", "—"), ("  (%s, %.0f Mo)" % [v["date"], v["fichier"]["taille"] / 1e6]) if not v.is_empty() else ""])
	if local != "":
		lignes.append("Build local : %s" % local)
	_versions.text = "\n".join(lignes)
	_notes.text = ("[b]Nouveautés de la version %s[/b]\n%s" % [v["version"], v.get("notes", "")]) if not v.is_empty() else ""
	_statut_ligne.visible = catalogue.mode_dev
	if catalogue.mode_dev:
		_statut_choix.selected = maxi(0, Catalogue.STATUTS.find(statut))
		_statut_aide.text = {"online": "visible et installable par les joueurs",
			"bientot": "visible, installation fermée",
			"hors-ligne": "visible, téléchargement suspendu",
			"dev": "invisible pour les joueurs, vous seuls le voyez"}.get(statut, "")
	var occupe := installateur.occupe()
	if catalogue.mode_dev and local != "":
		_bouton("Lancer (build local)", _jouer_local, false)
	match statut:
		"bientot":
			_bouton("Bientôt disponible", func(): pass, true)
		"hors-ligne":
			if i.is_empty():
				_bouton("Hors ligne", func(): pass, true)
			else:
				_bouton("Jouer", _jouer, occupe)
		_:
			match _etat_jeu(_choisi):
				"absent":
					_bouton("Installer", _installer, occupe)
				"maj":
					_bouton("Mettre à jour", _installer, occupe)
					_bouton("Jouer (version actuelle)", _jouer, occupe)
				"a_jour":
					_bouton("Jouer", _jouer, occupe)
	if not i.is_empty():
		_bouton("Désinstaller", func():
			installateur.desinstaller(_choisi)
			_etat.text = ("%s : confirmez la désinstallation dans la fenêtre d'Android." % j["nom"]
				) if OS.get_name() == "Android" else "%s désinstallé." % j["nom"]
			_maj_liste()
			_maj_fiche(), occupe)

# Mode dev : lance le build présent dans le dossier « local » du catalogue dev, sans rien publier.
func _jouer_local() -> void:
	var j := _jeu(_choisi)
	var dossier := str(j.get("local", ""))
	var exe: String = str(j.get("executable", {}).get(catalogue.systeme(), ""))
	if dossier == "" or exe == "":
		_etat.text = "%s : aucun build local indiqué dans le catalogue dev." % j.get("nom", _choisi)
		_etat.add_theme_color_override("font_color", ThemeLauncher.DANGER)
		return
	var chemin := dossier if dossier.ends_with(exe) else dossier.path_join(exe)
	if not chemin.begins_with("/"):
		chemin = ProjectSettings.globalize_path(chemin)
	if not FileAccess.file_exists(chemin):
		_etat.text = "%s : build local introuvable (%s)." % [j["nom"], chemin]
		_etat.add_theme_color_override("font_color", ThemeLauncher.DANGER)
		return
	var pid := OS.create_process(chemin, [])
	if pid <= 0:
		# Publication .NET ou export fraîchement décompressé : le bit « exécutable » peut manquer.
		OS.execute("chmod", ["+x", chemin])
		pid = OS.create_process(chemin, [])
	_dernier_pid = pid
	_etat.text = "%s (build local) est lancé." % j["nom"] if pid > 0 else "Le build local n'a pas pu démarrer."
	_etat.add_theme_color_override("font_color", ThemeLauncher.TEXTE if pid > 0 else ThemeLauncher.DANGER)

# Mode dev : change le statut public du jeu et publie le catalogue dev (commit GitHub).
func _changer_statut(statut: String) -> void:
	if _choisi == "" or not catalogue.mode_dev:
		return
	_etat.text = "Enregistrement du statut…"
	_etat.add_theme_color_override("font_color", ThemeLauncher.DISCRET)
	var err: String = await catalogue.changer_statut(_choisi, statut)
	var nom: String = _jeu(_choisi).get("nom", _choisi)
	_etat.text = "%s : %s." % [nom, Catalogue.libelle_statut(statut)] + ("" if err == "" else " — " + err)
	_etat.add_theme_color_override("font_color", ThemeLauncher.DANGER if err != "" else ThemeLauncher.ACCENT)
	_maj_liste()
	_maj_fiche()

func _bouton(texte: String, action: Callable, desactive: bool) -> void:
	var b := Button.new()
	b.text = texte
	b.custom_minimum_size = Vector2(170, 44)
	b.disabled = desactive
	b.pressed.connect(action)
	_boutons.add_child(b)

func _installer() -> void:
	var v: Dictionary = catalogue.versions.get(_choisi, {})
	if v.is_empty():
		return
	# Un jeu « bientôt » ou « hors ligne » ne doit pas s'installer, même depuis un raccourci.
	if Catalogue.statut(_jeu(_choisi)) in ["bientot", "hors-ligne"]:
		_etat.text = "%s n'est pas encore installable (%s)." % [_jeu(_choisi).get("nom", _choisi),
			Catalogue.libelle_statut(Catalogue.statut(_jeu(_choisi)))]
		_etat.add_theme_color_override("font_color", ThemeLauncher.LAITON)
		return
	installateur.installer(_jeu(_choisi), v, catalogue.entetes(), catalogue.systeme())
	_maj_fiche()

var _dernier_pid := 0

func _jouer() -> void:
	var err := installateur.lancer(_choisi)
	_dernier_pid = installateur.dernier_pid
	_etat.text = err if err != "" else "%s est lancé. Bon jeu !" % _jeu(_choisi)["nom"]

# Fond Keizuka Production : image paysage par défaut, version portrait quand la fenêtre est plus
# haute que large (téléphone tenu à la verticale).
func _maj_fond() -> void:
	var t := get_viewport().get_visible_rect().size
	var chemin := "res://assets/images/fond_portrait.jpg" if t.y > t.x else "res://assets/images/fond.jpg"
	_fond.texture = load(chemin)

# Téléphone vertical : base 720×1280, la liste des jeux au-dessus de la fiche.
# Paysage : base 1180×720, la liste à gauche et la fiche à droite.
func _ajuster_orientation() -> void:
	var f := get_window()
	var portrait := f.size.y > f.size.x
	var voulu := Vector2i(720, 1280) if portrait else Vector2i(1180, 720)
	if f.content_scale_size != voulu:
		f.content_scale_size = voulu
	if _corps != null:
		_corps.vertical = portrait
	if _tete != null:
		_tete.vertical = portrait
	if _defil != null:
		_defil.custom_minimum_size = Vector2(0, 280) if portrait else Vector2(330, 0)
	if _image != null:
		_image.custom_minimum_size.y = 150 if portrait else 220
	if _champ_catalogue != null:
		_champ_catalogue.custom_minimum_size.x = 0 if portrait else 620
	if _champ_catalogue_dev != null:
		_champ_catalogue_dev.custom_minimum_size.x = 0 if portrait else 620

# Vignette du catalogue (une URL d'image) : téléchargée une fois, puis gardée en cache.
func _vignette(url: String) -> Texture2D:
	if url == "":
		return null
	if _images.has(url):
		return _images[url]
	_images[url] = null
	var cache := "user://cache/%s.%s" % [url.sha1_text(), url.get_extension().left(4)]
	if FileAccess.file_exists(cache):
		_images[url] = _texture(FileAccess.get_file_as_bytes(cache))
		return _images[url]
	_charger_vignette(url, cache)
	return null

func _charger_vignette(url: String, cache: String) -> void:
	var h := HTTPRequest.new()
	add_child(h)
	if h.request(url, catalogue.entetes()) != OK:
		h.queue_free()
		return
	var r: Array = await h.request_completed
	h.queue_free()
	if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200:
		DirAccess.make_dir_recursive_absolute("user://cache")
		var f := FileAccess.open(cache, FileAccess.WRITE)
		f.store_buffer(r[3])
		f.close()
		_images[url] = _texture(r[3])
		_maj_liste()
		_maj_fiche()

static func _texture(o: PackedByteArray) -> Texture2D:
	var img := Image.new()
	if img.load_png_from_buffer(o) != OK and img.load_jpg_from_buffer(o) != OK and img.load_webp_from_buffer(o) != OK:
		return null
	return ImageTexture.create_from_image(img)

# --- Réglages ---

func _lire_reglages() -> void:
	var d = JSON.parse_string(FileAccess.get_file_as_string(REGLAGES)) if FileAccess.file_exists(REGLAGES) else null
	if d is Dictionary:
		catalogue.url_catalogue = d.get("catalogue", catalogue.url_catalogue)
		catalogue.jeton = d.get("jeton", "")
		if catalogue.mode_dev and str(d.get("catalogue_dev", "")) != "":
			catalogue.url_catalogue_dev = d["catalogue_dev"]

func _sauver_reglages() -> void:
	var f := FileAccess.open(REGLAGES, FileAccess.WRITE)
	var d := {"catalogue": catalogue.url_catalogue, "jeton": catalogue.jeton}
	if catalogue.mode_dev:
		d["catalogue_dev"] = catalogue.url_catalogue_dev
	f.store_string(JSON.stringify(d))

# --- Ligne de commande (tests) ---
#   --catalogue <url|fichier>  --api <url>  --auto "installer:id|lancer:id"  --capture <png>
var _auto: Array = []
var _auto_suivant := Callable()
var _auto_lance := false

func _options_ligne_de_commande() -> void:
	var a := OS.get_cmdline_user_args()
	var val := func(cle: String) -> String:
		var i := a.find(cle)
		return a[i + 1] if i >= 0 and i + 1 < a.size() else ""
	if val.call("--catalogue") != "":
		catalogue.url_catalogue = val.call("--catalogue")
	if val.call("--catalogue-dev") != "":
		catalogue.url_catalogue_dev = val.call("--catalogue-dev")
	if val.call("--api") != "":
		catalogue.url_api = val.call("--api")
	if val.call("--auto") != "":
		_auto = Array(val.call("--auto").split("|"))
		_auto_suivant = _etape_auto

func _etape_auto() -> void:
	if _auto.is_empty():
		var cap: String = OS.get_cmdline_user_args()[OS.get_cmdline_user_args().find("--capture") + 1] if "--capture" in OS.get_cmdline_user_args() else ""
		if cap != "":
			for k in 10:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png(cap)
		print("AUTO fini : ", _etat.text)
		get_tree().quit()
		return
	var e: String = _auto.pop_front()
	var action := e.get_slice(":", 0)
	_choisi = e.get_slice(":", 1)
	_maj_fiche()
	print("AUTO %s %s — état : %s" % [action, _choisi, _etat_jeu(_choisi)])
	match action:
		"installer":
			_installer()  # la suite vient avec le signal fini
		"lancer":
			_jouer()
			print("AUTO ", _etat.text, " pid=", _dernier_pid)
			_etape_auto()
		"desinstaller":
			installateur.desinstaller(_choisi)
			_etape_auto()
		"statut":
			await _changer_statut(e.get_slice(":", 2))
			print("AUTO statut ", _etat.text)
			_etape_auto()
		"maj_launcher":
			print("AUTO launcher %s, publié %s" % [AutoMaj.version(), catalogue.version_lanceur.get("version", "aucun")])
			_mettre_a_jour_launcher()  # se relance tout seul s'il y a plus récent
		_:
			_etape_auto()
