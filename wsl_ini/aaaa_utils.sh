#!/bin/bash

###############################################################################
# WSL 基础工具安装脚本
# 仅安装必要的开发工具，不包含配置
###############################################################################

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}➜ $1${NC}"
}

print_step() {
    echo -e "${BLUE}▶ $1${NC}"
}

# 检查是否为 WSL 环境
check_wsl() {
    print_step "检查 WSL 环境..."
    if grep -qi microsoft /proc/version 2>/dev/null; then
        print_success "WSL 环境检测成功"
    else
        print_error "非 WSL 环境，脚本可能无法正常工作"
        exit 1
    fi
}

# 更新系统包
update_system() {
    print_step "更新系统包索引..."
    sudo apt-get update -y
    print_success "系统包索引更新完成"
}

# 安装基础开发工具
install_base_tools() {
    print_step "安装基础开发工具..."

    sudo apt-get install -y \
        curl \
        wget \
        git \
        build-essential \
        make \
        pkg-config \
        ssh \
        vim \
        zip \
        unzip \
        ca-certificates \
        gnupg \
        lsb-release \
        software-properties-common \
        apt-transport-https

    print_success "基础开发工具安装完成"
}

# 安装网络工具（可选）
install_network_tools() {
    print_step "安装网络工具..."

    sudo apt-get install -y \
        net-tools \
        iputils-ping \
        traceroute \
        dnsutils \
        telnet \
        openssh-client

    print_success "网络工具安装完成"
}

# 安装常用工具
install_common_tools() {
    print_step "安装常用工具..."

    sudo apt-get install -y \
        htop \
        tree \
        jq \
        ripgrep \
        bat \
        fzf \
        tmux \
        screen \
        ncdu \
        duf

    print_success "常用工具安装完成"
}

# 安装语言运行时（可选）
install_language_runtimes() {
    print_step "安装语言运行时..."

    # Python 3
    sudo apt-get install -y \
        python3 \
        python3-pip \
        python3-venv

    # Node.js (通过 NodeSource)
    if ! command -v node &> /dev/null; then
        print_info "安装 Node.js..."
        curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    print_success "语言运行时安装完成"
}

# 显示安装总结
show_summary() {
    echo ""
    echo "=================================="
    print_success "基础工具安装完成！"
    echo "=================================="
    echo ""
    echo "已安装的工具版本:"
    echo "  Git:       $(git --version 2>/dev/null || echo '未安装')"
    echo "  Vim:       $(vim --version | head -1 2>/dev/null || echo '未安装')"
    echo "  Python:    $(python3 --version 2>/dev/null || echo '未安装')"
    echo "  Node:      $(node --version 2>/dev/null || echo '未安装')"
    echo "  Curl:      $(curl --version 2>/dev/null | head -1 || echo '未安装')"
    echo "  OpenSSL:   $(openssl version 2>/dev/null || echo '未安装')"
    echo ""
    echo "已安装的包列表:"
    dpkg -l | grep -E "git|ssh|vim|python|node" | awk '{print "  " $2 " - " $3}'
    echo ""
    echo "下一步操作:"
    echo "  1. 同步 Windows SSH 配置: ./sync-windows-config.sh"
    echo "  2. 复制 Windows Git 配置: cp /mnt/c/Users/\$USER/.gitconfig ~/"
    echo "  3. 查看已安装的工具: dpkg -l | grep -E 'git|ssh'"
    echo ""
}

# 主函数
main() {
    echo "=================================="
    echo "  WSL 基础工具安装脚本"
    echo "=================================="
    echo ""

    check_wsl
    echo ""

    update_system
    echo ""

    install_base_tools
    echo ""

    # 询问是否安装额外工具
    read -p "是否安装网络工具? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        install_network_tools
        echo ""
    fi

    read -p "是否安装常用工具? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        install_common_tools
        echo ""
    fi

    read -p "是否安装语言运行时 (Python/Node.js)? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        install_language_runtimes
        echo ""
    fi

    show_summary
}

# 运行主函数
main "$@"
