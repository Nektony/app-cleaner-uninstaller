#!/bin/bash
# ============================================================================
# ACL QuickTest — Verify results after uninstaller run
# Methodology ACL v1.0.4
# ============================================================================
#
# Reads the manifest, checks what was deleted / what remains, calculates metrics.
#
# Usage:
#   ./quicktest-verify-en.sh
#   sudo ./quicktest-verify-en.sh    # to check system-level artifacts
# ============================================================================

set -euo pipefail

AUDIT_DIR="$HOME/uninstall-audit"
MANIFEST="$AUDIT_DIR/quicktest-manifest.txt"
REPORT="$AUDIT_DIR/quicktest-report.txt"

if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_HOME=$(eval echo "~$SUDO_USER")
else
    REAL_HOME="$HOME"
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# --- Checks ---
if [[ ! -f "$MANIFEST" ]]; then
    echo -e "${RED}[ERROR]${NC} Manifest not found: $MANIFEST"
    echo "Run quicktest-setup-en.sh first"
    exit 1
fi

HAS_SUDO=false
if [[ $EUID -eq 0 ]] || sudo -v 2>/dev/null; then
    HAS_SUDO=true
fi

# --- Counters ---
TP=0          # True Positive: artifact deleted (correct)
FN=0          # False Negative: artifact NOT deleted (missed)
FP=0          # False Positive: trap deleted (dangerous!)
TN=0          # True Negative: trap still present (correct)
COLLATERAL=0  # Collateral damage: Delta/vendor artifacts deleted

FN_LIST=()
FP_LIST=()
COLLATERAL_LIST=()
TP_LIST=()

# --- Existence check ---
path_exists() {
    local type="$1"
    local path="$2"

    # Non-file artifacts: keychain entry, PKG receipt
    if [[ "$path" == keychain:* ]]; then
        local service="${path#keychain:}"
        security find-generic-password -s "$service" 2>/dev/null > /dev/null
        return $?
    fi

    if [[ "$path" == pkg:* ]]; then
        local pkg_id="${path#pkg:}"
        pkgutil --pkg-info "$pkg_id" 2>/dev/null > /dev/null
        return $?
    fi

    case "$type" in
        delete|trap|keep)
            [[ -e "$path" ]]
            ;;
        system)
            if [[ "$HAS_SUDO" == true ]]; then
                sudo test -e "$path" 2>/dev/null
            else
                test -e "$path" 2>/dev/null
            fi
            ;;
        profile)
            # path = profile identifier
            profiles list 2>/dev/null | grep -q "$path" 2>/dev/null
            ;;
        *)
            [[ -e "$path" ]]
            ;;
    esac
}

# ============================================================================
# MANIFEST ANALYSIS
# ============================================================================

echo -e "\n${BOLD}═══ ACL QuickTest — Verify Results ═══${NC}\n"

while IFS='|' read -r type path category desc; do
    # Skip comments and empty lines
    [[ "$type" =~ ^#.*$ ]] && continue
    [[ -z "$type" ]] && continue

    # Expand $HOME/$REAL_HOME in paths (in case manifest was created by a different user)
    path="${path/#\$HOME/$REAL_HOME}"

    case "$type" in
        delete|system)
            # Artifact MUST BE DELETED
            if path_exists "$type" "$path"; then
                FN=$((FN + 1))
                FN_LIST+=("  ❌ MISSED: $path ($desc)")
            else
                TP=$((TP + 1))
                TP_LIST+=("  ✅ Deleted: $path")
            fi
            ;;
        trap)
            # Trap MUST REMAIN
            if path_exists "$type" "$path"; then
                TN=$((TN + 1))
            else
                FP=$((FP + 1))
                FP_LIST+=("  🚨 TRAP DELETED: $path ($desc)")
            fi
            ;;
        keep)
            # Delta / shared vendor — MUST REMAIN
            if path_exists "$type" "$path"; then
                TN=$((TN + 1))
            else
                COLLATERAL=$((COLLATERAL + 1))
                COLLATERAL_LIST+=("  💥 COLLATERAL DAMAGE: $path ($desc)")
            fi
            ;;
        profile)
            # Profile MUST BE DELETED
            if path_exists "$type" "$path"; then
                FN=$((FN + 1))
                FN_LIST+=("  ❌ MISSED: profile $path ($desc)")
            else
                TP=$((TP + 1))
                TP_LIST+=("  ✅ Deleted: profile $path")
            fi
            ;;
    esac
done < "$MANIFEST"

# --- Additional checks ---

# Check launchctl — any loaded services still running?
ORPHAN_AGENTS=""
if launchctl list 2>/dev/null | grep -q "testcleaners-beta"; then
    ORPHAN_AGENTS="com.methodology-beta.testcleaners-beta (user agent)"
fi
if [[ "$HAS_SUDO" == true ]]; then
    if sudo launchctl list 2>/dev/null | grep -q "testcleaners-beta"; then
        ORPHAN_AGENTS="${ORPHAN_AGENTS:+$ORPHAN_AGENTS, }com.methodology-beta.testcleaners-beta (system daemon)"
    fi
