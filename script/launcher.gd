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
var _images := {}            # url -> Texture2D (vignettes du catalogue)
var _attente_auto := VERIFICATION_AUTO_S

func _ready() -> void:
	get_tree().root.theme = ThemeLauncher.creer()
	RenderingServer.set_default_clear_color(ThemeLauncher.FOND)
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
	var fond := TextureRect.new()
	fond.texture = load("res://assets/images/fond.jpg")
	fond.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fond.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	fond.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fond.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fond)
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
	var tete := HBoxContainer.new()
	col.add_child(tete)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/images/icone.png")
	logo.custom_minimum_size = Vector2(56, 56)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.tooltip_text = "Keizuka Production"
	tete.add_child(logo)
	var titre := Label.new()
	titre.text = "Mes jeux"
	titre.tooltip_text = "Launcher version %s" % AutoMaj.version()
	titre.theme_type_variation = "Titre"
	titre.add_theme_font_size_override("font_size", 40)
	tete.add_child(titre)
	var espace := Control.new()
	espace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tete.add_child(espace)
	var verif := Button.new()
	verif.text = "Vérifier les mises à jour"
	verif.pressed.connect(_verifier)
	tete.add_child(verif)
	var regl := Button.new()
	regl.text = "Réglages"
	regl.pressed.connect(func(): _reglages.visible = not _reglages.visible)
	tete.add_child(regl)

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
	rg.add_child(l2)
	_champ_jeton = LineEdit.new()
	_champ_jeton.secret = true
	_champ_jeton.placeholder_text = "Seulement pour un jeu dans un dépôt privé où vous êtes invité"
	_champ_jeton.text = catalogue.jeton
	rg.add_child(_champ_jeton)
	rg.add_child(Control.new())
	var enreg := Button.new()
	enreg.text = "Enregistrer"
	enreg.pressed.connect(func():
		catalogue.url_catalogue = _champ_catalogue.text.strip_edges()
		catalogue.jeton = _champ_jeton.text.strip_edges()
		_sauver_reglages()
		_reglages.visible = false
		_verifier())
	rg.add_child(enreg)

	var corps := HBoxContainer.new()
	corps.size_flags_vertical = Control.SIZE_EXPAND_FILL
	corps.add_theme_constant_override("separation", 16)
	col.add_child(corps)
	var defil := ScrollContainer.new()
	defil.custom_minimum_size = Vector2(330, 0)
	defil.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	corps.add_child(defil)
	_liste = VBoxContainer.new()
	_liste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_liste.add_theme_constant_override("separation", 8)
	defil.add_child(_liste)

	var cadre := PanelContainer.new()
	cadre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	corps.add_child(cadre)
	_fiche = VBoxContainer.new()
	_fiche.add_theme_constant_override("separation", 10)
	cadre.add_child(_fiche)
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
	if _choisi == "" and not catalogue.jeux.is_empty():
		_choisi = catalogue.jeux[0]["id"]
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
		b.icon = _vignette(j.get("image", ""))
		b.expand_icon = true
		var badge: String = {"absent": "Non installé", "a_jour": "À jour", "maj": "Mise à jour !", "indisponible": "Bientôt"}[_etat_jeu(id)]
		b.text = "  %s\n  %s" % [j["nom"], badge]
		if _etat_jeu(id) == "maj":
			b.add_theme_color_override("font_color", ThemeLauncher.LAITON)
		b.pressed.connect(func():
			_choisi = id
			_maj_liste()
			_maj_fiche())
		_liste.add_child(b)

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
		_nom.text = "Aucun jeu"
		_description.text = "Le catalogue est vide ou injoignable. Vérifiez votre connexion, ou l'adresse du catalogue dans les réglages."
		_versions.text = ""
		_notes.text = ""
		_image.texture = null
		return
	_nom.text = j["nom"]
	_description.text = j.get("description", "")
	_image.texture = _vignette(j.get("image", ""))
	_image.visible = _image.texture != null
	var v: Dictionary = catalogue.versions.get(_choisi, {})
	var i: Dictionary = installateur.installes.get(_choisi, {})
	_versions.text = "Installée : %s   ·   Dernière version : %s%s" % [i.get("version", "aucune"),
		v.get("version", "—"), ("  (%s, %.0f Mo)" % [v["date"], v["fichier"]["taille"] / 1e6]) if not v.is_empty() else ""]
	_notes.text = ("[b]Nouveautés de la version %s[/b]\n%s" % [v["version"], v.get("notes", "")]) if not v.is_empty() else ""
	var occupe := installateur.occupe()
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
	installateur.installer(_jeu(_choisi), v, catalogue.entetes(), catalogue.systeme())
	_maj_fiche()

var _dernier_pid := 0

func _jouer() -> void:
	var err := installateur.lancer(_choisi)
	_dernier_pid = installateur.dernier_pid
	_etat.text = err if err != "" else "%s est lancé. Bon jeu !" % _jeu(_choisi)["nom"]

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

func _sauver_reglages() -> void:
	var f := FileAccess.open(REGLAGES, FileAccess.WRITE)
	f.store_string(JSON.stringify({"catalogue": catalogue.url_catalogue, "jeton": catalogue.jeton}))

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
		"maj_launcher":
			print("AUTO launcher %s, publié %s" % [AutoMaj.version(), catalogue.version_lanceur.get("version", "aucun")])
			_mettre_a_jour_launcher()  # se relance tout seul s'il y a plus récent
		_:
			_etape_auto()
