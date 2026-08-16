---
description: リポジトリを解析してISUCONのスコア改善課題をGitHub Issue化し、まとめのDashboard Issueを作る
argument-hint: "[マニュアルのパス/URL] [絞り込み条件 (例: db only)] [--dry-run]"
allowed-tools: Bash, Read, Glob, Grep, Write, WebFetch, TaskCreate, TaskUpdate, TaskList
---

# ISUCON 改善課題の Issue 化

あなたは ISUCON の参加者です。**スコアを上げること**が唯一の目的です。
このリポジトリを解析し、スコア向上のために解決すべき課題を洗い出して、
**課題1つ = GitHub Issue 1つ**として作成し、それらを束ねる **Dashboard Issue** を作成してください。

**手順は必ずこの順で進める。マニュアル読解（§0）を飛ばしてコード解析に入ってはいけない。**
マニュアルを読まずに出した課題は、禁止された変更・整合性チェック違反・加点されない改善を含みやすく、当日そのまま事故になる。

追加指示（あれば優先して従う）: $ARGUMENTS

- 引数にパスや URL があれば、それを**マニュアルの場所**として扱う。
- `--dry-run` が渡された場合は Issue を作成せず、作成予定の内容を一覧で出力して終了する。
- **§0 のマニュアル読解は必須。省略する手段は無い。** マニュアルが手に入らない場合は Issue を作らず中断する。
- 絞り込み（例: `db only`）があれば、その領域を重点的に扱う。

## 0. マニュアル読解（最初に必ずやる）

**当日マニュアル**（競技のルール）と**アプリケーションマニュアル**（アプリの仕様）を先に読み切る。
ここで抽出した制約が、以降すべての Issue の判断基準になる。

### 0-1. マニュアルを探す

引数で場所が指定されていればそれを使う。指定が無ければ次を順に探す。

```sh
# リポジトリ内のマニュアル候補
ls -la
find . -maxdepth 3 -iname "*manual*" -o -iname "*regulation*" -o -iname "*rule*" \
  -o -iname "*spec*" -o -iname "*isucon*.md" | grep -v node_modules
ls -la docs/ manual/ 2>/dev/null
```

- リポジトリ内の `README.md` / `docs/**` / `*.md` / PDF / HTML
- URL が渡された場合は WebFetch で取得する（GitHub Wiki、配布ページなど）
- **どこにも見つからない場合は、勝手に一般論で進めない。**
  「当日マニュアルとアプリケーションマニュアルの場所（パス or URL）を教えてください」と伝えて**中断する**。
  マニュアル無しで Issue を作ることは**しない**。

### 0-2. 当日マニュアルから抽出する（ルール系）

読み飛ばさず、次の項目を**引用付きで**書き出す。1つでも不明なら「マニュアルに記載なし」と明記する。

- **スコア計算式** — 何が加点され、何が減点されるか。エンドポイントごとに重みが違うか
- **失格・再試行条件** — 整合性チェックの失敗、タイムアウト、エラー率の上限
- **変更禁止事項** — 触ってはいけないファイル・パス・ポート・レスポンス形式・外部サービス
- **追加してよいミドルウェア** — Redis / memcached / 別 DB の可否、インストール可否
- **サーバ構成** — 台数、スペック、どの台に何が載っているか、ネットワークの制約
- **ベンチマーカーの実行方法と挙動** — 並列度、実行時間、ポーリングするか、遅ければ待つか
- **再起動試験の条件** — 何を再起動され、どこまでの復旧が要求されるか
- **計測ツールの使用可否**、ログ出力に関する制約

### 0-3. アプリケーションマニュアルから抽出する（仕様系）

- **エンドポイント一覧**と、それぞれが返すべき内容・ステータスコード
- **整合性チェックの条件** — どのデータが、いつ、どの粒度で正しくなければならないか
- **キャッシュの可否と許容 stale** — 「N 秒古くてよい」「即時反映が必要」の線引き
- **画面ごとの表示要件**（並び順、件数、ページング、リアルタイム性）
- **ユーザー種別・権限**、認証方式（セッション、トークン）
- **外部 API・外部コマンド**への依存と、その制約（レート制限、置き換え可否）
- **初期データの規模**と、`/initialize` に要求される挙動・制限時間

