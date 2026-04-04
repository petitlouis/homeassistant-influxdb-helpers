#!/bin/bash
LOCAL_BIN_DIR="$1"

cmd="influx"
# Check if command exists in system OR in our local bin folder
if ! command -v "$cmd" >/dev/null 2>&1 && [ ! -f "$LOCAL_BIN_DIR/$cmd" ]; then
    echo "🌐 $cmd missing. Downloading standalone binary (v1.8.10)..."
    
    mkdir -p "$LOCAL_BIN_DIR"
    (
        cd "$LOCAL_BIN_DIR" || return 1
        wget -q https://dl.influxdata.com/influxdb/releases/influxdb-1.8.10_linux_amd64.tar.gz
        
        # Extract only the 'influx' binary from the tarball
        tar xvfz influxdb-1.8.10_linux_amd64.tar.gz > /dev/null
        mv influxdb-1.8.10-1/usr/bin/influx . 

        rm influxdb-1.8.10_linux_amd64.tar.gz
        rm -rf influxdb-1.8.10-1
    )
fi

# PATH Update and avoid duplicates
if [[ ":$PATH:" != *":$LOCAL_BIN_DIR:"* ]]; then
    export PATH="$LOCAL_BIN_DIR:$PATH"
fi

check_influxdb_connection() {
    if ! influx -host "${HA_HOST}" \
                -port "${INFLUXDB_PORT}" \
                -username "${INFLUXDB_USER}" \
                -password "${INFLUXDB_PASSWORD}" \
                -execute "SHOW DATABASES" >/dev/null 2>&1; then
        echo "❌ Error: Cannot connect to InfluxDB at ${HA_HOST}:${INFLUXDB_PORT}"
        echo "   Check your credentials and VPN/Network status."
        return 1
    else
        echo "✅ Connexion InfluxDB"
    fi
}

# Influx Database
ha_influx() { 
    influx -host "${HA_HOST}" \
           -port "${INFLUXDB_PORT}" \
           -username "${INFLUXDB_USER}" \
           -password "${INFLUXDB_PASSWORD}" \
           -database "${INFLUXDB_DB}" \
           "$@" ; 
}

# check influxDb connexion
check_influxdb_connection

# ha_influx -execute "SELECT * INTO hPa FROM hPa WHERE entity_id = 'tdeg_ext_pression_pressure' GROUP BY *"
migration() {
	SRC=tdeg_ext_pression_pressure
	DEST=tdegbureau_pressure
	
	# Export d'un capteur tdeg_ext_pression_pressure
	echo "export ${SRC} into ..."
	ha_influx -execute "SELECT value FROM \"hPa\" WHERE \"entity_id\" = '${SRC}'" -format csv > migration.csv

	# On met juste l'entête DML (Data Manipulation Language)
	echo "# DML" > migration.txt
	echo "# CONTEXT-DATABASE: ${INFLUXDB_DB}" >> migration.txt
	# On ajoute les données
	tail -n +2 migration.csv | awk -F, '{print "hPa,entity_id=tdegbureau_pressure value=" $3 " " $2}' >> migration.txt
	
	echo "import into ${DEST}..."
	ha_influx -import -path=migration.txt -database="${INFLUXDB_DB}"
	
	ha_influx -execute 'DROP SERIES FROM "hPa" WHERE "entity_id" = "${SRC}"'
	
	rm migration.csv migration.txt
}

# ha_drop_entity '%' 'tempsalon_humidity'
ha_drop_entity() {
    local MEASURE="$1"
    local ENTITY="$2"

    # 1. Vérification des arguments
    if [[ -z "$MEASURE" || -z "$ENTITY" ]]; then
        echo "Usage: ha_drop <measure> <entity_id>"
        echo "Exemple: ha_drop hPa tdeg_ext_pression_pressure"
        return 1
    fi

    # 2. Vérification de l'existence (Comptage de points)
    # On extrait juste le chiffre du CSV pour savoir s'il y a quelque chose à supprimer
    local COUNT=$(ha_influx -execute "SELECT count(value) FROM \"${MEASURE}\" WHERE \"entity_id\" = '${ENTITY}'" -format csv | tail -n 1 | cut -d',' -f3)

    if [[ -z "$COUNT" || "$COUNT" -eq 0 ]]; then
        echo "Annulation : Aucune donnée trouvée pour '${ENTITY}' dans '${MEASURE}'."
        return 1
    fi

    # 3. Confirmation interactive
    echo "ATTENTION : Vous allez supprimer $COUNT points de données."
    read -p "Confirmer la suppression de '${ENTITY}' ? (y/N) : " CONFIRM
    
    if [[ "$CONFIRM" =~ ^[yY](es)?$ ]]; then
        # 4. Le DROP (avec la syntaxe de quotes qui a fonctionné tout à l'heure)
        if ha_influx -execute "DROP SERIES FROM \"${MEASURE}\" WHERE \"entity_id\" = '${ENTITY}'"; then
            echo "Succès : L'entité '${ENTITY}' a été rayée de la carte."
        else
            echo "Erreur : La base a refusé le DROP."
        fi
    else
        echo "Action annulée."
    fi
}

ha_migration() {
    # Récupération des paramètres
    local SRC="$1"
    local DEST="$2"
    
    # Vérification que les deux paramètres sont présents
    if [ -z "$SRC" ] || [ -z "$DEST" ]; then
        echo "ERREUR : Il manque des paramètres."
        echo "Usage : migration <entity_id_source> <entity_id_destination>"
        return 1
    fi

    echo "--- Début de la migration ---"
    echo "Source      : $SRC"
    echo "Destination : $DEST"

    # 1. Exportation avec vérification de succès
    echo "1/4 Exportation..."
    if ! ha_influx -execute "SELECT value FROM \"hPa\" WHERE \"entity_id\" = '${SRC}'" -format csv > migration.csv; then
        echo "ERREUR : L'exportation a échoué (problème de connexion ?)"
        return 1
    fi

    # Vérification que le fichier n'est pas vide (capteur inexistant ou sans données)
    if [ ! -s migration.csv ] || [ $(wc -l < migration.csv) -le 1 ]; then
        echo "ERREUR : Aucune donnée trouvée pour '${SRC}'. Vérifie l'orthographe."
        rm -f migration.csv
        return 1
    fi

    # 2. Préparation du fichier d'import (Line Protocol)
    echo "2/4 Préparation des données..."
    {
        echo "# DML"
        echo "# CONTEXT-DATABASE: ${INFLUXDB_DB}"
        # On injecte dynamiquement la variable DEST dans awk
        tail -n +2 migration.csv | awk -F, -v d="${DEST}" '{print "hPa,entity_id=" d " value=" $3 " " $2}'
    } > migration.txt

    # 3. Importation avec arrêt si échec
    echo "3/4 Importation dans InfluxDB..."
    if ! ha_influx -import -path=migration.txt -database="${INFLUXDB_DB}"; then
        echo "ERREUR : L'importation a échoué. On ne supprime rien."
        rm -f migration.csv migration.txt
        return 1
    fi

    # 4. Suppression uniquement si tout le reste a fonctionné
    echo "4/4 Nettoyage de l'ancienne série..."
    if ha_influx -execute "DROP SERIES FROM \"hPa\" WHERE \"entity_id\" = '${SRC}'" ; then
        echo "SUCCÈS : Migration terminée de $SRC vers $DEST."
    else
        echo "ATTENTION : Données copiées, mais l'ancienne série n'a pas pu être supprimée."
    fi

    # Nettoyage final des fichiers temporaires
    rm -f migration.csv migration.txt
}