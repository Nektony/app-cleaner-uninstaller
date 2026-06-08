#!/bin/bash
# ============================================================================
# ACL QuickTest — Full cleanup of the test environment
# Methodology ACL v1.0.4
# ============================================================================
#
# Removes ALL artifacts created by quicktest-setup-en.sh:
# apps, services, profiles, traps, keychain.
#
# Usage:
#   ./quicktest-teardown-en.sh          # user-level
#   sudo ./quicktest-teardown-en.sh     # full cleanup including system-level
# ============================================================================

set -uo pipefail

# Bundle IDs — must match quicktest-setup-en.sh
ALPHA_ID="com.methodology-alpha.testcleaners-alpha"
BETA_ID="com.methodology-beta.testcleaners-beta"
GAMMA_ID="com.methodology.testcleaners-gamma"
DELTA_ID="com.methodology.testcleaners-delta"
TRAPE_ID="com.different-vendor.testapp"
VENDOR="MethodologyTestVendor"

if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_HOME=$(eval echo "~$SUDO_USER")
    REAL_USER="$SUDO_USER"
else
    REAL_HOME="$HOME"
    REAL_USER="$(whoami)"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "  ${GREEN}✓${NC} $1"; }
skip()    { echo -e "  ${YELLOW}–${NC} $1 (not found)"; }

remove_if_exists() {
    local path="$1"
    local desc="$2"
    if [[ -e "$path" ]]; then
        rm -rf "$path"
        info "Removed: $desc"
    else
        skip "$desc"
    fi
}

sudo_remove_if_exists() {
    local path="$1"
    local desc="$2"
    if sudo test -e "$path" 2>/dev/null; then
        sudo rm -rf "$path"
        info "Removed: $desc"
    else
        skip "$desc"
    fi
}

echo -e "\n${BOLD}═══ ACL QuickTest — Cleanup ═══${NC}\n"

# --- 1. Unload services ---
echo -e "${BOLD}Services:${NC}"

if launchctl list 2>/dev/null | grep -q "testcleaners-beta"; then
    launchctl unload "$REAL_HOME/Library/LaunchAgents/${BETA_ID}.agent.plist" 2>/dev/null && \
        info "Unloaded LaunchAgent" || skip "LaunchAgent (not loaded)"
else
    skip "LaunchAgent (not in launchctl)"
fi

if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
    if sudo launchctl list 2>/dev/null | grep -q "testcleaners-beta"; then
        sudo launchctl unload "/Library/LaunchDaemons/${BETA_ID}.daemon.plist" 2>/dev/null && \
            info "Unloaded LaunchDaemon" || skip "LaunchDaemon (not loaded)"
    else
        skip "LaunchDaemon (not in launchctl)"
    fi
fi

# --- 2. Applications ---
echo -e "\n${BOLD}Applications:${NC}"

remove_if_exists "/Applications/AlphaApp.app" "AlphaApp.app"
remove_if_exists "/Applications/BetaUtil.app" "BetaUtil.app"
remove_if_exists "/Applications/FamilyOne.app" "FamilyOne.app"
remove_if_exists "/Applications/FamilyTwo.app" "FamilyTwo.app"
remove_if_exists "/Applications/AlphaApp Tool.app" "AlphaApp Tool.app (Trap E)"

# --- 3. User-level artifacts ---
echo -e "\n${BOLD}User-level artifacts:${NC}"

# Alpha
remove_if_exists "$REAL_HOME/Library/Application Support/AlphaApp" "Alpha App Support"
remove_if_exists "$REAL_HOME/Library/Application Support/Alpha App" "Alpha App Support (space in name)"
remove_if_exists "$REAL_HOME/Library/Caches/${ALPHA_ID}" "Alpha Caches"
remove_if_exists "$REAL_HOME/Library/Logs/AlphaApp" "Alpha Logs"
remove_if_exists "$REAL_HOME/Library/Containers/${ALPHA_ID}" "Alpha Container"
remove_if_exists "$REAL_HOME/Library/Group Containers/group.${ALPHA_ID}" "Group Container"
remove_if_exists "$REAL_HOME/Library/HTTPStorages/${ALPHA_ID}" "Alpha HTTPStorages"
remove_if_exists "$REAL_HOME/Library/Saved Application State/${ALPHA_ID}.savedState" "Alpha Saved State"

# Beta
remove_if_exists "$REAL_HOME/Library/Application Support/BetaUtil" "Beta App Support (user)"
remove_if_exists "$REAL_HOME/Library/LaunchAgents/${BETA_ID}.agent.plist" "Beta LaunchAgent"
remove_if_exists "$REAL_HOME/Library/Caches/${BETA_ID}" "Beta Caches"