### 0-4. 抽出結果をメモにする

作業メモを `/tmp/isucon-manual-notes.md` に書き出し、以降の Issue 作成で参照する。
このメモの要点は Dashboard Issue の「マニュアル要点」節にそのまま載せる。

### 0-5. マニュアルから直接導く判断

コード解析に入る前に、次を確定させる。

- **加点されないエンドポイント** — 速くしても意味がない。Issue にしない（または優先度を下げる）
- **キャッシュしてよいリソース / だめなリソース** — キャッシュ系 Issue はここに必ず紐づける
- **禁止されている変更** — 該当する改善案は**最初から候補から外す**
- **スコア計算式から見て最も割のいい領域** — 優先度付けの土台にする

**マニュアルの記述と矛盾する Issue は作らない。** 判断できない場合は Issue 本文に「マニュアル要確認」と書く。

## 1. 事前チェック

```sh
gh auth status
gh repo view --json nameWithOwner,url
gh issue list --state open --limit 100 --json number,title,labels
```

- `gh` が未認証なら、その旨をユーザーに伝えて中断する（勝手に認証を試みない）。
- 既存 Issue と**重複する課題は作らない**。既存 Issue で内容が薄いものは新規作成ではなくコメントで補足する方針を提案する。

## 2. リポジトリ解析（推測ではなく実物を読む）

以下を実際に読んで、**このリポジトリの現状**に基づいて課題を出す。存在しないものは無理に触れない。
読みながら、§0 で抽出した仕様（整合性チェックの条件、キャッシュ可否、加点対象）と**コードの実装を突き合わせる**。

- アプリケーション: `webapp/**`（Go/Node/Python/Ruby など言語ディレクトリ、ハンドラ、SQL 発行箇所、ORM、初期化処理 `/initialize`）
- スキーマ・初期データ: `**/*.sql`（テーブル定義、INDEX、型、外部キー、初期データ投入方法）
- DB 設定: `mysql/**`（`pull.sh` が `isucondb:/etc/mysql/` を落としてくる先）、`my.cnf`, `**/*.cnf`（`innodb_buffer_pool_size`, `innodb_flush_log_at_trx_commit`, `sync_binlog`, `max_connections`, スロークエリ設定）
- Web サーバ: `nginx/**`（`pull.sh` が `isuconapp:/etc/nginx/` を落としてくる先）（`worker_processes`, `worker_connections`, `keepalive`, `gzip`, 静的ファイル配信、`open_file_cache`, upstream 設定、ログフォーマット）
- ミドルウェア/OS: systemd unit, `sysctl`, `ulimit`, Redis/memcached の有無
- 運用スクリプト: `Makefile`, `deploy.sh`, `pull.sh`, `install_tools.sh`, `.github/workflows/**`
- 計測結果（あれば最重要の根拠）: `alp_analysis.txt`, `pt_query_digest_analysis.txt`, `mysqldumpslow_analysis.txt`, ベンチ結果ログ
- ドキュメント: `README.md`, マニュアル、`CLAUDE.md`

計測結果ファイルが存在する場合は、**必ずその数値を根拠として引用**する（例: `GET /api/isu/:id/graph` が sum 42.5s で全体の 38%）。
存在しない場合は「まず計測する」課題（`make nginx/alp` / `make mysql/pt-query-digest` の実行、`/analyze` コメント運用）を最優先 Issue として立てる。

## 3. 課題の洗い出し観点（チェックリスト）

網羅的に検討し、**このリポジトリで実際に該当し、かつマニュアルで禁止されていないものだけ**を Issue にする。

