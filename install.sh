#!/usr/bin/env bash
#═══════════════════════════════════════════════════════════════════════════════
#                     Phantom Server v2.0 管理脚本
#                       极简 · 无状态 · 抗探测
#═══════════════════════════════════════════════════════════════════════════════
#
#  功能：安装 / 配置 / 管理 / 维护
#
#  用法：
#    bash install.sh              # 显示菜单
#    bash install.sh install      # 直接安装
#    bash install.sh uninstall    # 直接卸载
#    bash install.sh status       # 查看状态
#
#═══════════════════════════════════════════════════════════════════════════════

set -e

#═══════════════════════════════════════════════════════════════════════════════
# 全局变量
#═══════════════════════════════════════════════════════════════════════════════

VERSION="2.0.0"
SCRIPT_VERSION="1.0.0"
GITHUB_REPO="anthropics/phantom-server"

# 路径配置
INSTALL_DIR="/opt/phantom"
CONFIG_DIR="/etc/phantom"
LOG_DIR="/var/log/phantom"
BACKUP_DIR="/var/backup/phantom"
BINARY_NAME="phantom-server"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
SERVICE_NAME="phantom"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 日志函数
log_info()  { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step()  { echo -e "${BLUE}[→]${NC} $1"; }
log_input() { echo -e "${PURPLE}[?]${NC} $1"; }

#═══════════════════════════════════════════════════════════════════════════════
# 工具函数
#═══════════════════════════════════════════════════════════════════════════════

# 打印横幅
print_banner() {
    clear
    echo -e "${CYAN}"
    cat << 'EOF'
    ╔═══════════════════════════════════════════════════════════════════╗
    ║                                                                   ║
    ║      ██████╗ ██╗  ██╗ █████╗ ███╗   ██╗████████╗ ██████╗ ███╗   ███╗
    ║      ██╔══██╗██║  ██║██╔══██╗████╗  ██║╚══██╔══╝██╔═══██╗████╗ ████║
    ║      ██████╔╝███████║███████║██╔██╗ ██║   ██║   ██║   ██║██╔████╔██║
    ║      ██╔═══╝ ██╔══██║██╔══██║██║╚██╗██║   ██║   ██║   ██║██║╚██╔╝██║
    ║      ██║     ██║  ██║██║  ██║██║ ╚████║   ██║   ╚██████╔╝██║ ╚═╝ ██║
    ║      ╚═╝     ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝    ╚═════╝ ╚═╝     ╚═╝
    ║                                                                   ║
    ║                    Phantom Server v2.0                            ║
    ║                 极简 · 无状态 · 抗探测                            ║
    ╚═══════════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
}

# 检查 root 权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 权限运行此脚本"
        log_info "尝试: sudo bash $0"
        exit 1
    fi
}

# 检查是否已安装
is_installed() {
    [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]] && [[ -f "$CONFIG_FILE" ]]
}

# 检查服务状态
is_running() {
    systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|amd64) ARCH="amd64" ;;
        aarch64|arm64) ARCH="arm64" ;;
        armv7l) ARCH="armv7" ;;
        *) log_error "不支持的架构: $ARCH"; exit 1 ;;
    esac
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
    elif [[ -f /etc/redhat-release ]]; then
        OS="centos"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
    fi
}

# 获取公网 IP
get_public_ip() {
    local ip=""
    local services=(
        "https://api.ipify.org"
        "https://ifconfig.me/ip"
        "https://icanhazip.com"
        "https://ipinfo.io/ip"
    )
    
    for service in "${services[@]}"; do
        ip=$(curl -s --connect-timeout 5 "$service" 2>/dev/null | tr -d '[:space:]')
        if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            echo "$ip"
            return 0
        fi
    done
    return 1
}

# 生成随机 PSK
generate_psk() {
    openssl rand -base64 32
}

# 读取当前配置
read_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        CURRENT_PORT=$(grep -E "^listen:" "$CONFIG_FILE" | sed 's/listen: *":\([0-9]*\)"/\1/')
        CURRENT_PSK=$(grep -E "^psk:" "$CONFIG_FILE" | sed 's/psk: *"\([^"]*\)"/\1/')
        CURRENT_LOG_LEVEL=$(grep -E "^log_level:" "$CONFIG_FILE" | sed 's/log_level: *"\([^"]*\)"/\1/')
        return 0
    fi
    return 1
}

# 确认操作
confirm() {
    local prompt="$1"
    local default="${2:-N}"
    local response
    
    if [[ "$default" == "Y" ]]; then
        read -rp "$(echo -e "${PURPLE}[?]${NC} ${prompt} [Y/n]: ")" response
        response=${response:-Y}
    else
        read -rp "$(echo -e "${PURPLE}[?]${NC} ${prompt} [y/N]: ")" response
        response=${response:-N}
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# 按任意键继续
press_any_key() {
    echo ""
    read -n 1 -s -r -p "$(echo -e "${CYAN}按任意键继续...${NC}")"
    echo ""
}

#═══════════════════════════════════════════════════════════════════════════════
# 安装相关函数
#═══════════════════════════════════════════════════════════════════════════════

# 安装依赖
install_dependencies() {
    log_step "检查依赖..."
    
    local deps=("curl" "openssl" "tar")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_step "安装依赖: ${missing[*]}"
        case $OS in
            ubuntu|debian)
                apt-get update -qq && apt-get install -y -qq "${missing[@]}"
                ;;
            centos|rhel|fedora|rocky|almalinux)
                yum install -y -q "${missing[@]}" 2>/dev/null || dnf install -y -q "${missing[@]}"
                ;;
            alpine)
                apk add --no-cache "${missing[@]}"
                ;;
        esac
    fi
    
    log_info "依赖检查完成"
}

