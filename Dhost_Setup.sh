#!/bin/bash

# 如果配置文件不存在，进行交互式配置
CONFIG_FILE="/tmp/dhosts.conf"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "欢迎使用 DHosts！"
    echo "================="
    echo "首次运行，请进行配置..."
    echo

    # 获取配置信息
    read -p "请输入远程服务器用户名 (例如: root): " USERNAME
    read -p "请输入远程服务器IP: " SERVER_IP
    read -p "请输入SSH端口 (默认: 22): " SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    read -p "请输入需要更新的域名: " DOMAIN
    read -p "请输入SSH私钥路径 (默认: ~/.ssh/id_rsa): " SSH_KEY
    SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}
    read -p "请输入本地IP检查间隔(秒) [默认: 20]: " CHECK_IP_INTERVAL
    CHECK_IP_INTERVAL=${CHECK_IP_INTERVAL:-20}
    read -p "请输入远程hosts检查间隔(秒) [默认: 300]: " CHECK_REMOTE_INTERVAL
    CHECK_REMOTE_INTERVAL=${CHECK_REMOTE_INTERVAL:-300}

    # 保存配置到文件
    cat > "$CONFIG_FILE" << EOF
REMOTE_SERVER="${USERNAME}@${SERVER_IP}"
REMOTE_PORT="${SSH_PORT}"
DOMAIN="${DOMAIN}"
SSH_KEY="${SSH_KEY}"
CHECK_IP_INTERVAL=${CHECK_IP_INTERVAL}
CHECK_REMOTE_INTERVAL=${CHECK_REMOTE_INTERVAL}
EOF

    echo
    echo "配置已保存！"
    echo "开始运行 DHosts..."
    echo
else
    # 读取现有配置
    source "$CONFIG_FILE"
fi

# 其他必要的变量
IP_FILE="/tmp/last_ip.txt"
REMOTE_HOSTS_FILE="/tmp/remote_hosts.txt"
LAST_REMOTE_CHECK=0

# 获取IP的函数
get_current_ip() {
    # 尝试多个不同的IP查询服务
    CURRENT_IP=$(curl -s --connect-timeout 5 ifconfig.me) || \
    CURRENT_IP=$(curl -s --connect-timeout 5 ipinfo.io/ip) || \
    CURRENT_IP=$(curl -s --connect-timeout 5 api.ipify.org) || \
    CURRENT_IP=$(curl -s --connect-timeout 5 icanhazip.com) || \
    CURRENT_IP=$(curl -s --connect-timeout 5 ip.sb)
    
    if [ -z "$CURRENT_IP" ]; then
        echo "[$CURRENT_TIME] 错误: 无法获取当前IP" >&2
        return 1
    fi
    
    echo "$CURRENT_IP"
}

# 获取远程hosts中的IP并保存到文件
update_remote_hosts_ip() {
    ssh -i $SSH_KEY -p $REMOTE_PORT $REMOTE_SERVER "grep '$DOMAIN' /etc/hosts | awk '{print \$1}'" > "$REMOTE_HOSTS_FILE" 2>/dev/null
}

# 如果文件不存在，创建它们
if [ ! -f "$IP_FILE" ]; then
    get_current_ip > "$IP_FILE"
fi
if [ ! -f "$REMOTE_HOSTS_FILE" ]; then
    update_remote_hosts_ip
fi

# 显示当前配置
echo "DHosts 运行中..."
echo "----------------"
echo "远程服务器: $REMOTE_SERVER"
echo "域名: $DOMAIN"
echo "本地检查间隔: ${CHECK_IP_INTERVAL}秒"
echo "远程检查间隔: ${CHECK_REMOTE_INTERVAL}秒"
echo "----------------"

while true; do
    CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    CURRENT_TIMESTAMP=$(date +%s)
    
    # 获取当前IP
    CURRENT_IP=$(get_current_ip)
    
    # 检查是否需要更新远程hosts文件缓存
    if [ $((CURRENT_TIMESTAMP - LAST_REMOTE_CHECK)) -ge $CHECK_REMOTE_INTERVAL ]; then
        echo "[$CURRENT_TIME] 更新远程hosts缓存..."
        update_remote_hosts_ip
        LAST_REMOTE_CHECK=$CURRENT_TIMESTAMP
    fi
    
    # 获取缓存的远程IP
    REMOTE_IP=$(cat "$REMOTE_HOSTS_FILE")
    LAST_IP=$(cat "$IP_FILE")

    # 检查是否需要更新
    if [ -z "$REMOTE_IP" ]; then
        echo "[$CURRENT_TIME] 警告: 在远程hosts文件中未找到域名"
        NEED_UPDATE=true
    elif [ "$CURRENT_IP" != "$REMOTE_IP" ]; then
        echo "[$CURRENT_TIME] 远程hosts IP ($REMOTE_IP) 与当前IP ($CURRENT_IP) 不同"
        NEED_UPDATE=true
    else
        NEED_UPDATE=false
    fi

    # 如果IP发生变化或远程hosts需要更新
    if [ "$CURRENT_IP" != "$LAST_IP" ] || [ "$NEED_UPDATE" = true ]; then
        echo "[$CURRENT_TIME] 更新远程hosts文件..."
        
        # SSH命令修改为单行
        SSH_CMD="cp /etc/hosts /etc/hosts.bak && if grep -q '$DOMAIN' /etc/hosts; then sed -i 's/^.*$DOMAIN.*$/$CURRENT_IP $DOMAIN/' /etc/hosts; else echo '$CURRENT_IP $DOMAIN' >> /etc/hosts; fi && echo '修改完成，当前hosts内容：' && cat /etc/hosts"
        
        # 执行SSH命令
        ssh -i $SSH_KEY -p $REMOTE_PORT $REMOTE_SERVER "$SSH_CMD"
        
        # 更新本地缓存
        echo "$CURRENT_IP" > "$IP_FILE"
        echo "$CURRENT_IP" > "$REMOTE_HOSTS_FILE"
        LAST_REMOTE_CHECK=$CURRENT_TIMESTAMP
    else
        echo "[$CURRENT_TIME] IP未变化: $CURRENT_IP" 
    fi

    # 等待下一次检查
    sleep $CHECK_IP_INTERVAL
done 


