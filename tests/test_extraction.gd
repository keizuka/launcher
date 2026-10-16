# Une archive piégée (« ../ ») est refusée : godot --headless --path . -s tests/test_extraction.gd -- piege.zip
extends SceneTree
func _init():
	var zip: String = OS.get_cmdline_user_args()[0]
	var err := Installateur.extraire(zip, "user://test_extraction")
	print("EXTRACTION ", "refusée : " + err if err != "" else "ACCEPTÉE (problème !)")
	print("ÉVASION ", FileAccess.file_exists(ProjectSettings.globalize_path("user://../evasion.txt")))
	print("COMPARER ", Catalogue.comparer("1.10.0", "1.9.2"), " ", Catalogue.comparer("0.2", "0.2.0"), " ", Catalogue.comparer("0.1.9", "0.2"))
	Installateur.supprimer_dossier("user://test_extraction")
	quit()