# 下载二进制文件
download_binary() {
    log_step "下载 Phantom Server v${VERSION}..."
    
    local url="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${BINARY_NAME}-linux-${ARCH}.tar.gz"
    local temp_file="/tmp/${BINARY_NAME}.tar.gz"
    
    mkdir -p "$INSTALL_DIR"
    
    if curl -fSL --progress-bar -o "$temp_file" "$url" 2>/dev/null; then
        tar -xzf "$temp_file" -C "$INSTALL_DIR" 2>/dev/null
        rm -f "$temp_file"
    else
        # 尝试直接下载二进制
        url="https://github.com/${GITHUB_REPO}/releases/download/v${VERSION}/${BINARY_NAME}-linux-${ARCH}"
        if curl -fSL --progress-bar -o "${INSTALL_DIR}/${BINARY_NAME}" "$url"; then
            :
        else
            log_error "下载失败，请检查网络连接"
            return 1
        fi
    fi
    
    chmod +x "${INSTALL_DIR}/${BINARY_NAME}"
    ln -sf "${INSTALL_DIR}/${BINARY_NAME}" "/usr/local/bin/${BINARY_NAME}"
    
    log_info "下载完成"
}

# 生成配置文件
generate_config() {
    local psk="$1"
    local port="$2"
    local log_level="${3:-info}"
    
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LOG_DIR"
    
    cat > "$CONFIG_FILE" << EOF
# ═══════════════════════════════════════════════════════════════════
# Phantom Server v${VERSION} 配置文件
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# ═══════════════════════════════════════════════════════════════════

# 监听端口
listen: ":${port}"

# 预共享密钥 (Base64)
psk: "${psk}"

# 时间窗口 (秒)
time_window: 30

# 日志级别: debug, info, error
log_level: "${log_level}"
EOF

    chmod 600 "$CONFIG_FILE"
    log_info "配置文件已生成: $CONFIG_FILE"
}

# 安装 systemd 服务
install_systemd_service() {
    log_step "安装 systemd 服务..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Phantom Server - 极简代理协议
Documentation=https://github.com/${GITHUB_REPO}
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=${INSTALL_DIR}/${BINARY_NAME} -c ${CONFIG_FILE}
Restart=always
RestartSec=5
LimitNOFILE=1048576

# 安全加固
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=${LOG_DIR} ${CONFIG_DIR}
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "$SERVICE_NAME" --quiet
    
    log_info "systemd 服务已安装"
}

# 配置防火墙
configure_firewall() {
    local port="$1"
    
    log_step "配置防火墙..."
    
    # UFW
    if command -v ufw &> /dev/null && ufw status | grep -q "active"; then
        ufw allow "${port}/udp" > /dev/null 2>&1
        log_info "UFW: 已开放 UDP ${port}"
    fi
    
    # Firewalld
    if command -v firewall-cmd &> /dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="${port}/udp" > /dev/null 2>&1
        firewall-cmd --reload > /dev/null 2>&1
        log_info "Firewalld: 已开放 UDP ${port}"
    fi
    
    # iptables (直接添加，不检查是否存在)
    if command -v iptables &> /dev/null; then
        iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
    fi
}

# 移除防火墙规则
remove_firewall_rule() {
    local port="$1"
    
    # UFW
    if command -v ufw &> /dev/null; then
        ufw delete allow "${port}/udp" > /dev/null 2>&1 || true
    fi
    
    # Firewalld
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --remove-port="${port}/udp" > /dev/null 2>&1 || true
        firewall-cmd --reload > /dev/null 2>&1 || true
    fi
    
    # iptables
    if command -v iptables &> /dev/null; then
        iptables -D INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true
    fi
}

# 生成分享链接
generate_share_link() {
    local psk="$1"
    local server="$2"
    local port="$3"
    
    local config="{\"v\":2,\"server\":\"${server}\",\"port\":${port},\"psk\":\"${psk}\"}"
    local encoded=$(echo -n "$config" | base64 -w 0)
    echo "phantom://${encoded}"
}

# 系统优化
optimize_system() {
    log_step "优化系统参数..."
    
    cat > /etc/sysctl.d/99-phantom.conf << 'EOF'
# Phantom Server 系统优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.core.netdev_max_backlog = 65535
net.core.somaxconn = 65535
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192
fs.file-max = 2097152
EOF

    sysctl -p /etc/sysctl.d/99-phantom.conf > /dev/null 2>&1 || true
    
    # 文件描述符限制
    if ! grep -q "phantom" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'EOF'
# Phantom Server
* soft nofile 1048576
* hard nofile 1048576
EOF
    fi
    
    log_info "系统优化完成"
}

#═══════════════════════════════════════════════════════════════════════════════
# 配置 Cloudflare
#═══════════════════════════════════════════════════════════════════════════════

