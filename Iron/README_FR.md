# Iron

Une suite d'addons plug and play pour **WoW WotLK 3.3.5a** qui couvre le courrier, la banque et l'hôtel des ventes. Construite et testée sur Project Ascension.

Iron ne cherche pas à remplacer TSM ni à le concurrencer. TSM reste plus puissant et le restera. Iron s'adresse aux joueurs qui veulent l'essentiel du quotidien (vidange du courrier, restock banque, vente HV, achat de mats) sans passer une soirée à configurer des groupes, des opérations et des chaînes de prix custom avant que quoi que ce soit ne fonctionne.

Tu ouvres l'addon, tu cliques un bouton, ça marche. C'est tout le pitch.

## Ce que ça fait

Quatre modules indépendants dans un seul addon. Aucun ne demande de configuration avant la première utilisation.

**IronSell** liste tout ce qui est dans tes sacs et qui n'est pas en liste noire, et calcule un prix de vente à partir des derniers scans HV (décote de 5% par défaut). Clique sur le bouton Quick Sell pour mettre en vente en un coup au prix suggéré, ou clique sur la ligne de l'objet pour ouvrir un panneau de validation où tu peux ajuster la taille de pile, le nombre de piles, le prix et la durée avant de valider. Le principe de la liste noire fait que ça fonctionne dès le premier jour sans configuration. Les objets que tu ne veux pas vendre s'ajoutent à la liste noire au fur et à mesure.

**IronBuy** affiche tes recettes connues par profession, montre le prix de marché de chaque composant et le coût total des mats pour la quantité choisie, et te laisse cliquer sur un composant pour voir les enchères en direct triées du moins cher au plus cher. Tu choisis une quantité, l'addon sélectionne automatiquement les enchères les moins chères pour l'atteindre, et achète le lot. Ouvre chaque fenêtre métier une fois pour qu'Iron synchronise tes recettes ; la resynchro se fait à la prochaine ouverture de la fenêtre.

**IronVault** déplace des objets entre tes sacs et ta banque en se basant sur des cibles que tu définis une fois. Tu ouvres un groupe, tu y déposes des objets avec leurs quantités cibles ("je veux 40 flasks en banque", ou "je veux 200 potions de mana en sac"), et à partir de là un seul clic à la banque déplace ce qui manque. Chaque groupe fonctionne dans un seul sens, dépôt (sac vers banque) ou retrait (banque vers sac), avec synchronisation auto à l'ouverture de la banque si tu veux.

**IronMail** ajoute un bouton "Tout récupérer" à ta boîte aux lettres. Un clic vide l'or et les objets de ta boîte, avec un throttling pour que le serveur ne perde pas de pièces jointes. Les courriers COD sont ignorés par défaut (une popup de confirmation te protège si tu désactives cette sécurité).

## Points forts

Les workflows hôtel des ventes (IronSell + IronBuy) et la gestion de banque (IronVault) sont les trois piliers. Si tu vis à l'hôtel des ventes à poster des objets, sniper des mats pour tes crafts, et faire la navette entre sacs et banque, ces modules vont te faire gagner le plus de temps. IronMail est la couche de confort qui boucle la boucle après chaque cycle HV.

Pas de tier premium, pas de cloud sync, pas de télémétrie. Tout tourne en local avec tes saved variables.

Multilingue : anglais, français, allemand, espagnol, chinois simplifié. Bascule sur l'anglais pour les locales non supportées.

## Installation

Télécharge le zip de la dernière release depuis la page Releases. Extrais-le dans ton dossier `World of Warcraft/Interface/AddOns/` de sorte que le chemin ressemble à `Interface/AddOns/Iron/Iron.toc`. Lance le client.

À la connexion, tape `/ir about` dans le chat pour confirmer que l'addon est chargé et voir le statut de la locale.

## Commandes

`/ir help` liste toutes les commandes disponibles.
`/ir config` ouvre le panneau d'options.
`/ir about` affiche la version, la locale et un récap rapide des commandes.
`/ir logs` ouvre une fenêtre de logs debug copiable (utile pour les rapports de bug).
`/ir debug on|off` active ou désactive les messages debug verbeux dans le chat.
`/ir stats` affiche le nombre de chargements et la date de première installation.

## Compatibilité

Testé sur Project Ascension (3.3.5a). Devrait fonctionner sur d'autres serveurs privés WotLK 3.3.5a vu que l'addon utilise uniquement l'API Blizzard standard, mais Ascension est le seul environnement confirmé.

Compatible avec Bagnon.

## Rapports de bugs

Ouvre une issue sur GitHub avec les éléments suivants :

La version de l'addon (visible via `/ir about`).
Le royaume et le build du client sur lequel tu joues.
Les étapes pour reproduire (ce que tu as fait, ce que tu attendais, ce qui s'est passé).
La sortie de `/ir logs` couvrant le moment du bug (copie depuis la fenêtre de logs avec Ctrl+A puis Ctrl+C).

Sans les logs, la plupart des problèmes relèvent de la devinette.

## Licence

MIT. Fais ce que tu veux du code, garde juste la mention de copyright. Voir LICENSE pour le texte complet.

Copyright (c) 2026 SpySpoTt3d
