#!/bin/bash
# ============================================================================
# ACL QuickTest — Creating synthetic test environment
# Methodology ACL v1.0.4
# ============================================================================
#
# Creates synthetic apps with known artifacts for testing uninstallers.
# Ground truth is exact — we know every file.
#
# Synthetic apps:
#   Alpha  — simple .app (class 1) + sandbox simulation (class 2)
#   Beta   — PKG install (class 3) + LaunchAgent/Daemon (class 4/5)
#            + Privileged Helper (class 6) + Config profile (class 7)
#   Gamma  — family member 1 — DELETE (class 8)
#   Delta  — family member 2 — DO NOT DELETE (class 8)
#
# Traps:
#   Trap E — «AlphaApp Tool» with different bundle ID (similar name to AlphaApp)
#   Traps A,B,C — user files in ~/Documents, ~/Downloads, ~/Desktop
#                 with similar (but not matching) names
#
# Usage:
#   chmod +x quicktest-setup-en.sh
#   ./quicktest-setup-en.sh
#
# After running:
#   1. If the script created .mobileconfig — install the profile manually
#   2. Open the uninstaller being tested
#   3. Uninstall AlphaApp, BetaUtil, FamilyOne (NOT FamilyTwo, NOT «AlphaApp Tool»)
#   4. Run quicktest-verify-en.sh
# ============================================================================

set -euo pipefail

# --- Configuration ---
VENDOR="MethodologyTestVendor"
# Bundle IDs for each app — unique, so the uninstaller does not merge them by common prefix
ALPHA_ID="com.methodology-alpha.testcleaners-alpha"
BETA_ID="com.methodology-beta.testcleaners-beta"
# Gamma and Delta share prefix com.methodology.* (simulating a family)
GAMMA_ID="com.methodology.testcleaners-gamma"
DELTA_ID="com.methodology.testcleaners-delta"
TRAPE_ID="com.different-vendor.testapp"
AUDIT_DIR="$HOME/uninstall-audit"
MANIFEST="$AUDIT_DIR/quicktest-manifest.txt"
GROUND_TRUTH_FILE="$AUDIT_DIR/quicktest-ground-truth.txt"

# If run via sudo — preserve the real user
if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_HOME=$(eval echo "~$SUDO_USER")
    REAL_USER="$SUDO_USER"
else
    REAL_HOME="$HOME"
    REAL_USER="$(whoami)"
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; }
header()  { echo -e "\n${BOLD}═══ $1 ═══${NC}"; }

# --- Manifest ---
manifest() {
    # type|path|category|description
    echo "$1|$2|$3|$4" >> "$MANIFEST"
}

# --- Create .app bundle ---
create_app_bundle() {
    local app_path="$1"
    local bundle_id="$2"
    local app_name="$3"

    mkdir -p "$app_path/Contents/MacOS"
    mkdir -p "$app_path/Contents/Resources"

    cat > "$app_path/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
</dict>
</plist>
PLIST

    cat > "$app_path/Contents/MacOS/$app_name" << 'EXEC'
#!/bin/bash
echo "ACL QuickTest — synthetic test application"
EXEC
    chmod +x "$app_path/Contents/MacOS/$app_name"
}

# --- Create filler files ---
create_filler() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    echo "ACL QuickTest synthetic file — $(date -Iseconds)" > "$path"
}

# ============================================================================
# FUNCTION: output ground truth as plain text (no ANSI codes)
# Called twice: to terminal (with colors via echo -e) and to file (no colors)
# ============================================================================