setup_cloudflare_dns() {
    local domain="$1"
    local cf_token="$2"
    local cf_zone_id="$3"
    local server_ip="$4"
    
    log_step "配置 Cloudflare DNS..."
    
    # 查询现有记录
    local response=$(curl -s -X GET \
        "https://api.cloudflare.com/client/v4/zones/${cf_zone_id}/dns_records?type=A&name=${domain}" \
        -H "Authorization: Bearer ${cf_token}" \
        -H "Content-Type: application/json")
    
    local record_id=$(echo "$response" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
    
    local data="{\"type\":\"A\",\"name\":\"${domain}\",\"content\":\"${server_ip}\",\"ttl\":120,\"proxied\":false}"
    
    if [[ -n "$record_id" && "$record_id" != "null" ]]; then
        # 更新现有记录
        curl -s -X PUT \
            "https://api.cloudflare.com/client/v4/zones/${cf_zone_id}/dns_records/${record_id}" \
            -H "Authorization: Bearer ${cf_token}" \
            -H "Content-Type: application/json" \
            --data "$data" > /dev/null
        log_info "DNS 记录已更新"
    else
        # 创建新记录
        curl -s -X POST \
            "https://api.cloudflare.com/client/v4/zones/${cf_zone_id}/dns_records" \
            -H "Authorization: Bearer ${cf_token}" \
            -H "Content-Type: application/json" \
            --data "$data" > /dev/null
        log_info "DNS 记录已创建"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# 证书管理
#═══════════════════════════════════════════════════════════════════════════════

obtain_certificate() {
    local domain="$1"
    local email="${2:-admin@${domain}}"
    local cert_dir="${CONFIG_DIR}/ssl"
    
    mkdir -p "$cert_dir"
    
    log_step "申请 TLS 证书..."
    
    # 安装 acme.sh（如果不存在）
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        log_step "安装 acme.sh..."
        curl -fsSL https://get.acme.sh | sh -s email="$email" > /dev/null 2>&1 || true
    fi
    
    # 停止可能占用 80 端口的服务
    systemctl stop nginx 2>/dev/null || true
    systemctl stop apache2 2>/dev/null || true
    systemctl stop httpd 2>/dev/null || true
    
    # 申请证书
    if ~/.acme.sh/acme.sh --issue --standalone -d "$domain" \
        --fullchain-file "${cert_dir}/cert.pem" \
        --key-file "${cert_dir}/key.pem" \
        --force > /dev/null 2>&1; then
        
        chmod 600 "${cert_dir}/key.pem"
        chmod 644 "${cert_dir}/cert.pem"
        log_info "证书申请成功"
        return 0
    else
        log_warn "Let's Encrypt 证书申请失败"
        
        if confirm "是否生成自签名证书?"; then
            generate_self_signed_cert "$domain" "$cert_dir"
            return 0
        fi
        return 1
    fi
}

generate_self_signed_cert() {
    local domain="$1"
    local cert_dir="$2"
    
    log_step "生成自签名证书..."
    
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "${cert_dir}/key.pem" \
        -out "${cert_dir}/cert.pem" \
        -subj "/CN=${domain}" 2>/dev/null
    
    chmod 600 "${cert_dir}/key.pem"
    chmod 644 "${cert_dir}/cert.pem"
    
    log_info "自签名证书已生成"
}

renew_certificate() {
    local domain="$1"
    
    if [[ ! -f ~/.acme.sh/acme.sh ]]; then
        log_error "acme.sh 未安装"
        return 1
    fi
    
    log_step "续期证书..."
    
    if ~/.acme.sh/acme.sh --renew -d "$domain" --force > /dev/null 2>&1; then
        log_info "证书续期成功"
        return 0
    else
        log_error "证书续期失败"
        return 1
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# 安装流程
#═══════════════════════════════════════════════════════════════════════════════

# 交互式安装
do_install_interactive() {
    print_banner
    check_root
    detect_os
    detect_arch
    
    if is_installed; then
        log_warn "Phantom Server 已安装"
        if ! confirm "是否重新安装?"; then
            return 0
        fi
        do_uninstall_silent
    fi
    
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                       安装配置向导${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # 获取服务器 IP
    log_step "获取服务器公网 IP..."
    SERVER_IP=$(get_public_ip)
    if [[ -z "$SERVER_IP" ]]; then
        log_input "无法自动获取，请手动输入服务器 IP:"
        read -r SERVER_IP
    else
        log_info "服务器 IP: $SERVER_IP"
    fi
    
    # 端口配置
    echo ""
    log_input "请输入 UDP 端口 [默认: 54321]:"
    read -r PORT
    PORT=${PORT:-54321}
    
    # 验证端口
    if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [[ "$PORT" -lt 1 ]] || [[ "$PORT" -gt 65535 ]]; then
        log_error "无效的端口号"
        return 1
    fi
    
    # 域名配置（可选）
    echo ""
    log_input "请输入域名 (直接回车跳过，使用 IP 连接):"
    read -r DOMAIN
    
    # 如果有域名，询问 Cloudflare 配置
    CF_TOKEN=""
    CF_ZONE_ID=""
    if [[ -n "$DOMAIN" ]]; then
        echo ""
        if confirm "是否配置 Cloudflare DNS?"; then
            log_input "Cloudflare API Token:"
            read -r CF_TOKEN
            log_input "Cloudflare Zone ID:"
            read -r CF_ZONE_ID
        fi
        
        echo ""
        if confirm "是否申请 TLS 证书?"; then
            log_input "邮箱 (用于证书通知) [默认: admin@${DOMAIN}]:"
            read -r EMAIL
            EMAIL=${EMAIL:-"admin@${DOMAIN}"}
            SETUP_CERT=true
        fi
    fi
    
    # 日志级别
    echo ""
    log_input "日志级别 (debug/info/error) [默认: info]:"
    read -r LOG_LEVEL
    LOG_LEVEL=${LOG_LEVEL:-info}
    
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                       开始安装${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    # 执行安装步骤
    install_dependencies
    download_binary
    
    # 生成 PSK
    PSK=$(generate_psk)
    
    # 配置 DNS
    if [[ -n "$CF_TOKEN" && -n "$CF_ZONE_ID" ]]; then
        setup_cloudflare_dns "$DOMAIN" "$CF_TOKEN" "$CF_ZONE_ID" "$SERVER_IP"
        sleep 2
    fi
    
    # 申请证书
    if [[ "${SETUP_CERT:-false}" == "true" ]]; then
        obtain_certificate "$DOMAIN" "$EMAIL"
    fi
    
    # 生成配置
    generate_config "$PSK" "$PORT" "$LOG_LEVEL"
    
    # 保存域名信息（用于后续管理）
    if [[ -n "$DOMAIN" ]]; then
        echo "$DOMAIN" > "${CONFIG_DIR}/.domain"
    fi
    if [[ -n "$CF_TOKEN" ]]; then
        echo "$CF_TOKEN" > "${CONFIG_DIR}/.cf_token"
        chmod 600 "${CONFIG_DIR}/.cf_token"
    fi
    if [[ -n "$CF_ZONE_ID" ]]; then
        echo "$CF_ZONE_ID" > "${CONFIG_DIR}/.cf_zone_id"
    fi
    
    # 配置防火墙
    configure_firewall "$PORT"
    
    # 系统优化
    optimize_system
    
    # 安装服务
    install_systemd_service
    
    # 启动服务
    log_step "启动服务..."
    systemctl start "$SERVICE_NAME"
    sleep 2
    
    # 检查状态
    if is_running; then
        log_info "服务启动成功"
    else
        log_error "服务启动失败，请查看日志: journalctl -u $SERVICE_NAME -f"
        return 1
    fi
    
    # 生成分享链接
    SHARE_LINK=$(generate_share_link "$PSK" "${DOMAIN:-$SERVER_IP}" "$PORT")
    
    # 显示结果
    show_install_result "$SERVER_IP" "$DOMAIN" "$PORT" "$PSK" "$SHARE_LINK"
}

# 快速安装
do_install_quick() {
    print_banner
    check_root
    detect_os
    detect_arch
    
    if is_installed; then
        log_warn "Phantom Server 已安装"
        if ! confirm "是否重新安装?"; then
            return 0
        fi
        do_uninstall_silent
    fi
    
    log_info "快速安装模式 (使用默认配置)"
    echo ""
    
    SERVER_IP=$(get_public_ip)
    if [[ -z "$SERVER_IP" ]]; then
        log_error "无法获取服务器 IP"
        return 1
    fi
    
    PORT="54321"
    PSK=$(generate_psk)
    
    install_dependencies
    download_binary
    generate_config "$PSK" "$PORT" "info"
    configure_firewall "$PORT"
    optimize_system
    install_systemd_service
    
    systemctl start "$SERVICE_NAME"
    sleep 2
    
    if is_running; then
        SHARE_LINK=$(generate_share_link "$PSK" "$SERVER_IP" "$PORT")
        show_install_result "$SERVER_IP" "" "$PORT" "$PSK" "$SHARE_LINK"
    else
        log_error "服务启动失败"
        return 1
    fi
}

# 显示安装结果
show_install_result() {
    local server_ip="$1"
    local domain="$2"
    local port="$3"
    local psk="$4"
    local share_link="$5"
    
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║              Phantom Server v${VERSION} 安装完成！                 ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${WHITE}服务器信息${NC}"
    echo -e "  ─────────────────────────────────────────────────────────"
    echo -e "  IP 地址:     ${CYAN}${server_ip}${NC}"
    [[ -n "$domain" ]] && echo -e "  域名:        ${CYAN}${domain}${NC}"
    echo -e "  端口:        ${CYAN}${port}${NC}"
    echo -e "  PSK:         ${YELLOW}${psk}${NC}"
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════${NC}"
    echo -e "  ${WHITE}客户端分享链接${NC}"
    echo ""
    echo -e "  ${GREEN}${share_link}${NC}"
    echo ""
    echo -e "${PURPLE}═══════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${WHITE}管理命令${NC}"
    echo -e "  ─────────────────────────────────────────────────────────"
    echo -e "  启动:   ${GREEN}systemctl start ${SERVICE_NAME}${NC}"
    echo -e "  停止:   ${GREEN}systemctl stop ${SERVICE_NAME}${NC}"
    echo -e "  重启:   ${GREEN}systemctl restart ${SERVICE_NAME}${NC}"
    echo -e "  状态:   ${GREEN}systemctl status ${SERVICE_NAME}${NC}"
    echo -e "  日志:   ${GREEN}journalctl -u ${SERVICE_NAME} -f${NC}"
    echo -e "  管理:   ${GREEN}bash $0${NC}"
    echo ""
}

#═══════════════════════════════════════════════════════════════════════════════
# 配置管理
#═══════════════════════════════════════════════════════════════════════════════

# 修改端口
do_change_port() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    read_config
    echo ""
    log_info "当前端口: ${CURRENT_PORT}"
    log_input "请输入新端口 [留空取消]:"
    read -r NEW_PORT
    
    if [[ -z "$NEW_PORT" ]]; then
        log_info "已取消"
        return 0
    fi
    
    if ! [[ "$NEW_PORT" =~ ^[0-9]+$ ]] || [[ "$NEW_PORT" -lt 1 ]] || [[ "$NEW_PORT" -gt 65535 ]]; then
        log_error "无效的端口号"
        return 1
    fi
    
    if [[ "$NEW_PORT" == "$CURRENT_PORT" ]]; then
        log_info "端口未改变"
        return 0
    fi
    
    # 更新配置文件
    sed -i "s/listen: *\":${CURRENT_PORT}\"/listen: \":${NEW_PORT}\"/" "$CONFIG_FILE"
    
    # 更新防火墙
    remove_firewall_rule "$CURRENT_PORT"
    configure_firewall "$NEW_PORT"
    
    # 重启服务
    systemctl restart "$SERVICE_NAME"
    
    log_info "端口已修改: ${CURRENT_PORT} → ${NEW_PORT}"
    
    # 显示新的分享链接
    read_config
    SERVER=$(cat "${CONFIG_DIR}/.domain" 2>/dev/null || get_public_ip)
    SHARE_LINK=$(generate_share_link "$CURRENT_PSK" "$SERVER" "$NEW_PORT")
    echo ""
    echo -e "  新分享链接: ${GREEN}${SHARE_LINK}${NC}"
}

# 修改 PSK
do_change_psk() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    read_config
    echo ""
    log_warn "修改 PSK 后，所有客户端需要重新配置"
    
    if ! confirm "确定要修改 PSK?"; then
        return 0
    fi
    
    NEW_PSK=$(generate_psk)
    
    # 更新配置文件
    sed -i "s|psk: *\"${CURRENT_PSK}\"|psk: \"${NEW_PSK}\"|" "$CONFIG_FILE"
    
    # 重启服务
    systemctl restart "$SERVICE_NAME"
    
    log_info "PSK 已更新"
    echo ""
    echo -e "  新 PSK: ${YELLOW}${NEW_PSK}${NC}"
    
    # 显示新的分享链接
    SERVER=$(cat "${CONFIG_DIR}/.domain" 2>/dev/null || get_public_ip)
    SHARE_LINK=$(generate_share_link "$NEW_PSK" "$SERVER" "$CURRENT_PORT")
    echo ""
    echo -e "  新分享链接: ${GREEN}${SHARE_LINK}${NC}"
}

# 修改域名
do_change_domain() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    CURRENT_DOMAIN=$(cat "${CONFIG_DIR}/.domain" 2>/dev/null)
    echo ""
    log_info "当前域名: ${CURRENT_DOMAIN:-无}"
    log_input "请输入新域名 [留空删除域名]:"
    read -r NEW_DOMAIN
    
    if [[ -z "$NEW_DOMAIN" ]]; then
        rm -f "${CONFIG_DIR}/.domain"
        log_info "域名已删除"
    else
        echo "$NEW_DOMAIN" > "${CONFIG_DIR}/.domain"
        log_info "域名已更新: $NEW_DOMAIN"
        
        # 询问是否更新 DNS
        CF_TOKEN=$(cat "${CONFIG_DIR}/.cf_token" 2>/dev/null)
        CF_ZONE_ID=$(cat "${CONFIG_DIR}/.cf_zone_id" 2>/dev/null)
        
        if [[ -n "$CF_TOKEN" && -n "$CF_ZONE_ID" ]]; then
            if confirm "是否更新 Cloudflare DNS?"; then
                SERVER_IP=$(get_public_ip)
                setup_cloudflare_dns "$NEW_DOMAIN" "$CF_TOKEN" "$CF_ZONE_ID" "$SERVER_IP"
            fi
        fi
        
        # 询问是否申请新证书
        if confirm "是否为新域名申请证书?"; then
            log_input "邮箱 [默认: admin@${NEW_DOMAIN}]:"
            read -r EMAIL
            EMAIL=${EMAIL:-"admin@${NEW_DOMAIN}"}
            obtain_certificate "$NEW_DOMAIN" "$EMAIL"
        fi
    fi
    
    # 显示新的分享链接
    read_config
    SERVER="${NEW_DOMAIN:-$(get_public_ip)}"
    SHARE_LINK=$(generate_share_link "$CURRENT_PSK" "$SERVER" "$CURRENT_PORT")
    echo ""
    echo -e "  新分享链接: ${GREEN}${SHARE_LINK}${NC}"
}

# 修改日志级别
do_change_log_level() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    read_config
    echo ""
    log_info "当前日志级别: ${CURRENT_LOG_LEVEL}"
    echo ""
    echo "  1) debug - 调试模式（详细日志）"
    echo "  2) info  - 信息模式（默认）"
    echo "  3) error - 错误模式（仅错误）"
    echo ""
    log_input "请选择 [1-3]:"
    read -r choice
    
    case $choice in
        1) NEW_LEVEL="debug" ;;
        2) NEW_LEVEL="info" ;;
        3) NEW_LEVEL="error" ;;
        *) log_error "无效选择"; return 1 ;;
    esac
    
    sed -i "s/log_level: *\"${CURRENT_LOG_LEVEL}\"/log_level: \"${NEW_LEVEL}\"/" "$CONFIG_FILE"
    systemctl restart "$SERVICE_NAME"
    
    log_info "日志级别已修改: ${CURRENT_LOG_LEVEL} → ${NEW_LEVEL}"
}

