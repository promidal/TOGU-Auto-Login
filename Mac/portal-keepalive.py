#!/usr/bin/env python3
import getpass
import json
import os
import sys
import re
import subprocess
import time
import ssl
import urllib.request
import urllib.parse
from pathlib import Path

# Stamped from the git tag by the release workflow; "dev" builds skip the update check
VERSION = "dev"
REPO = "promidal/TOGU-Auto-Login"

HOME = Path.home()
# Legacy plaintext credentials; `login` moves them into the Keychain
ENV_FILE = HOME / ".portal.env"
CONFIG_FILE = HOME / ".portal-keepalive.json"
TOKEN_FILE = HOME / ".portal-token"
LOG_FILE = HOME / "portal-keepalive.log"
# Present while the portal rejects the saved password; keepalive stops trying until new credentials are entered
BAD_CREDS_FILE = HOME / ".portal-bad-credentials"
UPDATE_CHECK_FILE = HOME / ".portal-update-check.json"
KEYCHAIN_SERVICE = "PortalKeepalive"
CHANGE_PASSWORD_COMMAND = HOME / "Applications" / "PortalKeepalive" / "Şifreyi Değiştir.command"

BASE = "https://denetim.gop.edu.tr"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:158.0) Gecko/20100101 Firefox/158.0"


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} {msg}\n"
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line)
    # Under launchd stdout is the log file itself; only echo in a terminal
    if sys.stdout.isatty():
        print(line, end="")


def load_legacy_env():
    values = {}
    if not ENV_FILE.exists():
        return values
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            values[k.strip()] = v.strip()
    return values


def keychain_get(user):
    r = subprocess.run(
        ["security", "find-generic-password", "-s", KEYCHAIN_SERVICE, "-a", user, "-w"],
        capture_output=True, text=True,
    )
    return r.stdout.rstrip("\n") if r.returncode == 0 else None


def keychain_set(user, pwd):
    # Also drops the item of a previous username
    while subprocess.run(
        ["security", "delete-generic-password", "-s", KEYCHAIN_SERVICE], capture_output=True
    ).returncode == 0:
        pass
    subprocess.run(
        ["security", "add-generic-password", "-s", KEYCHAIN_SERVICE, "-a", user, "-w", pwd, "-U"],
        check=True, capture_output=True,
    )


def get_credentials():
    try:
        user = json.loads(CONFIG_FILE.read_text(encoding="utf-8")).get("username")
    except Exception:
        user = None
    if user:
        pwd = keychain_get(user)
        if pwd:
            return user, pwd
    env = load_legacy_env()
    if env.get("PORTAL_USER") and env.get("PORTAL_PASS"):
        return env["PORTAL_USER"], env["PORTAL_PASS"]
    return None


def prompt_credentials():
    user = ""
    while not user:
        user = input("Kullanıcı adı (kurumsal e-posta, örnek: isminiz.soyisminizXXXX@gop.edu.tr): ").strip()
    pwd = getpass.getpass("Parola: ")
    keychain_set(user, pwd)
    CONFIG_FILE.write_text(json.dumps({"username": user}), encoding="utf-8")
    if BAD_CREDS_FILE.exists():
        BAD_CREDS_FILE.unlink()
    if ENV_FILE.exists():
        ENV_FILE.unlink()
        log("Removed plaintext ~/.portal.env, credentials are in the Keychain now")
    log("Credentials saved")
    return user, pwd


def ssl_ctx():
    return ssl.create_default_context()


