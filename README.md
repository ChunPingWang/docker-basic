---
title: 'Docker 基礎工作坊集'
disqus: hackmd
---

# Docker 基礎工作坊集

> 一套以「動手做」為主的工作坊集,從 Docker 網路一路拆到 container runtime 與 OCI image 的內部。**10 個工作坊 / 49 個 lab**,每份都附 Dockerfile、bash 腳本、與一份 README,並對照解釋對應的 Linux kernel primitive 是怎麼運作的。

## 工作坊地圖

| # | 工作坊 | 主題 | Labs | 需 sudo? |
|---|---|---|:---:|:---:|
| 0 | [`network/`](./network/) | 容器網路 4 種模式 + `veth pair` | 5 | Lab 5 |
| 1 | [`storage/`](./storage/) | bind / volume / tmpfs / 手動 overlayfs | 5 | Lab 5 |
| 2 | [`cgroups/`](./cgroups/) | memory / cpu / pids 限額 + 手動 cgroup | 5 | Lab 5 |
| 3 | [`pidns/`](./pidns/) | PID namespace / signal / `--init` / tini | 5 | Lab 5 |
| 4 | [`caps/`](./caps/) | capabilities + user namespace | 5 | Lab 5(部分) |
| 5 | [`image-internals/`](./image-internals/) | OCI image = tar + JSON + multi-stage | 5 | — |
| 6 | [`seccomp/`](./seccomp/) | syscall 過濾 + 自訂 JSON profile | 5 | — |
| 7 | [`runtime/`](./runtime/) | docker → containerd → runc + OCI bundle | 5 | Lab 2/4/5 |
| 8 | [`rootless/`](./rootless/) | unprivileged Docker 怎麼做到 | 4 | Lab 3(部分) |
| 9 | [`compose/`](./compose/) | 多容器編排,並用純 docker 重現 | 5 | — |

## 學習路徑建議

**只想學 Docker 怎麼用** — `network/` → `storage/` → `cgroups/` (Lab 1〜4) → `compose/`,跳過每份的 Lab 5。

**想徹底懂底層** — 照表格順序由上而下,每份都做完(包含 Lab 5)。`runtime/` 與 `rootless/` 放最後比較好,因為它們把前面 8 份的 primitives 都串起來。

**只關心容器安全** — `caps/` → `seccomp/` → `rootless/`,然後 `runtime/` 看 OCI spec。

**只想了解 image** — `image-internals/`(獨立、其他都不依賴)。

## 共通環境需求

| 項目 | 版本 / 說明 |
|---|---|
| 作業系統 | Linux(建議 Ubuntu 22.04+)、或 WSL2 Ubuntu、或 macOS+OrbStack/Lima(見下節) |
| Docker | 20.10 以上,**cgroup v2** runtime(modern Ubuntu / Fedora 預設) |
| 工具 | `bash`、`jq`、`curl`、`tar` — 各 lab README 列各自所需 |
| 權限 | `docker` group 或 `sudo`;每份的 Lab 5 多半需要 root |

確認:

```bash
docker --version
jq --version
stat -fc %T /sys/fs/cgroup/   # 預期 cgroup2fs
```

## 在不同作業系統上跑這些 Lab

本 repo 裡的 lab 分成兩類:

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

- **`host` 網路模式**:macOS 的 `--network=host` 從 Docker 4.34+ 開始支援(beta);更早的版本下,「host」是指 VM 不是你的 Mac,你看到的 `ip addr` 是 VM 的網路。本 repo 的 network Lab 2 在 Mac 上行為跟 Linux 不同,本 README 下面有提示。

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
cd docker-basic/network
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
| network (本目錄) | ✅ 全 OS | Linux / WSL2 only |
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

---