### アプリケーションコード
- N+1 クエリ（ループ内クエリ、関連取得の逐次実行）→ JOIN / IN 一括取得 / アプリ側 JOIN
- 不要なクエリ・全件取得（`SELECT *`、LIMIT 無し、COUNT の多用）
- 同一リクエスト内・リクエスト間の重複計算 → メモリキャッシュ / sync.Once / TTL キャッシュ
- 重い処理の同期実行 → 非同期化・バッチ化・遅延書き込み（bulk insert、キュー）
- ループ内 INSERT/UPDATE → バルク化、トランザクションまとめ
- パスワードハッシュ・画像変換などの CPU 重処理 → コスト調整・キャッシュ・事前生成
- 画像/ファイルを DB から配信 → 静的ファイル化して nginx 配信 or キャッシュ
- DB コネクションプール設定（`SetMaxOpenConns` / `SetMaxIdleConns` / `SetConnMaxLifetime`）
- JSON エンコード・ログ出力・デバッグログのオーバーヘッド
- ロック競合・排他制御の粒度、無駄な `sleep` / リトライ
- `/initialize` の初期化コストと整合性（キャッシュのクリア漏れは失格リスク）

### DB
- 欠落 INDEX（WHERE / ORDER BY / JOIN キー、複合 INDEX の順序、カバリング INDEX）
- 効いていない INDEX（関数適用、型不一致、前方一致でない LIKE）
- テーブル設計（非正規化、集計カラムの持ち回り、不要カラムの分離、型の縮小）
- スロークエリ上位の個別チューニング（`EXPLAIN` 結果を根拠にする）
- MySQL パラメータ（buffer pool、`innodb_flush_log_at_trx_commit=0/2`、`sync_binlog=0`、binlog 無効化）
- トランザクション分離レベル・不要トランザクション
- DB を別ホストへ分離 / 逆に同一ホストへ集約（構成に応じて）
- Redis 等への移し替え（セッション、カウンタ、ランキング）

### インフラ / ミドルウェア
- nginx: `keepalive`（upstream 含む）、`worker_processes auto`、`worker_connections`、`gzip`/`gzip_static`、`sendfile`、静的配信、`open_file_cache`、`proxy_buffering`
- 静的ファイル・API レスポンスのキャッシュ（`expires`、`Cache-Control`、`proxy_cache`）
- ベンチ中の**ログ出力停止**（nginx access_log off / MySQL slow log off）※計測時は逆に有効化
- 複数台構成の役割分担（app / db / 内部 API の振り分け、nginx でのロードバランス）
- systemd の制限（`LimitNOFILE`）、`sysctl`（`somaxconn`, `tcp_tw_reuse`）、ファイルディスクリプタ
- unix domain socket 化（nginx ↔ app、app ↔ MySQL）
- 不要プロセスの停止、メモリ・CPU 使用状況の確認

### 計測・運用（スコアを上げるための土台）
- alp / pt-query-digest / スロークエリの計測フロー整備とログローテート
- ベンチ実行 → 計測 → 修正のサイクル短縮（`make` ターゲット、`deploy.sh`、CI）
- ベンチ本番時に計測を切る/戻す手順の明文化
- pprof / メトリクスの導入

## 4. ラベル整備

カテゴリ分けはラベルで表現する。冪等に作成する（既存ならエラーを無視）。

```sh
gh label create "category:app"     --color 1D76DB --description "アプリケーションコード" --force
gh label create "category:db"      --color 0E8A16 --description "DB・スキーマ・クエリ"   --force
gh label create "category:infra"   --color 5319E7 --description "nginx/OS/ミドルウェア"  --force
gh label create "category:measure" --color FBCA04 --description "計測・運用"             --force
gh label create "priority:high"    --color B60205 --description "効果大 / 優先度高"      --force
gh label create "priority:mid"     --color D93F0B --description "効果中"                 --force
gh label create "priority:low"     --color FEF2C0 --description "効果小 / 余力があれば"  --force
gh label create "dashboard"        --color 000000 --description "まとめ Issue"           --force
```

## 5. 個別 Issue の作成

**1 Issue = 1 つの独立して着手・レビューできる変更**にする。粒度が大きいものは分割する。

- タイトル: `[カテゴリ] 動詞から始まる具体的な内容`
  - 例: `[DB] isu_condition テーブルに (jia_isu_uuid, timestamp) の複合INDEXを追加する`
  - 例: `[App] GET /api/isu 一覧取得のN+1クエリを一括取得に置き換える`
- 本文は以下のテンプレートに従う（**日本語**、`--body-file` で渡す）:

