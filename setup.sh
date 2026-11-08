#!/bin/bash
# ============================================================
#  ELITE-X SLOWDNS VPN v7-LITE - 512MB RAM / 1 vCPU / OpenSSH
# ============================================================
set -u

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

ACTIVATION_KEY="ELITE"
STATIC_PRIVATE_KEY="7f207e92ab7cb365aad1966b62d2cfbd3f450fe8e523a38ffc7ecfbcec315693"
STATIC_PUBLIC_KEY="40aa057fcb2574e1e9223ea46457f9fdf9d60a2a1c23da87602202d93b41aa04"
EX=/etc/elite-x
RAW="https://raw.githubusercontent.com/NoXFiQ/NoXFiQ/main"

[ "$(id -u)" -eq 0 ] || { echo "Run as root"; exit 1; }

# ---------- 1. Activation & inputs ----------
read -r -p "Activation Key: " KEY
if [ "$KEY" != "$ACTIVATION_KEY" ] && [ "$KEY" != "Whtsapp +255713-628-668" ]; then
    echo -e "${RED}Invalid key${NC}"; exit 1
fi
read -r -p "Nameserver (mf: ns1.domain.com): " TDOMAIN
[[ "$TDOMAIN" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo -e "${RED}NS batili${NC}"; exit 1; }
MTU=1800

# ---------- 2. Clean old installs (KEEPS user data) ----------
cleanup_old(){
    echo -e "${YELLOW}Cleaning old services...${NC}"
    for s in $(systemctl list-units --all --plain --no-legend 'elite-x*' 'dnstt-elite-x*' 2>/dev/null | awk '{print $1}'); do
        systemctl disable --now "$s" >/dev/null 2>&1
    done
    rm -f /etc/systemd/system/elite-x*.service /etc/systemd/system/dnstt-elite-x*.service
    rm -f /usr/local/bin/elite-x-edns-proxy /usr/local/bin/elite-x-udp-turbo \
          /usr/local/bin/elite-x-slowdns-relay /usr/local/bin/elite-x-speedbooster \
          /usr/local/bin/elite-x-bandwidth-c /usr/local/bin/elite-x-connmon-c \
          /usr/local/bin/elite-x-datausage-c /usr/local/bin/elite-x-netbooster \
          /usr/local/bin/elite-x-dnscache /usr/local/bin/elite-x-ramcleaner \
          /usr/local/bin/elite-x-irqopt /usr/local/bin/elite-x-logcleaner \
          /usr/local/bin/elite-x-trafficcleaner /usr/local/bin/elite-x-fairsched \
          /usr/local/bin/elite-x-packetbackup /usr/local/bin/elite-x-midnight \
          /usr/local/bin/elite-x-force-user-message /usr/local/bin/elite-x-update-user-msg
    pkill -f dnstt-server 2>/dev/null
    # remove v7 SSH leftovers (Match blocks appended at the end of main config)
    sed -i '/^Match User/,$d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/elite-x/d' /etc/ssh/sshd_config 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf /etc/ssh/sshd_config.d/zz-elite-x-*.conf
    sed -i '/elite-x/d' /etc/pam.d/sshd 2>/dev/null
    rm -f /etc/sysctl.d/99-elite-x-vpn.conf /etc/security/limits.d/elite-x.conf \
          /etc/systemd/system.conf.d/elite-x-limits.conf /etc/profile.d/elite-x-dashboard.sh
    systemctl daemon-reload
}

# ---------- 3. Packages ----------
install_deps(){
    echo -e "${YELLOW}Installing packages...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl jq iptables dnsutils iproute2 gcc libc6-dev python3 \
        psmisc gawk procps >/dev/null 2>&1
}

# ---------- 4. Swap, kernel, journal ----------
setup_system(){
    if [ "$(swapon --show | wc -l)" -eq 0 ]; then
        fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
        chmod 600 /swapfile; mkswap /swapfile >/dev/null; swapon /swapfile
        grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    modprobe tcp_bbr 2>/dev/null
    cat > /etc/sysctl.d/99-elite-x.conf <<'EOF'
net.ipv4.ip_forward=1
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=4194304
net.core.wmem_max=4194304
net.core.rmem_default=212992
net.core.wmem_default=212992
net.ipv4.tcp_rmem=4096 87380 4194304
net.ipv4.tcp_wmem=4096 65536 4194304
net.core.netdev_max_backlog=5000
net.core.somaxconn=4096
net.ipv4.tcp_max_syn_backlog=4096
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_keepalive_time=60
net.ipv4.tcp_keepalive_intvl=10
net.ipv4.tcp_keepalive_probes=6
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.min_free_kbytes=16384
fs.file-max=131072
EOF
    sysctl -q -p /etc/sysctl.d/99-elite-x.conf >/dev/null 2>&1
    mkdir -p /etc/systemd/journald.conf.d
    printf "[Journal]\nSystemMaxUse=50M\nRuntimeMaxUse=20M\n" > /etc/systemd/journald.conf.d/elite-x.conf
    systemctl restart systemd-journald 2>/dev/null
    timedatectl set-timezone Africa/Dar_es_Salaam 2>/dev/null
}

# ---------- 5. OpenSSH ----------
setup_ssh(){
    cat > /etc/ssh/sshd_config.d/00-elite-x.conf <<'EOF'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
AllowTcpForwarding yes
PermitTunnel yes
GatewayPorts yes
PermitOpen any
UseDNS no
Compression no
LogLevel ERROR
MaxSessions 20
MaxStartups 30:30:60
TCPKeepAlive yes
ClientAliveInterval 30
ClientAliveCountMax 6
PrintMotd no
PrintLastLog no
EOF
    # per-user banners live in a separate file included at the END of sshd_config
    # (so Match blocks never affect the rest of the main config)
    touch /etc/ssh/elite-x-banners.conf
    grep -q 'elite-x-banners.conf' /etc/ssh/sshd_config || \
        echo "Include /etc/ssh/elite-x-banners.conf" >> /etc/ssh/sshd_config
    sshd -t && (systemctl restart ssh 2>/dev/null || systemctl restart sshd)
}

# ---------- 6. DNSTT + port 53 ----------
setup_dnstt(){
    echo -e "${YELLOW}Installing DNSTT...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || \
    curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server
    [ -s /usr/local/bin/dnstt-server ] || { echo -e "${RED}dnstt download failed${NC}"; exit 1; }
    chmod +x /usr/local/bin/dnstt-server
    mkdir -p /etc/dnstt
    echo "$STATIC_PRIVATE_KEY" > /etc/dnstt/server.key; chmod 600 /etc/dnstt/server.key
    echo "$STATIC_PUBLIC_KEY"  > /etc/dnstt/server.pub

    # free port 53 from systemd-resolved stub
    if [ -f /etc/systemd/resolved.conf ]; then
        sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
        systemctl restart systemd-resolved 2>/dev/null
    fi
    [ -L /etc/resolv.conf ] && rm -f /etc/resolv.conf
    printf "nameserver 1.1.1.1\nnameserver 8.8.8.8\noptions timeout:1 attempts:3\n" > /etc/resolv.conf

    cat > /etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=ELITE-X DNSTT Server
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp 127.0.0.1:5300 -mtu ${MTU} -privkey-file /etc/dnstt/server.key ${TDOMAIN} 127.0.0.1:22
Restart=always
RestartSec=3
LimitNOFILE=65535
CPUQuota=40%
MemoryMax=80M
[Install]
WantedBy=multi-user.target
EOF
}

# ---------- 7. Shared library ----------
write_lib(){
cat > /usr/local/lib/elite-x-lib.sh <<'LIBEOF'
#!/bin/bash
# ELITE-X shared helpers
EX=/etc/elite-x
UD=$EX/users; BW=$EX/bandwidth; CN=$EX/connections; BAN=$EX/banned
DD=$EX/deleted; ED=$EX/expired; MS=$EX/user_messages; PIDT=$BW/pidtrack
GLOG=$EX/global_bandwidth.log; DLOG=$EX/global_daily.log
SSHB=/etc/ssh/elite-x-banners.conf
mkdir -p "$UD" "$BW" "$CN" "$BAN" "$DD" "$ED" "$MS" "$PIDT" 2>/dev/null

# read a field from user file (active or expired)
gk(){ local f="$UD/$1"; [ -f "$f" ] || f="$ED/$1"; awk -F': ' -v k="$2" '$1==k{print $2; exit}' "$f" 2>/dev/null; }
setk(){ sed -i "s|^$2: .*|$2: $3|" "$UD/$1"; }
gb(){ awk -v b="${1:-0}" 'BEGIN{printf "%.2f", b/1073741824}'; }
rdn(){ local v; v=$(cat "$1" 2>/dev/null | tr -d ' \n\r'); [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo 0; }

# one /proc scan -> CMAP[uid]=sessions
load_conn_map(){
    declare -gA CMAP=()
    local d puid pp
    for d in /proc/[0-9]*/; do
        [ "$(cat "$d/comm" 2>/dev/null)" = "sshd" ] || continue
        pp=$(awk '{print $4}' "$d/stat" 2>/dev/null); [ "$pp" = "1" ] && continue
        puid=$(awk '/^Uid:/{print $2}' "$d/status" 2>/dev/null)
        [ -n "$puid" ] && CMAP[$puid]=$(( ${CMAP[$puid]:-0} + 1 ))
    done
}

# session pids for one uid
sess_pids(){
    local uid="$1" d puid pp
    [ -n "$uid" ] || return
    for d in /proc/[0-9]*/; do
        [ "$(cat "$d/comm" 2>/dev/null)" = "sshd" ] || continue
        pp=$(awk '{print $4}' "$d/stat" 2>/dev/null); [ "$pp" = "1" ] && continue
        puid=$(awk '/^Uid:/{print $2}' "$d/status" 2>/dev/null)
        [ "$puid" = "$uid" ] && basename "$d"
    done
}

# "count|ip1 ip2" for a user
get_user_connections_by_ip(){
    local u="$1" uid p ip ips="" cnt=0
    uid=$(id -u "$u" 2>/dev/null)
    for p in $(sess_pids "$uid"); do
        cnt=$((cnt+1))
        ip=$(ss -tnp 2>/dev/null | awk -v p="pid=$p," 'index($0,p){sub(/:[0-9]+$/,"",$5); print $5; exit}')
        [ -n "$ip" ] && ips="$ips $ip"
    done
    echo "$cnt|${ips# }"
}
LIBEOF
chmod 644 /usr/local/lib/elite-x-lib.sh
}

# ---------- 8. Banner sync (uses YOUR banner format) ----------
write_banner_sync(){
cat > /usr/local/bin/elite-x-banner-sync <<'BSEOF'
#!/bin/bash
. /usr/local/lib/elite-x-lib.sh
load_conn_map
NOW=$(date +%s)
TMP=$(mktemp)
echo "# ELITE-X per-user banners (auto-generated)" > "$TMP"

for f in "$UD"/*; do
    [ -f "$f" ] || continue
    u=$(basename "$f")
    username="$u"
    msg_file="$MS/$u"

    expire_date=$(gk "$u" Expire)
    bandwidth_gb=$(gk "$u" Bandwidth_GB); bandwidth_gb=${bandwidth_gb:-0}
    daily_limit=$(gk "$u" Daily_Limit);   daily_limit=${daily_limit:-0}
    conn_limit=$(gk "$u" Conn_Limit);     conn_limit=${conn_limit:-1}
    usage_gb=$(gb "$(rdn "$BW/$u.usage")")
    daily_gb=$(gb "$(rdn "$BW/$u.daily_usage")")
    uid=$(id -u "$u" 2>/dev/null)
    current_conn=${CMAP[${uid:-x}]:-0}

    exp_ts=$(date -d "$expire_date" +%s 2>/dev/null || echo 0)
    remaining_seconds=$(( exp_ts - NOW )); [ $remaining_seconds -lt 0 ] && remaining_seconds=0
    remaining_days=$((remaining_seconds / 86400))
    remaining_hours=$(((remaining_seconds % 86400) / 3600))
    remaining_mins=$(((remaining_seconds % 3600) / 60))

    if [ "$bandwidth_gb" = "0" ]; then bw_display="Unlimited"; else bw_display="$bandwidth_gb GB"; fi
    if [ "$daily_limit" = "0" ]; then daily_display="Unlimited"; else daily_display="$daily_limit GB"; fi

    if passwd -S "$u" 2>/dev/null | grep -q " L "; then
        status_icon="🔒"; status_text="LOCKED"
    elif [ $remaining_days -le 0 ] && [ $remaining_hours -eq 0 ]; then
        status_icon="⛔"; status_text="EXPIRED"
    elif [ $remaining_days -le 3 ]; then
        status_icon="⚠️"; status_text="EXPIRING SOON"
    else
        status_icon="🟢"; status_text="ACTIVE"
    fi

    cat <<EOF > "$msg_file"
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #0AB1F3; font-weight: bold;">  <span style="background-color: #09E4A2;">   ELITE-X SLOWDNS VPN V7-LITE </span></span><span style="color: #ffff00; font-weight: bold;">▐</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;"> USERNAME  </span>: <span style="color: #00ff00; font-weight: bold;">$username</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> EXPIRE    </span>: <span style="color: #ff0000; font-weight: bold;">$expire_date</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> REMAINING </span>: <span style="color: #00ffff; font-weight: bold;">${remaining_days}d + ${remaining_hours}hr + ${remaining_mins}min</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> LIMIT GB  </span>: <span style="color: #00ff00; font-weight: bold;">$bw_display</span>
<span style="color: #ffff00; font-weight: bold;"> USAGE GB  </span>: <span style="color: #ff0000; font-weight: bold;">$usage_gb GB</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> DAILY     </span>: <span style="color: #ff00ff; font-weight: bold;">$daily_gb GB / $daily_display</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> CONNECTION</span>: <span style="color: #ff00ff; font-weight: bold;">$current_conn/$conn_limit</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> STATUS    </span>: <span style="color: #00ff00; font-weight: bold;">$status_icon $status_text</span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
<span style="background-color: #09E4A2; color: #ffffff; font-weight: bold; display: block; text-align: center;">   Thanks for using ELITE-X VPN    </span>
<span style="color: #ff00ff; font-weight: bold;">═══════════════════════════════════</span>
EOF
    chmod 644 "$msg_file"
    printf 'Match User %s\n    Banner %s\n' "$u" "$msg_file" >> "$TMP"
done

# drop banners of users that no longer exist
for m in "$MS"/*; do
    [ -f "$m" ] || continue
    [ -f "$UD/$(basename "$m")" ] || rm -f "$m"
done

install -m 644 "$TMP" "$SSHB"; rm -f "$TMP"
sshd -t 2>/dev/null && { systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null; }
exit 0
BSEOF
chmod +x /usr/local/bin/elite-x-banner-sync
}

# ---------- 9. Lock / unlock / expire / delete ----------
write_user_actions(){
cat > /usr/local/bin/elite-x-lock <<'EOF'
#!/bin/bash
. /usr/local/lib/elite-x-lib.sh
u="$1"; kind="$2"; why="$3"
id "$u" >/dev/null 2>&1 || exit 0
usermod -L "$u" 2>/dev/null
pkill -KILL -u "$u" 2>/dev/null
case "$kind" in
    quota) touch "$BW/$u.locked_quota" ;;
    daily) touch "$BW/$u.daily_locked" ;;
    conn)  touch "$BW/$u.conn_locked" ;;
esac
echo "$(date '+%F %T') LOCKED ($kind): $why" >> "$BAN/$u"
/usr/local/bin/elite-x-banner-sync
EOF

cat > /usr/local/bin/elite-x-unlock <<'EOF'
#!/bin/bash
. /usr/local/lib/elite-x-lib.sh
u="$1"
id "$u" >/dev/null 2>&1 || exit 0
usermod -U "$u" 2>/dev/null
rm -f "$BW/$u.locked_quota" "$BW/$u.daily_locked" "$BW/$u.conn_locked"
echo "$(date '+%F %T') UNLOCKED" >> "$BAN/$u"
/usr/local/bin/elite-x-banner-sync
EOF

cat > /usr/local/bin/elite-x-expire <<'EOF'
#!/bin/bash
. /usr/local/lib/elite-x-lib.sh
u="$1"; why="$2"
[ -f "$UD/$u" ] || exit 0
pkill -KILL -u "$u" 2>/dev/null
usermod -L "$u" 2>/dev/null
mv "$UD/$u" "$ED/$u"
echo "$(date '+%F %T') EXPIRED ($why)" >> "$BAN/$u"
/usr/local/bin/elite-x-banner-sync
EOF

cat > /usr/local/bin/elite-x-del <<'EOF'
#!/bin/bash
. /usr/local/lib/elite-x-lib.sh
u="$1"
src="$UD/$u"; [ -f "$src" ] || src="$ED/$u"
[ -f "$src" ] || exit 0
echo "$(rdn "$BW/$u.usage") $u $(date +%F)" >> "$GLOG"
echo "$(date +%F) $(rdn "$BW/$u.daily_usage") $u" >> "$DLOG"
cp "$src" "$DD/${u}_$(date +%Y%m%d%H%M%S)"
pkill -KILL -u "$u" 2>/dev/null
userdel -r "$u" 2>/dev/null
rm -f "$src" "$CN/$u" "$MS/$u" "$BAN/$u" "$BW/$u.usage" "$BW/$u.daily_usage" \
      "$BW/$u.locked_quota" "$BW/$u.daily_locked" "$BW/$u.conn_locked"
/usr/local/bin/elite-x-banner-sync
EOF
chmod +x /usr/local/bin/elite-x-lock /usr/local/bin/elite-x-unlock \
         /usr/local/bin/elite-x-expire /usr/local/bin/elite-x-del
}

# ---------- 10. User CLI (display kept as you specified) ----------
write_user_cli(){
cat > /usr/local/bin/elite-x-user <<'UEOF'
#!/bin/bash
. /usr/local/lib/elite-x-lib.sh
RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
WHITE='\033[1;37m';BOLD='\033[1m';MAGENTA='\033[1;35m';LIGHT_RED='\033[1;31m'
LIGHT_GREEN='\033[1;32m';GRAY='\033[0;90m';NC='\033[0m'

ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
pause(){ read -r -p "Press Enter..." _; }
banner(){ /usr/local/bin/elite-x-banner-sync >/dev/null 2>&1; }
server_ip(){ cat $EX/cached_ip 2>/dev/null; }

add_user(){
    local u p d c bw dl exp
    u=$(ask "Username" ""); [ -z "$u" ] && return
    [[ "$u" =~ ^[a-zA-Z0-9_-]{3,32}$ ]] || { echo -e "${RED}Jina batili (3-32: herufi, namba, _ -)${NC}"; return; }
    if id "$u" &>/dev/null || [ -f "$UD/$u" ] || [ -f "$ED/$u" ]; then echo -e "${RED}User yupo tayari${NC}"; return; fi
    p=$(ask "Password" "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c10)")
    d=$(ask "Siku (days)" 30);       [[ "$d" =~ ^[0-9]+$ ]] || d=30
    c=$(ask "Devices (login limit)" 1); [[ "$c" =~ ^[0-9]+$ ]] || c=1
    bw=$(ask "Bandwidth GB (0=unlimited)" 0)
    dl=$(ask "Daily limit GB (0=unlimited)" 0)
    exp=$(date -d "+$d days" +%F)
    grep -qxF /bin/sh /etc/shells || echo /bin/sh >> /etc/shells
    if ! { useradd -m -s /bin/sh "$u" && echo "$u:$p" | chpasswd && chage -E "$exp" "$u"; }; then
        echo -e "${RED}Imeshindwa kuunda user${NC}"; return
    fi
    cat > "$UD/$u" <<INFO
Username: $u
Password: $p
Expire: $exp
Conn_Limit: $c
Bandwidth_GB: $bw
Daily_Limit: $dl
Speed_Limit: 0
Created: $(date '+%F %T')
INFO
    echo 0 > "$BW/$u.usage"; echo 0 > "$BW/$u.daily_usage"; echo 0 > "$CN/$u"
    banner
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}         USER CREATED SUCCESSFULLY               ${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}"
    printf "${GREEN}║${WHITE}  Username   : ${CYAN}%-38s${GREEN}║${NC}\n" "$u"
    printf "${GREEN}║${WHITE}  Password   : ${CYAN}%-38s${GREEN}║${NC}\n" "$p"
    printf "${GREEN}║${WHITE}  Server NS  : ${CYAN}%-38s${GREEN}║${NC}\n" "$(cat $EX/subdomain 2>/dev/null)"
    printf "${GREEN}║${WHITE}  IP         : ${CYAN}%-38s${GREEN}║${NC}\n" "$(server_ip)"
    printf "${GREEN}║${WHITE}  Public Key : ${CYAN}%-38s${GREEN}║${NC}\n" "$(cat $EX/public_key 2>/dev/null)"
    printf "${GREEN}║${WHITE}  Expire     : ${CYAN}%-38s${GREEN}║${NC}\n" "$exp"
    printf "${GREEN}║${WHITE}  Devices    : ${CYAN}%-38s${GREEN}║${NC}\n" "$c"
    printf "${GREEN}║${WHITE}  Bandwidth  : ${CYAN}%-38s${GREEN}║${NC}\n" "$([ "$bw" = 0 ] && echo Unlimited || echo "$bw GB") / daily $([ "$dl" = 0 ] && echo Unlimited || echo "$dl GB")"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
}

list_users(){
    clear
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                  ACTIVE USERS v7                    ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    if [ -z "$(ls -A "$UD" 2>/dev/null)" ]; then
        echo -e "${CYAN}║${RED}  No users found.${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
        return
    fi
    printf "${CYAN}║${WHITE} %-14s %-12s %-8s %-14s %-18s${CYAN} ║${NC}\n" "USERNAME" "EXPIRE" "LOGIN" "BANDWIDTH" "STATUS"
    echo -e "${CYAN}╟──────────────────────────────────────────────────────────────╢${NC}"

    load_conn_map
    local _total_users=0 _online_users=0 _cur_ts; _cur_ts=$(date +%s)
    for user in "$UD"/*; do
        [ -f "$user" ] || continue
        _total_users=$((_total_users+1))
        local u; u=$(basename "$user")
        local ex limit bw_limit daily_limit
        ex=$(gk "$u" Expire)
        limit=$(gk "$u" Conn_Limit);     [[ "$limit" =~ ^[0-9]+$ ]] || limit=1
        bw_limit=$(gk "$u" Bandwidth_GB); [[ "$bw_limit" =~ ^[0-9]+\.?[0-9]*$ ]] || bw_limit=0
        daily_limit=$(gk "$u" Daily_Limit); [[ "$daily_limit" =~ ^[0-9]+\.?[0-9]*$ ]] || daily_limit=0

        local uid cc; uid=$(id -u "$u" 2>/dev/null); cc=${CMAP[${uid:-x}]:-0}
        local raw_bytes d_raw_bytes total_gb d_used_gb
        raw_bytes=$(rdn "$BW/$u.usage"); d_raw_bytes=$(rdn "$BW/$u.daily_usage")
        total_gb=$(gb "$raw_bytes");     d_used_gb=$(gb "$d_raw_bytes")

        local expire_ts days_left
        expire_ts=$(date -d "$ex" +%s 2>/dev/null || echo 0)
        days_left=$(( (expire_ts - _cur_ts) / 86400 ))

        local status
        if passwd -S "$u" 2>/dev/null | grep -q " L "; then status="${RED}🔒 LOCKED${NC}"
        elif [ "$cc" -gt 0 ]; then status="${LIGHT_GREEN}🟢 ONLINE${NC}"; _online_users=$((_online_users+1))
        elif [ "$days_left" -le 0 ]; then status="${RED}⛔ EXPIRED${NC}"
        elif [ "$days_left" -le 3 ]; then status="${LIGHT_RED}⚠️ CRITICAL${NC}"
        elif [ "$days_left" -le 7 ]; then status="${YELLOW}⚠️ WARNING${NC}"
        else status="${YELLOW}⚫ OFFLINE${NC}"; fi

        local bw_disp total_str="" daily_str="" pct
        if [ "$bw_limit" != "0" ]; then
            pct=$(awk -v u="$raw_bytes" -v l="$bw_limit" 'BEGIN{print (u/(l*1073741824))*100}')
            if awk -v p="$pct" 'BEGIN{exit !(p>=100)}'; then total_str="${RED}${total_gb}/${bw_limit}G${NC}"
            elif awk -v p="$pct" 'BEGIN{exit !(p>=80)}'; then total_str="${YELLOW}${total_gb}/${bw_limit}G${NC}"
            else total_str="${GREEN}${total_gb}/${bw_limit}G${NC}"; fi
        else total_str="${GRAY}${total_gb}G/∞${NC}"; fi
        if [ "$daily_limit" != "0" ]; then
            pct=$(awk -v u="$d_raw_bytes" -v l="$daily_limit" 'BEGIN{print (u/(l*1073741824))*100}')
            if awk -v p="$pct" 'BEGIN{exit !(p>=100)}'; then daily_str="${RED}${d_used_gb}/${daily_limit}G/d${NC}"
            else daily_str="${GREEN}${d_used_gb}/${daily_limit}G/d${NC}"; fi
        fi
        if [ -n "$daily_str" ]; then bw_disp="${total_str}|${daily_str}"; else bw_disp="${total_str}"; fi

        local ld ed
        if   [ "$cc" -eq 0 ];          then ld="${GRAY}0/${limit}${NC}"
        elif [ "$cc" -ge "$limit" ];    then ld="${RED}${cc}/${limit}${NC}"
        else                                 ld="${GREEN}${cc}/${limit}${NC}"; fi
        if   [ "$days_left" -le 0 ];   then ed="${RED}${ex}${NC}"
        elif [ "$days_left" -le 7 ];   then ed="${YELLOW}${ex}${NC}"
        else                                 ed="${GREEN}${ex}${NC}"; fi

        printf "${CYAN}║${WHITE} %-14s %-12b %-8b %-14b %-18b${CYAN} ║${NC}\n" "$u" "$ed" "$ld" "$bw_disp" "$status"
    done

    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${YELLOW}  Total: ${GREEN}${_total_users}${YELLOW} | Online: ${GREEN}${_online_users}${NC}  ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
}

user_details(){
    local username; username=$(ask "Username" "")
    [ -z "$username" ] && return
    [ -f "$UD/$username" ] || { echo -e "${RED}❌ User not found: $username${NC}"; return; }

    local expire_date bandwidth_gb daily_limit speed_limit conn_limit
    expire_date=$(gk "$username" Expire)
    bandwidth_gb=$(gk "$username" Bandwidth_GB); bandwidth_gb=${bandwidth_gb:-0}
    daily_limit=$(gk "$username" Daily_Limit);   daily_limit=${daily_limit:-0}
    speed_limit=$(gk "$username" Speed_Limit);   speed_limit=${speed_limit:-0}
    conn_limit=$(gk "$username" Conn_Limit);     conn_limit=${conn_limit:-1}

    local usage_gb daily_gb
    usage_gb=$(gb "$(rdn "$BW/$username.usage")")
    daily_gb=$(gb "$(rdn "$BW/$username.daily_usage")")

    local conn_info current_conn ip_list
    conn_info=$(get_user_connections_by_ip "$username")
    current_conn=${conn_info%%|*}; ip_list=${conn_info#*|}

    local usage_percent=0
    if [ "$bandwidth_gb" != "0" ]; then
        usage_percent=$(awk -v u="$usage_gb" -v b="$bandwidth_gb" 'BEGIN{p=int((u/b)*100); if(p>100)p=100; if(p<0)p=0; print p}')
    fi
    local bar_length=30 filled bar="" i
    filled=$(( usage_percent * bar_length / 100 ))
    for ((i=0; i<filled; i++)); do bar="${bar}█"; done
    for ((i=filled; i<bar_length; i++)); do bar="${bar}░"; done

    local bw_show="$bandwidth_gb"; [ "$bw_show" = "0" ] && bw_show="Unlimited"
    local dl_show="$daily_limit";  [ "$dl_show" = "0" ] && dl_show="Unlimited"
    local sp_show="$speed_limit";  [ "$sp_show" = "0" ] && sp_show="Unlimited"

    echo -e "${MAGENTA}╔════════════════════════════════════════════════════════════════╗${NC}"
    printf "${MAGENTA}║${WHITE}  %-60s${MAGENTA}║${NC}\n" "USER DETAILS: $username"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}%-28s${MAGENTA}║${NC}\n" "Expire Date" "$expire_date"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}%-28s${MAGENTA}║${NC}\n" "Bandwidth Limit" "$bw_show GB"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}%-28s${MAGENTA}║${NC}\n" "Daily Limit" "$dl_show GB"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}%-28s${MAGENTA}║${NC}\n" "Speed Limit" "$sp_show"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}%-28s${MAGENTA}║${NC}\n" "Connection Limit" "$conn_limit"
    echo -e "${MAGENTA}╠════════════════════════════════════════════════════════════════╣${NC}"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}%-28s${MAGENTA}║${NC}\n" "Current Usage" "$usage_gb GB ($usage_percent%)"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}[%s] %3d%%${MAGENTA}  ║${NC}\n" "Usage Bar" "$bar" "$usage_percent"
    printf "${MAGENTA}║${WHITE}  %-30s: ${CYAN}%-28s${MAGENTA}║${NC}\n" "Daily Usage Today" "$daily_gb GB / $dl_show GB"
    printf "${MAGENTA}║${WHITE}  %-30s: ${YELLOW}%-28s${MAGENTA}║${NC}\n" "Connections" "$current_conn / $conn_limit"
    printf "${MAGENTA}║${WHITE}  %-30s: ${CYAN}%-28s${MAGENTA}║${NC}\n" "Connected IPs" "${ip_list:-None}"
    echo -e "${MAGENTA}╚════════════════════════════════════════════════════════════════╝${NC}"
}

renew_user(){
    local u d cur base new
    u=$(ask "Username" ""); [ -z "$u" ] && return
    if [ ! -f "$UD/$u" ] && [ ! -f "$ED/$u" ]; then echo -e "${RED}Haipo${NC}"; return; fi
    d=$(ask "Siku za kuongeza" 30); [[ "$d" =~ ^[0-9]+$ ]] || d=30
    cur=$(gk "$u" Expire); today=$(date +%F)
    if [[ "$cur" > "$today" ]]; then base="$cur"; else base="$today"; fi
    new=$(date -d "$base +$d days" +%F)
    if [ -f "$ED/$u" ]; then
        mv "$ED/$u" "$UD/$u"
        sed -i "s|^Expire: .*|Expire: $new|" "$UD/$u"
    else
        setk "$u" Expire "$new"
    fi
    chage -E "$new" "$u" 2>/dev/null
    if [ ! -f "$BW/$u.locked_quota" ] && [ ! -f "$BW/$u.daily_locked" ]; then usermod -U "$u" 2>/dev/null; fi
    echo "$(date '+%F %T') RENEWED +$d days -> $new" >> "$BAN/$u"
    banner
    echo -e "${GREEN}Imerenewiwa hadi $new${NC}"
}

set_limit(){
    local u v; u=$(ask "Username" ""); [ -f "$UD/$u" ] || { echo "Haipo"; return; }
    v=$(ask "Devices (login limit)" "$(gk "$u" Conn_Limit)")
    [[ "$v" =~ ^[0-9]+$ ]] || { echo "Batili"; return; }
    setk "$u" Conn_Limit "$v"; banner; echo -e "${GREEN}Imewekwa${NC}"
}

set_bw(){
    local u bw dl; u=$(ask "Username" ""); [ -f "$UD/$u" ] || { echo "Haipo"; return; }
    bw=$(ask "Bandwidth GB (0=unlimited)" "$(gk "$u" Bandwidth_GB)")
    dl=$(ask "Daily limit GB (0=unlimited)" "$(gk "$u" Daily_Limit)")
    [[ "$bw" =~ ^[0-9]+\.?[0-9]*$ ]] && [[ "$dl" =~ ^[0-9]+\.?[0-9]*$ ]] || { echo "Batili"; return; }
    setk "$u" Bandwidth_GB "$bw"; setk "$u" Daily_Limit "$dl"
    banner; echo -e "${GREEN}Limits zimewekwa${NC}"
}

reset_data(){
    local u; u=$(ask "Username" ""); [ -f "$UD/$u" ] || { echo "Haipo"; return; }
    echo 0 > "$BW/$u.usage"; echo 0 > "$BW/$u.daily_usage"
    /usr/local/bin/elite-x-unlock "$u"
    echo -e "${GREEN}Data imerekebishwa${NC}"
}

lock_user(){
    local u; u=$(ask "Username" ""); [ -f "$UD/$u" ] || { echo "Haipo"; return; }
    /usr/local/bin/elite-x-lock "$u" manual "admin"; echo -e "${GREEN}Locked${NC}"
}

unlock_user(){
    local u; u=$(ask "Username" ""); [ -f "$UD/$u" ] || [ -f "$ED/$u" ] || { echo "Haipo"; return; }
    /usr/local/bin/elite-x-unlock "$u"; echo -e "${GREEN}Unlocked${NC}"
}

del_user(){
    local u c; u=$(ask "Username" ""); [ -z "$u" ] && return
    if [ ! -f "$UD/$u" ] && [ ! -f "$ED/$u" ]; then echo -e "${RED}Haipo${NC}"; return; fi
    c=$(ask "Thibitisha futa $u? (y/N)" "N")
    [[ "$c" =~ ^[Yy]$ ]] || { echo "Imeghairiwa"; return; }
    /usr/local/bin/elite-x-del "$u"; echo -e "${GREEN}Imefutwa (imehifadhiwa kwenye Deleted)${NC}"
}

deleted_list(){
    clear
    echo -e "${CYAN}╔════════════════ DELETED USERS ════════════════╗${NC}"
    if [ -z "$(ls -A "$DD" 2>/dev/null)" ]; then
        echo -e "${GRAY}  No deleted users${NC}"
    else
        printf "${YELLOW}  %-20s %-20s %-12s${NC}\n" "Username" "Deleted At" "Expire"
        echo -e "${GRAY}  ─────────────────────────────────────────────────────${NC}"
        for f in "$DD"/*; do
            [ -f "$f" ] || continue
            local n name ts ex
            n=$(basename "$f"); name=${n%_*}; ts=${n##*_}
            ex=$(awk -F': ' '/^Expire:/{print $2; exit}' "$f")
            printf "  %-20s %-20s %-12s\n" "$name" "${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}" "$ex"
        done
    fi
    echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
}

expired_menu(){
    while true; do
        clear
        echo -e "${CYAN}╔════════════════ EXPIRED USERS ════════════════╗${NC}"
        if [ -z "$(ls -A "$ED" 2>/dev/null)" ]; then
            echo -e "${GRAY}  No expired users${NC}"
        else
            printf "${YELLOW}  %-18s %-12s %-22s${NC}\n" "Username" "Expire" "Usage"
            echo -e "${GRAY}  ─────────────────────────────────────────────────────${NC}"
            for f in "$ED"/*; do
                [ -f "$f" ] || continue
                local u; u=$(basename "$f")
                printf "  %-18s %-12s %s GB\n" "$u" "$(gk "$u" Expire)" "$(gb "$(rdn "$BW/$u.usage")")"
            done
        fi
        echo -e "${CYAN}╚════════════════════════════════════════════════════════╝${NC}"
        echo " [1] Renew / Restore user   [2] Delete permanently   [0] Back"
        read -r -p "Option: " c
        case $c in
            1) renew_user ;;
            2) del_user ;;
            0) return ;;
        esac
        pause
    done
}

online_list(){
    load_conn_map
    for f in "$UD"/*; do
        [ -f "$f" ] || continue
        local u uid cc; u=$(basename "$f"); uid=$(id -u "$u" 2>/dev/null); cc=${CMAP[${uid:-x}]:-0}
        [ "$cc" -gt 0 ] && echo "$u : $cc session(s)"
    done
}

case "$1" in
    add)       add_user ;;
    list)      list_users ;;
    details)   user_details ;;
    renew)     renew_user ;;
    setlimit)  set_limit ;;
    setbw)     set_bw ;;
    resetdata) reset_data ;;
    lock)      lock_user ;;
    unlock)    unlock_user ;;
    del)       del_user ;;
    deleted)   deleted_list ;;
    expired)   expired_menu ;;
    online)    online_list ;;
    *) echo "Usage: elite-x-user {add|list|details|renew|setlimit|setbw|resetdata|lock|unlock|del|deleted|expired|online}" ;;
esac
UEOF
chmod +x /usr/local/bin/elite-x-user
}

# ---------- 11. Menu (your layout) ----------
write_menu(){
cat > /usr/local/bin/elite-x <<'MEOF'
#!/bin/bash
. /usr/local/lib/elite-x-lib.sh
RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
WHITE='\033[1;37m';BOLD='\033[1m';MAGENTA='\033[1;35m';GRAY='\033[0;90m';NC='\033[0m'

pause(){ read -r -p "Press Enter..." _; }

cpu_pct(){
    read -r _ u1 n1 s1 i1 w1 q1 sq1 st1 _ < /proc/stat
    sleep 0.5
    read -r _ u2 n2 s2 i2 w2 q2 sq2 st2 _ < /proc/stat
    local t=$(( (u2+n2+s2+i2+w2+q2+sq2+st2) - (u1+n1+s1+i1+w1+q1+sq1+st1) ))
    local idle=$(( (i2+w2) - (i1+w1) ))
    [ $t -gt 0 ] && echo $(( (t-idle)*100/t )) || echo 0
}

svc_dot(){ systemctl is-active --quiet "$1" && echo "${GREEN}●${NC}" || echo "${RED}●${NC}"; }

show_dashboard(){
    clear
    IP=$(cat $EX/cached_ip 2>/dev/null || echo "Unknown")
    SUB=$(cat $EX/subdomain 2>/dev/null || echo "Not set")
    LOC=$(cat $EX/location 2>/dev/null || echo "Tanzania")
    MTU=$(cat $EX/mtu 2>/dev/null || echo "1800")
    RAM=$(free -h | awk '/^Mem:/{print $3"/"$2}')
    CPU=$(cpu_pct)
    TOTAL=$(ls "$UD" 2>/dev/null | wc -l)
    load_conn_map
    ONLINE=${#CMAP[@]}
    DNS=$(svc_dot dnstt-elite-x)
    PRX=$(svc_dot elite-x-edns)
    MON=$(svc_dot elite-x-monitor)
    SSHS=$(systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    PNL=$(svc_dot elite-x-panel)

    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}${BOLD}    ELITE-X SLOWDNS VPN v7 -  ULTRA       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${WHITE}  IP   :${CYAN} $IP   ${WHITE}MTU:${CYAN}$MTU  ${WHITE}LOC:${CYAN}$LOC${NC}"
    echo -e "${MAGENTA}║${WHITE}  NS   :${CYAN} $SUB${NC}"
    echo -e "${MAGENTA}║${WHITE}  RAM  :${CYAN} $RAM   ${WHITE}CPU:${CYAN}${CPU}%  ${WHITE}Users:${CYAN}${TOTAL}  ${WHITE}Online:${CYAN}${ONLINE}${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${YELLOW}  SERVICES STATUS:${NC}"
    echo -e "${MAGENTA}║${WHITE}  DNSTT Server    $DNS  EDNS Proxy    $PRX${NC}"
    echo -e "${MAGENTA}║${WHITE}  SSH             $SSHS  Monitor       $MON  Panel  $PNL${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

server_details(){
    local install_date script_owner total_all_bytes=0 daily_all_bytes=0 f b
    install_date=$(cat $EX/install_date 2>/dev/null || echo "Unknown")
    script_owner="ELITE-X Team | +255713-628-668"
    for f in "$BW"/*.usage; do [ -f "$f" ] && total_all_bytes=$((total_all_bytes + $(rdn "$f"))); done
    total_all_bytes=$((total_all_bytes + $(awk '{s+=$1} END{print s+0}' "$GLOG" 2>/dev/null)))
    for f in "$BW"/*.daily_usage; do [ -f "$f" ] && daily_all_bytes=$((daily_all_bytes + $(rdn "$f"))); done
    local today; today=$(date +%F)
    daily_all_bytes=$((daily_all_bytes + $(awk -v t="$today" '$1==t{s+=$2} END{print s+0}' "$DLOG" 2>/dev/null)))
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}               SERVER DETAILS v7                     ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${WHITE}  %-30s: ${GREEN}%-32s${CYAN}║${NC}\n" "Installed Date" "$install_date"
    printf "${CYAN}║${WHITE}  %-30s: ${GREEN}%-32s${CYAN}║${NC}\n" "Script Owner" "$script_owner"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    printf "${CYAN}║${WHITE}  %-30s: ${YELLOW}%-32s${CYAN}║${NC}\n" "Total Bandwidth (All-time)" "$(gb $total_all_bytes) GB"
    printf "${CYAN}║${WHITE}  %-30s: ${YELLOW}%-32s${CYAN}║${NC}\n" "Daily Usage (Today)" "$(gb $daily_all_bytes) GB"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════╝${NC}"
}

change_ns(){
    local ns; read -r -p "New NS (mf: ns1.domain.com): " ns
    [[ "$ns" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo -e "${RED}Batili${NC}"; return; }
    echo "$ns" > $EX/subdomain; echo "$ns" > $EX/nameserver.conf
    sed -i -E "s|(-privkey-file [^ ]+ )[^ ]+( 127\.0\.0\.1:22)|\1${ns}\2|" /etc/systemd/system/dnstt-elite-x.service
    systemctl daemon-reload; systemctl restart dnstt-elite-x
    echo -e "${GREEN}NS imebadilishwa: $ns${NC}"
}

change_mtu(){
    local m; read -r -p "MTU (100-1800) [1800]: " m; m=${m:-1800}
    [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -ge 100 ] && [ "$m" -le 1800 ] || { echo -e "${RED}Batili${NC}"; return; }
    echo "$m" > $EX/mtu
    sed -i -E "s|-mtu [0-9]+|-mtu $m|" /etc/systemd/system/dnstt-elite-x.service
    systemctl daemon-reload; systemctl restart dnstt-elite-x
    echo -e "${GREEN}MTU: $m${NC}"
}

ports(){
    echo -e "${MAGENTA}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${MAGENTA}║${YELLOW}        ELITE-X PORT REFERENCE                       ${MAGENTA}║${NC}"
    echo -e "${MAGENTA}╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${MAGENTA}║${CYAN}  SSH           : ${WHITE}22${NC}"
    echo -e "${MAGENTA}║${CYAN}  SlowDNS (DNS) : ${WHITE}53 UDP (EDNS Proxy)${NC}"
    echo -e "${MAGENTA}║${CYAN}  DNSTT backend : ${WHITE}127.0.0.1:5300${NC}"
    echo -e "${MAGENTA}║${CYAN}  Web Panel     : ${WHITE}44380${NC}"
    echo -e "${MAGENTA}╚══════════════════════════════════════════════════════╝${NC}"
}

panel_info(){
    local ip sec user pass
    ip=$(cat $EX/cached_ip 2>/dev/null)
    sec=$(grep '^PANEL_SECRET=' $EX/panel.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
    user=$(grep '^PANEL_USER=' $EX/panel.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
    pass=$(grep '^PANEL_PASS_PLAIN=' $EX/panel.conf 2>/dev/null | cut -d= -f2 | tr -d '"')
    echo -e "${GREEN}URL      : http://$ip:44380/$sec${NC}"
    echo -e "${GREEN}Username : $user${NC}"
    echo -e "${GREEN}Password : $pass${NC}"
}

test_msg(){
    local u; read -r -p "Username: " u
    if [ -f "$MS/$u" ]; then sed 's/<[^>]*>//g' "$MS/$u"; else echo -e "${RED}No message for $u${NC}"; fi
}

settings_menu(){
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${YELLOW}              SETTINGS v7                 ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════╣${NC}"
        AUTOBAN=$(cat "$EX/autoban_enabled" 2>/dev/null || echo 0)
        [ "$AUTOBAN" = "1" ] && AB="${GREEN}ON${NC}" || AB="${RED}OFF${NC}"
        echo -e "${CYAN}║${WHITE}  [1]  Auto-Ban        : $AB${NC}"
        echo -e "${CYAN}║${WHITE}  [2]  Restart All Services${NC}"
        echo -e "${CYAN}║${WHITE}  [3]  Restart DNSTT + Relay${NC}"
        echo -e "${CYAN}║${WHITE}  [5]  Fix VPN/SSH${NC}"
        echo -e "${CYAN}║${RED}  [10]   UNINSTALL ELITE-X${NC}"
        echo -e "${CYAN}║${YELLOW}  [11]  Reboot Server${NC}"
        echo -e "${CYAN}║${WHITE}  [12]  Change MTU${NC}"
        echo -e "${CYAN}║${WHITE}  [0]  Back${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════╝${NC}"
        read -r -p "$(echo -e $GREEN"Option: "$NC)" ch
        case $ch in
            1) [ "$AUTOBAN" = "1" ] && echo 0 > "$EX/autoban_enabled" || echo 1 > "$EX/autoban_enabled" ;;
            2) systemctl restart dnstt-elite-x elite-x-edns elite-x-monitor ssh 2>/dev/null
               echo -e "${GREEN}All services restarted${NC}"; pause ;;
            3) systemctl restart dnstt-elite-x elite-x-edns
               echo -e "${GREEN}DNSTT + Proxy restarted${NC}"; pause ;;
            5) systemctl restart dnstt-elite-x elite-x-edns ssh 2>/dev/null || systemctl restart sshd
               /usr/local/bin/elite-x-banner-sync
               echo -e "${GREEN}VPN/SSH fixed${NC}"; pause ;;
            10) uninstall_elitex ;;
            11) read -r -p "Reboot server? [y/N]: " r; [[ "$r" =~ ^[Yy]$ ]] && reboot ;;
            12) change_mtu; pause ;;
            0) return ;;
        esac
    done
}

uninstall_elitex(){
    local c; read -r -p "Andika YES kuthibitisha uninstall (kila user atafutwa): " c
    [ "$c" = "YES" ] || { echo "Imeghairiwa"; pause; return; }
    for s in dnstt-elite-x elite-x-edns elite-x-monitor elite-x-panel elite-x-ipcache; do
        systemctl disable --now "$s" >/dev/null 2>&1
    done
    for u in $(ls "$UD" "$ED" 2>/dev/null | grep -v ':' | grep -v '^$'); do
        [ -f "$UD/$u" ] || [ -f "$ED/$u" ] || continue
        pkill -KILL -u "$u" 2>/dev/null; userdel -r "$u" 2>/dev/null
    done
    rm -f /etc/systemd/system/dnstt-elite-x.service /etc/systemd/system/elite-x-*.service
    rm -f /usr/local/bin/dnstt-server /usr/local/bin/elite-x*
    rm -f /usr/local/lib/elite-x-lib.sh /etc/sysctl.d/99-elite-x.conf
    rm -f /etc/ssh/sshd_config.d/00-elite-x.conf /etc/ssh/elite-x-banners.conf
    sed -i '/elite-x-banners.conf/d' /etc/ssh/sshd_config
    rm -rf /etc/dnstt "$EX"
    systemctl daemon-reload; systemctl restart ssh 2>/dev/null || systemctl restart sshd
    echo -e "${GREEN}ELITE-X imeondolewa.${NC}"
    exit 0
}

main_menu(){
    while true; do
        show_dashboard
        echo -e "${MAGENTA}╔══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${MAGENTA}║${GREEN}${BOLD}                     MAIN MENU v7             ${MAGENTA}${NC}"
        echo -e "${MAGENTA}╠══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${MAGENTA}║${YELLOW}  ═══ USER MANAGEMENT ═══${NC}"
        echo -e "${MAGENTA}║${WHITE}  [1] Create User    [2] List Users     [3] User Details${NC}"
        echo -e "${MAGENTA}║${WHITE}  [4] Renew User     [5] Set Conn Limit  [6] Set BW Limit${NC}"
        echo -e "${MAGENTA}║${WHITE}  [7] Reset BW       [8] Lock User       [9] Unlock User${NC}"
        echo -e "${MAGENTA}║${WHITE}  [10] Delete User   [11] Deleted List   [12] Expired Users${NC}"
        echo -e "${MAGENTA}║${YELLOW}  ═══ TOOLS ═══${NC}"
        echo -e "${MAGENTA}║${WHITE}  [13] Change Nameserver   [14] Server Details${NC}"
        echo -e "${MAGENTA}║${WHITE}  [S] Settings   [W] Web Panel   [M] Test Msg   [P] Ports${NC}"
        echo -e "${MAGENTA}║${WHITE}  [0] Exit${NC}"
        echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════╝${NC}"
        read -r -p "$(echo -e $GREEN"Option: "$NC)" ch
        case $ch in
            1)  elite-x-user add;       pause ;;
            2)  elite-x-user list;      pause ;;
            3)  elite-x-user details;   pause ;;
            4)  elite-x-user renew;     pause ;;
            5)  elite-x-user setlimit;  pause ;;
            6)  elite-x-user setbw;     pause ;;
            7)  elite-x-user resetdata; pause ;;
            8)  elite-x-user lock;      pause ;;
            9)  elite-x-user unlock;    pause ;;
            10) elite-x-user del;       pause ;;
            11) elite-x-user deleted;   pause ;;
            12) elite-x-user expired ;;
            13) change_ns;              pause ;;
            14) server_details;         pause ;;
            [Ss]) settings_menu ;;
            [Ww]) panel_info;           pause ;;
            [Mm]) test_msg;             pause ;;
            [Pp]) ports;                pause ;;
            0) echo -e "${GREEN}Goodbye!${NC}"; exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}"; sleep 1 ;;
        esac
    done
}

main_menu
MEOF
chmod +x /usr/local/bin/elite-x
}

# ---------- 12. EDNS proxy (fixes FORMERR payload size) ----------
build_edns_proxy(){
    echo -e "${YELLOW}Compiling EDNS proxy...${NC}"
    cat > /tmp/elite-x-edns.c <<'CEOF'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <pthread.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define LISTEN_PORT  53
#define BACKEND_PORT 5300
#define EDNS_SIZE    1800
#define BUF          4096
#define MAX_INFLIGHT 64

static int srv = -1;
static int inflight = 0;
static pthread_mutex_t mu = PTHREAD_MUTEX_INITIALIZER;

typedef struct { unsigned char buf[BUF]; int len; struct sockaddr_in cli; socklen_t clen; } job_t;

static int skip_name(const unsigned char *d, int off, int max){
    while (off < max){
        unsigned char l = d[off++];
        if (l == 0) return off;
        if ((l & 0xC0) == 0xC0) return off + 1;
        off += l;
    }
    return max;
}

static void fix_edns(unsigned char *d, int len){
    if (len < 12) return;
    int qd = (d[4]<<8)|d[5], an = (d[6]<<8)|d[7], ns = (d[8]<<8)|d[9], ar = (d[10]<<8)|d[11];
    int off = 12, i;
    for (i = 0; i < qd; i++){ off = skip_name(d, off, len); off += 4; if (off > len) return; }
    for (i = 0; i < an + ns; i++){
        off = skip_name(d, off, len); if (off + 10 > len) return;
        int rd = (d[off+8]<<8)|d[off+9]; off += 10 + rd;
    }
    for (i = 0; i < ar; i++){
        off = skip_name(d, off, len); if (off + 10 > len) return;
        int type = (d[off]<<8)|d[off+1];
        if (type == 41){
            int cur = (d[off+2]<<8)|d[off+3];
            if (cur < EDNS_SIZE){ d[off+2] = EDNS_SIZE >> 8; d[off+3] = EDNS_SIZE & 0xff; }
            return;
        }
        int rd = (d[off+8]<<8)|d[off+9]; off += 10 + rd;
    }
}

static void *worker(void *arg){
    job_t *j = arg;
    fix_edns(j->buf, j->len);
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    if (s >= 0){
        struct timeval tv = {3, 0};
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
        struct sockaddr_in be; memset(&be, 0, sizeof be);
        be.sin_family = AF_INET; be.sin_port = htons(BACKEND_PORT);
        be.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        sendto(s, j->buf, j->len, 0, (struct sockaddr*)&be, sizeof be);
        unsigned char resp[BUF]; socklen_t bl = sizeof be;
        int n = recvfrom(s, resp, BUF, 0, (struct sockaddr*)&be, &bl);
        if (n > 0) sendto(srv, resp, n, 0, (struct sockaddr*)&j->cli, j->clen);
        close(s);
    }
    free(j);
    pthread_mutex_lock(&mu); inflight--; pthread_mutex_unlock(&mu);
    return NULL;
}

int main(void){
    signal(SIGPIPE, SIG_IGN);
    srv = socket(AF_INET, SOCK_DGRAM, 0);
    int one = 1; setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);
    struct sockaddr_in a; memset(&a, 0, sizeof a);
    a.sin_family = AF_INET; a.sin_port = htons(LISTEN_PORT); a.sin_addr.s_addr = htonl(INADDR_ANY);
    if (bind(srv, (struct sockaddr*)&a, sizeof a) < 0){ perror("bind"); return 1; }
    for (;;){
        job_t *j = malloc(sizeof *j);
        if (!j){ sleep(1); continue; }
        j->clen = sizeof j->cli;
        j->len = recvfrom(srv, j->buf, BUF, 0, (struct sockaddr*)&j->cli, &j->clen);
        if (j->len <= 0){ free(j); continue; }
        int ok;
        pthread_mutex_lock(&mu); ok = inflight < MAX_INFLIGHT; if (ok) inflight++; pthread_mutex_unlock(&mu);
        if (!ok){ free(j); continue; }
        pthread_t t; pthread_attr_t at; pthread_attr_init(&at);
        pthread_attr_setdetachstate(&at, PTHREAD_CREATE_DETACHED);
        pthread_attr_setstacksize(&at, 256 * 1024);
        if (pthread_create(&t, &at, worker, j) != 0){
            free(j); pthread_mutex_lock(&mu); inflight--; pthread_mutex_unlock(&mu);
        }
        pthread_attr_destroy(&at);
    }
}
CEOF
    if gcc -O2 -pthread -o /usr/local/bin/elite-x-edns /tmp/elite-x-edns.c 2>/dev/null; then
        echo -e "${GREEN}EDNS proxy compiled${NC}"
    else
        echo -e "${RED}EDNS proxy compile failed${NC}"
    fi
    rm -f /tmp/elite-x-edns.c
}

# ---------- 13. Monitor (quota, daily, expiry, conn limit) ----------
build_monitor(){
    echo -e "${YELLOW}Compiling monitor...${NC}"
    cat > /tmp/elite-x-monitor.c <<'CEOF'
#define _XOPEN_SOURCE 700
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <time.h>
#include <signal.h>
#include <pwd.h>
#include <ctype.h>
#include <sys/stat.h>

#define EX   "/etc/elite-x"
#define UD   EX "/users"
#define BW   EX "/bandwidth"
#define PIDT BW "/pidtrack"
#define CN   EX "/connections"
#define LIB  "/usr/local/bin/"
#define GB   1073741824.0
#define MAXS 4096

typedef struct { unsigned uid; int sess; long long delta; } sess_t;
static sess_t S[MAXS]; static int NS;
static volatile sig_atomic_t running = 1;
static void onsig(int s){ (void)s; running = 0; }

static int rd(const char *p, char *o, size_t n){
    FILE *f = fopen(p, "r"); o[0] = 0; if (!f) return 0;
    if (fgets(o, (int)n, f)) o[strcspn(o, "\r\n")] = 0;
    fclose(f); return 1;
}
static long long rdll(const char *p){ char b[64]; if (!rd(p, b, sizeof b)) return 0; return atoll(b); }
static void wrll(const char *p, long long v){ FILE *f = fopen(p, "w"); if (f){ fprintf(f, "%lld\n", v); fclose(f); } }
static void run(const char *c){ int r = system(c); (void)r; }
static int isnum(const char *s){ if (!*s) return 0; for (; *s; s++) if (!isdigit((unsigned char)*s)) return 0; return 1; }

static long long iob(int pid){
    char p[64], l[256]; snprintf(p, sizeof p, "/proc/%d/io", pid);
    FILE *f = fopen(p, "r"); if (!f) return -1;
    long long r = 0, w = 0;
    while (fgets(l, sizeof l, f)){
        if (!strncmp(l, "rchar:", 6)) r = atoll(l + 6);
        else if (!strncmp(l, "wchar:", 6)) w = atoll(l + 6);
    }
    fclose(f); return r + w;
}
static int find(unsigned uid){
    int i; for (i = 0; i < NS; i++) if (S[i].uid == uid) return i;
    if (NS >= MAXS) return -1;
    S[NS].uid = uid; S[NS].sess = 0; S[NS].delta = 0; return NS++;
}
static void scan(void){
    NS = 0;
    DIR *d = opendir("/proc"); if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))){
        if (!isnum(e->d_name)) continue;
        int pid = atoi(e->d_name); char p[80], b[512];
        snprintf(p, sizeof p, "/proc/%d/comm", pid);
        if (!rd(p, b, sizeof b) || strcmp(b, "sshd")) continue;
        snprintf(p, sizeof p, "/proc/%d/stat", pid);
        FILE *f = fopen(p, "r"); if (!f) continue;
        int ppid = 0;
        if (fgets(b, sizeof b, f)){ char *rp = strrchr(b, ')'); if (rp) sscanf(rp + 2, "%*c %d", &ppid); }
        fclose(f);
        if (ppid == 1) continue;
        snprintf(p, sizeof p, "/proc/%d/status", pid);
        f = fopen(p, "r"); if (!f) continue;
        unsigned uid = 0; int got = 0;
        while (fgets(b, sizeof b, f)) if (!strncmp(b, "Uid:", 4)){ uid = (unsigned)strtoul(b + 4, NULL, 10); got = 1; break; }
        fclose(f);
        if (!got || uid == 0) continue;
        int i = find(uid); if (i < 0) continue;
        S[i].sess++;
        long long cur = iob(pid); if (cur < 0) continue;
        char pf[160]; snprintf(pf, sizeof pf, PIDT "/%d.last", pid);
        long long last = rdll(pf);
        if (last > 0) S[i].delta += (cur >= last) ? (cur - last) : cur;
        wrll(pf, cur);
    }
    closedir(d);
}
static void clean_pidtrack(void){
    DIR *d = opendir(PIDT); if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))){
        char *dot = strstr(e->d_name, ".last"); if (!dot) continue;
        char p[200], q[300];
        snprintf(p, sizeof p, "/proc/%.*s", (int)(dot - e->d_name), e->d_name);
        if (access(p, F_OK) != 0){ snprintf(q, sizeof q, PIDT "/%s", e->d_name); unlink(q); }
    }
    closedir(d);
}
static void daily(void){
    char today[16]; time_t t = time(NULL);
    strftime(today, sizeof today, "%Y-%m-%d", localtime(&t));
    char saved[32]; rd(BW "/current_date", saved, sizeof saved);
    if (!strcmp(saved, today)) return;
    DIR *d = opendir(BW); struct dirent *e;
    if (d){
        while ((e = readdir(d))){
            char *n = e->d_name; size_t L = strlen(n);
            if (L > 12 && !strcmp(n + L - 12, ".daily_usage")){
                char p[300]; snprintf(p, sizeof p, BW "/%s", n); wrll(p, 0);
            } else if (L > 13 && !strcmp(n + L - 13, ".daily_locked")){
                char u[128], c[300]; snprintf(u, sizeof u, "%.*s", (int)(L - 13), n);
                snprintf(c, sizeof c, LIB "elite-x-unlock '%s'", u); run(c);
            }
        }
        closedir(d);
    }
    FILE *f = fopen(BW "/current_date", "w"); if (f){ fprintf(f, "%s\n", today); fclose(f); }
}
static int autoban_on(void){ char b[16]; if (!rd(EX "/autoban_enabled", b, sizeof b)) return 0; return atoi(b) == 1; }

static void cycle(void){
    daily();
    scan();
    clean_pidtrack();
    int ab = autoban_on();
    time_t now = time(NULL);
    DIR *d = opendir(UD); if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))){
        if (e->d_name[0] == '.') continue;
        char u[64]; snprintf(u, sizeof u, "%s", e->d_name);
        char path[300]; snprintf(path, sizeof path, UD "/%s", u);
        FILE *f = fopen(path, "r"); if (!f) continue;
        char line[256], exp[32] = {0};
        double bwl = 0, dl = 0; int cl = 1;
        while (fgets(line, sizeof line, f)){
            if (!strncmp(line, "Expire:", 7)) sscanf(line + 7, " %31s", exp);
            else if (!strncmp(line, "Bandwidth_GB:", 13)) bwl = atof(line + 13);
            else if (!strncmp(line, "Daily_Limit:", 12)) dl = atof(line + 12);
            else if (!strncmp(line, "Conn_Limit:", 11)) cl = atoi(line + 11);
        }
        fclose(f);

        if (exp[0]){
            struct tm tm; memset(&tm, 0, sizeof tm);
            if (strptime(exp, "%Y-%m-%d", &tm)){
                time_t et = mktime(&tm);
                if (now > et + 86400){
                    char c[400]; snprintf(c, sizeof c, LIB "elite-x-expire '%s' 'expired on %s'", u, exp);
                    run(c); continue;
                }
            }
        }
        struct passwd *pw = getpwnam(u); if (!pw) continue;
        int si = -1, i;
        for (i = 0; i < NS; i++) if (S[i].uid == (unsigned)pw->pw_uid){ si = i; break; }
        int cc = si >= 0 ? S[si].sess : 0;
        long long delta = si >= 0 ? S[si].delta : 0;

        char pu[300], pd[300], pc[300], m[320];
        snprintf(pu, sizeof pu, BW "/%s.usage", u);
        snprintf(pd, sizeof pd, BW "/%s.daily_usage", u);
        snprintf(pc, sizeof pc, CN "/%s", u);
        long long used = rdll(pu) + delta, daily_b = rdll(pd) + delta;
        wrll(pu, used); wrll(pd, daily_b); wrll(pc, cc);

        if (bwl > 0 && (double)used >= bwl * GB){
            snprintf(m, sizeof m, BW "/%s.locked_quota", u);
            if (access(m, F_OK) != 0){ char c[400]; snprintf(c, sizeof c, LIB "elite-x-lock '%s' quota 'Bandwidth quota reached'", u); run(c); }
        }
        if (dl > 0 && (double)daily_b >= dl * GB){
            snprintf(m, sizeof m, BW "/%s.daily_locked", u);
            if (access(m, F_OK) != 0){ char c[400]; snprintf(c, sizeof c, LIB "elite-x-lock '%s' daily 'Daily limit reached'", u); run(c); }
        }
        if (ab && cl > 0 && cc > cl){
            snprintf(m, sizeof m, BW "/%s.conn_locked", u);
            if (access(m, F_OK) != 0){ char c[400]; snprintf(c, sizeof c, LIB "elite-x-lock '%s' conn 'Connection limit exceeded'", u); run(c); }
        }
    }
    closedir(d);
}

int main(void){
    signal(SIGTERM, onsig); signal(SIGINT, onsig);
    mkdir(BW, 0755); mkdir(PIDT, 0755); mkdir(CN, 0755);
    int tick = 0;
    while (running){
        cycle();
        if (++tick % 10 == 0) run(LIB "elite-x-banner-sync >/dev/null 2>&1");
        int i; for (i = 0; i < 60 && running; i++) sleep(1);
    }
    return 0;
}
CEOF
    if gcc -O2 -o /usr/local/bin/elite-x-monitor /tmp/elite-x-monitor.c 2>/dev/null; then
        echo -e "${GREEN}Monitor compiled${NC}"
    else
        echo -e "${RED}Monitor compile failed${NC}"
    fi
    rm -f /tmp/elite-x-monitor.c
}

# ---------- 14. Panel (optional, from your repo) ----------
install_panel(){
    echo -e "${YELLOW}Installing web panel...${NC}"
    mkdir -p $EX/panel
    if curl -fsSL --connect-timeout 10 --max-time 30 "$RAW/panel.py" -o $EX/panel/panel.py && \
       curl -fsSL --connect-timeout 10 --max-time 30 "$RAW/panel.html" -o $EX/panel/panel.html; then
        chmod 755 $EX/panel/panel.py; chmod 644 $EX/panel/panel.html
        cat > /etc/systemd/system/elite-x-panel.service <<'EOF'
[Unit]
Description=ELITE-X Web Panel
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
WorkingDirectory=/etc/elite-x/panel
ExecStart=/usr/bin/python3 /etc/elite-x/panel/panel.py
Restart=always
RestartSec=5
CPUQuota=25%
MemoryMax=120M
Nice=5
[Install]
WantedBy=multi-user.target
EOF
        iptables -C INPUT -p tcp --dport 44380 -j ACCEPT 2>/dev/null || iptables -I INPUT -p tcp --dport 44380 -j ACCEPT
    else
        echo -e "${YELLOW}panel files not found in repo - panel skipped${NC}"
    fi
}

# ---------- 15. Units + enable ----------
install_units(){
    cat > /etc/systemd/system/elite-x-edns.service <<'EOF'
[Unit]
Description=ELITE-X EDNS Proxy (port 53 -> DNSTT 5300)
After=dnstt-elite-x.service
Wants=dnstt-elite-x.service
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-edns
Restart=always
RestartSec=2
CPUQuota=30%
MemoryMax=30M
Nice=-5
[Install]
WantedBy=multi-user.target
EOF
    cat > /etc/systemd/system/elite-x-monitor.service <<'EOF'
[Unit]
Description=ELITE-X Monitor (bandwidth, limits, expiry)
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-monitor
Restart=always
RestartSec=5
CPUQuota=15%
MemoryMax=20M
Nice=10
[Install]
WantedBy=multi-user.target
EOF
    cat > /etc/systemd/system/elite-x-ipcache.service <<'EOF'
[Unit]
Description=ELITE-X cache public IP at boot
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'curl -4 -s --max-time 5 icanhazip.com > /etc/elite-x/cached_ip'
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now dnstt-elite-x >/dev/null 2>&1
    systemctl enable --now elite-x-edns >/dev/null 2>&1
    systemctl enable --now elite-x-monitor >/dev/null 2>&1
    systemctl enable --now elite-x-ipcache >/dev/null 2>&1
    [ -f /etc/systemd/system/elite-x-panel.service ] && systemctl enable --now elite-x-panel >/dev/null 2>&1
}

# ---------- MAIN ----------
cleanup_old
install_deps
mkdir -p $EX/{users,bandwidth/pidtrack,connections,banned,deleted,expired,user_messages,panel}
mkdir -p /var/log/elite-x
echo "$TDOMAIN"            > $EX/subdomain
echo "$TDOMAIN"            > $EX/nameserver.conf
echo "$MTU"                > $EX/mtu
echo "Tanzania"            > $EX/location
echo "$STATIC_PUBLIC_KEY"  > $EX/public_key
echo "$STATIC_PRIVATE_KEY" > $EX/private_key
[ -f $EX/autoban_enabled ] || echo 0 > $EX/autoban_enabled
[ -f $EX/install_date ]    || date '+%Y-%m-%d %H:%M:%S' > $EX/install_date
touch $EX/global_bandwidth.log $EX/global_daily.log

setup_system
write_lib
write_banner_sync
write_user_actions
write_user_cli
write_menu
setup_ssh
setup_dnstt
build_edns_proxy
build_monitor
install_panel
install_units
/usr/local/bin/elite-x-banner-sync
curl -4 -s --max-time 5 icanhazip.com > $EX/cached_ip 2>/dev/null

clear
echo -e "${GREEN}ELITE-X LITE v7 imewekwa${NC}"
echo "NS      : $TDOMAIN"
echo "PUBKEY  : $STATIC_PUBLIC_KEY"
echo "Menu    : elite"
echo "Panel   : http://$(cat $EX/cached_ip 2>/dev/null):44380"
systemctl is-active -q dnstt-elite-x   && echo -e "${GREEN}✅ DNSTT${NC}"   || echo -e "${RED}❌ DNSTT${NC}"
systemctl is-active -q elite-x-edns    && echo -e "${GREEN}✅ EDNS Proxy${NC}" || echo -e "${RED}❌ EDNS Proxy${NC}"
systemctl is-active -q elite-x-monitor && echo -e "${GREEN}✅ Monitor${NC}" || echo -e "${RED}❌ Monitor${NC}"
(systemctl is-active -q ssh || systemctl is-active -q sshd) && echo -e "${GREEN}✅ SSH${NC}" || echo -e "${RED}❌ SSH${NC}"
