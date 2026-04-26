#!/usr/bin/env bash
set -euo pipefail

echo "==> Demo: pretend to be root inside a user namespace using only unshare."
echo "==> This is the same kernel feature rootless docker / podman use,"
echo "==> just exposed without all the daemon plumbing."
echo

REAL_UID=$(id -u)
REAL_USER=$(id -un)
echo "==> Real UID outside: $REAL_UID ($REAL_USER)"
echo

apparmor_restrict=$(cat /proc/sys/kernel/apparmor_restrict_unprivileged_userns 2>/dev/null || echo 0)
if [[ "$apparmor_restrict" == "1" && "$REAL_UID" != "0" ]]; then
    echo "==> AppArmor is blocking unprivileged uid_map writes on this system."
    echo "==> Re-run with sudo (use --map-current-user to keep your UID, no real root):"
    echo "      sudo $0"
    echo "==> Or: sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0"
    exit 0
fi

echo "------------------------------------------------------------"
echo "Run a shell inside a new user-ns, with caller UID -> 0 mapped:"
echo "------------------------------------------------------------"
unshare --user --map-root-user --pid --fork --mount-proc bash -c '
echo "[unshared] my id:"
id
echo
echo "[unshared] /proc/self/uid_map (single 1-row mapping):"
cat /proc/self/uid_map
echo
echo "[unshared] capabilities (CapEff inside the user-ns):"
grep ^CapEff /proc/self/status
echo "[unshared] (we have ALL caps inside the ns, but only relative to this ns —"
echo "           the kernel still uses the real UID for any cross-ns operation)"
echo
echo "[unshared] my pid in the new pid-ns:"
echo "  $$"
'

echo
echo "==> A rootless docker container is exactly this idea, plus:"
echo "      - subuid range mapped (so non-root UIDs inside also work)"
echo "      - net namespace + slirp4netns to give it a network stack"
echo "      - mount namespace + fuse-overlayfs so layered images work"
echo "      - all wrapped by rootlesskit (which sets up the namespaces / mounts /"
echo "        sysctls / port forwarding before exec'ing dockerd)"