def http_get(url, timeout=15):
    req = urllib.request.Request(
        url,
        headers={
            "User-Agent": UA,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx()) as r:
        data = r.read()
        return data.decode("utf-8", "replace"), r.geturl()


def http_post(url, data, timeout=15):
    body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "User-Agent": UA,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    with urllib.request.urlopen(req, timeout=timeout, context=ssl_ctx()) as r:
        data = r.read()
        return data.decode("utf-8", "replace"), r.geturl()


def parse_inputs(html):
    inputs = {}
    for m in re.finditer(r"<input[^>]*>", html, re.I):
        tag = m.group(0)
        name = re.search(r'name="([^"]*)"', tag)
        value = re.search(r'value="([^"]*)"', tag)
        if name:
            inputs[name.group(1)] = value.group(1) if value else ""
    return inputs


def parse_token(html):
    m = re.search(r"keepalive\?([0-9a-fA-F]+)", html)
    if m:
        return m.group(1)
    m = re.search(r"logout\?([0-9a-fA-F]+)", html)
    if m:
        return m.group(1)
    return None


def internet_ok():
    # Apple's captive check: the portal intercepts it until we log in
    try:
        html, _ = http_get("http://captive.apple.com/hotspot-detect.html", timeout=5)
        return "<TITLE>Success</TITLE>" in html
    except Exception:
        return False


def is_login_page(html):
    return 'name="username"' in html or "Giriş Başarısız" in html


def login(user, pwd):
    html, _ = http_get(f"{BASE}/login?0")
    inputs = parse_inputs(html)

    if "username" in inputs:
        inputs["username"] = user
    else:
        for k in list(inputs.keys()):
            if any(x in k.lower() for x in ["user", "login", "tc", "kimlik", "kadi"]):
                inputs[k] = user

    if "password" in inputs:
        inputs["password"] = pwd
    else:
        for k in list(inputs.keys()):
            if any(x in k.lower() for x in ["pass", "sifre", "parola"]):
                inputs[k] = pwd

    html, _ = http_post(f"{BASE}/", inputs)

    if "Giriş Başarısız" in html or "Kullanıcı adı / parola hatalı" in html:
        BAD_CREDS_FILE.write_text(time.strftime("%Y-%m-%d %H:%M:%S"), encoding="utf-8")
        raise RuntimeError("Login failed: bad credentials")
    if is_login_page(html):
        raise RuntimeError("Login failed: still on login page")

    token = parse_token(html)
    if not token:
        raise RuntimeError("Login succeeded but no token found")

    TOKEN_FILE.write_text(token, encoding="utf-8")
    os.chmod(TOKEN_FILE, 0o600)
    log(f"Login OK, token={token}")
    return token


def keepalive_once(user, pwd):
    token = None
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text(encoding="utf-8").strip()

    if not token:
        if internet_ok():
            return  # off campus: internet works without the portal
        login(user, pwd)
        return

    try:
        html, _ = http_get(f"{BASE}/keepalive?{token}")
    except Exception as e:
        if internet_ok():
            log(f"Keepalive failed ({e}) but internet works, off campus; dropping token")
            TOKEN_FILE.unlink()
            return
        log(f"Keepalive request failed ({e}), attempting re-login")
        login(user, pwd)
        return

    if is_login_page(html):
        log("Session expired, re-login")
        login(user, pwd)
        return

    new_token = parse_token(html)
    if new_token and new_token != token:
        TOKEN_FILE.write_text(new_token, encoding="utf-8")
        os.chmod(TOKEN_FILE, 0o600)
        token = new_token

    log(f"Keepalive OK, token={token}")


def retry(func, attempts=3, delays=(5, 10, 20)):
    last = None
    for i in range(attempts):
        try:
            func()
            return True
        except Exception as e:
            last = e
            log(f"Attempt {i + 1}/{attempts} failed: {e}")
            # Retrying a rejected password only risks locking the account
            if BAD_CREDS_FILE.exists():
                break
            if i < attempts - 1:
                time.sleep(delays[i])
    log(f"All attempts failed: {last}")
    return False


def applescript_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def show_dialog(lines):
    # Own session: launchd kills the job's process group when the keepalive run exits,
    # and a waiting dialog must not hold up the next run either
    args = ["osascript"]
    for line in lines:
        args += ["-e", line]
    subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)


