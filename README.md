# Launcher

Installe, met à jour et lance les jeux de Keizuka (Godot 4.7, Linux et Windows).

## Pour les joueurs

Téléchargez le launcher (Linux ou Windows) depuis les releases de https://github.com/keizuka/jeux, décompressez,
lancez `launcher.x86_64` ou `launcher.exe`. Il liste les jeux, installe la dernière version, prévient quand une
mise à jour sort (vérification au démarrage et toutes les 30 minutes) et lance le jeu.
Les jeux vont dans les données du launcher (`~/.local/share/godot/app_userdata/Launcher/jeux` sous Linux,
`%APPDATA%\Godot\app_userdata\Launcher\jeux` sous Windows).

## Fonctionnement

- `catalogue.json` (dans le dépôt public `keizuka/jeux`) : la liste des jeux (id, nom, description, image, dépôt,
  préfixe de tag, exécutable par système).
- Une version d'un jeu = une release GitHub de ce dépôt, tag `<id>-v<version>`, avec `<id>-<version>-linux.zip` et
  `<id>-<version>-windows.zip`. Le texte de la release est affiché comme « Nouveautés ».
- Jeton GitHub facultatif (Réglages) pour un jeu publié dans un dépôt privé où le joueur est invité.

## Publier une version (développeur)

```sh
./tools/publier_jeu.sh ~/Projects/rpg-ia rpg-ia 0.2.0 --notes "- Nouveautés…"
./tools/publier_jeu.sh ~/Projects/rpg-ia rpg-ia 0.2.0 --local /tmp/essai   # zips seulement, rien de publié
```

Le projet du jeu doit avoir des préréglages d'export « Linux » et « Windows » ; les modèles d'export Godot 4.7.2
doivent être installés. Le code source des jeux peut rester privé : seuls les exécutables sont publiés.
