#!/bin/bash

# List of required dependencies
for cmd in curl jq ; do
    # Check if command exists in PATH or in ~/bin
    if ! command -v "$cmd" >/dev/null 2>&1 && [ ! -f "$HOME/bin/$cmd" ]; then
        echo "❌ Dependency Error: '$cmd' is missing. Please install it to use these helpers."
        return 1
    fi
done

# Home Assistant API
ha_api() { 
    curl -s -X GET \
    -H "Authorization: Bearer ${HA_TOKEN}" \
    -H "Content-Type: application/json" \
    "http://${HA_HOST}:${HA_PORT}/api${1}" ; 
}

# 3. Test de connexion au chargement
check_ha_connection() {
    # On interroge l'endpoint racine de l'API
    local RESPONSE=$(ha_api "/")
    if [[ "$RESPONSE" == *"API running"* ]]; then
        echo "✅ Connexion Home Assistant"
    else
        echo "❌ Erreur Connexion Home Assistant : Vérifiez HA_TOKEN ou HA_HOST dans credentials.sh"
        return 1
    fi
}

# --- EXECUTION AU CHARGEMENT ---
check_ha_connection

# Home asisstant senors
# ha_getsensors : list all sensors
# ha_getsensors battery: list of sensors with battery
ha_getsensors() {
    ha_api /states | jq -r ".[] | select(.entity_id | startswith(\"sensor.\") or startswith(\"binary_sensor.\")) | .entity_id" | grep "${1:-.}"
}

# Home asisstant climate
ha_getclimats() {
    ha_api /states | jq -r ".[] | select(.entity_id | startswith(\"climate.\")) | .entity_id" | grep -E "${1:-.}"
}

# get data of a sensor
ha_getsensor() { 
    ha_api "/states/sensor.${1}" | jq '.'
}