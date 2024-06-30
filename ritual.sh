#!/bin/bash

# Логотип
while true; do
  echo -e '\e[40m\e[32m'
  echo -e '███╗   ██╗ ██████╗ ██████╗ ███████╗██████╗ ██╗   ██╗███╗   ██╗███╗   ██╗███████╗██████╗ '
  echo -e '████╗  ██║██╔═══██╗██╔══██╗██╔════╝██╔══██╗██║   ██║████╗  ██║████╗  ██║██╔════╝██╔══██╗'
  echo -e '██╔██╗ ██║██║   ██║██║  ██║█████╗  ██████╔╝██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██████╔╝'
  echo -e '██║╚██╗██║██║   ██║██║  ██║██╔══╝  ██╔══██╗██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██╔══██╗'
  echo -e '██║ ╚████║╚██████╔╝██████╔╝███████╗██║  ██║╚██████╔╝██║ ╚████║██║ ╚████║███████╗██║  ██║'
  echo -e '╚═╝  ╚═══╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚═╝  ╚═╝'
  echo -e '\e[0m'
  sleep 2
  break
done

# Цветные переменные для вывода
fmt=$(tput setaf 45)
end="\e[0m\n"
err="\e[31m"
scss="\e[32m"
log_file="/var/log/script.log"

# Проверка прав суперпользователя
if [ "$EUID" -ne 0 ]; then
  echo -e "${err}Please run as root${end}" | tee -a "$log_file"
  exit 1
fi

# Функция для проверки ошибок
check_error() {
  if [ $? -ne 0 ]; then
    echo -e "${err}$1${end}" | tee -a "$log_file"
    exit 1
  fi
}