# 查看当前配置
do_show_config() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                       当前配置${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    read_config
    DOMAIN=$(cat "${CONFIG_DIR}/.domain" 2>/dev/null)
    SERVER_IP=$(get_public_ip)
    
    echo -e "  配置文件:   ${CYAN}${CONFIG_FILE}${NC}"
    echo ""
    echo -e "  服务器 IP:  ${CYAN}${SERVER_IP}${NC}"
    echo -e "  域名:       ${CYAN}${DOMAIN:-无}${NC}"
    echo -e "  端口:       ${CYAN}${CURRENT_PORT}${NC}"
    echo -e "  PSK:        ${YELLOW}${CURRENT_PSK}${NC}"
    echo -e "  日志级别:   ${CYAN}${CURRENT_LOG_LEVEL}${NC}"
    
    echo ""
    echo -e "  ${WHITE}分享链接:${NC}"
    SHARE_LINK=$(generate_share_link "$CURRENT_PSK" "${DOMAIN:-$SERVER_IP}" "$CURRENT_PORT")
    echo -e "  ${GREEN}${SHARE_LINK}${NC}"
    echo ""
    
    if [[ -f "${CONFIG_DIR}/ssl/cert.pem" ]]; then
        echo -e "  ${WHITE}证书信息:${NC}"
        local expiry=$(openssl x509 -in "${CONFIG_DIR}/ssl/cert.pem" -noout -enddate 2>/dev/null | cut -d= -f2)
        echo -e "  证书路径:   ${CYAN}${CONFIG_DIR}/ssl/cert.pem${NC}"
        echo -e "  过期时间:   ${CYAN}${expiry}${NC}"
        echo ""
    fi
}

