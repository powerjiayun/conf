#!/bin/bash

check_root() {
    [ "$(id -u)" != "0" ] && echo "Error: You must be root to run this script" && exit 1
}

install_tools() {
    echo "Start updating the system..." && apt-get update -y > /dev/null || true && \
    echo "Start installing software..." && apt-get install -y curl wget netcat-traditional apt-transport-https ca-certificates iptables netfilter-persistent software-properties-common > /dev/null || true && \
    echo "Operation completed"
}

clean_lock_files() {
    echo "Start cleaning the system..."

    # Kill apt and dpkg processes if they are running
    pkill -9 apt || true
    pkill -9 dpkg || true

    # Remove lock files
    rm -f /var/{lib/dpkg/{lock,lock-frontend},lib/apt/lists/lock} || true

    # Configure dpkg
    dpkg --configure -a > /dev/null || true

    # Clean apt cache
    apt-get clean > /dev/null

    # Autoclean apt
    apt-get autoclean > /dev/null

    # Autoremove unused packages
    apt-get autoremove -y > /dev/null

    # Purge old linux-image and linux-headers packages
    dpkg --list | awk '/^ii/{print $2}' | grep -E 'linux-(image|headers)-[0-9]' | grep -v $(uname -r) | xargs apt-get -y purge > /dev/null

    echo "Cleaning completed"
}

install_docker_and_compose() {
    # 检测 Docker 是否已安装
    if ! command -v docker &> /dev/null; then
        # 安装 Docker 和 Docker Compose
        echo "Installing Docker and Docker Compose..."
        apt-get update > /dev/null 2>&1
        apt-get install -y apt-transport-https ca-certificates curl software-properties-common > /dev/null 2>&1
        curl -fsSL https://get.docker.com | bash > /dev/null 2>&1
        apt-get update > /dev/null 2>&1
        apt-get install -y docker-compose > /dev/null 2>&1
        echo "Docker installation completed"
    else
        echo "Docker and Docker Compose are already installed"
    fi
}

get_public_ip() {
    ip_services=("ifconfig.me" "ipinfo.io/ip" "icanhazip.com" "ipecho.net/plain" "ident.me")
    public_ip=""
    for service in "${ip_services[@]}"; do
        if public_ip=$(curl -s "$service" 2>/dev/null); then
            if [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "Local IP: $public_ip"
                break
            else
                echo "$service returned an invalid IP address: $public_ip"
            fi
        else
            echo "$service Unable to connect or slow response"
        fi
        sleep 1
    done
    [[ "$public_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "All services are unable to obtain public IP addresses"; exit 1; }
}

get_location() {
    location_services=("http://ip-api.com/line?fields=city" "ipinfo.io/city" "https://ip-api.io/json | jq -r .city")
    for service in "${location_services[@]}"; do
        LOCATION=$(curl -s "$service" 2>/dev/null)
        if [ -n "$LOCATION" ]; then
            echo "Host location: $LOCATION"
            break
        else
            echo "Unable to obtain city name from $service."
            continue
        fi
    done
    [ -n "$LOCATION" ] || echo "Unable to obtain city name."
}

setup_environment() {
    echo -e "nameserver 8.8.4.4\nnameserver 8.8.8.8" > /etc/resolv.conf
    echo "DNS servers updated successfully."
    # 设置历史记录大小
    grep -qxF 'export HISTSIZE=10000' ~/.bashrc || echo "export HISTSIZE=10000" >> ~/.bashrc
    source ~/.bashrc
}

select_version() {
    echo "Please select the version of Snell："
    echo "1. v3 "
    echo "2. v4 Exclusive to Surge"
    echo "0. Exit script"
    read -p "Enter selection (press Enter for default 2): " choice

    choice="${choice:-2}"

    case $choice in
        0) echo "Exit script"; exit 0 ;;
        1) BASE_URL="https://github.com/xOS/Others/raw/master/snell"; SUB_PATH="v3.0.1/snell-server-v3.0.1"; VERSION_NUMBER="3" ;;
        2) BASE_URL="https://dl.nssurge.com/snell"; SUB_PATH="snell-server-v4.1.1"; VERSION_NUMBER="4" ;;
        *) echo "Invalid selection"; exit 1 ;;
    esac
}

