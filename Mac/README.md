# PortalKeepalive (macOS)

Keeps the GOP University captive portal session (denetim.gop.edu.tr) alive on macOS.

## Install
1. Copy `portal-keepalive.py` to `~/.portal-keepalive.py` and make executable:
   chmod 700 ~/.portal-keepalive.py
2. Create `~/.portal.env` (chmod 600) with:
   PORTAL_USER=your.email@gop.edu.tr
   PORTAL_PASS=yourpassword
3. Copy `com.serkan.portal-keepalive.plist` to `~/Library/LaunchAgents/`.
4. Load the agent:
   launchctl load -w ~/Library/LaunchAgents/com.serkan.portal-keepalive.plist

## Test
python3 ~/.portal-keepalive.py keepalive

## Logs
~/portal-keepalive.log
~/.portal-token
