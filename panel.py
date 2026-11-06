#!/usr/bin/env python3
"""
ELITE-X Web Panel v8 - Reseller Auto-Login + Package System
"""

import os
import sys
import json
import time
import subprocess
import secrets
import hashlib
import threading
import re
import glob
import shutil
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http import cookies
from urllib.parse import urlparse, parse_qs
from datetime import datetime, timedelta
from collections import defaultdict
import traceback

# ================================================================
# CONSTANTS
# ================================================================
BASE_DIR = "/etc/elite-x"
USER_DB = f"{BASE_DIR}/users"
BANDWIDTH_DIR = f"{BASE_DIR}/bandwidth"
CONN_DB = f"{BASE_DIR}/connections"
BANNED_DB = f"{BASE_DIR}/banned"
DELETED_DB = f"{BASE_DIR}/deleted"
EXPIRED_DB = f"{BASE_DIR}/expired"
RESELLER_DB = f"{BASE_DIR}/resellers"
RESELLER_REQUESTS_DB = f"{BASE_DIR}/reseller_requests"
USER_MSG_DIR = f"{BASE_DIR}/user_messages"
NAMESERVER_FILE = f"{BASE_DIR}/nameserver.conf"
PANEL_CONFIG = f"{BASE_DIR}/panel.conf"
PANEL_HTML = f"{BASE_DIR}/panel/index.html"
PUBLIC_KEY_FILE = f"{BASE_DIR}/public_key"
PRIVATE_KEY_FILE = f"{BASE_DIR}/private_key"
SUBDOMAIN_FILE = f"{BASE_DIR}/subdomain"
MTU_FILE = f"{BASE_DIR}/mtu"
INSTALL_DATE_FILE = f"{BASE_DIR}/install_date"
GLOBAL_BW_LOG = f"{BASE_DIR}/global_bandwidth.log"
GLOBAL_DAILY_LOG = f"{BASE_DIR}/global_daily.log"
PIDTRACK_DIR = f"{BANDWIDTH_DIR}/pidtrack"
JUNK_DIR = f"{BASE_DIR}/junk"
LOGS_DIR = "/var/log/elite-x"
PACKAGES_FILE = f"{BASE_DIR}/packages.json"
PACKAGE_REQUESTS_DIR = f"{BASE_DIR}/package_requests"
SESSION_FILE = f"{BASE_DIR}/sessions.json"
PANEL_PORT = 44380
USER_ACTIVITY_DIR = f"{BASE_DIR}/user_activity"
RESELLER_USER_REQUESTS = f"{BASE_DIR}/reseller_user_requests"
VIP_PACKAGE_ID = "vip"
VIP_PRICE = 20000

# ================================================================
# SESSIONS
# ================================================================
sessions = {}

def load_sessions():
    global sessions
    try:
        if os.path.exists(SESSION_FILE):
            with open(SESSION_FILE, "r") as f:
                sessions = json.load(f)
    except Exception:
        sessions = {}

def save_sessions():
    try:
        os.makedirs(os.path.dirname(SESSION_FILE), exist_ok=True)
        with open(SESSION_FILE, "w") as f:
            json.dump(sessions, f)
    except Exception:
        pass

load_sessions()

# ================================================================
# UTILITY - Improved error handling
# ================================================================
def run_cmd(cmd, ignore_errors=False, timeout=15):
    try:
        if isinstance(cmd, str):
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        else:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if not ignore_errors and res.returncode != 0:
            cmd_str = str(cmd)
            # Ignore common non-critical errors
            if any(x in cmd_str for x in ['sshd', 'id', 'rust', 'chage', 'passwd', 'systemctl']):
                pass
            else:
                print(f"CMD warning: {cmd} -> {res.stderr}", file=sys.stderr)
        return res.returncode, res.stdout.strip(), res.stderr.strip()
    except Exception as e:
        return -1, "", str(e)

def read_file(path, default=""):
    try:
        if os.path.exists(path):
            with open(path, "r") as f:
                return f.read().strip()
    except Exception:
        pass
    return default

def write_file(path, content):
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as f:
            f.write(content)
        return True
    except Exception:
        return False

def read_file_int(path, default=0):
    try:
        if os.path.exists(path):
            with open(path, "r") as f:
                return int(f.read().strip())
    except Exception:
        pass
    return default

def generate_password(length=10):
    chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    return "".join(secrets.choice(chars) for _ in range(length))

def calculate_expire_date(days):
    return (datetime.now() + timedelta(days=days)).strftime("%Y-%m-%d")

def get_server_ip():
    for cmd in ["curl -s -4 --max-time 3 icanhazip.com", "curl -s -4 --max-time 3 ifconfig.me"]:
        code, ip, _ = run_cmd(cmd)
        if code == 0 and ip:
            return ip
    return "Unknown"

def get_public_key():
    return read_file(PUBLIC_KEY_FILE, "")

def get_nameserver():
    ns = read_file(NAMESERVER_FILE, "")
    if not ns:
        ns = read_file(SUBDOMAIN_FILE, "")
    return ns

def get_services_status():
    services = {
        "dnstt": False,
        "edns": False,
        "udp": False,
        "slowdns": False,
        "ssh": False,
        "bandwidth": False
    }
    service_map = {
        "dnstt-elite-x": "dnstt",
        "dnstt-elite-x-proxy": "edns",
        "elite-x-udp-turbo": "udp",
        "elite-x-slowdns-relay": "slowdns",
        "ssh": "ssh",
        "elite-x-bandwidth": "bandwidth"
    }
    for s, key in service_map.items():
        try:
            code, _, _ = run_cmd(["systemctl", "is-active", s])
            services[key] = (code == 0)
        except:
            services[key] = False
    return services

def get_chart_data(username):
    data = []
    daily_log = f"{BANDWIDTH_DIR}/{username}.daily_usage"
    if os.path.exists(daily_log):
        try:
            with open(daily_log, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) >= 2:
                        data.append(float(parts[1]))
        except:
            pass
    while len(data) < 7:
        data.append(0)
    return data[-7:]

def get_reseller_commission(username):
    total = 0
    users = get_all_users()
    for u in users:
        if u.get("Owner", "") == username:
            total += 500
    return total

def log_user_activity(username, action, ip="unknown"):
    os.makedirs(USER_ACTIVITY_DIR, exist_ok=True)
    with open(f"{USER_ACTIVITY_DIR}/{username}", "a") as f:
        f.write(f"{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}|{action}|{ip}\n")

def get_user_activity(username, limit=20):
    activity = []
    log_file = f"{USER_ACTIVITY_DIR}/{username}"
    if os.path.exists(log_file):
        with open(log_file, "r") as f:
            lines = f.readlines()[-limit:]
        for line in lines:
            parts = line.strip().split("|")
            if len(parts) >= 3:
                activity.append({"time": parts[0], "action": parts[1], "ip": parts[2]})
    return activity

def get_all_activity(limit=50):
    all_activity = []
    if not os.path.exists(USER_ACTIVITY_DIR):
        return all_activity
    for fname in os.listdir(USER_ACTIVITY_DIR):
        fpath = f"{USER_ACTIVITY_DIR}/{fname}"
        if os.path.isfile(fpath):
            with open(fpath, "r") as f:
                for line in f:
                    parts = line.strip().split("|")
                    if len(parts) >= 3:
                        all_activity.append({"user": fname, "time": parts[0], "action": parts[1], "ip": parts[2]})
    all_activity.sort(key=lambda x: x["time"], reverse=True)
    return all_activity[:limit]

# ================================================================
# USER MANAGEMENT
# ================================================================
def get_user_info(username):
    user_file = f"{USER_DB}/{username}"
    if not os.path.exists(user_file):
        return None
    info = {}
    with open(user_file, "r") as f:
        for line in f:
            if ":" in line:
                k, v = line.split(":", 1)
                info[k.strip()] = v.strip()
    return info

def get_all_users():
    users = []
    if not os.path.exists(USER_DB):
        return users
    for f in os.listdir(USER_DB):
        path = f"{USER_DB}/{f}"
        if os.path.isfile(path):
            info = get_user_info(f)
            if info:
                info["username"] = f
                users.append(info)
    return users

def get_users_by_reseller(reseller):
    users = []
    if not os.path.exists(USER_DB):
        return users
    for f in os.listdir(USER_DB):
        path = f"{USER_DB}/{f}"
        if os.path.isfile(path):
            info = get_user_info(f)
            if info and info.get("Owner", "") == reseller:
                info["username"] = f
                users.append(info)
    return users

def get_user_bandwidth(username):
    usage_file = f"{BANDWIDTH_DIR}/{username}.usage"
    return read_file_int(usage_file, 0)

def get_user_daily_bandwidth(username):
    daily_file = f"{BANDWIDTH_DIR}/{username}.daily_usage"
    return read_file_int(daily_file, 0)