# 重新申请证书
do_renew_cert() {
    DOMAIN=$(cat "${CONFIG_DIR}/.domain" 2>/dev/null)
    
    if [[ -z "$DOMAIN" ]]; then
        log_error "未配置域名，无法申请证书"
        return 1
    fi
    
    if confirm "是否为 ${DOMAIN} 重新申请证书?"; then
        log_input "邮箱 [默认: admin@${DOMAIN}]:"
        read -r EMAIL
        EMAIL=${EMAIL:-"admin@${DOMAIN}"}
        
        obtain_certificate "$DOMAIN" "$EMAIL"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# 服务管理
#═══════════════════════════════════════════════════════════════════════════════

do_start() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    if is_running; then
        log_warn "服务已在运行"
        return 0
    fi
    
    systemctl start "$SERVICE_NAME"
    sleep 1
    
    if is_running; then
        log_info "服务已启动"
    else
        log_error "启动失败"
        return 1
    fi
}

do_stop() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    if ! is_running; then
        log_warn "服务未运行"
        return 0
    fi
    
    systemctl stop "$SERVICE_NAME"
    log_info "服务已停止"
}

do_restart() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    systemctl restart "$SERVICE_NAME"
    sleep 1
    
    if is_running; then
        log_info "服务已重启"
    else
        log_error "重启失败"
        return 1
    fi
}

