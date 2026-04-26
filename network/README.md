---
title: 'Docker 網路工作坊'
disqus: hackmd
---

> ← 回到 [工作坊集索引](../README.md)

# Docker 網路工作坊

> 從零開始學習 Docker 網路。本工作坊會帶你動手體驗 Docker 的四種網路模式,並進一步認識 Linux network namespace 與 veth 的運作方式。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
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
| 作業系統 | Linux(建議 Ubuntu 22.04 以上)。macOS / Windows 上的 Docker Desktop 因為跑在 VM 裡,Lab 2 與 Lab 5 行為會不同 — 詳見 [頂層 README 的「在不同 OS 上跑」](../README.md#在不同作業系統上跑這些-lab) |
| Docker | 20.10 以上 |
| 權限 | 能執行 `docker` 指令(已加入 `docker` group,或用 `sudo`)。Lab 5 需要 `sudo` |
| 工具 | `bash`、`jq`(用於解析 JSON 輸出) |

確認環境:

```bash
docker --version
jq --version
```

## 專案結構

```
network/
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
A: Docker Desktop 在 macOS 上是用 VM 跑 Docker,所以「host」是指那台 VM,不是你的 Mac。要看到原汁原味的行為,請在 Linux 上做(或用 [頂層 README 的 nsenter trick](../README.md#-macos-docker-desktop))。

**Q: `Dockerfile-ubuntu-network` 為什麼裝了 `iproute2` 與 `iputils-ping`?**
A: 因為 Ubuntu 22.04 的 minimal 映像沒有 `ip` 與 `ping` 指令,沒有它們就無法在容器內驗證實驗結果。

**Q: 我可以跳著做嗎?**
A: Lab 1〜3 互相獨立,可以任意順序。Lab 4 必須先有 Lab 3 的容器在跑。Lab 5 與 Docker 無關,隨時可以做。

**Q: 跑 Lab 5 後我的網路怪怪的?**
A: Lab 5 只動了**新建的 namespace**,不會影響 host 主網路。只要記得 `ip netns del` 清理掉 namespace 即可。

---

###### tags: `Docker` `Networking` `Tutorial` `Linux Namespace`
