---
title: 'Linux cgroups 工作坊'
disqus: hackmd
---

> ← 回到 [工作坊集索引](../README.md)

# Linux cgroups 工作坊

> 一份從零開始學習 Linux **cgroups**(control groups)的實作教材。本工作坊會帶你動手體驗 Docker 三個最常用的資源限制旗標(`--memory`、`--cpus`、`--pids-limit`),看 Docker 怎麼把這些旗標翻譯成 cgroupfs 的設定,最後不靠 Docker、純粹用 `mkdir` 在 `/sys/fs/cgroup` 下做出一個會 OOM-kill 的 cgroup。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:namespace 與 cgroups 的差別](#背景知識namespace-與-cgroups-的差別)
- [Lab 1 — 記憶體上限與 OOM kill](#lab-1--記憶體上限與-oom-kill)
- [Lab 2 — CPU 限額](#lab-2--cpu-限額)
- [Lab 3 — pids 上限與 fork bomb 防護](#lab-3--pids-上限與-fork-bomb-防護)
- [Lab 4 — 看 Docker 怎麼設 cgroupfs](#lab-4--看-docker-怎麼設-cgroupfs)
- [Lab 5 — 自己動手做 cgroup](#lab-5--自己動手做-cgroup)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 說出 namespace 與 cgroups 的差別:**namespace 管「看得到什麼」、cgroups 管「能用多少」**。
2. 用 `docker run --memory / --cpus / --pids-limit` 替容器設限,並解釋設了之後在 kernel 端發生什麼事。
3. 從 `/proc/<pid>/cgroup` 找到任何容器在 cgroupfs 上對應的目錄,並讀出它的限制。
4. 親手在 `/sys/fs/cgroup` 下 `mkdir` 一個 cgroup,把程序丟進去並讓它被 OOM-kill。

## 先備知識

- 會用 terminal、知道什麼是程序與 PID。
- 知道 Docker 是什麼,做過 `docker run hello-world`。
- **不需要**寫過 kernel 程式;cgroupfs 就是個怪怪的檔案系統,我們只會用 `cat`、`echo`。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| 作業系統 | Linux,且 **cgroup v2**(Ubuntu 22.04+、Fedora 31+、Debian 11+ 預設都是) |
| Docker | 20.10 以上 |
| 權限 | 能執行 `docker` 指令(已加入 `docker` group,或用 `sudo`)。Lab 5 需要 `sudo` |
| 工具 | `bash`、`python3`(Lab 5 要它配置記憶體) |

確認系統是 cgroup v2:

```bash
stat -fc %T /sys/fs/cgroup/   # 預期看到 cgroup2fs
cat /sys/fs/cgroup/cgroup.controllers
```

## 專案結構

```
cgroups/
├── Dockerfile-ubuntu-cgroups   # 帶 stress-ng / procps 的 Ubuntu 映像
├── build.sh                    # 建立映像
├── lab1-memory.sh              # Lab 1: 記憶體上限 + OOM
├── lab2-cpu.sh                 # Lab 2: CPU 限額
├── lab3-pids.sh                # Lab 3: pids 上限
├── lab4-inspect.sh             # Lab 4: 看 Docker 寫在 cgroupfs 哪裡
├── lab5-manual.sh              # Lab 5: 手動建 cgroup(需 sudo)
└── README.md                   # 本文件
```

## 快速開始

```bash
# 1. 建立練習用的映像(只需做一次)
./build.sh

# 2. 依序執行各個 Lab
./lab1-memory.sh
./lab2-cpu.sh
./lab3-pids.sh
./lab4-inspect.sh

# Lab 5 需要 root 權限
sudo ./lab5-manual.sh
```

> 💡 **小提醒**:Lab 1〜4 的容器都加了 `--rm`,結束後會自動清掉。Lab 5 為了讓你有時間檢查,不會自己 `rmdir`,腳本最後會印出清理指令。

---

## 背景知識:namespace 與 cgroups 的差別

container 不是一個 kernel 機制,它是好幾個機制疊出來的結果。最常被誤會的兩個:

| 機制 | 解決什麼 | 例子 |
|---|---|---|
| **namespace** | 隔離(看得到什麼) | net ns:看不到 host 的網卡;pid ns:`ps` 從 PID 1 開始 |
| **cgroups** | 限額(能用多少) | memory.max=64M:吃超過就被 OOM-kill;cpu.max=50000 100000:最多用半顆 CPU |

兩件事**正交**:你可以只開 namespace 不開 cgroups(就只是隔離,沒限制),也可以只開 cgroups 不開 namespace(限制 host 上某個 process,但它仍看得到一切)。Docker 把兩者都自動裝起來,做出一個既隔離又限額的容器。

cgroup 在 kernel 裡長成一棵樹,掛在 `/sys/fs/cgroup/`。每個目錄就是一個 cgroup,目錄裡的檔案是「設定 / 觀測值」:

| 檔案 | 意義 |
|---|---|
| `cgroup.procs` | 這個 cgroup 裡有哪些 PID。寫 PID 進去就把 process 移進來 |
| `cgroup.controllers` | 這個 cgroup 啟用了哪些控制器 |
| `cgroup.subtree_control` | 把哪些控制器**下放**給子 cgroup 用 |
| `memory.max` | 記憶體上限。寫 `64M` 進去就是 64MB |
| `memory.current` | 目前用量(唯讀) |
| `cpu.max` | `quota period`,例如 `50000 100000` 代表每 100ms 給 50ms,= 半顆 CPU |
| `pids.max` | 這個 cgroup 內最多多少個 task |
| `memory.events` | OOM、達到上限等事件次數 |

接下來我們會一個一個動手玩。

---

## Lab 1 — 記憶體上限與 OOM kill

**目標**:看一個被限 64MB 的容器是怎麼在嘗試吃 200MB 時被 kernel 殺掉的。

```bash
./lab1-memory.sh
```

腳本會做這些事:

1. 用 `--memory=64m --memory-swap=64m`(swap 也鎖死,避免被 swap 救活)啟動容器。
2. 容器內跑 `python3 -c 'data = bytearray(200 * 1024 * 1024)'`,要求配置 200MB(`bytearray` 會把所有 page 寫成 0,強制實際分配實體記憶體)。
3. 容器隨即被 OOM-kill,退出碼 **137**(= 128 + SIGKILL 的訊號號 9)。
4. 腳本最後再啟一個容器,讓你親眼看到容器內的 `/sys/fs/cgroup/memory.max` 寫的就是 `64M`。

**你應該看到**:

- 容器沒有印出「survived」字樣(代表 Python 沒跑完就被殺)。
- exit code 是 137。
- `memory.max` 是 `67108864`(= 64 × 1024 × 1024)。

> 💡 **memory-swap 的小坑**:如果不設 `--memory-swap`,Docker 預設給 2 倍 swap,寫 200MB 不見得會 OOM(會去吃 swap)。把它設成跟 `--memory` 一樣等於「禁用 swap」,才能穩定觸發 OOM。

> 💡 **為什麼用 Python 不用 stress-ng?**:`stress-ng --vm` 預設的記憶體存取模式不會穩定踩到上限(它會 unmap 又重 map),需要加一堆旗標才會觸發 OOM。用 `bytearray` 直接配置一塊夠大的連續記憶體最直接。

---

## Lab 2 — CPU 限額

**目標**:看 `--cpus=0.5` 真的把容器壓在半顆 CPU。

```bash
./lab2-cpu.sh
```

腳本會做這些事:

1. 用 `--cpus=0.5` 啟動容器,在背景跑 `stress-ng --cpu 1`(理論上會把一顆 CPU 吃滿)。
2. 等幾秒後 `docker stats --no-stream` 抓一個快照,觀察 CPU% 大概落在 50%。
3. `docker exec` 進容器看 `/sys/fs/cgroup/cpu.max`,你會看到 `50000 100000` — 每 100ms 給 50ms 的執行時間。

**你應該看到**:

- `docker stats` 的 CPU% 大約是 50%(可能落在 48〜52%)。
- `cpu.max` 是 `50000 100000`,正好是 quota / period = 0.5。

> 💡 **多核機器**:`--cpus=0.5` 不限定哪一顆 CPU,kernel 排程器會在所有 CPU 上湊出平均 50% 使用率。如果想固定 CPU,用 `--cpuset-cpus=0`(這寫的是 cgroup 的 `cpuset.cpus`)。

---

## Lab 3 — pids 上限與 fork bomb 防護

**目標**:看 `--pids-limit=20` 怎麼擋掉一個會 fork 一堆東西的程式。

```bash
./lab3-pids.sh
```

腳本會做這些事:

1. 用 `--pids-limit=20` 啟動容器。
2. 容器內用 Python 跑一個 `os.fork()` 迴圈,試 50 次 fork。
3. 統計成功 / 失敗次數,並讀 `/sys/fs/cgroup/pids.current`。

**你應該看到**:

- 約 19 個 fork 成功(扣掉 Python 自己 + 其他基礎 process,總共剛好頂到 20)。
- 約 31 次 fork 失敗,Python 收到 `OSError: [Errno 11] Resource temporarily unavailable`。
- `pids.current` 卡在 20。

> 💡 **為什麼用 Python 不用 bash 寫迴圈?**:bash 對 fork EAGAIN 會 retry 8 次後直接放棄並中止整個 shell(exit 254),沒辦法做 50 次容錯嘗試;Python 的 `try / except OSError` 一次失敗一次計數,比較好控制。

> 💡 **真的有用**:fork bomb(`:(){ :|:& };:`)就是靠無限 fork 把系統壓垮。container 預設沒設 pid 上限的話,容器內的 fork bomb 仍可能拖垮 host;`--pids-limit` 是最便宜的防線。

---

## Lab 4 — 看 Docker 怎麼設 cgroupfs

**目標**:把 `docker run --memory=64m` 跟 kernel 端的 cgroupfs 檔案連起來,證明 Docker「不過就是個 wrapper」。

```bash
./lab4-inspect.sh
```

腳本會做這些事:

1. 啟動一個有完整三項限制的容器(memory / cpu / pids)。
2. 用 `docker inspect` 拿到容器的 host PID。
3. 讀 `/proc/<pid>/cgroup`,得到該 process 在 cgroupfs 樹上的相對路徑(例如 `/system.slice/docker-<id>.scope`)。
4. 拼出絕對路徑後,把 `memory.max`、`cpu.max`、`pids.max` 等檔案 cat 出來。

**你應該看到**:

- `/proc/<pid>/cgroup` 的內容類似 `0::/system.slice/docker-<64-hex>.scope`。
- 在那個目錄底下,`memory.max` 寫的是 `67108864`、`cpu.max` 寫的是 `50000 100000`、`pids.max` 寫的是 `50`。
- 這些值跟 `docker run` 旗標**一一對應**。

**觀念連結**:從這個 Lab 可以看到 Docker 的真面目 — 它讀你下的旗標、`mkdir` 一個 cgroup、把這些數字寫進對應的檔案、再把容器 process 的 PID 寫進 `cgroup.procs`。Lab 5 會把這整個流程不靠 Docker 重做一遍。

---

## Lab 5 — 自己動手做 cgroup

**目標**:不靠 Docker,純用 `mkdir` 與 `echo` 在 `/sys/fs/cgroup/` 下做出一個會 OOM-kill 的 cgroup。看完這個 Lab,Docker 在 cgroup 端做的事你就完全懂了。

```bash
sudo ./lab5-manual.sh
```

腳本會做這些事:

1. `mkdir /sys/fs/cgroup/cgroups-lab5` — 在 cgroup 樹上開一個新節點。
2. 確保 root 的 `cgroup.subtree_control` 把 `memory` 與 `pids` 下放給子節點(現代 systemd 系統通常已經做好)。
3. `echo 20M > memory.max`、`echo 0 > memory.swap.max`、`echo 10 > pids.max` — 設 20MB 記憶體 + 禁用 swap + 10 個 task 的上限。
4. `( echo $BASHPID > cgroup.procs; exec python3 -c '...' )` — 把一個 subshell 移進這個 cgroup,然後 `exec` 成 Python,直接配置 100MB。
5. Python 在跨過 20MB 時被 kernel OOM-kill,退出碼 137。
6. 印 `memory.events`,看到 `oom_kill 1`。

**運作原理**:

- `cgroup v2` 是「整棵樹單一階層」(unified hierarchy),不像 v1 每個控制器一棵樹。
- 把 PID 寫進 `cgroup.procs` 就是「把這個 process 搬進這個 cgroup」。
- kernel 會幫 cgroup 內所有 process 加總用量,任一 process 觸到上限,kernel 就動手(OOM kill / 拒絕 fork / 限制排程)。

**清理**(腳本不會自動 `rmdir`,讓你有時間檢查):

```bash
sudo rmdir /sys/fs/cgroup/cgroups-lab5
```

---

## 常用指令速查

```bash
# 看系統是 v1 還是 v2
stat -fc %T /sys/fs/cgroup/   # cgroup2fs = v2

# 看可用控制器
cat /sys/fs/cgroup/cgroup.controllers
cat /sys/fs/cgroup/cgroup.subtree_control

# 看任何 process 在哪個 cgroup
cat /proc/<pid>/cgroup
cat /proc/self/cgroup

# Docker 端
docker stats                  # 即時用量
docker stats --no-stream      # 拍一張快照
docker run --memory=64m --memory-swap=64m ...
docker run --cpus=0.5 ...
docker run --pids-limit=20 ...
docker run --cpuset-cpus=0,1 ...   # 固定 CPU 編號

# 手動建 cgroup(需 root)
mkdir /sys/fs/cgroup/<name>
echo "+memory +pids" > /sys/fs/cgroup/cgroup.subtree_control
echo "20M" > /sys/fs/cgroup/<name>/memory.max
echo "$$"  > /sys/fs/cgroup/<name>/cgroup.procs
rmdir /sys/fs/cgroup/<name>   # 清理(內無 process 才能刪)
```

## 常見問題 FAQ

**Q: 我的系統是 cgroup v1 怎麼辦?**
A: Lab 1〜4 都是透過 Docker 的旗標,Docker 會自動處理 v1/v2 差異,不受影響。Lab 5 的腳本假設 v2;v1 路徑長得很不一樣(`/sys/fs/cgroup/memory/...`、`/sys/fs/cgroup/pids/...` 各一棵樹),這份腳本不會 work,可以升級到 Ubuntu 22.04 以上,或自己改寫。

**Q: 為什麼 Lab 1 一定要設 `--memory-swap`?**
A: Docker 預設 swap 給 2 倍 memory,200MB 寫進去可能被 swap 吃掉,沒觸到 OOM。把 swap 鎖死(`--memory-swap` = `--memory`)強制只用實體記憶體,才能穩定示範。

**Q: Lab 2 的 CPU% 沒有剛好 50%,是壞了嗎?**
A: 不是。`--cpus=0.5` 是「平均 50%」,不是「瞬間嚴格上限」。短時間內排程器會抖動,看到 48〜52% 都正常。

**Q: Lab 3 看到 `pids.current` 是 21 不是 20?**
A: 也正常。`pids.current` 包含 cgroup 內所有的 task(含 bash 自己),所以會 ≤ `pids.max` 但不一定剛好等於目標數。

**Q: Lab 5 跑完之後 `rmdir` 失敗?**
A: 因為 cgroup 內還有 process。先確認 subshell + Python 都已退出(腳本跑完應該都退了),再 `rmdir`。萬一卡住,看 `cat /sys/fs/cgroup/cgroups-lab5/cgroup.procs` 是誰還在,kill 掉再 rmdir。

**Q: 為什麼要設 `memory.swap.max=0`?**
A: 跟 Docker 的 `--memory-swap=64m --memory=64m` 是同一招。如果不鎖死 swap,host 上有 swap 時 kernel 會把超出 `memory.max` 的頁面 swap 到磁碟而不是 OOM-kill,你會看到 `memory.events` 裡 `max` 計數一直跳但 `oom_kill` 一直是 0。設 `memory.swap.max=0` 才能穩定觸發 OOM。

---

###### tags: `Linux` `cgroups` `Docker` `Tutorial` `Resource Limits`
