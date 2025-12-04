#!/bin/bash


LOAN_FILE="emprunts.txt"


check_file(){
    INPUT=$1
     # check file exists
     if [ ! -f "$INPUT" ]; then
        echo "Error: $INPUT file not found"
        exit 1
    fi
}

strip_quotes() {
    # removing "" et les espaces
    echo "$1" | sed -E 's/^[[:space:]"]+|[[:space:]"]+$//g'
}

append_op_csv() {
    local csv="$1"; 
    local action="$2"; 
    local id="$3"; 
    local titre="$4"; 
    local annee="$5"; 
    local auteur="$6"; 
    local genre="$7"; 

    # log file 
    local ops_file="log.csv"

    # Creation de fichier si exist pas
    if [[ ! -f "$ops_file" ]]; then
        echo 'timestamp,action,ID,Titre,Annee,Auteur,Genre,source_file,user' > "$ops_file"
    fi

    local ts
    ts=$(date '+%Y-%m-%dT%H:%M:%S')

    # escape the ""
    titre="${titre//\"/\"\"}"
    auteur="${auteur//\"/\"\"}"
    genre="${genre//\"/\"\"}"

    local src_file="$csv"
    local user_run="${USER:-unknown}"

    printf '%s,%s,%s,"%s",%s,"%s","%s","%s","%s"\n' \
        "$ts" "$action" "$id" "$titre" "$annee" "$auteur" "$genre" "$src_file" "$user_run" >> "$ops_file"
}


