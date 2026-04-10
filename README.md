# 🛠️ Home-assistant & InfluxDB Toolbox

[![CI Quality Control](https://github.com/petitlouis/homeassistant-influxdb-helpers/actions/workflows/lint.yml/badge.svg)](https://github.com/petitlouis/homeassistant-influxdb-helpers/actions/workflows/lint.yml) [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**Lightweight Bash helpers to manage and monitor Home Assistant data with InfluxDB 1.8.**

This toolbox optimizes Home Assistant storage by delegating long-term history to InfluxDB, simplifies YAML configuration, and automates data maintenance (migration/deletion).

## 🗂️ Project Structure

* **`load.ha.influxdb.sh`**: The main loader. It handles dependencies and injects functions into your shell session.
* **`scripts/ha.helpers.sh`**: Functions to query the Home Assistant API (`curl`, `jq`).
* **`scripts/influxDB.helpers.sh`**: Tools for InfluxQL data manipulation (migration, drop, etc.).
* **`influxdb.yaml`**: A configuration template for selective sensor exportation.

---

## 🚀 Installation & Setup

### Prerequisites

The script automatically checks for the following dependencies:

* `curl`: For REST API calls.
* `jq`: A JSON processor for data filtering.
* `influx` (v1.8): **Automatically installed locally** in `./bin` if not found on your system.

### Credentials configuration

Duplicate the credential template outside the repository folder for security:

```bash
cp templates/credentials.sh.example ~/sandbox/ha.influxdb.credentials.sh
chmod 600 ~/sandbox/ha.influxdb.credentials.sh
```

Fill in your access details (`HA_TOKEN`, `INFLUX_USER`, etc.).

### Automatic loading

Add the following block to your `~/.bashrc` to have the helpers available in every new terminal session:

```bash
# Home Assistant & InfluxDB helpers
LOAD_HELPERS="${HOME}/sandbox/homeassistant-influxdb-helpers/load.ha.influxdb.sh"
if [ -f "${LOAD_HELPERS}" ]; then
    . "${LOAD_HELPERS}" "${HOME}/sandbox/ha.influxdb.credentials.sh"
fi
```

### 🏠 Installation on Home Assistant OS

If you want to use these helpers directly within your Home Assistant terminal (via the **Advanced SSH & Web Terminal** add-on), follow these steps:

#### Clone the repository

We recommend cloning the repo into the `/share` folder to ensure it persists across add-on restarts:

```bash
cd /share
git clone https://github.com/petitlouis/homeassistant-influxdb-helpers
```

#### Create your credentials file

Follow [Credentials Configuration](#credentials-configuration) and store your HomeAssistant and InfluxDB credentials `ha.influxdb.credentials.sh` in the `/config` folder (which is included in your HA backups)

#### Auto-load on terminal start

To have the commands available every time you open the terminal, add the loader to your shell profile (`.zshrc` for Advanced SSH or .bashrc for the standard add-on):

```shell
REPO_PATH="/share/homeassistant-influxdb-helpers"
CREDS_PATH="/config/ha.influxdb.credentials.sh"

if [ -f "${REPO_PATH}/load.ha.influxdb.sh" ]; then
    . "${REPO_PATH}/load.ha.influxdb.sh" "${CREDS_PATH}"
fi
```

---

## 📖 Usage Guide

### 🔍 Home Assistant Inspection

Use these commands to identify which sensors to include in your `influxdb.yaml`:

* **List all sensors**: `ha_getsensors`
* **Filter by type (e.g., batteries)**: `ha_getsensors battery$` (grep syntax)
* **Inspect a sensor's JSON state**: `ha_getsensor my_temperature_sensor`, `ha_getsensor binary_sensor.magnetic_contact_battery_low`

### 🧹 InfluxDB Maintenance

* **Data Migration**: If you rename an entity, move your history to the new ID without losing data.
  * `ha_migration <old_id> <new_id>`
* **Clean Deletion**: Safely delete an obsolete series after a confirmation prompt.
  * `ha_drop_entity <measurement> <entity_id>`

---

## ⚖️ License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for details.
