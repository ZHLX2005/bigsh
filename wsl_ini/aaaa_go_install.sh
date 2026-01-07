#!/bin/bash

# 定义颜色
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# 定义常量
readonly GO_VERSION=${1:-"1.25.4"}  # 默认版本为 1.25.4
readonly GO_ROOT="/usr/local/go"
readonly GO_WORKSPACE="/usr/local/go_workspace"
readonly GO_URL="https://dl.google.com/go"
readonly TEMP_DIR="/tmp/go_install_$$"  # 使用 PID 创建唯一临时目录
readonly LOG_FILE="/tmp/go_install_$$.log"

# 检测系统架构
detect_architecture() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[1/9] 检测系统架构${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64)
            GO_ARCH="amd64"
            ;;
        aarch64|arm64)
            GO_ARCH="arm64"
            ;;
        armv7l|armv6l)
            GO_ARCH="armv6l"
            ;;
        i386|i686)
            GO_ARCH="386"
            ;;
        *)
            log_error "不支持的系统架构: $arch"
            echo "支持的架构: amd64, arm64, armv6l, 386"
            exit 1
            ;;
    esac

    echo -e "  系统架构: ${GREEN}$arch${NC}"
    echo -e "  Go 平台:  ${GREEN}linux-$GO_ARCH${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

# 清理函数
cleanup() {
    log_info "清理临时文件..."
    rm -rf "$TEMP_DIR"
    if [ $? -ne 0 ]; then
        log_warn "清理临时文件失败，请手动删除: $TEMP_DIR"
    fi
}

# 错误处理
handle_error() {
    log_error "安装过程中发生错误，请检查日志文件: $LOG_FILE"
    cleanup
    exit 1
}

# 设置错误处理
trap 'handle_error' ERR

# 检查是否为 root 用户
check_root() {
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 权限运行此脚本"
        echo "使用: sudo bash $0 [version]"
        exit 1
    fi
}

# 检查版本格式
check_version() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[2/9] 验证版本格式${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    if [ -z "$1" ]; then
        echo -e "  未指定版本，将使用默认版本: ${GREEN}$GO_VERSION${NC}"
        echo -e "${BLUE}===============================================${NC}"
        echo
        return
    fi

    # 支持版本格式：1.23.4, 1.23.4-beta1, 1.23.4rc1, 1.23.0.0 等
    if ! echo "$GO_VERSION" | grep -qE '^[0-9]+\.[0-9]+(\.[0-9]+)?([a-zA-Z0-9]+)?$'; then
        log_error "无效的版本格式: $GO_VERSION"
        echo "正确的格式例如: 1.23.4, 1.22.0, 1.21beta1, 1.20rc1"
        exit 1
    fi

    echo -e "  版本格式: ${GREEN}✓ 有效${NC}"
    echo -e "  目标版本: ${GREEN}$GO_VERSION${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 检测操作系统
detect_os() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[3/9] 检测操作系统${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_NAME=$NAME
        OS_VERSION=$VERSION_ID
        echo -e "  操作系统: ${GREEN}$OS_NAME${NC}"
        echo -e "  系统版本: ${GREEN}$OS_VERSION${NC}"
        echo -e "${BLUE}===============================================${NC}"
        echo
    else
        log_error "不支持的系统类型"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[4/9] 安装必要的依赖${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"
    echo -e "  正在安装: wget, tar, curl"
    echo

    case "$OS_NAME" in
        *"Ubuntu"*|*"Debian"*)
            apt update -qq
            apt install -y wget tar curl
            ;;
        *"CentOS"*|*"Red Hat"*)
            yum install -y wget tar curl
            ;;
        *"Fedora"*)
            dnf install -y wget tar curl
            ;;
        *"openSUSE"*)
            zypper install -y wget tar curl
            ;;
        *"Arch"*)
            pacman -Sy --noconfirm wget tar curl
            ;;
        *)
            log_error "不支持的系统类型: $OS_NAME"
            exit 1
            ;;
    esac

    echo -e "  依赖安装: ${GREEN}✓ 完成${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 下载 Go
