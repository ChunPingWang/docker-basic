#!/usr/bin/env bash
set -euo pipefail

echo "==> Rootless containers need to map a RANGE of UIDs/GIDs into the user ns,"
echo "==> so 'root' (0) inside maps to your real UID, but UID 1, 2, ... inside"
echo "==> map to a chunk of UIDs that the kernel reserves for you."
echo "==> That allocation lives in /etc/subuid and /etc/subgid."
echo

ME=$(whoami)

echo "------------------------------------------------------------"
echo "Allocations for $ME:"
echo "------------------------------------------------------------"
echo "/etc/subuid:"
grep "^${ME}:" /etc/subuid 2>/dev/null || echo "  (no entry — rootless wont work)"
echo
echo "/etc/subgid:"
grep "^${ME}:" /etc/subgid 2>/dev/null || echo "  (no entry — rootless wont work)"

echo
echo "------------------------------------------------------------"
echo "Reading the format:    user:start_id:count"
echo "------------------------------------------------------------"
START=$(awk -F: -v u="$ME" '$1==u {print $2; exit}' /etc/subuid)
COUNT=$(awk -F: -v u="$ME" '$1==u {print $3; exit}' /etc/subuid)
echo "  $ME has UIDs $START .. $((START + COUNT - 1)) (total $COUNT) reserved."
echo
echo "  In a rootless container:"
echo "      container UID 0 -> host UID $(id -u)        (caller, single map)"
echo "      container UID 1 -> host UID $START          (start of subuid range)"
echo "      container UID 2 -> host UID $((START+1))"
echo "      ..."
echo "      container UID $COUNT -> host UID $((START + COUNT - 1))"
echo
echo "==> The kernel uses these mappings via newuidmap(1) (a setuid helper)."
echo "==> If /etc/subuid is empty, you can not run a rootless container."
echo
echo "------------------------------------------------------------"
echo "All users with subuid allocations on this system:"
echo "------------------------------------------------------------"
cat /etc/subuid
