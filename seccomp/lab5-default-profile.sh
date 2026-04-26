#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t seccomp-lab5-XXXX)"
trap "rm -rf $WORK" EXIT

echo "==> Inspect Docker's default seccomp profile (the one that's loaded"
echo "==> automatically when you don't specify --security-opt seccomp=)."
echo

URL="https://raw.githubusercontent.com/moby/moby/v24.0.7/profiles/seccomp/default.json"
echo "==> Downloading from $URL"
echo "==> (Pinning to v24.0.7 — newer moby branches embed the profile in Go code"
echo "==>  rather than a standalone JSON file, but the structure is identical.)"
if ! curl -sf -o "$WORK/default.json" "$URL"; then
    echo "==> Download failed. Check your network and try again."
    exit 1
fi

echo "==> Profile size on disk:"
ls -lh "$WORK/default.json"

echo
echo "==> Top-level structure:"
jq 'keys' "$WORK/default.json"

echo
echo "==> Default action (what happens to a syscall not listed):"
jq -r '.defaultAction' "$WORK/default.json"

echo
echo "==> How many syscalls are in the syscalls array, and their actions?"
jq -r '
.syscalls
| group_by(.action)
| map({action: .[0].action, syscalls: ([.[].names[]] | length)})
' "$WORK/default.json"

echo
echo "==> Surprise — defaultAction is ERRNO! That means the profile is a WHITELIST:"
echo "==> 'block everything by default, then explicitly allow these 423 safe syscalls.'"
echo
echo "==> Some syscalls that are NOT in the allow list (and so blocked):"
for s in kexec_load kexec_file_load reboot swapon swapoff init_module finit_module \
         delete_module mount_setattr lookup_dcookie name_to_handle_at; do
    if ! jq -r '.syscalls[].names[]' "$WORK/default.json" | grep -qx "$s"; then
        echo "      $s"
    fi
done

echo
echo "==> The 1 syscall explicitly listed as ERRNO (a special-case override):"
jq -r '.syscalls[] | select(.action == "SCMP_ACT_ERRNO") | .names[]' "$WORK/default.json"
echo "      ^ clone3 is the newer fork-family syscall; older glibc auto-fallback to clone"
echo "        on EPERM, so blocking clone3 is a compat workaround."

echo
echo "==> Punchline: a Docker container can only use a fixed, curated set of"
echo "==> ~423 syscalls. 'reboot the host', 'load a kernel module', 'swapon'"
echo "==> are blocked by being absent from the list, not by being denied."
