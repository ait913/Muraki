---
title: drift を iOS の 2 つの FlutterEngine (main + headless bg) から同一 DB で使う
category: library
project: bloom
tags: [drift, sqlite, flutter, ios, isolate, background-engine, wal, busy_timeout, sqlite_busy]
created: 2026-10-09
sources:
  - https://drift.simonbinder.eu/isolates/
  - https://drift.simonbinder.eu/platforms/vm
  - https://pub.dev/documentation/drift/2.34.3/isolate/DriftIsolate/DriftIsolate.fromConnectPort.html
  - https://api.flutter.dev/flutter/dart-ui/IsolateNameServer-class.html
  - https://github.com/flutter/flutter/issues/154918
  - https://berthub.eu/articles/posts/a-brief-post-on-sqlite3-database-locked-despite-timeout
  - drift-2.34.3/lib/native.dart (実読み)
  - sqlite3-3.5.2/lib/src/database.dart (実読み)
model-era: opus-4.8
---

## Context

iOS アプリが main engine (UI) と headless の第 2 FlutterEngine (位置/background_downloader で
起動) を持ち、両方が `NativeDatabase.createInBackground` で同じ sqlite ファイルを別コネクションで
開くと、busy_timeout=0・WAL 未設定だと書き込み競合で `SQLITE_BUSY` → drift isolate 例外 →
メインに `DriftRemoteException` (FATAL) が出る。drift 2.34.3 / sqlite3 3.5.2 で確認。

## What

- **別 FlutterEngine 間で drift の単一 DriftIsolate を共有することはできない (iOS)。** drift 公式
  isolates ページが明言: 「`shareAcrossIsolates` only discovers databases inside the same
  Flutter engine. Independent engines still cannot share one `DriftIsolate` this way.」
- 共有の土台になる `IsolateNameServer` は C++ 側で per-instance の map
  (`std::map<std::string, Dart_PortEx> port_mapping_`、static でない) を持ち、
  `UIDartState::Current()->GetIsolateNameServer()` で引く。直接生成した `FlutterEngine`
  (FlutterEngineGroup 経由でない) は別 Shell = 別レジストリで、**iOS では engine またぎの
  `registerPortWithName`/`lookupPortByName` が機能しない** (flutter/flutter#154918:
  Android では動くが iOS では動かない)。SendPort は MethodChannel の標準メッセージ型でも
  ないので native 経由で手渡すこともできない。→ **「DB を 1 本の isolate がホストして両エンジンが
  接続」案は iOS の 2 独立エンジンでは成立しない。**
- drift は「別 Flutter エンジン (workmanager が spawn する類) をまたぐ isolate は複雑な
  オブジェクトを送れない」ケースを `DriftIsolate.fromConnectPort` の `serialize` フラグで
  想定している。ただしこれは connect SendPort を相手に渡す手段が別途ある前提の話で、
  iOS の独立エンジン間にはその手段がない (上記)。
- **正攻法 = 各エンジンが独立コネクションを開いたまま WAL + busy_timeout で待ち合わせる。**
  drift native/VM ページ: 「Efficiently using multiple isolates requires the use of」WAL。
  「Not using WAL will cause "database is locked" errors when multiple isolates access the
  same database.」WAL は 1 writer + N reader を並行させる。
- **drift 2.34.3 の API 現存確認 (lib/native.dart 実読み):**
  - `typedef DatabaseSetup = void Function(Database database);` (`Database` は package:sqlite3)。
  - `NativeDatabase.createInBackground(File file, {..., DatabaseSetup? setup, IsolateSetup? isolateSetup, int readPool = 0, ...})` — **`setup` を受け取れる**。
  - `NativeDatabase(File file, {..., DatabaseSetup? setup, ...})` — こちらも `setup` あり。両者の違いは
    createInBackground が DB をバックグラウンド isolate に立てて I/O をメインスレッドから外すこと。
  - doc comment が明記: 「the functions [setup], [isolateSetup] and [sqlite3], are sent to
    other isolates and are executed there.」= **setup コールバックは DB を走らせる worker
    isolate 側で呼ばれる** (createInBackground の場合、背景 isolate 側)。キャプチャする状態に注意。
  - readPool は WAL 有効時のみ効く。
- `setup` の中の `Database` (sqlite3 3.5.2) は `void execute(String sql, [params])` を持つ。
  **`busyTimeout` プロパティは sqlite3 3.5.2 に無い** → busy_timeout は pragma で設定する。
- busy_timeout は **コネクション単位 (connection-local)**。DB ファイル単位でなく、開く各コネクションの
  setup で毎回設定する必要がある。WAL は DB ファイルの永続属性なので一度設定すれば残るが、
  両コネクションの setup で冪等に設定して構わない。
- **WAL + busy_timeout でも残る SQLITE_BUSY:** WAL では「読み取りトランザクション開始後に別
  コネクションが書き込んでいると、こちらの commit が `SQLITE_BUSY_SNAPSHOT` で即失敗」し、
  busy_timeout はこれをリトライしない (berthub)。対策は書き込みを `BEGIN IMMEDIATE` で始める・
  書き込みトランザクションを短く保つ・アプリ層でリトライ。

## Why

- iOS の第 2 FlutterEngine は別 Shell で isolate レジストリが分離されるため、Android で動く
  IsolateNameServer ベースの共有が iOS では破綻する。engine 間を安全に渡せるのは native の
  共有ストレージ (ファイル / App Group UserDefaults / DB ファイル自体) だけ。
- よって「同一ファイルを 2 コネクションで開き、SQLite の WAL ロック機構に調停させる」のが
  drift が公式に推奨する複数 isolate パターンそのもの。

## How to apply

- `BloomDb.open` の `createInBackground` に setup を渡し、両エンジンから同じ設定で開く:
  ```dart
  NativeDatabase.createInBackground(
    File(...),
    setup: (db) {
      db.execute('pragma journal_mode = WAL;');
      db.execute('pragma busy_timeout = 5000;'); // 任意 ms。コネクション毎に必須
    },
  )
  ```
  setup は背景 worker isolate 側で実行される点に注意 (外側のクロージャ状態を掴まない)。
- WAL + busy_timeout は reader/writer 重なりを解消するが 2 writer を並行化はしない (SQLite は
  write を直列化)。起動時 migration (bloom の schema 4->5: createTable + INSERT...SELECT + DROP の
  write トランザクション) と backfill の unawaited write が bg の presence/footprints write と
  競合する窓が残る → 書き込みは短く、必要ならアプリ層リトライか BEGIN IMMEDIATE を検討。
- 代替案 (低結合): bg エンジンは drift を開かず native バッファ (bloom は既に
  pending_events.jsonl を持つ) に貯め、前景復帰で main engine が drift に取り込む。drift の
  同時書き込み面を 1 本に減らせる。どちらを採るかは設計判断。