def get_user_connections(username):
    count = 0
    try:
        code, uid, _ = run_cmd(["id", "-u", username])
        if code != 0 or not uid or not uid.isdigit():
            return 0
        for pid_dir in glob.glob("/proc/[0-9]*/"):
            try:
                with open(f"{pid_dir}comm", "r") as f:
                    comm = f.read().strip()
                if comm not in ["sshd", "dropbear"]:
                    continue
                with open(f"{pid_dir}status", "r") as f:
                    content = f.read()
                    m = re.search(r"^Uid:\s*(\d+)", content, re.MULTILINE)
                    if not m or m.group(1) != uid:
                        continue
                with open(f"{pid_dir}stat", "r") as f:
                    parts = f.read().split()
                    if len(parts) > 3 and parts[3] == "1":
                        continue
                count += 1
            except Exception:
                continue
    except Exception:
        pass
    return count

def is_user_locked(username):
    code, out, _ = run_cmd(["passwd", "-S", username])
    if code == 0 and len(out.split()) >= 2:
        return out.split()[1] == "L"
    return False

def is_user_expired(info):
    expire = info.get("Expire", "")
    if not expire or expire == "Never":
        return False
    try:
        exp_date = datetime.strptime(expire, "%Y-%m-%d")
        return exp_date < datetime.now()
    except ValueError:
        return False

def user_exists_system(username):
    code, _, _ = run_cmd(["id", username])
    return code == 0

def create_system_user(username, password, expire_date, shell="/bin/sh"):
    run_cmd(["useradd", "-m", "-s", shell, username])
    run_cmd(f"echo '{username}:{password}' | chpasswd")
    run_cmd(["usermod", "-U", username])
    run_cmd(["chage", "-E", expire_date, username])
    run_cmd(["passwd", "-u", username], ignore_errors=True)
    return True

def delete_system_user(username):
    run_cmd(["pkill", "-u", username], ignore_errors=True)
    run_cmd(["killall", "-u", username, "-9"], ignore_errors=True)
    time.sleep(0.5)
    run_cmd(["userdel", "-rf", username], ignore_errors=True)
    return True

def save_user_info(username, info):
    os.makedirs(USER_DB, exist_ok=True)
    with open(f"{USER_DB}/{username}", "w") as f:
        for k, v in info.items():
            f.write(f"{k}: {v}\n")

def create_user(username, password, days, conn_limit, bandwidth_gb=0, daily_limit_gb=0, speed_limit_mbps=0, owner="admin", package_name="", package_price=0, is_vip=False):
    if not re.match(r'^[a-zA-Z0-9_\-]{3,32}$', username):
        raise ValueError("Invalid username (3-32 chars, alphanumeric, underscore, hyphen)")
    
    if os.path.exists(f"{USER_DB}/{username}"):
        raise ValueError("User already exists in database")
    
    if user_exists_system(username):
        raise ValueError("System user already exists")
    
    expire_date = calculate_expire_date(days)
    create_system_user(username, password, expire_date)
    
    info = {
        "Username": username,
        "Password": password,
        "Expire": expire_date,
        "Conn_Limit": str(conn_limit),
        "Bandwidth_GB": str(bandwidth_gb),
        "Daily_Limit": str(daily_limit_gb),
        "Speed_Limit": str(speed_limit_mbps),
        "Owner": owner,
        "Created": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "Package": package_name,
        "Package_Price": str(package_price),
        "Purchase_Date": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "VIP": "1" if is_vip else "0"
    }
    save_user_info(username, info)
    
    os.makedirs(BANDWIDTH_DIR, exist_ok=True)
    write_file(f"{BANDWIDTH_DIR}/{username}.usage", "0")
    write_file(f"{BANDWIDTH_DIR}/{username}.daily_usage", "0")
    write_file(f"{CONN_DB}/{username}", "0|")
    
    force_user_message(username)
    log_user_activity(username, f"Created by {owner}")
    return info

def update_user(username, data):
    info = get_user_info(username)
    if not info:
        raise ValueError("User not found")
    
    if "password" in data and data["password"]:
        run_cmd(f"echo '{username}:{data['password']}' | chpasswd")
        info["Password"] = data["password"]
    
    if "bandwidth_gb" in data:
        info["Bandwidth_GB"] = str(data["bandwidth_gb"])
    if "daily_limit_gb" in data:
        info["Daily_Limit"] = str(data["daily_limit_gb"])
    if "conn_limit" in data:
        info["Conn_Limit"] = str(data["conn_limit"])
    if "days" in data and data["days"] > 0:
        current = info.get("Expire", datetime.now().strftime("%Y-%m-%d"))
        try:
            exp_date = datetime.strptime(current, "%Y-%m-%d")
        except:
            exp_date = datetime.now()
        new_expire = (exp_date + timedelta(days=data["days"])).strftime("%Y-%m-%d")
        info["Expire"] = new_expire
        run_cmd(["chage", "-E", new_expire, username])
    
    save_user_info(username, info)
    force_user_message(username)
    return info

def delete_user(username):
    usage = get_user_bandwidth(username)
    daily = get_user_daily_bandwidth(username)
    today = datetime.now().strftime("%Y-%m-%d")
    
    with open(GLOBAL_BW_LOG, "a") as f:
        f.write(f"{usage} {username} {today}\n")
    with open(GLOBAL_DAILY_LOG, "a") as f:
        f.write(f"{today} {daily} {username}\n")
    
    delete_system_user(username)
    
    for f in [f"{USER_DB}/{username}", f"{CONN_DB}/{username}", 
              f"{BANNED_DB}/{username}", f"{USER_MSG_DIR}/{username}",
              f"{USER_ACTIVITY_DIR}/{username}"]:
        if os.path.exists(f):
            os.remove(f)
    
    for f in [f"{BANDWIDTH_DIR}/{username}.usage", f"{BANDWIDTH_DIR}/{username}.daily_usage",
              f"{BANDWIDTH_DIR}/{username}.daily_locked"]:
        if os.path.exists(f):
            os.remove(f)
    
    for f in glob.glob(f"{PIDTRACK_DIR}/{username}__*.last"):
        try:
            os.remove(f)
        except:
            pass
    
    return True

def renew_user(username, days):
    info = get_user_info(username)
    if not info:
        raise ValueError("User not found")
    
    current_expire = info.get("Expire", datetime.now().strftime("%Y-%m-%d"))
    try:
        exp_date = datetime.strptime(current_expire, "%Y-%m-%d")
    except ValueError:
        exp_date = datetime.now()
    
    new_expire = (exp_date + timedelta(days=days)).strftime("%Y-%m-%d")
    info["Expire"] = new_expire
    save_user_info(username, info)
    run_cmd(["chage", "-E", new_expire, username])
    run_cmd(["usermod", "-U", username])
    force_user_message(username)
    log_user_activity(username, f"Renewed +{days} days")
    return new_expire

def lock_user(username):
    run_cmd(["usermod", "-L", username])
    run_cmd(["pkill", "-u", username], ignore_errors=True)
    with open(f"{BANNED_DB}/{username}", "a") as f:
        f.write(f"{datetime.now()} - LOCKED\n")
    force_user_message(username)
    log_user_activity(username, "Locked")
    return True

def unlock_user(username):
    run_cmd(["usermod", "-U", username])
    for f in [f"{BANDWIDTH_DIR}/{username}.daily_locked"]:
        if os.path.exists(f):
            os.remove(f)
    with open(f"{BANNED_DB}/{username}", "a") as f:
        f.write(f"{datetime.now()} - UNLOCKED\n")
    force_user_message(username)
    log_user_activity(username, "Unlocked")
    return True

