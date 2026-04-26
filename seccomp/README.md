---
title: 'Linux seccomp 工作坊'
disqus: hackmd
---

> ← 回到 [工作坊集索引](../README.md)

# Linux seccomp 工作坊

> 一份從零開始學習 **Linux seccomp**(secure computing mode)的實作教材。會帶你看 Docker 預設掛在每個容器上的 seccomp filter、寫自己的 JSON profile 阻擋特定 syscall、比較 ERRNO 與 KILL 兩種 action,最後解析 Docker 官方預設 profile 的內容。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:capabilities 與 seccomp 的差別](#背景知識capabilities-與-seccomp-的差別)
- [Lab 1 — 觀察 seccomp 預設狀態](#lab-1--觀察-seccomp-預設狀態)
- [Lab 2 — `seccomp=unconfined` 把 filter 拿掉](#lab-2--seccompunconfined-把-filter-拿掉)
- [Lab 3 — 自訂 profile,用 ERRNO 阻擋 chmod](#lab-3--自訂-profile用-errno-阻擋-chmod)
- [Lab 4 — 用 `KILL_PROCESS` 直接砍掉行為異常的 process](#lab-4--用-kill_process-直接砍掉行為異常的-process)
- [Lab 5 — 解析 Docker 官方預設 profile](#lab-5--解析-docker-官方預設-profile)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 解釋 seccomp 是什麼,以及它跟 capabilities、AppArmor 的差別。
2. 觀察容器內 `/proc/self/status` 的 `Seccomp` 欄位,知道 filter 有沒有掛上。
3. 寫一份 JSON 格式的 seccomp profile,用 `--security-opt seccomp=...` 套到容器。
4. 區別 SCMP_ACT_ERRNO 與 SCMP_ACT_KILL_PROCESS 兩種行為。
5. 看懂 Docker 官方預設 profile 的結構。

## 先備知識

- 知道什麼是 syscall、`man 2 ...` 那種介面。
- 看過前面的 capabilities 工作坊更佳(seccomp 是它的補充)。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| Docker | 20.10 以上 |
| Kernel | 3.5+(普遍都有 seccomp-bpf) |
| 工具 | `bash`、`jq`、`curl`(Lab 5 從 GitHub 下載官方 profile) |

## 專案結構

```
seccomp/
├── lab1-observe.sh           # Lab 1: 觀察預設 seccomp 狀態
├── lab2-unconfined.sh        # Lab 2: seccomp=unconfined 比較
├── lab3-custom-errno.sh      # Lab 3: 自訂 profile + ERRNO
├── lab4-custom-kill.sh       # Lab 4: KILL_PROCESS
├── lab5-default-profile.sh   # Lab 5: 看 Docker 官方 profile
└── README.md
```

不需要自家 image — 全部用 `ubuntu:22.04`。

## 快速開始

```bash
./lab1-observe.sh
./lab2-unconfined.sh
./lab3-custom-errno.sh
./lab4-custom-kill.sh
./lab5-default-profile.sh
```

---

## 背景知識:capabilities 與 seccomp 的差別

兩者都是縮減容器權力的機制,但層級不同:

| 機制 | 作用層級 | 例子 |
|---|---|---|
| **capabilities** | UID 0 內部的權力切割 | "可以 chown" / "可以綁低 port" / "可以 mount" |
| **seccomp** | syscall 層級的白/黑名單 | "可以 read" / "不能 reboot" / "不能 kexec_load" |

兩者**互不取代**:capabilities 對「需要某個內核權力的 syscall」有效,seccomp 直接從「能不能 invoke 這個 syscall 號碼」的層級擋下。

舉例:`mount` syscall。
- capability 端:`CAP_SYS_ADMIN` 沒有 → mount 失敗。
- seccomp 端:即使有 SYS_ADMIN,如果 profile 把 `mount` 列為 ERRNO,還是失敗。

Docker 同時用兩者 — capabilities 預設給 14 個、seccomp 預設掛官方 profile。

### seccomp profile 的格式(JSON)

```json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "syscalls": [
    {
      "names": ["chmod", "fchmod"],
      "action": "SCMP_ACT_ERRNO",
      "errnoRet": 1
    }
  ]
}
```

**defaultAction** 是「沒列出的 syscall 怎麼辦」,常用:

- `SCMP_ACT_ALLOW`:放行
- `SCMP_ACT_ERRNO`:返回 EPERM,process 繼續
- `SCMP_ACT_KILL_PROCESS`:殺掉整個 process
- `SCMP_ACT_LOG`:記到 audit log,放行(調查用)
- `SCMP_ACT_TRACE`:交給 PTRACE 處理

**syscalls** 是規則陣列,每條規則指定一組 syscall 名字 + 動作。可以一條條疊。

---

## Lab 1 — 觀察 seccomp 預設狀態

```bash
./lab1-observe.sh
```

腳本在容器內 `cat /proc/self/status` 抓 `Seccomp` 欄位:

- `Seccomp: 0` = 沒 filter
- `Seccomp: 1` = strict mode(只允許 read/write/exit/sigreturn,幾乎不能用)
- `Seccomp: 2` = filter mode(BPF 程式已載入,Docker 預設就是這個)

預設容器顯示 2;`--security-opt seccomp=unconfined` 顯示 0。

---

## Lab 2 — `seccomp=unconfined` 把 filter 拿掉

```bash
./lab2-unconfined.sh
```

把 seccomp 完全關掉。注意:**不代表所有東西都能跑** — capabilities 還在,還是可能 EPERM。這是兩個獨立機制。

> ⚠️ **生產環境千萬別用 `seccomp=unconfined`**:它把 Docker 預設擋的 50 個危險 syscall 全部開放,等於削弱防禦縱深。Lab 5 會列出有哪些。

---

## Lab 3 — 自訂 profile,用 ERRNO 阻擋 chmod

```bash
./lab3-custom-errno.sh
```

腳本動態產生一個 JSON,把 `chmod` 系列 syscall 的 action 設成 `SCMP_ACT_ERRNO`,errnoRet=1(=EPERM)。

**你應該看到**:

- 預設容器:`chmod 600 /tmp/x` 成功。
- 套上 profile:`chmod` 失敗,bash 印 "Operation not permitted"。
- **process 沒被殺掉** — bash 還在,可以繼續做別的。

**真實用途**:封鎖你不需要的 syscall。例如純 read-only API 服務不需要 `chmod`、`unlink`、`rename`,擋掉它們可以阻止某些攻擊鏈。

---

## Lab 4 — 用 `KILL_PROCESS` 直接砍掉行為異常的 process

```bash
./lab4-custom-kill.sh
```

同樣 profile 但 action 改成 `SCMP_ACT_KILL_PROCESS`。容器在嘗試 chmod 的瞬間被 kernel 殺掉。

**ERRNO vs KILL** 怎麼選?

- **ERRNO**:你想要應用「優雅地」處理失敗(例如 fall back 到不需要該 syscall 的 code path)。
- **KILL**:呼叫該 syscall 是「絕對不該發生」的事(例如已知這支 binary 不會 fork、看到 fork 一定是入侵)。

KILL 對偵測異常更激進,但會造成可用性風險(若應用偶爾走到該 code path 就被殺)。先用 LOG 收集資料、改成 ERRNO 上線、確認穩定再考慮 KILL,是常見做法。

---

## Lab 5 — 解析 Docker 官方預設 profile

```bash
./lab5-default-profile.sh
```

從 [moby/moby GitHub](https://github.com/moby/moby/blob/master/profiles/seccomp/default.json) 下載官方 profile,用 `jq` 拆開:

- 看 defaultAction(預設 ALLOW,白名單只列「想阻止」的)。
- 統計 ERRNO / KILL / 其他 action 各有幾個 syscall。
- 列出被 ERRNO 的代表性 syscall。

**你應該看到**:

- profile 大約 60〜80KB。
- **defaultAction 是 `SCMP_ACT_ERRNO`** — 也就是說它是**白名單**:預設全部 deny,然後 ALLOW ~423 個普通 app 會用到的 syscall。
- 沒被列進去的危險 syscall(`kexec_load`、`reboot`、`swapon`、`bpf`、`init_module` 等等)就被 default action 擋掉。
- 唯一一個被明確設成 ERRNO 的特例是 `clone3`(舊版 glibc 對 clone3 失敗會自動 fallback 到 clone,所以擋它不會弄壞既有 app)。

> 💡 **怎麼自己寫一個 hardening profile?** 通常從官方 profile 複製過來,在它的基礎上把不需要的 syscall 從 ALLOW 列表裡刪掉(等於落入 defaultAction = ERRNO)。從零寫一份是壞主意 — 你會發現連 `dup3` 都漏了,容器啟不起來。

---

## 常用指令速查

```bash
# 觀察容器的 seccomp 狀態
docker run --rm <image> grep Seccomp /proc/self/status

# 套用自訂 profile
docker run --rm --security-opt seccomp=/path/to/profile.json <image>

# 完全關掉 seccomp(危險)
docker run --rm --security-opt seccomp=unconfined <image>

# 看 docker 自己的安全設定
docker info | grep -i security

# 用 strace 看你的 app 用了哪些 syscall(profile 設計參考)
strace -c -f -o /tmp/syscalls myapp
sort -k4 -n -r /tmp/syscalls | head -20
```

## 常見問題 FAQ

**Q: 我的 Docker 跑的 seccomp profile 在哪?**
A: 不在檔案系統上 — Docker daemon 把預設 profile **編譯進 binary**。要看內容只能去 [moby GitHub](https://github.com/moby/moby/blob/master/profiles/seccomp/default.json)。或者你下 `--security-opt seccomp=/path/to/your.json` 用自己的。

**Q: K8s 也用 seccomp 嗎?**
A: 用。Pod spec 的 `securityContext.seccompProfile` 可以選 `RuntimeDefault`(用 runtime 預設,等同 docker 的)、`Localhost`(指定 node 上的 JSON 檔)、或 `Unconfined`(關閉)。預設是不掛 — 1.19 之前是這樣,新版有些 distro 開始預設掛。

**Q: SCMP_ACT_LOG 怎麼用?**
A: 它把 syscall 寫到 kernel audit log(`auditd`)。先把所有東西設成 LOG 跑一段時間,觀察哪些 syscall 真的被用到,再寫一份只 ALLOW 那些的 profile。是 profile 設計的標準工作流。

**Q: seccomp 跟 AppArmor / SELinux 是一樣的東西嗎?**
A: 不一樣。
- **seccomp** 是 syscall 層級的過濾(這個 syscall 號碼能不能呼叫)。
- **AppArmor / SELinux** 是 LSM(Linux Security Module),做檔案/路徑/網路存取的 MAC(Mandatory Access Control)。
三者疊在一起做防禦縱深 — 一道擋不住,還有兩道。

---

###### tags: `Linux` `seccomp` `Docker` `Security` `Tutorial`
