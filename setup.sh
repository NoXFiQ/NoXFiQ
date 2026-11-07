#!/bin/bash
# ============================================================
#  ELITE-X LITE v8 - 512MB RAM / 1 vCPU / OpenSSH only
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
echo "MTU: [1] 1800 (default)  [2] 1500  [3] 1400"
read -r -p "Chagua [1]: " M
case "${M:-1}" in 2) MTU=1500;; 3) MTU=1400;; *) MTU=1800;; esac

# ---------- 2. Clean old v7 install (keeps user data) ----------
cleanup_old(){
    echo -e "${YELLOW}Cleaning old services...${NC}"
    for s in $(systemctl list-units --all --plain --no-legend 'elite-x*' 'dnstt-elite-x*' 2>/dev/null | awk '{print $1}'); do
        systemctl disable --now "$s" >/dev/null 2>&1
    done
    rm -f /etc/systemd/system/elite-x*.service /etc/systemd/system/dnstt-elite-x*.service
    for b in edns-proxy udp-turbo slowdns-relay speedbooster bandwidth-c connmon-c datausage-c \
             netbooster dnscache ramcleaner irqopt logcleaner trafficcleaner fairsched \
             packetbackup midnight force-user-message update-user-msg monitor; do
        rm -f "/usr/local/bin/elite-x-$b"
    done
    pkill -f dnstt-server 2>/dev/null
    # SSH: remove old appended Match blocks and Include lines
    sed -i '/^Match User/,$d' /etc/ssh/sshd_config 2>/dev/null
    sed -i '/Include \/etc\/ssh\/sshd_config.d/d' /etc/ssh/sshd_config 2>/dev/null
    rm -f /etc/ssh/sshd_config.d/elite-x-*.conf /etc/ssh/sshd_config.d/zz-elite-x-*.conf
    sed -i '/elite-x/d' /etc/pam.d/sshd 2>/dev/null
    rm -f /etc/sysctl.d/99-elite-x-vpn.conf /etc/security/limits.d/elite-x.conf \
          /etc/systemd/system.conf.d/elite-x-limits.conf /etc/profile.d/elite-x-dashboard.sh
    systemctl daemon-reload
}

# ---------- 3. Base packages ----------
install_deps(){
    echo -e "${YELLOW}Installing packages...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq >/dev/null 2>&1
    apt-get install -y -qq curl jq iptables bc dnsutils iproute2 gcc libc6-dev python3 >/dev/null 2>&1
}

# ---------- 4. Swap + kernel + journal limits ----------
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

# ---------- 5. OpenSSH config ----------
setup_ssh(){
    grep -q '^Include /etc/ssh/sshd_config.d' /etc/ssh/sshd_config || \
        sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' /etc/ssh/sshd_config
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
    sshd -t && (systemctl restart ssh 2>/dev/null || systemctl restart sshd)
}

# ---------- 6. DNSTT on port 53 directly ----------
setup_dnstt(){
    echo -e "${YELLOW}Installing DNSTT...${NC}"
    curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null || \
    curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server
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
Description=ELITE-X DNSTT Server (lite)
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/dnstt-server -udp :53 -mtu ${MTU} -privkey-file /etc/dnstt/server.key ${TDOMAIN} 127.0.0.1:22
Restart=always
RestartSec=3
LimitNOFILE=65535
CPUQuota=40%
MemoryMax=80M
[Install]
WantedBy=multi-user.target
EOF
}

# ---------- 7. Helper scripts ----------
write_scripts(){
    # ---- lock (quota | daily | manual) ----
    cat > /usr/local/bin/elite-x-lock <<'EOF'
#!/bin/bash
u="$1"; kind="$2"; why="$3"; BW=/etc/elite-x/bandwidth; BAN=/etc/elite-x/banned
id "$u" &>/dev/null || exit 0
usermod -L "$u" 2>/dev/null
pkill -KILL -u "$u" 2>/dev/null
case "$kind" in
    quota) touch "$BW/$u.locked_quota" ;;
    daily) touch "$BW/$u.daily_locked" ;;