write_ground_truth_plain() {
    # $1 — file path (if set — write there, otherwise to stdout)
    local OUT="${1:-/dev/stdout}"
    local TRAP_DATE_DISP
    TRAP_DATE_DISP=$(date +%Y-%m-%d)

    {
    echo "ACL QuickTest — Ground Truth"
    echo "Created: $(date '+%Y-%m-%d %H:%M:%S')"
    echo "Methodology ACL v1.0.4"
    echo ""
    echo "Apps to uninstall: AlphaApp, BetaUtil, FamilyOne"
    echo "Apps to leave untouched: FamilyTwo, «AlphaApp Tool»"
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║         MUST FIND AND DELETE                                     ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "▶ AlphaApp  [${ALPHA_ID}]"
    echo "  Class 1 (Drag & Drop) + Class 2 (Sandbox)"
    echo "  User-level:"
    echo "    /Applications/AlphaApp.app"
    echo "    ~/Library/Application Support/AlphaApp/"
    echo "    ~/Library/Preferences/${ALPHA_ID}.plist"
    echo "    ~/Library/Caches/${ALPHA_ID}/"
    echo "    ~/Library/Logs/AlphaApp/"
    echo "    ~/Library/Containers/${ALPHA_ID}/          [sandbox container]"
    echo "    ~/Library/Group Containers/group.${ALPHA_ID}/"
    echo "    ~/Library/HTTPStorages/${ALPHA_ID}/"
    echo "    ~/Library/Saved Application State/${ALPHA_ID}.savedState/"
    echo "    Keychain: entry «AlphaApp»"
    echo "    ~/Library/Application Support/Alpha App/   <- space in name, detector test"
    echo ""
    echo "▶ BetaUtil  [${BETA_ID}]"
    echo "  Class 3 (PKG) + Class 4/5 (LaunchAgent/Daemon) + Class 6 (Helper) + Class 7 (Config Profile)"
    echo "  User-level:"
    echo "    /Applications/BetaUtil.app"
    echo "    ~/Library/Application Support/BetaUtil/"
    echo "    ~/Library/LaunchAgents/${BETA_ID}.agent.plist   [LaunchAgent — must be unloaded!]"
    echo "    ~/Library/Preferences/${BETA_ID}.plist"
    echo "    ~/Library/Caches/${BETA_ID}/"
    if [[ "$HAS_SUDO" == true ]]; then
    echo "  System-level (require sudo):"
    echo "    /Library/Application Support/BetaUtil/"
    echo "    /Library/LaunchDaemons/${BETA_ID}.daemon.plist  [LaunchDaemon — must be unloaded!]"
    echo "    /Library/PrivilegedHelperTools/${BETA_ID}.helper  [Privileged Helper!]"
    echo "    PKG receipt: ${BETA_ID}.pkg                    [pkgutil --forget + file removal]"
    echo "    /usr/local/bin/acl-testapp-beta               [symlink]"
    echo "    Config profile: com.methodology-beta.testcleaners-beta.vpnprofile  [Configuration Profile!]"
    else
    echo "  [sudo was not used — system artifacts were not created]"
    fi
    echo ""
    echo "▶ FamilyOne  [${GAMMA_ID}]"
    echo "  Class 8 (family) — delete ONLY Gamma-specific subfolders, shared — must not!"
    echo "  User-level:"
    echo "    /Applications/FamilyOne.app"
    echo "    ~/Library/Application Support/${VENDOR}/Gamma/   <- this subfolder only!"
    echo "    ~/Library/Preferences/${GAMMA_ID}.plist"
    echo "    ~/Library/Caches/${GAMMA_ID}/"
    if [[ "$HAS_SUDO" == true ]]; then
    echo "  System-level:"
    echo "    /Library/Application Support/${VENDOR}/Gamma/    <- this subfolder only!"
    fi
    echo ""
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║         MUST NOT TOUCH — TRAPS AND OTHER APPS DATA               ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "⛔ Shared vendor folders  [${VENDOR}]  — DO NOT DELETE"
    echo "   Reason: FamilyTwo depends on them (another app from the same vendor)"
    echo "    ~/Library/Application Support/${VENDOR}/Shared/   <- shared library"
    echo "    ~/Library/Application Support/${VENDOR}/          <- entire vendor folder"
    if [[ "$HAS_SUDO" == true ]]; then
    echo "    /Library/Application Support/${VENDOR}/Shared/"
    echo "    /Library/Application Support/${VENDOR}/"
    fi
    echo ""
    echo "⛔ FamilyTwo  [${DELTA_ID}]  — DO NOT DELETE"
    echo "   Reason: another app in the same family, remains installed"
    echo "    /Applications/FamilyTwo.app"
    echo "    ~/Library/Application Support/${VENDOR}/Delta/"
    echo "    ~/Library/Preferences/${DELTA_ID}.plist"
    echo "    ~/Library/Caches/${DELTA_ID}/"
    if [[ "$HAS_SUDO" == true ]]; then
    echo "    /Library/Application Support/${VENDOR}/Delta/"
    fi
    echo ""
    echo "⛔ Trap E — «AlphaApp Tool»  [${TRAPE_ID}]  — DO NOT DELETE"
    echo "   Reason: different bundle ID, just a similar name"
    echo "    /Applications/AlphaApp Tool.app"
    echo "    ~/Library/Application Support/AlphaApp Tool/"
    echo "    ~/Library/Preferences/${TRAPE_ID}.plist"
    echo "    ~/Library/Caches/${TRAPE_ID}/"
    echo ""
    echo "⛔ Traps A/B/C — user locations (Documents / Downloads / Desktop)"
    echo "   Rule: detecting is allowed, not an error if skipped,"
    echo "         but selecting for deletion without explicit user confirmation — not allowed"
    echo ""
    echo "  Trap A — user data with similar names:"
    echo "    ~/Documents/Alpha App/             <- user location, even if name matches"
    echo "    ~/Downloads/AlphaApp-data/         <- hyphen, user data"
    echo "    ~/Desktop/Alpha App Export/        <- word Export in name"
    echo "    ~/Documents/Alpha_App_Backup/      <- underscores"
    echo ""
    echo "  Trap B — name similar to vendor:"
    echo "    ~/Documents/Methodology Test/          <- looks like «${VENDOR}»"
    echo "    ~/Documents/TestVendor Files/          <- vendor-like name"
    echo ""
    echo "  Trap C — exports and backups with app name in filename:"
    echo "    ~/Documents/AlphaApp-export-${TRAP_DATE_DISP}.zip"
    echo "    ~/Documents/AlphaApp-backup.json"
    echo "    ~/Documents/AlphaApp-report.pdf"
    echo "    ~/Documents/testcleaners-report.txt"
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "Manifest (machine-readable): ${MANIFEST}"
    echo "Report after verification:   ${AUDIT_DIR}/quicktest-report.txt"
    echo "══════════════════════════════════════════════════════════════════"
    } > "$OUT"
}

# ============================================================================
# CHECKS
# ============================================================================

if [[ -d "$AUDIT_DIR" ]]; then
    error "Directory $AUDIT_DIR already exists."
    error "Run quicktest-teardown-en.sh to clean up, then try again."
    exit 1
fi

# Check sudo
HAS_SUDO=false
if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
    HAS_SUDO=true
    info "sudo available — system artifacts will be created (PKG, Daemon, Helper, Profile)"
else
    warn "No sudo — system artifacts will be skipped"
    warn "For full coverage: sudo ./quicktest-setup-en.sh"
fi

# ============================================================================
# START
# ============================================================================

header "ACL QuickTest — creating test environment"
echo "Bundle IDs:"
echo "  Alpha: ${ALPHA_ID}"
echo "  Beta:  ${BETA_ID}"
echo "  Gamma: ${GAMMA_ID} (family)"
echo "  Delta: ${DELTA_ID} (family)"
echo "  Trap:  ${TRAPE_ID}"
echo "Audit directory: ${AUDIT_DIR}"
echo ""