def notify_bad_credentials():
    button = "Şifreyi Değiştir"
    msg = (
        "Portal şifrenizi kabul etmedi; şifreniz değişmiş olabilir.\n\n"
        "Yeni şifrenizi girmek için 'Şifreyi Değiştir'e tıklayın "
        "(veya Uygulamalar > PortalKeepalive klasöründeki 'Şifreyi Değiştir' dosyasını açın).\n\n"
        "O zamana kadar otomatik giriş durduruldu."
    )
    show_dialog([
        f"set r to button returned of (display alert \"PortalKeepalive\" message {applescript_str(msg)} "
        f"as warning buttons {{\"Sonra\", {applescript_str(button)}}} default button 2)",
        f"if r is {applescript_str(button)} then do shell script \"open \" & quoted form of "
        f"{applescript_str(str(CHANGE_PASSWORD_COMMAND))}",
    ])


def parse_version(s):
    return tuple(int(x) for x in s.lstrip("v").split("."))


# At most once a day (GitHub allows 60 unauthenticated requests/hour); each new release is announced once
def check_update():
    if VERSION == "dev":
        return
    try:
        state = json.loads(UPDATE_CHECK_FILE.read_text(encoding="utf-8"))
    except Exception:
        state = {}
    if time.time() - state.get("last_check", 0) < 24 * 3600:
        return

    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/releases/latest",
        headers={"User-Agent": "PortalKeepalive", "Accept": "application/vnd.github+json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10, context=ssl_ctx()) as r:
            rel = json.loads(r.read().decode("utf-8"))
    except Exception:
        return  # behind the captive portal or offline: try again next run
    tag, url = rel.get("tag_name"), rel.get("html_url", "")
    if not tag:
        return

    state["last_check"] = time.time()
    try:
        newer = parse_version(tag) > parse_version(VERSION)
    except ValueError:
        newer = False
    announce = newer and state.get("notified") != tag and url.startswith("https://github.com/")
    if announce:
        state["notified"] = tag
    UPDATE_CHECK_FILE.write_text(json.dumps(state), encoding="utf-8")
    if not announce:
        return

    log(f"Update available: {tag} (installed {VERSION})")
    button = "İndirme sayfasını aç"
    msg = (
        f"PortalKeepalive için yeni sürüm yayınlandı: {tag} (kurulu sürüm: {VERSION}).\n\n"
        "İndirme sayfasından PortalKeepalive-Mac.zip dosyasını indirip içindeki install.sh'yi çalıştırmanız yeterli."
    )
    show_dialog([
        f"set r to button returned of (display dialog {applescript_str(msg)} "
        f"buttons {{\"Sonra\", {applescript_str(button)}}} default button 2 "
        f"with title \"PortalKeepalive - Güncelleme\" with icon note)",
        f"if r is {applescript_str(button)} then open location {applescript_str(url)}",
    ])


def login_interactive():
    # Always ask: this is how the user changes the saved username/password
    # (install.sh, or the "Şifreyi Değiştir" command in ~/Applications/PortalKeepalive)
    ok = False
    for _ in range(3):
        user, pwd = prompt_credentials()
        ok = retry(lambda: login(user, pwd))
        if ok or not BAD_CREDS_FILE.exists():
            break
        print("Kullanıcı adı veya parola hatalı, tekrar deneyin.")
    if ok:
        print("Giriş başarılı, bilgiler kaydedildi.")
    elif BAD_CREDS_FILE.exists():
        print("Giriş yapılamadı: kullanıcı adı veya parola hatalı.")
    else:
        print("Bilgiler kaydedildi ama şu an portala giriş yapılamadı (kampüs ağı dışında olabilirsiniz). "
              "Kampüs ağına bağlanınca otomatik giriş yapılacak.")


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "keepalive"
    if mode == "login":
        login_interactive()
        return

    creds = get_credentials()
    if not creds:
        log("No saved credentials; run: python3 ~/.portal-keepalive.py login")
        sys.exit(1)
    if BAD_CREDS_FILE.exists():
        sys.exit(1)  # already told the user; wait for new credentials
    retry(lambda: keepalive_once(*creds))
    try:
        check_update()
    except Exception as e:
        log(f"Update check failed: {e}")
    if BAD_CREDS_FILE.exists():
        notify_bad_credentials()


if __name__ == "__main__":
    main()