download_go() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[5/9] 下载 Go 安装包${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    # 使用动态架构
    local archive="go$GO_VERSION.linux-$GO_ARCH.tar.gz"
    local download_url="$GO_URL/$archive"

    echo -e "  目标版本: ${GREEN}$GO_VERSION${NC}"
    echo -e "  目标架构: ${GREEN}linux-$GO_ARCH${NC}"
    echo -e "  下载地址: ${GREEN}$download_url${NC}"
    echo

    # 检查版本是否存在
    echo -e "  检查版本可用性..."
    if ! curl --output /dev/null --silent --head --fail "$download_url"; then
        echo -e "  ${RED}✗ 失败${NC}"
        log_error "版本 $GO_VERSION (linux-$GO_ARCH) 不存在或无法访问"
        echo "请检查版本号是否正确，或访问 https://golang.org/dl/ 查看可用版本"
        exit 1
    fi
    echo -e "  版本检查: ${GREEN}✓ 可用${NC}"
    echo

    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR" || exit 1

    echo -e "  开始下载..."
    if ! wget -q --show-progress "$download_url"; then
        echo -e "  ${RED}✗ 失败${NC}"
        log_error "下载失败，请检查网络连接或版本号是否正确"
        exit 1
    fi

    # 验证下载文件
    if [ ! -f "$archive" ]; then
        echo -e "  ${RED}✗ 失败${NC}"
        log_error "下载文件不存在"
        exit 1
    fi

    local file_size=$(du -h "$archive" | cut -f1)
    echo -e "  文件大小: ${GREEN}$file_size${NC}"
    echo -e "  下载状态: ${GREEN}✓ 完成${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 检查现有 Go 安装
check_existing_go() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[6/9] 检查现有安装${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    if command -v go &> /dev/null; then
        local current_version
        current_version=$(go version | awk '{print $3}' | sed 's/go//')
        local current_path=$(which go)

        echo -e "  ${YELLOW}! 检测到已安装的 Go${NC}"
        echo -e "  当前版本: ${YELLOW}$current_version${NC}"
        echo -e "  安装路径: ${YELLOW}$current_path${NC}"
        echo
        echo -n "  是否继续安装 Go ${GO_VERSION}？[y/N] "
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            echo -e "  ${GREEN}安装已取消${NC}"
            echo -e "${BLUE}===============================================${NC}"
            exit 0
        fi

        local backup_dir="${GO_ROOT}_backup_$(date '+%Y%m%d_%H%M%S')"
        echo
        echo -e "  ${YELLOW}将备份现有安装到:${NC}"
        echo -e "  ${YELLOW}  $backup_dir${NC}"
        echo
        echo -n "  是否继续？[y/N] "
        read -r answer
        if [[ ! "$answer" =~ ^[Yy]$ ]]; then
            echo -e "  ${GREEN}安装已取消${NC}"
            echo -e "${BLUE}===============================================${NC}"
            exit 0
        fi
    else
        echo -e "  未检测到现有安装"
    fi

    echo -e "  检查完成: ${GREEN}✓ 继续${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 安装 Go
install_go() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[7/9] 安装 Go${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    # 备份已存在的 Go 安装
    if [ -d "$GO_ROOT" ]; then
        local backup_dir="${GO_ROOT}_backup_$(date '+%Y%m%d_%H%M%S')"
        echo -e "  备份现有安装..."
        if ! mv "$GO_ROOT" "$backup_dir"; then
            log_error "备份失败，无法继续安装"
            exit 1
        fi
        echo -e "  备份位置: ${GREEN}$backup_dir${NC}"
        echo -e "  备份状态: ${GREEN}✓ 完成${NC}"
    fi

    # 解压安装
    echo -e "  解压安装包..."
    local archive="go$GO_VERSION.linux-$GO_ARCH.tar.gz"
    tar -C /usr/local -xzf "$archive"

    if [ ! -d "$GO_ROOT" ]; then
        log_error "安装失败，目录不存在: $GO_ROOT"
        exit 1
    fi

    echo -e "  安装位置: ${GREEN}$GO_ROOT${NC}"
    echo -e "  解压状态: ${GREEN}✓ 完成${NC}"

    # 创建工作空间
    echo -e "  创建工作空间..."
    mkdir -p "$GO_WORKSPACE"/{src,pkg,bin}
    chmod -R 755 "$GO_WORKSPACE"  # 修改为更安全的权限

    echo -e "  工作空间: ${GREEN}$GO_WORKSPACE${NC}"
    echo -e "  安装状态: ${GREEN}✓ 完成${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 配置环境变量
setup_environment() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[8/9] 配置环境变量${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    # 创建环境变量配置文件
    cat > /etc/profile.d/go.sh << EOF
export GOROOT=$GO_ROOT
export GOPATH=$GO_WORKSPACE
export PATH=\$PATH:\$GOROOT/bin:\$GOPATH/bin
EOF

    chmod 644 /etc/profile.d/go.sh

    echo -e "  GOROOT:  ${GREEN}$GO_ROOT${NC}"
    echo -e "  GOPATH:  ${GREEN}$GO_WORKSPACE${NC}"
    echo -e "  配置文件: ${GREEN}/etc/profile.d/go.sh${NC}"
    echo -e "  配置状态: ${GREEN}✓ 完成${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 验证安装
verify_installation() {
    echo -e "${BLUE}===============================================${NC}"
    echo -e "${BLUE}[9/9] 验证安装${NC}"
    echo -e "${BLUE}-----------------------------------------------${NC}"

    # 立即生效环境变量以便验证
    source /etc/profile.d/go.sh

    if ! command -v go &> /dev/null; then
        echo -e "  ${RED}✗ Go 命令不可用${NC}"
        log_error "Go 命令不可用，安装似乎失败了"
        exit 1
    fi

    local installed_version
    installed_version=$(go version | awk '{print $3}' | sed 's/go//')

    echo -e "  Go 版本:  ${GREEN}$installed_version${NC}"
    echo -e "  安装路径: ${GREEN}$(which go)${NC}"

    if [ "$installed_version" != "$GO_VERSION" ]; then
        echo -e "  ${RED}✗ 版本不匹配${NC}"
        log_error "版本不匹配: 预期 $GO_VERSION, 实际 $installed_version"
        exit 1
    fi

    echo -e "  验证状态: ${GREEN}✓ 成功${NC}"
    echo -e "${BLUE}===============================================${NC}"
    echo
}

# 显示完成信息
show_completion() {
    echo
    echo -e "${GREEN}===============================================${NC}"
    echo -e "${BLUE}Go $GO_VERSION 安装完成！${NC}"
    echo -e "${GREEN}-----------------------------------------------${NC}"
    echo -e "请执行以下步骤完成配置："
    echo
    echo -e "1. 重新加载环境变量:"
    echo -e "   ${YELLOW}source /etc/profile${NC}"
    echo
    echo -e "2. 配置 Go 模块和代理 (推荐):"
    echo -e "   ${YELLOW}go env -w GO111MODULE=on${NC}"
    echo -e "   ${YELLOW}go env -w GOPROXY=https://goproxy.cn,direct${NC}"
    echo
    echo -e "3. 验证安装:"
    echo -e "   ${YELLOW}go version${NC}"
    echo -e "${GREEN}===============================================${NC}"
    
    log_info "安装日志已保存至: $LOG_FILE"
}

# 主函数
main() {
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}       Go $GO_VERSION 自动安装脚本${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════${NC}"
    echo

    check_root
    detect_architecture  # 新增：架构检测
    check_version
    detect_os
    install_dependencies
    download_go
    check_existing_go
    install_go
    setup_environment
    verify_installation
    cleanup
    show_completion
}

# 执行主函数
main