mkdir -p "$AUDIT_DIR"
echo "# ACL QuickTest Manifest — $(date -Iseconds)" > "$MANIFEST"
echo "# TYPE|PATH|CATEGORY|DESCRIPTION" >> "$MANIFEST"
echo "# delete  = must be found and deleted by the uninstaller" >> "$MANIFEST"
echo "# trap    = must NOT be deleted (user data / another app)" >> "$MANIFEST"
echo "# keep    = Delta app — remains installed" >> "$MANIFEST"
echo "# system  = system-level artifact (requires sudo for verification)" >> "$MANIFEST"
echo "# profile = configuration profile" >> "$MANIFEST"

# ============================================================================
# 1. APP ALPHA — simple app (class 1 + 2)
# ============================================================================

header "1/6 App Alpha (class 1 — Drag & Drop + class 2 — Sandbox)"

ALPHA_NAME="AlphaApp"

# .app bundle
create_app_bundle "/Applications/${ALPHA_NAME}.app" "$ALPHA_ID" "$ALPHA_NAME"
manifest "delete" "/Applications/${ALPHA_NAME}.app" "alpha" ".app bundle"
success "Created /Applications/${ALPHA_NAME}.app"

# Application Support
mkdir -p "$REAL_HOME/Library/Application Support/${ALPHA_NAME}"
create_filler "$REAL_HOME/Library/Application Support/${ALPHA_NAME}/settings.json"
create_filler "$REAL_HOME/Library/Application Support/${ALPHA_NAME}/data.db"
manifest "delete" "$REAL_HOME/Library/Application Support/${ALPHA_NAME}" "alpha" "Application Support"

# Application Support — name with space (detector test)
# A quality uninstaller should find «Alpha App» the same way as «AlphaApp»
mkdir -p "$REAL_HOME/Library/Application Support/Alpha App"
create_filler "$REAL_HOME/Library/Application Support/Alpha App/settings.json"
manifest "delete" "$REAL_HOME/Library/Application Support/Alpha App" "alpha" "Application Support with space in name (detector test)"

# Preferences
defaults write "$ALPHA_ID" QuickTestVersion -string "1.0"
defaults write "$ALPHA_ID" SyntheticApp -bool true
manifest "delete" "$REAL_HOME/Library/Preferences/${ALPHA_ID}.plist" "alpha" "Preferences"

# Caches
mkdir -p "$REAL_HOME/Library/Caches/${ALPHA_ID}"
create_filler "$REAL_HOME/Library/Caches/${ALPHA_ID}/cache.dat"
create_filler "$REAL_HOME/Library/Caches/${ALPHA_ID}/thumbnails.dat"
manifest "delete" "$REAL_HOME/Library/Caches/${ALPHA_ID}" "alpha" "Caches"

# Logs
mkdir -p "$REAL_HOME/Library/Logs/${ALPHA_NAME}"
create_filler "$REAL_HOME/Library/Logs/${ALPHA_NAME}/app.log"
manifest "delete" "$REAL_HOME/Library/Logs/${ALPHA_NAME}" "alpha" "Logs"

# Containers (sandbox simulation — class 2)
# Same TCC + containermanagerd issue as Group Containers — must use sudo,
# then strip com.apple.macl and ACLs so the uninstaller can actually delete it.
sudo mkdir -p "$REAL_HOME/Library/Containers/${ALPHA_ID}/Data/Library/Preferences"
sudo chown -R "$REAL_USER" "$REAL_HOME/Library/Containers/${ALPHA_ID}"
sudo xattr -dr com.apple.macl "$REAL_HOME/Library/Containers/${ALPHA_ID}" 2>/dev/null || true
sudo chmod -RN "$REAL_HOME/Library/Containers/${ALPHA_ID}" 2>/dev/null || true
create_filler "$REAL_HOME/Library/Containers/${ALPHA_ID}/Data/Library/Preferences/${ALPHA_ID}.plist"
create_filler "$REAL_HOME/Library/Containers/${ALPHA_ID}/Data/Library/settings.dat"
manifest "delete" "$REAL_HOME/Library/Containers/${ALPHA_ID}" "alpha" "Container (sandbox)"

# Group Containers
# ~/Library/Group Containers/ is TCC-protected — requires sudo to create.
# After mkdir, containermanagerd asynchronously sets com.apple.macl xattr
# (Mandatory Access Control) tied to an app entitlement. Since no real app
# has this group container entitlement, the folder becomes an orphan and
# cannot be deleted by Finder or any uninstaller without sudo.
# Fix: remove com.apple.macl and any deny-delete ACL immediately after creation.
sudo mkdir -p "$REAL_HOME/Library/Group Containers/group.${ALPHA_ID}"
sudo chown "$REAL_USER" "$REAL_HOME/Library/Group Containers/group.${ALPHA_ID}"
sudo xattr -d com.apple.macl "$REAL_HOME/Library/Group Containers/group.${ALPHA_ID}" 2>/dev/null || true
sudo chmod -N "$REAL_HOME/Library/Group Containers/group.${ALPHA_ID}" 2>/dev/null || true
create_filler "$REAL_HOME/Library/Group Containers/group.${ALPHA_ID}/shared.dat"
manifest "delete" "$REAL_HOME/Library/Group Containers/group.${ALPHA_ID}" "alpha" "Group Container"

# HTTPStorages
mkdir -p "$REAL_HOME/Library/HTTPStorages/${ALPHA_ID}"
create_filler "$REAL_HOME/Library/HTTPStorages/${ALPHA_ID}/cookies.dat"
manifest "delete" "$REAL_HOME/Library/HTTPStorages/${ALPHA_ID}" "alpha" "HTTPStorages"

# Saved Application State
mkdir -p "$REAL_HOME/Library/Saved Application State/${ALPHA_ID}.savedState"
create_filler "$REAL_HOME/Library/Saved Application State/${ALPHA_ID}.savedState/window_1.data"
manifest "delete" "$REAL_HOME/Library/Saved Application State/${ALPHA_ID}.savedState" "alpha" "Saved State"

