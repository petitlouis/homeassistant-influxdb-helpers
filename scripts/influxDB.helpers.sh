#!/bin/bash
LOCAL_BIN_DIR="$1"

cmd="influx"
# Check if command exists in system OR in our local bin folder
if ! command -v "$cmd" >/dev/null 2>&1 && [ ! -f "$LOCAL_BIN_DIR/$cmd" ]; then
	echo "🌐 $cmd missing. Downloading standalone binary (v1.8.10)..."

	mkdir -p "$LOCAL_BIN_DIR"
	(
		cd "$LOCAL_BIN_DIR" || return 1
		ARCH=$(uname -m)
		case ${ARCH} in
		x86_64) INFLUX_ARCH="amd64" ;;
		aarch64 | arm64) INFLUX_ARCH="arm64" ;;
		armv7l | armhf) INFLUX_ARCH="armhf" ;;
		*)
			echo "ERROR: Unsupported architecture: ${ARCH}"
			return 1
			;;
		esac
		archive="influxdb-1.8.10_linux_${INFLUX_ARCH}.tar.gz"

		echo "Local installation InfluxDB from ${archive}..."
		wget -q "https://dl.influxdata.com/influxdb/releases/${archive}"

		# Extract only the 'influx' binary from the tarball
		tar xvfz ${archive} >/dev/null
		mv influxdb-1.8.10-1/usr/bin/influx .

		rm ${archive}
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
		echo "✅ Connection InfluxDB"
	fi
}

# Influx Database
ha_influx() {
	influx -host "${HA_HOST}" \
		-port "${INFLUXDB_PORT}" \
		-username "${INFLUXDB_USER}" \
		-password "${INFLUXDB_PASSWORD}" \
		-database "${INFLUXDB_DB}" \
		"$@"
}

# check influxDb connection
check_influxdb_connection

# ha_influx -execute "SELECT * INTO hPa FROM hPa WHERE entity_id = 'tdeg_ext_pression_pressure' GROUP BY *"
migration() {
	SRC=$1
	DEST=$2

	echo "export ${SRC} into ..."
	ha_influx -execute "SELECT value FROM \"hPa\" WHERE \"entity_id\" = '${SRC}'" -format csv >migration.csv

	# Add DML header (Data Manipulation Language)
	echo "# DML" >migration.txt
	echo "# CONTEXT-DATABASE: ${INFLUXDB_DB}" >>migration.txt
	# Add data
	tail -n +2 migration.csv | awk -F, '{print "hPa,entity_id=${SRC} value=" $3 " " $2}' >>migration.txt

	echo "import into ${DEST}..."
	ha_influx -import -path=migration.txt -database="${INFLUXDB_DB}"

	ha_influx -execute "DROP SERIES FROM \"hPa\" WHERE \"entity_id\" = '${SRC}'"

	rm migration.csv migration.txt
}

ha_drop_entity() {
	local MEASURE="$1"
	local ENTITY="$2"

	if [[ -z "$MEASURE" || -z "$ENTITY" ]]; then
		echo "Usage: ha_drop <measurement unit> <entity_id>"
		return 1
	fi

	# Existence check (Point counting)
	# Parsing the CSV point count to verify if records exist for deletion
	local count
	count=$(ha_influx -execute "SELECT count(value) FROM \"${MEASURE}\" WHERE \"entity_id\" = '${ENTITY}'" -format csv | tail -n 1 | cut -d',' -f3)

	if [[ -z "$count" || "$count" -eq 0 ]]; then
		echo "Canceled : No data found '${ENTITY}' in '${MEASURE}'."
		return 1
	fi

	echo "ATTENTION : You're going to delete $count data points."
	read -rp "Confirm deletion of '${ENTITY}'  ? (y/N) : " confirm

	if [[ "$confirm" =~ ^[yY](es)?$ ]]; then
		if ha_influx -execute "DROP SERIES FROM \"${MEASURE}\" WHERE \"entity_id\" = '${ENTITY}'"; then
			echo "Success: The entity '${ENTITY}' has been wiped off the map."
		else
			echo "Error : Database refused to drop."
		fi
	else
		echo "Action canceled."
	fi
}

ha_migration() {
	local SRC="$1"
	local DEST="$2"

	if [ -z "$SRC" ] || [ -z "$DEST" ]; then
		echo "Error : parameters are missing."
		echo "Usage : migration <entity_id_source> <entity_id_destination>"
		return 1
	fi

	echo "--- Begin of the migration ---"
	echo "Source      : $SRC"
	echo "Destination : $DEST"

	echo "1/4 Exportation..."
	if ! ha_influx -execute "SELECT value FROM \"hPa\" WHERE \"entity_id\" = '${SRC}'" -format csv >migration.csv; then
		echo "ERROR: Export failed (connection issue?)"
		return 1
	fi

	# Verifying that the file is not empty (handles missing sensors or empty datasets)
	if [ ! -s migration.csv ] || [ "$(wc -l <migration.csv)" -le 1 ]; then
		echo "ERROR: No data found for '${SRC}'. Please check the spelling."
		rm -f migration.csv
		return 1
	fi

	# 2. Preparation import file (Line Protocol)
	echo "2/4 Data preparation..."
	{
		echo "# DML"
		echo "# CONTEXT-DATABASE: ${INFLUXDB_DB}"
		# Dynamically inject the DEST variable into awk
		tail -n +2 migration.csv | awk -F, -v d="${DEST}" '{print "hPa,entity_id=" d " value=" $3 " " $2}'
	} >migration.txt

	# 3. Import with fail-safe stop
	echo "3/4 Importing into InfluxDB..."
	if ! ha_influx -import -path=migration.txt -database="${INFLUXDB_DB}"; then
		echo "ERROR: Import failed. Aborting deletion to prevent data loss."
		rm -f migration.csv migration.txt
		return 1
	fi

	# 4. Deletion only if everything else succeeded
	echo "4/4 Cleaning up old series..."
	if ha_influx -execute "DROP SERIES FROM \"hPa\" WHERE \"entity_id\" = '${SRC}'"; then
		echo "SUCCESS: Migration completed from $SRC to $DEST."
	else
		echo "WARNING: Data copied, but the old series could not be deleted."
	fi

	# Final cleanup of temporary files
	rm -f migration.csv migration.txt
}
