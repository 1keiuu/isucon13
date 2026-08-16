---
name: pprotein-setup
description: pprotein（kaz/pprotein）の導入手順。アクセスログ集計（alp）・スロークエリ集計（slp）・pprof/fgprof を1つのUIに集約し、/initialize フックでベンチ開始と同時に自動収集させる。ログローテートが不要になり、走行ごとに結果が残る。ISUCON の初動で計測基盤を立てるとき、pprotein が動かない/結果が出ないとき、複数台構成で計測対象を増やすときに使う。
---

# pprotein 導入

**何を解決するか**: alp・pt-query-digest・pprof を毎回手で叩いて `.txt` に落とす運用をやめる。
ベンチを回すと fgprof / httplog / slowlog が揃い、走行ごとに UI 上で比較できる。

- ログローテートが不要（走行ごとに別スナップショットとして保存）
- UI を競技インスタンス外に置けば、解析負荷をサーバから逃がせる

**導入コスト目安 20〜30 分。** nginx のログ形式を LTSV に変えるため、既存の `make nginx/alp`（JSON 前提）と衝突する。§3 を必ず読む。

前提: Go アプリ。**v1.2.4** を前提に記述。

---

## 1. 構成（競技本番想定）

競技ではベンチが **nginx（:443）経由**でアプリに到達する。スロークエリログは **DB サーバ上のファイル**にある。

| 役割 | 実体 | ポート | 収集対象 |
|---|---|---|---|
| 本体 | `pprotein` | 9000 | UI、alp/slp 実行、スナップショット保存 |
| app 内 standalone | `standalone.Integrate` | 19000 | **fgprof**（pprof 系） |
| app 上の agent | `pprotein-agent` | 19001 | **httplog**（nginx access.log） |
| db 上の agent | `pprotein-agent` | 19000 | **slowlog** |

```
[計測 UI 用マシン or app サーバ]
  pprotein :9000

[app サーバ]
  app 内 standalone :19000  → fgprof
  pprotein-agent    :19001  → /var/log/nginx/access.log（root で読む）
  nginx :443 → app :8080

[db サーバ]
  pprotein-agent :19000  → /var/log/mysql/mysql-slow.log
```

**ポイント**

- `pprotein-agent` の pprof は **agent 自身**のプロファイル。アプリの fgprof は **app 内 standalone :19000** から取る。
- httplog は nginx ログの読み取り権限が必要。**`isucon` ユーザの standalone ではなく :19001 の agent（root）** を使う。
- slowlog の URL は **DB サーバのプライベート IP** を指定する（`127.0.0.1` は app から見た db ではない）。
- 余裕があれば pprotein 本体は競技インスタンス外に置く。

---

## 2. 依存バイナリ（pprotein を置くホスト）

pprotein は解析を外部コマンドに委譲する。PATH に無いと収集は成功しても解析が `fail` になる。

```sh
ARCH=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')
apt-get install -y graphviz unzip
wget -q "https://github.com/kaz/pprotein/releases/download/v1.2.4/pprotein_1.2.4_linux_${ARCH}.tar.gz"
tar -xzf pprotein_1.2.4_linux_${ARCH}.tar.gz
install ./pprotein ./pprotein-agent /usr/local/bin/
# alp / slp も GitHub Releases から同 ARCH で wget
which alp slp dot pprotein pprotein-agent
```

競技サーバに `go` が無いことが多い。**`go install` は使わずバイナリを wget する**（`make pprotein/setup-app` / `pprotein/setup-db`）。

---

## 3. nginx を LTSV にする

pprotein は `alp ltsv` を実行する。**JSON ログは解析できない。**

```nginx
log_format ltsv "time:$time_local"
  "\thost:$remote_addr"
  "\tforwardedfor:$http_x_forwarded_for"
  "\treq:$request"
  "\tstatus:$status"
  "\tmethod:$request_method"
  "\turi:$request_uri"
  "\tsize:$body_bytes_sent"
  "\treferer:$http_referer"
  "\tua:$http_user_agent"
  "\treqtime:$request_time"
  "\tcache:$upstream_http_x_cache"
  "\truntime:$upstream_http_x_runtime"
  "\tapptime:$upstream_response_time"
  "\tvhost:$host";

access_log /var/log/nginx/access.log ltsv buffer=32k flush=1;
```