# Keychain
security add-generic-password \
    -a "${ALPHA_ID}" \
    -s "${ALPHA_NAME}" \
    -w "quicktest-token-12345" \
    -T "" \
    2>/dev/null || warn "Failed to create Keychain entry (may already exist)"
# Keychain is NOT added to manifest as delete — most uninstallers don't clean it
# and that's considered normal. The verify script reports it as [INFO] only.

success "App Alpha — $(find "/Applications/${ALPHA_NAME}.app" "$REAL_HOME/Library" -path "*testcleaners-alpha*" -o -path "*${ALPHA_NAME}*" 2>/dev/null | wc -l | tr -d ' ') artifacts"

# ============================================================================
# 2. APP BETA — PKG + LaunchAgent + Daemon + Helper + Config Profile (classes 3-7)
# ============================================================================

header "2/6 App Beta (classes 3–7: PKG, Agent, Daemon, Helper, Config Profile)"

BETA_NAME="BetaUtil"

# --- User-level artifacts ---

# .app bundle (will also be in PKG if sudo is available)
create_app_bundle "/Applications/${BETA_NAME}.app" "$BETA_ID" "$BETA_NAME"
manifest "delete" "/Applications/${BETA_NAME}.app" "beta" ".app bundle"
success "Created /Applications/${BETA_NAME}.app"

# Application Support (user)
mkdir -p "$REAL_HOME/Library/Application Support/${BETA_NAME}"
create_filler "$REAL_HOME/Library/Application Support/${BETA_NAME}/config.json"

# Agent script
cat > "$REAL_HOME/Library/Application Support/${BETA_NAME}/agent.sh" << 'AGENT'
#!/bin/bash
# ACL QuickTest — synthetic LaunchAgent (does nothing)
while true; do sleep 86400; done
AGENT
chmod +x "$REAL_HOME/Library/Application Support/${BETA_NAME}/agent.sh"
manifest "delete" "$REAL_HOME/Library/Application Support/${BETA_NAME}" "beta" "Application Support (user)"

# LaunchAgent (user-level)
cat > "$REAL_HOME/Library/LaunchAgents/${BETA_ID}.agent.plist" << LAPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BETA_ID}.agent</string>
    <key>ProgramArguments</key>
    <array>
        <string>${REAL_HOME}/Library/Application Support/${BETA_NAME}/agent.sh</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
LAPLIST
# Load agent
launchctl load "$REAL_HOME/Library/LaunchAgents/${BETA_ID}.agent.plist" 2>/dev/null || true
manifest "delete" "$REAL_HOME/Library/LaunchAgents/${BETA_ID}.agent.plist" "beta" "LaunchAgent (user)"
success "LaunchAgent created and loaded"

# Preferences
defaults write "$BETA_ID" QuickTestVersion -string "1.0"
manifest "delete" "$REAL_HOME/Library/Preferences/${BETA_ID}.plist" "beta" "Preferences"

# Caches
mkdir -p "$REAL_HOME/Library/Caches/${BETA_ID}"
create_filler "$REAL_HOME/Library/Caches/${BETA_ID}/cache.dat"
manifest "delete" "$REAL_HOME/Library/Caches/${BETA_ID}" "beta" "Caches"

# --- System-level artifacts (require sudo) ---

if [[ "$HAS_SUDO" == true ]]; then

    # Application Support (system-level)
    sudo mkdir -p "/Library/Application Support/${BETA_NAME}"
    sudo sh -c "echo 'ACL QuickTest system config' > '/Library/Application Support/${BETA_NAME}/system-config.dat'"

    # Daemon script
    sudo sh -c "cat > '/Library/Application Support/${BETA_NAME}/daemon.sh'" << 'DAEMON'
#!/bin/bash
# ACL QuickTest — synthetic LaunchDaemon (does nothing)
while true; do sleep 86400; done
DAEMON
    sudo chmod +x "/Library/Application Support/${BETA_NAME}/daemon.sh"
    manifest "system" "/Library/Application Support/${BETA_NAME}" "beta" "Application Support (system)"

    # LaunchDaemon
    sudo tee "/Library/LaunchDaemons/${BETA_ID}.daemon.plist" > /dev/null << LDPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BETA_ID}.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>/Library/Application Support/${BETA_NAME}/daemon.sh</string>
    </array>
    <key>RunAtLoad</key>
    <false/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
LDPLIST
    sudo launchctl load "/Library/LaunchDaemons/${BETA_ID}.daemon.plist" 2>/dev/null || true
    manifest "system" "/Library/LaunchDaemons/${BETA_ID}.daemon.plist" "beta" "LaunchDaemon"
    success "LaunchDaemon created and loaded"

    # Privileged Helper
    sudo mkdir -p /Library/PrivilegedHelperTools
    sudo sh -c "cat > '/Library/PrivilegedHelperTools/${BETA_ID}.helper'" << 'HELPER'
