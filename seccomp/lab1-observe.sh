#!/usr/bin/env bash
set -euo pipefail

echo "==> Look at /proc/self/status inside a container."
echo "==> Seccomp values:"
echo "      0 = no filter   1 = strict   2 = filter (BPF program loaded)"
echo

echo "------------------------------------------------------------"
echo "Default container — Docker's default profile is loaded:"
echo "------------------------------------------------------------"
docker container run --rm ubuntu:22.04 grep -E '^Seccomp|Seccomp_filters' /proc/self/status

echo
echo "------------------------------------------------------------"
echo "--security-opt seccomp=unconfined — no filter at all:"
echo "------------------------------------------------------------"
docker container run --rm --security-opt seccomp=unconfined ubuntu:22.04 \
    grep -E '^Seccomp|Seccomp_filters' /proc/self/status

echo
echo "==> Punchline: by default, every container has a BPF seccomp filter loaded."
echo "==> Docker's profile blocks ~50 dangerous syscalls (kexec_load, reboot,"
echo "==> swapon, etc.) so they fail-fast with EPERM even if the process has"
echo "==> the matching capability."