do_status() {
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                       服务状态${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if ! is_installed; then
        echo -e "  安装状态:   ${RED}未安装${NC}"
        echo ""
        return 0
    fi
    
    echo -e "  安装状态:   ${GREEN}已安装${NC}"
    echo -e "  安装路径:   ${CYAN}${INSTALL_DIR}/${BINARY_NAME}${NC}"
    
    if is_running; then
        echo -e "  运行状态:   ${GREEN}运行中${NC}"
        
        # 获取 PID 和运行时间
        local pid=$(systemctl show -p MainPID --value "$SERVICE_NAME")
        local uptime=$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')
        
        echo -e "  进程 PID:   ${CYAN}${pid}${NC}"
        echo -e "  运行时间:   ${CYAN}${uptime}${NC}"
        
        # 获取端口监听
        read_config
        echo -e "  监听端口:   ${CYAN}UDP ${CURRENT_PORT}${NC}"
        
        # 内存使用
        local mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.1f MB", $1/1024}')
        echo -e "  内存使用:   ${CYAN}${mem}${NC}"
    else
        echo -e "  运行状态:   ${RED}已停止${NC}"
    fi
    
    echo ""
}

do_logs() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    echo ""
    log_info "显示最近 50 条日志 (Ctrl+C 退出实时模式)"
    echo ""
    
    journalctl -u "$SERVICE_NAME" -n 50 -f
}

do_show_link() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    read_config
    DOMAIN=$(cat "${CONFIG_DIR}/.domain" 2>/dev/null)
    SERVER_IP=$(get_public_ip)
    
    SHARE_LINK=$(generate_share_link "$CURRENT_PSK" "${DOMAIN:-$SERVER_IP}" "$CURRENT_PORT")
    
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}                       客户端分享链接${NC}"
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "  ${GREEN}${SHARE_LINK}${NC}"
    echo ""
    echo -e "  服务器:  ${CYAN}${DOMAIN:-$SERVER_IP}${NC}"
    echo -e "  端口:    ${CYAN}${CURRENT_PORT}${NC}"
    echo ""
}

#═══════════════════════════════════════════════════════════════════════════════
# 维护功能
#═══════════════════════════════════════════════════════════════════════════════

# 更新
do_update() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    check_root
    detect_arch
    
    # 获取当前版本
    local current_version=""
    if [[ -f "${INSTALL_DIR}/${BINARY_NAME}" ]]; then
        current_version=$("${INSTALL_DIR}/${BINARY_NAME}" -v 2>/dev/null | grep -oP 'v?\d+\.\d+\.\d+' || echo "unknown")
    fi
    
    log_info "当前版本: ${current_version}"
    log_info "最新版本: v${VERSION}"
    
    if [[ "$current_version" == "$VERSION" || "$current_version" == "v$VERSION" ]]; then
        log_info "已是最新版本"
        return 0
    fi
    
    if ! confirm "是否更新到 v${VERSION}?"; then
        return 0
    fi
    
    # 备份当前配置
    do_backup_silent
    
    # 下载新版本
    download_binary
    
    # 重启服务
    systemctl restart "$SERVICE_NAME"
    sleep 1
    
    if is_running; then
        log_info "更新完成"
        local new_version=$("${INSTALL_DIR}/${BINARY_NAME}" -v 2>/dev/null | grep -oP 'v?\d+\.\d+\.\d+' || echo "unknown")
        log_info "新版本: ${new_version}"
    else
        log_error "更新后服务启动失败，正在回滚..."
        do_restore_silent
    fi
}