#!/bin/bash
# ACL QuickTest — synthetic Privileged Helper (does nothing)
echo "Synthetic helper"
HELPER
    sudo chmod +x "/Library/PrivilegedHelperTools/${BETA_ID}.helper"
    manifest "system" "/Library/PrivilegedHelperTools/${BETA_ID}.helper" "beta" "Privileged Helper"
    success "Privileged Helper created"

    # PKG (create and install)
    PKG_TMP=$(mktemp -d)
    mkdir -p "$PKG_TMP/Library/Application Support/${BETA_NAME}/pkg-data"
    echo "ACL QuickTest PKG component" > "$PKG_TMP/Library/Application Support/${BETA_NAME}/pkg-data/installed-by-pkg.dat"

    pkgbuild --root "$PKG_TMP" \
             --identifier "${BETA_ID}.pkg" \
             --version "1.0" \
             --ownership recommended \
             "$AUDIT_DIR/BetaUtil.pkg" > /dev/null 2>&1

    sudo installer -pkg "$AUDIT_DIR/BetaUtil.pkg" -target / > /dev/null 2>&1
    rm -rf "$PKG_TMP"
    manifest "system" "pkg:${BETA_ID}.pkg" "beta" "PKG receipt"
    success "PKG created and installed (receipt: ${BETA_ID}.pkg)"

    # Symlink in /usr/local/bin
    sudo mkdir -p /usr/local/bin
    sudo ln -sf "/Applications/${BETA_NAME}.app/Contents/MacOS/${BETA_NAME}" /usr/local/bin/acl-testapp-beta
    manifest "system" "/usr/local/bin/acl-testapp-beta" "beta" "Symlink"
    success "Symlink created: /usr/local/bin/acl-testapp-beta"

    # Configuration Profile (.mobileconfig) — WiFi payload (installs without errors)
    PROFILE_PATH="$AUDIT_DIR/BetaUtil-Profile.mobileconfig"
    cat > "$PROFILE_PATH" << 'MOBILECONFIG'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>PayloadContent</key>
    <array>
        <dict>
            <key>PayloadType</key>
            <string>com.apple.wifi.managed</string>
            <key>PayloadVersion</key>
            <integer>1</integer>
            <key>PayloadIdentifier</key>
            <string>com.methodology-beta.testcleaners-beta.wifi</string>
            <key>PayloadUUID</key>
            <string>A1B2C3D4-E5F6-7890-ABCD-EF1234567890</string>
            <key>PayloadDisplayName</key>
            <string>ACL Test WiFi</string>
            <key>SSID_STR</key>
            <string>ACL-QuickTest-DoNotConnect</string>
            <key>HIDDEN_NETWORK</key>
            <false/>
            <key>AutoJoin</key>
            <false/>
            <key>EncryptionType</key>
            <string>None</string>
        </dict>
    </array>
    <key>PayloadDisplayName</key>
    <string>BetaUtil Test Profile</string>
    <key>PayloadDescription</key>
    <string>Synthetic configuration profile for ACL Methodology QuickTest. Safe to remove.</string>
    <key>PayloadIdentifier</key>
    <string>com.methodology-beta.testcleaners-beta.vpnprofile</string>
    <key>PayloadType</key>
    <string>Configuration</string>
    <key>PayloadUUID</key>
    <string>B2C3D4E5-F6A7-8901-BCDE-F12345678901</string>
    <key>PayloadVersion</key>
    <integer>1</integer>
    <key>PayloadRemovalDisallowed</key>
    <false/>
</dict>
</plist>
MOBILECONFIG
    manifest "profile" "com.methodology-beta.testcleaners-beta.vpnprofile" "beta" "Configuration Profile (WiFi)"
    success "Config profile created: $PROFILE_PATH"
    warn "Profile must be installed manually (see instructions below)"

else
    warn "Skipped: LaunchDaemon, Privileged Helper, PKG, Symlink, Config profile (no sudo)"
fi

# ============================================================================
# 3. APP GAMMA — family member 1 — DELETE (class 8)
# ============================================================================

header "3/6 App Gamma (class 8 — family, DELETE)"

GAMMA_NAME="FamilyOne"

create_app_bundle "/Applications/${GAMMA_NAME}.app" "$GAMMA_ID" "$GAMMA_NAME"
manifest "delete" "/Applications/${GAMMA_NAME}.app" "gamma" ".app bundle"

# Shared vendor folder + app-specific subfolder
mkdir -p "$REAL_HOME/Library/Application Support/${VENDOR}/Shared"
mkdir -p "$REAL_HOME/Library/Application Support/${VENDOR}/Gamma"
create_filler "$REAL_HOME/Library/Application Support/${VENDOR}/Shared/shared-library.dat"
create_filler "$REAL_HOME/Library/Application Support/${VENDOR}/Gamma/gamma-settings.json"
manifest "delete" "$REAL_HOME/Library/Application Support/${VENDOR}/Gamma" "gamma" "App-specific subfolder in vendor"
# Shared folder — must NOT be deleted (Delta depends on it)
manifest "keep" "$REAL_HOME/Library/Application Support/${VENDOR}/Shared" "vendor_shared" "Shared vendor data (Delta depends on it)"
manifest "keep" "$REAL_HOME/Library/Application Support/${VENDOR}" "vendor_shared" "Vendor folder (Delta depends on it)"

defaults write "$GAMMA_ID" QuickTestVersion -string "1.0"
manifest "delete" "$REAL_HOME/Library/Preferences/${GAMMA_ID}.plist" "gamma" "Preferences"

mkdir -p "$REAL_HOME/Library/Caches/${GAMMA_ID}"
create_filler "$REAL_HOME/Library/Caches/${GAMMA_ID}/cache.dat"
manifest "delete" "$REAL_HOME/Library/Caches/${GAMMA_ID}" "gamma" "Caches"

if [[ "$HAS_SUDO" == true ]]; then
    sudo mkdir -p "/Library/Application Support/${VENDOR}/Shared"
    sudo mkdir -p "/Library/Application Support/${VENDOR}/Gamma"
    sudo sh -c "echo 'system shared lib' > '/Library/Application Support/${VENDOR}/Shared/system-lib.dat'"
    sudo sh -c "echo 'gamma system data' > '/Library/Application Support/${VENDOR}/Gamma/system-gamma.dat'"
    manifest "system" "/Library/Application Support/${VENDOR}/Gamma" "gamma" "System vendor app-specific"
    manifest "keep" "/Library/Application Support/${VENDOR}/Shared" "vendor_shared" "System shared vendor (Delta depends on it)"
    manifest "keep" "/Library/Application Support/${VENDOR}" "vendor_shared" "System vendor folder (Delta depends on it)"
