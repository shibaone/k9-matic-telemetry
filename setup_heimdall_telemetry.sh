#!/bin/bash

# This script installs the Heimdall telemetry service on a Linux machine.
# This is setup for Shibarium by K9 Finance DAO. Modify for your needs.

set -e  # Exit immediately if a command exits with a non-zero status
# set -x  # Enable debugging output

function prompt_selection() {
    local prompt="$1"
    shift
    local options=("$@")
    
    echo "$prompt" >&2
    for i in "${!options[@]}"; do
        echo "$((i+1))) ${options[$i]}" >&2
    done

    while true; do
        echo "Enter selection (number or first letter): " >&2
        read choice
        echo "Debug: User entered: $choice" >&2
        choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]')  # Convert to lowercase
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#options[@]}" ]; then
            echo "${options[$((choice-1))]}"
            return 0
        elif [[ "$choice" =~ ^[a-z]$ ]]; then
            for opt in "${options[@]}"; do
                if [[ "$(echo "$opt" | tr '[:upper:]' '[:lower:]' | cut -c1)" == "$choice" ]]; then
                    echo "$opt"
                    return 0
                fi
            done
        fi
        echo "Invalid selection. Please try again." >&2
    done
}

function validate_network() {
    if [[ "$1" != "shibarium" && "$1" != "puppynet" ]]; then
        echo "Invalid network input. Must be one of: 'shibarium' or 'puppynet'."
        return 1
    fi
}

function validate_node_type() {
    if [[ "$1" != "sentry" && "$1" != "validator" && "$1" != "archive" ]]; then
        echo "Invalid node type input. Must be one of: 'sentry', 'validator', or 'archive'."
        return 1
    fi
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    key="$1"

    case $key in
    -t | --node-type)
        validate_node_type "$2" || exit 1
        node_type="$2"
        shift # past argument
        shift # past value
        ;;
    -n | --network)
        validate_network "$2" || exit 1
        network="$2"
        shift # past argument
        shift # past value
        ;;
    *)
        # unknown option
        echo "Unknown option: $1"
        exit 1
        ;;
    esac
done

# Prompt for missing parameters
if [[ -z "$network" ]]; then
    network=$(prompt_selection "Select a network:" "shibarium" "puppynet")
fi

if [[ -z "$node_type" ]]; then
    node_type=$(prompt_selection "Select a node type:" "sentry" "validator" "archive")
fi

echo "###########################################################"
echo "Network: $network"
echo "Node Type: $node_type"
echo "###########################################################"
echo ""

# if we are using archive node, it only applies to bor client
# check if the client is heimdall, then node type should be changed to validator
if [[ "$node_type" == "archive" ]]; then
    node_type="validator"
    echo "Node Type -> $node_type"
fi


# Install go:
sudo apt update
sudo apt install -y golang-go

cd ~
git clone https://github.com/shibaone/k9-matic-telemetry.git
cd k9-matic-telemetry

# Build the telemetry service
go mod tidy
go build -o heimdall-telemetry
sudo mv heimdall-telemetry /usr/bin/
sudo chown $USER:$USER /usr/bin/heimdall-telemetry

# Create the telemetry config

# config path is hardcoded in the config.go to $HOME/.telemetry/config/
# configPath := path.Join(usr.HomeDir, `.telemetry/config/`)
# so link this directory to our config directory
mkdir -p ~/.telemetry/config
cp -f example.config.toml ~/.telemetry/config/config.toml

# Edit the telemetry config

# `$HOME/.telemetry/config/config.toml`:
# ```toml
# [rpc_and_lcd_endpoints]
# heimdall_rpc_endpoint = "http://localhost:26657"
# heimdall_lcd_endpoint = "http://localhost:1317"

# [stats_details]
# # **Puppynet (Testnet):**
# # - `xxx`
# # **Shibarium (Mainnet):**
# # - `xxx`
# secret_key = "xxx"
# # node = "K9 Finance DAO Sentry"
# # node = "K9 Finance DAO Validator"
# # node = "K9 Finance DAO Validator (Puppynet Archive)"
# node = "K9 Finance DAO Sentry (Puppynet)"
# # **Puppynet (Testnet):**
# # - http://heimdall-puppynet.shibariumscan.io:3000/
# # **Shibarium (Mainnet):**
# # - http://heimdall-shibarium-eth-stats.shibariumscan.io:3000/
# net_stats_ip = "heimdall-puppynet.shibariumscan.io:3000"
# ```

if [[ "$network" == "shibarium" ]]; then
    secret_key="xxx"
    net_stats_ip="heimdall-shibarium-eth-stats.shibariumscan.io:3000"
    if [[ "$node_type" == "sentry" ]]; then
        node_name="K9 Finance DAO Sentry"
    else
        node_name="K9 Finance DAO Validator"
    fi
else
    secret_key="xxx"
    net_stats_ip="heimdall-puppynet.shibariumscan.io:3000"
    if [[ "$node_type" == "sentry" ]]; then
        node_name="K9 Finance DAO Sentry (Puppynet)"
    else
        node_name="K9 Finance DAO Validator (Puppynet Archive)"
    fi
fi

# Overwrite the telemetry-config.toml with the following:
echo "
[rpc_and_lcd_endpoints]
heimdall_rpc_endpoint = \"http://localhost:26657\"
heimdall_lcd_endpoint = \"http://localhost:1317\"

[stats_details]
# **Puppynet (Testnet):**
# - \`xxx\`
# **Shibarium (Mainnet):**
# - \`xxx\`
secret_key = \"${secret_key}\"
node = \"${node_name}\"
# **Puppynet (Testnet):**
# - http://heimdall-puppynet.shibariumscan.io:3000/
# **Shibarium (Mainnet):**
# - http://heimdall-shibarium-eth-stats.shibariumscan.io:3000/
net_stats_ip = \"${net_stats_ip}\"
retry_delay = \"500ms\"
" | sudo tee ~/.telemetry/config/config.toml

# Create the telemetry service
echo "
[Unit]
    Description=heimdall-telemetry
    After=network-online.target
    StartLimitIntervalSec=500
    StartLimitBurst=5

[Service]
    Type=simple
    User=$USER
    ExecStart=/usr/bin/heimdall-telemetry
    Restart=always
    RestartSec=5s
    RuntimeMaxSec=infinity
    LimitNOFILE=4096
    # Add 60 second delay after manual stop
    ExecStopPost=/bin/sh -c 'if [ \"\$SERVICE_RESULT\" = \"killed\" ]; then sleep 60; fi'

[Install]
    WantedBy=multi-user.target
" | sudo tee "/lib/systemd/system/heimdall-telemetry.service"

# Reload the systemd daemon
sudo systemctl daemon-reload

# Enable the service
sudo systemctl enable heimdall-telemetry

# Start the service
sudo service heimdall-telemetry start

# View the service status
sudo service heimdall-telemetry status

echo "Heimdall telemetry service has been installed and started!"
echo "You can view the service status with:"
echo "sudo service heimdall-telemetry status"
echo ""
echo "You can view the logs with:"
echo "sudo journalctl -u heimdall-telemetry -f"
echo ""