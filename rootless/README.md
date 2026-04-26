---
title: 'Rootless Docker 工作坊'
disqus: hackmd
---

# Rootless Docker 工作坊

> 一份說明 **rootless Docker / Podman** 是怎麼做到「不需要 root 也能跑容器」的工作坊。比起前面六份,這份比較偏觀念性 — 因為**完整的 rootless 環境需要安裝多個套件**,我們不在 lab 裡幫使用者改機器,改用 4 個 lab 把運作原理拆給你看。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:rootless 是什麼,為什麼](#背景知識rootless-是什麼為什麼)
- [Lab 1 — 觀察當前的 rootful Docker](#lab-1--觀察當前的-rootful-docker)
- [Lab 2 — `/etc/subuid` 與 `/etc/subgid`:rootless 的前置](#lab-2--etcsubuid-與-etcsubgidrootless-的前置)
- [Lab 3 — 用 `unshare -U` 親身體會 user namespace](#lab-3--用-unshare--u-親身體會-user-namespace)
- [Lab 4 — rootless 架構詳解(本 lab 為說明性)](#lab-4--rootless-架構詳解本-lab-為說明性)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 解釋為什麼 rootful Docker 是個資安顧慮(daemon 與容器 root 都是 host root)。
2. 看懂 `/etc/subuid` / `/etc/subgid` 的內容,以及它如何讓一般使用者可以 map 出多個 UID。
3. 列出 rootless docker 的關鍵零件:**rootlesskit、newuidmap、slirp4netns、fuse-overlayfs**,並說明各自負責什麼。
4. 知道 rootless 的限制(port < 1024、host 網路模式等)與替代方案(podman、lima、sysbox)。

## 先備知識

- 跑過前面的 caps 工作坊更佳 — Lab 3 沿用了那邊的 `unshare -U`。
- 對 Linux user / group 概念熟悉。

## 環境需求

| 項目 | 說明 |
|---|---|
| Linux | 任何發行版,kernel 3.8+ 即可建 user namespace |
| `/etc/subuid` 必須有目前使用者的條目 | Ubuntu 預設會自動建,確認用 `grep $(whoami) /etc/subuid` |
| 工具 | `bash`、`unshare` |

## 專案結構

```
rootless/
├── lab1-rootful.sh        # Lab 1: 觀察 rootful daemon
├── lab2-subuid.sh         # Lab 2: /etc/subuid mapping range
├── lab3-userns-demo.sh    # Lab 3: 動手 unshare -U
├── lab4-architecture.sh   # Lab 4: rootless 架構解說(純 echo)
└── README.md
```

> ⚠️ **本工作坊只有 4 個 lab,而不是傳統的 5 個** — 因為「真的安裝 rootless Docker」會動到使用者的環境(裝 4-5 個套件、改 systemd user service、改 PATH 與 DOCKER_HOST)。Lab 4 把完整的安裝指令列出來,你可以自行決定要不要動手。

## 快速開始

```bash
./lab1-rootful.sh
./lab2-subuid.sh
./lab3-userns-demo.sh   # 在 Ubuntu 24.04+ 可能需要 sudo
./lab4-architecture.sh
```

---

## 背景知識:rootless 是什麼,為什麼

**Rootful Docker(預設):**

```
你 (UID 1000) -> docker CLI -> dockerd (UID 0, root) -> containerd -> runc -> 容器
                                ^^^^^^^^^^^^^^^^^^^^
                                整個 daemon 是 root 在跑
```

危險在哪?

- **dockerd 漏洞** = host root。Docker daemon 有過 CVE,例如 [CVE-2019-5736](https://nvd.nist.gov/vuln/detail/CVE-2019-5736) 是 runc 漏洞讓容器內可覆蓋 host 的 runc binary。
- **`docker` group = root**:能操作 docker socket 等於能起 `--privileged` 容器,也等於 host root。
- **多租戶不適用**:在共用機器上不能讓多個使用者各自跑容器(任何人都會拿到 root)。

**Rootless Docker:**

```
你 (UID 1000) -> rootlesskit -> dockerd (在 user-ns 內看是 root,host 看是 UID 1000)
                  ▲ 建 user-ns, 寫 uid_map, 起 slirp4netns
                                                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                                        daemon 漏洞 → 拿到的「root」實際只是你
```

關鍵:**「root」這個身份不再有特殊意義** — 只是一個在 user namespace 裡看起來像 0 的 UID,kernel 做存取檢查時用真實 UID(1000)。即使 dockerd 被打穿,攻擊者拿到的也只是「你」這個使用者的權限,不是 host root。

接下來的 Lab 會把這個過程拆給你看。

---

## Lab 1 — 觀察當前的 rootful Docker

```bash
./lab1-rootful.sh
```

腳本會印 `dockerd`、`containerd` 是 root 在跑,並啟一個容器確認容器內 root 對應 host root。

**你應該看到**:

- `dockerd` 與 `containerd` 的 user 欄位都是 `root`。
- 容器內 `id` 是 `uid=0(root)`,`/proc/self/uid_map` 是 `0  0  4294967295`(對應到 host 全部 UID 範圍)。

---

## Lab 2 — `/etc/subuid` 與 `/etc/subgid`:rootless 的前置

```bash
./lab2-subuid.sh
```

腳本印當前使用者在 `/etc/subuid` 與 `/etc/subgid` 的 entry。

**檔案格式**:

```
user:start_id:count
rexwang:100000:65536
```

意思是「rexwang 這個使用者擁有從 100000 開始連續 65536 個 UID 的使用權」。需要這個是因為 user namespace 一次只能 map 一段(或多段)連續的 UID。container 內 root(UID 0)map 到你真實 UID,容器內 UID 1...65535 map 到 100000...165535。這樣 nginx (UID 33)、postgres (UID 999)等容器內非 root UID 都有對應。

> 💡 沒有 `/etc/subuid` 條目時 rootless 跑不起來。Ubuntu 預設會自動建,Arch 等發行版可能要手動加(`sudo usermod --add-subuids 100000-165535 $USER`)。

---

## Lab 3 — 用 `unshare -U` 親身體會 user namespace

```bash
./lab3-userns-demo.sh
```

腳本用 `unshare --user --map-root-user --pid --fork --mount-proc bash` 建一個 user-ns + pid-ns,在裡面我們看起來是 root,但 kernel 對外仍把我們當原本的 UID。

> **Ubuntu 24.04+ 注意**:預設 `apparmor_restrict_unprivileged_userns=1` 會擋 unprivileged 寫 uid_map。腳本會偵測並提示用 sudo 重跑(這是 caps 工作坊 Lab 5 同樣的議題)。

**你應該看到**:

- 進 ns 內 `id` 是 `uid=0(root)`。
- `cat /proc/self/uid_map` 是 `0 <你的UID> 1`(只 map 你自己這一個 UID,沒用 subuid 範圍)。
- `CapEff` 全部 bit 設起來 — 在這個 ns 裡你是「真 root」(對 ns 內的東西,不對 host)。

要做更逼真的 rootless 模擬(用 subuid 多段 mapping),需要 `newuidmap` / `newgidmap`(在 `uidmap` 套件)。本 lab 不安裝套件,你可以自己 `sudo apt install uidmap`。

---

## Lab 4 — rootless 架構詳解(本 lab 為說明性)

```bash
./lab4-architecture.sh
```

純 echo,把 rootless docker 的整套零件畫出來,並列出實際安裝指令(自行決定要不要動手)。整理:

**啟動鏈**:

```
你的 shell
  └─ rootlesskit dockerd-rootless.sh
       ├─ 建 user-ns / mount-ns / net-ns
       ├─ newuidmap 寫 uid_map(讀 /etc/subuid 授權)
       ├─ slirp4netns 在 ns 與 host 間搭 TAP + user-mode TCP/IP
       ├─ fuse-overlayfs 在 user space 做 overlay(因為 user-ns 不能 mount)
       └─ exec dockerd
            └─ 你 docker run 的容器,再做一次 namespace 隔離
```

**安裝**:

```bash
sudo apt install -y uidmap dbus-user-session fuse-overlayfs
curl -fsSL https://get.docker.com/rootless | sh
export PATH=$HOME/bin:$PATH
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
systemctl --user start docker
docker info | grep -i rootless     # 預期看到 "rootless: true"
```

---

## 常用指令速查

```bash
# 查 subuid / subgid
grep $(whoami) /etc/subuid /etc/subgid

# 看任何 process 的 user-ns mapping
cat /proc/<pid>/uid_map
cat /proc/<pid>/gid_map

# 用 unshare 試做
unshare --user --map-root-user --pid --fork --mount-proc bash

# 進階:用 newuidmap 自己做 multi-range mapping(需 uidmap 套件)
sudo apt install uidmap
unshare --user bash -c 'sleep 9999' &
PID=$!
newuidmap $PID 0 $(id -u) 1  1 100000 65536
newgidmap $PID 0 $(id -g) 1  1 100000 65536
nsenter --user --target $PID

# Rootless docker 啟動 / 切換
systemctl --user start docker
export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
docker info | grep -i rootless

# Podman(預設 rootless)
podman run --rm alpine echo hi
```

## 常見問題 FAQ

**Q: rootless docker 跟把 daemon 跑在 `--user` 下不一樣嗎?**
A: 不一樣。`--user` 只改容器 UID,daemon 還是 root。rootless 是 daemon 本身就跑在非 root + user-ns 裡,從根本上消除 daemon-as-root 的攻擊面。

**Q: K8s 也有 rootless 嗎?**
A: 有,但比較零碎。kubelet 一般還是 root,但可以配合:
- runtime 端用 rootless containerd(早期 alpha)
- 透過 `runAsNonRoot: true` 強制 Pod 用非 root user
- usernsremap mode(K8s 1.28+ alpha)
完整 rootless K8s 在 sig-node 還在進化,目前生產環境多用「rootless wrappers」(如 sysbox)而非全套 rootless。

**Q: rootless 為什麼有 port < 1024 的限制?**
A: 因為 rootless docker 的 daemon 在 user-ns 裡,綁低 port 需要 `CAP_NET_BIND_SERVICE`,這個 cap 在 user-ns 裡有,但對外還是要真實 UID 有 cap 才能用 — 一般使用者沒有。解法是 `sudo setcap cap_net_bind_service=+ep $(which rootlesskit)`,讓 rootlesskit 自帶這個 cap;rootlesskit 再轉發給 dockerd。

**Q: rootless 比 rootful 慢嗎?**
A: 啟動稍慢(多了 newuidmap / slirp4netns 的初始化),網路速度會被 slirp4netns 的 user-mode TCP stack 拖慢一些(視版本約 -10 ~ -30%)。儲存若用 fuse-overlayfs 也比 native overlayfs 慢一點。如果效能敏感、又想要 rootless,考慮 podman + crun(更輕)+ 在支援 idmapped mounts 的 kernel 上原生 overlayfs。

**Q: 我同事說「我們直接禁用 docker.sock 掛載就好了」,這跟 rootless 哪個比較好?**
A: 兩件事互補。禁 docker.sock 掛載防止「容器內透過 socket 起更多 root 容器」,但若容器自己 escape,還是 host root。rootless 從根本消除這條路徑。理想是兩個都做。

---

###### tags: `Linux` `Docker` `Rootless` `Security` `Tutorial`
