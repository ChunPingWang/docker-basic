---
title: 'Docker Compose 工作坊'
disqus: hackmd
---

# Docker Compose 工作坊

> 一份從零學 **Docker Compose** 的實作教材。會帶你寫一個多容器 stack(nginx + redis)、看 compose 自動建的 network 與 DNS、用 healthcheck 控制啟動順序、用 named volume 做資料持久化,最後把同一份 stack 用純 `docker run` 重現一次,證明 compose 是個 YAML wrapper。

## 目錄

- [學習目標](#學習目標)
- [先備知識](#先備知識)
- [環境需求](#環境需求)
- [專案結構](#專案結構)
- [快速開始](#快速開始)
- [背景知識:Compose v1 vs v2、為什麼用 compose](#背景知識compose-v1-vs-v2為什麼用-compose)
- [Lab 1 — 最小的 compose 起步](#lab-1--最小的-compose-起步)
- [Lab 2 — Compose 自動建的 network 與 DNS](#lab-2--compose-自動建的-network-與-dns)
- [Lab 3 — `depends_on` + `healthcheck`](#lab-3--depends_on--healthcheck)
- [Lab 4 — Volumes、env、restart 策略](#lab-4--volumesenvrestart-策略)
- [Lab 5 — 不用 compose,用 `docker run` 重現](#lab-5--不用-compose用-docker-run-重現)
- [常用指令速查](#常用指令速查)
- [常見問題 FAQ](#常見問題-faq)

---

## 學習目標

完成這份工作坊後,你應該能夠:

1. 寫一份簡單的 `compose.yml`,啟動多容器 stack。
2. 知道 compose 在背後做了哪些 docker 操作(network、volume、container、DNS)。
3. 用 `depends_on` + `healthcheck` 控制啟動順序與就緒檢查。
4. 用 named volume 做資料持久化、用 env 注入設定。
5. 用一連串 `docker network/volume/run` 把一個 compose stack 完整重現,理解 compose 是個 declarative wrapper,runtime 行為一模一樣。

## 先備知識

- 跑過 docker run、會用 -p / -v / -e 旗標。
- 對 YAML 不陌生。

## 環境需求

| 項目 | 版本 / 說明 |
|---|---|
| Docker | 20.10 以上 |
| Docker Compose v2 | 隨 Docker Desktop / `docker-compose-plugin` 一起裝;呼叫方式是 `docker compose ...` |
| 工具 | `bash`、`curl`、`jq` |

確認:

```bash
docker compose version
```

## 專案結構

```
compose/
├── lab1-up.sh             # Lab 1: 最小 compose
├── lab2-network.sh        # Lab 2: 自動 network + DNS
├── lab3-depends.sh        # Lab 3: depends_on + healthcheck
├── lab4-volumes.sh        # Lab 4: volumes / env / restart
├── lab5-no-compose.sh     # Lab 5: 用 docker run 重現
└── README.md
```

每個 lab 把所需的 `compose.yml` 寫在腳本裡(`cat > ...`)再執行,跑完清掉,**不會留下 compose 檔在 repo 裡**。

## 快速開始

```bash
./lab1-up.sh
./lab2-network.sh
./lab3-depends.sh
./lab4-volumes.sh
./lab5-no-compose.sh
```

---

## 背景知識:Compose v1 vs v2、為什麼用 compose

**Compose v1**(`docker-compose`,Python 寫):2014 年問世,用 YAML 描述多容器服務。已不再積極維護。

**Compose v2**(`docker compose`,Go 寫,plugin 形式):2021 年起的官方推薦版,直接整合進 docker CLI。本工作坊用 v2。

**為什麼要用 compose?**

當你的服務不只一個容器,例如:

- web (nginx)
- api (你的 Go/Python 服務)
- db (postgres)
- cache (redis)
- worker (background job)

每次都 `docker run -d --name web --network mynet --network-alias web -v ... -e ... -p 80:80 nginx:...` 連續打五次,而且要記住 network、volume 命名,要記得清理 — 這非常容易出錯。compose 把它變成一份 YAML:

```yaml
services:
  web: {image: nginx, ports: ["80:80"]}
  api: {image: myapi, depends_on: [db, cache]}
  db:  {image: postgres, volumes: [pgdata:/var/lib/postgresql/data]}
  cache: {image: redis}
  worker: {image: myworker, depends_on: [db, cache]}
volumes:
  pgdata:
```

`docker compose up -d` 全部拉起來、`docker compose down` 全部清掉。也支援 healthcheck、profiles、override files、secrets 等等。

**很重要的事**:compose 沒有自己的 runtime,它是一個 **client**,把 YAML 翻譯成一連串 docker API 呼叫。Lab 5 會把這件事拆給你看。

---

## Lab 1 — 最小的 compose 起步

```bash
./lab1-up.sh
```

腳本動態寫一份 minimal compose.yml(只兩個 service:nginx 與 redis),`docker compose up -d` 起來,從 host curl nginx,然後 `docker compose down` 清掉。

**你應該看到**:

- `up -d` 跑起兩個 container 與一個 network。
- `docker compose ps` 顯示兩個服務 running。
- `curl http://localhost:8080` 回 200。
- `down` 把所有東西收乾淨。

---

## Lab 2 — Compose 自動建的 network 與 DNS

```bash
./lab2-network.sh
```

腳本同樣起 nginx + redis,然後:

1. `docker network ls` 看到一個叫 `lab2_default` 的 bridge 網路。
2. `docker network inspect` 看哪些 container 連在上面、各自 IP。
3. 在 web 容器內 `getent hosts cache` 與 `( exec 3<>/dev/tcp/cache/6379 ... )` 都成功 — service 名字自動變成 hostname,可以直接 ping、連線。

**你應該看到**:

- 自動 network 名字是 `<project-name>_default`。
- 跨服務通訊用 service 名字,不需要記 IP。

> 💡 這個自動 DNS 是 docker daemon 的 embedded DNS server 做的(127.0.0.11),compose 啟容器時會把它指向那個 server。

---

## Lab 3 — `depends_on` + `healthcheck`

```bash
./lab3-depends.sh
```

腳本給 redis 加 healthcheck (`redis-cli ping`),web 用 `depends_on: cache: condition: service_healthy`,然後 `up -d --wait`。

**你應該看到**:

- `up -d --wait` 一路 block 到 redis healthy 才回。
- `docker compose ps` 的 STATUS 欄顯示 `(healthy)`。

> 💡 `depends_on` 三種 condition:
> - `service_started` — 啟了就行(不保證 ready)
> - `service_healthy` — healthcheck 通過
> - `service_completed_successfully` — one-shot job 跑完(常用於 init job)

---

## Lab 4 — Volumes、env、restart 策略

```bash
./lab4-volumes.sh
```

腳本示範:

- `volumes: cache-data:/data` 名 volume 持久化。
- `environment:` 注入 env(腳本會 exec 進容器 `env | grep`)。
- `restart: unless-stopped` 容器若 crash 自動重啟。
- 寫 redis key → 重啟容器 → key 仍在(因為在 volume,不在容器)。

**你應該看到**:

- 重啟前後,redis 中的 key 都還在。
- `docker volume ls | grep lab4_` 看到自動命名的 volume。

---

## Lab 5 — 不用 compose,用 `docker run` 重現

```bash
./lab5-no-compose.sh
```

最終揭密 lab。腳本用六條純 docker 指令重現 Lab 4 的 stack:

```bash
docker network create lab5-net
docker volume create lab5-cache-data
docker run -d --name lab5-cache --network lab5-net --network-alias cache \
    -v lab5-cache-data:/data -e REDIS_... --restart unless-stopped redis:alpine
docker run -d --name lab5-web   --network lab5-net --network-alias web \
    -p 8080:80 nginx:alpine
```

**你應該看到**:

- HTTP 從 host 通,服務間 DNS 通,跟 compose 版本行為一致。
- 證明 compose 是個 wrapper,不是另一個 runtime。

**觀念連結**:這呼應前幾份工作坊的「X 不過是個 wrapper」主題:

- `docker build` 是個 wrapper(用 image-internals 那一套也能造 image)。
- `docker run` 是個 wrapper(底下是 runc + bundle + namespaces + cgroups)。
- `docker compose up` 是個 wrapper(底下是一串 docker run + 一些編排邏輯)。

---

## 常用指令速查

```bash
# 基本生命週期
docker compose up -d                           # 起來,背景
docker compose up -d --wait                    # 等到 healthcheck 都 OK
docker compose ps                              # 看狀態
docker compose logs -f [service]               # 看 log
docker compose exec <service> <cmd>            # 進去執行
docker compose down                            # 停 + 清 container + 清 network
docker compose down -v                         # 連 volume 一起清

# 改 compose file
docker compose config                          # 印出展開後的 effective config
docker compose pull                            # 預拉所有 image
docker compose build [service]                 # build 用 build: 指定的 stage

# 多檔案疊加
docker compose -f compose.yml -f compose.override.yml up

# 變數
docker compose --env-file .env.staging up

# 專案隔離(同一份檔不同 project)
docker compose -p staging up
docker compose -p prod up

# scaling
docker compose up -d --scale worker=3
```

## 常見問題 FAQ

**Q: `compose.yml`、`compose.yaml`、`docker-compose.yml`、`docker-compose.yaml` 哪個正確?**
A: Compose v2 自動找這四個之一,順序就是上面列的。新專案建議寫 `compose.yml`(無 `docker-` 前綴),官方推薦的命名。

**Q: 我看別人 compose 檔有 `version: "3.8"` 在最頂端,要寫嗎?**
A: 不用了。Compose v2 已經把 schema version 廢棄,寫了會收到 deprecation warning。直接從 `services:` 開始就好。

**Q: `depends_on: [redis]` 跟 `depends_on: redis: { condition: service_healthy }` 哪個好?**
A: 後者更可靠。短形式只保證 redis 啟了,不保證 ready;app 開始連 redis 時可能還沒 listen。長形式配合 healthcheck 確保 redis ready 後才啟動依賴它的服務。

**Q: compose 跟 K8s 哪個學?**
A: 兩個都學。compose 適合本機開發 / 小型部署 / CI;K8s 適合多 node、多副本、需要 self-healing 的 production。compose 的 YAML 也常被 [Kompose](https://kompose.io/) 工具轉成 K8s manifest 作為起點。

**Q: 為什麼 Lab 5 中的 `--network-alias cache` 是必要的?**
A: 沒有 alias 的話,docker 內建 DNS 只會把容器名(`lab5-cache`)當 hostname。compose 自動建立的網路是把 service 名(`cache`)當 alias,所以其他服務可以 `redis-cli -h cache` 而不是 `redis-cli -h lab5-cache`。Lab 5 為了保持與 Lab 4 一樣的 hostname,顯式加 `--network-alias`。

---

###### tags: `Docker` `Compose` `Tutorial` `Multi-container`