- `buffer=32k flush=1` を付ける（`flush` 単体は nginx エラー。バッファなしだと tail 収集時に行が見えず **empty content** になる）
- 終盤用に `access_log off;` はコメントアウトで残す

`make nginx/alp` を使い続けるなら `alp json` → `alp ltsv` に合わせる。

---

## 4. MySQL スロークエリログ（db サーバ）

cnf に書く（`SET GLOBAL` は再起動で消える）。

```ini
[mysqld]
slow_query_log      = 1
slow_query_log_file = /var/log/mysql/mysql-slow.log
long_query_time     = 0
```

```sh
systemctl restart mysql
chmod +rx /var/log/mysql && chmod +r /var/log/mysql/mysql-slow.log
```

`long_query_time = 0` にする。閾値を上げると N+1（1回は速いが回数が異常）が見えなくなる。

---

## 5. アプリに standalone を入れる

`echov4.Integrate(e)` は **`middleware.Logger()` を有効化するので使わない**。
アプリ本体のポートに `/debug/*` を生やさず、**別ポート + 環境変数で止められる形**にする。

```go
import "github.com/kaz/pprotein/integration/standalone"

func startProfiler() {
    if os.Getenv("ENABLE_PPROTEIN") != "1" {
        return
    }
    go standalone.Integrate("127.0.0.1:19000") // localhost ではなく 127.0.0.1
}
```

環境変数は **`env.sh` に書き、`EnvironmentFile=` で読む**（systemd の `KEY=value` 直書きは無効）。

```bash
# env.sh
ENABLE_PPROTEIN=1
PPROTEIN_HTTPLOG=/var/log/nginx/access.log
ISUCON13_MYSQL_DIALCONFIG_ADDRESS=<db のプライベート IP>
```

`ISUCON13_MYSQL_DIALCONFIG_ADDRESS` が `127.0.0.1` のままだと、db 分離構成でアプリが別ホストの DB に繋がらず **slowlog が空**になる。

### Commit 列について

UI の **Commit** は収集時点の **git HEAD**（メッセージ・ハッシュ・ブランチ）。
`PPROTEIN_GIT_REPOSITORY` で指定したディレクトリの `.git` を読み、`X-Git-Repository` ヘッダ経由で保存される。

- サーバ上で `git pull` デプロイしていればコミットが表示される
- rsync のみで `.git` が無い場合は `[unknown]` になる（**計測には影響しない。無視してよい**）
- httplog / slowlog は agent から収集するため、agent 側にも `PPROTEIN_GIT_REPOSITORY` が必要（任意）

---

## 6. `/initialize` に収集フックを仕込む

httplog / slowlog は **「収集開始後 `Duration` 秒間にログへ増えた行だけ」** を返す tail 実装。
**ベンチ開始と同時に collect を走らせる**必要がある。

```go
func triggerPproteinCollect() {
    if os.Getenv("ENABLE_PPROTEIN") != "1" {
        return
    }
    endpoint := os.Getenv("PPROTEIN_ENDPOINT")
    if endpoint == "" {
        endpoint = "http://127.0.0.1:9000"
    }
    go func() {
        time.Sleep(2 * time.Second)
        http.Get(endpoint + "/api/group/collect")
    }()
}
```

- **`GET`** で叩く（POST は 405）
- **必ず `go func()` で非同期**（同期だと `/initialize` がタイムアウトする）
- ベンチ後に UI で手動 collect しても httplog/slowlog は空（正常）
- `Duration` はベンチ時間（秒）に合わせる

### db 分離構成で `/initialize` が遅い場合

`init.sh` が SQL ファイルごとに mysql を起動し、かつ `long_query_time=0` で全クエリが slow log に書かれると、initialize が **30秒超**してベンチが失敗することがある。

対策（`webapp/sql/init.sh`）:

1. 全 SQL を **1 セッション**にまとめる（`cat *.sql | mysql ...`）
2. 投入中だけ `SET GLOBAL slow_query_log = OFF` してから `ON` に戻す

---

## 7. 起動（systemd 推奨）

```sh
mkdir -p /opt/pprotein
systemctl enable --now pprotein.service              # app（または計測用マシン）
systemctl enable --now pprotein-agent-httplog.service # app :19001
systemctl enable --now pprotein-agent.service         # db  :19000
```

`data/` に `targets.json`・`alp.yml`・`slp.yml`・スナップショットが溜まる。起動ディレクトリを固定する（`/opt/pprotein`）。

