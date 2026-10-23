#!/usr/bin/env python3
import os
import sys
import re
import time
import ssl
import urllib.request
import urllib.parse
from pathlib import Path

HOME = Path.home()
ENV_FILE = HOME / ".portal.env"
TOKEN_FILE = HOME / ".portal-token"
LOG_FILE = HOME / "portal-keepalive.log"

BASE = "https://denetim.gop.edu.tr"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:158.0) Gecko/20100101 Firefox/158.0"


def log(msg):
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"{ts} {msg}\n"
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line)
    print(line, end="")


def load_env():
    if not ENV_FILE.exists():
        raise RuntimeError(f"{ENV_FILE} not found")
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())


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


def is_login_page(html):
    return 'name="username"' in html or "Giriş Başarısız" in html


def login():
    html, _ = http_get(f"{BASE}/login?0")
    inputs = parse_inputs(html)

    user = os.environ.get("PORTAL_USER")
    pwd = os.environ.get("PORTAL_PASS")
    if not user or not pwd:
        raise RuntimeError("PORTAL_USER/PASS not set in ~/.portal.env")

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


def keepalive_once():
    token = None
    if TOKEN_FILE.exists():
        token = TOKEN_FILE.read_text(encoding="utf-8").strip()

    if not token:
        login()
        return

    try:
        html, _ = http_get(f"{BASE}/keepalive?{token}")
    except Exception as e:
        log(f"Keepalive request failed ({e}), attempting re-login")
        login()
        return

    if is_login_page(html):
        log("Session expired, re-login")
        login()
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
            if i < attempts - 1:
                time.sleep(delays[i])
    log(f"All attempts failed: {last}")
    return False


def main():
    load_env()
    mode = sys.argv[1] if len(sys.argv) > 1 else "keepalive"
    if mode == "login":
        retry(login)
    else:
        retry(keepalive_once)


if __name__ == "__main__":
    main()
