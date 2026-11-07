#!/usr/bin/env python3
"""
ELITE-X Web Panel v8 LITE - optimized for 512MB RAM / 1 vCPU
- Light TTL cache for heavy /proc scans
- No external network calls per request
- Single ssh banner-sync script (no per-user ssh calls)
"""

import os
import json
import time
import subprocess
import secrets
import hashlib
import re
import glob
import shutil
import pwd
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from http import cookies
from urllib.parse import urlparse
from datetime import datetime, timedelta
from collections import defaultdict

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
PANEL_HTML = f"{BASE_DIR}/panel/panel.html"
SUBDOMAIN_FILE = f"{BASE_DIR}/subdomain"
MTU_FILE = f"{BASE_DIR}/mtu"
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
BANNER_SYNC = "/usr/local/bin/elite-x-banner-sync"
VIP_PACKAGE_ID = "vip"
VIP_PRICE = 20000

# ================================================================
# LIGHT TTL CACHE (keeps CPU low on 1 vCPU)
# ================================================================
_cache = {}
_cache_lock = __import__("threading").Lock()

def cached(key, ttl, fn):
    now = time.time()
    with _cache_lock:
        hit = _cache.get(key)
        if hit and now - hit[0] < ttl:
            return hit[1]
    val = fn()
    with _cache_lock:
        _cache[key] = (now, val)
    return val

def invalidate(*keys):
    with _cache_lock:
        for k in keys:
            _cache.pop(k, None)

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
# UTILITY
# ================================================================
def run_cmd(cmd, ignore_errors=False, timeout=15):
    try:
        if isinstance(cmd, str):
            res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
        else:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
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
    return read_file(f"{BASE_DIR}/cached_ip", "") or "Unknown"

def get_public_key():
    return read_file(f"{BASE_DIR}/public_key", "")

def get_nameserver():
    ns = read_file(NAMESERVER_FILE, "")
    if not ns:
        ns = read_file(SUBDOMAIN_FILE, "")
    return ns

SERVICES = {"dnstt-elite-x": "dnstt", "elite-x-monitor": "monitor",
            "ssh": "ssh", "elite-x-panel": "panel"}

def _services_raw():
    names = list(SERVICES)
    _, out, _ = run_cmd(["systemctl", "is-active"] + names)
    states = out.split()
    result = {}
    for i, n in enumerate(names):
        result[SERVICES[n]] = (i < len(states) and states[i] == "active")
    if not result.get("ssh"):
        _, out2, _ = run_cmd(["systemctl", "is-active", "sshd"])
        result["ssh"] = (out2.strip() == "active")
    return result

def get_services_status():
    return cached("svc", 30, _services_raw)

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
        except Exception:
            pass
    while len(data) < 7:
        data.append(0)
    return data[-7:]

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

def _get_all_activity_raw(limit):
    all_activity = []
    if not os.path.exists(USER_ACTIVITY_DIR):
        return all_activity
    for fname in os.listdir(USER_ACTIVITY_DIR):
        fpath = f"{USER_ACTIVITY_DIR}/{fname}"
        if os.path.isfile(fpath):
            try:
                with open(fpath, "r") as f:
                    lines = f.readlines()[-20:]
                for line in lines:
                    parts = line.strip().split("|")
                    if len(parts) >= 3:
                        all_activity.append({"user": fname, "time": parts[0], "action": parts[1], "ip": parts[2]})
            except Exception:
                continue
    all_activity.sort(key=lambda x: x["time"], reverse=True)
    return all_activity[:limit]

def get_all_activity(limit=50):
    return cached(f"act{limit}", 30, lambda: _get_all_activity_raw(limit))

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

def _get_all_users_raw():
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

def get_all_users():
    # list(...) is important: callers append pending items to this list
    return list(cached("allusers", 5, _get_all_users_raw))

def get_users_by_reseller(reseller):
    return [u for u in get_all_users() if u.get("Owner", "") == reseller]

def get_user_bandwidth(username):
    return read_file_int(f"{BANDWIDTH_DIR}/{username}.usage", 0)

def get_user_daily_bandwidth(username):
    return read_file_int(f"{BANDWIDTH_DIR}/{username}.daily_usage", 0)

def _scan_conn_map():
    counts = defaultdict(int)
    for pid_dir in glob.glob("/proc/[0-9]*/"):
        try:
            with open(pid_dir + "comm") as f:
                if f.read().strip() != "sshd":
                    continue
            with open(pid_dir + "stat") as f:
                parts = f.read().rsplit(")", 1)[1].split()
            if parts[1] == "1":  # ppid
                continue
            uid = None
            with open(pid_dir + "status") as f:
                for line in f:
                    if line.startswith("Uid:"):
                        uid = int(line.split()[1])
                        break
            if uid:
                counts[uid] += 1
        except Exception:
            continue
    return dict(counts)

def conn_map():
    # one /proc scan every 5 seconds, regardless of how many users exist
    return cached("connmap", 5, _scan_conn_map)

def get_user_connections(username):
    try:
        uid = pwd.getpwnam(username).pw_uid
    except KeyError:
        return 0
    return conn_map().get(uid, 0)

def _locked_set():
    s = set()
    try:
        with open("/etc/shadow") as f:
            for line in f:
                p = line.split(":")
                if len(p) > 1 and p[1].startswith("!"):
                    s.add(p[0])
    except Exception:
        pass
    return s

def is_user_locked(username):
    return username in cached("locked", 10, _locked_set)

def is_user_expired(info):
    expire = info.get("Expire", "")
    if not expire or expire == "Never":
        return False
    try:
        return datetime.strptime(expire, "%Y-%m-%d") < datetime.now()
    except ValueError:
        return False

