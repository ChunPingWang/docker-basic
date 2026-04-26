---
title: 'Docker image 內部構造工作坊'
disqus: hackmd
---

> ← 回到 [工作坊集索引](../README.md)

# Docker image 內部構造工作坊

> 一份從零開始拆解 Docker image 的實作教材。本工作坊會帶你看清楚:image 不是黑盒子,就是 **tar + JSON**。會親手用 `docker save` 解開官方 image、用 `docker import` 把任意 tar 變成 image、用 multi-stage 把 image 從幾百 MB 縮到 1 MB,最後完全跳過 Dockerfile 手動造一個 image。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:OCI image format](#背景知識oci-image-format)
- [Lab 1 — `docker history` 看 image 是怎麼疊起來的](#lab-1--docker-history-看-image-是怎麼疊起來的)
- [Lab 2 — `docker save` 解開來看裡面到底有什麼](#lab-2--docker-save-解開來看裡面到底有什麼)
- [Lab 3 — 不寫 Dockerfile,用 `docker import` 造 image](#lab-3--不寫-dockerfile用-docker-import-造-image)
- [Lab 4 — multi-stage build 把 image 從 370MB 縮到 1MB](#lab-4--multi-stage-build-把-image-從-370mb-縮到-1mb)
- [Lab 5 — 完全手動造 image,連 `docker build` 都不用](#lab-5--完全手動造-image連-docker-build-都不用)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 解釋 OCI image 的結構:**manifest + config + N 個 layer blob**。
2. 看懂 `docker history` 與 `docker inspect` 的輸出。
3. 用 `docker save` / `docker load` / `docker export` / `docker import` 進行 image 的 round-trip。
4. 寫 multi-stage Dockerfile,把 build toolchain 從最終 image 拿掉。
5. 不靠 Dockerfile 也能造一個 image。

## 先備知識

- 寫過 Dockerfile,跑過 `docker build`、`docker run`。
- 對 tar、JSON 有基本概念。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| Docker | 20.10 以上 |
| 工具 | `bash`、`tar`、`jq`、`gcc`(會由 image 內安裝,host 不需要) |
| 網路 | 第一次跑 `docker pull` 需連網 |

## 專案結構

```
image-internals/
├── lab1-history.sh       # Lab 1: docker history / inspect
├── lab2-save.sh          # Lab 2: docker save 解開
├── lab3-import.sh        # Lab 3: docker export | docker import
├── lab4-multistage.sh    # Lab 4: multi-stage build
├── lab5-manual.sh        # Lab 5: 完全手動造 image
└── README.md
```

注意:**沒有 `Dockerfile-...` 與 `build.sh`** — 這份工作坊用的是現成的 `ubuntu:22.04` / `alpine:3.19`,以及 lab 中即時生成的 Dockerfile。

## 快速開始

```bash
./lab1-history.sh
./lab2-save.sh
./lab3-import.sh
./lab4-multistage.sh
./lab5-manual.sh   # 依賴 Lab 4 的 hello-scratch image
```

> 💡 **副作用**:Lab 4 會留下 `hello-fat`、`hello-alpine`、`hello-scratch` 三個 image,合計約 400 MB。檢查完用 `docker rmi` 清掉即可。Lab 3 / 5 的 image 由腳本自己刪。

---

## 背景知識:OCI image format

「Docker image」現在叫 **OCI image**(Open Container Initiative,2015 年由 Docker 與 CoreOS 聯合制定)。它就是個 tar 檔,展開後結構如下:

```
.
├── oci-layout                    # 版本號
├── index.json                    # 入口
├── manifest.json                 # docker-style manifest
└── blobs/
    └── sha256/
        ├── <hash>                # config (JSON)
        ├── <hash>                # layer 0 (tarball of file diffs)
        ├── <hash>                # layer 1
        └── ...
```

**關鍵概念**:

- **content-addressable**:每個 blob 的檔名就是它內容的 sha256。內容變了,hash 就變,所以每個 layer 都是不可變的。
- **layer 是 file-level diff**:每層只放「比上一層多了什麼 / 改了什麼 / 刪了什麼」(用 `whiteout` 檔表示刪除)。
- **manifest 描述疊法**:`{ config: <hash>, layers: [<hash>, <hash>, ...] }`,執行時 overlayfs 從 layer[0] 一路疊到 layer[N-1]。
- **共享 layer**:多個 image 共用 layer 時,只需存一份。`ubuntu:22.04` 跟 `node:lts-jammy` 的 base 層是同一個 sha256,本機只下一份。

下面五個 Lab 會一個個把這些事拆開讓你看到。

---

## Lab 1 — `docker history` 看 image 是怎麼疊起來的

```bash
./lab1-history.sh
```

腳本 pull `ubuntu:22.04` 與 `alpine:3.19`,印它們的 history,讓你看到「每個 Dockerfile 指令對應一個 layer」。也會印 `docker inspect` 的 `.Config`,看 ENV、CMD、Labels 等元資料。

**你應該看到**:

- `ubuntu:22.04` 約 80 MB,`alpine:3.19` 約 8 MB,差距全在 base layer。
- 每個 layer 有自己的大小、CREATED、CMD(就是當時的 RUN 指令)。

---

## Lab 2 — `docker save` 解開來看裡面到底有什麼

```bash
./lab2-save.sh
```

腳本 `docker save alpine:3.19 -o alpine.tar`,然後 `tar -xf` 解開,印出:

- 頂層檔案結構(`oci-layout`、`index.json`、`manifest.json`、`blobs/`)。
- `manifest.json` 的 JSON 內容(經 `jq`)。
- `blobs/sha256/` 下每個 blob 是什麼。
- 隨便挑一個 layer blob 用 `tar -tf` 列出來,看到的是檔案系統的 diff。

**你應該看到**:

- `manifest.json` 指向一個 config 與一串 layer。
- 每個 layer blob 自己也是個 tar,展開後就是 rootfs 上「這層新增/修改的檔案」。

---

## Lab 3 — 不寫 Dockerfile,用 `docker import` 造 image

```bash
./lab3-import.sh
```

腳本流程:

1. `docker run -d ubuntu:22.04 sleep 60` 起一個臨時容器。
2. `docker exec` 在容器裡寫一個 `/baked.txt`。
3. `docker export <container> -o baked.tar` — 把容器的整個檔案系統 dump 成 tar。
4. `docker import --change 'CMD ...' baked.tar baked-image:v1` — 把 tar 變成 image。
5. `docker run --rm baked-image:v1` — 跑出來,看到 `cat /baked.txt` 的輸出。

**你應該看到**:

- export 出來的 tar 約 80 MB(等同 ubuntu base 的 rootfs)。
- 新 image 跑起來能讀到 `/baked.txt`。

> 💡 `docker save` vs `docker export`:**save** 是 image 級的(包含所有 layer 與 metadata),**export** 是 container 級的(把該容器當下的 fs 攤平成單一 tar,丟掉 layer 結構)。前者用於備份/分發 image,後者用於把容器轉成新 image。

---

## Lab 4 — multi-stage build 把 image 從 370MB 縮到 1MB

```bash
./lab4-multistage.sh
```

腳本會用 3 個 Dockerfile 對同一支 `hello.c` 做 build:

| 變體 | 構造 | 預期大小 |
|---|---|---|
| `hello-fat` | `FROM ubuntu` + `apt install gcc` + `gcc -o /hello` | ~370 MB |
| `hello-alpine` | builder stage 編 static binary,執行階段 `FROM alpine` | ~10 MB |
| `hello-scratch` | builder stage 編 static binary,執行階段 `FROM scratch` | ~1 MB |

**你應該看到**:

- 三個 image 跑起來輸出一樣("hello from a tiny image")。
- `hello-fat` 把 gcc 與 libc-dev 的所有 header 一起留在 image 裡 → 大。
- `hello-scratch` 只有那個 1MB 的靜態 binary,連 `/bin/sh` 都沒 → 進不去 shell,但 production 跑得起來。

> 💡 **Go / Rust 黨的最愛**:`CGO_ENABLED=0 go build` 出來就是靜態 binary,直接放進 `FROM scratch`,production image 就是 binary 大小,沒了。

---

## Lab 5 — 完全手動造 image,連 `docker build` 都不用

```bash
./lab5-manual.sh
```

腳本流程:

1. 從 Lab 4 的 `hello-scratch` 把那支 1 MB 靜態 binary 取出來(`docker create` + `docker cp`)。
2. 在 host 上開一個 `rootfs/`,放進那支 binary。
3. `tar -C rootfs -cf manual.tar .` — 打包成 tar。
4. `docker import --change 'ENTRYPOINT [...]' manual.tar manual-hello:v1` — 變 image。
5. `docker run --rm manual-hello:v1` — 跑出來。
6. `docker inspect` 看 config,跟一般 image 沒兩樣。

**觀念連結**:Google 的 [`ko`](https://github.com/ko-build/ko)、Buildpacks、Bazel rules_docker 都是用類似手法 — 跳過 `docker build` / Dockerfile,直接 layer-by-layer 拼出 image。理解這個 Lab 後,「怎麼造 image」對你來說就只是「打 tar 包 + 寫 JSON」。

---

## 常用指令速查

```bash
# 觀察 image
docker images
docker history <image>
docker inspect <image>
docker inspect --format '{{json .Config}}' <image> | jq

# Image / Container 互轉
docker save <image> -o file.tar           # image -> tar (含 layer)
docker load -i file.tar                   # tar -> image
docker export <container> -o file.tar     # container fs -> tar (攤平)
docker import file.tar <name>:<tag>       # tar -> image (單一 layer)

# 用 --change 在 import 時注入 metadata
docker import --change 'CMD ["bash"]' \
              --change 'ENV FOO=bar' \
              file.tar custom:v1

# 清理
docker image prune                # 砍沒被 tag 的中間 layer
docker image prune -a             # 砍所有未被使用的 image
docker rmi <image>
```

## 常見問題 FAQ

**Q: `RUN` 指令越多 image 越大嗎?**
A: 是。每個 `RUN` 都會建一層,即使 `RUN apt-get install ... && rm /var/cache` 在同一層裡刪掉了某檔,前面建立的內容仍在 layer 中(只是被後面的 whiteout 標記蓋掉)。要真的瘦,就要把所有相關步驟用 `&&` 串在同一個 `RUN` 裡。

**Q: 為什麼我的 multi-stage build 沒效果?**
A: 通常是 final stage 還是 `FROM ubuntu` 之類的大 base,只省了 builder stage 的 toolchain。要更激進可以用 `FROM alpine` 或 `FROM scratch`(後者要靜態 binary)。

**Q: `docker import` 的 image 為什麼跑不起來?**
A: 多半是 tar 裡沒有可執行的 entrypoint(沒 `/bin/sh`、沒任何 binary),或 `--change` 設的 CMD 路徑錯了。先用 `docker run --rm <image> ls /` 試試 image 裡有什麼。

**Q: `FROM scratch` 的 image 怎麼進去 debug?**
A: 進不去 — 它沒 shell。常見手法:臨時加一個 debug stage `FROM busybox`,複製進去看;或 `docker cp` 把檔案撈出來在 host 看;production 階段就用 distroless / scratch + 靜態 binary。

**Q: 我看到 image tar 裡有 `oci-layout`,但同事的沒有?**
A: Docker 24.0+ 預設輸出 OCI 格式,舊版輸出 docker-style 格式(目錄式 layer + `manifest.json` 在頂層)。兩種都能 `docker load`,結構大同小異。

---

###### tags: `Docker` `OCI Image` `Multi-stage Build` `Tutorial`