esac
mkdir -p "$BAN"; echo "$(date '+%F %T') LOCKED ($kind): $why" >> "$BAN/$u"
/usr/local/bin/elite-x-banner-sync >/dev/null 2>&1
EOF

    # ---- delete (expired / admin) ----
    cat > /usr/local/bin/elite-x-del <<'EOF'
#!/bin/bash
u="$1"; why="$2"; EX=/etc/elite-x; BW=$EX/bandwidth
[ -f "$EX/users/$u" ] || exit 0
today=$(date +%F)
echo "$(cat $BW/$u.usage 2>/dev/null || echo 0) $u $today" >> $EX/global_bandwidth.log
echo "$today $(cat $BW/$u.daily_usage 2>/dev/null || echo 0) $u" >> $EX/global_daily.log
mkdir -p $EX/deleted; cp "$EX/users/$u" "$EX/deleted/${u}_$(date +%Y%m%d%H%M%S)"
echo "$(date '+%F %T') DELETED ($why): $u" >> /var/log/elite-x-expire.log
pkill -KILL -u "$u" 2>/dev/null
userdel -r "$u" 2>/dev/null
rm -f "$EX/users/$u" "$EX/connections/$u" "$EX/user_messages/$u" "$EX/banned/$u" \
      "$BW/$u.usage" "$BW/$u.daily_usage" "$BW/$u.locked_quota" "$BW/$u.daily_locked"
/usr/local/bin/elite-x-banner-sync >/dev/null 2>&1
EOF

    # ---- banner sync: ONE pass, rebuilds all banners ----
    cat > /usr/local/bin/elite-x-banner-sync <<'BSEOF'