```md
## 現状 / 課題
（コードや設定の該当箇所を `path/to/file.go:123` 形式で示す）

## 根拠
（alp / pt-query-digest / EXPLAIN の数値。無ければ「未計測・要計測」と明記）

## マニュアル上の根拠・制約
（§0 で抽出した記述を引用する。次を必ず埋める）
- 加点対象か: （スコア計算式のどこに効くか / 加点されないなら理由）
- 整合性チェック: （このエンドポイント/データに要求される正しさ）
- キャッシュ可否: （可 / 不可 / N秒までの stale 許容。キャッシュを含まない変更なら「該当なし」）
- 禁止事項に触れないか: （変更禁止範囲・レスポンス形式・追加ミドルウェアの可否）
- 判断できない点があれば「マニュアル要確認」と明記

## 対応方針
（具体的な変更内容。必要なら差分イメージやSQLを書く）

## 期待効果
（どのエンドポイント / クエリがどれだけ軽くなるか。スコアへの寄与の見立て）

## リスク・注意点
（整合性、/initialize、複数台構成、失格条件に触れないか）

## 検証方法
（ベンチ再実行、alp の該当行、EXPLAIN 再確認など）

## 影響ファイル
| ファイル | 変更種別 | 変更内容 |
| --- | --- | --- |
| `webapp/go/main.go:412-438` | 修正 | `getIsuList` のループ内クエリを IN 句の一括取得に置換 |
| `webapp/sql/1_InitData.sql` | 修正 | 複合INDEXを追加 |
| `webapp/go/cache.go` | 新規 | TTLキャッシュの実装 |
| `nginx/nginx.conf` | 設定 | upstream に keepalive を追加 |
| `Makefile` | 設定 | 計測用ターゲットを追加 |

### 再起動・反映が必要なもの
（`make app/build` + `make app/restart` / `make mysql/restart` / `make nginx/restart` / SQL の再投入 / `/initialize` への影響）

### 他Issueとの競合
（同じファイルを触る Issue があれば `#12 と webapp/go/main.go で競合` のように明記。無ければ「なし」）

