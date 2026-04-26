#!/usr/bin/env bash
set -euo pipefail

REAL_UID=$(id -u)
REAL_USER=$(id -un)

echo "==> Use unshare to create a new USER namespace."
echo "==> User namespaces are designed to be creatable WITHOUT sudo,"
echo "==> but on Ubuntu 24.04+ AppArmor blocks unprivileged uid_map writes by default."
echo
echo "==> Caller's UID outside the new ns: $REAL_UID ($REAL_USER)"
echo

# ---- Part 1: works for any caller (no sudo needed) ----
echo "------------------------------------------------------------"
echo "Part 1: unshare -U with NO uid_map (always works)"
echo "------------------------------------------------------------"
echo "==> Without writing uid_map, unmapped UIDs become 'nobody' (65534)."
echo

unshare -U bash -c '
echo "[unshared] id seen inside the namespace:"
id
echo
echo "[unshared] /proc/self/uid_map (empty — no mapping yet):"
cat /proc/self/uid_map
'

# ---- Part 2: needs root OR apparmor disabled ----
echo
echo "------------------------------------------------------------"
echo "Part 2: --map-root-user (be 'root' inside the ns)"
echo "------------------------------------------------------------"

apparmor_restrict=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)
echo "==> kernel.apparmor_restrict_unprivileged_userns = $apparmor_restrict"

can_map=true
if [[ "$apparmor_restrict" == "1" && "$REAL_UID" != "0" ]]; then
    can_map=false
fi

if [[ "$can_map" != "true" ]]; then
    echo
    echo "==> Skipped: AppArmor is restricting unprivileged uid_map writes,"
    echo "==> and we are not root. Re-run as:"
    echo "      sudo $0"
    echo "==> Or temporarily relax the restriction (NOT recommended for prod):"
    echo "      sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0"
    exit 0
fi

unshare --user --map-root-user --pid --fork --mount-proc bash -c '
echo "[unshared] id inside (with --map-root-user):"
id
echo
echo "[unshared] /proc/self/uid_map shows the mapping:"
cat /proc/self/uid_map
echo "                ^ inside-uid  outside-uid  range"
echo
echo "[unshared] read-side test: ls -l /etc/shadow shows what the kernel"
echo "          tells US about ownership — through the user_ns lens:"
ls -l /etc/shadow
echo
echo "[unshared] my pid in this ns: $$"
ps -ef
'

if [[ "$REAL_UID" != "0" ]]; then
    echo
    echo "==> Note: when called as a normal user, kernel access checks use your"
    echo "==> REAL uid ($REAL_UID), so writing /etc/shadow / loading kernel modules"
    echo "==> / etc. are still blocked even though you appear root inside the ns."
    echo "==> (We can not demo this part now because AppArmor required us to use sudo.)"
fi

echo
echo "==> Punchline: user namespace lets a UNPRIVILEGED process appear as root"
echo "==> INSIDE its own ns, while the kernel uses the real UID for access checks."
echo "==> This is the foundation of:"
echo "==>   - rootless Docker / Podman"
echo "==>   - rootless Kubernetes runtimes"
echo "==>   - --userns-remap (Docker daemon flag)"
