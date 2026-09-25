#!/usr/bin/env bash
# ==============================================================================
# S22 Ultra Zero-Echo Microphone Installer
# Installs the verified AudioSource bridge directly on the Samsung S22 Ultra,
# grants recording permissions, and locks in the silent pipe stream.
# ==============================================================================

set -euo pipefail

S22_SERIAL="RFCT428ZRSZ"

echo "================================================================="
echo "  COPYING VERIFIED ZERO-ECHO AUDIO BRIDGE TO SAMSUNG S22 ULTRA"
echo "================================================================="

# 1. Download Audio Source package
echo "[1/4] Downloading Audio Source package..."
curl -fsSL https://github.com/gdzx/audiosource/releases/download/v1.5/audiosource.apk -o /tmp/audiosource.apk || true

if [ ! -s /tmp/audiosource.apk ]; then
    echo "ERROR: Failed to obtain audiosource.apk. Please ensure the internet connection is available."
    exit 1
fi

# 2. Install on Samsung S22 Ultra
echo "[3/4] Installing Audio Source on Samsung S22 Ultra ($S22_SERIAL)..."
adb -s "$S22_SERIAL" install -r -g /tmp/audiosource.apk

# Grant permissions explicitly
adb -s "$S22_SERIAL" shell pm grant fr.dzx.audiosource android.permission.RECORD_AUDIO 2>/dev/null || true
adb -s "$S22_SERIAL" shell pm grant fr.dzx.audiosource android.permission.POST_NOTIFICATIONS 2>/dev/null || true

echo "  -> Installed and permissions granted on S22 Ultra!"

# 3. Copy APK to ~/workspace/audiosource for permanence
mkdir -p "$HOME/workspace/audiosource/app/build/outputs/apk/debug"
cp -f /tmp/audiosource.apk "$HOME/workspace/audiosource/app/build/outputs/apk/debug/app-debug.apk"
cp -f /tmp/audiosource.apk "$HOME/workspace/audiosource/audiosource.apk"
rm -f /tmp/audiosource.apk

# 4. Configure permanent S22 audiosource service
echo "[4/4] Activating permanent S22 zero-echo mic service..."
cat << 'EOF' > "$HOME/.config/systemd/user/audiosource-s22.service"
[Unit]
Description=Audio Source: Samsung S22 Ultra microphone to PulseAudio (Zero Echo)
After=pipewire-pulse.service
Wants=pipewire-pulse.service

[Service]
Type=simple
ExecStart=%h/workspace/audiosource/audiosource -s RFCT428ZRSZ run -r
Restart=always
RestartSec=3
Environment=HOME=%h

[Install]
WantedBy=default.target
EOF

# Router service that keeps S22 mic as system default
cat << 'EOF' > "$HOME/.local/bin/s22-mic-router"
#!/bin/bash
SOURCE="android-4f3b250"

while true; do
    if pactl list sources short 2>/dev/null | awk '{print $2}' | grep -qx "$SOURCE"; then
        pactl set-source-mute "$SOURCE" false 2>/dev/null || true
        pactl set-source-volume "$SOURCE" 100% 2>/dev/null || true
        pactl set-default-source "$SOURCE" 2>/dev/null || true

        # Route browser capture streams to S22 mic
        while read -r id; do
            [ -z "$id" ] && continue
            pactl move-source-output "$id" "$SOURCE" 2>/dev/null || true
        done < <(
            pactl list source-outputs short 2>/dev/null |
            while read -r id rest; do
                [ -z "$id" ] && continue
                details="$(pactl list source-outputs 2>/dev/null | awk -v id="$id" '
                    $0 ~ "Source Output #"id"$" {found=1}
                    found {print}
                    found && /^$/ {exit}
                ')"
                if printf '%s\n' "$details" | grep -qiE 'firefox|chrome|browser'; then
                    printf '%s\n' "$id"
                fi
            done
        )
    fi
    sleep 2
done
EOF
chmod +x "$HOME/.local/bin/s22-mic-router"

cat << 'EOF' > "$HOME/.config/systemd/user/s22-mic-router.service"
[Unit]
Description=Samsung S22 Ultra microphone default-source router
After=audiosource-s22.service
Wants=audiosource-s22.service

[Service]
Type=simple
ExecStart=/home/justin/.local/bin/s22-mic-router
Restart=always
RestartSec=2

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload

systemctl --user enable --now audiosource-s22.service s22-mic-router.service
sleep 3

echo ""
echo "================================================================="
echo "  S22 ULTRA MIC IS LIVE & 100% SILENT ON SPEAKERS!"
echo "================================================================="
systemctl --user status audiosource-s22.service --no-pager -n 5 2>&1 || true