def user_exists_system(username):
    try:
        pwd.getpwnam(username)
        return True
    except KeyError:
        return False

def create_system_user(username, password, expire_date, shell="/bin/sh"):
    run_cmd(["useradd", "-m", "-s", shell, username])
    run_cmd(f"echo '{username}:{password}' | chpasswd")
    run_cmd(["usermod", "-U", username])
    run_cmd(["chage", "-E", expire_date, username])
    return True

def delete_system_user(username):
    run_cmd(["pkill", "-KILL", "-u", username], ignore_errors=True)
    run_cmd(["userdel", "-r", username], ignore_errors=True)
    return True

def save_user_info(username, info):
    os.makedirs(USER_DB, exist_ok=True)
    with open(f"{USER_DB}/{username}", "w") as f:
        for k, v in info.items():
            f.write(f"{k}: {v}\n")

def create_user(username, password, days, conn_limit, bandwidth_gb=0, daily_limit_gb=0,
                speed_limit_mbps=0, owner="admin", package_name="", package_price=0, is_vip=False):
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
    write_file(f"{BANDWIDTH_DIR}/{username}.usage", "0")
    write_file(f"{BANDWIDTH_DIR}/{username}.daily_usage", "0")
    write_file(f"{CONN_DB}/{username}", "0")
    log_user_activity(username, f"Created by {owner}")
    invalidate("allusers", "banner")
    run_cmd([BANNER_SYNC], ignore_errors=True)
    return info

def update_user(username, data):
    info = get_user_info(username)
    if not info:
        raise ValueError("User not found")
    if data.get("password"):
        run_cmd(f"echo '{username}:{data['password']}' | chpasswd")
        info["Password"] = data["password"]
    if "bandwidth_gb" in data:
        info["Bandwidth_GB"] = str(data["bandwidth_gb"])
    if "daily_limit_gb" in data:
        info["Daily_Limit"] = str(data["daily_limit_gb"])
    if "conn_limit" in data:
        info["Conn_Limit"] = str(data["conn_limit"])
    if data.get("days", 0) > 0:
        current = info.get("Expire", datetime.now().strftime("%Y-%m-%d"))
        try:
            exp_date = datetime.strptime(current, "%Y-%m-%d")
        except ValueError:
            exp_date = datetime.now()
        new_expire = (exp_date + timedelta(days=data["days"])).strftime("%Y-%m-%d")
        info["Expire"] = new_expire
        run_cmd(["chage", "-E", new_expire, username])
    save_user_info(username, info)
    invalidate("allusers", "banner")
    run_cmd([BANNER_SYNC], ignore_errors=True)
    return info

def delete_user(username):
    usage = get_user_bandwidth(username)
    daily = get_user_daily_bandwidth(username)
    today = datetime.now().strftime("%Y-%m-%d")
    with open(GLOBAL_BW_LOG, "a") as f:
        f.write(f"{usage} {username} {today}\n")
    with open(GLOBAL_DAILY_LOG, "a") as f:
        f.write(f"{today} {daily} {username}\n")

    # delegate to the same script the monitor uses (single source of truth)
    run_cmd(["/usr/local/bin/elite-x-del", username, "panel"], ignore_errors=True)
    invalidate("allusers", "banner")
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
    rm_flags = [f"{BANDWIDTH_DIR}/{username}.daily_locked",
                f"{BANDWIDTH_DIR}/{username}.locked_quota"]
    for f in rm_flags:
        if os.path.exists(f):
            os.remove(f)
    log_user_activity(username, f"Renewed +{days} days")
    invalidate("allusers", "banner")
    run_cmd([BANNER_SYNC], ignore_errors=True)
    return new_expire

def lock_user(username):
    run_cmd(["/usr/local/bin/elite-x-lock", username, "manual", "panel"], ignore_errors=True)
    log_user_activity(username, "Locked")
    invalidate("locked", "allusers")
    return True

def unlock_user(username):
    run_cmd(["usermod", "-U", username])
    for f in [f"{BANDWIDTH_DIR}/{username}.daily_locked",
              f"{BANDWIDTH_DIR}/{username}.locked_quota"]:
        if os.path.exists(f):
            os.remove(f)
    log_user_activity(username, "Unlocked")
    invalidate("locked", "allusers")
    run_cmd([BANNER_SYNC], ignore_errors=True)
    return True

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