# Status update
update_status() {
    local file="$1"
    local id="$2"
    local new_status="$3"
    local required_old_status="$4" # checks old status before updating
    
    local tmp=$(mktemp)
    local updated=0
    
    # Read header
    IFS= read -r header < "$file"
    echo "$header" > "$tmp"
    
    while IFS=, read -r ID Titre Auteur Annee Genre Status; do
        clean_ID=$(strip_quotes "$ID")
        clean_Status=$(strip_quotes "$Status")
        
        if [[ "$clean_ID" == "$id" ]]; then
            # Check strict status requirement if provided
            if [[ -n "$required_old_status" ]]; then

                if [[ "${clean_Status,,}" != "${required_old_status,,}" ]]; then
                     echo "Erreur: Le livre n'est pas '${required_old_status}' (Statut actuel: $clean_Status)."
                     rm "$tmp"
                     return 1
                fi
            fi
            
            # Prepare data for writing (Strip then escape)
            clean_Titre=$(strip_quotes "$Titre")
            clean_Auteur=$(strip_quotes "$Auteur")
            clean_Annee=$(strip_quotes "$Annee")
            clean_Genre=$(strip_quotes "$Genre")
            
            # Sanitize quotes for CSV format (replace " with ')
            out_Titre=${clean_Titre//\"/\'}
            out_Auteur=${clean_Auteur//\"/\'}
            out_Genre=${clean_Genre//\"/\'}
            
            # Write new line
            echo "${clean_ID},\"${out_Titre}\",\"${out_Auteur}\",${clean_Annee},\"${out_Genre}\",\"${new_status}\"" >> "$tmp"
            updated=1
            
            # Log the status change
            append_op_csv "$file" "STATUS_CHANGE_${new_status^^}" "$clean_ID" "$clean_Titre" "$clean_Annee" "$clean_Auteur" "$clean_Genre"
        else
            # Write existing line
            echo "$ID,$Titre,$Auteur,$Annee,$Genre,$Status" >> "$tmp"
        fi
    done < <(tail -n +2 "$file")
    
    if [[ $updated -eq 1 ]]; then
        mv "$tmp" "$file"
        echo "Opération réussie : Livre marqué comme '$new_status'."
    else
        echo "ID introuvable."
        rm "$tmp"
    fi
}

# BORROW / RETURN LOGIC

borrow_book_flow() {
    local file="$1"
    check_file "$file"
    
    echo "=== Emprunter un livre ==="
    read -p "Recherche (Titre/Auteur) : " query < /dev/tty
    

    local found=0
    echo "--------------------------------------------------------"
    printf "%-5s %-30s %-20s\n" "ID" "Titre" "Auteur"
    echo "--------------------------------------------------------"
    
    while IFS=, read -r ID Titre Auteur Annee Genre Status; do
        clean_ID=$(strip_quotes "$ID")
        clean_Titre=$(strip_quotes "$Titre")
        clean_Auteur=$(strip_quotes "$Auteur")
        clean_Status=$(strip_quotes "$Status")
        
        if [[ "${clean_Status,,}" == "disponible" ]]; then
             if [[ "${clean_Titre,,}" == *"${query,,}"* ]] || [[ "${clean_Auteur,,}" == *"${query,,}"* ]]; then
                printf "%-5s %-30s %-20s\n" "$clean_ID" "${clean_Titre:0:29}" "${clean_Auteur:0:19}"
                found=1
             fi
        fi
    done < <(tail -n +2 "$file")
    
    if [[ $found -eq 0 ]]; then echo "Aucun livre trouvé."; return; fi
    
    echo "--------------------------------------------------------"
    read -p "ID à emprunter : " target_id < /dev/tty
    if [[ -z "$target_id" ]]; then return; fi
    
    # ask de la duree
    read -p "Nom de l'emprunteur : " user < /dev/tty
    read -p "Nombre de jours : " days < /dev/tty
    
    # Calculate dates
    local date_out=$(date +%Y-%m-%d)
    local date_due=$(date -d "+$days days" +%Y-%m-%d 2>/dev/null || date -v+${days}d +%Y-%m-%d) # Linux/Mac compatible

    # Update Status in CSV
    update_status "$file" "$target_id" "emprunte" "disponible"
    
    # Save to emprunts.txt

    echo "${target_id}|${user}|${date_out}|${date_due}" >> "$LOAN_FILE"
}
return_book_flow() {
    local file="$1"
    check_file "$file"
    
    echo "=== Retourner un livre ==="
    
    # List currently borrowed books from emprunts.txt
    if [[ ! -s "$LOAN_FILE" ]]; then echo "Aucun emprunt actif."; return; fi

    echo "--- Livres Empruntés ---"
    cat "$LOAN_FILE"
    echo "------------------------"

    read -p "ID à retourner : " target_id < /dev/tty
    if [[ -z "$target_id" ]]; then return; fi
    
    # Remove from emprunts.txt
    if grep -q "^${target_id}|" "$LOAN_FILE"; then
        grep -v "^${target_id}|" "$LOAN_FILE" > temp_loans.txt && mv temp_loans.txt "$LOAN_FILE"
    else
        echo "Cet ID n'est pas dans le fichier des emprunts."
        return
    fi
    
    # Update Status in CSV
    update_status "$file" "$target_id" "disponible" "emprunte"
}

check_loans() {
    echo "=== Suivi des Emprunts ==="
    if [[ ! -f "$LOAN_FILE" ]] || [[ ! -s "$LOAN_FILE" ]]; then
        echo "Aucun emprunt en cours."
        return
    fi

    local current_ts=$(date +%s)

    printf "%-5s %-15s %-12s %-12s %-10s\n" "ID" "Nom" "Pris le" "Retour" "Etat"
    echo "-------------------------------------------------------------"

    while IFS='|' read -r id user date_out date_due; do
        # Convert due date to timestamp for comparison
        local due_ts=$(date -d "$date_due" +%s 2>/dev/null || date -j -f "%Y-%m-%d" "$date_due" +%s)
        
        local status="OK"
        # If today > due_date, it is LATE
        if [[ $current_ts -gt $due_ts ]]; then
            status="RETARD!"
        fi

        printf "%-5s %-15s %-12s %-12s %-10s\n" "$id" "${user:0:14}" "$date_out" "$date_due" "$status"
    done < "$LOAN_FILE"
}


print_csv(){
    local file="$1"
    check_file "$file"

    local PAGE_SIZE=5
    local current_page=1
    

    local total_lines=$(wc -l < "$file")
    total_lines=$((total_lines - 1))

 
    local total_pages=$(( (total_lines + PAGE_SIZE - 1) / PAGE_SIZE ))

    if [[ "$total_lines" -le 0 ]]; then
        echo "Aucun livre trouvé."
        return
    fi


    while true; do
        clear
        echo "=== Page $current_page sur $total_pages ==="
        echo "-------------------------"

        local start_line=$(( (current_page - 1) * PAGE_SIZE + 2 ))
        local end_line=$(( start_line + PAGE_SIZE - 1 ))

        # Use sed to read ONLY the specific lines for this page
        # We pipe the output of sed into a while loop to format it
        sed -n "${start_line},${end_line}p" "$file" | while IFS=, read -r ID Titre Auteur Annes Genre Status; do
            

            ID=$(strip_quotes "$ID")
            Titre=$(strip_quotes "$Titre")
            Auteur=$(strip_quotes "$Auteur")
            Annes=$(strip_quotes "$Annes")
            Genre=$(strip_quotes "$Genre")
            Status=$(strip_quotes "$Status")

            echo "ID     : $ID"
            echo "Titre  : $Titre"
            echo "Auteur : $Auteur"
            echo "Année  : $Annes"
            echo "Genre  : $Genre"
            echo "Statut : $Status"
            echo "-------------------------"
        done


        echo ""
        echo " [n] Suivant  |  [p] Précédent  |  [q] Quitter le menu"
        echo ""
        read -p "Votre choix : " choice < /dev/tty

        case "$choice" in
            n|N)
                if (( current_page < total_pages )); then
                    current_page=$((current_page + 1))
                else
                    echo "Dernière page atteinte."
                    sleep 1
                fi
                ;;
            p|P)
                if (( current_page > 1 )); then
                    current_page=$((current_page - 1))
                else
                    echo "Première page atteinte."
                    sleep 1
                fi
                ;;
            q|Q)
 
                break 
                ;;
            *)
                echo "Choix invalide."
                sleep 1
                ;;
        esac
    done
}

