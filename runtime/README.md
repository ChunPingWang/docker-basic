---
title: 'Container Runtime 工作坊:Docker → containerd → runc'
disqus: hackmd
---

# Container Runtime 工作坊:Docker → containerd → runc

> 一份從零開始解剖 container runtime 鏈的實作教材。會帶你看 process tree 觀察「Docker 其實只是個外殼」、用 `ctr` 直接跟 containerd 講話跳過 Docker、看一個 OCI bundle 的內部、用 `runc` 直接跑 bundle、最後親手客製 OCI spec 的 config.json。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:三層 runtime 是怎麼分工的](#背景知識三層-runtime-是怎麼分工的)
- [Lab 1 — process tree 觀察 runtime 鏈](#lab-1--process-tree-觀察-runtime-鏈)
- [Lab 2 — 用 `ctr` 跳過 Docker 直接打 containerd](#lab-2--用-ctr-跳過-docker-直接打-containerd)
- [Lab 3 — 看一個 OCI bundle 長什麼樣](#lab-3--看一個-oci-bundle-長什麼樣)
- [Lab 4 — 用 `runc` 直接跑一個 bundle](#lab-4--用-runc-直接跑一個-bundle)
- [Lab 5 — 客製 config.json,看 OCI spec 怎麼影響行為](#lab-5--客製-configjson看-oci-spec-怎麼影響行為)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 畫出 docker → containerd → runc 的呼叫鏈,說明每一層的職責。
2. 用 `ctr` 直接跟 containerd 互動,完全不經過 Docker daemon。
3. 看懂 OCI 一個 image bundle = `rootfs/` + `config.json` 的結構。
4. 用 `runc run` 啟動一個容器,不靠任何 daemon。
5. 客製 OCI spec 的 process / capabilities / cgroup 欄位,看到行為的差別。

## 先備知識

- 跑過前面四份工作坊(network / storage / cgroups / pidns)會有很大幫助 — 這份把那些底層 primitives 串起來看。
- 知道什麼是 daemon、CLI、gRPC。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| Docker | 20.10 以上(本機已用 containerd 作為 runtime) |
| containerd / runc | 通常隨 docker 安裝;Ubuntu 22.04+ 都有 |
| 工具 | `bash`、`jq`、`ps`、`runc`、`ctr` |
| 權限 | Lab 2、4、5 需要 `sudo` |

確認:

```bash
docker info | grep -i runtime
runc --version
ctr --version
```

## 專案結構

```
runtime/
├── lab1-tree.sh       # Lab 1: 觀察 process tree
├── lab2-ctr.sh        # Lab 2: ctr 直接打 containerd(需 sudo)
├── lab3-bundle.sh     # Lab 3: OCI bundle 結構
├── lab4-runc.sh       # Lab 4: runc 直接跑 bundle(需 sudo)
├── lab5-spec.sh       # Lab 5: 客製 config.json(需 sudo)
└── README.md
```

不需要自家 image。

## 快速開始

```bash
./lab1-tree.sh
sudo ./lab2-ctr.sh
./lab3-bundle.sh
sudo ./lab4-runc.sh
sudo ./lab5-spec.sh
```

---

## 背景知識:三層 runtime 是怎麼分工的

Docker 一開始(2013)是單體 daemon,自己處理 image、network、namespace 等等。後來社群把功能拆出去,演變成今天這樣的層次:

```
   docker CLI
      │ HTTP REST
      ▼
   dockerd (Docker daemon)        ← image 管理、API、build、network、volume
      │ gRPC
      ▼
   containerd                     ← 跨 Docker / K8s 共用的低層管理 daemon
      │ shim (per-container)       管理 image pull、container 生命週期
      ▼
   containerd-shim-runc-v2        ← 每個容器一個,常駐負責收 stdio / 處理子程序
      │ exec
      ▼
   runc                           ← 一次性 binary,call 一堆 syscall 把容器拉起來
      │ exec
      ▼
   你的 app                        ← 容器內的 PID 1
```

**為什麼要拆這麼多層?**

- **Docker daemon** 寄生在 containerd 上 — Docker 自己只專心做 image build、CLI、API、network、volume 等使用者面相的事。
- **containerd** 是中立的 daemon,K8s 可以直接用(透過 CRI),不需要 Docker。podman 也可以做為替代。
- **shim**(每個容器一個常駐 process):runc 是一次性的,exec 完就結束。但容器需要一個父 process 來收 stdio、reparent zombie、上報狀態 — 這就是 shim 的責任。可以用 `ps -ef | grep shim` 看。
- **runc** 是純粹的 launcher:把 OCI bundle 拉起來成 process,然後就走人。不常駐,沒狀態。

**OCI 規範**

[OCI](https://opencontainers.org/) 訂了兩份規範:

1. **OCI Image Spec** — image 是什麼樣子(我們的 image-internals 工作坊涵蓋了)。
2. **OCI Runtime Spec** — bundle 是什麼樣子、runtime 該怎麼啟動容器(本份工作坊的主軸)。

任何符合 OCI Runtime Spec 的 runtime(runc、crun、kata-runtime、gVisor、firecracker)都能消化同一個 bundle。

下面五個 Lab 會把這些抽象一個一個變具體。

---

## Lab 1 — process tree 觀察 runtime 鏈

```bash
./lab1-tree.sh
```

腳本啟動一個 sleep 容器,在 host 上從容器的 PID 1 一路往上爬 ppid,印出每一層。

**你應該看到**:

- `sleep 60`(容器內 PID 1)
- `containerd-shim-runc-v2`(它的 ppid)
- `systemd`(再上去一層)

**沒看到的**:`runc` 和 `containerd` daemon 不在直接父子鏈上 —
- runc 已經 exec 完離場了(它是 fork → setup namespaces → exec into your app 的一次性程式)。
- containerd 是 daemon,跟 shim 之間是 gRPC 而不是 fork 關係。

---

## Lab 2 — 用 `ctr` 跳過 Docker 直接打 containerd

```bash
sudo ./lab2-ctr.sh
```

腳本用 `ctr` 在一個獨立 namespace(`runtime-lab2`)裡 pull alpine、run 一個容器,完全沒 docker 出場。

**你應該看到**:

- `ctr -n runtime-lab2 images list` 顯示我們剛 pull 的 alpine。
- `ctr -n moby images list` 顯示 Docker 自己用的 image(它把所有東西放在 `moby` namespace)。
- 容器跑出 hello 訊息,就跟 `docker run` 一樣。

> 💡 **K8s 視角**:K8s 的 kubelet 跟 containerd 講話用的是 CRI(Container Runtime Interface)gRPC,不是 ctr。ctr 是給人用的 debug CLI,功能上類似 K8s 的 `crictl`。

---

## Lab 3 — 看一個 OCI bundle 長什麼樣

```bash
./lab3-bundle.sh
```

腳本用 `runc spec` 產生一個預設 config.json,然後 `jq` 把幾個關鍵段落印出來:

- `.process` — 要跑什麼指令、cwd、env、capabilities。
- `.linux.namespaces` — 要建哪幾種 namespace(預設 7 種)。
- `.mounts` — 容器內要 mount 什麼(預設有 /proc、/dev、/sys、/dev/pts 等)。

**觀念連結**:
- Docker 的 `--user`、`--cap-drop`、`--memory`、`--read-only`、`-v` 這些旗標,在 daemon 端都會翻譯成這個 JSON 的某個欄位的修改。
- K8s 的 PodSpec 同樣會被 kubelet 翻譯成 OCI spec 然後丟給 containerd → runc。

---

## Lab 4 — 用 `runc` 直接跑一個 bundle

```bash
sudo ./lab4-runc.sh
```

腳本流程:

1. `docker export` 抽出 alpine 的 rootfs,放進 `bundle/rootfs/`。
2. `runc spec` 在 `bundle/` 下產生 `config.json`。
3. `jq` 修改 config 的 `.process.args`,改成 `["/bin/sh", "-c", "echo hello..."]`。
4. `runc run mycontainer` — 啟動。

**你應該看到**:

- 容器跑出 echo 內容、PID(1,因為它就是新 ns 的 PID 1)、`ls /etc` 結果。
- 容器一退出,runc 就清掉(本範例腳本在 trap 裡 `runc delete -f` 也保險清一次)。

> 💡 **觀念**:從現在開始你可以說「我懂容器了」 — `runc run` 之外的所有層(containerd、dockerd、CLI)都只是「方便」,核心就是 runc + bundle。

---

## Lab 5 — 客製 config.json,看 OCI spec 怎麼影響行為

```bash
sudo ./lab5-spec.sh
```

腳本在 Lab 4 的基礎上,進一步用 `jq` 改 spec:

- `.process.env` 加一個 `MY_VAR=hello-from-spec`
- `.process.capabilities` 全清,只留 `CAP_NET_BIND_SERVICE`
- `.linux.resources.memory.limit = 33554432`(32MB)

執行後,容器內 echo 出:

- `MY_VAR=hello-from-spec` ← 從 spec 注入
- `memory.max=33554432` ← cgroup 設定
- `CapEff: 0000000000000400` ← 只有 NET_BIND_SERVICE bit

**觀念連結**:每個 Docker / Compose / K8s 的旗標都最終變成這份 JSON 的某個欄位。看懂 OCI Runtime Spec,就等於看懂所有 orchestrator 跟 runtime 之間的契約。

---

## 常用指令速查

```bash
# Daemon / runtime 觀察
docker info | grep -i runtime
ps auxf | grep -E 'containerd|runc'

# ctr (containerd CLI)
sudo ctr --help
sudo ctr namespaces list                      # 看有哪些 ns
sudo ctr -n moby images list                  # Docker 用 moby ns
sudo ctr -n moby containers list
sudo ctr -n <ns> images pull <ref>
sudo ctr -n <ns> run --rm <image> <id> <cmd>

# runc
runc --version
runc spec                                     # 產生 default config.json
sudo runc run <id>                            # 啟動 (需要在 bundle 目錄)
sudo runc list
sudo runc state <id>
sudo runc delete -f <id>

# OCI image -> bundle
docker create --name temp <image>
mkdir -p bundle/rootfs
docker export temp | tar -C bundle/rootfs -xf -
docker rm temp
```

## 常見問題 FAQ

**Q: K8s 還用 Docker 嗎?**
A: 1.24 之後不直接用 Docker。Kubelet 的 CRI 介面只認 containerd 或 cri-o。Docker daemon 過去是透過一個叫 dockershim 的轉換層接 CRI,1.24 移除了 dockershim。Docker 自己仍在跑容器(透過 containerd),只是 K8s 不再經過 dockerd。

**Q: 為什麼要有 shim?直接讓 containerd 當 parent 不行嗎?**
A: 重啟 containerd 時,所有容器若以 containerd 為 parent 會跟著被信號處理影響。把 shim 放中間,containerd 重啟時容器仍然由 shim 維持(containerd 重啟後重新接管)。也方便容器的 stdio attach/detach。

**Q: runc、crun、youki、kata-runtime 差在哪?**
A:
- **runc**:Go 寫,reference 實作,最普及。
- **crun**:C 寫,啟動更快、記憶體更小,Red Hat 主導。
- **youki**:Rust 寫,新但成熟度上升中。
- **kata-runtime**:每個容器跑在迷你 VM 裡,用硬體虛擬化做隔離,代價是啟動慢、消耗大。
都符合 OCI Runtime Spec,可以互相替換。Docker 用 `--runtime=...` 切。

**Q: ctr 跟 nerdctl 又是什麼?**
A: 都是 containerd 的 CLI。`ctr` 是 containerd 內建,介面偏低層、難用。`nerdctl` 是社群做的「docker-compatible」CLI,指令幾乎跟 docker 一樣,但底下是 containerd。在 K8s node 上 debug 時很常用。

---

###### tags: `Container Runtime` `Docker` `containerd` `runc` `OCI` `Tutorial`
