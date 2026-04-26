---
title: 'Linux capabilities 與 user namespace 工作坊'
disqus: hackmd
---

> ← 回到 [工作坊集索引](../README.md)

# Linux capabilities 與 user namespace 工作坊

> 一份從零開始學習 **Linux capabilities** 與 **user namespace** 的實作教材。本工作坊會帶你看清楚「容器內的 root 不是真的 root」這件事:capabilities 怎麼把 root 的權力切碎、`--user` 怎麼一鍵降權、user namespace 怎麼讓 unprivileged process「假裝」當 root。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:root 不是一個權力,是 38 個](#背景知識root-不是一個權力是-38-個)
- [Lab 1 — 容器預設拿到哪些 capabilities](#lab-1--容器預設拿到哪些-capabilities)
- [Lab 2 — `--cap-drop` / `--cap-add` 看權力怎麼被切走](#lab-2----cap-drop----cap-add-看權力怎麼被切走)
- [Lab 3 — `--privileged` 是核彈級的全給](#lab-3----privileged-是核彈級的全給)
- [Lab 4 — `--user` 一鍵降權](#lab-4----user-一鍵降權)
- [Lab 5 — 自己用 `unshare -U` 做一個 user namespace](#lab-5--自己用-unshare--u-做一個-user-namespace)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 解釋什麼是 capabilities,並說出至少 5 個常見 capability 對應的能力(NET_RAW、SYS_ADMIN、CHOWN、KILL、SETUID 等)。
2. 用 `--cap-drop` / `--cap-add` 替容器精準調整可用權力。
3. 理解 `--privileged` 為什麼是反模式,並能找出更精細的替代寫法。
4. 用 `--user` 把容器降權為非 root,知道這帶來哪些保護。
5. 用 `unshare -U --map-root-user` 親手做一個 user namespace,看到 UID 映射的本體。

## 先備知識

- 會用 terminal、知道 UID / root 是什麼。
- 知道 Docker 的基本指令(`docker run`、`docker exec`)。
- 看過前面四份工作坊(network / storage / cgroups / pidns)更佳,但不強制。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| 作業系統 | Linux,kernel 3.8+(預設都有 user namespace) |
| Docker | 20.10 以上 |
| 權限 | 能跑 `docker`。**Lab 5 不需要 sudo!** user namespace 開放給一般使用者 |
| 工具 | `bash`、`unshare`(util-linux 內建)、`capsh`(libcap2-bin,容器內已裝) |

## 專案結構

```
caps/
├── Dockerfile-ubuntu-caps   # Ubuntu + libcap2-bin + iputils-ping + iproute2
├── build.sh
├── lab1-default.sh          # Lab 1: 預設 capabilities
├── lab2-drop.sh             # Lab 2: --cap-drop / --cap-add
├── lab3-privileged.sh       # Lab 3: --privileged 全給
├── lab4-user.sh             # Lab 4: --user 降權
├── lab5-userns.sh           # Lab 5: 手動 unshare -U(不需 sudo)
└── README.md
```

## 快速開始

```bash
./build.sh
./lab1-default.sh
./lab2-drop.sh
./lab3-privileged.sh
./lab4-user.sh
./lab5-userns.sh   # 注意:不需要 sudo
```

---

## 背景知識:root 不是一個權力,是 38 個

UNIX 早期的 root(UID 0)是「一切權力」的同義詞。但這帶來一個問題 — 任何需要某個小特權的程式(例如 `ping` 需要 raw socket、`mount` 需要操作 fs)都得拿全套 root 權力,風險過大。

Linux 2.2 開始把 root 的權力切成許多獨立的 **capability**,每個 capability 對應一組可以做的事。今天大約有 41 個(`man capabilities`)。下面挑常見的:

| Capability | 它授權什麼 |
|---|---|
| `CAP_NET_RAW` | 開 raw socket / packet socket(`ping`、`tcpdump`) |
| `CAP_NET_BIND_SERVICE` | 綁 < 1024 的 port |
| `CAP_NET_ADMIN` | 改網路設定(routes、interfaces、iptables) |
| `CAP_SYS_ADMIN` | 萬用權限(mount、namespace 操作、許多 syscall),**最危險** |
| `CAP_SYS_TIME` | 改系統時間 |
| `CAP_SYS_MODULE` | 載入 kernel module |
| `CAP_CHOWN` | `chown` 任意檔案 |
| `CAP_SETUID` / `CAP_SETGID` | 改變 process 的 UID/GID |
| `CAP_KILL` | kill 任意 process |
| `CAP_DAC_OVERRIDE` | 繞過檔案權限檢查 |

每個 process 有四個 capability set:Permitted、Effective、Inheritable、Bounding。最常看的是 **CapEff**(Effective):「這個 process **此刻能用**的 capability」。

### Docker 預設給容器的 capability

Docker 啟容器時,預設給 14 個 capability(較新版本可能略有變動):

```
CHOWN, DAC_OVERRIDE, FSETID, FOWNER, MKNOD, NET_RAW,
SETGID, SETUID, SETFCAP, SETPCAP, NET_BIND_SERVICE,
SYS_CHROOT, KILL, AUDIT_WRITE
```

**沒給**:`SYS_ADMIN`、`SYS_TIME`、`SYS_MODULE`、`NET_ADMIN`、`SYS_PTRACE`、`SYS_BOOT` 等(危險的全部沒給)。

所以「容器內 root」其實是個削弱版的 root。Lab 1 會讓你親眼看到。

### user namespace:更激進的做法

capabilities 是「權力的細分」。**user namespace** 則是「UID 的虛擬化」:你可以在新 namespace 裡是 root(UID 0),但 kernel 在做存取控制時把你映射回原本的真實 UID。所以你看起來是 root,實際上沒有 host 上 root 的權力。

這是 rootless container 的基石。Lab 5 會手動做一個讓你看清楚。

---

## Lab 1 — 容器預設拿到哪些 capabilities

**目標**:用 `capsh` 解碼 `/proc/self/status` 的 `CapEff`,看 Docker 預設給多少。

```bash
./lab1-default.sh
```

**你應該看到**:

- 容器內 `id` 顯示 `uid=0(root)`,但 capability 集合只是 host root 的子集。
- `capsh --decode=` 列出大約 14 個 cap_xxx,沒有 `cap_sys_admin`、`cap_net_admin` 等。

---

## Lab 2 — `--cap-drop` / `--cap-add` 看權力怎麼被切走

**目標**:讓你親眼看到 `ping` 在 `--cap-drop=NET_RAW` 後壞掉,在 `--cap-drop=ALL --cap-add=NET_RAW` 後又能用,但 `chown` 失能(因為 `CAP_CHOWN` 沒加回來)。

```bash
./lab2-drop.sh
```

**你應該看到**:

- 預設容器:ping 成功。
- `--cap-drop=NET_RAW`:ping 報 `Operation not permitted`。
- `--cap-drop=ALL --cap-add=NET_RAW`:ping 成功,但 `chown` 失敗。

> 💡 **生產建議**:多數 web 服務只需要綁 port 的能力(`NET_BIND_SERVICE`)或完全不需要(用高 port + reverse proxy)。`--cap-drop=ALL` 是好習慣,需要哪個 add 哪個。

---

## Lab 3 — `--privileged` 是核彈級的全給

**目標**:對比預設容器與 `--privileged` 容器,讓你親眼看到後者怎麼把所有限制都拿掉。

```bash
./lab3-privileged.sh
```

**你應該看到**:

- 預設容器嘗試 `mount -t proc` 失敗(沒有 SYS_ADMIN)。
- `--privileged` 容器能 mount,而且 CapEff bitmap 多很多 bit。

> ⚠️ **`--privileged` 等於關門開盜**:除了 capabilities 全給,還會把 seccomp、AppArmor、device cgroup 全關掉。基本上等於把 container 變成普通 host process。除非你在做 Docker-in-Docker、低階硬體存取,否則不要用。

---

## Lab 4 — `--user` 一鍵降權

**目標**:看 `--user 1000:1000` 怎麼把 capability 全部清掉(因為非 root 拿不到 capability)。

```bash
./lab4-user.sh
```

**你應該看到**:

- 預設(root)容器:`id` 是 `uid=0`,有完整 default cap 集。
- `--user 1000:1000`:`id` 是 `uid=1000`,`CapEff` 是 `0000000000000000`(零)。
- 嘗試綁 port 80 失敗(非 root + 沒 NET_BIND_SERVICE)。

> 💡 **最佳實踐**:Dockerfile 寫 `USER 1000` 或部署時加 `--user 1000:1000`。多數 web stack(node、python)根本不需要 root,但很多 image 預設就用 root,只是因為「方便」。

---

## Lab 5 — 自己用 `unshare -U` 做一個 user namespace

**目標**:不靠 Docker、**也不需要 sudo**,純 unprivileged 使用者就能建一個 user namespace,在裡面看起來是 root。

```bash
./lab5-userns.sh
```

腳本會做這件事:

```bash
unshare --user --map-root-user --pid --fork --mount-proc bash
```

旗標解釋:

| 旗標 | 作用 |
|---|---|
| `--user` | 建立新 user namespace |
| `--map-root-user` | 把新 ns 內的 UID 0 映射到外面的「呼叫者 UID」 |
| `--pid --fork --mount-proc` | 順便也建 PID ns(第 4 份工作坊講過) |

**你應該看到**:

- 新 ns 內 `id` 顯示 `uid=0(root)`,但 `/proc/self/uid_map` 寫的是 `0  <你的真實 UID>  1` — 意思是「ns 內 0 對應到外面真實 UID」。
- 試圖寫 `/etc/shadow` 仍然失敗,kernel 在做存取檢查時用真實 UID。
- 但你能在這個 ns 裡再建更多 namespace、做 capability 操作 — 因為「ns 內你是 root」。

**觀念連結**:

- `rootless docker` / `podman` 用一樣的機制,讓你不用 root 也能跑容器。
- Docker daemon 的 `--userns-remap` 把 host root 也透過 user namespace 映射到 host 上某個受限 UID,進一步降低 daemon 的攻擊面。
- LXC、firecracker、Bottlerocket 等也都用 user namespace 隔離。

---

## 常用指令速查

```bash
# 看當前 process 的 capabilities
grep Cap /proc/self/status
capsh --print
capsh --decode=<bitmap>

# 在 host 給 binary 設特定 capability(取代 setuid bit)
sudo setcap cap_net_bind_service=+ep /usr/bin/myapp

# Docker 旗標
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE ...
docker run --user 1000:1000 ...
docker run --privileged ...        # 不要在生產用!

# 看容器當下的 cap set
docker container inspect --format '{{ .HostConfig.CapAdd }} / {{ .HostConfig.CapDrop }}' <c>

# user namespace 操作
unshare --user --map-root-user bash
cat /proc/<pid>/uid_map
cat /proc/<pid>/gid_map
```

## 常見問題 FAQ

**Q: 為什麼 Docker 不直接給容器全部 capability?**
A: 因為 capability 設計初衷就是「最小授權」。Docker 預設給 14 個是經過權衡的:足以讓 99% 的應用正常跑,又把最危險的(SYS_ADMIN、SYS_TIME、NET_ADMIN)擋掉。如果一個應用真的需要更多,使用者要自己 add — 強制思考。

**Q: `--user 1000` vs Dockerfile 寫 `USER 1000` 哪個好?**
A: 寫在 Dockerfile 比較好(image 自帶,不會忘),但 `--user` 旗標可以覆蓋它,適合臨時除錯或在 K8s spec 強制覆寫。

**Q: Lab 5 為什麼不需要 sudo?**
A: kernel 從 3.8 開始允許 unprivileged user 建立 user namespace(預設開,可以被 sysctl `kernel.unprivileged_userns_clone` 關掉)。這是設計上的安全性折衷:讓使用者能 sandbox,代價是若 kernel 在 user ns 處理上有漏洞會擴大攻擊面。

**Q: rootless Docker 跟 `--user` 有什麼差別?**
A: `--user` 是 daemon 仍以 root 跑,容器內以非 root 跑。**rootless Docker** 是整個 daemon 都以非 root 跑(透過 user namespace 把 daemon 看到的 root 映射到 host 的非 root)。後者更安全,但有一些限制(無法綁 < 1024 port without 設定、儲存 driver 受限)。

**Q: 我看到別人 Dockerfile 寫 `RUN setcap cap_net_bind_service=+ep /usr/bin/myapp`,意思是?**
A: 這把 `cap_net_bind_service` 綁在 binary 上(像進化版 setuid)。執行該 binary 的 process 自動拿到這個 cap,即使它是非 root 也能綁低 port。配合 `USER 1000` 是常見模式。

---

###### tags: `Linux` `Capabilities` `User Namespace` `Docker` `Security` `Tutorial`
