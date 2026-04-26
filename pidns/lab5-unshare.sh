#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This lab uses unshare(1) and needs root (use sudo)." >&2
    exit 1
fi

echo "==> Use unshare to create a new PID namespace — no Docker involved."
echo "==> Flags:"
echo "      --pid          create a new PID namespace"
echo "      --fork         fork into the new namespace (the first process must be"
echo "                     a child, because the original process retains its old PID)"
echo "      --mount-proc   /proc reads PIDs through a special filesystem; remount"
echo "                     it inside the new ns so 'ps' sees the right view"
echo

unshare --pid --fork --mount-proc bash -c '
echo "[unshared bash] my own PID inside this namespace: $$"
echo "[unshared bash] (\$\$ is bash, the first process to enter the new ns,"
echo "                so the kernel assigns it PID 1.)"
echo
echo "[unshared bash] ps inside this namespace:"
ps -ef
echo
echo "[unshared bash] The host can still see this bash with its host PID via:"
echo "                ps -e | grep bash   (in another terminal)"
echo
echo "[unshared bash] Note: we ONLY unshared the PID namespace. We still share"
echo "                everything else (mount, network, user, ipc, uts) with the host."
echo "                A real container does unshare(CLONE_NEWPID|CLONE_NEWNET|"
echo "                CLONE_NEWNS|CLONE_NEWUTS|CLONE_NEWIPC|CLONE_NEWUSER|...) all at once."
'

echo
echo "==> Done. The unshared bash exited, the PID namespace was destroyed with it."
echo "==> No cleanup needed — namespaces vanish when their last process exits."