search_book(){
   local file="$1"
   check_file "$file"

   echo "Recherche par critères multiples"
   echo "Laissez vide les champs que vous ne voulez pas utiliser"
   echo ""

   # Get search criteria from user
   read -p "Auteur: " author_query
   read -p "Titre: " title_query
   read -p "Année (ex: 2015 ou 2008-2010): " year_query
   read -p "Genre: " genre_query
   read -p "Statut: " status_query
   echo ""

   local year_start_query=""
   local year_end_query=""

   if [[ -n "$year_query" ]]; then 
        if [[ "$year_query" =~ ^[0-9]+$ ]]; then
            year_start_query="$year_query"
            year_end_query="$year_query"
        elif [[ "$year_query" == *"-"* ]]; then
            year_start_query=$(echo "$year_query" | cut -d'-' -f1)
            year_end_query=$(echo "$year_query" | cut -d'-' -f2)
        else
            echo "Format d'année '$year_query' non reconnu. La recherche par année sera ignorée." >&2
        fi
   fi

   echo "Résultats de la recherche:"
   echo "*************************"

   OLDIFS="$IFS"
   IFS=,

   local found=0

   while IFS=, read -r ID Titre Auteur Annes Genre Status ; do 
        ID=$(strip_quotes "$ID")
        Titre=$(strip_quotes "$Titre")
        Auteur=$(strip_quotes "$Auteur")
        Annes=$(strip_quotes "$Annes")
        Genre=$(strip_quotes "$Genre")
        Status=$(strip_quotes "$Status")

        local match=1

        # Check author
        if [[ -n "$author_query" ]]; then
            local author_norm=$(echo "$Auteur" | tr '[:upper:]' '[:lower:]')
            local author_query_norm=$(echo "$author_query" | tr '[:upper:]' '[:lower:]')
            if [[ ! "$author_norm" == *"$author_query_norm"* ]]; then
                match=0
            fi
        fi

        # Check title
        if [[ $match -eq 1 && -n "$title_query" ]]; then
            local title_norm=$(echo "$Titre" | tr '[:upper:]' '[:lower:]')
            local title_query_norm=$(echo "$title_query" | tr '[:upper:]' '[:lower:]')
            if [[ ! "$title_norm" == *"$title_query_norm"* ]]; then
                match=0
            fi
        fi
   
        if [[ $match -eq 1 && ( -n "$year_start_query" || -n "$year_end_query" ) ]]; then
            local year_match=1
            if ! [[ "$Annes" =~ ^[0-9]+$ ]]; then
                year_match=0
            fi
            if [[ $year_match -eq 1 && -n "$year_start_query" ]]; then
                if [[ "$year_start_query" =~ ^[0-9]+$ ]]; then
                    if [[ "$Annes" -lt "$year_start_query" ]]; then
                        year_match=0
                    fi
                else
                    year_match=0 
                fi
            fi
            if [[ $year_match -eq 1 && -n "$year_end_query" ]]; then
                if [[ "$year_end_query" =~ ^[0-9]+$ ]]; then
                    if [[ "$Annes" -gt "$year_end_query" ]]; then
                        year_match=0
                    fi
                else
                    year_match=0
                fi
            fi
            if [[ $year_match -eq 0 ]]; then
                match=0
            fi
        fi

        # Check genre
        if [[ $match -eq 1 && -n "$genre_query" ]]; then
            local genre_norm=$(echo "$Genre" | tr '[:upper:]' '[:lower:]')
            local genre_query_norm=$(echo "$genre_query" | tr '[:upper:]' '[:lower:]')
            if [[ ! "$genre_norm" == *"$genre_query_norm"* ]]; then
                match=0
            fi
        fi

        # Check status
        if [[ $match -eq 1 && -n "$status_query" ]]; then
            local status_norm=$(echo "$Status" | tr '[:upper:]' '[:lower:]')
            local status_query_norm=$(echo "$status_query" | tr '[:upper:]' '[:lower:]')
            if [[ ! "$status_norm" == *"$status_query_norm"* ]]; then
                match=0
            fi
        fi
        
        if [[ $match -eq 1 ]]; then
            echo "ID     : $ID"
            echo "Titre  : $Titre"
            echo "Auteur : $Auteur"
            echo "Année  : $Annes"
            echo "Genre  : $Genre"
            echo "Statut : $Status"
            echo "-------------------------"
            found=1
        fi
   done < <(tail -n +2 "$file")

   if [[ $found -eq 0 ]]; then
        echo "Aucun livre trouvé avec les critères spécifiés."
   fi

   IFS="$OLDIFS"
   return 0
}

