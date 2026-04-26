#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
================================================================
Rootless Docker / Podman 架構解說(本 lab 為說明性,不執行 install)
================================================================

問題:rootful Docker 的 dockerd 必須是 root;若 daemon 漏洞或容器 escape,
       攻擊者立刻拿到 host root。

解法:把 dockerd 自己跑在一個 user namespace 裡,該 namespace 內它「看似 root」,
       但對 host 而言它只是個一般使用者。要做到這件事,需要拼一些零件:

  ┌────────────────────────────────────────────────────────────────────┐
  │  user space tooling                                                │
  │                                                                    │
  │  1. rootlesskit                                                    │
  │     負責進新的 user-ns / mount-ns / net-ns,呼叫 newuidmap 寫好    │
  │     uid_map,然後在 ns 裡 exec 你想跑的東西(這裡是 dockerd)。     │
  │                                                                    │
  │  2. newuidmap / newgidmap (uidmap package, setuid)                 │
  │     寫 /proc/<pid>/uid_map 需要 CAP_SETUID。一般使用者沒有,所以  │
  │     這兩支是 setuid root 的小程式,讀 /etc/subuid 確認你有資格,  │
  │     然後幫你寫進去。                                               │
  │                                                                    │
  │  3. slirp4netns(或 vpnkit)                                       │
  │     net-ns 裡沒有真網卡。slirp4netns 在 host 與 ns 之間搭 TAP +    │
  │     做 user-mode TCP/IP stack(類似 QEMU 的 slirp),提供出網能力。│
  │                                                                    │
  │  4. fuse-overlayfs                                                  │
  │     overlayfs 在 user-ns 裡權限受限,有些 distro 不允許 mount。   │
  │     fuse-overlayfs 用 FUSE 把 overlayfs 行為實作出來,跑在 user   │
  │     space,不需要 mount syscall 權限。                             │
  │                                                                    │
  │  5. dbus-user-session                                              │
  │     systemd --user 用 dbus 跟 system 講話,rootlesskit 也用它管理 │
  │     daemon 生命週期。                                              │
  └────────────────────────────────────────────────────────────────────┘

啟動流程:

  你的 user shell
      │ rootlesskit dockerd-rootless.sh
      ▼
  rootlesskit:
      - 建 user-ns + mount-ns + net-ns
      - newuidmap: 把 [container 0..N] 對到 [host UID, host subuid 起..]
      - 啟 slirp4netns 做 NAT 出網
      - exec dockerd
      ▼
  dockerd 在新 ns 內,看自己是 root,管 image/container/network
      │
      ▼
  你 docker run 起的容器,在「rootless 父環境」內再做一次 namespace 隔離。
      容器內 UID 0 對到 dockerd 的 UID 0(就是你的真實 UID)。

實際安裝(若要試,自行衡量):

  # 1. 安裝相依
  sudo apt install -y uidmap dbus-user-session fuse-overlayfs

  # 2. 安裝 rootless 套件 (Docker 官方腳本)
  curl -fsSL https://get.docker.com/rootless | sh

  # 3. 把 ~/bin 加進 PATH
  export PATH=$HOME/bin:$PATH
  export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock

  # 4. 啟動使用者層的 dockerd
  systemctl --user start docker

  # 5. 確認
  docker info | grep -E 'rootless|Cgroup Version'
  # 應該看到 "rootless: true"

限制:

  - 預設不能綁 < 1024 的 port(沒 CAP_NET_BIND_SERVICE 跨 ns)。
    可用 `setcap cap_net_bind_service=+ep $(which rootlesskit)` 解決。
  - 共享 host 網卡(host 模式)行為受限。
  - cgroup v1 上某些 cgroup 控制不可用;建議搭 cgroup v2。
  - 第一次啟動較慢、若用 fuse-overlayfs 比 overlayfs 慢一點。

替代方案:

  - **Podman**:預設就是 rootless,沒有 daemon。docker CLI 相容。
  - **Lima**:macOS 上跑 rootless Linux VM 中的 podman/docker,Docker Desktop 替代。
  - **Sysbox**:Nestybox 的 runtime,讓 rootful 容器內也能跑 systemd / docker。

EOF
