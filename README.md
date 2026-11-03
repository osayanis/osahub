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
- **Tout mettre à jour** en un clic, ou **automatiquement** app par app (seulement quand elle est fermée : OsaHUB ne coupe personne).
- **Tes apps sous la main** : lesquelles sont ouvertes, Ouvrir / Quitter / Relancer, depuis la fenêtre, le clic droit sur une carte ou la barre des menus.
- **Revenir en arrière** : chaque fiche liste les versions précédentes avec leurs notes, et installe celle de ton choix.
- **Désinstaller proprement** : l'app est quittée puis mise à la Corbeille (seulement celles rangées dans Applications, jamais une copie de développement).
- **⌘K** : une recherche rapide pour ouvrir, installer, mettre à jour ou quitter une app au clavier.
- **Les sites OsaLabs en direct** : osalabs.fr, OsaDrop, OsaCast et OsaParty, en ligne ou pas, avec leur temps de réponse.
- **Une mascotte** qui dit où on en est : elle salue, travaille pendant les installations, saute quand c'est fini.
- **Un logo vivant** : à l'ouverture, une poussière converge, les quatre tuiles se déplient, la flèche tombe, les lettres montent, puis le logo s'envole se ranger en haut de la fenêtre, où il ondule quand OsaHUB travaille. Noir et blanc, comme le reste de la suite. Un clic passe l'animation.

<p align="center">
  <img src=".github/assets/changelog.png" width="380" alt="Les nouveautés d'une mise à jour">
  <img src=".github/assets/detail.png" width="380" alt="La fiche d'une app">
</p>
<p align="center">
  <img src=".github/assets/palette.png" width="380" alt="La recherche rapide ⌘K">
  <img src=".github/assets/splash.png" width="380" alt="Le logo animé à l'ouverture">
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

SwiftUI + AppKit, aucune dépendance. API GitHub sans compte (60 requêtes par heure) : chaque réponse est gardée avec son ETag, et une réponse « rien n'a changé » (304) ne compte pas dans la limite. Si la limite est atteinte malgré tout, OsaHUB ressert la dernière réponse connue et dit à quelle heure il pourra revérifier. `./build.sh` construit l'app, `./publish.sh X.Y.Z notes.md` la publie.

Pour les captures : `OSAHUB_OPEN=<id>` ouvre une fiche, `OSAHUB_PALETTE=1` ouvre la recherche rapide. Pour les tests : `OsaHub verifier` télécharge et contrôle la dernière archive de chaque app sans rien installer. `OsaHub essai <id> <dossier>` fait une installation complète dans un autre dossier que Applications, sans toucher aux apps ouvertes.