get_next_id() {
    local file="$1"
    check_file "$file"

    local last_id
    last_id=$(tail -n +2 "$file" | tail -n 1 | cut -d',' -f1 | tr -d '"')

    if [[ -z "$last_id" ]]; then
        echo 1
    else
        echo $((last_id + 1))
    fi
}

add_book() {
    local file="$1"
    check_file "$file"

    echo "=== Ajouter un livre ==="
    read -p "Titre : " titre
    read -p "Auteur : " auteur

    # Validation Année
    local current_year
    current_year=$(date +%Y)
    while true; do
        read -p "Année : " annee
        if [[ "$annee" =~ ^[0-9]{1,4}$ ]] && (( annee <= current_year )); then
            break
        else
            echo "Année invalide. Entrez une année entre 0 et $current_year."
        fi
    done


    local genre_file=$(mktemp)


    while IFS=, read -r _ _ _ _ raw_genre _; do
        clean_g=$(strip_quotes "$raw_genre")
        if [[ -n "$clean_g" ]]; then echo "$clean_g"; fi
    done < <(tail -n +2 "$file") | sort | uniq > "$genre_file"

    echo "=== Genres disponibles ==="
    local i=1
    

    while read -r g; do
        echo "  $i) $g"
        ((i++))
    done < "$genre_file"
    echo "  $i) Ajouter un nouveau genre"

    local selected_genre
    local total_genres=$((i - 1))

    while true; do
        read -p "Choix : " choice
        if [[ "$choice" =~ ^[0-9]+$ ]]; then
            # Existing Genre: Use SED to pull the specific line from temp file
            if (( choice >= 1 && choice <= total_genres )); then
                selected_genre=$(sed -n "${choice}p" "$genre_file")
                break
            # New Genre
            elif (( choice == i )); then
                read -p "Nouveau genre : " selected_genre
                break
            fi
        fi
        echo "Choix invalide."
    done
    rm "$genre_file"


    local id=$(get_next_id "$file")
    local statut="disponible"

    titre=${titre//\"/\'}
    auteur=${auteur//\"/\'}
    selected_genre=${selected_genre//\"/\'}

    echo "${id},\"${titre}\",\"${auteur}\",${annee},\"${selected_genre}\",\"${statut}\"" >> "$file"
    append_op_csv "$file" "ADD" "$id" "$titre" "$annee" "$auteur" "$selected_genre"

    echo "Livre ajouté avec succès ! ID: $id | Genre: $selected_genre"
}


delete_book() {
    local file="$1"
    check_file "$file"

    echo "=== Supprimer un livre ==="
    read -p "ID du livre à supprimer : " id

    if [[ ! "$id" =~ ^[0-9]+$ ]]; then
        echo "ID invalide (doit être un nombre)."
        return 1
    fi

    local tmp found=0
    tmp=$(mktemp)

    {
        IFS= read -r header
        echo "$header" > "$tmp"

        while IFS=',' read -r ID Titre Auteur Annes Genre Status; do
            ID_clean=$(strip_quotes "$ID")

            if [[ "$ID_clean" == "$id" ]]; then
                echo "Livre supprimé :"
                echo "ID     : $(strip_quotes "$ID")"
                echo "Titre  : $(strip_quotes "$Titre")"
                echo "Auteur : $(strip_quotes "$Auteur")"
                echo "-------------------------"
                found=1
                append_op_csv "$file" "DELETE" "$ID_clean" "$(strip_quotes "$Titre")" "$(strip_quotes "$Annes")" "$(strip_quotes "$Auteur")" "$(strip_quotes "$Genre")"
                continue
            fi

            echo "$ID,$Titre,$Auteur,$Annes,$Genre,$Status" >> "$tmp"
        done
    } < "$file"

    if [[ $found -eq 0 ]]; then
        echo "Aucun livre avec l'ID $id."
        rm -f "$tmp"
        return 1
    fi

    mv "$tmp" "$file"
    echo "Suppression effectuée."
    return 0
}

edit_book() {
    local file="$1"
    check_file "$file"

    echo "=== Modifier un livre ==="
    read -p "ID du livre à modifier : " target_id

    if [[ ! "$target_id" =~ ^[0-9]+$ ]]; then
        echo "ID invalide."
        return 1
    fi

    local tmp=$(mktemp)
    local found=0

    # Read header
    IFS= read -r header < "$file"
    echo "$header" > "$tmp"

    # Read the file
    while IFS=, read -r ID Titre Auteur Annee Genre Status; do
        # Strip quotes immediately so we work with clean data
        ID=$(strip_quotes "$ID")
        Titre=$(strip_quotes "$Titre")
        Auteur=$(strip_quotes "$Auteur")
        Annee=$(strip_quotes "$Annee")
        Genre=$(strip_quotes "$Genre")
        Status=$(strip_quotes "$Status")

        if [[ "$ID" == "$target_id" ]]; then
            found=1
            echo "Livre actuel :"
            echo "ID     : $ID"
            echo "Titre  : $Titre"
            echo "Auteur : $Auteur"
            echo "Année  : $Annee"
            echo "Genre  : $Genre"
            echo "Statut : $Status"
            echo "-------------------------"

            # Using < /dev/tty to force reading from user keyboard, NOT the pipe
            read -p "Nouveau titre (laisser vide pour garder) : " new_titre < /dev/tty
            [[ -z "$new_titre" ]] && new_titre="$Titre"

            read -p "Nouvel auteur (laisser vide pour garder) : " new_auteur < /dev/tty
            [[ -z "$new_auteur" ]] && new_auteur="$Auteur"

            read -p "Nouvelle année (laisser vide pour garder) : " new_annee < /dev/tty
            if [[ -z "$new_annee" ]]; then
                new_annee="$Annee"
            elif ! [[ "$new_annee" =~ ^[0-9]{1,4}$ ]] || (( new_annee > $(date +%Y) )); then
                echo "Année invalide, ancienne gardée."
                new_annee="$Annee"
            fi

            read -p "Nouveau genre (laisser vide pour garder) : " new_genre < /dev/tty
            [[ -z "$new_genre" ]] && new_genre="$Genre"

            read -p "Nouveau statut (laisser vide pour garder) : " new_statut < /dev/tty
            [[ -z "$new_statut" ]] && new_statut="$Status"

            # Write edited line with fresh quotes
            echo "$ID,\"$new_titre\",\"$new_auteur\",$new_annee,\"$new_genre\",\"$new_statut\"" >> "$tmp"

            append_op_csv "$file" "EDIT" "$ID" "$new_titre" "$new_annee" "$new_auteur" "$new_genre"
        else
            # Write back existing line with standard quotes
            echo "$ID,\"$Titre\",\"$Auteur\",$Annee,\"$Genre\",\"$Status\"" >> "$tmp"
        fi
    done < <(tail -n +2 "$file")

    if [[ $found -eq 0 ]]; then
        echo "Aucun livre trouvé avec l'ID $target_id."
        rm "$tmp"
        return 1
    fi

    mv "$tmp" "$file"
    echo "Modification effectuée."
}




#fonction menu de gestion de livres
menu_gestion_livres() {
    while true; do
        echo "----- Gestion des livres -----"
        echo "1) Ajouter un livre"
        echo "2) Supprimer un livre"
        echo "3) Modifier un livre"
        echo "0) Retour au menu principal"
        echo "------------------------------"
        read -p "Votre choix: " choix_gl

        case "$choix_gl" in
            "1")
                add_book "$DATA_FILE"
                ;;
            "2")
                delete_book "$DATA_FILE"
                ;;
            "3")
                edit_book "$DATA_FILE"
                ;;
            "0")
                break
                ;;
            *)
                echo "Choix invalide."
                ;;
        esac

        echo ""
        read -p "Appuyez sur Entrée pour continuer..." dummy
    done
}





