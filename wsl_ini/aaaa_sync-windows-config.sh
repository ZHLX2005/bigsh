#!/bin/bash

###############################################################################
# WSL 同步 Windows 宿主机 SSH 和 Git 配置脚本
# 用法: ./sync-windows-config.sh
###############################################################################

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}➜ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# 检查是否在 WSL 环境中运行
check_wsl_env() {
    print_info "检查 WSL 环境..."

    if [ ! -f /proc/version ] || ! grep -qi microsoft /proc/version; then
        print_error "此脚本只能在 WSL 环境中运行"
        exit 1
    fi

    print_success "WSL 环境确认"
}

# 获取 Windows 用户目录
get_windows_home() {
    print_info "查找 Windows 用户目录..."

    # 方法1: 通过 wslpath 获取
    if cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | grep -q ":"; then
        WIN_HOME=$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')
        WIN_HOME_WSL=$(wslpath "$WIN_HOME" 2>/dev/null)
    fi

    # 方法2: 尝试常见的挂载点
    if [ -z "$WIN_HOME_WSL" ]; then
        for user_dir in /mnt/c/Users/*; do
            if [ -d "$user_dir" ]; then
                WIN_HOME_WSL="$user_dir"
                WIN_HOME=$(cmd.exe /c "echo $user_dir" 2>/dev/null | sed 's|/mnt/c||; s|/|\\|g')
                break
            fi
        done
    fi

    if [ -z "$WIN_HOME_WSL" ] || [ ! -d "$WIN_HOME_WSL" ]; then
        print_error "无法找到 Windows 用户目录"
        exit 1
    fi

    print_success "找到 Windows 用户目录: $WIN_HOME_WSL"
}

# 备份现有配置
backup_config() {
    local file_path=$1
    local backup_suffix=$2

    if [ -e "$file_path" ]; then
        local backup_path="${file_path}${backup_suffix}"
        print_warning "已存在的配置将备份到: $backup_path"
        mv "$file_path" "$backup_path"
        print_success "备份完成"
    fi
}

# 同步 SSH 配置
sync_ssh_config() {
    print_info "同步 SSH 配置..."

    local win_ssh_dir="$WIN_HOME_WSL/.ssh"
    local wsl_ssh_dir="$HOME/.ssh"

    # 检查 Windows SSH 目录是否存在
    if [ ! -d "$win_ssh_dir" ]; then
        print_warning "Windows SSH 目录不存在: $win_ssh_dir"
        print_warning "跳过 SSH 配置同步"
        return
    fi

    # 备份现有配置
    if [ -d "$wsl_ssh_dir" ]; then
        backup_config "$wsl_ssh_dir" ".backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # 创建 WSL SSH 目录
    mkdir -p "$wsl_ssh_dir"

    # 复制 SSH 文件
    print_info "复制 SSH 配置文件..."
    cp -r "$win_ssh_dir"/* "$wsl_ssh_dir/" 2>/dev/null || true

    # 设置正确的权限
    print_info "设置 SSH 文件权限..."
    chmod 700 "$wsl_ssh_dir"
    chmod 600 "$wsl_ssh_dir"/* 2>/dev/null || true
    chmod 644 "$wsl_ssh_dir"/*.pub 2>/dev/null || true
    chmod 600 "$wsl_ssh_dir"/config 2>/dev/null || true
    chmod 644 "$wsl_ssh_dir"/known_hosts 2>/dev/null || true

    # 处理 potential 的私钥文件（包括各种常见格式）
    find "$wsl_ssh_dir" -type f -name "id_*" ! -name "*.pub" -exec chmod 600 {} \; 2>/dev/null || true

    print_success "SSH 配置同步完成"
    echo ""
    print_info "SSH 配置文件列表:"
    ls -la "$wsl_ssh_dir"
}

# 同步 Git 配置
sync_git_config() {
    print_info "同步 Git 配置..."

    local win_gitconfig="$WIN_HOME_WSL/.gitconfig"
    local wsl_gitconfig="$HOME/.gitconfig"

    # 检查 Windows gitconfig 是否存在
    if [ ! -f "$win_gitconfig" ]; then
        print_warning "Windows .gitconfig 不存在: $win_gitconfig"
        print_warning "跳过 Git 配置同步"
        return
    fi

    # 备份现有配置
    if [ -f "$wsl_gitconfig" ]; then
        backup_config "$wsl_gitconfig" ".backup.$(date +%Y%m%d_%H%M%S)"
    fi

    # 复制配置文件
    cp "$win_gitconfig" "$wsl_gitconfig"

    # 更新可能的 Windows 特定路径
    print_info "调整 Windows 路径引用..."
    sed -i 's|C:\\\\Users\\\\|/mnt/c/Users/|g' "$wsl_gitconfig" 2>/dev/null || true
    sed -i 's|C:/Users/|/mnt/c/Users/|g' "$wsl_gitconfig" 2>/dev/null || true

    print_success "Git 配置同步完成"
    echo ""
    print_info "Git 配置内容:"
    cat "$wsl_gitconfig"
}

# 同步 .git-credentials (如果存在)
sync_git_credentials() {
    local win_creds="$WIN_HOME_WSL/.git-credentials"
    local wsl_creds="$HOME/.git-credentials"

    if [ -f "$win_creds" ]; then
        print_info "同步 Git 凭证存储..."

        if [ -f "$wsl_creds" ]; then
            backup_config "$wsl_creds" ".backup.$(date +%Y%m%d_%H%M%S)"
        fi

        cp "$win_creds" "$wsl_creds"
        chmod 600 "$wsl_creds"

        # 转换路径
        sed -i 's|C:/Users/|/mnt/c/Users/|g' "$wsl_creds" 2>/dev/null || true

        print_success "Git 凭证同步完成"
    fi
}

# 配置 Git 自动处理换行符
configure_git_core() {
    print_info "配置 Git 核心设置..."

    # 设置在 Linux 提交时转换 CRLF 为 LF
    git config --global core.autocrlf input 2>/dev/null || true

    print_success "Git core.autocrlf 设置为 input"
}

# 测试 SSH 连接
test_ssh_connection() {
    print_info "测试 SSH 配置..."

    if [ -f "$HOME/.ssh/id_rsa.pub" ] || [ -f "$HOME/.ssh/id_ed25519.pub" ]; then
        print_success "找到 SSH 公钥"

        # 尝试列出公钥
        echo ""
        print_info "SSH 公钥列表:"
        find "$HOME/.ssh" -maxdepth 1 -type f -name "*.pub" -exec echo "  - {}" \; -exec ssh-keygen -l -f {} \; 2>/dev/null || true

        echo ""
        print_info "你可以使用以下命令测试 SSH 连接:"
        echo "  ssh -T git@github.com    # 测试 GitHub"
        echo "  ssh -T git@gitlab.com    # 测试 GitLab"
    else
        print_warning "未找到 SSH 公钥文件"
    fi
}

# 显示同步总结
show_summary() {
    echo ""
    echo "=================================="
    print_success "配置同步完成！"
    echo "=================================="
    echo ""
    echo "已同步的内容:"
    echo "  • SSH 密钥和配置: ~/.ssh/"
    echo "  • Git 配置文件: ~/.gitconfig"
    echo ""
    echo "下一步:"
    echo "  1. 测试 SSH 连接: ssh -T git@github.com"
    echo "  2. 克隆仓库: git clone git@github.com:user/repo.git"
    echo "  3. 查看配置: git config --list --show-origin"
    echo ""
}

# 主函数
main() {
    echo "========================================"
    echo "  WSL 同步 Windows 配置脚本"
    echo "========================================"
    echo ""

    # 检查 WSL 环境
    check_wsl_env
    echo ""

    # 获取 Windows 用户目录
    get_windows_home
    echo ""

    # 询问用户要同步哪些配置
    echo "请选择要同步的配置 (直接回车表示全部):"
    read -p "同步 SSH 配置? [Y/n]: " sync_ssh
    read -p "同步 Git 配置? [Y/n]: " sync_git

    # 默认值处理
    sync_ssh=${sync_ssh:-Y}
    sync_git=${sync_git:-Y}

    echo ""

    # 执行同步
    if [[ "$sync_ssh" =~ ^[Yy]$ ]]; then
        sync_ssh_config
        echo ""
    fi

    if [[ "$sync_git" =~ ^[Yy]$ ]]; then
        sync_git_config
        sync_git_credentials
        configure_git_core
        echo ""
    fi

    # 测试和总结
    if [[ "$sync_ssh" =~ ^[Yy]$ ]]; then
        test_ssh_connection
    fi

    show_summary
}

# 运行主函数
main "$@"