def force_user_message(username):
    info = get_user_info(username)
    if not info:
        return
    
    os.makedirs(USER_MSG_DIR, exist_ok=True)
    msg_file = f"{USER_MSG_DIR}/{username}"
    
    expire_date = info.get("Expire", "N/A")
    bandwidth_gb = float(info.get("Bandwidth_GB", 0))
    conn_limit = int(info.get("Conn_Limit", 1))
    daily_limit_gb = float(info.get("Daily_Limit", 0))
    speed_limit = int(info.get("Speed_Limit", 0))
    is_vip = info.get("VIP", "0") == "1"
    
    usage_bytes = get_user_bandwidth(username)
    usage_gb = usage_bytes / 1073741824 if usage_bytes else 0
    daily_bytes = get_user_daily_bandwidth(username)
    daily_gb = daily_bytes / 1073741824 if daily_bytes else 0
    conn_count = get_user_connections(username)
    
    try:
        exp_ts = datetime.strptime(expire_date, "%Y-%m-%d")
        now = datetime.now()
        remaining = (exp_ts - now).days
        if remaining < 0:
            remaining = 0
    except ValueError:
        remaining = 0
    
    if remaining <= 0:
        status_icon = "⛔"
        status_text = "EXPIRED"
    elif remaining <= 3:
        status_icon = "⚠️"
        status_text = "EXPIRING SOON"
    else:
        status_icon = "🟢"
        status_text = "ACTIVE"
    
    bw_display = "Unlimited" if bandwidth_gb == 0 else f"{bandwidth_gb} GB"
    speed_display = "Unlimited" if speed_limit == 0 else f"{speed_limit} Mbps"
    daily_display = "Unlimited" if daily_limit_gb == 0 else f"{daily_limit_gb} GB"
    vip_display = "⭐ VIP" if is_vip else "Standard"
    
    html = f"""<span style="color: #FF0000; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #ffff00; font-weight: bold;">▌</span><span style="color: #FFFEFE; font-weight: bold;"><span style="background-color: #0B56E2;">     ELITE-X SLOWDNS VPN v8      </span></span><span style="color: #ffff00; font-weight: bold;">▐</span>
<span style="color: #FF0000; font-weight: bold;">═══════════════════════════════════</span>
<span style="color: #FAFAF7; font-weight: bold;"> USERNAME  </span>: <span style="color: #00ff00; font-weight: bold;">{username}</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #DA0971; font-weight: bold;"> EXPIRE    </span>: <span style="color: #ff0000; font-weight: bold;">{expire_date}</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> REMAINING </span>: <span style="color: #00ffff; font-weight: bold;">{remaining}d left</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #F825B9; font-weight: bold;"> LIMIT GB  </span>: <span style="color: #00ff00; font-weight: bold;">{bw_display}</span>
<span style="color: #ffff00; font-weight: bold;"> USAGE GB  </span>: <span style="color: #ff0000; font-weight: bold;">{usage_gb:.2f} GB</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #0ED5F8; font-weight: bold;"> DAILY     </span>: <span style="color: #ff00ff; font-weight: bold;">{daily_gb:.2f} GB / {daily_display}</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #0ED5F8; font-weight: bold;"> SPEED     </span>: <span style="color: #ff00ff; font-weight: bold;">{speed_display}</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #0ED5F8; font-weight: bold;"> CONNECTION</span>: <span style="color: #ff00ff; font-weight: bold;">{conn_count}/{conn_limit}</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> PACKAGE   </span>: <span style="color: #00ff00; font-weight: bold;">{vip_display}</span>
<span style="color: #0000ff; font-weight: bold;">───────────────────────────────────</span>
<span style="color: #ffff00; font-weight: bold;"> STATUS    </span>: <span style="color: #00ff00; font-weight: bold;">{status_icon} {status_text}</span>
<span style="color: #52F805; font-weight: bold;">═══════════════════════════════════</span>
<span style="background-color: #D40633; color: #ffffff; font-weight: bold; display: block; text-align: center;">   Thanks for using ELITE-X VPN    </span>
<span style="color: #0CF833; font-weight: bold;">═══════════════════════════════════</span>"""
    
    with open(msg_file, "w") as f:
        f.write(html)
    
    update_ssh_banner(username, msg_file)

def update_ssh_banner(username, msg_file):
    ssh_conf = "/etc/ssh/sshd_config.d/elite-x-users.conf"
    os.makedirs(os.path.dirname(ssh_conf), exist_ok=True)
    
    lines = []
    if os.path.exists(ssh_conf):
        with open(ssh_conf, "r") as f:
            lines = f.readlines()
    
    new_lines = []
    skip = False
    for line in lines:
        if line.strip().startswith(f"Match User {username}"):
            skip = True
            continue
        if skip and line.strip().startswith("    Banner"):
            skip = False
            continue
        if skip:
            skip = False
            continue
        new_lines.append(line)
    
    new_lines.append(f"Match User {username}\n")
    new_lines.append(f"    Banner {msg_file}\n")
    
    with open(ssh_conf, "w") as f:
        f.writelines(new_lines)
    
    run_cmd(["systemctl", "reload", "sshd"], ignore_errors=True)

# ================================================================
# RESELLER MANAGEMENT
# ================================================================
def get_all_resellers():
    resellers = []
    if not os.path.exists(RESELLER_DB):
        return resellers
    for fname in os.listdir(RESELLER_DB):
        fpath = f"{RESELLER_DB}/{fname}"
        if not os.path.isfile(fpath):
            continue
        info = {}
        try:
            with open(fpath, "r") as fp:
                raw = fp.read().strip()
            if raw.startswith("{"):
                data = json.loads(raw)
                info = {k: str(v) for k, v in data.items()}
            else:
                for line in raw.splitlines():
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if "=" in line:
                        k, v = line.split("=", 1)
                        info[k.strip()] = v.strip().strip('"').strip("'")
        except Exception:
            continue
        
        info["_filename"] = fname
        info["username"] = info.get("USERNAME") or info.get("NAME") or fname
        info["package"] = "VIP" if info.get("VIP", "0") == "1" else "Standard"
        resellers.append(info)
    return resellers

def get_reseller_online_users(username):
    count = 0
    users = get_all_users()
    for u in users:
        if u.get("Owner", "") == username:
            if get_user_connections(u.get("username", "")) > 0:
                count += 1
    return count

def get_reseller_total_bandwidth(username):
    total = 0
    users = get_all_users()
    for u in users:
        if u.get("Owner", "") == username:
            total += get_user_bandwidth(u.get("username", ""))
    return total / 1073741824

def create_reseller_account(username, password, brand, phone="", email="", firstname="", lastname="", is_vip=False):
    if not re.match(r'^[a-zA-Z0-9_\-]{3,32}$', username):
        raise ValueError("Invalid username (3-32 chars, alphanumeric/underscore/hyphen)")
    
    existing = get_all_resellers()
    for r in existing:
        if (r.get("USERNAME") or r.get("NAME") or r.get("_filename","")) == username:
            raise ValueError(f"Reseller '{username}' already exists")
    
    expire = calculate_expire_date(30)
    pwd_hash = hashlib.sha256(password.encode()).hexdigest()
    
    info = {
        "USERNAME": username,
        "NAME": username,
        "FIRSTNAME": firstname or username,
        "LASTNAME": lastname,
        "BRAND": brand,
        "PHONE": phone,
        "EMAIL": email,
        "PASSWORD": password,
        "PASSWORD_HASH": pwd_hash,
        "EXPIRE": expire,
        "MAX_USERS": "5" if not is_vip else "999",
        "ENABLED": "1",
        "CREATED": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "VIP": "1" if is_vip else "0"
    }
    os.makedirs(RESELLER_DB, exist_ok=True)
    with open(f"{RESELLER_DB}/{username}", "w") as f:
        for k, v in info.items():
            f.write(f"{k}={v}\n")
    return info

def update_reseller(username, data):
    path = f"{RESELLER_DB}/{username}"
    if not os.path.exists(path):
        raise ValueError("Reseller not found")
    
    with open(path, "r") as f:
        lines = f.readlines()
    
    new_lines = []
    for line in lines:
        if line.startswith("BRAND=") and "brand" in data:
            new_lines.append(f"BRAND={data['brand']}\n")
        elif line.startswith("PHONE=") and "phone" in data:
            new_lines.append(f"PHONE={data['phone']}\n")
        elif line.startswith("MAX_USERS=") and "max_users" in data:
            new_lines.append(f"MAX_USERS={data['max_users']}\n")
        elif line.startswith("PASSWORD=") and "password" in data:
            new_lines.append(f"PASSWORD={data['password']}\n")
        elif line.startswith("PASSWORD_HASH=") and "password" in data:
            new_lines.append(f"PASSWORD_HASH={hashlib.sha256(data['password'].encode()).hexdigest()}\n")
        elif line.startswith("SPEED=") and "speed" in data:
            new_lines.append(f"SPEED={data['speed']}\n")
        elif line.startswith("DAILY_LIMIT=") and "daily_limit" in data:
            new_lines.append(f"DAILY_LIMIT={data['daily_limit']}\n")
        elif line.startswith("BANDWIDTH_LIMIT=") and "bandwidth_limit" in data:
            new_lines.append(f"BANDWIDTH_LIMIT={data['bandwidth_limit']}\n")
        else:
            new_lines.append(line)
    
    with open(path, "w") as f:
        f.writelines(new_lines)
    return True

def toggle_reseller(username):
    resellers = get_all_resellers()
    for r in resellers:
        if r.get("NAME") == username or r.get("username") == username:
            current = r.get("ENABLED", "1")
            new_val = "0" if current == "1" else "1"
            path = f"{RESELLER_DB}/{r.get('username') or r.get('NAME')}"
            if os.path.exists(path):
                with open(path, "r") as f:
                    lines = f.readlines()
                with open(path, "w") as f:
                    for line in lines:
                        if line.startswith("ENABLED="):
                            f.write(f"ENABLED={new_val}\n")
                        else:
                            f.write(line)
            return {"enabled": new_val == "1"}
    raise ValueError("Reseller not found")