# Gamma / Delta / Vendor
remove_if_exists "$REAL_HOME/Library/Application Support/${VENDOR}" "Vendor folder (user)"
remove_if_exists "$REAL_HOME/Library/Caches/${GAMMA_ID}" "Gamma Caches"
remove_if_exists "$REAL_HOME/Library/Caches/${DELTA_ID}" "Delta Caches"

# Trap E
remove_if_exists "$REAL_HOME/Library/Application Support/AlphaApp Tool" "Trap E App Support"
remove_if_exists "$REAL_HOME/Library/Caches/${TRAPE_ID}" "Trap E Caches"

# Preferences (via defaults)
for bid in "$ALPHA_ID" "$BETA_ID" "$GAMMA_ID" "$DELTA_ID" "$TRAPE_ID"; do
    if [[ -f "$REAL_HOME/Library/Preferences/${bid}.plist" ]]; then
        defaults delete "$bid" 2>/dev/null
        info "Removed plist: $bid"
    else
        skip "plist: $bid"
    fi
done

# Keychain
if security find-generic-password -s "AlphaApp" 2>/dev/null > /dev/null; then
    security delete-generic-password -s "AlphaApp" 2>/dev/null && \
        info "Removed Keychain entry" || skip "Keychain (removal error)"
else
    skip "Keychain"
fi

# --- 4. System-level artifacts ---
echo -e "\n${BOLD}System-level artifacts:${NC}"

if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
    sudo_remove_if_exists "/Library/LaunchDaemons/${BETA_ID}.daemon.plist" "Beta LaunchDaemon"
    sudo_remove_if_exists "/Library/PrivilegedHelperTools/${BETA_ID}.helper" "Beta Privileged Helper"
    sudo_remove_if_exists "/Library/Application Support/BetaUtil" "Beta App Support (system)"
    sudo_remove_if_exists "/Library/Application Support/${VENDOR}" "Vendor folder (system)"
    sudo_remove_if_exists "/usr/local/bin/acl-testapp-beta" "Symlink"

    # PKG receipt
    if pkgutil --pkgs 2>/dev/null | grep -q "testcleaners-beta"; then
        PKGS=$(pkgutil --pkgs 2>/dev/null | grep "testcleaners-beta")
        while IFS= read -r pkg_id; do
            sudo pkgutil --forget "$pkg_id" > /dev/null 2>&1 && \
                info "Forgot PKG receipt: $pkg_id" || skip "PKG receipt: $pkg_id"
        done <<< "$PKGS"
    else
        skip "PKG receipts"
    fi

    # Configuration Profile
    if profiles list 2>/dev/null | grep -q "testcleaners-beta"; then
        sudo profiles remove -identifier "${BETA_ID}.vpnprofile" 2>/dev/null && \
            info "Removed configuration profile" || \
            echo -e "  ${YELLOW}⚠${NC} Configuration profile: remove manually → System Settings → General → Device Management"
    else
        skip "Configuration profile"
    fi
else
    echo -e "  ${YELLOW}⚠${NC} No sudo — system-level artifacts skipped"
    echo "  For full cleanup: sudo ./quicktest-teardown-en.sh"
fi

# --- 5. Traps ---
echo -e "\n${BOLD}Traps (Documents/Downloads/Desktop):${NC}"

remove_if_exists "$REAL_HOME/Documents/Alpha App" "Trap A: Documents/Alpha App"
remove_if_exists "$REAL_HOME/Downloads/AlphaApp-data" "Trap A: Downloads/AlphaApp-data"
remove_if_exists "$REAL_HOME/Desktop/Alpha App Export" "Trap A: Desktop/Alpha App Export"
remove_if_exists "$REAL_HOME/Documents/Alpha_App_Backup" "Trap A: Documents/Alpha_App_Backup"
remove_if_exists "$REAL_HOME/Documents/Methodology Test" "Trap B: Documents/Methodology Test"
remove_if_exists "$REAL_HOME/Documents/TestVendor Files" "Trap B: Documents/TestVendor Files"

# Trap C — individual files
for f in "$REAL_HOME"/Documents/AlphaApp-export-*.zip \
         "$REAL_HOME/Documents/AlphaApp-backup.json" \
         "$REAL_HOME/Documents/AlphaApp-report.pdf" \
         "$REAL_HOME/Documents/testcleaners-report.txt"; do
    if [[ -e "$f" ]]; then
        rm -f "$f"
        info "Removed: $(basename "$f")"
    fi
done

# --- 6. Audit directory ---
echo -e "\n${BOLD}Audit directory:${NC}"
remove_if_exists "$REAL_HOME/uninstall-audit" "~/uninstall-audit"

# --- Done ---
echo -e "\n${BOLD}═══ Cleanup complete ═══${NC}\n"
echo "All QuickTest artifacts removed."
echo "You can run quicktest-setup-en.sh to start a new test."
