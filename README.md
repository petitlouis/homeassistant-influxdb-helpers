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

### 1. Prerequisites

The script automatically checks for the following dependencies:
* `curl` & `jq`
* `influx` (v1.8): **Automatically installed locally** in `./bin` if not found on your system.

### 2. Credentials Configuration

Duplicate the credential template outside the repository folder for security:

```bash
cp templates/credentials.sh.example ~/ha.influxdb.credentials.sh
chmod 600 ~/ha.influxdb.credentials.sh
```

> [!TIP]
> Home Assistant OS Users: Store this file in /config/ha.influxdb.credentials.sh so it is included in your official HA backups.

### 3. Shell Integration & Persistence

To use the ha_ helpers, the loader must be sourced in your shell profile. Choose the method that matches your environment:

#### Standard Linux (Bash/Zsh)

Add this block to your ~/.bashrc or ~/.zshrc:

```bash
# Load HA & InfluxDB helpers
REPO_PATH="${HOME}/homeassistant-influxdb-helpers"
CREDS_PATH="${HOME}/ha.influxdb.credentials.sh"

if [ -f "${REPO_PATH}/load.ha.influxdb.sh" ]; then
    . "${REPO_PATH}/load.ha.influxdb.sh" "${CREDS_PATH}"
fi
```

#### Home Assistant OS (Persistent)

On HA OS, the filesystem is ephemeral. To ensure the helpers survive add-on restarts and system updates, use the init_commands feature of the Advanced SSH & Web Terminal.

1. Clone the repo in a persistent folder:

```bash
cd /share
git clone [https://github.com/petitlouis/homeassistant-influxdb-helpers](https://github.com/petitlouis/homeassistant-influxdb-helpers)
```

2. Navigate to **Settings** > **Add-ons / Apps** > **Terminal & SSH** > **Configuration**.

3. Add the following to the `init_commands` section:

```yaml
init_commands:
  - >-
    if ! grep -q "REPO_PATH" ~/.zshrc; then
      echo 'REPO_PATH="/share/homeassistant-influxdb-helpers"' >> ~/.zshrc
      echo 'CREDS_PATH="/config/ha.influxdb.credentials.sh"' >> ~/.zshrc
      echo 'if [ -f "${REPO_PATH}/load.ha.influxdb.sh" ]; then' >> ~/.zshrc
      echo '    . "${REPO_PATH}/load.ha.influxdb.sh" "${CREDS_PATH}"' >> ~/.zshrc
      echo 'fi' >> ~/.zshrc
    fi
```

## Usage Guide

### Home Assistant Inspection

Use these commands to identify sensors for your influxdb.yaml:

* List all sensors: ha_getsensors

* Filter by type (e.g., batteries): ha_getsensors battery$

* Inspect a sensor's state: ha_getsensor sensor.my_temperature

### InfluxDB Maintenance

* Data Migration: Move history when an entity is renamed.
  * ha_migration <old_id> <new_id>

* Clean Deletion: Safely delete an obsolete series.
  * ha_drop_entity <measurement> <entity_id>

## ⚖️ License

This project is licensed under the MIT License. See the LICENSE file for details.