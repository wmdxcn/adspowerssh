#!/bin/bash

# ==========================================
# 交互式获取配置信息
# ==========================================
echo "-------------------------------------------"
echo "      SSH 代理用户及端口快速配置工具           "
echo "-------------------------------------------"

# 1. 获取端口号
read -p "请输入新的 SSH 端口号 [默认: 22]: " ssh_port
ssh_port=${ssh_port:-22}

# 2. 获取用户名
read -p "请输入要创建的代理用户名 [默认: adsproxy]: " proxy_user
proxy_user=${proxy_user:-adsproxy}

# 3. 获取密码
read -s -p "请输入该用户的代理密码 [默认随机生成]: " proxy_pass
echo ""

if [ -z "$proxy_pass" ]; then
    proxy_pass=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 12)
fi

# 自动获取 nologin 路径
NOLOGIN_PATH=$(which nologin 2>/dev/null || echo "/usr/sbin/nologin")

echo "正在配置中，请稍候..."

# ==========================================
# 开始系统配置
# ==========================================

# 1. 备份配置
sudo cp /etc/ssh/sshd_config "/etc/ssh/sshd_config.bak"

# 2. 修改 SSH 端口
if grep -q "^#\?Port" /etc/ssh/sshd_config; then
    sudo sed -i "s|^#\?Port.*|Port $ssh_port|" /etc/ssh/sshd_config
else
    echo "Port $ssh_port" | sudo tee -a /etc/ssh/sshd_config
fi

# 3. 全局性能与基础配置
set_ssh_config() {
    local key=$1
    local value=$2
    if grep -q "^#\?$key" /etc/ssh/sshd_config; then
        sudo sed -i "s|^#\?$key.*|$key $value|" /etc/ssh/sshd_config
    else
        echo "$key $value" | sudo tee -a /etc/ssh/sshd_config
    fi
}

set_ssh_config "MaxSessions" "100"
set_ssh_config "MaxStartups" "100:30:200"
set_ssh_config "ClientAliveInterval" "30"
set_ssh_config "ClientAliveCountMax" "3"
set_ssh_config "AllowTcpForwarding" "yes"
set_ssh_config "PasswordAuthentication" "yes"
set_ssh_config "PermitRootLogin" "yes"

# 4. 自动处理防火墙放行
if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
    sudo ufw allow "$ssh_port/tcp" >/dev/null
elif command -v firewall-cmd &>/dev/null && sudo systemctl is-active --quiet firewalld; then
    sudo firewall-cmd --permanent --add-port="$ssh_port/tcp" >/dev/null
    sudo firewall-cmd --reload >/dev/null
fi

# 5. 创建/更新代理用户
if ! id "$proxy_user" &>/dev/null; then
    sudo useradd -m -s "$NOLOGIN_PATH" "$proxy_user"
else
    sudo usermod -s "$NOLOGIN_PATH" "$proxy_user"
fi
echo "$proxy_user:$proxy_pass" | sudo chpasswd

# 6. 配置 Match 块 (带标记，防止重复写入)
sudo sed -i "/# --- $proxy_user START ---/,/# --- $proxy_user END ---/d" /etc/ssh/sshd_config
sudo tee -a /etc/ssh/sshd_config <<EOF

# --- $proxy_user START ---
Match User $proxy_user
    AllowTcpForwarding yes
    X11Forwarding no
    PermitTunnel no
    PermitTTY no
    ForceCommand $NOLOGIN_PATH
# --- $proxy_user END ---
EOF

# 7. 最终检查与重启
echo "-------------------------------------------"
if sudo sshd -t; then
    echo "✅ 配置文件检查通过，正在重启服务..."
    sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
    
    echo "-------------------------------------------"
    echo "配置成功！请保存以下信息："
    echo "SSH 端口: $ssh_port"
    echo "用户名  : $proxy_user"
    echo "密  码  : $proxy_pass"
    echo "-------------------------------------------"
    echo "⚠️  注意：如果使用的是云服务器，请务必在云平台安全组开启 $ssh_port 端口！"
else
    echo "❌ 配置文件存在错误，已取消重启！"
    sudo mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    sudo systemctl restart ssh

fi
