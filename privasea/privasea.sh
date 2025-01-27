#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

CONFIG_DIR="/privasea/config"
DOCKER_IMAGE="privasea/acceleration-node-beta:latest"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

BANNER="${RED}
  ____    ____    ___  __     __     _      ____    _____      _    
 |  _ \  |  _ \  |_ _| \ \   / /    / \    / ___|  | ____|    / \   
 | |_) | | |_) |  | |   \ \ / /    / _ \   \___ \  |  _|     / _ \  
 |  __/  |  _ <   | |    \ V /    / ___ \   ___) | | |___   / ___ \ 
 |_|     |_| \_\ |___|    \_/    /_/   \_\ |____/  |_____| /_/   \_\
                                                                    
${NC}"

BORDER="${RED}===============================================================${NC}"

trap 'echo -e "${RED}Error occurred at line $LINENO${NC}"; exit 1' ERR

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script must be run as root${NC}"
        exit 1
    fi
}

install_docker() {
    if command -v docker &>/dev/null; then
        echo -e "${GREEN}Docker is already installed${NC}"
        return
    fi

    echo -e "${YELLOW}Installing Docker...${NC}"
    apt update && apt install -y apt-transport-https ca-certificates curl software-properties-common
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt update
    apt install -y docker-ce docker-ce-cli containerd.io
    systemctl enable --now docker
    echo -e "${GREEN}Docker installed successfully${NC}"
}

pull_image() {
    echo -e "${YELLOW}Pulling Docker image...${NC}"
    docker pull $DOCKER_IMAGE
    echo -e "${GREEN}Image pulled successfully${NC}"
}

configure_node() {
    mkdir -p "$CONFIG_DIR"
    cd "$CONFIG_DIR/.." || exit 1

    echo -e "${YELLOW}Generating keystore...${NC}"

    while true; do
        read -p "Enter password for new keystore: " keystore_pass
        echo
        read -p "Confirm password: " keystore_pass_confirm
        echo
        if [[ "$keystore_pass" == "$keystore_pass_confirm" ]]; then
            break
        else
            echo -e "${RED}Passwords do not match. Please try again.${NC}"
        fi
    done

    if ! command -v expect &>/dev/null; then
        echo -e "${RED}ERROR: 'expect' command is required. Install with:"
        echo -e "apt-get install expect${NC}"
        exit 1
    fi

    expect << EOF
    spawn docker run -it -v "$CONFIG_DIR:/app/config" "$DOCKER_IMAGE" ./node-calc new_keystore
    expect "Enter password for a new key:"
    send -- "$keystore_pass\r"
    expect "Enter password again to verify:"
    send -- "$keystore_pass\r"
    expect eof
EOF

    latest_keystore=$(ls -t "$CONFIG_DIR/UTC--"* 2>/dev/null | head -1)
    if [[ -n "$latest_keystore" ]]; then
        BACKUP_DIR="$CONFIG_DIR/backup"
        mkdir -p "$BACKUP_DIR"

        backup_file="$BACKUP_DIR/$(basename "$latest_keystore")"
        cp "$latest_keystore" "$backup_file"
        echo -e "${GREEN}Backup keystore created at: ${backup_file}${NC}"

        mv -f "$latest_keystore" "$CONFIG_DIR/wallet_keystore"
        echo -e "${GREEN}Keystore renamed to wallet_keystore${NC}"
    else
        echo -e "${RED}Failed to generate keystore file!${NC}"
        exit 1
    fi
}

start_node() {
    read -p "Enter keystore password: " keystore_pass
    echo
    echo -e "${YELLOW}Starting node...${NC}"
    
    docker run -d \
        -v "$CONFIG_DIR:/app/config" \
        -e KEYSTORE_PASSWORD="$keystore_pass" \
        $DOCKER_IMAGE
        
    echo -e "${GREEN}Node started successfully${NC}"
    echo -e "Container ID: $(docker ps -lq --filter ancestor=$DOCKER_IMAGE)"
}

check_health() {
    container_id=$(docker ps -q --filter ancestor=$DOCKER_IMAGE)
    if [[ -z "$container_id" ]]; then
        echo -e "${RED}No running nodes found${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Showing node logs (Ctrl+C to exit)...${NC}"
    docker logs -f "$container_id"
}

stop_node() {
    echo -e "${YELLOW}Stopping node...${NC}"
    docker ps -q --filter "ancestor=$DOCKER_IMAGE" | xargs --no-run-if-empty docker stop
    echo -e "${GREEN}Node stopped successfully${NC}"
}

show_menu() {
    clear
    echo -e "${BORDER}"
    echo -e "${BANNER}"
    echo -e "${BORDER}"
    echo -e "${YELLOW}Privanetix Node Management${NC}"
    echo "1) Install Docker and pull image"
    echo "2) Configure node"
    echo "3) Start node (Please configure the node to the website before start node)"
    echo "4) Check node status"
    echo "5) Stop node"
    echo "6) Exit"
    echo -n "Enter your choice [1-6]: "
}

main() {
    check_root
    while true; do
        show_menu
        read choice
        case $choice in
            1)
                install_docker
                pull_image
                read -p "Press [Enter] to continue..."
                ;;
            2)
                configure_node
                read -p "Press [Enter] to continue..."
                ;;
            3)
                start_node
                read -p "Press [Enter] to continue..."
                ;;
            4)
                check_health
                read -p "Press [Enter] to continue..."
                ;;
            5)
                stop_node
                read -p "Press [Enter] to continue..."
                ;;
            6)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option!${NC}"
                sleep 1
                ;;
        esac
    done
}

main "$@"