fi

success "App Gamma created (shared vendor: ${VENDOR})"

# ============================================================================
# 4. APP DELTA — family member 2 — DO NOT DELETE (class 8)
# ============================================================================

header "4/6 App Delta (class 8 — family, DO NOT DELETE)"

DELTA_NAME="FamilyTwo"

create_app_bundle "/Applications/${DELTA_NAME}.app" "$DELTA_ID" "$DELTA_NAME"
manifest "keep" "/Applications/${DELTA_NAME}.app" "delta" ".app bundle (DO NOT delete)"

# App-specific subfolder in shared vendor folder
mkdir -p "$REAL_HOME/Library/Application Support/${VENDOR}/Delta"
create_filler "$REAL_HOME/Library/Application Support/${VENDOR}/Delta/delta-settings.json"
manifest "keep" "$REAL_HOME/Library/Application Support/${VENDOR}/Delta" "delta" "App-specific subfolder Delta (DO NOT delete)"

defaults write "$DELTA_ID" QuickTestVersion -string "1.0"
manifest "keep" "$REAL_HOME/Library/Preferences/${DELTA_ID}.plist" "delta" "Preferences Delta (DO NOT delete)"

mkdir -p "$REAL_HOME/Library/Caches/${DELTA_ID}"
create_filler "$REAL_HOME/Library/Caches/${DELTA_ID}/cache.dat"
manifest "keep" "$REAL_HOME/Library/Caches/${DELTA_ID}" "delta" "Caches Delta (DO NOT delete)"

if [[ "$HAS_SUDO" == true ]]; then
    sudo mkdir -p "/Library/Application Support/${VENDOR}/Delta"
    sudo sh -c "echo 'delta system data' > '/Library/Application Support/${VENDOR}/Delta/system-delta.dat'"
    manifest "keep" "/Library/Application Support/${VENDOR}/Delta" "delta" "System Delta (DO NOT delete)"
fi

success "App Delta created (depends on shared vendor folder)"

# ============================================================================
# 5. TRAP E — similar name, different bundle ID
# ============================================================================

header "5/6 Trap E (similar name, different bundle ID)"

TRAPE_NAME="AlphaApp Tool"  # similar to «AlphaApp», but a different app

create_app_bundle "/Applications/${TRAPE_NAME}.app" "$TRAPE_ID" "$TRAPE_NAME"
manifest "trap" "/Applications/${TRAPE_NAME}.app" "trap_e" "Different app with similar name"

mkdir -p "$REAL_HOME/Library/Application Support/${TRAPE_NAME}"
create_filler "$REAL_HOME/Library/Application Support/${TRAPE_NAME}/data.db"
manifest "trap" "$REAL_HOME/Library/Application Support/${TRAPE_NAME}" "trap_e" "App Support of another app"

defaults write "$TRAPE_ID" SomeOtherApp -bool true
manifest "trap" "$REAL_HOME/Library/Preferences/${TRAPE_ID}.plist" "trap_e" "Preferences of another app"

mkdir -p "$REAL_HOME/Library/Caches/${TRAPE_ID}"
create_filler "$REAL_HOME/Library/Caches/${TRAPE_ID}/cache.dat"
manifest "trap" "$REAL_HOME/Library/Caches/${TRAPE_ID}" "trap_e" "Caches of another app"

success "Trap E: «${TRAPE_NAME}» (${TRAPE_ID}) — must NOT be touched when uninstalling Alpha"

# ============================================================================
# 6. TRAPS A, B, C — user data with similar names
# ============================================================================

header "6/6 Traps A, B, C (user data)"

# --- Trap A: «Naive name matching» ---
# Names resemble apps, but these are user files

# In Documents — name matches the app, but this is a user location
# Showing is allowed, selecting for deletion without explicit confirmation — not allowed
mkdir -p "$REAL_HOME/Documents/Alpha App"
echo "User document — DO NOT DELETE" > "$REAL_HOME/Documents/Alpha App/DO_NOT_DELETE.txt"
echo "%PDF-1.4 fake" > "$REAL_HOME/Documents/Alpha App/report.pdf"
dd if=/dev/urandom bs=1024 count=10 of="$REAL_HOME/Documents/Alpha App/photo.jpg" 2>/dev/null
manifest "trap" "$REAL_HOME/Documents/Alpha App" "trap_a" "Documents/Alpha App — user location, must not delete without explicit confirmation"

# In Downloads — name with hyphen (different naming pattern)
mkdir -p "$REAL_HOME/Downloads/AlphaApp-data"
echo "Downloaded data — user file" > "$REAL_HOME/Downloads/AlphaApp-data/important.csv"
echo "%PDF-1.4 fake" > "$REAL_HOME/Downloads/AlphaApp-data/manual.pdf"
manifest "trap" "$REAL_HOME/Downloads/AlphaApp-data" "trap_a" "Downloads with similar name (hyphen)"

# In Desktop — «export»
mkdir -p "$REAL_HOME/Desktop/Alpha App Export"
echo "Exported report" > "$REAL_HOME/Desktop/Alpha App Export/results.csv"
manifest "trap" "$REAL_HOME/Desktop/Alpha App Export" "trap_a" "Desktop with similar name (Export)"

# In Documents — name with underscores (another pattern)
mkdir -p "$REAL_HOME/Documents/Alpha_App_Backup"
echo "User backup" > "$REAL_HOME/Documents/Alpha_App_Backup/backup.dat"
manifest "trap" "$REAL_HOME/Documents/Alpha_App_Backup" "trap_a" "Documents with underscores"

success "Trap A: 4 folders with similar names in Documents/Downloads/Desktop"

# --- Trap B: «Vendor name» ---
# Name resembles VENDOR (MethodologyTestVendor), but this is a user folder

