# PortalKeepalive (macOS)

Keeps the GOP University captive portal session (denetim.gop.edu.tr) alive on macOS.

## Install
1. Download `PortalKeepalive-Mac.zip` from the latest GitHub release and unzip it.
2. In Terminal: `bash ~/Downloads/PortalKeepalive-Mac/install.sh`
3. Enter your institutional email and password when asked.

The installer copies the script to `~/.portal-keepalive.py`, stores the password in the macOS Keychain
(service `PortalKeepalive`), registers a launchd agent (at login + every 80 seconds) and adds
`~/Applications/PortalKeepalive/` with "Şifreyi Değiştir" and "Kaldır". Requires `/usr/bin/python3`
(`xcode-select --install`). An existing `~/.portal.env` is moved into the Keychain and deleted.

## Changing the password
Double-click `~/Applications/PortalKeepalive/Şifreyi Değiştir.command` (or run
`python3 ~/.portal-keepalive.py login`). It asks for the username and password again, tests and saves them.

If the portal rejects the saved password (e.g. it was changed), the keepalive shows a warning once and
stops retrying (to avoid locking the account) until new credentials are entered this way.

## Updates
Once a day the keepalive checks the latest GitHub release. When a newer version is out it shows a one-time
notice offering to open the download page; run the new `install.sh` over the old installation.

## Uninstall
Double-click `~/Applications/PortalKeepalive/Kaldır.command` (or run `bash uninstall.sh`).

## Test
python3 ~/.portal-keepalive.py keepalive

## Logs
~/portal-keepalive.log
~/.portal-token
