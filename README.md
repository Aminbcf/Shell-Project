License informatique universite d'artois
Section 1 Groupe 1 TD A

Contributeurs et responsabilités
- Ibn Elamid Reda : développement du module de gestion des livres (ajout, modification, suppression, validation des données).
- Boucif Amine : recherche, statistiques, génération de rapports et journalisation (logs) des opérations.
- Rouas Massilva : gestion des emprunts (emprunter, rendre, suivi des retards).


Bibliothèque en ligne - Système de gestion (version étudiante)

Présentation

Ce projet est un petit système de gestion de bibliothèque écrit uniquement en scripts Shell (Bash). Il permet de gérer une liste de livres au format CSV, d'enregistrer les emprunts, de faire des recherches et d'obtenir des statistiques simples.

Structure du dépôt

ProjetShell/
- bibliotheque.sh       : script principal (menu interactif)
- lib_functions.sh      : fonctions utilisées par le programme
- Data/livres_status.csv: base de données des livres (CSV)
- emprunts.txt          : suivi des emprunts (fichier simple)
- log.csv               : journal des opérations
- README.md             : documentation (ce fichier)

Format des données

Le fichier CSV `Data/livres_status.csv` contient les colonnes suivantes (avec un en-tête) :
"ID","Titre","Auteur","Année","Genre","Statut"
Les lignes de données sont ensuite listées, une par livre. Les champs texte sont entre guillemets si nécessaire.

Fonctionnalités principales

1) Gestion des livres
- Ajouter un livre (ID automatique, validation de l'année)
- Modifier un livre (par ID)
- Supprimer un livre (par ID)
- Afficher les livres (affichage paginé)

2) Recherche
- Recherche multi-critères : auteur, titre, année (ou intervalle), genre, statut
- La recherche auteur est insensible à la casse et aux espaces et accepte les correspondances partielles (ex. entrer "albert" trouve "Albert Camus").

3) Emprunts
- Emprunter un livre (vérifie la disponibilité)
- Retourner un livre (met à jour le statut)
- Suivi des emprunts dans `emprunts.txt` avec date de sortie et date de retour prévue
- Détection simple des retards

4) Statistiques et export
- Statistiques rapides dans le terminal (top auteurs, genres, années)
- Export HTML basique (`stats.html`) pour rapport visuel

5) Journalisation
- Toutes les actions importantes sont ajoutées à `log.csv` avec timestamp, action, ID, titre, auteur, etc.

Prérequis

- Système Unix/Linux avec Bash
- Utilitaires standards : sed, awk, cut, tail, grep
- Permission de lecture/écriture sur les fichiers du projet

Installation et lancement

1) Rendre les scripts exécutables (si nécessaire) :

```sh
chmod +x bibliotheque.sh lib_functions.sh
```

2) Lancer le programme :

```sh
./bibliotheque.sh
```

Menu principal

Lorsque vous lancez `bibliotheque.sh`, vous verrez un menu avec des options :
1) Afficher tous les livres
2) Chercher un livre
3) Gestion des livres (Ajouter/Supprimer/Modifier)
4) Statistiques
5) Emprunts
0) Quitter

Exemples d'utilisation (rapide)

- Rechercher par auteur (insensible à la casse) : entrer "albert" trouvera "Albert Camus".

- Ajouter un livre : passer par le menu Gestion des livres et suivre les instructions.

- Emprunter un livre : chercher un livre disponible, noter son ID et suivre la procédure d'emprunt.

Exemples de commandes utiles

- Rendre un script exécutable :

```sh
chmod +x bibliotheque.sh lib_functions.sh
```

- Lancer l'application :

```sh
./bibliotheque.sh
```

- Afficher les 10 premières lignes du CSV (pour vérifier la structure) :

```sh
head -n 11 Data/livres_status.csv
```

- Rechercher une occurrence d'auteur dans le CSV (simple vérification) :

```sh
grep -i "albert" Data/livres_status.csv
```

Notes techniques et bonnes pratiques

- Les modifications du CSV sont faites en écrivant un fichier temporaire puis en le remplaçant pour éviter d'endommager les données.
- Les champs texte sont nettoyés des guillemets ou espaces superflus avant traitement.
- Les suppressions sont définitives : il n'y a pas de corbeille.
- Le système n'implémente pas de gestion de concurrence : évitez d'exécuter plusieurs instances qui modifient les mêmes fichiers en même temps.


Licence

Projet étudiant — libre d'utilisation et de modification pour des fins pédagogiques.