select_architecture() {
    ARCH="$(uname -m)"
    ARCH_TYPE="linux-amd64.zip"

    if [ "$ARCH" == "aarch64" ]; then
        ARCH_TYPE="linux-aarch64.zip"
    fi

    SNELL_URL="${BASE_URL}/${SUB_PATH}-${ARCH_TYPE}"
}

generate_port() {
    while true; do
        RANDOM_PORT=$(shuf -i 10000-20000 -n 1)

        # 检查端口是否被占用
        if ! nc.traditional -z 127.0.0.1 "$RANDOM_PORT"; then
            PORT_NUMBER="$RANDOM_PORT"  # 设置 PORT_NUMBER
            echo "选定的随机端口: $PORT_NUMBER"

            # 添加 iptables 规则开放端口
            iptables -A INPUT -p tcp --dport "$PORT_NUMBER" -j ACCEPT
            echo "端口 $PORT_NUMBER 已开放"
            break
        fi
    done
}

setup_firewall() {
    iptables -A INPUT -p tcp --dport "$PORT_NUMBER" -j ACCEPT || { echo "Error: Unable to add firewall rule"; exit 1; }
    echo "Firewall rule added, allowing port $PORT_NUMBER's traffic"
}

generate_password() {
    PASSWORD=$(openssl rand -base64 18) || { echo "Error: Unable to generate password"; exit 1; }
    echo "Password generated: $PASSWORD"
}

setup_docker() {
    NODE_DIR="/root/snelldocker/Snell$PORT_NUMBER"

    mkdir -p "$NODE_DIR" || { echo "Error: Unable to create directory $NODE_DIR"; exit 1; }
    cd "$NODE_DIR" || { echo "Error: Unable to change directory to $NODE_DIR"; exit 1; }

    cat <<EOF > docker-compose.yml
services:
  snell:
    image: accors/snell:latest
    container_name: Snell$PORT_NUMBER
    restart: always
    network_mode: host
    privileged: true
    environment:
      - SNELL_URL=$SNELL_URL
    volumes:
      - ./snell-conf/snell.conf:/etc/snell-server.conf
EOF

    mkdir -p ./snell-conf || { echo "Error: Unable to create directory $NODE_DIR/snell-conf"; exit 1; }
    cat <<EOF > ./snell-conf/snell.conf
[snell-server]
listen = 0.0.0.0:$PORT_NUMBER
psk = $PASSWORD
tfo = false
obfs = off
dns = 8.8.8.8,8.8.4.4,94.140.14.140,94.140.14.141,208.67.222.222,208.67.220.220
ipv6 = false
EOF

    docker-compose up -d || { echo "Error: Unable to start Docker container"; exit 1; }

    echo "Node setup completed. Here is your node information"
}

print_node() {
    if [ "$choice" == "1" ]; then
        echo
        echo
        echo "  - name: $LOCATION Snell v$VERSION_NUMBER $PORT_NUMBER"
        echo "    type: snell"
        echo "    server: $public_ip"
        echo "    port: $PORT_NUMBER"
        echo "    psk: $PASSWORD"
        echo "    version: $VERSION_NUMBER"
        echo "    udp: true"
        echo
        echo "$LOCATION Snell v$VERSION_NUMBER $PORT_NUMBER = snell, $public_ip, $PORT_NUMBER, psk=$PASSWORD, version=$VERSION_NUMBER"
        echo
        echo
    elif [ "$choice" == "2" ]; then
        echo
        echo "$LOCATION Snell v$VERSION_NUMBER $PORT_NUMBER = snell, $public_ip, $PORT_NUMBER, psk=$PASSWORD, version=$VERSION_NUMBER"
        echo
    fi
}

main(){
    check_root
    apt-get autoremove -y > /dev/null
    apt-get install -y sudo > /dev/null
    select_version
    clean_lock_files
    install_tools
    install_docker_and_compose
    get_public_ip
    get_location
    setup_environment
    select_architecture
    generate_port
    setup_firewall
    generate_password
    setup_docker
    print_node
}

main