fi

# Check pkgutil — any receipt left behind?
PKG_ORPHAN=""
if pkgutil --pkgs 2>/dev/null | grep -q "testcleaners-beta"; then
    PKG_RECEIPT=$(pkgutil --pkgs 2>/dev/null | grep "testcleaners-beta")
    # Check: files deleted but receipt remains?
    PKG_FILES_EXIST=false
    while IFS= read -r pkg_id; do
        while IFS= read -r pkg_file; do
            if [[ -e "/$pkg_file" ]]; then
                PKG_FILES_EXIST=true
                break 2
            fi
        done < <(pkgutil --files "$pkg_id" 2>/dev/null)
    done <<< "$PKG_RECEIPT"

    if [[ "$PKG_FILES_EXIST" == false ]]; then
        # Files deleted, receipt remains — acceptable (see test 1.6)
        PKG_ORPHAN="receipt remains but files are deleted (acceptable)"
    else
        PKG_ORPHAN="receipt AND files still present"
    fi
fi

# Check Keychain
KEYCHAIN_ENTRY=""
if security find-generic-password -s "AlphaApp" 2>/dev/null > /dev/null; then
    KEYCHAIN_ENTRY="Keychain entry for Alpha still present (not deleted)"
fi

# ============================================================================
# METRICS
# ============================================================================

TOTAL_SHOULD_DELETE=$((TP + FN))
TOTAL_SHOULD_KEEP=$((TN + FP + COLLATERAL))

if [[ $TOTAL_SHOULD_DELETE -gt 0 ]]; then
    RECALL=$(echo "scale=1; $TP * 100 / $TOTAL_SHOULD_DELETE" | bc)
else
    RECALL="N/A"
fi

if [[ $((TP + FP)) -gt 0 ]]; then
    PRECISION=$(echo "scale=1; $TP * 100 / ($TP + $FP)" | bc)
else
    PRECISION="N/A"
fi

# ============================================================================
# L1 SAFETY GATES
# ============================================================================

L1_PASS=true
L1_RESULTS=()

# 1.1 Precision = 100%
if [[ $FP -eq 0 ]]; then
    L1_RESULTS+=("  1.1 Precision = 100%               ✅ (FP=0)")
else
    L1_RESULTS+=("  1.1 Precision = 100%               ❌ FAIL (FP=$FP)")
    L1_PASS=false
fi

# 1.2 No user data deleted without opt-in
TRAP_A_DELETED=false
for item in "${FP_LIST[@]+"${FP_LIST[@]}"}"; do
    if [[ "$item" == *"trap_a"* ]] || [[ "$item" == *"trap_c"* ]]; then
        TRAP_A_DELETED=true
    fi
done
if [[ "$TRAP_A_DELETED" == false ]]; then
    L1_RESULTS+=("  1.2 No user data deleted           ✅")
else
    L1_RESULTS+=("  1.2 No user data deleted           ❌ FAIL")
    L1_PASS=false
fi

# 1.3 Shared folders
if [[ $COLLATERAL -eq 0 ]]; then
    L1_RESULTS+=("  1.3 Shared folders                 ✅")
else
    L1_RESULTS+=("  1.3 Shared folders                 ❌ FAIL (collateral damage: $COLLATERAL)")
    L1_PASS=false
fi

# 1.4 Root helpers
HELPER_EXISTS=false
if [[ "$HAS_SUDO" == true ]]; then
    if sudo test -e "/Library/PrivilegedHelperTools/com.methodology-beta.testcleaners-beta.helper" 2>/dev/null; then
        HELPER_EXISTS=true
    fi
fi
if [[ "$HELPER_EXISTS" == false ]] || [[ "$HAS_SUDO" == false ]]; then
    L1_RESULTS+=("  1.4 Root helpers                   ✅")
else
    L1_RESULTS+=("  1.4 Root helpers                   ❌ FAIL (helper still present)")
    L1_PASS=false
fi

# 1.5 Orphaned launchd services
if [[ -z "$ORPHAN_AGENTS" ]]; then
    L1_RESULTS+=("  1.5 Launchd services               ✅")
else
    L1_RESULTS+=("  1.5 Launchd services               ❌ FAIL ($ORPHAN_AGENTS)")
    L1_PASS=false
fi

# 1.6 PKG receipts
if [[ -z "$PKG_ORPHAN" ]] || [[ "$PKG_ORPHAN" == *"acceptable"* ]]; then
    L1_RESULTS+=("  1.6 PKG receipts                   ✅ ${PKG_ORPHAN:+($PKG_ORPHAN)}")
else
    L1_RESULTS+=("  1.6 PKG receipts                   ❌ FAIL ($PKG_ORPHAN)")
    L1_PASS=false
fi

# 1.7 Profiles/Extensions
PROFILE_EXISTS=false
if profiles list 2>/dev/null | grep -q "testcleaners-beta" 2>/dev/null; then
    PROFILE_EXISTS=true
