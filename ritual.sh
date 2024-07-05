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

  echo -e "\nПодписаться на канал may.crypto{🦅} чтобы быть в курсе самых актуальных нод - https://t.me/maycrypto\n"
  
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
  echo -e "${err}Пожалуйста, запустите скрипт от имени root${end}" | tee -a "$log_file"
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
    echo -e "${err}\nВы не указали RPC_URL, пожалуйста, задайте переменную и попробуйте снова${end}" | tee -a "$log_file"
    exit 1
  fi

  if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${err}\nВы не указали PRIVATE_KEY${end}" | tee -a "$log_file"
    exit 1
  fi

  if [[ "${PRIVATE_KEY:0:2}" != "0x" ]]; then
    PRIVATE_KEY="0x${PRIVATE_KEY}"
    echo -e "${fmt}Private Key не содержал '0x' в начале. Добавлено автоматически.${end}" | tee -a "$log_file"
  fi

  echo -e "${fmt}\nНастройка зависимостей${end}" | tee -a "$log_file"
  sudo apt update && sudo apt upgrade -y
  check_error "Не удалось обновить и обновить пакеты"

  sudo apt -qy install curl git jq lz4 build-essential make
  check_error "Не удалось установить необходимые пакеты"

  if ! command -v docker &> /dev/null || ! command -v docker-compose &> /dev/null; then
    sudo wget https://raw.githubusercontent.com/fackNode/requirements/main/docker.sh -O /tmp/docker.sh
    check_error "Не удалось скачать скрипт установки Docker"
    chmod +x /tmp/docker.sh && /tmp/docker.sh
    check_error "Не удалось выполнить скрипт установки Docker"
  fi

  git clone --recurse-submodules https://github.com/ritual-net/infernet-container-starter /root/infernet-container-starter
  check_error "Не удалось клонировать репозиторий"

  echo -e "${fmt}\nСоздание deploy-container.service${end}" | tee -a "$log_file"

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
  check_error "Не удалось запустить службу deploy-container"

  echo -e "${fmt}\nОжидание 60 секунд перед проверкой контейнеров Docker${end}" | tee -a "$log_file"
  sleep 60

  if docker ps -a | grep -q 'deploy-redis-1' && docker ps -a | grep -q 'deploy-fluentbit-1'; then
    echo -e "${scss}\nКонтейнеры успешно запущены${end}" | tee -a "$log_file"
  else
    echo -e "${err}\nКонтейнеры запущены неправильно. Продолжение...${end}" | tee -a "$log_file"
  fi

  echo -e "${fmt}\nРедактирование Makefile${end}" | tee -a "$log_file"
  
  CONFIG_FILE=~/infernet-container-starter/projects/hello-world/container/config.json
  sed -i "9s|\"rpc_url\": \".*\"|\"rpc_url\": \"$RPC_URL\"|" $CONFIG_FILE
  sed -i "13s|\"private_key\": \".*\"|\"private_key\": \"$PRIVATE_KEY\"|" $CONFIG_FILE
  sed -i 's/sender := .*/sender := '"$PRIVATE_KEY"'/' /root/infernet-container-starter/projects/hello-world/contracts/Makefile
  sed -i 's|RPC_URL := .*|RPC_URL := '"$RPC_URL"'|' /root/infernet-container-starter/projects/hello-world/contracts/Makefile

  echo -e "${fmt}\nРедактирование Deploy.s.sol${end}" | tee -a "$log_file"
  sed -i 's/address coordinator = 0x5FbDB2315678afecb367f032d93F642f64180aa3;/address coordinator = 0x8D871Ef2826ac9001fB2e33fDD6379b6aaBF449c;/' /root/infernet-container-starter/projects/hello-world/contracts/script/Deploy.s.sol

  echo -e "${fmt}\nПерезапуск контейнеров Docker для применения новых настроек${end}" | tee -a "$log_file"
  for container in hello-world deploy-fluentbit-1 deploy-redis-1; do
    docker restart $container
    check_error "Не удалось перезапустить контейнер $container"
  done

  echo -e "${fmt}\nУстановка Foundry${end}" | tee -a "$log_file"
  cd /root/

  mkdir -p foundry
  cd foundry

  curl -L https://foundry.paradigm.xyz | bash
  check_error "Не удалось скачать скрипт установки Foundry"

  ~/.foundry/bin/foundryup
  check_error "Не удалось выполнить скрипт установки Foundry"
}

