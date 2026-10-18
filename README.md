# Launcher

Installe, met à jour et lance les jeux de Keizuka (Godot 4.7, Linux, Windows, macOS et Android).

## Pour les joueurs

Téléchargez le launcher (Linux ou Windows) depuis les releases de https://github.com/keizuka/launcher, décompressez,
lancez `launcher.x86_64` ou `launcher.exe`. Il liste les jeux, installe la dernière version, prévient quand une
mise à jour sort (vérification au démarrage et toutes les 30 minutes) et lance le jeu.
Les jeux vont dans les données du launcher (`~/.local/share/godot/app_userdata/Launcher/jeux` sous Linux,
`%APPDATA%\Godot\app_userdata\Launcher\jeux` sous Windows).

### Android

Téléchargez `launcher-<version>-android.apk` depuis les releases et installez-le (autorisez d'abord les
installations venant de votre gestionnaire de fichiers / navigateur). Sur téléphone, le launcher ne liste
que les jeux publiés en APK : « Installer » télécharge l'APK puis ouvre la fenêtre d'installation d'Android
(première fois : autorisez le launcher à installer des applications dans les réglages d'Android), « Jouer »
ouvre le jeu installé, « Désinstaller » demande la désinstallation à Android. Le launcher se met à jour lui-même
par APK, comme les jeux.

## Fonctionnement

- `catalogue.json` (dans ce dépôt public) : la liste des jeux (id, nom, description, image, dépôt,
  préfixe de tag, exécutable par système, paquet Android).
- Une version d'un jeu = une release GitHub de ce dépôt, tag `<id>-v<version>`, avec `<id>-<version>-linux.zip` et
  `<id>-<version>-windows.zip` (et `…-macos.zip`), ou `<id>-<version>-android.apk` sur Android. Sur téléphone,
  seuls les jeux ayant un APK sont listés. Le texte de la release est affiché comme « Nouveautés ».
- Jeton GitHub facultatif (Réglages) pour un jeu publié dans un dépôt privé où le joueur est invité.
- Le launcher se met à jour lui-même : il est exporté en un seul fichier, télécharge la dernière release
  `launcher-v*`, se renomme en `.old`, met la nouvelle version à sa place et la relance. Il doit donc être
  installé dans un dossier modifiable (pas dans Program Files). Sur Android, la mise à jour est l'APK
  de la dernière release, installé par le système.

## Publier une version (développeur)

```sh
./tools/publier_jeu.sh ~/Projects/rpg-ia rpg-ia 0.2.0 --notes "- Nouveautés…"
./tools/publier_jeu.sh ~/Projects/rpg-ia rpg-ia 0.2.0 --local /tmp/essai   # zips seulement, rien de publié
```

Le projet du jeu doit avoir des préréglages d'export « Linux » et « Windows » ; les modèles d'export Godot 4.7.2
doivent être installés. Le code source des jeux peut rester privé : seuls les exécutables sont publiés.

### APK Android

L'APK d'un jeu (préréglage « Android » du projet, sortie `build/android/…-android.apk`) se publie avec :

```sh
gh release upload <tag> chemin/vers/<id>-<version>-android.apk --repo keizuka/launcher
```

## macOS

Le launcher et les jeux existent en app universelle (Mac Intel et Apple Silicon), signée « ad hoc » mais pas
notariée par Apple (il faudrait un compte développeur payant). Au premier lancement du launcher :

1. décompressez `launcher-<version>-macos.zip` et glissez `Launcher.app` dans **Applications** ;
2. clic droit (ou Ctrl+clic) sur `Launcher.app` → **Ouvrir** → **Ouvrir** ; ou bien Réglages Système →
   Confidentialité et sécurité → **Ouvrir quand même** ;
3. si macOS dit que l'app est « endommagée » : dans le Terminal, `xattr -cr /Applications/Launcher.app`.

Les jeux installés par le launcher n'ont pas cette étape (le launcher retire l'attribut de quarantaine).
