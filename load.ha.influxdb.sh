#!/bin/bash

# Path Configuration
# This function detects the absolute path of the script, whether it is executed or sourced.
get_script_dir() {
	# shellcheck disable=SC2296 # Incompatibility between Bash and Zsh for sourcing
	local SOURCE="${BASH_SOURCE[0]}"
	while [ -h "$SOURCE" ]; do
		local DIR
		DIR="$(cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd)"
		SOURCE="$(readlink "$SOURCE")"
		[[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
	done
	cd -P "$(dirname "$SOURCE")" >/dev/null 2>&1 && pwd
}

# Fix SC2155
sandbox_dir=$(get_script_dir)
credentials="$1"

scripts_dir="${sandbox_dir}/scripts"
local_bin_dir="${sandbox_dir}/bin"
load_error=false

# Load credentials
if [ -f "${credentials}" ]; then
	# Fix SC1090: Tell ShellCheck we know what we are doing
	# shellcheck source=/dev/null
	. "${credentials}"
else
	echo "❌ Error: credentials not found at $credentials"
	load_error=true
fi

load_module() {
	local module_path="$1"
	local args="$2"

	if [ -f "${module_path}" ]; then
		# Fix SC1090, SC2086 et SC2181
		# shellcheck source=/dev/null
		if ! . "${module_path}" "${args}"; then
			return 1
		fi
	else
		echo "❌ Error: $(basename "${module_path}") file missing"
		return 1
	fi
}

if [ "$load_error" = false ]; then
	# loading HA Helpers
	load_module "${scripts_dir}/ha.helpers.sh" || load_error=true

	# loading InfluxDB Helpers
	load_module "${scripts_dir}/influxDB.helpers.sh" "${local_bin_dir}" || load_error=true
fi

# Final Confirmation
if [ "$load_error" != false ]; then
	echo "⚠️  Loading failed. Some features might be unavailable."
	return 1
fi
