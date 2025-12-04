#!/usr/bin/env bash

# Shell Project done by amine and reda


# Repertoire de helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Check si exist
if [[ -f "${SCRIPT_DIR}/lib_functions.sh" ]]; then
    . "${SCRIPT_DIR}/lib_functions.sh"
else
    echo "Error: lib_functions.sh not found in ${SCRIPT_DIR}"
    exit 1
fi

# jeux de donner
DATA_FILE="${SCRIPT_DIR}/Data/livres_status.csv"


# Loop 
while true; do
    echo "------------------------------------------------"
    echo "Bonjour dans le system de gestion de bibliotheque"
    echo "------------------------------------------------"
    echo "1) Afficher tous les livres"
    echo "2) Chercher un livre"
    echo "3) Gestion des livres (Ajouter/Supprimer)"
    echo "4) Statistiques"
    echo "5) Emprunter"
    echo "0) Quitter"
    echo "------------------------------------------------"
    
    # -p meme ligne 
    read -p "Votre choix: " choix

    case "$choix" in 

        "1")   
           
            print_csv "$DATA_FILE" 
            ;;
        
        "2") 
          
            search_book "$DATA_FILE"
            ;;

        "3") 
           
            menu_gestion_livres
            ;;

        "4") 

            menu_gestion_stat
            
            ;;

        "5") 
            menu_emprunts
            ;;

        "0") 
            echo "Au revoir!"
            exit 0
            ;;

        *) 
            echo "Choisis une option valide stp" 
            ;;
    esac
    
    echo "" # Line vide pour voire le resultat du terminal
    read -p "Appuyez sur Entrée pour continuer..." dummy
done