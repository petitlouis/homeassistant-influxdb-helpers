#!/bin/bash

# List of required dependencies
for cmd in curl jq; do
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
		"http://${HA_HOST}:${HA_PORT}/api${1}"
}

check_ha_connection() {
	local response
	response=$(ha_api "/")
	if [[ "$response" == *"API running"* ]]; then
		echo "✅ Home Assistant connexion: commands ha_getclimats, ha_getsensors, ha_getsensor."
	else
		echo "❌ Error Home Assistant connexion: Check HA_TOKEN ou HA_HOST in credentials.sh"
		return 1
	fi
}

check_ha_connection

# Home assistant senors
# ha_getsensors : list all sensors
# ha_getsensors battery: list of sensors with battery
ha_getsensors() {
	ha_api /states | jq -r ".[] | select(.entity_id | startswith(\"sensor.\") or startswith(\"binary_sensor.\")) | .entity_id" | grep "${1:-.}"
}

# Home assistant climate
ha_getclimats() {
	ha_api /states | jq -r ".[] | select(.entity_id | startswith(\"climate.\")) | .entity_id" | grep -E "${1:-.}"
}

# get data of a sensor
ha_getsensor() {
	local input=$1
	local entity_id

	# argument with a point (ex: sensor.toto or binary_sensor.toto)
	if [[ "$input" == *"."* ]]; then
		entity_id="$input"
	else
		# else add sensor. by default
		entity_id="sensor.$input"
	fi

	ha_api "/states/${entity_id}" | jq '.'
}
