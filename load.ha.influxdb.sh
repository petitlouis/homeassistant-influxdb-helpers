#!/bin/bash

# Path Configuration
# Cette fonction détecte le chemin absolu du script, qu'il soit exécuté ou sourcé
get_script_dir() {
    local SOURCE="${BASH_SOURCE[0]:-${(%):-%x}}"
    while [ -h "$SOURCE" ]; do
        local DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
        SOURCE="$(readlink "$SOURCE")"
        [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
    done
    echo "$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
}

export sandbox_dir=$(get_script_dir)
credentials="$1"

scripts_dir="${sandbox_dir}/scripts"
local_bin_dir="${sandbox_dir}/bin"
load_error=false

# Load credentials
if [ -f "${credentials}" ]; then
    . "${credentials}"
else
    echo "❌ Error: credentials not found at $credentials"
    load_error=true
fi

load_module() {
    local module_path="$1"
    local args="$2"
    
    if [ -f "${module_path}" ]; then
        # On passe les arguments au module si nécessaire
        . "${module_path}" ${args}
        if [ $? -ne 0 ]; then return 1; fi
    else
        echo "❌ Error: $(basename "${module_path}") file missing"
        return 1
    fi
}

if [ "$load_error" = false ]; then
    # loading HA Helpers
    load_module "${scripts_dir}/ha.helpers.sh" || load_error=true
    
    # loding InfluxDB Helpers
    load_module "${scripts_dir}/influxDB.helpers.sh" "${local_bin_dir}" || load_error=true
fi

# Final Confirmation
if [ "$load_error" != false ]; then
    echo "⚠️  Loading failed. Some features might be unavailable."
    return 1
fi