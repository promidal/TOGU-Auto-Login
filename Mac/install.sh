#!/bin/bash
# PortalKeepalive installer for macOS. Run from the unzipped folder: bash install.sh
# Running it again updates the program and asks for the username/password again.
set -euo pipefail
cd "$(dirname "$0")"

LABEL="com.serkan.portal-keepalive"
SCRIPT="$HOME/.portal-keepalive.py"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
APP_DIR="$HOME/Applications/PortalKeepalive"

# /usr/bin/python3 is only a stub until the Command Line Tools are installed
if ! /usr/bin/python3 -c "import ssl" >/dev/null 2>&1; then
    echo "python3 bulunamadı. Önce şunu çalıştırıp kurulumu tamamlayın, sonra tekrar deneyin:"
    echo "    xcode-select --install"
    exit 1
fi

install -m 700 portal-keepalive.py "$SCRIPT"

# Double-clickable helpers (Finder > Uygulamalar > PortalKeepalive)
mkdir -p "$APP_DIR"
cat > "$APP_DIR/Şifreyi Değiştir.command" <<EOF
#!/bin/bash
/usr/bin/python3 "$SCRIPT" login
EOF
chmod 755 "$APP_DIR/Şifreyi Değiştir.command"
install -m 755 uninstall.sh "$APP_DIR/Kaldır.command"

echo "Kullanıcı adı ve parolanız sorulacak."
/usr/bin/python3 "$SCRIPT" login

# (Re)load the agent; bootout fails harmlessly when it is not loaded yet
mkdir -p "$HOME/Library/LaunchAgents"
sed "s|__HOME__|$HOME|g" com.serkan.portal-keepalive.plist > "$PLIST"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"

echo
echo "Kurulum tamamlandı. Oturum her 80 saniyede bir canlı tutulacak."
echo "Şifre değiştirmek veya kaldırmak için: Finder > Uygulamalar > PortalKeepalive"
