---
title: 'Docker 網路工作坊'
disqus: hackmd
---

# Docker 網路工作坊

> 一份從零開始學習 Docker 網路的實作教材。本工作坊會帶你動手體驗 Docker 的四種網路模式,並進一步認識 Linux network namespace 與 veth 的運作方式。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [在不同作業系統上跑這些 Lab](#在不同作業系統上跑這些-lab)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:Docker 的四種網路模式](#背景知識docker-的四種網路模式)
- [Lab 1 — none 模式](#lab-1--none-模式)
- [Lab 2 — host 模式](#lab-2--host-模式)
- [Lab 3 — bridge 模式](#lab-3--bridge-模式)
- [Lab 4 — container 模式(共享網路)](#lab-4--container-模式共享網路)
- [Lab 5 — 自己動手做 veth pair](#lab-5--自己動手做-veth-pair)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 說出 Docker 四種網路模式(`none`、`host`、`bridge`、`container`)的差異與使用時機。
2. 用 `docker inspect`、`ip addr`、`lsns` 等指令觀察容器的網路設定。
3. 理解 Linux **network namespace** 是什麼,以及容器為什麼能擁有獨立的網路堆疊。
4. 親手用 `ip netns` 與 `veth pair` 建立兩個獨立 namespace 之間的虛擬連線。

## 先備知識

- 會用 terminal 下基本指令(`cd`、`ls`、`cat`)。
- 知道 Docker 是什麼,並做過 `docker run hello-world`。
- **不需要**懂 Linux kernel,也**不需要**寫過網路程式。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| 作業系統 | Linux(建議 Ubuntu 22.04 以上)。macOS / Windows 上的 Docker Desktop 因為跑在 VM 裡,Lab 2 與 Lab 5 行為會不同 |
| Docker | 20.10 以上 |
| 權限 | 能執行 `docker` 指令(已加入 `docker` group,或用 `sudo`)。Lab 5 需要 `sudo` |
| 工具 | `bash`、`jq`(用於解析 JSON 輸出) |

確認環境:

```bash
docker --version
jq --version
```

## 在不同作業系統上跑這些 Lab

本 repo 裡的工作坊分成兩類:

- **「跑容器」類 lab**:全部用 `docker run` / `docker compose`,任何裝得起 Docker 的 OS 都能跑。
- **「動 host kernel」類 lab**(每個工作坊的 Lab 5、加上整個 `runtime/` 與 `rootless/`):用 `ip netns` / `unshare` / `mount -t overlay` / `runc` / `ctr` 等指令直接操作 host 的 kernel,**這些只有在 Linux 主機上跑才看得到原汁原味**。

下面說明每個 OS 的差別。

### 🐧 Linux (native) — 推薦,所有 lab 都能跑

任何主流 distro(Ubuntu / Fedora / Arch / Debian)都行,kernel ≥ 5.4 即可。本工作坊在 Ubuntu 22.04+ / 24.04 上開發與驗證。

需注意:

- **cgroup v2**:`cgroups/` 與 `runtime/` 工作坊預設 cgroup v2(modern Ubuntu / Fedora 預設)。若是還在 v1 的舊系統(Ubuntu 20.04 預設、CentOS 7),Lab 5 的 cgroupfs 路徑會不一樣,需要自己改。
- **AppArmor 限制**:Ubuntu 24.04+ 預設 `kernel.apparmor_restrict_unprivileged_userns=1`,會擋住 unprivileged user namespace 的 uid_map 寫入。`caps/` 與 `rootless/` 的 Lab 5 已經做了 fallback,fallback 時請用 `sudo` 重跑或 `sudo sysctl kernel.apparmor_restrict_unprivileged_userns=0` 暫時放行。
- **AppArmor 設定檔**:某些 distro(Ubuntu 預設)會給 docker container 套 `docker-default` AppArmor profile,可能造成額外的 permission denied。除錯時用 `--security-opt apparmor=unconfined` 排除。

### 🍎 macOS (Docker Desktop)

Docker Desktop 在 macOS 上是把 Docker 跑在一個 LinuxKit / VZ.framework VM 裡,Mac 本身沒有 Linux kernel。後果:

- **「跑容器」類 lab 全部正常**:`docker run`、`docker compose` 跟在 Linux 上一樣。
- **「動 host kernel」類 lab 不能在 Mac shell 裡直接跑**,因為 Mac 沒有 `ip netns` / `unshare` / `runc`。**但**你還有兩個選項:

  **選項 1:進 Docker Desktop 的 VM 跑**

  ```bash
  # 用 nsenter 進到 VM 的 PID 1,等於進到 LinuxKit 主機
  docker run -it --rm --privileged --pid=host alpine \
    nsenter -t 1 -m -u -n -i sh
  ```

  進去之後 `apt`/`apk` 不見得有(LinuxKit 是極簡 image),但 `ip netns`、`unshare`、`mount` 都在。把 lab 的內容複製貼上跑即可。

  **選項 2:Lima / Colima / OrbStack 跑一個輕量 Linux VM**

  ```bash
  # 例如 OrbStack
  brew install orbstack
  orb create ubuntu lab
  orb shell lab    # 進入一個正常的 Ubuntu shell,這裡所有 lab 都正常
  ```

- **`host` 網路模式**:macOS 的 `--network=host` 從 Docker 4.34+ 開始支援(beta);更早的版本下,「host」是指 VM 不是你的 Mac,你看到的 `ip addr` 是 VM 的網路。本 repo 的 `network/` Lab 2 在 Mac 上行為跟 Linux 不同,README 裡有提示。

- **效能**:VM 多了一層虛擬化,啟動容器與 file system I/O(尤其是 bind mount)會比 Linux 慢。

### 🪟 Windows

兩種架構:

#### Windows + WSL2 (Docker Desktop 預設) — 推薦

Docker Desktop 在 Windows 上預設用 WSL2,等於有一個正版 Linux kernel。**最佳體驗是在 WSL2 的 Ubuntu shell 裡 clone 並跑這個 repo**:

```powershell
# 在 PowerShell 啟用 WSL2 + Ubuntu
wsl --install -d Ubuntu

# 進 WSL2 shell
wsl
# 之後就跟 Linux 一樣
sudo apt update && sudo apt install -y git jq
git clone https://github.com/ChunPingWang/docker-basic.git
cd docker-basic
./build.sh
./lab1-none.sh
```

WSL2 限制:

- **AppArmor 不裝**:WSL2 的 Ubuntu 預設沒有 AppArmor,反而 `caps/` 與 `rootless/` Lab 5 在 WSL2 比 native Ubuntu 24.04 更順(沒有 apparmor restriction)。
- **systemd**:WSL 預設沒啟用 systemd。Docker Desktop 自帶 docker daemon 不需要 systemd,但 `runtime/` Lab 1 觀察 process tree 時看不到 `system.slice/...` 路徑(用 cgroupfs cgroup driver 而非 systemd)。改用 `cgroupfs` 是 WSL 的預設行為,觀察結果略有差異。
- **本機檔案系統**:在 WSL2 內存 `/home/<user>/...` 比存 `/mnt/c/...`(Windows 檔案系統)快幾十倍。clone repo 到 WSL2 home 不要放 `/mnt/c`。

#### Windows + Hyper-V VM(Docker Desktop 老設定 / Pro 版)

行為跟 macOS 一樣 — Docker 在獨立 VM 裡,host kernel 類 lab 要用 nsenter trick 進 VM 才能跑。一般已不建議,直接切 WSL2 較好。

### 跨 OS 相容性矩陣

| 工作坊 | Lab 1-4 (Docker 類) | Lab 5 (host kernel 類) |
|---|:---:|:---:|
| `network/` | ✅ 全 OS | Linux / WSL2 only |
| `storage/` | ✅ 全 OS | Linux / WSL2 only(`mount -t overlay`) |
| `cgroups/` | ✅ 全 OS | Linux only,需 cgroup v2 |
| `pidns/` | ✅ 全 OS | Linux / WSL2 only(`unshare`) |
| `caps/` | ✅ 全 OS | Linux / WSL2 only(`unshare -U`) |
| `image-internals/` | ✅ 全 OS(全部 5 個 lab 都是 docker 類) | — |
| `seccomp/` | ✅ 全 OS | — |
| `runtime/` | Lab 1 ✅ 全 OS | Lab 2-5 Linux only(需 host 上有 `ctr`、`runc`) |
| `rootless/` | — | Linux only |
| `compose/` | ✅ 全 OS | — |

✅ = native / Docker Desktop / WSL2 都行
Linux only = 需要 host 是 Linux,macOS 用 nsenter trick 或 Lima/OrbStack 也可

### 動手前的快速判斷

- **我只想學 Docker 用法**:任何 OS 都行,跳過每個工作坊的 Lab 5 與 `runtime/` `rootless/`。
- **我想徹底懂底層**:用 Linux(native 或 WSL2)。
- **我在公司 Mac 上**:用 OrbStack / Lima / Colima 起一個 Linux VM,從那裡跑 repo。Docker Desktop 也行,只是 host kernel 類 lab 要用 nsenter trick。
- **我在 Windows**:啟用 WSL2、把 repo clone 進 WSL2 home,從那邊跑。

## 專案結構

```
.
├── Dockerfile-ubuntu-network   # 帶有網路工具的 Ubuntu 映像檔定義
├── build.sh                    # 建立映像檔
├── lab1-none.sh                # Lab 1: none 模式
├── lab2-host.sh                # Lab 2: host 模式
├── lab3-bridge.sh              # Lab 3: bridge 模式
├── lab4-container.sh           # Lab 4: container 模式(需傳入目標 ID)
├── lab5-veth.sh                # Lab 5: 手動建立 veth pair(需 sudo)
└── README.md                   # 本文件
```

## 快速開始

```bash
# 1. 建立練習用的映像檔(只需做一次)
./build.sh

# 2. 依序執行各個 Lab
./lab1-none.sh
./lab2-host.sh
./lab3-bridge.sh

# Lab 4 需要先在另一個 terminal 執行 lab3,
# 然後用 `docker ps` 取得它的 container id 再傳入:
./lab4-container.sh <container_id>

# Lab 5 需要 root 權限
sudo ./lab5-veth.sh
```

> 💡 **小提醒**:每個 Lab 容器都加了 `--rm`,所以你只要在容器內 `exit`,容器就會自動刪除,不會留下殘留。

---

## 背景知識:Docker 的四種網路模式

容器其實是一個**共享 host 核心、但擁有自己 namespace 的程序**。網路 namespace 讓每個容器可以擁有自己的網卡、路由表、iptables 規則。Docker 在這個基礎上,提供了四種常用的網路模式:

| 模式 | 行為 | 適合場景 |
|---|---|---|
| `none` | 只有 `lo`,沒有對外網路 | 安全沙箱、純運算工作 |
| `host` | 直接共用 host 的網路 namespace,沒有隔離 | 對效能極度敏感、需要監聽 host port 的工具 |
| `bridge` | 預設模式。Docker 建立一張虛擬橋接 `docker0`,容器透過 NAT 連外 | 大多數應用、一般 web 服務 |
| `container:<id>` | 與另一個容器共用同一個網路 namespace | sidecar 模式、debug、Pod 概念的雛形 |

接下來我們會一個一個動手玩。

---

## Lab 1 — none 模式

**目標**:看到一個「沒有網路」的容器長什麼樣子。

```bash
./lab1-none.sh
# 等同於:docker container run -it --rm --network=none ubuntu-network
```

進入容器後,試試:

```bash
ip addr        # 應該只看到 lo (loopback)
ping 8.8.8.8   # 應該完全失敗
```

開另一個 terminal,用以下指令觀察 host 上 Docker 對這個容器的看法:

```bash
docker ps                                    # 找到 container id
docker container inspect --format='{{ json .NetworkSettings }}' <container_id> | jq
```

**你應該看到**:`Networks` 是空的、`IPAddress` 是空字串。這就是 `none` 模式的意思 — Docker 幫你建了一個全新的 net namespace,但**什麼網卡都沒有插進去**。

---

## Lab 2 — host 模式

**目標**:看到一個「沒有網路隔離」的容器。

```bash
./lab2-host.sh
```

進入容器後:

```bash
ip addr   # 看到的網卡跟 host 完全一樣
hostname  # 仍然是容器自己的 hostname(其他 namespace 還是有隔離)
```

用 `ifconfig` 在 host 與容器內各執行一次,你會發現 IP 一模一樣。容器**沒有自己的 network namespace**,直接共用 host 的。

> ⚠️ **macOS / Windows 注意**:Docker Desktop 把 Docker 跑在 Linux VM 裡,所以 host 模式的「host」指的是 VM 不是你的 Mac。
> ⚠️ **安全提醒**:host 模式等於把容器的 process 直接放進你的網路堆疊,失去了一層隔離,正式環境要謹慎使用。

---

## Lab 3 — bridge 模式

**目標**:認識 Docker 預設的網路模式。

```bash
./lab3-bridge.sh
```

進入容器後:

```bash
ip addr   # 看到 eth0 拿到一個 172.17.x.x 的 IP
ping 8.8.8.8   # 應該成功
```

在 host 執行:

```bash
ip addr show docker0   # docker0 就是那座「橋」
```

**運作原理**:Docker daemon 啟動時建立了一個叫 `docker0` 的虛擬交換器。每個 bridge 模式的容器都會被插上一根虛擬網路線(veth pair)的一端,另一端接到 `docker0`。對外的流量再透過 iptables 做 NAT 出去。Lab 5 我們會自己動手做一遍這個概念。

---

## Lab 4 — container 模式(共享網路)

**目標**:讓兩個容器**共用同一張網卡**,理解 Kubernetes Pod 的雛形。

步驟:

1. 開 terminal A,啟動 Lab 3 的 bridge 容器並**保持不退出**:
   ```bash
   ./lab3-bridge.sh
   ```
2. 開 terminal B,查它的 container id:
   ```bash
   docker ps
   ```
3. 仍在 terminal B,用該 id 啟動第二個容器:
   ```bash
   ./lab4-container.sh <container_id>
   ```

在第二個容器內執行 `ip addr`,你會發現它的 IP **與第一個容器一模一樣**。

進一步驗證:

```bash
# 在兩個容器內分別執行
lsns
```

兩邊的 **net namespace id 應該相同**,但其他 namespace(pid、mnt 等)是不同的。這代表它們共用網路堆疊,但其他資源仍然隔離 — 這就是 Kubernetes 的 Pod 把多個 container 「綁」在一起的方式。

**有趣的實驗**:把第一個容器(terminal A)`exit` 掉,因為它是「網路擁有者」,第二個容器就會瞬間失去網路。

---

## Lab 5 — 自己動手做 veth pair

**目標**:不靠 Docker,純粹用 Linux 指令把 Lab 3 那個「兩端虛擬網路線」做出來。看完這個 Lab,你會徹底懂 bridge 模式背後在幹什麼。

```bash
sudo ./lab5-veth.sh
```

腳本會做這些事:

1. 建立兩個 network namespace `ns0`、`ns1`(像是兩個迷你容器)。
2. 建立一對 veth(`veth0` ↔ `veth1`),這是一條虛擬網路線,兩端不能分開。
3. 把 `veth0` 丟進 `ns0`,`veth1` 丟進 `ns1`。
4. 在兩端各設一個 IP(`172.18.0.2` 與 `172.18.0.3`),把介面 up 起來。

驗證連通性:

```bash
sudo ip netns exec ns0 ping -c 3 172.18.0.3
```

清理(腳本不會自動刪 namespace,讓你有時間觀察):

```bash
sudo ip netns del ns0
sudo ip netns del ns1
```

**觀念連結**:Docker 的 bridge 模式就是把這個流程自動化 — 它把其中一端塞進容器的 net namespace,另一端接到 `docker0` 上。理解這個 Lab 後,Docker 網路就不再是黑盒子了。

---

## 常用指令速查

```bash
# 看所有 namespace
sudo lsns
sudo lsns -t net          # 只看 network namespace

# 看容器網路設定
docker container inspect --format='{{ json .NetworkSettings }}' <id> | jq

# 看 host 上的 docker 網路
docker network ls
docker network inspect bridge

# 看網路介面
ip addr
ip link list
ip route

# network namespace 操作
sudo ip netns list
sudo ip netns add  <name>
sudo ip netns del  <name>
sudo ip netns exec <name> <command>
```

## 常見問題 FAQ

**Q: 為什麼 `lab2-host.sh` 在我的 Mac 上行為跟教材不同?**
A: Docker Desktop 在 macOS 上是用 VM 跑 Docker,所以「host」是指那台 VM,不是你的 Mac。要看到原汁原味的行為,請在 Linux 上做。

**Q: `Dockerfile-ubuntu-network` 為什麼裝了 `iproute2` 與 `iputils-ping`?**
A: 因為 Ubuntu 22.04 的 minimal 映像沒有 `ip` 與 `ping` 指令,沒有它們就無法在容器內驗證實驗結果。

**Q: 我可以跳著做嗎?**
A: Lab 1〜3 互相獨立,可以任意順序。Lab 4 必須先有 Lab 3 的容器在跑。Lab 5 與 Docker 無關,隨時可以做。

**Q: 跑 Lab 5 後我的網路怪怪的?**
A: Lab 5 只動了**新建的 namespace**,不會影響 host 主網路。只要記得 `ip netns del` 清理掉 namespace 即可。

---

###### tags: `Docker` `Networking` `Tutorial` `Linux Namespace`