# 备份
do_backup() {
    if ! is_installed; then
        log_error "Phantom Server 未安装"
        return 1
    fi
    
    mkdir -p "$BACKUP_DIR"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/phantom_backup_${timestamp}.tar.gz"
    
    log_step "创建备份..."
    
    tar -czf "$backup_file" \
        -C / \
        "${CONFIG_DIR#/}" \
        2>/dev/null
    
    log_info "备份已创建: $backup_file"
    
    # 显示备份列表
    echo ""
    echo -e "  ${WHITE}现有备份:${NC}"
    ls -lh "$BACKUP_DIR"/*.tar.gz 2>/dev/null | awk '{print "  " $9 " (" $5 ")"}'
}

do_backup_silent() {
    mkdir -p "$BACKUP_DIR"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="${BACKUP_DIR}/phantom_backup_${timestamp}.tar.gz"
    tar -czf "$backup_file" -C / "${CONFIG_DIR#/}" 2>/dev/null
}

# 恢复
do_restore() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        log_error "没有找到备份文件"
        return 1
    fi
    
    echo ""
    echo -e "${WHITE}可用的备份:${NC}"
    echo ""
    
    local backups=($(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null))
    local i=1
    for backup in "${backups[@]}"; do
        local filename=$(basename "$backup")
        local size=$(ls -lh "$backup" | awk '{print $5}')
        echo "  $i) $filename ($size)"
        ((i++))
    done
    
    echo ""
    log_input "请选择要恢复的备份 [1-$((i-1))]:"
    read -r choice
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -ge "$i" ]]; then
        log_error "无效选择"
        return 1
    fi
    
    local selected_backup="${backups[$((choice-1))]}"
    
    if ! confirm "确定要恢复 $(basename "$selected_backup")? 当前配置将被覆盖"; then
        return 0
    fi
    
    log_step "恢复备份..."
    
    # 停止服务
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    
    # 恢复文件
    tar -xzf "$selected_backup" -C /
    
    # 重启服务
    systemctl start "$SERVICE_NAME"
    
    log_info "备份已恢复"
}

do_restore_silent() {
    local latest_backup=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)
    if [[ -n "$latest_backup" ]]; then
        tar -xzf "$latest_backup" -C /
        systemctl restart "$SERVICE_NAME"
    fi
}

# 清理
do_cleanup() {
    echo ""
    echo -e "${WHITE}清理选项:${NC}"
    echo ""
    echo "  1) 清理旧备份 (保留最近 5 个)"
    echo "  2) 清理日志文件"
    echo "  3) 清理临时文件"
    echo "  4) 全部清理"
    echo "  0) 返回"
    echo ""
    log_input "请选择 [0-4]:"
    read -r choice
    
    case $choice in
        1)
            log_step "清理旧备份..."
            if [[ -d "$BACKUP_DIR" ]]; then
                cd "$BACKUP_DIR" && ls -t *.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
                log_info "旧备份已清理"
            fi
            ;;
        2)
            log_step "清理日志..."
            journalctl --vacuum-time=7d > /dev/null 2>&1
            rm -f "${LOG_DIR}"/*.log.* 2>/dev/null
            log_info "日志已清理"
            ;;
        3)
            log_step "清理临时文件..."
            rm -rf /tmp/phantom-* 2>/dev/null
            log_info "临时文件已清理"
            ;;
        4)
            log_step "全部清理..."
            
            # 清理备份
            if [[ -d "$BACKUP_DIR" ]]; then
                cd "$BACKUP_DIR" && ls -t *.tar.gz 2>/dev/null | tail -n +6 | xargs -r rm -f
            fi
            
            # 清理日志
            journalctl --vacuum-time=7d > /dev/null 2>&1
            rm -f "${LOG_DIR}"/*.log.* 2>/dev/null
            
            # 清理临时文件
            rm -rf /tmp/phantom-* 2>/dev/null
            
            log_info "全部清理完成"
            ;;
        0)
            return 0
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 卸载
do_uninstall() {
    if ! is_installed; then
        log_warn "Phantom Server 未安装"
        return 0
    fi
    
    echo ""
    log_warn "即将卸载 Phantom Server"
    
    if ! confirm "确定要卸载吗?"; then
        log_info "已取消"
        return 0
    fi
    
    # 获取当前端口（用于清理防火墙规则）
    read_config
    
    log_step "停止服务..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    
    log_step "删除服务文件..."
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    
    log_step "删除程序文件..."
    rm -rf "$INSTALL_DIR"
    rm -f "/usr/local/bin/${BINARY_NAME}"
    
    # 清理防火墙规则
    if [[ -n "$CURRENT_PORT" ]]; then
        log_step "清理防火墙规则..."
        remove_firewall_rule "$CURRENT_PORT"
    fi
    
    # 询问是否删除配置
    if confirm "是否删除配置文件?"; then
        rm -rf "$CONFIG_DIR"
        log_info "配置文件已删除"
    else
        log_info "配置文件已保留: $CONFIG_DIR"
    fi
    
    # 询问是否删除备份
    if [[ -d "$BACKUP_DIR" ]] && [[ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        if confirm "是否删除备份文件?"; then
            rm -rf "$BACKUP_DIR"
            log_info "备份文件已删除"
        else
            log_info "备份文件已保留: $BACKUP_DIR"
        fi
    fi
    
    # 清理系统优化配置
    rm -f /etc/sysctl.d/99-phantom.conf
    
    log_info "Phantom Server 已卸载"
}

do_uninstall_silent() {
    read_config 2>/dev/null || true
    
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload
    rm -rf "$INSTALL_DIR"
    rm -f "/usr/local/bin/${BINARY_NAME}"
    rm -rf "$CONFIG_DIR"
    
    if [[ -n "$CURRENT_PORT" ]]; then
        remove_firewall_rule "$CURRENT_PORT"
    fi
}

#═══════════════════════════════════════════════════════════════════════════════
# 菜单系统
#═══════════════════════════════════════════════════════════════════════════════

show_main_menu() {
    print_banner
    
    # 显示当前状态
    if is_installed; then
        if is_running; then
            echo -e "  状态: ${GREEN}● 运行中${NC}"
        else
            echo -e "  状态: ${RED}● 已停止${NC}"
        fi
        read_config 2>/dev/null
        DOMAIN=$(cat "${CONFIG_DIR}/.domain" 2>/dev/null)
        echo -e "  地址: ${CYAN}${DOMAIN:-$(get_public_ip)}:${CURRENT_PORT}${NC}"
    else
        echo -e "  状态: ${YELLOW}● 未安装${NC}"
    fi
    
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    
    if ! is_installed; then
        echo -e "  ${GREEN}1)${NC} 安装 Phantom Server"
        echo -e "  ${GREEN}2)${NC} 快速安装 (默认配置)"
    else
        echo -e "  ${WHITE}── 服务管理 ──${NC}"
        echo -e "  ${GREEN}1)${NC} 启动服务"
        echo -e "  ${GREEN}2)${NC} 停止服务"
        echo -e "  ${GREEN}3)${NC} 重启服务"
        echo -e "  ${GREEN}4)${NC} 查看状态"
        echo -e "  ${GREEN}5)${NC} 查看日志"
        echo -e "  ${GREEN}6)${NC} 显示分享链接"
        echo ""
        echo -e "  ${WHITE}── 配置管理 ──${NC}"
        echo -e "  ${GREEN}11)${NC} 修改端口"
        echo -e "  ${GREEN}12)${NC} 修改域名"
        echo -e "  ${GREEN}13)${NC} 重置 PSK"
        echo -e "  ${GREEN}14)${NC} 修改日志级别"
        echo -e "  ${GREEN}15)${NC} 重新申请证书"
        echo -e "  ${GREEN}16)${NC} 查看当前配置"
        echo ""
        echo -e "  ${WHITE}── 维护功能 ──${NC}"
        echo -e "  ${GREEN}21)${NC} 更新程序"
        echo -e "  ${GREEN}22)${NC} 备份配置"
        echo -e "  ${GREEN}23)${NC} 恢复配置"
        echo -e "  ${GREEN}24)${NC} 清理文件"
        echo -e "  ${GREEN}25)${NC} 卸载"
    fi
    
    echo ""
    echo -e "  ${GREEN}0)${NC} 退出"
    echo ""
    echo -e "${WHITE}════════════════════════════════════════════════════════════════${NC}"
    echo ""
}

handle_menu_choice() {
    local choice="$1"
    
    if ! is_installed; then
        case $choice in
            1) do_install_interactive ;;
            2) do_install_quick ;;
            0) exit 0 ;;
            *) log_error "无效选择" ;;
        esac
    else
        case $choice in
            # 服务管理
            1) do_start ;;
            2) do_stop ;;
            3) do_restart ;;
            4) do_status ;;
            5) do_logs ;;
            6) do_show_link ;;
            
            # 配置管理
            11) do_change_port ;;
            12) do_change_domain ;;
            13) do_change_psk ;;
            14) do_change_log_level ;;
            15) do_renew_cert ;;
            16) do_show_config ;;
            
            # 维护功能
            21) do_update ;;
            22) do_backup ;;
            23) do_restore ;;
            24) do_cleanup ;;
            25) do_uninstall ;;
            
            0) exit 0 ;;
            *) log_error "无效选择" ;;
        esac
    fi
}

run_menu() {
    while true; do
        show_main_menu
        log_input "请选择操作:"
        read -r choice
        echo ""
        handle_menu_choice "$choice"
        
        if [[ "$choice" != "5" ]]; then  # 日志是交互式的，不需要暂停
            press_any_key
        fi
    done
}

#═══════════════════════════════════════════════════════════════════════════════
# 命令行接口
#═══════════════════════════════════════════════════════════════════════════════

show_help() {
    echo ""
    echo "Phantom Server v${VERSION} 管理脚本"
    echo ""
    echo "用法: $0 [命令]"
    echo ""
    echo "命令:"
    echo "  install     交互式安装"
    echo "  quick       快速安装 (默认配置)"
    echo "  uninstall   卸载"
    echo "  start       启动服务"
    echo "  stop        停止服务"
    echo "  restart     重启服务"
    echo "  status      查看状态"
    echo "  logs        查看日志"
    echo "  link        显示分享链接"
    echo "  config      查看配置"
    echo "  update      更新程序"
    echo "  backup      备份配置"
    echo "  restore     恢复配置"
    echo "  help        显示帮助"
    echo ""
    echo "不带参数运行将显示交互式菜单。"
    echo ""
}

#═══════════════════════════════════════════════════════════════════════════════
# 主入口
#═══════════════════════════════════════════════════════════════════════════════

main() {
    # 检查 root
    check_root
    
    # 检测系统
    detect_os
    detect_arch
    
    # 处理命令行参数
    case "${1:-}" in
        install)
            do_install_interactive
            ;;
        quick)
            do_install_quick
            ;;
        uninstall|remove)
            do_uninstall
            ;;
        start)
            do_start
            ;;
        stop)
            do_stop
            ;;
        restart)
            do_restart
            ;;
        status)
            do_status
            ;;
        logs|log)
            do_logs
            ;;
        link)
            do_show_link
            ;;
        config)
            do_show_config
            ;;
        update|upgrade)
            do_update
            ;;
        backup)
            do_backup
            ;;
        restore)
            do_restore
            ;;
        help|-h|--help)
            show_help
            ;;
        "")
            # 无参数，显示交互式菜单
            run_menu
            ;;
        *)
            log_error "未知命令: $1"
            show_help
            exit 1
            ;;
    esac
}

# 运行
main "$@"