def create_reseller_account(username, password, brand, phone="", email="", firstname="", lastname="", is_vip=False):
    if not re.match(r'^[a-zA-Z0-9_\-]{3,32}$', username):
        raise ValueError("Invalid username (3-32 chars, alphanumeric/underscore/hyphen)")
    for r in get_all_resellers():
        if (r.get("USERNAME") or r.get("NAME") or r.get("_filename", "")) == username:
            raise ValueError(f"Reseller '{username}' already exists")
    expire = calculate_expire_date(30)
    pwd_hash = hashlib.sha256(password.encode()).hexdigest()
    info = {
        "USERNAME": username, "NAME": username,
        "FIRSTNAME": firstname or username, "LASTNAME": lastname,
        "BRAND": brand, "PHONE": phone, "EMAIL": email,
        "PASSWORD": password, "PASSWORD_HASH": pwd_hash,
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
        else:
            new_lines.append(line)
    with open(path, "w") as f:
        f.writelines(new_lines)
    return True

def toggle_reseller(username):
    for r in get_all_resellers():
        if r.get("NAME") == username or r.get("username") == username:
            new_val = "0" if r.get("ENABLED", "1") == "1" else "1"
            path = f"{RESELLER_DB}/{r.get('_filename')}"
            with open(path, "r") as f:
                lines = f.readlines()
            with open(path, "w") as f:
                for line in lines:
                    f.write(f"ENABLED={new_val}\n" if line.startswith("ENABLED=") else line)
            return {"enabled": new_val == "1"}
    raise ValueError("Reseller not found")

def delete_reseller_account(username):
    path = f"{RESELLER_DB}/{username}"
    if os.path.exists(path):
        os.remove(path)
    return True

# ================================================================
# RESELLER USER REQUESTS
# ================================================================
def create_reseller_user_request(reseller, action, data):
    os.makedirs(RESELLER_USER_REQUESTS, exist_ok=True)
    req_id = f"{reseller}_{action}_{int(time.time())}"
    req = {
        "id": req_id, "reseller": reseller, "action": action, "data": data,
        "status": "pending", "created_at": time.time(),
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
    try:
        if action == "create":
            result = create_user(
                data["username"], data.get("password") or generate_password(),
                data.get("days", 30), data.get("conn_limit", 1),
                data.get("bandwidth_gb", 0), data.get("daily_limit_gb", 0),
                0, req["reseller"])
        elif action == "renew":
            result = renew_user(data["username"], data["days"])
        elif action == "edit":
            result = update_user(data["username"], data)
        elif action == "lock":
            result = lock_user(data["username"])
        elif action == "unlock":
            result = unlock_user(data["username"])
        else:
            raise ValueError("Unknown action")
    except Exception as e:
        raise ValueError(f"Failed to process request: {e}")
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
    {"id": "starter", "name": "Starter", "days": 7, "reseller_price": 5000, "conn_limit": 1, "bandwidth_gb": 0, "daily_limit_gb": 0},
    {"id": "basic", "name": "Basic", "days": 14, "reseller_price": 8500, "conn_limit": 1, "bandwidth_gb": 0, "daily_limit_gb": 0},
    {"id": "premium", "name": "Premium", "days": 30, "reseller_price": 15000, "conn_limit": 2, "bandwidth_gb": 0, "daily_limit_gb": 0},
    {"id": "vip", "name": "VIP", "days": 30, "reseller_price": 20000, "conn_limit": 999, "bandwidth_gb": 0, "daily_limit_gb": 0, "is_vip": True},
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
    attempts = 1
    for r in existing:
        if r.get("reseller") == reseller and r.get("ssh_username") == ssh_username:
            if r.get("status") == "pending":
                raise ValueError(f"User '{ssh_username}' already has a pending request")
            if r.get("status") == "banned":
                raise ValueError(f"User '{ssh_username}' is banned. Too many failed attempts.")
            attempts = max(attempts, r.get("attempts", 0) + 1)
    if attempts > 3:
        raise ValueError(f"Too many failed attempts for '{ssh_username}'. Account banned.")

    is_vip = package_id == "vip"
    os.makedirs(PACKAGE_REQUESTS_DIR, exist_ok=True)
    req_id = f"{reseller}_{package_id}_{int(time.time())}"
    req = {
        "id": req_id, "reseller": reseller, "package_id": package_id,
        "package_name": pkg["name"], "days": pkg["days"], "conn_limit": pkg["conn_limit"],
        "bandwidth_gb": pkg.get("bandwidth_gb", 0), "daily_limit_gb": pkg.get("daily_limit_gb", 0),
        "reseller_price": pkg["reseller_price"], "ssh_username": ssh_username,
        "ssh_password": ssh_password or generate_password(), "payment_ref": payment_ref,
        "status": "approved" if is_vip else "pending", "attempts": attempts,
        "created_at": time.time(), "created_str": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "is_vip": is_vip
    }
    if is_vip:
        try:
            info = create_user(ssh_username, req["ssh_password"], pkg["days"], pkg["conn_limit"],
                               pkg.get("bandwidth_gb", 0), pkg.get("daily_limit_gb", 0), 0,
                               reseller, pkg["name"], pkg["reseller_price"], True)
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
    try:
        info = create_user(req["ssh_username"], req["ssh_password"], req["days"], req["conn_limit"],
                           req.get("bandwidth_gb", 0), req.get("daily_limit_gb", 0), 0,
                           req["reseller"], req.get("package_name", ""),
                           req.get("reseller_price", 0), req.get("is_vip", False))
    except Exception as e:
        raise ValueError(f"Failed to create user: {e}")
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
def _os_name():
    try:
        with open("/etc/os-release") as f:
            for line in f:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except Exception:
        pass
    return ""

def _uptime():
    try:
        with open("/proc/uptime") as f:
            secs = int(float(f.read().split()[0]))
        d, r = divmod(secs, 86400); h, r = divmod(r, 3600); m = r // 60
        parts = []
        if d: parts.append(f"{d}d")
        if h: parts.append(f"{h}h")
        parts.append(f"{m}m")
        return " ".join(parts)
    except Exception:
        return "Unknown"

def _mem():
    total = avail = 0
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                if line.startswith("MemTotal:"):
                    total = int(line.split()[1]) // 1024
                elif line.startswith("MemAvailable:"):
                    avail = int(line.split()[1]) // 1024
    except Exception:
        pass
    used = total - avail
    pct = round(used / total * 100, 1) if total else 0
    return {"ram_total_mb": total, "ram_used_mb": used, "ram_percent": pct}

def _cpu_load():
    try:
        with open("/proc/loadavg") as f:
            return round(float(f.read().split()[0]), 2)
    except Exception:
        return 0

def get_dashboard_data_for_user(username, role="admin"):
    result = {
        "username": username,
        "password": "",
        "nameserver": get_nameserver(),
        "public_key": get_public_key(),
        "expire_date": "",
        "expire_percent": 0,
        "bandwidth_limit_gb": 0, "bandwidth_used_gb": 0, "bandwidth_percent": 0,
        "daily_limit_gb": 0, "daily_used_gb": 0, "daily_percent": 0,
        "total_users": 0, "online_sessions": 0,
        "cpu_load": _cpu_load(),
        "server_ip": get_server_ip(),
        "os_name": _os_name(),
        "uptime": _uptime(),
        "services": get_services_status(),
        "chart_data": get_chart_data(username),
        "commission": 0,
        "activity": get_all_activity(10),
        "package": "Standard"
    }
    result.update(_mem())

    if role == "reseller":
        for r in get_all_resellers():
            r_name = r.get("USERNAME") or r.get("NAME") or r.get("username") or r.get("_filename", "")
            if r_name == username:
                result["password"] = r.get("PASSWORD", "")
                result["expire_date"] = r.get("EXPIRE", "")
                result["package"] = "VIP" if r.get("VIP", "0") == "1" else "Standard"
                break
    else:
        creds = get_panel_creds()
        result["password"] = creds.get("PANEL_PASS_PLAIN", "")
        result["expire_date"] = "N/A"
        result["package"] = "Admin"

    expire_date = result["expire_date"]
    if expire_date and expire_date != "N/A":
        try:
            exp_ts = datetime.strptime(expire_date, "%Y-%m-%d")
            elapsed = (datetime.now() - (exp_ts - timedelta(days=30))).days
            result["expire_percent"] = min(max(elapsed / 30 * 100, 0), 100)
        except Exception:
            pass

    all_users = get_all_users()
    if role == "reseller":
        mine = [u for u in all_users if u.get("Owner", "") == username]
        result["total_users"] = len(mine)
        for u in mine:
            un = u.get("username", "")
            bw_gb = get_user_bandwidth(un) / 1073741824
            bw_limit = float(u.get("Bandwidth_GB", 0))
            result["bandwidth_used_gb"] = round(result["bandwidth_used_gb"] + bw_gb, 2)
            result["bandwidth_limit_gb"] = result["bandwidth_limit_gb"] + bw_limit
            daily_gb = get_user_daily_bandwidth(un) / 1073741824
            result["daily_used_gb"] = round(result["daily_used_gb"] + daily_gb, 2)
            result["daily_limit_gb"] = result["daily_limit_gb"] + float(u.get("Daily_Limit", 0))
        if result["bandwidth_limit_gb"] > 0:
            result["bandwidth_percent"] = min(100, result["bandwidth_used_gb"] / result["bandwidth_limit_gb"] * 100)
        if result["daily_limit_gb"] > 0:
            result["daily_percent"] = min(100, result["daily_used_gb"] / result["daily_limit_gb"] * 100)
    else:
        result["total_users"] = len(all_users)

    # one conn_map() call total, not one per user
    cmap = conn_map()
    online = 0
    for u in all_users:
        try:
            online += cmap.get(pwd.getpwnam(u.get("username", "")).pw_uid, 0)
        except KeyError:
            pass
    result["online_sessions"] = online
    return result

# ================================================================
# PANEL CREDENTIALS
# ================================================================
def get_panel_creds():
    creds = {
        "PANEL_USER": "admin", "PANEL_PASS_HASH": "", "PANEL_PASS_PLAIN": "",
        "PANEL_SECRET": "elitex", "PANEL_NAME": "ELITE-X", "PANEL_LOGO": ""
    }
    if os.path.exists(PANEL_CONFIG):
        with open(PANEL_CONFIG, "r") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.split("#")[0].strip().strip('"').strip("'").strip()
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
# HTTP HANDLER
# ================================================================
class EliteXHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, format, *args):
        pass

    def send_json(self, status, data, extra_headers=None):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-cache, no-store, must-revalidate")
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
                return sessions.get(C["session"].value)
        return None

    def require_auth(self):
        session = self.get_session()
        if not session:
            self.send_json(401, {"error": "Unauthorized"})
            return None
        return session

    def require_reseller(self, session):
        if session.get("role") != "reseller":
            self.send_json(403, {"error": "Reseller access required"})
            return False
        return True

    def is_vip_reseller(self, session):
        if session.get("role") != "reseller":
            return False
        for r in get_all_resellers():
            if r.get("username") == session.get("username"):
                return r.get("VIP", "0") == "1"
        return False

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0) or 0)
        raw = self.rfile.read(length) if length else b""
        try:
            return json.loads(raw.decode("utf-8")) if raw else {}
        except (json.JSONDecodeError, UnicodeDecodeError):
            return {}

    def do_GET(self):
        path = urlparse(self.path).path
        try:
            creds = get_panel_creds()
            secret = creds.get("PANEL_SECRET", "").strip().lstrip("/")
            secret_url = f"/{secret}" if secret else None
            if path in ("/", "/index.html") or (secret_url and path == secret_url):
                if os.path.exists(PANEL_HTML):
                    with open(PANEL_HTML, "rb") as f:
                        content = f.read()
                    self.send_response(200)
                    self.send_header("Content-Type", "text/html; charset=utf-8")
                    self.send_header("Content-Length", str(len(content)))
                    self.send_header("Cache-Control", "no-cache")
                    self.end_headers()
                    self.wfile.write(content)
                else:
                    self.send_json(404, {"error": "panel.html not found"})
                return

            session = self.require_auth()
            if not session:
                return
            username = session.get("username", "")
            role = session.get("role", "admin")
            is_vip = self.is_vip_reseller(session)

            if path == "/api/me":
                pkg = ("VIP" if is_vip else "Standard") if role == "reseller" else "Admin"
                self.send_json(200, {"username": username, "role": role,
                                     "panel_name": creds.get("PANEL_NAME", "ELITE-X"),
                                     "panel_logo": creds.get("PANEL_LOGO", ""), "package": pkg})

            elif path == "/api/dashboard":
                self.send_json(200, get_dashboard_data_for_user(username, role))

            elif path == "/api/users":
                users = get_all_users()
                pending = [r for r in get_reseller_user_requests() if r.get("status") == "pending"]
                scoped = role == "reseller" and not is_vip
                if scoped:
                    users = [u for u in users if u.get("Owner", "") == username]
                for r in pending:
                    if scoped and r.get("reseller") != username:
                        continue
                    d = r.get("data", {})
                    users.append({
                        "username": d.get("username", "pending"), "Password": "****",
                        "Expire": "Pending", "Conn_Limit": d.get("conn_limit", 1),
                        "Bandwidth_GB": d.get("bandwidth_gb", 0), "Daily_Limit": d.get("daily_limit_gb", 0),
                        "status": f"pending-{r.get('action')}" if r.get("action") != "create" else "pending",
                        "Owner": r.get("reseller", "admin"),
                        "Package": d.get("package_name", ""), "Package_Price": d.get("package_price", 0),
                        "Purchase_Date": r.get("created_str", ""), "_pending": True
                    })
                cmap = conn_map()
                result = []
                for u in users:
                    un = u.get("username", "")
                    pending_item = u.get("_pending", False)
                    try:
                        conns = 0 if pending_item else cmap.get(pwd.getpwnam(un).pw_uid, 0)
                    except KeyError:
                        conns = 0
                    result.append({
                        "username": un,
                        "password": u.get("Password", ""),
                        "expire_date": u.get("Expire", ""),
                        "conn_limit": int(u.get("Conn_Limit", 1) or 1),
                        "bandwidth_gb": float(u.get("Bandwidth_GB", 0) or 0),
                        "bandwidth_used": get_user_bandwidth(un),
                        "daily_limit_gb": float(u.get("Daily_Limit", 0) or 0),
                        "daily_used": get_user_daily_bandwidth(un),
                        "connections": conns,
                        "is_locked": False if pending_item else is_user_locked(un),
                        "is_expired": is_user_expired(u),
                        "owner": u.get("Owner", "admin"),
                        "status": u.get("status", ""),
                        "reject_reason": u.get("reject_reason", ""),
                        "package_name": u.get("Package", ""),
                        "package_price": u.get("Package_Price", 0),
                        "purchase_date": u.get("Purchase_Date", ""),
                        "vip": u.get("VIP", "0") == "1",
                    })
                self.send_json(200, {"users": result})

            elif path == "/api/reseller/packages":
                if not self.require_reseller(session):
                    return
                reqs = [r for r in get_package_requests() if r.get("reseller") == username]
                user_reqs = [r for r in get_reseller_user_requests() if r.get("reseller") == username]
                self.send_json(200, {"packages": get_packages(), "requests": reqs, "user_requests": user_reqs})

            elif path == "/api/admin/requests":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"}); return
                all_reqs = get_package_requests() + get_reseller_user_requests()
                all_reqs.sort(key=lambda x: x.get("created_at", 0), reverse=True)
                self.send_json(200, {"requests": all_reqs})

            elif path == "/api/resellers":
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"}); return
                all_users = get_all_users()
                cmap = conn_map()
                user_counts = defaultdict(int)
                online_counts = defaultdict(int)
                bw_totals = defaultdict(float)
                for u in all_users:
                    owner = u.get("Owner", "admin")
                    un = u.get("username", "")
                    user_counts[owner] += 1
                    try:
                        if cmap.get(pwd.getpwnam(un).pw_uid, 0) > 0:
                            online_counts[owner] += 1
                    except KeyError:
                        pass
                    bw_totals[owner] += get_user_bandwidth(un)
                out = []
                for r in get_all_resellers():
                    name = r.get("NAME") or r.get("username", "")
                    out.append({
                        "username": name, "brand": r.get("BRAND", ""), "phone": r.get("PHONE", ""),
                        "email": r.get("EMAIL", ""), "expire_date": r.get("EXPIRE", ""),
                        "max_users": int(r.get("MAX_USERS", 5) or 5),
                        "created_users": user_counts.get(name, 0),
                        "online_users": online_counts.get(name, 0),
                        "total_bandwidth_gb": round(bw_totals.get(name, 0) / 1073741824, 2),
                        "enabled": r.get("ENABLED", "1") == "1",
                        "is_expired": is_user_expired({"Expire": r.get("EXPIRE", "")}),
                        "package": "VIP" if r.get("VIP", "0") == "1" else "Standard",
                    })
                self.send_json(200, {"resellers": out})

            elif path.startswith("/api/reseller/users/"):
                if role == "reseller" and not is_vip:
                    self.send_json(403, {"error": "Access denied"}); return
                reseller_name = path.split("/")[4]
                mine = [u for u in get_all_users() if u.get("Owner", "") == reseller_name]
                cmap = conn_map()
                out = []
                for u in mine:
                    un = u.get("username", "")
                    try:
                        conns = cmap.get(pwd.getpwnam(un).pw_uid, 0)
                    except KeyError:
                        conns = 0
                    out.append({
                        "username": un, "password": u.get("Password", ""),
                        "expire_date": u.get("Expire", ""),
                        "conn_limit": int(u.get("Conn_Limit", 1) or 1),
                        "bandwidth_gb": float(u.get("Bandwidth_GB", 0) or 0),
                        "bandwidth_used": get_user_bandwidth(un),
                        "daily_limit_gb": float(u.get("Daily_Limit", 0) or 0),
                        "daily_used": get_user_daily_bandwidth(un),
                        "connections": conns, "is_locked": is_user_locked(un),
                        "is_expired": is_user_expired(u),
                        "package_name": u.get("Package", ""), "package_price": u.get("Package_Price", 0),
                        "purchase_date": u.get("Purchase_Date", ""),
                        "vip": u.get("VIP", "0") == "1",
                    })
                self.send_json(200, {"users": out})

            elif path == "/api/user/activity":
                uname = urlparse(self.path).query.split("=")[-1] if "=" in urlparse(self.path).query else ""
                if not uname:
                    self.send_json(400, {"error": "Username required"}); return
                if role == "reseller" and not is_vip:
                    info = get_user_info(uname)
                    if info and info.get("Owner", "") != username:
                        self.send_json(403, {"error": "Not your user"}); return
                self.send_json(200, {"activity": get_user_activity(uname)})

            else:
                self.send_json(404, {"error": "Not Found"})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def do_POST(self):
        path = urlparse(self.path).path
        body = self._read_body()
        try:
            if path == "/api/login":
                return self._handle_login(body)
            if path == "/api/logout":
                if "Cookie" in self.headers:
                    C = cookies.SimpleCookie(self.headers["Cookie"])
                    if "session" in C and C["session"].value in sessions:
                        del sessions[C["session"].value]
                        save_sessions()
                self.send_json(200, {"success": True},
                               {"Set-Cookie": "session=; Path=/; HttpOnly; Max-Age=0"})
                return

            if path == "/api/reseller/register":
                try:
                    fields = {k: body.get(k, "").strip() for k in
                              ("firstname", "lastname", "phone", "email", "username", "brand")}
                    if not all(fields.values()):
                        self.send_json(400, {"error": "All fields are required"}); return
                    password = body.get("password", "").strip() or generate_password()
                    create_reseller_account(fields["username"], password, fields["brand"],
                                            fields["phone"], fields["email"],
                                            fields["firstname"], fields["lastname"])
                    token = secrets.token_hex(32)
                    sessions[token] = {"username": fields["username"], "role": "reseller", "created_at": time.time()}
                    save_sessions()
                    self.send_json(200, {"success": True, "username": fields["username"], "password": password},
                                   {"Set-Cookie": f"session={token}; Path=/; HttpOnly; Max-Age=86400"})
                except Exception as e:
                    self.send_json(400, {"error": str(e)})
                return

            session = self.require_auth()
            if not session:
                return
            return self._handle_authed_post(path, body, session)
        except Exception as e:
            self.send_json(500, {"error": str(e)})

    def _handle_login(self, body):
        username = body.get("username", "")
        password = body.get("password", "")
        pwd_hash = hashlib.sha256(password.encode()).hexdigest()
        creds = get_panel_creds()
        if username == creds.get("PANEL_USER") and pwd_hash == creds.get("PANEL_PASS_HASH"):
            token = secrets.token_hex(32)
            sessions[token] = {"username": username, "role": "admin", "created_at": time.time()}
            save_sessions()
            return self.send_json(200, {"success": True, "role": "admin"},
                                  {"Set-Cookie": f"session={token}; Path=/; HttpOnly; Max-Age=86400"})
        for r in get_all_resellers():
            r_name = r.get("USERNAME") or r.get("NAME") or r.get("username") or r.get("_filename", "")
            if r_name != username:
                continue
            if r.get("ENABLED", "1") == "0":
                return self.send_json(401, {"error": "Account disabled"})
            expire = r.get("EXPIRE", "")
            if expire:
                try:
                    if datetime.strptime(expire, "%Y-%m-%d") < datetime.now():
                        return self.send_json(401, {"error": "Account expired"})
                except ValueError:
                    pass
            stored_hash = r.get("PASSWORD_HASH", "")
            plain = r.get("PASSWORD", "")
            if not ((stored_hash and stored_hash == pwd_hash) or (plain and plain == password)):
                return self.send_json(401, {"error": "Invalid credentials"})
            token = secrets.token_hex(32)
            sessions[token] = {"username": r_name, "role": "reseller", "created_at": time.time()}
            save_sessions()
            return self.send_json(200, {"success": True, "role": "reseller"},
                                  {"Set-Cookie": f"session={token}; Path=/; HttpOnly; Max-Age=86400"})
        self.send_json(401, {"error": "Invalid credentials"})

    def _handle_authed_post(self, path, body, session):
        username = session.get("username", "")
        role = session.get("role", "admin")
        is_vip = self.is_vip_reseller(session)
        admin_only = lambda: role == "reseller" and not is_vip

        if path == "/api/users":
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            try:
                info = create_user(body.get("username", ""), body.get("password") or generate_password(),
                                   int(body.get("days", 30)), int(body.get("conn_limit", 1)),
                                   float(body.get("bandwidth_gb", 0)), float(body.get("daily_limit_gb", 0)),
                                   0, "admin")
                return self.send_json(200, {"success": True, "user": info})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        if path == "/api/reseller/request-user":
            if not self.require_reseller(session):
                return
            data = {
                "username": body.get("username", ""),
                "password": body.get("password", "") or generate_password(),
                "days": int(body.get("days", 30)),
                "conn_limit": int(body.get("conn_limit", 1)),
                "bandwidth_gb": float(body.get("bandwidth_gb", 0)),
                "daily_limit_gb": float(body.get("daily_limit_gb", 0)),
            }
            try:
                if is_vip:
                    info = create_user(data["username"], data["password"], data["days"], data["conn_limit"],
                                       data["bandwidth_gb"], data["daily_limit_gb"], 0, username)
                    return self.send_json(200, {"success": True, "user": info})
                req = create_reseller_user_request(username, "create", data)
                return self.send_json(200, {"success": True, "request": req})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        if path in ("/api/reseller/request-renew", "/api/reseller/request-edit",
                    "/api/reseller/request-lock", "/api/reseller/request-unlock"):
            if not self.require_reseller(session):
                return
            action = path.rsplit("-", 1)[1]
            if action == "renew":
                data = {"username": body.get("username", ""), "days": int(body.get("days", 30))}
            elif action == "edit":
                data = {"username": body.get("username", ""),
                        "password": body.get("password") or None,
                        "bandwidth_gb": float(body.get("bandwidth_gb", 0)),
                        "daily_limit_gb": float(body.get("daily_limit_gb", 0)),
                        "conn_limit": int(body.get("conn_limit", 1)),
                        "days": int(body.get("days", 0))}
            else:
                data = {"username": body.get("username", "")}
            try:
                if is_vip:
                    if action == "renew":
                        res = renew_user(data["username"], data["days"])
                    elif action == "edit":
                        res = update_user(data["username"], data)
                    elif action == "lock":
                        res = lock_user(data["username"])
                    else:
                        res = unlock_user(data["username"])
                    return self.send_json(200, {"success": True, "result": str(res)})
                req = create_reseller_user_request(username, action, data)
                return self.send_json(200, {"success": True, "request": req})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        m = re.match(r"^/api/admin/(user-requests|requests)/([^/]+)/(approve|reject)$", path)
        if m:
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            req_id, act = m.group(2), m.group(3)
            try:
                if os.path.exists(f"{PACKAGE_REQUESTS_DIR}/{req_id}"):
                    if act == "approve":
                        res = approve_package_request(req_id)
                    else:
                        reject_package_request(req_id, body.get("reason", ""))
                        res = {}
                elif os.path.exists(f"{RESELLER_USER_REQUESTS}/{req_id}"):
                    if act == "approve":
                        res = approve_reseller_user_request(req_id)
                    else:
                        reject_reseller_user_request(req_id, body.get("reason", ""))
                        res = {}
                else:
                    return self.send_json(404, {"error": "Request not found"})
                return self.send_json(200, {"success": True, **res})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        if path == "/api/reseller/request-package":
            if not self.require_reseller(session):
                return
            try:
                package_id = body.get("package_id", "").strip()
                ssh_username = body.get("ssh_username", "").strip()
                if not package_id or not ssh_username:
                    return self.send_json(400, {"error": "Package and SSH username required"})
                req = create_package_request(username, package_id, ssh_username,
                                             body.get("ssh_password", "").strip() or generate_password(),
                                             body.get("payment_ref", "").strip())
                return self.send_json(200, {"success": True, "request": req})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        if path == "/api/admin/create-user":
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            try:
                reseller_owner = body.get("reseller", "").strip()
                uname = body.get("username", "").strip()
                if not reseller_owner or not uname:
                    return self.send_json(400, {"error": "Reseller and username required"})
                if not any((r.get("USERNAME") or r.get("NAME") or r.get("_filename", "")) == reseller_owner
                           for r in get_all_resellers()):
                    return self.send_json(404, {"error": f"Reseller '{reseller_owner}' not found"})
                info = create_user(uname, body.get("password", "").strip() or generate_password(),
                                   int(body.get("days", 30)), int(body.get("conn_limit", 1)),
                                   float(body.get("bandwidth_gb", 0)), float(body.get("daily_limit_gb", 0)),
                                   0, reseller_owner)
                return self.send_json(200, {"success": True, "user": info})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        if path == "/api/resellers":
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            try:
                name = body.get("username", "").strip()
                if not name:
                    return self.send_json(400, {"error": "Username is required"})
                info = create_reseller_account(name, body.get("password", "").strip() or generate_password(),
                                               body.get("brand", name).strip(), body.get("phone", "").strip(),
                                               body.get("email", "").strip(), "", "", bool(body.get("is_vip", False)))
                return self.send_json(200, {"success": True, "reseller": info})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        m = re.match(r"^/api/resellers/([^/]+)(/toggle)?$", path)
        if m:
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            try:
                if m.group(2):
                    res = toggle_reseller(m.group(1))
                    return self.send_json(200, {"success": True, "enabled": res["enabled"]})
                update_reseller(m.group(1), body)
                return self.send_json(200, {"success": True})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        m = re.match(r"^/api/users/([^/]+)/(lock|unlock|renew)$", path)
        if m:
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            uname, act = m.group(1), m.group(2)
            try:
                if act == "lock":
                    lock_user(uname)
                elif act == "unlock":
                    unlock_user(uname)
                else:
                    new_expire = renew_user(uname, int(body.get("days", 30)))
                    return self.send_json(200, {"success": True, "expire_date": new_expire})
                return self.send_json(200, {"success": True})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        m = re.match(r"^/api/users/([^/]+)$", path)
        if m:
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            try:
                return self.send_json(200, {"success": True, "user": update_user(m.group(1), body)})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        if path == "/api/account":
            if role == "admin":
                creds = get_panel_creds()
                if "username" in body:
                    creds["PANEL_USER"] = body["username"]
                if "password" in body:
                    creds["PANEL_PASS_PLAIN"] = body["password"]
                    creds["PANEL_PASS_HASH"] = hashlib.sha256(body["password"].encode()).hexdigest()
                save_panel_creds(creds)
            else:
                for r in get_all_resellers():
                    if r.get("username") == username and body.get("password"):
                        p = f"{RESELLER_DB}/{r.get('_filename')}"
                        with open(p) as f:
                            lines = f.readlines()
                        with open(p, "w") as f:
                            for line in lines:
                                if line.startswith("PASSWORD="):
                                    f.write(f"PASSWORD={body['password']}\n")
                                elif line.startswith("PASSWORD_HASH="):
                                    f.write(f"PASSWORD_HASH={hashlib.sha256(body['password'].encode()).hexdigest()}\n")
                                else:
                                    f.write(line)
                        break
            return self.send_json(200, {"success": True})

        if path == "/api/reseller/settings":
            if not self.require_reseller(session):
                return
            try:
                for r in get_all_resellers():
                    if r.get("username") == username:
                        p = f"{RESELLER_DB}/{r.get('_filename')}"
                        with open(p) as f:
                            lines = f.readlines()
                        with open(p, "w") as f:
                            for line in lines:
                                if line.startswith("BRAND=") and "brand" in body:
                                    f.write(f"BRAND={body['brand']}\n")
                                elif line.startswith("PHONE=") and "phone" in body:
                                    f.write(f"PHONE={body['phone']}\n")
                                else:
                                    f.write(line)
                        break
                return self.send_json(200, {"success": True})
            except Exception as e:
                return self.send_json(400, {"error": str(e)})

        m = re.match(r"^/api/services/([^/]+)/restart$", path)
        if m:
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            # only allow the services this panel manages
            if m.group(1) not in ("dnstt-elite-x", "elite-x-monitor", "ssh", "sshd", "elite-x-panel"):
                return self.send_json(400, {"error": "Unknown service"})
            run_cmd(["systemctl", "restart", m.group(1)])
            invalidate("svc")
            return self.send_json(200, {"success": True})

        if path == "/api/services/restart-all":
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            for s in ("dnstt-elite-x", "elite-x-monitor", "ssh"):
                run_cmd(["systemctl", "restart", s])
            invalidate("svc")
            return self.send_json(200, {"success": True})

        if path == "/api/system/mtu":
            if role != "admin":
                return self.send_json(403, {"error": "Only admin can change MTU"})
            mtu = body.get("mtu")
            if not mtu:
                return self.send_json(400, {"error": "MTU value required"})
            try:
                mtu = int(mtu)
                if not 100 <= mtu <= 1800:
                    raise ValueError
            except ValueError:
                return self.send_json(400, {"error": "MTU must be 100-1800"})
            write_file(MTU_FILE, str(mtu))
            run_cmd(["sed", "-i", "-E", f"s|-mtu [0-9]+|-mtu {mtu}|",
                     "/etc/systemd/system/dnstt-elite-x.service"])
            run_cmd(["systemctl", "daemon-reload"])
            run_cmd(["systemctl", "restart", "dnstt-elite-x"])
            return self.send_json(200, {"success": True})

        if path == "/api/system/reboot":
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            self.send_json(200, {"success": True})
            subprocess.Popen(["sh", "-c", "sleep 2; reboot"])
            return

        if path == "/api/system/clear-junk":
            if admin_only():
                return self.send_json(403, {"error": "Access denied"})
            run_cmd(f"rm -rf {JUNK_DIR}/* 2>/dev/null; journalctl --vacuum-size=30M >/dev/null 2>&1")
            return self.send_json(200, {"success": True})

        self.send_json(404, {"error": "Not Found"})

    def do_DELETE(self):
        path = urlparse(self.path).path
        try:
            session = self.require_auth()
            if not session:
                return
            role = session.get("role", "admin")
            is_vip = self.is_vip_reseller(session)
            if role == "reseller" and not is_vip:
                return self.send_json(403, {"error": "Access denied"})

            m = re.match(r"^/api/users/([^/]+)$", path)
            if m:
                delete_user(m.group(1))
                return self.send_json(200, {"success": True})

            m = re.match(r"^/api/resellers/([^/]+)$", path)
            if m:
                delete_reseller_account(m.group(1))
                return self.send_json(200, {"success": True})

            self.send_json(404, {"error": "Not Found"})
        except Exception as e:
            self.send_json(500, {"error": str(e)})

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
        save_panel_creds({
            "PANEL_USER": "admin",
            "PANEL_PASS_PLAIN": default_pass,
            "PANEL_PASS_HASH": hashlib.sha256(default_pass.encode()).hexdigest(),
            "PANEL_SECRET": "elitex", "PANEL_NAME": "ELITE-X", "PANEL_LOGO": "",
        })
        print(f"Default credentials - User: admin, Password: {default_pass}", flush=True)

    # keep the HTML next to the script if a copy sits there
    script_dir = os.path.dirname(os.path.abspath(__file__))
    html_source = os.path.join(script_dir, "panel.html")
    if os.path.exists(html_source) and os.path.abspath(html_source) != os.path.abspath(PANEL_HTML):
        shutil.copy2(html_source, PANEL_HTML)

    server = ThreadingHTTPServer(("0.0.0.0", PANEL_PORT), EliteXHandler)
    server.daemon_threads = True
    print(f"ELITE-X Panel v8 LITE running on port {PANEL_PORT}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    server.server_close()

if __name__ == "__main__":
    main()