def delete_reseller_account(username):
    path = f"{RESELLER_DB}/{username}"
    if os.path.exists(path):
        os.remove(path)
    return True

# ================================================================
# RESELLER USER REQUESTS (for admin approval)
# ================================================================
def create_reseller_user_request(reseller, action, data):
    os.makedirs(RESELLER_USER_REQUESTS, exist_ok=True)
    req_id = f"{reseller}_{action}_{int(time.time())}"
    req = {
        "id": req_id,
        "reseller": reseller,
        "action": action,
        "data": data,
        "status": "pending",
        "created_at": time.time(),
        "created_str": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    with open(f"{RESELLER_USER_REQUESTS}/{req_id}", "w") as f:
        json.dump(req, f, indent=2)
    return req

def get_reseller_user_requests():
    requests = []
    if not os.path.exists(RESELLER_USER_REQUESTS):
        return requests
    for fname in os.listdir(RESELLER_USER_REQUESTS):
        fpath = f"{RESELLER_USER_REQUESTS}/{fname}"
        if os.path.isfile(fpath):
            try:
                with open(fpath) as f:
                    req = json.load(f)
                req["_id"] = fname
                requests.append(req)
            except Exception:
                pass
    requests.sort(key=lambda x: x.get("created_at", 0), reverse=True)
    return requests

def approve_reseller_user_request(req_id):
    fpath = f"{RESELLER_USER_REQUESTS}/{req_id}"
    if not os.path.exists(fpath):
        raise ValueError("Request not found")
    with open(fpath) as f:
        req = json.load(f)
    if req.get("status") != "pending":
        raise ValueError("Request already processed")
    
    action = req["action"]
    data = req["data"]
    result = None
    
    try:
        if action == "create":
            result = create_user(
                data["username"],
                data.get("password", generate_password()),
                data.get("days", 30),
                data.get("conn_limit", 1),
                data.get("bandwidth_gb", 0),
                data.get("daily_limit_gb", 0),
                0,
                req["reseller"]
            )
        elif action == "renew":
            result = renew_user(data["username"], data["days"])
        elif action == "edit":
            result = update_user(data["username"], data)
        elif action == "lock":
            result = lock_user(data["username"])
        elif action == "unlock":
            result = unlock_user(data["username"])
    except Exception as e:
        raise ValueError(f"Failed to process request: {str(e)}")
    
    req["status"] = "approved"
    req["approved_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    req["result"] = str(result)
    with open(fpath, "w") as f:
        json.dump(req, f, indent=2)
    return {"approved": True, "result": result}

def reject_reseller_user_request(req_id, reason=""):
    fpath = f"{RESELLER_USER_REQUESTS}/{req_id}"
    if not os.path.exists(fpath):
        raise ValueError("Request not found")
    with open(fpath) as f:
        req = json.load(f)
    req["status"] = "rejected"
    req["reject_reason"] = reason
    req["rejected_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(fpath, "w") as f:
        json.dump(req, f, indent=2)
    return True

# ================================================================
# PACKAGE SYSTEM
# ================================================================
DEFAULT_PACKAGES = [
    {"id":"starter", "name":"Starter", "days":7, "reseller_price":5000, "conn_limit":1, "bandwidth_gb":0, "daily_limit_gb":0},
    {"id":"basic", "name":"Basic", "days":14, "reseller_price":8500, "conn_limit":1, "bandwidth_gb":0, "daily_limit_gb":0},
    {"id":"premium", "name":"Premium", "days":30, "reseller_price":15000, "conn_limit":2, "bandwidth_gb":0, "daily_limit_gb":0},
    {"id":"vip", "name":"VIP", "days":30, "reseller_price":20000, "conn_limit":999, "bandwidth_gb":0, "daily_limit_gb":0, "is_vip":True},
]

def get_packages():
    if os.path.exists(PACKAGES_FILE):
        try:
            with open(PACKAGES_FILE) as f:
                return json.load(f)
        except Exception:
            pass
    return DEFAULT_PACKAGES

def save_packages(pkgs):
    os.makedirs(os.path.dirname(PACKAGES_FILE), exist_ok=True)
    with open(PACKAGES_FILE, "w") as f:
        json.dump(pkgs, f, indent=2)

def get_package_requests():
    requests = []
    if not os.path.exists(PACKAGE_REQUESTS_DIR):
        return requests
    for fname in os.listdir(PACKAGE_REQUESTS_DIR):
        fpath = f"{PACKAGE_REQUESTS_DIR}/{fname}"
        if os.path.isfile(fpath):
            try:
                with open(fpath) as f:
                    req = json.load(f)
                req["_id"] = fname
                requests.append(req)
            except Exception:
                pass
    requests.sort(key=lambda x: x.get("created_at", 0), reverse=True)
    return requests

def create_package_request(reseller, package_id, ssh_username, ssh_password, payment_ref=""):
    pkgs = get_packages()
    pkg = next((p for p in pkgs if p["id"] == package_id), None)
    if not pkg:
        raise ValueError(f"Package '{package_id}' not found")
    
    existing = get_package_requests()
    for r in existing:
        if r.get("reseller") == reseller and r.get("ssh_username") == ssh_username and r.get("status") == "pending":
            raise ValueError(f"User '{ssh_username}' already has a pending request")
        if r.get("reseller") == reseller and r.get("ssh_username") == ssh_username and r.get("status") == "banned":
            raise ValueError(f"User '{ssh_username}' is banned. Too many failed attempts.")
    
    attempts = 1
    for r in existing:
        if r.get("reseller") == reseller and r.get("ssh_username") == ssh_username:
            attempts = r.get("attempts", 0) + 1
            if attempts > 3:
                raise ValueError(f"Too many failed attempts for '{ssh_username}'. Account banned.")
    
    # VIP package - auto approve
    is_vip = package_id == "vip"
    
    os.makedirs(PACKAGE_REQUESTS_DIR, exist_ok=True)
    req_id = f"{reseller}_{package_id}_{int(time.time())}"
    req = {
        "id": req_id,
        "reseller": reseller,
        "package_id": package_id,
        "package_name": pkg["name"],
        "days": pkg["days"],
        "conn_limit": pkg["conn_limit"],
        "bandwidth_gb": pkg.get("bandwidth_gb", 0),
        "daily_limit_gb": pkg.get("daily_limit_gb", 0),
        "reseller_price": pkg["reseller_price"],
        "ssh_username": ssh_username,
        "ssh_password": ssh_password or generate_password(),
        "payment_ref": payment_ref,
        "status": "approved" if is_vip else "pending",
        "attempts": attempts,
        "created_at": time.time(),
        "created_str": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "is_vip": is_vip
    }
    
    if is_vip:
        # Auto-create VIP user
        try:
            info = create_user(
                ssh_username, 
                req["ssh_password"], 
                pkg["days"], 
                pkg["conn_limit"], 
                pkg.get("bandwidth_gb", 0), 
                pkg.get("daily_limit_gb", 0), 
                0, 
                reseller, 
                pkg["name"], 
                pkg["reseller_price"],
                True
            )
            req["created_user"] = info
            req["approved_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        except Exception as e:
            req["status"] = "failed"
            req["error"] = str(e)
    
    with open(f"{PACKAGE_REQUESTS_DIR}/{req_id}", "w") as f:
        json.dump(req, f, indent=2)
    return req

def approve_package_request(req_id):
    fpath = f"{PACKAGE_REQUESTS_DIR}/{req_id}"
    if not os.path.exists(fpath):
        raise ValueError("Request not found")
    with open(fpath) as f:
        req = json.load(f)
    if req.get("status") != "pending":
        raise ValueError("Request already processed")
    
    reseller = req["reseller"]
    username = req["ssh_username"]
    password = req["ssh_password"]
    days = req["days"]
    conn = req["conn_limit"]
    bw = req.get("bandwidth_gb", 0)
    daily = req.get("daily_limit_gb", 0)
    pkg_name = req.get("package_name", "")
    pkg_price = req.get("reseller_price", 0)
    is_vip = req.get("is_vip", False)
    
    try:
        info = create_user(username, password, days, conn, bw, daily, 0, reseller, pkg_name, pkg_price, is_vip)
    except Exception as e:
        raise ValueError(f"Failed to create user: {str(e)}")
    
    req["status"] = "approved"
    req["approved_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    req["created_user"] = info
    with open(fpath, "w") as f:
        json.dump(req, f, indent=2)
    return {"approved": True, "user": info}

def reject_package_request(req_id, reason=""):
    fpath = f"{PACKAGE_REQUESTS_DIR}/{req_id}"
    if not os.path.exists(fpath):
        raise ValueError("Request not found")
    with open(fpath) as f:
        req = json.load(f)
    
    attempts = req.get("attempts", 1)
    
    if attempts >= 3:
        req["status"] = "banned"
        reason = f"{reason} (Banned after 3 attempts)"
    else:
        req["status"] = "rejected"
        req["attempts"] = attempts + 1
    
    req["reject_reason"] = reason
    req["rejected_at"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    
    with open(fpath, "w") as f:
        json.dump(req, f, indent=2)
    return True

# ================================================================
# DASHBOARD DATA
# ================================================================
def get_dashboard_data_for_user(username, role="admin"):
    result = {
        "username": username,
        "password": "",
        "nameserver": get_nameserver(),
        "public_key": get_public_key(),
        "expire_date": "",
        "expire_percent": 0,
        "bandwidth_limit_gb": 0,
        "bandwidth_used_gb": 0,
        "bandwidth_percent": 0,
        "daily_limit_gb": 0,
        "daily_used_gb": 0,
        "daily_percent": 0,
        "total_users": 0,
        "online_sessions": 0,
        "ram_percent": 0,
        "ram_used_mb": 0,
        "ram_total_mb": 0,
        "cpu_load": 0,
        "server_ip": "",
        "os_name": "",
        "uptime": "",
        "services": get_services_status(),
        "chart_data": get_chart_data(username),
        "commission": 0,
        "activity": get_all_activity(10),
        "package": "Standard"
    }
    
    if role == "reseller":
        resellers = get_all_resellers()
        for r in resellers:
            r_name = r.get("USERNAME") or r.get("NAME") or r.get("username") or r.get("_filename","")
            if r_name == username:
                result["password"] = r.get("PASSWORD", "")
                result["expire_date"] = r.get("EXPIRE", "")
                result["package"] = "VIP" if r.get("VIP", "0") == "1" else "Standard"
                break
        result["commission"] = get_reseller_commission(username)
    else:
        creds = get_panel_creds()
        result["password"] = creds.get("PANEL_PASS_PLAIN", "")
        result["expire_date"] = "N/A"
        result["package"] = "Admin"
    
    expire_date = result["expire_date"]
    if expire_date and expire_date != "N/A":
        try:
            exp_ts = datetime.strptime(expire_date, "%Y-%m-%d")
            now = datetime.now()
            total = 30
            elapsed = (now - (exp_ts - timedelta(days=total))).days
            pct = (elapsed / total) * 100
            result["expire_percent"] = min(max(pct, 0), 100)
        except Exception:
            pass
    
    if role == "reseller":
        all_users = get_all_users()
        for u in all_users:
            if u.get("Owner", "") == username:
                un = u.get("username", "")
                bw_bytes = get_user_bandwidth(un)
                bw_gb = bw_bytes / 1073741824 if bw_bytes else 0
                bw_limit = float(u.get("Bandwidth_GB", 0))
                result["bandwidth_used_gb"] = round(bw_gb, 2)
                result["bandwidth_limit_gb"] = bw_limit if bw_limit > 0 else 0
                if bw_limit > 0:
                    result["bandwidth_percent"] = min(100, (bw_gb / bw_limit) * 100)
                
                daily_bytes = get_user_daily_bandwidth(un)
                daily_gb = daily_bytes / 1073741824 if daily_bytes else 0
                daily_limit = float(u.get("Daily_Limit", 0))
                result["daily_used_gb"] = round(daily_gb, 2)
                result["daily_limit_gb"] = daily_limit if daily_limit > 0 else 0
                if daily_limit > 0:
                    result["daily_percent"] = min(100, (daily_gb / daily_limit) * 100)
                break
    
    users = get_all_users()
    if role == "reseller":
        result["total_users"] = len([u for u in users if u.get("Owner", "") == username])
    else:
        result["total_users"] = len(users)
    
    online_count = 0
    for u in users:
        conn = get_user_connections(u.get("username", ""))
        online_count += conn
    result["online_sessions"] = online_count
    
    result["server_ip"] = get_server_ip()
    
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    result["os_name"] = line.split("=")[1].strip().strip('"')
                    break
    except Exception:
        pass
    
    code, uptime_str, _ = run_cmd("uptime -p")
    if uptime_str.startswith("up "):
        uptime_str = uptime_str[3:]
    result["uptime"] = uptime_str or "Unknown"
    
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    result["ram_total_mb"] = int(line.split()[1]) // 1024
                elif line.startswith("MemAvailable:"):
                    ram_avail = int(line.split()[1]) // 1024
                    result["ram_used_mb"] = result["ram_total_mb"] - ram_avail
                    if result["ram_total_mb"] > 0:
                        result["ram_percent"] = round((result["ram_used_mb"] / result["ram_total_mb"]) * 100, 1)
    except Exception:
        pass
    
    try:
        with open("/proc/loadavg") as f:
            result["cpu_load"] = round(float(f.read().split()[0]), 2)
    except Exception:
        pass
    
    return result

# ================================================================
# PANEL CREDENTIALS
# ================================================================
def get_panel_creds():
    creds = {
        "PANEL_USER": "admin",
        "PANEL_PASS_HASH": "",
        "PANEL_PASS_PLAIN": "",
        "PANEL_SECRET": "elitex",
        "PANEL_NAME": "ELITE-X",
        "PANEL_LOGO": ""
    }
    if os.path.exists(PANEL_CONFIG):
        with open(PANEL_CONFIG, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip()
                    v = v.split("#")[0].strip()
                    v = v.strip('"').strip("'").strip()
                    if k in creds:
                        creds[k] = v
    
    if not creds["PANEL_PASS_HASH"] and creds["PANEL_PASS_PLAIN"]:
        creds["PANEL_PASS_HASH"] = hashlib.sha256(creds["PANEL_PASS_PLAIN"].encode()).hexdigest()
    
    return creds

def save_panel_creds(creds):
    with open(PANEL_CONFIG, "w") as f:
        for k, v in creds.items():
            f.write(f'{k}="{v}"\n')

# ================================================================
# HTTP HANDLER
# ================================================================
class EliteXHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass
    
    def send_json(self, status, data, extra_headers=None):
        body = json.dumps(data).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
        if extra_headers:
            for k, v in extra_headers.items():
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)
    
    def get_session(self):
        cleanup_sessions()
        if "Cookie" in self.headers:
            C = cookies.SimpleCookie(self.headers["Cookie"])
            if "session" in C:
                token = C["session"].value
                if token in sessions:
                    return sessions[token]
        return None
    
    def require_auth(self):
        session = self.get_session()
        if not session:
            self.send_json(401, {"error": "Unauthorized"})
            return None
        return session
    
    def require_admin(self, session):
        if session.get("role") != "admin":
            self.send_json(403, {"error": "Admin access required"})
            return False
        return True
    
    def require_reseller(self, session):
        if session.get("role") != "reseller":
            self.send_json(403, {"error": "Reseller access required"})
            return False
        return True
    
    def is_vip_reseller(self, session):
        username = session.get("username", "")
        resellers = get_all_resellers()
        for r in resellers:
            if r.get("username") == username:
                return r.get("VIP", "0") == "1"
        return False
    
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        try:
            creds_for_path = get_panel_creds()
            secret_path = creds_for_path.get("PANEL_SECRET", "").strip().lstrip("/")
            secret_url = f"/{secret_path}" if secret_path else None
            if path == "/" or path == "/index.html" or (secret_url and path == secret_url):
                if os.path.exists(PANEL_HTML):
                    with open(PANEL_HTML, "rb") as f:
                        content = f.read()
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.send_header('Content-Length', str(len(content)))
                    self.send_header('Cache-Control', 'no-cache, no-store, must-revalidate')
                    self.end_headers()
                    self.wfile.write(content)
                else:
                    body = b"<h1>panel.html not found</h1>"
                    self.send_response(404)
                    self.send_header('Content-Type', 'text/html')
                    self.send_header('Content-Length', str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                return
            
            session = self.require_auth()
            if not session:
                return
            
            username = session.get("username", "")
            role = session.get("role", "admin")
            is_vip = self.is_vip_reseller(session) if role == "reseller" else False
            
            if path == "/api/me":
                creds = get_panel_creds()
                pkg = "VIP" if is_vip else "Standard" if role == "reseller" else "Admin"
                self.send_json(200, {
                    "username": username,
                    "role": role,
                    "panel_name": creds.get("PANEL_NAME", "ELITE-X"),
                    "panel_logo": creds.get("PANEL_LOGO", ""),
                    "package": pkg
                })
            
            elif path == "/api/dashboard":
                data = get_dashboard_data_for_user(username, role)
                self.send_json(200, data)
            
            elif path == "/api/users":
                users = get_all_users()
                
                all_requests = get_reseller_user_requests()
                pending_reqs = [r for r in all_requests if r.get("status") == "pending"]
                
                if role == "reseller" and not is_vip:
                    users = [u for u in users if u.get("Owner", "") == username]
                    for r in pending_reqs:
                        if r.get("reseller") == username:
                            data = r.get("data", {})
                            users.append({
                                "username": data.get("username", "pending"),
                                "password": data.get("password", "****"),
                                "expire_date": "Pending",
                                "conn_limit": data.get("conn_limit", 1),
                                "bandwidth_gb": data.get("bandwidth_gb", 0),
                                "daily_limit_gb": data.get("daily_limit_gb", 0),
                                "connections": 0,
                                "is_locked": False,
                                "is_expired": False,
                                "status": f"pending-{r.get('action')}" if r.get('action') != 'create' else "pending",
                                "reject_reason": "",
                                "owner": username,
                                "bandwidth_used": 0,
                                "daily_used": 0,
                                "package_name": data.get("package_name", ""),
                                "package_price": data.get("package_price", 0),
                                "purchase_date": r.get("created_str", "")
                            })
                else:
                    for r in pending_reqs:
                        data = r.get("data", {})
                        users.append({
                            "username": data.get("username", "pending"),
                            "password": data.get("password", "****"),
                            "expire_date": "Pending",
                            "conn_limit": data.get("conn_limit", 1),
                            "bandwidth_gb": data.get("bandwidth_gb", 0),
                            "daily_limit_gb": data.get("daily_limit_gb", 0),
                            "connections": 0,
                            "is_locked": False,
                            "is_expired": False,
                            "status": f"pending-{r.get('action')}" if r.get('action') != 'create' else "pending",
                            "reject_reason": "",
                            "owner": r.get("reseller", "admin"),
                            "bandwidth_used": 0,
                            "daily_used": 0,
                            "package_name": data.get("package_name", ""),
                            "package_price": data.get("package_price", 0),
                            "purchase_date": r.get("created_str", "")
                        })
                
                result = []
                for u in users:
                    un = u.get("username", "")
                    result.append({
                        "username": un,
                        "password": u.get("Password", ""),
                        "expire_date": u.get("Expire", ""),
                        "conn_limit": int(u.get("Conn_Limit", 1)),
                        "bandwidth_gb": float(u.get("Bandwidth_GB", 0)),
                        "bandwidth_used": get_user_bandwidth(un),
                        "daily_limit_gb": float(u.get("Daily_Limit", 0)),
                        "daily_used": get_user_daily_bandwidth(un),
                        "connections": get_user_connections(un),
                        "is_locked": is_user_locked(un),
                        "is_expired": is_user_expired(u),
                        "owner": u.get("Owner", "admin"),
                        "status": u.get("status", ""),
                        "reject_reason": u.get("reject_reason", ""),
                        "activity": get_user_activity(un, 5),
                        "package_name": u.get("Package", u.get("package_name", "")),
                        "package_price": u.get("Package_Price", u.get("package_price", 0)),
                        "purchase_date": u.get("Purchase_Date", u.get("purchase_date", "")),
                        "vip": u.get("VIP", "0") == "1"
                    })
                self.send_json(200, {"users": result})
            
            elif path == "/api/reseller/packages":
                if not self.require_reseller(session):
                    return
                pkgs = get_packages()
                reqs = [r for r in get_package_requests() if r.get("reseller") == username]
                user_reqs = [r for r in get_reseller_user_requests() if r.get("reseller") == username]
                self.send_json(200, {"packages": pkgs, "requests": reqs, "user_requests": user_reqs})
            
            elif path == "/api/admin/requests":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                package_reqs = get_package_requests()
                user_reqs = get_reseller_user_requests()
                all_reqs = package_reqs + user_reqs
                all_reqs.sort(key=lambda x: x.get("created_at", 0), reverse=True)
                self.send_json(200, {"requests": all_reqs})
            
            elif path == "/api/resellers":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                resellers = get_all_resellers()
                all_users = get_all_users()
                user_counts = defaultdict(int)
                online_counts = defaultdict(int)
                bw_totals = defaultdict(float)
                for u in all_users:
                    owner = u.get("Owner", "admin")
                    user_counts[owner] += 1
                    if get_user_connections(u.get("username", "")) > 0:
                        online_counts[owner] += 1
                    bw_totals[owner] += get_user_bandwidth(u.get("username", ""))
                
                reseller_list = []
                for r in resellers:
                    name = r.get("NAME") or r.get("username", "")
                    reseller_list.append({
                        "username": name,
                        "brand": r.get("BRAND", ""),
                        "phone": r.get("PHONE", ""),
                        "email": r.get("EMAIL", ""),
                        "expire_date": r.get("EXPIRE", ""),
                        "max_users": int(r.get("MAX_USERS", 5)),
                        "created_users": user_counts.get(name, 0),
                        "online_users": online_counts.get(name, 0),
                        "total_bandwidth_gb": round(bw_totals.get(name, 0) / 1073741824, 2),
                        "enabled": r.get("ENABLED", "1") == "1",
                        "is_expired": is_user_expired({"Expire": r.get("EXPIRE", "")}),
                        "package": "VIP" if r.get("VIP", "0") == "1" else "Standard"
                    })
                self.send_json(200, {"resellers": reseller_list})
            
            elif path.startswith("/api/reseller/users/"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                reseller_name = path.split("/")[4]
                users = get_users_by_reseller(reseller_name)
                result = []
                for u in users:
                    un = u.get("username", "")
                    result.append({
                        "username": un,
                        "password": u.get("Password", ""),
                        "expire_date": u.get("Expire", ""),
                        "conn_limit": int(u.get("Conn_Limit", 1)),
                        "bandwidth_gb": float(u.get("Bandwidth_GB", 0)),
                        "bandwidth_used": get_user_bandwidth(un),
                        "daily_limit_gb": float(u.get("Daily_Limit", 0)),
                        "daily_used": get_user_daily_bandwidth(un),
                        "connections": get_user_connections(un),
                        "is_locked": is_user_locked(un),
                        "is_expired": is_user_expired(u),
                        "package_name": u.get("Package", ""),
                        "package_price": u.get("Package_Price", 0),
                        "purchase_date": u.get("Purchase_Date", ""),
                        "vip": u.get("VIP", "0") == "1"
                    })
                self.send_json(200, {"users": result})
            
            elif path == "/api/user/activity":
                uname = parsed.query.split("=")[-1] if "=" in parsed.query else ""
                if not uname:
                    self.send_json(400, {"error": "Username required"})
                    return
                if role == "reseller" and not is_vip:
                    info = get_user_info(uname)
                    if info and info.get("Owner", "") != username:
                        self.send_json(403, {"error": "Not your user"})
                        return
                activity = get_user_activity(uname)
                self.send_json(200, {"activity": activity})
            
            else:
                self.send_json(404, {"error": "Not Found"})
        
        except Exception as e:
            self.send_json(500, {"error": str(e)})
    
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)
        try:
            body = json.loads(post_data.decode('utf-8')) if post_data else {}
        except json.JSONDecodeError:
            body = {}
        
        try:
            if path == "/api/login":
                username = body.get("username", "")
                password = body.get("password", "")
                
                creds = get_panel_creds()
                pwd_hash = hashlib.sha256(password.encode()).hexdigest()
                
                if username == creds.get("PANEL_USER") and pwd_hash == creds.get("PANEL_PASS_HASH"):
                    token = secrets.token_hex(32)
                    sessions[token] = {"username": username, "role": "admin", "created_at": time.time()}
                    save_sessions()
                    cookie = f"session={token}; Path=/; HttpOnly; Max-Age=86400"
                    self.send_json(200, {"success": True, "role": "admin"}, {"Set-Cookie": cookie})
                    return
                
                resellers = get_all_resellers()
                for r in resellers:
                    r_name = r.get("USERNAME") or r.get("NAME") or r.get("username") or r.get("_filename","")
                    if r_name != username:
                        continue
                    
                    if r.get("ENABLED", "1") == "0":
                        self.send_json(401, {"error": "Account disabled"})
                        return
                    
                    expire = r.get("EXPIRE", "")
                    if expire:
                        try:
                            exp_date = datetime.strptime(expire, "%Y-%m-%d")
                            if exp_date < datetime.now():
                                self.send_json(401, {"error": "Account expired"})
                                return
                        except ValueError:
                            pass
                    
                    pwd_plain = r.get("PASSWORD", "")
                    pwd_hash_stored = r.get("PASSWORD_HASH", "")
                    pwd_hash_input = hashlib.sha256(password.encode()).hexdigest()
                    
                    matched = False
                    if pwd_hash_stored and pwd_hash_stored == pwd_hash_input:
                        matched = True
                    elif pwd_plain and pwd_plain == password:
                        matched = True
                    
                    if not matched:
                        self.send_json(401, {"error": "Invalid credentials"})
                        return
                    
                    token = secrets.token_hex(32)
                    sessions[token] = {"username": r_name, "role": "reseller", "created_at": time.time()}
                    save_sessions()
                    cookie = f"session={token}; Path=/; HttpOnly; Max-Age=86400"
                    self.send_json(200, {"success": True, "role": "reseller"}, {"Set-Cookie": cookie})
                    return
                
                self.send_json(401, {"error": "Invalid credentials"})
                return
            
            if path == "/api/logout":
                if "Cookie" in self.headers:
                    C = cookies.SimpleCookie(self.headers["Cookie"])
                    if "session" in C:
                        token = C["session"].value
                        if token in sessions:
                            del sessions[token]
                            save_sessions()
                cookie = "session=; Path=/; HttpOnly; Max-Age=0"
                self.send_json(200, {"success": True}, {"Set-Cookie": cookie})
                return
            
            if path == "/api/reseller/register":
                try:
                    firstname = body.get("firstname", "").strip()
                    lastname = body.get("lastname", "").strip()
                    phone = body.get("phone", "").strip()
                    email = body.get("email", "").strip()
                    username = body.get("username", "").strip()
                    password = body.get("password", "").strip() or generate_password()
                    brand = body.get("brand", "").strip()
                    
                    if not all([firstname, lastname, phone, email, username, brand]):
                        self.send_json(400, {"error": "All fields are required"})
                        return
                    
                    info = create_reseller_account(username, password, brand, phone, email, firstname, lastname)
                    
                    token = secrets.token_hex(32)
                    sessions[token] = {"username": username, "role": "reseller", "created_at": time.time()}
                    save_sessions()
                    cookie = f"session={token}; Path=/; HttpOnly; Max-Age=86400"
                    
                    self.send_json(200, {
                        "success": True,
                        "message": "Account created successfully!",
                        "username": username,
                        "password": password
                    }, {"Set-Cookie": cookie})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
                return
            
            session = self.require_auth()
            if not session:
                return
            
            username = session.get("username", "")
            role = session.get("role", "admin")
            is_vip = self.is_vip_reseller(session) if role == "reseller" else False
            
            if path == "/api/users":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                try:
                    uname = body.get("username", "")
                    password = body.get("password", "") or generate_password()
                    days = int(body.get("days", 30))
                    conn_limit = int(body.get("conn_limit", 1))
                    bandwidth_gb = float(body.get("bandwidth_gb", 0))
                    daily_limit_gb = float(body.get("daily_limit_gb", 0))
                    owner = "admin"
                    
                    info = create_user(uname, password, days, conn_limit, bandwidth_gb, daily_limit_gb, 0, owner)
                    self.send_json(200, {"success": True, "user": info})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path == "/api/reseller/request-user":
                if not self.require_reseller(session):
                    return
                if is_vip:
                    # VIP reseller can create users directly
                    try:
                        data = {
                            "username": body.get("username", ""),
                            "password": body.get("password", "") or generate_password(),
                            "days": int(body.get("days", 30)),
                            "conn_limit": int(body.get("conn_limit", 1)),
                            "bandwidth_gb": float(body.get("bandwidth_gb", 0)),
                            "daily_limit_gb": float(body.get("daily_limit_gb", 0))
                        }
                        info = create_user(
                            data["username"],
                            data["password"],
                            data["days"],
                            data["conn_limit"],
                            data["bandwidth_gb"],
                            data["daily_limit_gb"],
                            0,
                            username
                        )
                        self.send_json(200, {"success": True, "user": info})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
                else:
                    try:
                        data = {
                            "username": body.get("username", ""),
                            "password": body.get("password", "") or generate_password(),
                            "days": int(body.get("days", 30)),
                            "conn_limit": int(body.get("conn_limit", 1)),
                            "bandwidth_gb": float(body.get("bandwidth_gb", 0)),
                            "daily_limit_gb": float(body.get("daily_limit_gb", 0))
                        }
                        req = create_reseller_user_request(username, "create", data)
                        self.send_json(200, {"success": True, "request": req})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
            
            elif path == "/api/reseller/request-renew":
                if not self.require_reseller(session):
                    return
                if is_vip:
                    try:
                        data = {
                            "username": body.get("username", ""),
                            "days": int(body.get("days", 30))
                        }
                        result = renew_user(data["username"], data["days"])
                        self.send_json(200, {"success": True, "expire_date": result})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
                else:
                    try:
                        data = {
                            "username": body.get("username", ""),
                            "days": int(body.get("days", 30))
                        }
                        req = create_reseller_user_request(username, "renew", data)
                        self.send_json(200, {"success": True, "request": req})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
            
            elif path == "/api/reseller/request-edit":
                if not self.require_reseller(session):
                    return
                if is_vip:
                    try:
                        data = {
                            "username": body.get("username", ""),
                            "password": body.get("password") or None,
                            "bandwidth_gb": float(body.get("bandwidth_gb", 0)),
                            "daily_limit_gb": float(body.get("daily_limit_gb", 0)),
                            "conn_limit": int(body.get("conn_limit", 1)),
                            "days": int(body.get("days", 0))
                        }
                        result = update_user(data["username"], data)
                        self.send_json(200, {"success": True, "user": result})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
                else:
                    try:
                        data = {
                            "username": body.get("username", ""),
                            "password": body.get("password") or None,
                            "bandwidth_gb": float(body.get("bandwidth_gb", 0)),
                            "daily_limit_gb": float(body.get("daily_limit_gb", 0)),
                            "conn_limit": int(body.get("conn_limit", 1)),
                            "days": int(body.get("days", 0))
                        }
                        req = create_reseller_user_request(username, "edit", data)
                        self.send_json(200, {"success": True, "request": req})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
            
            elif path == "/api/reseller/request-lock":
                if not self.require_reseller(session):
                    return
                if is_vip:
                    try:
                        data = {"username": body.get("username", "")}
                        result = lock_user(data["username"])
                        self.send_json(200, {"success": True})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
                else:
                    try:
                        data = {"username": body.get("username", "")}
                        req = create_reseller_user_request(username, "lock", data)
                        self.send_json(200, {"success": True, "request": req})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
            
            elif path == "/api/reseller/request-unlock":
                if not self.require_reseller(session):
                    return
                if is_vip:
                    try:
                        data = {"username": body.get("username", "")}
                        result = unlock_user(data["username"])
                        self.send_json(200, {"success": True})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
                else:
                    try:
                        data = {"username": body.get("username", "")}
                        req = create_reseller_user_request(username, "unlock", data)
                        self.send_json(200, {"success": True, "request": req})
                    except Exception as e:
                        self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/admin/user-requests/") and path.endswith("/approve"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                req_id = path.split("/")[4]
                try:
                    result = approve_reseller_user_request(req_id)
                    self.send_json(200, {"success": True, **result})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/admin/user-requests/") and path.endswith("/reject"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                req_id = path.split("/")[4]
                reason = body.get("reason", "")
                try:
                    reject_reseller_user_request(req_id, reason)
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path == "/api/reseller/request-package":
                if not self.require_reseller(session):
                    return
                try:
                    package_id = body.get("package_id", "").strip()
                    ssh_username = body.get("ssh_username", "").strip()
                    ssh_password = body.get("ssh_password", "").strip() or generate_password()
                    payment_ref = body.get("payment_ref", "").strip()
                    
                    if not package_id or not ssh_username:
                        self.send_json(400, {"error": "Package and SSH username required"})
                        return
                    
                    req = create_package_request(username, package_id, ssh_username, ssh_password, payment_ref)
                    self.send_json(200, {"success": True, "request": req})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/admin/requests/") and path.endswith("/approve"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                req_id = path.split("/")[4]
                try:
                    if os.path.exists(f"{PACKAGE_REQUESTS_DIR}/{req_id}"):
                        result = approve_package_request(req_id)
                    elif os.path.exists(f"{RESELLER_USER_REQUESTS}/{req_id}"):
                        result = approve_reseller_user_request(req_id)
                    else:
                        self.send_json(404, {"error": "Request not found"})
                        return
                    self.send_json(200, {"success": True, **result})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/admin/requests/") and path.endswith("/reject"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                req_id = path.split("/")[4]
                reason = body.get("reason", "")
                try:
                    if os.path.exists(f"{PACKAGE_REQUESTS_DIR}/{req_id}"):
                        reject_package_request(req_id, reason)
                    elif os.path.exists(f"{RESELLER_USER_REQUESTS}/{req_id}"):
                        reject_reseller_user_request(req_id, reason)
                    else:
                        self.send_json(404, {"error": "Request not found"})
                        return
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path == "/api/admin/create-user":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                try:
                    reseller_owner = body.get("reseller", "").strip()
                    uname = body.get("username", "").strip()
                    password = body.get("password", "").strip() or generate_password()
                    days = int(body.get("days", 30))
                    conn_limit = int(body.get("conn_limit", 1))
                    bandwidth_gb = float(body.get("bandwidth_gb", 0))
                    daily_limit_gb = float(body.get("daily_limit_gb", 0))
                    
                    if not reseller_owner or not uname:
                        self.send_json(400, {"error": "Reseller and username required"})
                        return
                    
                    resellers = get_all_resellers()
                    found = any(
                        (r.get("USERNAME") or r.get("NAME") or r.get("username") or r.get("_filename","")) == reseller_owner
                        for r in resellers
                    )
                    if not found:
                        self.send_json(404, {"error": f"Reseller '{reseller_owner}' not found"})
                        return
                    
                    info = create_user(uname, password, days, conn_limit, bandwidth_gb, daily_limit_gb, 0, reseller_owner)
                    self.send_json(200, {"success": True, "user": info})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path == "/api/resellers":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                try:
                    username_new = body.get("username", "").strip()
                    password = body.get("password", "").strip() or generate_password()
                    brand = body.get("brand", username_new).strip()
                    phone = body.get("phone", "").strip()
                    email = body.get("email", "").strip()
                    is_vip_new = body.get("is_vip", False)
                    
                    if not username_new:
                        self.send_json(400, {"error": "Username is required"})
                        return
                    
                    info = create_reseller_account(username_new, password, brand, phone, email, "", "", is_vip_new)
                    self.send_json(200, {"success": True, "reseller": info})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/resellers/") and not path.endswith("/toggle"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                reseller_name = path.split("/")[3]
                try:
                    result = update_reseller(reseller_name, body)
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/resellers/") and path.endswith("/toggle"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                reseller_name = path.split("/")[3]
                try:
                    result = toggle_reseller(reseller_name)
                    self.send_json(200, {"success": True, "enabled": result["enabled"]})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/users/") and path.endswith("/lock"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                uname = path.split("/")[3]
                try:
                    lock_user(uname)
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/users/") and path.endswith("/unlock"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                uname = path.split("/")[3]
                try:
                    unlock_user(uname)
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/users/") and path.endswith("/renew"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                uname = path.split("/")[3]
                days = int(body.get("days", 30))
                try:
                    new_expire = renew_user(uname, days)
                    self.send_json(200, {"success": True, "expire_date": new_expire})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/users/") and not path.endswith("/lock") and not path.endswith("/unlock") and not path.endswith("/renew"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                uname = path.split("/")[3]
                try:
                    result = update_user(uname, body)
                    self.send_json(200, {"success": True, "user": result})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path == "/api/account":
                if role == "admin":
                    creds = get_panel_creds()
                    if "username" in body:
                        creds["PANEL_USER"] = body["username"]
                    if "password" in body:
                        creds["PANEL_PASS_PLAIN"] = body["password"]
                        creds["PANEL_PASS_HASH"] = hashlib.sha256(body["password"].encode()).hexdigest()
                    save_panel_creds(creds)
                else:
                    resellers = get_all_resellers()
                    for r in resellers:
                        if r.get("username") == username:
                            path = f"{RESELLER_DB}/{r.get('_filename')}"
                            with open(path, "r") as f:
                                lines = f.readlines()
                            with open(path, "w") as f:
                                for line in lines:
                                    if line.startswith("PASSWORD=") and "password" in body:
                                        f.write(f"PASSWORD={body['password']}\n")
                                    elif line.startswith("PASSWORD_HASH=") and "password" in body:
                                        f.write(f"PASSWORD_HASH={hashlib.sha256(body['password'].encode()).hexdigest()}\n")
                                    else:
                                        f.write(line)
                            break
                self.send_json(200, {"success": True})
            
            elif path == "/api/reseller/settings":
                if not self.require_reseller(session):
                    return
                try:
                    resellers = get_all_resellers()
                    for r in resellers:
                        if r.get("username") == username:
                            path = f"{RESELLER_DB}/{r.get('_filename')}"
                            with open(path, "r") as f:
                                lines = f.readlines()
                            with open(path, "w") as f:
                                for line in lines:
                                    if line.startswith("BRAND=") and "brand" in body:
                                        f.write(f"BRAND={body['brand']}\n")
                                    elif line.startswith("PHONE=") and "phone" in body:
                                        f.write(f"PHONE={body['phone']}\n")
                                    else:
                                        f.write(line)
                            break
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/services/") and path.endswith("/restart"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                service = path.split("/")[3]
                try:
                    run_cmd(["systemctl", "restart", service])
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path == "/api/services/restart-all":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                try:
                    for s in ["dnstt-elite-x", "dnstt-elite-x-proxy", "elite-x-udp-turbo",
                             "elite-x-slowdns-relay", "ssh", "elite-x-bandwidth"]:
                        run_cmd(["systemctl", "restart", s])
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path == "/api/system/mtu":
                if role != "admin":
                    self.send_json(403, {"error": "Only admin can change MTU"})
                    return
                mtu = body.get("mtu")
                if mtu:
                    write_file(MTU_FILE, str(mtu))
                    run_cmd(["systemctl", "restart", "dnstt-elite-x"])
                    self.send_json(200, {"success": True})
                else:
                    self.send_json(400, {"error": "MTU value required"})
            
            elif path == "/api/system/reboot":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                self.send_json(200, {"success": True})
                time.sleep(1)
                os.system("reboot")
            
            elif path == "/api/system/clear-junk":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                try:
                    os.system(f"rm -rf {JUNK_DIR}/* 2>/dev/null")
                    os.system("find /var/log -type f -name '*.log' -size +50M -exec truncate -s 0 {} \\; 2>/dev/null")
                    os.system("journalctl --vacuum-size=50M 2>/dev/null")
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            else:
                self.send_json(404, {"error": "Not Found"})
        
        except Exception as e:
            self.send_json(500, {"error": str(e)})
    
    def do_DELETE(self):
        parsed = urlparse(self.path)
        path = parsed.path
        
        try:
            session = self.require_auth()
            if not session:
                return
            
            role = session.get("role", "admin")
            is_vip = self.is_vip_reseller(session) if role == "reseller" else False
            
            if path.startswith("/api/users/"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                uname = path.split("/")[3]
                try:
                    delete_user(uname)
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            elif path.startswith("/api/resellers/"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"})
                    return
                uname = path.split("/")[3]
                try:
                    delete_reseller_account(uname)
                    self.send_json(200, {"success": True})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
            
            else:
                self.send_json(404, {"error": "Not Found"})
        
        except Exception as e:
            self.send_json(500, {"error": str(e)})

# ================================================================
# SESSION CLEANUP
# ================================================================
def cleanup_sessions():
    now = time.time()
    expired = [t for t, s in sessions.items() if now - s.get("created_at", 0) > 86400]
    for t in expired:
        del sessions[t]
    if expired:
        save_sessions()

# ================================================================
# MAIN
# ================================================================
def main():
    for d in [BASE_DIR, USER_DB, BANDWIDTH_DIR, CONN_DB, BANNED_DB, DELETED_DB,
              EXPIRED_DB, RESELLER_DB, RESELLER_REQUESTS_DB, USER_MSG_DIR,
              f"{BASE_DIR}/panel", PIDTRACK_DIR, JUNK_DIR, LOGS_DIR,
              PACKAGE_REQUESTS_DIR, USER_ACTIVITY_DIR, RESELLER_USER_REQUESTS]:
        os.makedirs(d, exist_ok=True)
    
    if not os.path.exists(PANEL_CONFIG):
        default_pass = generate_password(12)
        creds = {
            "PANEL_USER": "admin",
            "PANEL_PASS_PLAIN": default_pass,
            "PANEL_PASS_HASH": hashlib.sha256(default_pass.encode()).hexdigest(),
            "PANEL_SECRET": "elitex",
            "PANEL_NAME": "ELITE-X",
            "PANEL_LOGO": ""
        }
        save_panel_creds(creds)
        print(f"Default credentials - User: admin, Password: {default_pass}", flush=True)
    
    script_dir = os.path.dirname(os.path.abspath(__file__))
    html_source = os.path.join(script_dir, "panel.html")
    if os.path.exists(html_source):
        if os.path.abspath(html_source) != os.path.abspath(PANEL_HTML):
            shutil.copy2(html_source, PANEL_HTML)
            print(f"Copied HTML to {PANEL_HTML}", flush=True)
    
    server = ThreadingHTTPServer(("0.0.0.0", PANEL_PORT), EliteXHandler)
    ip = get_server_ip()
    print(f"ELITE-X Panel v8 running on port {PANEL_PORT}", flush=True)
    print(f"URL: http://{ip}:{PANEL_PORT}", flush=True)
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()

if __name__ == "__main__":
    main()