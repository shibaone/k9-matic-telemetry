# Matic-stats-exporter

- ## Bor:-
Telemetry data for Bor nodes on Mainnet and Mumbai-testnet can be found here https://bor-mainnet.vitwit.com and https://bor-mumbai.vitwit.com.
![](https://github.com/vitwit/matic-telemetry/blob/main/docs/screen.png)

To export your nodes telemetry data to these dashboards do the following steps - 
#### Restart your bor node with the ethstats flag

  
   - Add `--ethstats` flag to your bor bash script which will be present at `~/node/bor/start.sh`. After adding the flag to the bash file it should look like this:
```
#!/usr/bin/env sh

set -x #echo on

BOR_DIR=${BOR_DIR:-~/.bor}
DATA_DIR=$BOR_DIR/data

bor --datadir $DATA_DIR \
  --ethstats <node-name>:<key>@<server-ip>:<port> \
  --port 30303 \
  --http --http.addr '0.0.0.0' \
  --http.vhosts '*' \
  --http.corsdomain '*' \
  ......
  ......
```

**Note**:- For connecting to the mainnet dashboard use  `--ethstats <node-name>:mainnet@bor-mainnet.vitwit.com:3000`. For connecting to the testnet dashboard use `--ethstats <node-name>:testnet@bor-mumbai.vitwit.com:3000`. `<node-name>` is just an identifier to display it on the dashboard.
   - Restart your bor service `sudo systemctl restart bor`
   
To set up your own dashboard follow these [instructions](./docs/bor-setup.md).

- ## Heimdall:
Telemetry data for Heimdall nodes on Polygon Mainnet and Mumbai-testnet can be found here:
- [https://heimdall-mainnet.vitwit.com](https://heimdall-mainnet.vitwit.com) 
- [https://heimdall-mumbai.vitwit.com](https://heimdall-mumbai.vitwit.com)

Telemetry data for Heimdall nodes on Shibarium Mainnet and Puppynet testnet can be found here:
- [http://heimdall-shibarium-eth-stats.shibariumscan.io:3000/](http://heimdall-shibarium-eth-stats.shibariumscan.io:3000/)
- [https://puppynet-heimdall-ethstat.shib.io/](https://puppynet-heimdall-ethstat.shib.io/) 


To export your nodes telemetry data to these dashboards do the following:-

```sh
# git clone https://github.com/vitwit/matic-telemetry.git
git clone https://github.com/K9-Finance-DAO/matic-telemetry.git
cd matic-telemetry
mkdir -p ~/.telemetry/config
cp example.config.toml ~/.telemetry/config/config.toml
```

Replace default value of `node` with your <node-name> in `~/.telemetry/config/config.toml`.

### Polygon
Use the following secret_key and IP to connect to **Mainnet** dashboard

```toml
[stats_details]
secret_key = "heimdall_mainnet"  
node = "<node-name>" 
net_stats_ip = "heimdall-mainnet.vitwit.com:3000"
retry_delay = "500ms"
```

Use the following secret_key and IP to connect to **Testnet** dashboard

```toml
[stats_details]
secret_key = "heimdall_testnet"  
node = "<node-name>" 
net_stats_ip = "heimdall-mumbai.vitwit.com:3000"
# NEW:
retry_delay = "500ms"
```


Build the binary :-
```sh
go build -o telemetry
mv telemetry $GOBIN
```
Create systemd file :-
```
echo "[Unit]
Description=Telemtry
After=network-online.target
[Service]
User=$USER
ExecStart=$(which telemetry)
Restart=always
RestartSec=3
LimitNOFILE=4096
[Install]
WantedBy=multi-user.target" | sudo tee "/lib/systemd/system/telemetry.service"
```
Start the telemetry service

```
sudo systemctl enable telemetry.service
sudo systemctl start telemetry.service
```

View the logs using 

`journalctl -u telemetry -f`



# **Shibarium**: Heimdall Telemetry Setup

> See: `setup_heimdall_telemetry.sh` to automate the setup process. (Requires slight modification as this script is hard coded for K9 Finance Shibarium validators).

## Manual Setup

Install Go and build the telemetry service:

```sh
# git clone https://github.com/vitwit/matic-telemetry.git
git clone https://github.com/K9-Finance-DAO/matic-telemetry.git
sudo apt update
sudo apt install -y golang-go

cd ~
git clone https://github.com/K9-Finance-DAO/matic-telemetry.git
cd matic-telemetry

# Build the telemetry service
go mod tidy
go build -o heimdall-telemetry
sudo mv heimdall-telemetry /usr/bin/
sudo chown root:root /usr/bin/heimdall-telemetry
```

Edit `~/.telemetry/config/config.toml`. 

```sh
mkdir -p ~/.telemetry/config
nano ~/.telemetry/config/config.toml
```

Replace default value of `node` with your node moniker and set correct `net_stats_ip` and `secret_key` with the secret key provided by the Shib Team.

```toml
[rpc_and_lcd_endpoints]
heimdall_rpc_endpoint = "http://localhost:26657"
heimdall_lcd_endpoint = "http://localhost:1317"

[stats_details]
# ask Shib Team for secret_key
secret_key = "${secret_key}" 
node = "K9 Finance DAO Validator"
# **Puppynet (Testnet):**
# - https://puppynet-heimdall-ethstat.shib.io/
# **Shibarium (Mainnet):**
# - http://heimdall-shibarium-eth-stats.shibariumscan.io:3000/
net_stats_ip = "https://puppynet-heimdall-ethstat.shib.io/"
# retry_delay can be a time.Duration: "500ms", "1s", 2m", etc.
retry_delay = "1s"
```

> **Note**: `retry_delay` is the time interval to wait when there is an error. (Like "Stats login failed : unauthorized"). Previously there was a 10 second delay coded into the Dialer function, but this delay was not respected. Now this is configurable and actually does wait.

### Create Systemd Service

```sh

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
```