<!-- generated-by: /summarize-issues -->
```

- 本文末尾の `<!-- generated-by: /summarize-issues -->` は**必ず入れる**。後続コマンド（`/parallel-plan`）がこのマーカーで対象 Issue を絞り込むため、省略しない。

### 影響ファイルの書き方（必須ルール）

- **推測でパスを書かない。** 表に載せるパスは Glob / Grep / Read で**実在を確認したものだけ**にする。
- 行番号は実際に読んだ結果を書く。範囲がある場合は `path:412-438`、関数単位なら `path:412 (getIsuList)` のように関数名を添える。
- 変更種別は `修正` / `新規` / `削除` / `設定` のいずれか。`新規` はまだ存在しないファイルなので実在確認の対象外だが、置き場所が既存のディレクトリ構成に沿っていることを確認する。
- 1つの変更が複数レイヤに波及する場合（例: スキーマ変更 → アプリのクエリ修正 → 初期化SQL）、**波及先も漏らさず表に含める**。
- 表の1行1行が「そのファイルで何をするか」まで書けていること。ファイル名だけの列挙は不可。
- `webapp/**` などがまだ pull されていない場合は、表に `（未pull・要確認）` と明記し、確認手順（`sh ./pull.sh`）を書く。

- ラベル: `category:*` を必ず 1 つ、`priority:*` を必ず 1 つ付与。
- 優先度は **(期待効果 ÷ 実装コスト)** で決める。計測で上位に来ているものを high にする。
  ただし**マニュアル上加点されないエンドポイント**は、計測上位でも high にしない（理由を本文に書く）。
- 作成コマンド例（本文は一時ファイル経由）:

```sh
gh issue create --title "..." --body-file /tmp/isucon-issue-01.md \
  --label "category:db" --label "priority:high"
```

- 作成した Issue 番号・タイトル・カテゴリ・優先度を必ず記録しておく（Dashboard で使う）。

## 6. Dashboard Issue の作成

個別 Issue を**すべて作成した後**に、まとめ Issue を 1 つ作る。

- タイトル: `[Dashboard] ISUCON 改善タスク一覧`
- ラベル: `dashboard`
- 本文構成:

```md
## 概要
（アプリの構成・ベンチ観点のボトルネック要約を3〜5行）

## マニュアル要点（判断の前提）
| 項目 | 内容 | 出典 |
| --- | --- | --- |
| スコア計算式 | | 当日マニュアル ○○節 |
| 加点されない/重みの低いエンドポイント | | |
| 整合性チェックの条件 | | アプリケーションマニュアル ○○節 |
| キャッシュ可否・許容 stale | | |
| 変更禁止事項 | | |
| 追加してよいミドルウェア | | |
| サーバ構成・台数 | | |
| 再起動試験の条件 | | |
| ベンチの挙動（待つ/ポーリング） | | |

**この表と矛盾する改善は入れない。** 不明な項目は「マニュアル要確認」と書き、当日ここを埋めてから着手する。

## 計測状況
（alp / pt-query-digest の有無と、上位ボトルネックの要約表）

## 優先度順おすすめ着手順
1. #12 （理由: 効果大・変更小）
2. #15
...

## アプリケーションコード
- [ ] #12 タイトル — `priority:high`
- [ ] #13 タイトル — `priority:mid`

## DB
- [ ] #14 ...

## インフラ
- [ ] #16 ...

## 計測・運用
- [ ] #11 ...

## 影響ファイル一覧（競合チェック用）
| ファイル | 触る Issue |
| --- | --- |
| `webapp/go/main.go` | #12, #13 |
| `webapp/sql/1_InitData.sql` | #14 |
| `etc/nginx/nginx.conf` | #16 |

同じファイルを複数 Issue が触る場合は、並行作業でコンフリクトするため着手順を決める。

## 進め方のルール
- **着手前にマニュアル要点の表を各自が読む。** 仕様の見落としは後で必ず時間を溶かす
- 1 Issue = 1 PR。**`main` への push（＝PRマージ）で自動デプロイされる**（`.github/workflows/cd.yaml` は `push: branches: [main]` トリガー）。PR を作っただけでは反映されない
- Go の場合バイナリは**ローカルで `make app/build` してコミットする**（`deploy.sh` はビルドせず rsync するだけ）
- 変更後は必ずベンチを回し、**PR に** `/analyze` をコメントして再計測する（`analyze.yaml` は PR コメントのみ反応。Issue へのコメントでは動かない）
- 計測用ログはベンチ本番前に停止する
- 並行作業の進め方は `/parallel-plan` で可視化する

<!-- generated-by: /summarize-issues (dashboard) -->
```

- 「影響ファイル一覧」は各 Issue の影響ファイル表を集計して作る。**2つ以上の Issue が触るファイルは太字**にして目立たせる。

- カテゴリ内は優先度順に並べる。
- 作成後、Dashboard Issue の URL をユーザーに提示する。

## 7. 最終報告

- **読んだマニュアルのパス/URL** と、抽出できなかった項目
- マニュアルを根拠に**候補から外した改善案**（例: 「Redis 追加は禁止のためセッション移設は不可」）
- マニュアルを根拠に**優先度を下げた項目**（加点されないエンドポイントなど）
- 作成した Issue 数（カテゴリ別）と Dashboard Issue の URL
- 特に効果が大きいと判断した上位3件とその理由
- 情報不足で Issue にできなかった項目（例: ベンチ結果が無く判断不能なもの）と、それを埋めるために必要なもの

## 禁止事項

- **マニュアルを読まずに Issue を作らない**（見つからない場合は場所を聞いて中断する。例外は無い）
- **マニュアルで禁止されている変更を Issue にしない**
- マニュアルに書いていないことを「書いてある」ように引用しない。不明は「マニュアル要確認」と書く
- アプリケーションコードや設定ファイルを**修正しない**（このコマンドは課題の洗い出しと Issue 化のみ）
- 実物を読まずに一般論だけの Issue を作らない。該当箇所が示せない課題は Issue にしない
- 既存 Issue の重複を作らない
- Issue の一括クローズや既存 Issue の破壊的編集をしない
