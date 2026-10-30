#!/bin/bash
# Removes PortalKeepalive (install.sh also copies this as ~/Applications/PortalKeepalive/Kaldır.command)

LABEL="com.serkan.portal-keepalive"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" \
      "$HOME/.portal-keepalive.py" \
      "$HOME/.portal-keepalive.json" \
      "$HOME/.portal-token" \
      "$HOME/.portal-bad-credentials" \
      "$HOME/.portal-update-check.json" \
      "$HOME/.portal.env" \
      "$HOME/portal-keepalive.log"
while security delete-generic-password -s PortalKeepalive >/dev/null 2>&1; do :; done
rm -rf "$HOME/Applications/PortalKeepalive"

echo "PortalKeepalive kaldırıldı."