mkdir -p "$REAL_HOME/Documents/Methodology Test"
echo "User notes about methodology" > "$REAL_HOME/Documents/Methodology Test/notes.txt"
echo "Research data" > "$REAL_HOME/Documents/Methodology Test/research.pdf"
manifest "trap" "$REAL_HOME/Documents/Methodology Test" "trap_b" "Documents with vendor-like name"

mkdir -p "$REAL_HOME/Documents/TestVendor Files"
echo "Vendor-like name but user data" > "$REAL_HOME/Documents/TestVendor Files/data.txt"
manifest "trap" "$REAL_HOME/Documents/TestVendor Files" "trap_b" "Documents with vendor-like name"

success "Trap B: 2 folders with vendor-like names"

# --- Trap C: «Exports and backups» ---
# Files named after the app, but these are user exports

TRAP_DATE=$(date +%Y-%m-%d)
echo "PK fake zip content" > "$REAL_HOME/Documents/AlphaApp-export-${TRAP_DATE}.zip"
echo '{"backup": true, "user_data": "important"}' > "$REAL_HOME/Documents/AlphaApp-backup.json"
echo "%PDF-1.4 fake report" > "$REAL_HOME/Documents/AlphaApp-report.pdf"
echo "Log of user actions" > "$REAL_HOME/Documents/testcleaners-report.txt"

manifest "trap" "$REAL_HOME/Documents/AlphaApp-export-${TRAP_DATE}.zip" "trap_c" "Export file named after the app"
manifest "trap" "$REAL_HOME/Documents/AlphaApp-backup.json" "trap_c" "Backup named after the app"
manifest "trap" "$REAL_HOME/Documents/AlphaApp-report.pdf" "trap_c" "Report with similar name"
manifest "trap" "$REAL_HOME/Documents/testcleaners-report.txt" "trap_c" "File with part of bundle ID in name"

success "Trap C: 4 export files with similar names"

# ============================================================================
# SUMMARY
# ============================================================================

header "DONE"

# Count artifacts by type
TOTAL_DELETE=$(grep -c "^delete|" "$MANIFEST" || true)
TOTAL_SYSTEM=$(grep -c "^system|" "$MANIFEST" || true)
TOTAL_TRAP=$(grep -c "^trap|" "$MANIFEST" || true)
TOTAL_KEEP=$(grep -c "^keep|" "$MANIFEST" || true)
TOTAL_PROFILE=$(grep -c "^profile|" "$MANIFEST" || true)

echo ""
echo "Manifest: ${MANIFEST}"
echo ""

# ============================================================================
# GROUND TRUTH — visual summary by app
# ============================================================================

echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         GROUND TRUTH — WHAT THE UNINSTALLER MUST FIND           ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- AlphaApp ---
echo -e "${GREEN}${BOLD}▶ AlphaApp  [${ALPHA_ID}]  — DELETE COMPLETELY${NC}"
echo -e "  ${BOLD}User-level artifacts (class 1 Drag&Drop + class 2 Sandbox):${NC}"
echo "    /Applications/AlphaApp.app"
echo "    ~/Library/Application Support/AlphaApp/"
echo "    ~/Library/Preferences/${ALPHA_ID}.plist"
echo "    ~/Library/Caches/${ALPHA_ID}/"
echo "    ~/Library/Logs/AlphaApp/"
echo "    ~/Library/Containers/${ALPHA_ID}/          [sandbox container]"
echo "    ~/Library/Group Containers/group.${ALPHA_ID}/"
echo "    ~/Library/HTTPStorages/${ALPHA_ID}/"
echo "    ~/Library/Saved Application State/${ALPHA_ID}.savedState/"
echo "    Keychain: entry «AlphaApp»"
echo "    ~/Library/Application Support/Alpha App/   ← space in name, detector test"
echo ""

# --- BetaUtil ---
echo -e "${GREEN}${BOLD}▶ BetaUtil  [${BETA_ID}]  — DELETE COMPLETELY${NC}"
echo -e "  ${BOLD}User-level artifacts (class 3 PKG + class 4/5 LaunchAgent/Daemon):${NC}"
echo "    /Applications/BetaUtil.app"
echo "    ~/Library/Application Support/BetaUtil/"
echo "    ~/Library/LaunchAgents/${BETA_ID}.agent.plist   ⚡ LaunchAgent (must be unloaded!)"
echo "    ~/Library/Preferences/${BETA_ID}.plist"
echo "    ~/Library/Caches/${BETA_ID}/"
if [[ "$HAS_SUDO" == true ]]; then
echo -e "  ${BOLD}System-level artifacts (require sudo):${NC}"
echo "    /Library/Application Support/BetaUtil/"
echo "    /Library/LaunchDaemons/${BETA_ID}.daemon.plist  ⚡ LaunchDaemon (must be unloaded!)"
echo "    /Library/PrivilegedHelperTools/${BETA_ID}.helper  ⚠️  Privileged Helper!"
echo "    PKG receipt: ${BETA_ID}.pkg                    (pkgutil --forget + file removal)"
echo "    /usr/local/bin/acl-testapp-beta               [symlink]"
echo "    Config profile: com.methodology-beta.testcleaners-beta.vpnprofile  ⚠️  Configuration Profile!"
else
echo -e "  ${YELLOW}  [sudo was not used — system artifacts were not created]${NC}"
fi
echo ""

# --- FamilyOne ---
echo -e "${GREEN}${BOLD}▶ FamilyOne  [${GAMMA_ID}]  — DELETE COMPLETELY${NC}"
echo -e "  ${BOLD}Class 8 (family): delete ONLY Gamma-specific items, shared — must not!${NC}"
echo "    /Applications/FamilyOne.app"
echo "    ~/Library/Application Support/${VENDOR}/Gamma/   ✅ this subfolder only!"
echo "    ~/Library/Preferences/${GAMMA_ID}.plist"
echo "    ~/Library/Caches/${GAMMA_ID}/"
if [[ "$HAS_SUDO" == true ]]; then
echo "    /Library/Application Support/${VENDOR}/Gamma/    ✅ this subfolder only!"
fi
echo ""

echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║              MUST NOT TOUCH — TRAPS AND OTHER APPS DATA         ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Shared vendor (do not touch) ---
echo -e "${RED}${BOLD}⛔ Shared vendor folders  [${VENDOR}]  — DO NOT DELETE (FamilyTwo depends on them!)${NC}"
echo "    ~/Library/Application Support/${VENDOR}/Shared/   ← shared library"
echo "    ~/Library/Application Support/${VENDOR}/          ← entire vendor folder"
if [[ "$HAS_SUDO" == true ]]; then
echo "    /Library/Application Support/${VENDOR}/Shared/"
echo "    /Library/Application Support/${VENDOR}/"
fi
echo ""

# --- Delta (do not touch) ---
echo -e "${RED}${BOLD}⛔ FamilyTwo  [${DELTA_ID}]  — DO NOT DELETE (another app in the family!)${NC}"
echo "    /Applications/FamilyTwo.app"
echo "    ~/Library/Application Support/${VENDOR}/Delta/"
echo "    ~/Library/Preferences/${DELTA_ID}.plist"
echo "    ~/Library/Caches/${DELTA_ID}/"
if [[ "$HAS_SUDO" == true ]]; then
echo "    /Library/Application Support/${VENDOR}/Delta/"
fi
echo ""

# --- Trap E (do not touch) ---
echo -e "${RED}${BOLD}⛔ Trap E — «AlphaApp Tool»  [${TRAPE_ID}]  — DO NOT DELETE (similar name, different bundle ID!)${NC}"
echo "    /Applications/AlphaApp Tool.app"
echo "    ~/Library/Application Support/AlphaApp Tool/"
echo "    ~/Library/Preferences/${TRAPE_ID}.plist"
echo "    ~/Library/Caches/${TRAPE_ID}/"
echo ""

# --- Traps A/B/C (do not touch) ---
TRAP_DATE_DISPLAY=$(date +%Y-%m-%d)
echo -e "${RED}${BOLD}⛔ Traps A/B/C — user locations (Documents / Downloads / Desktop)${NC}"
echo -e "  ${YELLOW}Rule: detecting is allowed, not an error if skipped,"
echo -e "        but selecting for deletion without explicit user confirmation — not allowed${NC}"
echo ""
echo -e "  ${BOLD}Trap A — user data with similar names:${NC}"
echo "    ~/Documents/Alpha App/             ← user location, even if name matches"
echo "    ~/Downloads/AlphaApp-data/         ← hyphen, user data"
echo "    ~/Desktop/Alpha App Export/        ← word «Export» in name"
echo "    ~/Documents/Alpha_App_Backup/      ← underscores"
echo -e "  ${BOLD}Trap B — similar vendor name:${NC}"
echo "    ~/Documents/Methodology Test/              ← looks like «${VENDOR}»"
echo "    ~/Documents/TestVendor Files/              ← vendor-like name"
echo -e "  ${BOLD}Trap C — exports and backups with app name in filename:${NC}"
echo "    ~/Documents/AlphaApp-export-${TRAP_DATE_DISPLAY}.zip"
echo "    ~/Documents/AlphaApp-backup.json"
echo "    ~/Documents/AlphaApp-report.pdf"
echo "    ~/Documents/testcleaners-report.txt"
echo ""

echo -e "${BOLD}───────────────────────────────────────────────────────────────────${NC}"
echo "  Artifacts to delete (delete+system): $((TOTAL_DELETE + TOTAL_SYSTEM))"
echo "  Traps — DO NOT touch (trap+keep):    $((TOTAL_TRAP + TOTAL_KEEP))"
echo "  Profiles (require manual check):     ${TOTAL_PROFILE}"
echo -e "${BOLD}───────────────────────────────────────────────────────────────────${NC}"

# --- Save ground truth to file ---
write_ground_truth_plain "$GROUND_TRUTH_FILE"
success "Ground truth saved: ${GROUND_TRUTH_FILE}"
echo "  → Open the file any time for manual verification"
echo ""

# --- Instructions ---
echo ""
echo -e "${BOLD}NEXT STEPS:${NC}"
echo ""

if [[ "$HAS_SUDO" == true ]] && [[ -f "$AUDIT_DIR/BetaUtil-Profile.mobileconfig" ]]; then
    echo "1. Install the configuration profile:"
    echo "   open \"$AUDIT_DIR/BetaUtil-Profile.mobileconfig\""
    echo "   → System Settings → General → Device Management → Install"
    echo ""
    echo "2. Open the uninstaller being tested"
    echo ""
    echo "3. Uninstall THREE apps:"
    echo "   ✅ AlphaApp"
    echo "   ✅ BetaUtil"
    echo "   ✅ FamilyOne"
    echo ""
    echo "4. DO NOT uninstall:"
    echo "   ⛔ FamilyTwo (family — must stay)"
    echo "   ⛔ AlphaApp Tool (trap E — different bundle ID)"
    echo ""
    echo "5. Run verification:"
    echo "   ./quicktest-verify-en.sh"
else
    echo "1. Open the uninstaller being tested"
    echo ""
    echo "2. Uninstall THREE apps:"
    echo "   ✅ AlphaApp"
    echo "   ✅ BetaUtil"
    echo "   ✅ FamilyOne"
    echo ""
    echo "3. DO NOT uninstall:"
    echo "   ⛔ FamilyTwo (family — must stay)"
    echo "   ⛔ AlphaApp Tool (trap E — different bundle ID)"
    echo ""
    echo "4. Run verification:"
    echo "   ./quicktest-verify-en.sh"
fi
