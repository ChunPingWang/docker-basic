---
title: 'Linux PID namespace 與 init 工作坊'
disqus: hackmd
---

> ← 回到 [工作坊集索引](../README.md)

# Linux PID namespace 與 init 工作坊

> 一份從零開始學習 Linux **PID namespace** 與容器內 **init process** 的實作教材。本工作坊會帶你動手體驗 PID namespace 的隔離、PID 1 的特權與責任、為什麼很多容器需要 `--init`,最後不靠 Docker、純粹用 `unshare` 在 host 上做出一個 PID namespace。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:PID namespace 與 init 的責任](#背景知識pid-namespace-與-init-的責任)
- [Lab 1 — PID namespace 的隔離](#lab-1--pid-namespace-的隔離)
- [Lab 2 — PID 1 為什麼接不到 SIGTERM](#lab-2--pid-1-為什麼接不到-sigterm)
- [Lab 3 — Zombie:沒人 reap 的孤兒](#lab-3--zombie沒人-reap-的孤兒)
- [Lab 4 — `docker run --init` 是怎麼救命的](#lab-4--docker-run---init-是怎麼救命的)
- [Lab 5 — 自己用 `unshare` 做一個 PID namespace](#lab-5--自己用-unshare-做一個-pid-namespace)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 解釋 PID namespace:同一個 process 為什麼在容器內看到是 PID 1、在 host 看到是某個大數字。
2. 講清楚為什麼很多人下 `docker stop` 之後要等 10 秒才結束,以及怎麼修。
3. 看到容器內 zombie process 累積時知道哪邊出問題,並用 `--init` / tini 解決。
4. 用一行 `unshare` 在 host 上做出自己的 PID namespace,不需要 Docker。

## 先備知識

- 會用 terminal、知道什麼是 process / PID / 父子 process。
- 知道 SIGTERM、SIGKILL、SIGINT 大概是什麼。
- 做過前面三份工作坊(network / storage / cgroups)會更好,但不強制。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| 作業系統 | Linux,任何發行版都行 |
| Docker | 20.10 以上 |
| 權限 | 能跑 `docker`(`docker` group 或 `sudo`)。Lab 5 需要 `sudo` 來呼叫 `unshare` |
| 工具 | `bash`、`procps`(host 端要有 `ps`)、`util-linux`(要有 `unshare`) |

## 專案結構

```
pidns/
├── Dockerfile-ubuntu-pidns   # Ubuntu + procps + python3-minimal
├── build.sh                  # 建立映像
├── lab1-isolation.sh         # Lab 1: PID namespace 隔離
├── lab2-signal.sh            # Lab 2: PID 1 接不到 SIGTERM
├── lab3-zombie.sh            # Lab 3: zombie process 累積
├── lab4-init.sh              # Lab 4: --init / tini 救命
├── lab5-unshare.sh           # Lab 5: 手動建 PID namespace(需 sudo)
└── README.md                 # 本文件
```

## 快速開始

```bash
# 1. 建立練習用的映像(只需做一次)
./build.sh

# 2. 依序執行各個 Lab
./lab1-isolation.sh
./lab2-signal.sh
./lab3-zombie.sh
./lab4-init.sh

# Lab 5 需要 root 權限
sudo ./lab5-unshare.sh
```

> 💡 **小提醒**:Lab 1〜4 的容器都加了 `--rm`,結束後會自動清掉。

---

## 背景知識:PID namespace 與 init 的責任

**PID namespace 隔離 PID 編號**:每個 namespace 各自從 1 開始編號。同一個 process 在不同 namespace 看到的 PID 不同,但本質還是同一個。

**PID 1 在 Linux 是個有特殊地位的 process**,kernel 給它兩個特權與兩個責任:

| 項目 | 內容 | 在容器裡的後果 |
|---|---|---|
| 特權 1 | **kernel 不會把預設處理(`SIG_DFL`)是「終結 process」的訊號送給 PID 1** | 容器內的 sleep / bash 收不到 SIGTERM,`docker stop` 等到 timeout 才用 SIGKILL 殺 |
| 特權 2 | 整棵 PID namespace 的孤兒(parent 死掉的 child)都會被 reparent 到 PID 1 | 容器內任何 process 死了,如果它的 parent 已先死,就由 PID 1 負責清 |
| 責任 1 | 必須 install 各種 signal handler(至少 SIGTERM)才能優雅結束 | 否則上面那條特權變成詛咒,容器永遠等 SIGKILL |
| 責任 2 | 必須有一個 `wait()` 迴圈持續清理 zombie | 否則 zombie 會堆滿 process table,長期跑爆 PID |

真正的 init system(systemd、SysV init)兩件事都會做。但容器的 entrypoint 通常是你的 app(node、python、bash 寫的腳本),它們**沒做這兩件事**,於是兩個責任沒人扛 → Docker 提供 `--init` 旗標,塞一個叫 `tini` 的迷你 init 進去當 PID 1,問題就解決。

接下來四個 lab 會一步步把這四件事示範給你看,Lab 5 則用 kernel 原生的 `unshare(2)` 做一個自己的 PID namespace。

---

## Lab 1 — PID namespace 的隔離

**目標**:看到「同一個 process,在容器內是 PID 1,在 host 是 PID 某某」這件事。

```bash
./lab1-isolation.sh
```

腳本會做這些事:

1. 啟動一個跑 `sleep 60` 的容器。
2. `docker exec ... ps -ef` 從容器內看 — sleep 是 PID 1,還可能看到 ps 自己是 PID 7 之類。
3. `docker inspect --format '{{.State.Pid}}'` 拿到該 process 在 host 上的 PID。
4. host 上 `ps -p <hostpid>` 看到同一個 sleep,但 PID 是 2 萬、3 萬之類的大數字。

**你應該看到**:

- 容器內 sleep 的 PID 是 1。
- host 上同一個 sleep 的 PID 是某個大數字(典型 5 位數)。
- 兩邊看到的 cmdline 完全相同 — 因為它就是同一個 process,只是兩個 namespace 從不同角度看它。

---

## Lab 2 — PID 1 為什麼接不到 SIGTERM

**目標**:看一個沒人寫 signal handler 的 PID 1(這裡是 `sleep`)怎麼把 `docker stop` 變成「等 timeout 然後被 SIGKILL」。

```bash
./lab2-signal.sh
```

腳本會做這些事:

1. 啟動 `docker run -d --rm ubuntu-pidns sleep 300` — 純 sleep 是 PID 1。
2. `docker exec ... kill -TERM 1` — 從容器內送 SIGTERM 給 PID 1。
3. 觀察 sleep 沒事 — kernel 把這個 signal 丟掉了。
4. `time docker stop --time=2 ...` — 量測 docker stop 真的等了 2 秒(SIGTERM 被忽略 → timeout 後 SIGKILL)。

**你應該看到**:

- `kill -TERM 1` 之後容器仍在 running。
- `docker stop --time=2` 大約耗時 2.0x 秒,證明 kernel 真的等到 grace period 結束才用 SIGKILL。

> 💡 **kernel 的規則**:PID 1 收到的 signal,如果 disposition 是 `SIG_DFL` 而且 default action 是 terminate / core,kernel **直接丟掉**。SIGKILL 不受影響(它不是 SIG_DFL,而是強制 kill,不能被攔截)。

> 💡 **`docker kill` vs `docker stop`**:`docker kill` 預設送 SIGKILL,所以可以瞬間殺掉這種容器;`docker stop` 比較禮貌,但禮貌的代價就是要等 timeout。

---

## Lab 3 — Zombie:沒人 reap 的孤兒

**目標**:看到容器內 zombie 累積的真實場景,並理解為什麼這在長期 running 的容器是個漏洞。

```bash
./lab3-zombie.sh
```

腳本會做這些事:

1. 容器內跑一段 Python:fork 10 個 child,每個 child 再 fork 一個 grandchild 然後立刻 exit。
2. Grandchild 的 parent 死掉,於是被 reparent 到 PID 1(也就是這個 Python)。
3. Grandchild sleep 0.2 秒後 exit,變成 zombie 等人 `wait()`。
4. Python 沒呼叫 `wait()`,zombie 就一直堆著。
5. `ps -e -o pid,ppid,stat,cmd` 列出來看看。

**你應該看到**:

- 10 個 process 的 STAT 欄是 `Z`(zombie),它們的 PPID 都是 1。
- 容器持續跑下去的話,PID table 會被慢慢吃光,直到撞到 host 的 pid_max 或 cgroup 的 pids.max。

> 💡 **這在現實生活中的後果**:CI runner、開發者用的 dev container、跑 shell out 一堆 subprocess 的工具(像 `npm`、`make`、`gradle`),如果 entrypoint 直接是 node / python / bash,zombie 累積是常態漏洞。

---

## Lab 4 — `docker run --init` 是怎麼救命的

**目標**:看 `--init` 同時解掉 Lab 2(信號)與 Lab 3(zombie)兩個問題。

```bash
./lab4-init.sh
```

腳本會做這兩件事:

**Part 1**:用 `--init` 啟一個 sleep 容器,容器內 PID 1 變成 `tini`,sleep 變成 PID 2。`docker stop --time=10` 應該瞬間結束(<1 秒) — tini 收到 SIGTERM、轉發給 sleep,sleep 是 PID 2 不受 PID 1 保護,正常被殺。

**Part 2**:跑同一段 Python orphan-factory,但容器加了 `--init`。這次 zombie 數量是 **0** — tini 在背景持續呼叫 `wait()` 把 reparent 上來的 zombie 全收走。

**你應該看到**:

- Part 1 的 `docker stop` 耗時 0.x 秒,而不是 Lab 2 的 2.0x 秒。
- Part 2 的 zombie count 是 0。
- 容器內 `ps -ef` 顯示 PID 1 是 `/sbin/docker-init`(就是 tini)。

> 💡 **tini 是什麼**:大約 1KB 的 C 程式,只做兩件事:一是把它收到的 signal 轉發給 child,二是在 SIGCHLD 進來時呼叫 `waitpid(-1, ..., WNOHANG)` 直到沒 zombie 為止。Docker 內建一份在 `/sbin/docker-init`,加 `--init` 旗標就會把它塞進容器當 PID 1。

> 💡 **K8s 也有同樣機制**:Pod spec 的 `shareProcessNamespace: true` 會讓 Pod 內所有容器共用 PID namespace,通常搭配 `securityContext.runAsNonRoot`,並由 kubelet 注入 pause container 當 PID 1。

---

## Lab 5 — 自己用 `unshare` 做一個 PID namespace

**目標**:不靠 Docker,用 kernel 原生介面親手做一個 PID namespace。

```bash
sudo ./lab5-unshare.sh
```

腳本會做這件事:

```bash
unshare --pid --fork --mount-proc bash
```

三個旗標各做一件事:

| 旗標 | 在 kernel 端的對應 | 為什麼需要 |
|---|---|---|
| `--pid` | `clone(CLONE_NEWPID)` | 建立新的 PID namespace |
| `--fork` | 建完 ns 後 fork,讓 child 進新 ns | 原本的 process 仍在舊 ns,新 ns 的 PID 1 必須是新 fork 出來的 process |
| `--mount-proc` | 在新 ns 裡重 mount `/proc` | `/proc` 是個特殊 fs,讀的是 caller 自己 namespace 的 view;不重 mount 的話 `ps` 看到的還是 host 的 |

進入後跑 `ps -ef`,你會看到只剩兩個 process(bash 跟 ps),都是新 ns 的 PID。

**觀念連結**:Docker 啟容器時的核心 syscall 大致就是:

```c
clone(CLONE_NEWPID | CLONE_NEWNET | CLONE_NEWNS | CLONE_NEWUTS |
      CLONE_NEWIPC | CLONE_NEWUSER | CLONE_NEWCGROUP, ...);
```

把所有 namespace 一次切開,然後在新 ns 裡 exec 你的 entrypoint。理解 Lab 5 後,「Docker」就只剩下「友善的 wrapper」這一層神秘。

清理:bash 退出時 PID namespace 自動消失,**不用手動清**。

---

## 常用指令速查

```bash
# 容器內外的 PID 對應
docker inspect --format '{{.State.Pid}}' <container>   # 容器主 process 在 host 的 PID
docker top <container>                                 # 容器裡所有 process 的 host PID

# 看 namespace
ls -la /proc/<pid>/ns/                # 那個 process 屬於哪幾個 namespace
sudo lsns -t pid                      # 列出所有 PID namespace

# 信號相關
docker stop --time=N <container>      # SIGTERM,N 秒後 SIGKILL(預設 10)
docker kill <container>               # 直接 SIGKILL
docker kill -s SIGUSR1 <container>    # 送任意 signal

# init / tini
docker run --init ...                 # 把 tini 塞進去當 PID 1
docker inspect --format '{{.HostConfig.Init}}' <c>   # 看是否啟用了 --init

# 手動建 namespace
sudo unshare --pid --fork --mount-proc <cmd>
sudo unshare --uts --net --mount --ipc --pid --fork --mount-proc <cmd>   # 多個一起
```

## 常見問題 FAQ

**Q: 我的容器是 nginx / postgres,需要 `--init` 嗎?**
A: 不一定。nginx 自己會處理 SIGTERM(graceful shutdown)、postgres 也會。如果 entrypoint 是「會回應 signal、會 reap children 的程式」,就不需要。但如果是 bash 腳本、node 應用、一般 Python script,**幾乎都要加**。

**Q: K8s 也是這樣嗎?**
A: 同樣的問題在 K8s 也存在,而且 K8s 有更多 corner case(因為一個 Pod 可能有多個容器、有 sidecar、有 initContainer)。K8s 的解法是 `kubelet` 在啟動 Pod 時注入一個 pause container 當 PID 1(如果你開了 `shareProcessNamespace`),或讓每個容器自己處理。

**Q: `--init` 跟我自己 `ENTRYPOINT ["tini", "--", "myapp"]` 哪個好?**
A: 行為一樣,習慣就好。在 Dockerfile 裡寫 ENTRYPOINT 是 portable 的(image 自帶),`--init` 是 runtime 旗標(每次 run 要自己加)。CI / 公司內部標準化的話,寫 Dockerfile 比較不會忘。

**Q: Lab 5 為什麼要 `--mount-proc`?**
A: 因為 `ps` 是讀 `/proc` 取得 process 資訊,而 `/proc` 反映的是「**讀的人**自己的 PID namespace」(實作上是 `/proc` 這個 procfs 是用 mount-time 的 namespace 綁住的)。如果不重 mount,你在新 ns 裡跑 `ps` 還是看到 host 的全部 process,那這個 lab 就白做了。

**Q: 我在容器內跑 `kill 1` 為什麼真的把容器殺了?**
A: 你大概沒設 `kill` 的 signal,bash 內建 `kill` 預設送 SIGTERM。但 Docker 的 image 如果用真的 init(像 systemd image)當 PID 1,它有 SIGTERM handler,handler 會 graceful shutdown 自己。或者你是用 `kill -9`,SIGKILL 不受 PID 1 保護。

---

###### tags: `Linux` `PID Namespace` `Docker` `init` `tini` `Tutorial`