# Функция установки
installation() {
  if [ -z "$RPC_URL" ]; then
    echo -e "${err}\nYou have not set RPC_URL, please set the variable and try again${end}" | tee -a "$log_file"
    exit 1
  fi

  if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${err}\nYou have not set PRIVATE_KEY${end}" | tee -a "$log_file"
    exit 1
  fi

  if [[ "${PRIVATE_KEY:0:2}" != "0x" ]]; then
    echo -e "${err}First 2 chars in PRIVATE_KEY variable is not 0x${end}" | tee -a "$log_file"
    exit 1
  fi

  echo -e "${fmt}\nSetting up dependencies${end}" | tee -a "$log_file"
  sudo apt update && sudo apt upgrade -y
  check_error "Failed to update and upgrade packages"

  sudo apt -qy install curl git jq lz4 build-essential make
  check_error "Failed to install required packages"

  if ! command -v docker &> /dev/null && ! command -v docker-compose &> /dev/null; then
    sudo wget https://raw.githubusercontent.com/fackNode/requirements/main/docker.sh -O /tmp/docker.sh
    check_error "Failed to download Docker installation script"
    chmod +x /tmp/docker.sh && /tmp/docker.sh
    check_error "Failed to execute Docker installation script"
  fi

  git clone --recurse-submodules https://github.com/ritual-net/infernet-container-starter /root/infernet-container-starter
  check_error "Failed to clone repository"

  echo -e "${fmt}\nCreating deploy-container.service${end}" | tee -a "$log_file"

  sudo tee /etc/systemd/system/deploy-container.service <<EOF
[Unit]
Description=Deploy Container Service
After=network.target

[Service]
Type=simple
ExecStart=/bin/bash -c 'cd /root/infernet-container-starter && project=hello-world make deploy-container'
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable deploy-container
  sudo systemctl start deploy-container
  check_error "Failed to start deploy-container service"

  echo -e "${fmt}\nSleep 60 seconds before checking docker containers${end}" | tee -a "$log_file"
  sleep 60

  if docker ps -a | grep -q 'deploy-redis-1' && docker ps -a | grep -q 'deploy-fluentbit-1'; then
    echo -e "${scss}\nContainers up correctly${end}" | tee -a "$log_file"
  else
    echo -e "${err}\nContainers up incorrectly. Continue${end}" | tee -a "$log_file"
  fi

  echo -e "${fmt}\nEditing Makefile${end}" | tee -a "$log_file"
  sed -i 's/sender := .*/sender := '"$PRIVATE_KEY"'/' /root/infernet-container-starter/projects/hello-world/contracts/Makefile
  sed -i 's|RPC_URL := .*|RPC_URL := '"$RPC_URL"'|' /root/infernet-container-starter/projects/hello-world/contracts/Makefile

  echo -e "${fmt}\nEditing Deploy.s.sol${end}" | tee -a "$log_file"
  sed -i 's/address coordinator = 0x5FbDB2315678afecb367f032d93F642f64180aa3;/address coordinator = 0x8D871Ef2826ac9001fB2e33fDD6379b6aaBF449c;/' /root/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol

  echo -e "${fmt}\nRestart docker containers to apply new config${end}" | tee -a "$log_file"
  for container in hello-world deploy-fluentbit-1 deploy-redis-1; do
    docker restart $container
    check_error "Failed to restart $container"

  echo -e "${fmt}\nInstall Foundry${end}" | tee -a "$log_file"
  cd /root/

  mkdir -p foundry
  cd foundry

  curl -L https://foundry.paradigm.xyz | bash
  check_error "Failed to download Foundry installation script"

  bash -i -c "source ~/.bashrc && foundryup"
  check_error "Failed to execute Foundry installation script"

# Функция настройки ноды
node_tune() {
  echo -e "${fmt}⚒️ Tune the node! ⚒️${end}" | tee -a "$log_file"
  CONTRACT_DATA_FILE="/root/infernet-container-starter/projects/hello-world/contracts/broadcast/Deploy.s.sol/8453/run-latest.json"
  CONFIG_FILE="/root/infernet-container-starter/deploy/config.json"
  CONTRACT_ADDRESS=$(jq -r '.receipts[0].contractAddress' "$CONTRACT_DATA_FILE")

  if [ -z "$CONTRACT_ADDRESS" ]; then
    echo -e "${err}Error occurred cannot read contractAddress from $CONTRACT_DATA_FILE${end}" | tee -a "$log_file"
    exit 1
  fi

  echo -e "${fmt}Your contract address: $CONTRACT_ADDRESS${end}" | tee -a "$log_file"

  if grep -qF "$CONTRACT_ADDRESS" "$CONFIG_FILE"; then
    echo "$CONTRACT_ADDRESS already in allowed_addresses array" | tee -a "$log_file"
    exit 0
  fi

  echo -e "${fmt}Adding snapshot_sync params to /root/infernet-container-starter/deploy/config.json${end}" | tee -a "$log_file"
  jq '. += { "snapshot_sync": { "sleep": 5, "batch_size": 25 } }' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"

  echo -e "${fmt}Adding $CONTRACT_ADDRESS in allowed_addresses to /root/infernet-container-starter/deploy/config.json${end}" | tee -a "$log_file"
  jq --arg contract_address "$CONTRACT_ADDRESS" '.containers[] |= if .id == "hello-world" then .allowed_addresses += [$contract_address] else . end' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"

  cat "$CONFIG_FILE" | tee -a "$log_file"

  docker restart deploy-node-1
  check_error "Failed to restart deploy-node-1"
}

# Меню
PS3='Please enter your choice: '
options=("Set RPC link" "Set private key" "Install" "Quit")
select opt in "${options[@]}"
do
  case $opt in
    "Set RPC link")
      read -p "Enter RPC URL: " RPC_URL
      export RPC_URL
      ;;
    "Set private key")
      read -p "Enter Private Key: " PRIVATE_KEY
      export PRIVATE_KEY
      ;;
    "Install")
      installation
      ;;
    "Quit")
      break
      ;;
    *) echo "Invalid option $REPLY";;
  esac
done
