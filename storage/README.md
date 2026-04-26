---
title: 'Docker 儲存工作坊'
disqus: hackmd
---

> ← 回到 [工作坊集索引](../README.md)

# Docker 儲存工作坊

> 一份從零開始學習 Docker 儲存的實作教材。本工作坊會帶你動手體驗 Docker 的四種掛載方式(bind mount、named volume、anonymous volume、tmpfs),並進一步用 Linux `overlayfs` 親手做一次 Docker image layer 背後的 Copy-on-Write。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:Docker 的四種儲存方式](#背景知識docker-的四種儲存方式)
- [Lab 1 — bind mount](#lab-1--bind-mount)
- [Lab 2 — named volume](#lab-2--named-volume)
- [Lab 3 — anonymous volume(VOLUME 指令)](#lab-3--anonymous-volumevolume-指令)
- [Lab 4 — tmpfs mount](#lab-4--tmpfs-mount)
- [Lab 5 — 自己動手做 overlayfs](#lab-5--自己動手做-overlayfs)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 說出 Docker 四種掛載方式(`bind mount`、`volume`、`anonymous volume`、`tmpfs`)的差異與使用時機。
2. 用 `docker volume`、`docker inspect`、`findmnt` 等指令觀察容器的儲存設定。
3. 理解 Dockerfile 中的 `VOLUME` 指令會帶來什麼後果(以及為什麼會默默吃掉磁碟)。
4. 親手用 Linux `overlayfs` 做出一個 lower / upper / merged 三層結構,理解 Docker image layer 的 Copy-on-Write 是怎麼運作的。

## 先備知識

- 會用 terminal 下基本指令(`cd`、`ls`、`cat`)。
- 知道 Docker 是什麼,並做過 `docker run hello-world`。
- **不需要**懂 Linux kernel 或檔案系統,腳本會把每個步驟的輸出印給你看。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| 作業系統 | Linux(建議 Ubuntu 22.04 以上)。Lab 5 在 Docker Desktop 的 VM 內可能無法直接驗證 |
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
storage/
├── Dockerfile-ubuntu-storage   # 帶有 VOLUME 指令的 Ubuntu 映像
├── build.sh                    # 建立映像
├── lab1-bind.sh                # Lab 1: bind mount
├── lab2-volume.sh              # Lab 2: named volume
├── lab3-anon-volume.sh         # Lab 3: anonymous volume / VOLUME 指令
├── lab4-tmpfs.sh               # Lab 4: tmpfs(記憶體掛載)
├── lab5-overlay.sh             # Lab 5: 手動建立 overlayfs(需 sudo)
└── README.md                   # 本文件
```

## 快速開始

```bash
# 1. 建立練習用的映像(只需做一次)
./build.sh

# 2. 依序執行各個 Lab
./lab1-bind.sh
./lab2-volume.sh
./lab3-anon-volume.sh
./lab4-tmpfs.sh

# Lab 5 需要 root 權限
sudo ./lab5-overlay.sh
```

> 💡 **小提醒**:Lab 1、4 的容器都加了 `--rm`,結束後會自動清掉。Lab 2 會留下 named volume、Lab 3 會故意留下 anonymous volume,讓你看到「忘了清」的後果,腳本最後會印出清理指令。

---

## 背景知識:Docker 的四種儲存方式

容器的 root filesystem 預設是 image 各層 + 一個 writable layer 疊起來的(下面 Lab 5 會親手做一次)。但這層 writable layer 跟著容器一起被刪 — 為了讓資料活得比容器久,Docker 提供了幾種掛載方式:

| 類型 | 行為 | 適合場景 |
|---|---|---|
| `bind mount` | 把 host 上的某個目錄/檔案直接掛進容器 | 開發時把原始碼掛進去、容器需要讀 host 設定檔 |
| `named volume` | Docker 管理的儲存空間,通常落在 `/var/lib/docker/volumes/` | 資料庫資料、容器間共用、希望由 Docker 管理生命週期 |
| `anonymous volume` | 透過 Dockerfile `VOLUME` 指令或 `-v /path` 不指定名字時自動建立 | 通常你不會主動用,但常常意外產生造成磁碟膨脹 |
| `tmpfs mount` | 純記憶體,容器結束就消失 | 機敏資料(密鑰)、效能要求高的暫存 |

容器自己預設的 writable layer 也是「儲存」之一,只是它跟著容器一起死。Lab 5 會用 `overlayfs` 親手把這個機制重做一遍。

---

## Lab 1 — bind mount

**目標**:看到 host 與容器之間「同一份檔案、兩邊看得到」的效果,並理解 bind mount 會「蓋掉」image 裡原本的內容。

```bash
./lab1-bind.sh
```

腳本會做這些事:

1. 在 host `mktemp` 一個臨時目錄,先放一個 `from-host.txt`。
2. 用 `-v <host-dir>:/data` 啟動容器,在容器內列出 `/data` 的內容、再寫一個 `from-container.txt`。
3. 容器退出後,在 host 端確認該檔案真的出現了。

**你應該看到**:

- 容器內看到的 `/data/from-host.txt` = host 端寫的那份。
- 容器內看不到 image build 階段塞的 `/data/seed.txt`(被 bind mount 蓋掉了)。
- 容器寫的 `/data/from-container.txt` 直接落在 host 目錄裡。

> ⚠️ bind mount 把 host 的權限與內容直接交給容器,**容器內的 root 等於可以動 host 的那個目錄**,正式環境要小心路徑。

---

## Lab 2 — named volume

**目標**:看到 Docker 自己管的儲存空間怎麼跨容器持久化資料。

```bash
./lab2-volume.sh
```

腳本會做這些事:

1. 用 `docker volume create storage-lab2-vol` 建一個 named volume。
2. 啟動第一個容器,把 volume 掛在 `/data`,寫入 `note.txt`,容器退出。
3. 啟動第二個容器(全新生命週期),掛同一個 volume,確認 `note.txt` 還在。
4. 印出 volume 在 host 上的真實路徑(預設 `/var/lib/docker/volumes/...`)。

**你應該看到**:

- 第一個容器啟動時,`/data` 不只有空目錄,還有 image 中 `/data/seed.txt` — 因為「掛 named volume 到 image 已有內容的目錄」會把 image 的內容**複製**進空 volume(只在 volume 為空時發生一次)。
- 第二個容器讀得到第一個容器寫的檔案。
- volume 不會跟著容器消失,要手動 `docker volume rm` 才會清掉。

---

## Lab 3 — anonymous volume(VOLUME 指令)

**目標**:示範 Dockerfile 中的 `VOLUME` 指令是怎麼「在你不知不覺中」建立一個 anonymous volume,以及為什麼長期下來會吃掉磁碟。

```bash
./lab3-anon-volume.sh
```

腳本會做這些事:

1. 啟動 `ubuntu-storage` 容器(這個 image 有 `VOLUME ["/data"]`),**故意不加 `--rm`**。
2. 用 `docker inspect` 看 `.Mounts`,你會看到一個 type 為 `volume`、有著一串隨機 hash 名字的 anonymous volume。
3. 停掉並 `docker rm` 容器後,**該 anonymous volume 不會被自動清掉**。

**你應該看到**:

- `docker volume ls` 多出一個 64 字元 hash 的 volume,沒人記得它是誰建的。
- 在 CI 或開發機上長期跑 `VOLUME` 過的 image 而沒加 `--rm`,這些 dangling volume 會一直累積。

> 💡 解法:跑完即丟的場景一律用 `--rm`,或定期 `docker volume prune` 清理沒人用的。

---

## Lab 4 — tmpfs mount

**目標**:看到「資料只存在 RAM、容器結束就消失」的掛載方式。

```bash
./lab4-tmpfs.sh
```

腳本會做這些事:

1. 用 `--tmpfs /scratch:size=128m` 啟動容器。
2. 在容器內 `findmnt /scratch`,看到型別是 `tmpfs`。
3. 寫 64 MB 進去,確認可寫,然後容器退出。

**你應該看到**:

- `/scratch` 的 mount 型別是 `tmpfs`,**完全不會落到磁碟**。
- 容器退出後,那 64 MB 跟著一起 free。

> 💡 適合場景:存放 secrets、TLS private key、需要高速但不需要持久的暫存。

---

## Lab 5 — 自己動手做 overlayfs

**目標**:不靠 Docker,純粹用 Linux `mount -t overlay` 把 Docker image layer 的 Copy-on-Write 做出來。看完這個 Lab,你會徹底懂為什麼多個容器可以共用同一個 base image 卻互不影響。

```bash
sudo ./lab5-overlay.sh
```

腳本會做這些事:

1. 在 `/tmp/storage-lab5/` 下建四個目錄:`lower`、`upper`、`work`、`merged`。
2. 在 `lower/` 放兩個檔案,當作「base image」的內容。
3. 用 `mount -t overlay` 把 `lower`(唯讀)+ `upper`(可寫)疊起來,掛到 `merged`。
4. 在 `merged/` 修改檔案、新增檔案,觀察:
   - `lower/` 完全不變(這就是為什麼多容器可以共享 image)。
   - `upper/` 會出現修改後的版本與新檔案(這就是容器的 writable layer)。
   - `merged/` 看到的是兩層合併的最終結果。

**觀念連結**:Docker 跑容器時:

- **lowerdir** = image 的所有 layer(唯讀)
- **upperdir** = 容器自己的 writable layer
- **merged** = 容器內看到的 `/`

`docker run` 從同一個 image 啟兩個容器,就是建兩個獨立的 upperdir,共享同一份 lowerdir — 所以 image 大但容器小。理解這個 Lab 後,Docker 的 layered storage 就不再是黑盒子了。

清理(腳本不會自動 umount,讓你有時間觀察):

```bash
sudo umount /tmp/storage-lab5/merged
sudo rm -rf /tmp/storage-lab5
```

---

## 常用指令速查

```bash
# Volume 操作
docker volume ls
docker volume create <name>
docker volume inspect <name>
docker volume rm <name>
docker volume prune              # 清掉沒人用的 volume

# 看容器掛載
docker container inspect --format='{{ json .Mounts }}' <id> | jq

# 容器內看 mount 結構
findmnt
findmnt <path>
cat /proc/mounts

# Overlayfs 手動操作(host 上)
mount -t overlay overlay -o lowerdir=L,upperdir=U,workdir=W /target
umount /target
```

## 常見問題 FAQ

**Q: bind mount 跟 named volume 哪個比較好?**
A: 看用途。**開發**通常用 bind mount(改原始碼立刻反映進容器);**正式環境**或**資料庫資料**用 named volume(由 Docker 管權限與生命週期,跨主機遷移較友善)。

**Q: 為什麼 Lab 2 第一次啟動,空 volume 裡就已經有 `seed.txt`?**
A: 這是 Docker 的「empty volume populate」行為:把 volume 掛到 image 裡**原本有內容**的目錄時,Docker 會在 volume 為空時把 image 的內容複製進去。掛在空目錄上不會發生這件事。

**Q: Lab 3 的 anonymous volume 用 `docker rm -v` 是不是就會一起刪?**
A: 是。`-v` 會把該容器名下的 anonymous volume 一起刪。但 named volume 不會,要手動 `docker volume rm`。

**Q: 跑 Lab 5 後,`/tmp/storage-lab5/merged` 還掛著怎麼辦?**
A: `sudo umount /tmp/storage-lab5/merged` 即可,然後 `rm -rf /tmp/storage-lab5` 清掉目錄。Lab 5 不會影響 host 上其他 mount。

**Q: 為什麼 `Dockerfile-ubuntu-storage` 還要 `apt-get install util-linux`?**
A: 因為 Lab 1、4 在容器內會用 `findmnt` 看掛載資訊,minimal Ubuntu 映像有時會缺;裝起來保險。

---

###### tags: `Docker` `Storage` `Volume` `Tutorial` `OverlayFS`
