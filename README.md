<p align="center"><img src=".github/assets/icon.png" width="128" alt="Icône d'OsaHUB"></p>

<h1 align="center">OsaHUB</h1>

<p align="center">Toutes les apps OsaLabs pour Mac au même endroit : les installer, les mettre à jour, voir leurs nouveautés.</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/SwiftUI-natif-0a84ff?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/un%20projet-OsaLabs-b7a5ff" alt="OsaLabs">
</p>

<p align="center"><img src=".github/assets/home.png" width="760" alt="L'accueil d'OsaHUB"></p>

## Ce qu'il fait

- **Un catalogue** : OsaNotch, OsaWallpaper, OsaBoot, OsaWeight… avec leurs captures, leur version installée et la dernière publiée.
- **Installer en un clic** : OsaHUB télécharge l'app depuis sa release GitHub, vérifie que l'archive contient bien la bonne app (identifiant + signature intacte), puis la range dans Applications.
- **Les nouveautés à chaque mise à jour** : quand une app installée a une nouvelle version, OsaHUB affiche ses notes de version avec ses captures, puis la met à jour. Si l'app tournait, il la quitte et la relance.
- **Il veille** : fenêtre fermée, OsaHUB reste dans la barre des menus, vérifie toutes les 6 heures et envoie une notification. Il peut s'ouvrir à la connexion.
- **Une ouverture animée** : « OsaHUB » en motion design, noir et blanc comme le reste de la suite. Un clic la passe.

<p align="center">
  <img src=".github/assets/changelog.png" width="380" alt="Les nouveautés d'une mise à jour">
  <img src=".github/assets/detail.png" width="380" alt="La fiche d'une app">
</p>

## Installation

1. Télécharge `OsaHUB.dmg` depuis la [dernière release](https://github.com/osayanis/osahub/releases/latest).
2. Glisse OsaHUB dans Applications.
3. La première fois : **clic droit → Ouvrir** (l'app n'est pas notarisée par Apple).

Mac Apple Silicon, macOS 14 ou plus.

## Ajouter une app ou des captures

- **Le catalogue** est `catalog.json`, lu en ligne au lancement : ajouter une app ici suffit, sans republier OsaHUB. Le catalogue embarqué dans l'app sert hors ligne.
- **Une app du catalogue** doit avoir des releases GitHub publiques avec son archive (`NomApp.zip`, faite avec `ditto -c -k --keepParent`). Son Info.plist doit porter la vraie version (`CFBundleShortVersionString`) : c'est elle qu'OsaHUB compare.
- **Les captures des nouveautés** : mets des images dans les notes de la release (`![](https://…)`, ou glisse une image dans l'éditeur de GitHub) ou joins des PNG/JPG à la release. Sans images, OsaHUB montre les captures du catalogue.

## Technique

SwiftUI + AppKit, aucune dépendance. API GitHub sans compte (60 requêtes par heure : une vérification en coûte une par app). `./build.sh` construit l'app, `./publish.sh X.Y.Z notes.md` la publie.

Pour les tests : `OsaHub verifier` télécharge et contrôle la dernière archive de chaque app sans rien installer. `OsaHub essai <id> <dossier>` fait une installation complète dans un autre dossier que Applications, sans toucher aux apps ouvertes.