print_top_5() {
    local total_count="$1"

    while read -r count name; do
        local percent=$(( (count * 100) / total_count ))
        printf "  %-20s : %3d books (%d%%)\n" "$name" "$count" "$percent"
    done
}

print_ascii_graph() {
    local total_count="$1"
    
    while read -r count name; do
        local percent=$(( (count * 100) / total_count ))
        local bar_length=$percent
        local bar=""
        
        for ((i=0; i<bar_length; i++)); do bar="${bar}|"; done
        
        printf "  %-25s : %30s (%d%%)\n" "$name" "$bar" "$percent"
    done
}

count_books() {
    local file="$1"
    check_file "$file"

    local total=$(tail -n +2 "$file" | wc -l)

    if [[ "$total" -eq 0 ]]; then
        echo "File is empty."
        return
    fi

    echo "===== STATISTICS (Total: $total books) ====="

    echo ""
    echo "--------------- Top 5 Authors -------------"
    tail -n +2 "$file" | cut -d, -f3 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/^"//; s/"$//' | \
    sort | uniq -c | sort -nr | head -n 5 | print_top_5 "$total"

    echo ""
    echo "--------------- Top 5 Genres --------------"
    tail -n +2 "$file" | cut -d, -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/^"//; s/"$//' | \
    sort | uniq -c | sort -nr | head -n 5 | print_top_5 "$total"

    echo ""
    echo "--------------- Top 5 Years ---------------"
    tail -n +2 "$file" | cut -d, -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | \
    sort | uniq -c | sort -nr | head -n 5 | print_top_5 "$total"

    echo ""
    echo "------- Genre Distribution (ASCII) --------"
    
    tail -n +2 "$file" | cut -d, -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/^"//; s/"$//' | \
    sort | uniq -c | sort -nr | head -n 8 | print_ascii_graph "$total"

    echo ""
    echo "----------- Books by Decade ---------------"
    tail -n +2 "$file" | cut -d, -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | \
    sed 's/.$/0s/' | sort | uniq -c | sort -n | print_top_5 "$total"
    
    echo "==========================================="

    return 0;
}