#!/bin/bash
EX=/etc/elite-x; UD=$EX/users; BW=$EX/bandwidth; CN=$EX/connections; MS=$EX/user_messages
CONF=/etc/ssh/sshd_config.d/zz-elite-x-users.conf
mkdir -p "$MS"; TMP=$(mktemp); echo "# ELITE-X per-user banners" > "$TMP"
NOW=$(date +%s)
for f in "$UD"/*; do
    [ -f "$f" ] || continue
    u=$(basename "$f")
    exp=$(awk -F': ' '/^Expire:/{print $2}' "$f")
    bwl=$(awk -F': ' '/^Bandwidth_GB:/{print $2}' "$f"); bwl=${bwl:-0}
    dl=$(awk -F': ' '/^Daily_Limit:/{print $2}' "$f");   dl=${dl:-0}
    cl=$(awk -F': ' '/^Conn_Limit:/{print $2}' "$f");    cl=${cl:-1}
    used=$(cat "$BW/$u.usage" 2>/dev/null || echo 0)
    daily=$(cat "$BW/$u.daily_usage" 2>/dev/null || echo 0)
    cc=$(cat "$CN/$u" 2>/dev/null || echo 0)
    ex_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
    rem=$(( (ex_ts - NOW) / 86400 )); [ $rem -lt 0 ] && rem=0
    if grep -q "^$u:!" /etc/shadow 2>/dev/null; then st="LOCKED"
    elif [ $rem -le 0 ]; then st="EXPIRED"
    elif [ $rem -le 3 ]; then st="EXPIRING SOON"
    else st="ACTIVE"; fi
    gb_used=$(awk -v b="$used" 'BEGIN{printf "%.2f",b/1073741824}')
    gb_day=$(awk -v b="$daily" 'BEGIN{printf "%.2f",b/1073741824}')
    bw_txt=$([ "$bwl" = 0 ] && echo Unlimited || echo "$bwl GB")
    dl_txt=$([ "$dl" = 0 ] && echo Unlimited || echo "$dl GB")
    cat > "$MS/$u" <<HTML
<span style="color:#FF0000;font-weight:bold;">═══════════════════════════════════</span>
<span style="background-color:#0B56E2;color:#FFFEFE;font-weight:bold;"> ELITE-X SLOWDNS VPN v8 </span>
<span style="color:#FAFAF7;font-weight:bold;"> USERNAME  </span>: <span style="color:#00ff00;font-weight:bold;">$u</span>
<span style="color:#DA0971;font-weight:bold;"> EXPIRE    </span>: <span style="color:#ff0000;font-weight:bold;">$exp</span>
<span style="color:#ffff00;font-weight:bold;"> REMAINING </span>: <span style="color:#00ffff;font-weight:bold;">${rem} days</span>
<span style="color:#F825B9;font-weight:bold;"> LIMIT GB  </span>: <span style="color:#00ff00;font-weight:bold;">$bw_txt</span>
<span style="color:#ffff00;font-weight:bold;"> USAGE GB  </span>: <span style="color:#ff0000;font-weight:bold;">$gb_used GB</span>
<span style="color:#0ED5F8;font-weight:bold;"> DAILY     </span>: <span style="color:#ff00ff;font-weight:bold;">$gb_day GB / $dl_txt</span>
<span style="color:#0ED5F8;font-weight:bold;"> CONNECTION</span>: <span style="color:#ff00ff;font-weight:bold;">$cc/$cl</span>
<span style="color:#ffff00;font-weight:bold;"> STATUS    </span>: <span style="color:#00ff00;font-weight:bold;">$st</span>
<span style="background-color:#D40633;color:#ffffff;font-weight:bold;display:block;text-align:center;">   Thanks for using ELITE-X VPN   </span>
HTML
    printf 'Match User %s\n    Banner %s\n' "$u" "$MS/$u" >> "$TMP"
done
for m in "$MS"/*; do [ -f "$m" ] && [ -f "$UD/$(basename "$m")" ] || rm -f "$m"; done
install -m 644 "$TMP" "$CONF"; rm -f "$TMP"
sshd -t 2>/dev/null && (systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null)
BSEOF
    chmod +x /usr/local/bin/elite-x-banner-sync

    # ---- user management CLI ----
    cat > /usr/local/bin/elite-x-user <<'EOF'
#!/bin/bash
EX=/etc/elite-x; UD=$EX/users; BW=$EX/bandwidth; CN=$EX/connections
mkdir -p "$UD" "$BW" "$CN" "$EX/deleted"
gk(){ awk -F': ' -v k="$2" '$1==k{print $2}' "$UD/$1" 2>/dev/null; }
setk(){ sed -i "s|^$2: .*|$2: $3|" "$UD/$1"; }
gb(){ awk -v b="${1:-0}" 'BEGIN{printf "%.2f",b/1073741824}'; }
ask(){ local v; read -r -p "$1 [$2]: " v; echo "${v:-$2}"; }
banner(){ /usr/local/bin/elite-x-banner-sync >/dev/null 2>&1; }

add(){
    u=$(ask "Username" ""); [ -z "$u" ] && return
    [[ "$u" =~ ^[a-zA-Z0-9_-]{3,32}$ ]] || { echo "Jina batili"; return; }
    id "$u" &>/dev/null && { echo "User yupo tayari"; return; }
    p=$(ask "Password" "$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c10)")
    d=$(ask "Siku" 30); c=$(ask "Devices" 1)
    bw=$(ask "Bandwidth GB (0=unlimited)" 0); dl=$(ask "Daily GB (0=unlimited)" 0)
    exp=$(date -d "+$d days" +%F)
    grep -qxF /bin/sh /etc/shells || echo /bin/sh >> /etc/shells
    if ! { useradd -m -s /bin/sh "$u" && echo "$u:$p" | chpasswd && chage -E "$exp" "$u"; }; then
        echo "Imeshindwa kuunda user"; return
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
    echo "----------------------------------------"
    echo "Username: $u | Password: $p"
    echo "Expire: $exp | Devices: $c | BW: $bw GB | Daily: $dl GB"
    echo "----------------------------------------"
}

list(){
    printf "%-16s %-11s %-8s %-20s %-16s %s\n" USER EXPIRE ONLINE BANDWIDTH DAILY STATUS
    for f in "$UD"/*; do
        [ -f "$f" ] || continue; u=$(basename "$f")
        cl=$(gk "$u" Conn_Limit); bwl=$(gk "$u" Bandwidth_GB); dl=$(gk "$u" Daily_Limit)
        cc=$(cat "$CN/$u" 2>/dev/null || echo 0)
        used=$(gb "$(cat "$BW/$u.usage" 2>/dev/null || echo 0)")
        day=$(gb "$(cat "$BW/$u.daily_usage" 2>/dev/null || echo 0)")
        st=""; passwd -S "$u" 2>/dev/null | grep -q ' L ' && st=LOCKED
        printf "%-16s %-11s %-8s %-20s %-16s %s\n" "$u" "$(gk "$u" Expire)" "$cc/${cl:-1}" \
            "$used/${bwl:-0}G" "$day/${dl:-0}G" "$st"
    done
    echo "(Online inasasishwa kila dakika 1)"
}

details(){
    u=$(ask "Username" ""); [ -f "$UD/$u" ] || { echo "Haipo"; return; }
    cat "$UD/$u"
    echo "Usage : $(gb "$(cat "$BW/$u.usage" 2>/dev/null || echo 0)") GB"
    echo "Daily : $(gb "$(cat "$BW/$u.daily_usage" 2>/dev/null || echo 0)") GB"
    echo "Online: $(cat "$CN/$u" 2>/dev/null || echo 0)"
}

renew(){
    u=$(ask "Username" ""); [ -f "$UD/$u" ] || { echo "Haipo"; return; }
    d=$(ask "Siku za kuongeza" 30)
    new=$(date -d "$(gk "$u" Expire) +$d days" +%F)
    setk "$u" Expire "$new"; chage -E "$new" "$u"; usermod -U "$u" 2>/dev/null
    banner; echo "Imerenewiwa hadi $new"
}
setlimit(){ u=$(ask "Username" ""); [ -f "$UD/$u" ] || return; setk "$u" Conn_Limit "$(ask 'Devices' 1)"; banner; echo ok; }
setbw(){ u=$(ask "Username" ""); [ -f "$UD/$u" ] || return; setk "$u" Bandwidth_GB "$(ask 'Bandwidth GB (0=unlimited)' 0)"; banner; echo ok; }
setdaily(){ u=$(ask "Username" ""); [ -f "$UD/$u" ] || return; setk "$u" Daily_Limit "$(ask 'Daily GB (0=unlimited)' 0)"; banner; echo ok; }
resetdata(){
    u=$(ask "Username" ""); [ -f "$UD/$u" ] || return
    echo 0 > "$BW/$u.usage"; echo 0 > "$BW/$u.daily_usage"
    rm -f "$BW/$u.locked_quota" "$BW/$u.daily_locked"; usermod -U "$u" 2>/dev/null
    banner; echo "Data imerekebishwa"
}
lock(){ u=$(ask "Username" ""); [ -f "$UD/$u" ] || return; /usr/local/bin/elite-x-lock "$u" manual "admin"; echo "Locked"; }
unlock(){
    u=$(ask "Username" ""); [ -f "$UD/$u" ] || return
    usermod -U "$u" 2>/dev/null; rm -f "$BW/$u.locked_quota" "$BW/$u.daily_locked"
    banner; echo "Unlocked"
}
del(){ u=$(ask "Username" ""); [ -f "$UD/$u" ] || return; /usr/local/bin/elite-x-del "$u" "admin"; echo "Deleted"; }

case "$1" in
    add) add;; list) list;; details) details;; renew) renew;;
    setlimit) setlimit;; setbw) setbw;; setdaily) setdaily;; resetdata) resetdata;;
    lock) lock;; unlock) unlock;; del) del;;
    *) echo "Usage: elite-x-user {add|list|details|renew|setlimit|setbw|setdaily|resetdata|lock|unlock|del}";;
esac
EOF

    # ---- main menu ----
    cat > /usr/local/bin/elite-x <<'EOF'
#!/bin/bash
EX=/etc/elite-x
G='\033[0;32m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'
ask(){ local v; read -r -p "$1: " v; echo "$v"; }
show(){
    clear
    IP=$(cat $EX/cached_ip 2>/dev/null); NS=$(cat $EX/subdomain 2>/dev/null)
    U=$(ls $EX/users 2>/dev/null | wc -l)
    ON=$(cat $EX/connections/* 2>/dev/null | awk '{s+=$1}END{print s+0}')
    echo -e "${C}ELITE-X LITE v8${N}  IP:$IP  NS:$NS"
    echo -e "RAM: $(free -m | awk '/Mem:/{print $3"/"$2"MB"}')  Load: $(cut -d' ' -f1-3 /proc/loadavg)  Users:$U  Online:$ON"
    for s in dnstt-elite-x elite-x-monitor ssh elite-x-panel; do
        systemctl is-active -q $s && echo -ne "[$s ${G}OK${N}] " || echo -ne "[$s ${R}DOWN${N}] "
    done; echo; echo
    echo " [1] Create user        [2] List users       [3] User details"
    echo " [4] Renew user         [5] Set devices      [6] Set bandwidth"
    echo " [7] Set daily limit    [8] Reset data       [9] Lock user"
    echo " [10] Unlock user       [11] Delete user"
    echo " [12] Change NS         [13] Change MTU      [14] Restart services"
    echo " [15] Refresh banners   [16] Panel info      [0] Exit"
    echo
}
set_ns(){
    ns=$(ask "New NS"); [[ "$ns" =~ ^[a-zA-Z0-9.-]+$ ]] || { echo "Batili"; return; }
    echo "$ns" > $EX/subdomain; echo "$ns" > $EX/nameserver.conf
    sed -i -E "s|(-privkey-file [^ ]+ )[^ ]+( 127\.0\.0\.1:22)|\1${ns}\2|" /etc/systemd/system/dnstt-elite-x.service
    systemctl daemon-reload; systemctl restart dnstt-elite-x; echo "NS imebadilishwa"
}
set_mtu(){
    m=$(ask "MTU (100-1800)"); [[ "$m" =~ ^[0-9]+$ ]] && [ "$m" -ge 100 ] && [ "$m" -le 1800 ] || { echo "Batili"; return; }
    echo "$m" > $EX/mtu; sed -i -E "s|-mtu [0-9]+|-mtu $m|" /etc/systemd/system/dnstt-elite-x.service
    systemctl daemon-reload; systemctl restart dnstt-elite-x; echo "MTU: $m"
}
while true; do
    show
    read -r -p "Chagua: " ch
    case $ch in
        1) elite-x-user add ;;   2) elite-x-user list ;;   3) elite-x-user details ;;
        4) elite-x-user renew ;; 5) elite-x-user setlimit ;; 6) elite-x-user setbw ;;
        7) elite-x-user setdaily ;; 8) elite-x-user resetdata ;; 9) elite-x-user lock ;;
        10) elite-x-user unlock ;; 11) elite-x-user del ;;
        12) set_ns ;; 13) set_mtu ;;
        14) systemctl restart dnstt-elite-x elite-x-monitor sshd 2>/dev/null; echo "Restarted" ;;
        15) /usr/local/bin/elite-x-banner-sync; echo "Banners refreshed" ;;
        16) grep -E '^PANEL_(USER|PASS_PLAIN|SECRET)=' $EX/panel.conf | tr -d '"'
            echo "URL: http://$(cat $EX/cached_ip 2>/dev/null):44380/$(grep '^PANEL_SECRET=' $EX/panel.conf | cut -d= -f2 | tr -d '"')" ;;
        0) exit 0 ;;
        *) echo "Batili" ;;
    esac
    read -r -p "Enter..." _
done
EOF
    chmod +x /usr/local/bin/elite-x
}

# ---------- 8. Monitor (single C daemon) ----------
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
#define UD   EX"/users"
#define BW   EX"/bandwidth"
#define PIDT BW"/pidtrack"
#define CN   EX"/connections"
#define GB   1073741824.0
#define MAXS 2048
#define BIN  "/usr/local/bin/"

typedef struct { unsigned uid; int sessions; long long delta; } sess_t;
static sess_t S[MAXS]; static int NS;
static volatile sig_atomic_t running = 1;
static void onsig(int s){ (void)s; running = 0; }

static int rd_str(const char *p, char *o, size_t n){
    FILE *f = fopen(p, "r"); o[0] = 0; if (!f) return 0;
    if (fgets(o, (int)n, f)) o[strcspn(o, "\r\n")] = 0;
    fclose(f); return 1;
}
static long long rd_ll(const char *p){ char b[64]; if (!rd_str(p, b, 64)) return 0; return atoll(b); }
static void wr_ll(const char *p, long long v){ FILE *f = fopen(p, "w"); if (f){ fprintf(f, "%lld\n", v); fclose(f); } }
static void run(const char *c){ int r = system(c); (void)r; }

static int find_sess(unsigned uid){
    for (int i = 0; i < NS; i++) if (S[i].uid == uid) return i;
    if (NS >= MAXS) return -1;
    S[NS].uid = uid; S[NS].sessions = 0; S[NS].delta = 0; return NS++;
}
static long long io_bytes(int pid){
    char p[64], l[256]; snprintf(p, sizeof p, "/proc/%d/io", pid);
    FILE *f = fopen(p, "r"); if (!f) return -1;
    long long r = 0, w = 0;
    while (fgets(l, sizeof l, f)){
        if (!strncmp(l, "rchar:", 6)) r = atoll(l + 6);
        else if (!strncmp(l, "wchar:", 6)) w = atoll(l + 6);
    }
    fclose(f); return r + w;
}
static void scan_sessions(void){
    NS = 0;
    DIR *d = opendir("/proc"); if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))){
        if (!isdigit((unsigned char)e->d_name[0])) continue;
        int pid = atoi(e->d_name); char p[64], b[512];
        snprintf(p, sizeof p, "/proc/%d/comm", pid);
        if (!rd_str(p, b, sizeof b) || strcmp(b, "sshd")) continue;
        snprintf(p, sizeof p, "/proc/%d/stat", pid);
        FILE *f = fopen(p, "r"); if (!f) continue;
        int ppid = 0;
        if (fgets(b, sizeof b, f)){ char *rp = strrchr(b, ')'); if (rp) sscanf(rp + 2, "%*c %d", &ppid); }
        fclose(f);
        if (ppid == 1) continue;                      /* listener daemon, not a session */
        snprintf(p, sizeof p, "/proc/%d/status", pid);
        f = fopen(p, "r"); if (!f) continue;
        unsigned uid = 0; int got = 0;
        while (fgets(b, sizeof b, f)) if (!strncmp(b, "Uid:", 4)){ uid = (unsigned)strtoul(b + 4, NULL, 10); got = 1; break; }
        fclose(f);
        if (!got || uid == 0) continue;
        int i = find_sess(uid); if (i < 0) continue;
        S[i].sessions++;
        long long cur = io_bytes(pid); if (cur < 0) continue;
        char pf[256]; snprintf(pf, sizeof pf, PIDT "/%d.last", pid);
        long long last = rd_ll(pf);
        if (last > 0) S[i].delta += (cur >= last) ? (cur - last) : cur;
        wr_ll(pf, cur);
    }
    closedir(d);
}
static void clean_pidtrack(void){
    DIR *d = opendir(PIDT); if (!d) return; struct dirent *e;
    while ((e = readdir(d))){
        char *dot = strstr(e->d_name, ".last"); if (!dot) continue;
        char p[320]; snprintf(p, sizeof p, "/proc/%.*s", (int)(dot - e->d_name), e->d_name);
        if (access(p, F_OK) != 0){ char q[384]; snprintf(q, sizeof q, PIDT "/%s", e->d_name); unlink(q); }
    }
    closedir(d);
}
static void daily_reset(void){
    char today[16]; time_t t = time(NULL);
    strftime(today, sizeof today, "%Y-%m-%d", localtime(&t));
    char saved[32]; rd_str(BW "/current_date", saved, sizeof saved);
    if (!strcmp(saved, today)) return;
    DIR *d = opendir(BW);
    if (d){
        struct dirent *e;
        while ((e = readdir(d))){
            char *n = e->d_name; size_t L = strlen(n);
            if (L > 12 && !strcmp(n + L - 12, ".daily_usage")){
                char p[300]; snprintf(p, sizeof p, BW "/%s", n); wr_ll(p, 0);
            } else if (L > 13 && !strcmp(n + L - 13, ".daily_locked")){
                char u[128], c[512]; snprintf(u, sizeof u, "%.*s", (int)(L - 13), n);
                snprintf(c, sizeof c, "usermod -U '%s' 2>/dev/null; rm -f '%s/%s'", u, BW, n); run(c);
            }
        }
        closedir(d);
    }
    FILE *f = fopen(BW "/current_date", "w"); if (f){ fprintf(f, "%s\n", today); fclose(f); }
    run(BIN "elite-x-banner-sync >/dev/null 2>&1");
}
static void act_lock(const char *u, const char *kind, const char *why){
    char c[512]; snprintf(c, sizeof c, BIN "elite-x-lock '%s' '%s' '%s'", u, kind, why); run(c);
}
static void act_del(const char *u, const char *why){
    char c[512]; snprintf(c, sizeof c, BIN "elite-x-del '%s' '%s'", u, why); run(c);
}
static int autoban_on(void){ char b[16]; if (!rd_str(EX "/autoban_enabled", b, sizeof b)) return 0; return atoi(b) == 1; }

