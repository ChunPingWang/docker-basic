#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "This lab manipulates network namespaces and must run as root (use sudo)." >&2
    exit 1
fi

ip link list

ip netns add ns0
ip netns add ns1
ip netns list

ip link add veth0 type veth peer name veth1

ip link set veth0 netns ns0
ip link set veth1 netns ns1

ip netns list

ip netns exec ns0 ip addr add 172.18.0.2/24 dev veth0
ip netns exec ns0 ip link set veth0 up

ip netns exec ns1 ip addr add 172.18.0.3/24 dev veth1
ip netns exec ns1 ip link set veth1 up

echo "--- ns0 ---"
ip netns exec ns0 ip addr
echo "--- ns1 ---"
ip netns exec ns1 ip addr

echo
echo "Cleanup with:"
echo "  sudo ip netns del ns0 && sudo ip netns del ns1"