fi
if [[ "$PROFILE_EXISTS" == false ]]; then
    L1_RESULTS+=("  1.7 Profiles/Extensions            ✅")
else
    L1_RESULTS+=("  1.7 Profiles/Extensions            ⚠️ Configuration profile still present (check warning)")
fi

# 1.8 and 1.9 — require manual tester observation
L1_RESULTS+=("  1.8 Confirmation before deletion    ❓ (check manually)")
L1_RESULTS+=("  1.9 Stability                       ❓ (check manually)")

# ============================================================================
# REPORT OUTPUT
# ============================================================================

echo -e "${BOLD}─── METRICS ───${NC}"
echo ""
echo "  Artifacts to delete:     $TOTAL_SHOULD_DELETE"
echo "  Deleted (TP):            $TP"
echo "  Missed (FN):             $FN"
echo "  Traps deleted (FP):      $FP"
echo "  Collateral damage:       $COLLATERAL"
echo ""
echo "  Precision:  ${PRECISION}%"
echo "  Recall:     ${RECALL}%"

echo ""
echo -e "${BOLD}─── L1 SAFETY GATES ───${NC}"
echo ""
for r in "${L1_RESULTS[@]}"; do
    echo -e "$r"
done
echo ""
if [[ "$L1_PASS" == true ]]; then
    echo -e "  ${GREEN}${BOLD}L1 VERDICT: PASS${NC}"
else
    echo -e "  ${RED}${BOLD}L1 VERDICT: FAIL — Not recommended${NC}"
fi

if [[ ${#FP_LIST[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}─── 🚨 FALSE POSITIVES (traps deleted!) ───${NC}"
    for item in "${FP_LIST[@]}"; do
        echo -e "$item"
    done
fi

if [[ ${#COLLATERAL_LIST[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}─── 💥 COLLATERAL DAMAGE ───${NC}"
    for item in "${COLLATERAL_LIST[@]}"; do
        echo -e "$item"
    done
fi

if [[ ${#FN_LIST[@]} -gt 0 ]]; then
    echo ""
    echo -e "${BOLD}─── ❌ MISSED ARTIFACTS ───${NC}"
    for item in "${FN_LIST[@]}"; do
        echo -e "$item"
    done
fi

if [[ -n "$KEYCHAIN_ENTRY" ]]; then
    echo ""
    echo -e "${YELLOW}[INFO]${NC} $KEYCHAIN_ENTRY"
fi

# ============================================================================
# SAVE REPORT TO FILE
# ============================================================================

{
    echo "ACL QuickTest Report — $(date -Iseconds)"
    echo "========================================"
    echo ""
    echo "Uninstaller: _______________"
    echo "Version:     _______________"
    echo ""
    echo "METRICS"
    echo "  To delete:         $TOTAL_SHOULD_DELETE"
    echo "  Deleted:           $TP"
    echo "  Missed:            $FN"
    echo "  FP:                $FP"
    echo "  Collateral:        $COLLATERAL"
    echo "  Precision:         ${PRECISION}%"
    echo "  Recall:            ${RECALL}%"
    echo ""
    echo "L1 SAFETY GATES"
    for r in "${L1_RESULTS[@]}"; do
        echo "$r" | sed 's/\x1b\[[0-9;]*m//g'
    done
    echo ""
    if [[ "$L1_PASS" == true ]]; then
        echo "L1 VERDICT: PASS"
    else
        echo "L1 VERDICT: FAIL"
    fi
    echo ""
    if [[ ${#FP_LIST[@]} -gt 0 ]]; then
        echo "FALSE POSITIVES:"
        for item in "${FP_LIST[@]}"; do
            echo "$item" | sed 's/\x1b\[[0-9;]*m//g'
        done
    fi
    if [[ ${#COLLATERAL_LIST[@]} -gt 0 ]]; then
        echo "COLLATERAL DAMAGE:"
        for item in "${COLLATERAL_LIST[@]}"; do
            echo "$item" | sed 's/\x1b\[[0-9;]*m//g'
        done
    fi
    if [[ ${#FN_LIST[@]} -gt 0 ]]; then
        echo "MISSED ARTIFACTS:"
        for item in "${FN_LIST[@]}"; do
            echo "$item" | sed 's/\x1b\[[0-9;]*m//g'
        done
    fi
    echo ""
    echo "DELETED ARTIFACTS:"
    for item in "${TP_LIST[@]+"${TP_LIST[@]}"}"; do
        echo "$item" | sed 's/\x1b\[[0-9;]*m//g'
    done
} > "$REPORT"

echo ""
echo -e "${BOLD}─── SUMMARY ───${NC}"
echo ""
echo "Report saved: $REPORT"
echo ""
echo "Next steps:"
if [[ "$L1_PASS" == true ]]; then
    echo "  ✅ QuickTest passed — app is ready for full methodology test"
    echo "  → Run the full test per methodology (02-methodology-v1.md)"
else
    echo "  ❌ QuickTest failed — full test not needed"
    echo "  → Record the failures in the report"
fi
echo ""
echo "To clean up: ./quicktest-teardown-en.sh"
