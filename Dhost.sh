#!/bin/bash

# 配置信息
REMOTE_SERVER="user@your-server-ip"     # 远程服务器SSH连接信息
REMOTE_PORT="22"                        # SSH端口
DOMAIN="your-domain.com"                # 需要更新的域名
SSH_KEY="~/.ssh/id_rsa"                # SSH私钥路径
CHECK_IP_INTERVAL=20                    # 本地IP检查间隔（秒）
CHECK_REMOTE_INTERVAL=300               # 远程hosts检查间隔（秒）
IP_FILE="/tmp/last_ip.txt"             # 存储本地IP的文件
REMOTE_HOSTS_FILE="/tmp/remote_hosts.txt" # 存储远程hosts IP的文件
LAST_REMOTE_CHECK=0                     # 上次检查远程hosts的时间戳

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
        
        # SSH连接并修改hosts文件
        ssh -i $SSH_KEY -p $REMOTE_PORT $REMOTE_SERVER "
            cp /etc/hosts /etc/hosts.bak
            if grep -q '$DOMAIN' /etc/hosts; then
                sed -i 's/^.*$DOMAIN.*$/$CURRENT_IP $DOMAIN/' /etc/hosts
            else
                echo '$CURRENT_IP $DOMAIN' >> /etc/hosts
            fi
            echo '修改完成，当前hosts内容：'
            cat /etc/hosts
        "
        
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

