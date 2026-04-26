#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t seccomp-lab3-XXXX)"
trap "rm -rf $WORK" EXIT

echo "==> Write a custom seccomp profile that BLOCKS the chmod family of syscalls."
echo "==> Action SCMP_ACT_ERRNO makes the syscall return EPERM (process keeps running)."
echo

cat > "$WORK/no-chmod.json" <<'EOF'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {
      "names": ["chmod", "fchmod", "fchmodat", "fchmodat2"],
      "action": "SCMP_ACT_ERRNO",
      "errnoRet": 1
    }
  ]
}
EOF

echo "==> Profile contents:"
cat "$WORK/no-chmod.json"

echo
echo "------------------------------------------------------------"
echo "Default container — chmod works:"
echo "------------------------------------------------------------"
docker container run --rm ubuntu:22.04 bash -c '
touch /tmp/x
chmod 600 /tmp/x && echo "chmod OK" && stat -c "%a %n" /tmp/x
'

echo
echo "------------------------------------------------------------"
echo "With our custom profile — chmod fails with EPERM:"
echo "------------------------------------------------------------"
docker container run --rm --security-opt seccomp="$WORK/no-chmod.json" ubuntu:22.04 bash -c '
touch /tmp/x
chmod 600 /tmp/x 2>&1 || echo "(chmod blocked by seccomp)"
echo "Process is still alive — only the chmod syscall returned EPERM."
'

echo
echo "==> Punchline: with SCMP_ACT_ERRNO the kernel rejects the syscall but"
echo "==> the process continues. Most apps will log the failure and try a"
echo "==> different code path."