UI 参照: 計測ホストへ `ssh -L 9000:localhost:9000 <app>` → `http://localhost:9000`

---

## 8. 収集ターゲット（`data/targets.json`）

`pprotein/targets.example.json` を UI の Setting に貼る。IP は環境に合わせて書き換える。

```json
[
  { "Type": "pprof",   "Label": "app-fg", "URL": "http://127.0.0.1:19000/debug/fgprof",              "Duration": 60 },
  { "Type": "httplog", "Label": "app",    "URL": "http://127.0.0.1:19001/debug/log/httplog",        "Duration": 60 },
  { "Type": "slowlog", "Label": "db",     "URL": "http://<DB_PRIVATE_IP>:19000/debug/log/slowlog",   "Duration": 60 }
]
```

| 注意点 | 内容 |
|---|---|
| URL | **`127.0.0.1` を使う**（`localhost` → `[::1]` で connection refused） |
| pprof | **`/debug/pprof/profile` と `/debug/fgprof` を同時収集しない**（`cpu profiling already in use`） |
| Duration | 単位は**秒**（ミリ秒ではない） |
| Label | 複数台なら台ごとに変える |

### alp 設定（パス正規化）

```yaml
matching_groups:
  - ^/api/livestream/[0-9]+$
  - ^/api/livestream/[0-9]+/livecomment$
  - ^/api/livestream/[0-9]+/reaction$
  - ^/api/user/[^/]+$
```

### slp 設定

既定の `filters` だと `COMMIT` が落ちる。書き込みが重い問題では追加を検討:

```yaml
filters: Query matches "^(SELECT|INSERT|UPDATE|REPLACE|COMMIT) "
```

---

## 9. 動作確認

```sh
# ベンチを流しながら（これが重要）
curl -s 'http://127.0.0.1:19001/debug/log/httplog?seconds=5' | wc -l
curl -s 'http://<DB_IP>:19000/debug/log/slowlog?seconds=5' | wc -l
which alp slp dot            # pprotein ホスト上
```

---

## 10. 症状別の切り分け

| 症状 | 原因と対処 |
|---|---|
| **`received empty content`** | ベンチ中に収集していない（tail は収集開始後の増分のみ）。またはログに行が増えていない |
| httplog が空 | nginx が LTSV でない / `flush=1` なし / agent 未起動 / :19000 ではなく **:19001** を向ける |
| slowlog が空 | db に agent 未起動 / `long_query_time != 0` / app の DB アドレスが誤り |
| `cpu profiling already in use` | profile と fgprof の同時収集 → **fgprof のみ** |
| `connection refused` | standalone / agent 未起動、`ENABLE_PPROTEIN` 未設定 |
| `connection refused` ([::1]) | URL の `localhost` → `127.0.0.1` |
| 解析が `fail` | `alp` / `slp` / `dot` が PATH に無い |
| Commit が `[unknown]` | サーバに `.git` が無い（rsync デプロイ）。無視してよい |
| `/initialize` タイムアウト | collect を同期実行している / init が遅い（§6 参照） |

---

## 11. isucon-kit への組み込み

```sh
./install_tools.sh   # 初回のみ（pprotein + allow-remote）
./deploy.sh          # env / app / nginx / mysql など本体の反映
```

Git 管理するもの: `systemd/isupipe-go.service`, `systemd/pprotein*.service`, `env.sh`

| 既存 | pprotein 導入後 |
|---|---|
| `make nginx/rotate-log` / `make mysql/rotate-log` | 不要（走行ごとにスナップショット） |
| `make nginx/alp` | LTSV 前提に合わせる |
| `/analyze`（PR コメント） | 併存可（pprotein は走行比較、/analyze は PR 用） |

---

## 12. 終盤に外す

| 落とすもの | 用意しておく形 |
|---|---|
| standalone | `ENABLE_PPROTEIN != 1` で `Integrate` を呼ばない |
| 収集フック | `ENABLE_PPROTEIN` で `triggerPproteinCollect` を止める |
| agent / pprotein | systemd 化して `systemctl stop` |
| nginx ログ | `access_log off;` をコメントアウトで残す |

中盤に一度「計測 ON/OFF でスコアが何%変わるか」を測っておくと、終盤の判断が速い。

---

## 出典

- kaz/pprotein v1.2.4（`integration/`, `internal/collect/`, `internal/tail/`）
- https://hackmd.io/@to-hutohu/pprotein-getting-started