static void cycle(void){
    daily_reset();
    scan_sessions();
    clean_pidtrack();
    int ab = autoban_on();
    time_t now = time(NULL);
    DIR *d = opendir(UD); if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))){
        if (e->d_name[0] == '.') continue;
        char path[320], u[64], exp[32] = {0}, line[256];
        snprintf(u, sizeof u, "%s", e->d_name);
        snprintf(path, sizeof path, UD "/%s", u);
        FILE *f = fopen(path, "r"); if (!f) continue;
        double bwl = 0, dl = 0; int cl = 1;
        while (fgets(line, sizeof line, f)){
            if (!strncmp(line, "Expire:", 7)) sscanf(line + 7, " %31s", exp);
            else if (!strncmp(line, "Bandwidth_GB:", 13)) bwl = atof(line + 13);
            else if (!strncmp(line, "Daily_Limit:", 12)) dl = atof(line + 12);
            else if (!strncmp(line, "Conn_Limit:", 11)) cl = atoi(line + 11);
        }
        fclose(f);

        if (exp[0]){
            struct tm tm = {0};
            if (strptime(exp, "%Y-%m-%d", &tm)){
                time_t et = mktime(&tm);
                if (now > et + 86400){ act_del(u, "expired"); continue; }
            }
        }
        struct passwd *pw = getpwnam(u); if (!pw) continue;
        int si = -1;
        for (int i = 0; i < NS; i++) if (S[i].uid == (unsigned)pw->pw_uid){ si = i; break; }
        int cc = si >= 0 ? S[si].sessions : 0;
        long long delta = si >= 0 ? S[si].delta : 0;

        char pu[300], pd[300], pc[300], m[300];
        snprintf(pu, sizeof pu, BW "/%s.usage", u);
        snprintf(pd, sizeof pd, BW "/%s.daily_usage", u);
        snprintf(pc, sizeof pc, CN "/%s", u);
        long long used  = rd_ll(pu) + delta;
        long long daily = rd_ll(pd) + delta;
        wr_ll(pu, used); wr_ll(pd, daily); wr_ll(pc, cc);

        if (bwl > 0 && (double)used >= bwl * GB){
            snprintf(m, sizeof m, BW "/%s.locked_quota", u);
            if (access(m, F_OK) != 0) act_lock(u, "quota", "Bandwidth quota reached");
        }
        if (dl > 0 && (double)daily >= dl * GB){
            snprintf(m, sizeof m, BW "/%s.daily_locked", u);
            if (access(m, F_OK) != 0) act_lock(u, "daily", "Daily limit reached");
        }
        if (ab && cl > 0 && cc > cl){
            snprintf(m, sizeof m, BW "/%s.conn_locked", u);
            if (access(m, F_OK) != 0){ act_lock(u, "conn", "Connection limit exceeded"); FILE *g = fopen(m, "w"); if (g) fclose(g); }
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
        if (++tick % 30 == 0) run(BIN "elite-x-banner-sync >/dev/null 2>&1");
        for (int i = 0; i < 60 && running; i++) sleep(1);
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

# ---------- 9. Panel ----------
install_panel(){
    echo -e "${YELLOW}Installing web panel...${NC}"
    mkdir -p $EX/panel
    curl -fsSL --connect-timeout 10 --max-time 30 "$RAW/panel.py"   -o $EX/panel/panel.py   || { echo -e "${RED}panel.py download failed${NC}"; return; }
    curl -fsSL --connect-timeout 10 --max-time 30 "$RAW/panel.html" -o $EX/panel/panel.html || { echo -e "${RED}panel.html download failed${NC}"; return; }
    chmod 644 $EX/panel/panel.html; chmod 755 $EX/panel/panel.py
    cat > /etc/systemd/system/elite-x-panel.service <<'EOF'
[Unit]
Description=ELITE-X Web Panel (lite)
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
}

# ---------- 10. Units + enable ----------
install_units(){
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
Description=ELITE-X cache public IP once at boot
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/bin/sh -c 'curl -4 -s --max-time 5 icanhazip.com > /etc/elite-x/cached_ip'
[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable --now dnstt-elite-x elite-x-monitor elite-x-ipcache >/dev/null 2>&1
    systemctl enable --now elite-x-panel >/dev/null 2>&1
}

# ---------- MAIN ----------
cleanup_old
install_deps
mkdir -p $EX/{users,bandwidth/pidtrack,connections,banned,deleted,user_messages,panel,resellers,reseller_requests}
mkdir -p /var/log/elite-x
echo "$TDOMAIN" > $EX/subdomain
echo "$TDOMAIN" > $EX/nameserver.conf
echo "$MTU"     > $EX/mtu
echo "$STATIC_PUBLIC_KEY"  > $EX/public_key
echo "$STATIC_PRIVATE_KEY" > $EX/private_key
[ -f $EX/autoban_enabled ] || echo 0 > $EX/autoban_enabled
[ -f $EX/install_date ]    || date '+%Y-%m-%d %H:%M:%S' > $EX/install_date
setup_system
setup_ssh
setup_dnstt
write_scripts
build_monitor
install_panel
install_units
/usr/local/bin/elite-x-banner-sync
curl -4 -s --max-time 5 icanhazip.com > $EX/cached_ip 2>/dev/null

clear
echo -e "${GREEN}ELITE-X LITE v8 imewekwa${NC}"
echo "NS      : $TDOMAIN"
echo "PUBKEY  : $STATIC_PUBLIC_KEY"
echo "Menu    : elite-x"
echo "Panel   : http://$(cat $EX/cached_ip 2>/dev/null):44380"
systemctl is-active -q dnstt-elite-x   && echo -e "${GREEN}✅ DNSTT${NC}"   || echo -e "${RED}❌ DNSTT${NC}"
systemctl is-active -q elite-x-monitor && echo -e "${GREEN}✅ Monitor${NC}" || echo -e "${RED}❌ Monitor${NC}"
systemctl is-active -q ssh || systemctl is-active -q sshd && echo -e "${GREEN}✅ SSH${NC}" || echo -e "${RED}❌ SSH${NC}"