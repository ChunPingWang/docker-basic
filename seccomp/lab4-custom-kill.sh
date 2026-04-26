#!/usr/bin/env bash
set -euo pipefail

WORK="$(mktemp -d -t seccomp-lab4-XXXX)"
trap "rm -rf $WORK" EXIT

echo "==> Same chmod block as Lab 3, but with SCMP_ACT_KILL_PROCESS instead."
echo "==> The kernel sends SIGSYS to the offender the moment it tries chmod."
echo "==> We let chmod itself be PID 1 of the container so the signal is unambiguous."
echo

cat > "$WORK/kill-on-chmod.json" <<'EOF'
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {
      "names": ["chmod", "fchmod", "fchmodat", "fchmodat2"],
      "action": "SCMP_ACT_KILL_PROCESS"
    }
  ]
}
EOF

echo "------------------------------------------------------------"
echo "Without the profile — chmod (PID 1) succeeds, exit code 0:"
echo "------------------------------------------------------------"
set +e
docker container run --rm ubuntu:22.04 chmod 600 /etc/hostname
rc=$?
set -e
echo "  exit code: $rc"

echo
echo "------------------------------------------------------------"
echo "With KILL_PROCESS profile — chmod is killed by SIGSYS:"
echo "------------------------------------------------------------"
set +e
docker container run --rm --security-opt seccomp="$WORK/kill-on-chmod.json" \
    ubuntu:22.04 chmod 600 /etc/hostname
rc=$?
set -e
echo "  exit code: $rc"
echo "  (159 = 128 + 31, where 31 is SIGSYS — kernel killed the process)"

echo
echo "==> Compare seccomp actions:"
echo "      SCMP_ACT_ALLOW         — pass through"
echo "      SCMP_ACT_ERRNO         — return EPERM, process continues"
echo "      SCMP_ACT_KILL_PROCESS  — SIGSYS, terminates the offender"
echo "      SCMP_ACT_LOG           — log and pass through (audit only)"
echo "      SCMP_ACT_TRACE         — hand off to a ptrace tracer"
echo
echo "==> Use ERRNO when you expect the app to handle it gracefully."
echo "==> Use KILL_PROCESS when reaching that syscall is a sure sign of compromise."