export_stats_to_html() {
    local file="$1"
    local output_html="stats.html" 
    
    check_file "$file"

    local total=$(tail -n +2 "$file" | wc -l)

    if [[ "$total" -eq 0 ]]; then
        echo "File is empty."
        return
    fi

    echo "HTML report to $output_html..."

    cat <<EOF > "$output_html"
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <title>Statistiques de la Bibliothèque</title>
       <style>
        body { font-family: 'Times New Roman', Tahoma, Geneva, Verdana, sans-serif; max-width: 800px; margin: 20px auto; background-color: #f4f4f9; color: #333; }
        h1 { text-align: center; color: #000000; }
        h2 { border-bottom: 2px solid #000000; padding-bottom: 10px; margin-top: 30px; color: #000000; }
        table { width: 100%; border-collapse: collapse; background: white; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #6b0909; color: white; }
        tr:hover { background-color: #f1f1f1; }
        
    
        .graph-row { margin-bottom: 10px; display: flex; align-items: center; }
        .graph-label { width: 150px; font-weight: bold; }
        .bar-container { flex-grow: 1; background-color: #e0e0e0; border-radius: 5px; overflow: hidden; margin-right: 10px; }
        .bar { height: 25px; background-color: #27ae60; text-align: right; padding-right: 5px; line-height: 25px; color: white; font-size: 0.8em; white-space: nowrap;}
        .stat-box { background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); text-align: center; font-size: 1.2em; margin-bottom: 20px; }
    </style>
</head>
<body>

    <h1>Statistiques de la Bibliothèque</h1>
    
    <div class="stat-box">
        <strong>Total livres :</strong> $total
    </div>

EOF

    print_html_rows() {
        echo "<table><tr><th>Nom</th><th>Livres</th><th>Pourcentage</th></tr>" >> "$output_html"
        while read -r count name; do
            local percent=$(( (count * 100) / total ))
            echo "<tr><td>$name</td><td>$count</td><td>$percent%</td></tr>" >> "$output_html"
        done
        echo "</table>" >> "$output_html"
    }


    print_html_graph() {
        echo "<div class='graph-section'>" >> "$output_html"
        while read -r count name; do
            local percent=$(( (count * 100) / total ))
            
            local width=$percent
            if [ "$width" -eq 0 ]; then width=1; fi
            
            echo "<div class='graph-row'>" >> "$output_html"
            echo "  <div class='graph-label'>$name</div>" >> "$output_html"
            echo "  <div class='bar-container'><div class='bar' style='width: ${width}%;'>$percent%</div></div>" >> "$output_html"
            echo "</div>" >> "$output_html"
        done
        echo "</div>" >> "$output_html"
    }


    # 1. Authors
    echo "<h2>Top 5 Auteurs</h2>" >> "$output_html"
    tail -n +2 "$file" | cut -d, -f3 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/^"//; s/"$//' | \
    sort | uniq -c | sort -nr | head -n 5 | print_html_rows

    # 2. Genres
    echo "<h2>Top 5 Genres</h2>" >> "$output_html"
    tail -n +2 "$file" | cut -d, -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/^"//; s/"$//' | \
    sort | uniq -c | sort -nr | head -n 5 | print_html_rows

    # 3. Years
    echo "<h2>Top 5 Années</h2>" >> "$output_html"
    tail -n +2 "$file" | cut -d, -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | \
    sort | uniq -c | sort -nr | head -n 5 | print_html_rows

    # 4. Genre Graph (Visual)
    echo "<h2>Distribution par Genre</h2>" >> "$output_html"
    tail -n +2 "$file" | cut -d, -f5 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/^"//; s/"$//' | \
    sort | uniq -c | sort -nr | head -n 8 | print_html_graph

    # 5. Decades
    echo "<h2>Livres par Décennie</h2>" >> "$output_html"
    tail -n +2 "$file" | cut -d, -f4 | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | \
    sed 's/.$/0s/' | sort | uniq -c | sort -n | print_html_rows

    # Close HTML
    echo "</body></html>" >> "$output_html"

    echo "Done! Open $output_html to see the report."
}


menu_gestion_stat(){

    while true;do

        echo "---- Menu statistique ----"
        echo "1) Voir dans le terminal"
        echo "2) Export en html"
        echo "0) Retour au menu principal"
        echo "------------------------------"
        read -p "Votre choix: " choix_gl


        case "$choix_gl" in
            "1")
                 count_books "$DATA_FILE"
                ;;
            "2")
                export_stats_to_html "$DATA_FILE"
                ;;
            "0")
                break
                ;;
            *)
                echo "Choix invalide."
                ;;
        esac

        echo ""
        read -p "Appuyez sur Entrée pour continuer..." dummy
    done

}

menu_emprunts() {
    while true; do
        echo "--------------------------------"
        echo "     GESTION EMPRUNTS           "
        echo "--------------------------------"
        echo "1) Emprunter un livre"
        echo "2) Retourner un livre"
        echo "3) Voir les emprunts & Retards"
        echo "0) Retour"
        echo "--------------------------------"
        read -p "Choix : " choix_emp < /dev/tty

        case "$choix_emp" in
            1) borrow_book_flow "$DATA_FILE" ;;
            2) return_book_flow "$DATA_FILE" ;;
            3) check_loans ;; 
            0) break ;;
            *) echo "Option invalide." ;;
        esac
        echo ""
        read -p "Entrée pour continuer..." dummy < /dev/tty
    done
}