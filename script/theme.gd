# theme.gd — Apparence du launcher, la même que RPG IA (couleurs du carnet, polices Alegreya).
class_name ThemeLauncher
extends RefCounted

const FOND := Color("#121816")
const SURFACE := Color("#19211e")
const SURFACE_HAUTE := Color("#222c28")
const TEXTE := Color("#e2e8e3")
const DISCRET := Color("#9aa8a0")
const LIGNE := Color("#2d3a35")
const ACCENT := Color("#74bdb0")
const LAITON := Color("#d3b162")
const DANGER := Color("#e99a7f")

static func police(chemin: String) -> FontFile:
	return load(chemin) as FontFile  # ressource importée : fonctionne aussi une fois exporté

static func boite(fond: Color, bord := Color.TRANSPARENT, rayon := 6, marge := 8) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = fond
	b.set_corner_radius_all(rayon)
	b.set_content_margin_all(marge)
	if bord.a > 0:
		b.border_color = bord
		b.set_border_width_all(1)
	return b

static func creer() -> Theme:
	var t := Theme.new()
	t.default_font = police("res://assets/polices/AlegreyaSans-Regular.ttf")
	t.default_font_size = 18
	for type in ["Label", "Button", "LineEdit", "CheckBox"]:
		t.set_color("font_color", type, TEXTE)
	t.set_stylebox("normal", "Button", boite(SURFACE_HAUTE, LIGNE))
	t.set_stylebox("hover", "Button", boite(LIGNE, ACCENT))
	t.set_stylebox("pressed", "Button", boite(ACCENT.darkened(0.55), ACCENT))
	t.set_stylebox("disabled", "Button", boite(SURFACE, LIGNE))
	t.set_stylebox("focus", "Button", boite(Color.TRANSPARENT, LAITON))
	t.set_color("font_disabled_color", "Button", DISCRET.darkened(0.3))
	t.set_stylebox("normal", "LineEdit", boite(FOND, LIGNE, 6, 10))
	t.set_stylebox("focus", "LineEdit", boite(FOND, ACCENT, 6, 10))
	t.set_stylebox("panel", "PanelContainer", boite(SURFACE, LIGNE, 10, 16))
	t.set_stylebox("background", "ProgressBar", boite(FOND, LIGNE, 4, 0))
	t.set_stylebox("fill", "ProgressBar", boite(ACCENT.darkened(0.2), Color.TRANSPARENT, 4, 0))
	t.set_font("normal_font", "RichTextLabel", police("res://assets/polices/AlegreyaSans-Regular.ttf"))
	t.set_font("bold_font", "RichTextLabel", police("res://assets/polices/AlegreyaSans-Bold.ttf"))
	t.set_font("italics_font", "RichTextLabel", police("res://assets/polices/Alegreya-Italic.ttf"))
	t.set_color("default_color", "RichTextLabel", TEXTE)
	t.add_type("Titre")
	t.set_type_variation("Titre", "Label")
	t.set_font("font", "Titre", police("res://assets/polices/AlegreyaSC-Bold.ttf"))
	t.set_color("font_color", "Titre", ACCENT)
	t.add_type("Discret")
	t.set_type_variation("Discret", "Label")
	t.set_color("font_color", "Discret", DISCRET)
	t.set_font_size("font_size", "Discret", 15)
	return t