# Функция настройки ноды
node_tune() {
  echo -e "${fmt}⚒️ Настройка ноды! ⚒️${end}" | tee -a "$log_file"
  CONTRACT_DATA_FILE="/root/infernet-container-starter/projects/hello-world/contracts/broadcast/Deploy.s.sol/8453/run-latest.json"
  CONFIG_FILE="/root/infernet-container-starter/deploy/config.json"
  CONTRACT_ADDRESS=$(jq -r '.receipts[0].contractAddress' "$CONTRACT_DATA_FILE")

  if [ -z "$CONTRACT_ADDRESS" ]; then
    echo -e "${err}Произошла ошибка: не удалось прочитать contractAddress из $CONTRACT_DATA_FILE${end}" | tee -a "$log_file"
    exit 1
  fi

  echo -e "${fmt}Адрес вашего контракта: $CONTRACT_ADDRESS${end}" | tee -a "$log_file"

  if grep -qF "$CONTRACT_ADDRESS" "$CONFIG_FILE"; then
    echo "$CONTRACT_ADDRESS уже в массиве allowed_addresses" | tee -a "$log_file"
    exit 0
  fi

  echo -e "${fmt}Добавление параметров snapshot_sync в /root/infernet-container-starter/deploy/config.json${end}" | tee -a "$log_file"
  jq '. += { "snapshot_sync": { "sleep": 5, "batch_size": 25 } }' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"

  echo -e "${fmt}Добавление $CONTRACT_ADDRESS в allowed_addresses в /root/infernet-container-starter/deploy/config.json${end}" | tee -a "$log_file"
  jq --arg contract_address "$CONTRACT_ADDRESS" '.containers[] |= if .id == "hello-world" then .allowed_addresses += [$contract_address] else . end' "$CONFIG_FILE" > temp.json && mv temp.json "$CONFIG_FILE"

  cat "$CONFIG_FILE" | tee -a "$log_file"

  docker restart deploy-node-1
  check_error "Не удалось перезапустить deploy-node-1"
}

# Просмотр логов ноды
view_logs() {
  echo -e "${fmt}Через 15 секунд начнется отображение логов... Для выхода из отображения логов используйте комбинацию CTRL+C${end}"
  sleep 15
  docker ps
  CONTAINER_ID=$(docker ps --filter "name=infernet-anvil" --format "{{.ID}}")
  if [ -z "$CONTAINER_ID" ]; then
    echo -e "${err}Контейнер infernet-anvil не найден${end}" | tee -a "$log_file"
    exit 1
  fi
  docker logs -f "$CONTAINER_ID"
}

# Меню
PS3='Пожалуйста, выберите опцию: '
options=("Ввести RPC ссылку" "Ввести приватный ключ" "Установить ноду Ritual" "Просмотреть логи ноды Ritual" "Выйти из установочного скрипта")
select opt in "${options[@]}"
do
  case $opt in
    "Ввести RPC ссылку")
      read -p "Введите RPC URL: " RPC_URL
      export RPC_URL
      ;;
    "Ввести приватный ключ")
      read -p "Введите приватный ключ: " PRIVATE_KEY
      if [[ "${PRIVATE_KEY:0:2}" != "0x" ]]; then
        PRIVATE_KEY="0x${PRIVATE_KEY}"
        echo -e "${fmt}Private Key не содержал '0x' в начале. Добавлено автоматически.${end}"
      fi
      export PRIVATE_KEY
      ;;
    "Установить ноду Ritual")
      installation
      ;;
    "Просмотреть логи ноды Ritual")
      view_logs
      ;;
    "Выйти из установочного скрипта")
      break
      ;;
    *) echo "Неверная опция $REPLY";;
  esac
done
