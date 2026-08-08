---
title: macOS のディスプレイスリープ中は headless Chrome の captureScreenshot が全滅する
category: gotcha
project: global
tags: [chrome, headless, screenshot, captureScreenshot, display-sleep, caffeinate, chrome-devtools-mcp, cdp]
created: 2026-08-08
sources:
  - omatase LP スクショ撮影で実踏 (2026-08-08)。pmset -g log の Display off 時刻とスクショ失敗開始時刻が一致
model-era: fable-5
---

## Context

chrome-devtools MCP (または CDP 直叩き) の headless Chrome でスクショを撮っている最中に、突然すべての `Page.captureScreenshot` が `timed out` になった。JS 評価・ナビゲーション・ネットワークは全部正常。ページ固有の問題に見えるが、**example.com ですら撮れない**。

## What

- **Mac のディスプレイが眠ると、headless Chrome を含む全 Chrome インスタンスでフレーム生成が止まり、`Page.captureScreenshot` が返らなくなる** (180 秒待っても返らない)
- 新しいタブ・新しい Chrome プロセスを起動しても直らない。GPU プロセス kill も無効
- 症状の見分け方: `Runtime.evaluate` は正常 / CPU は全プロセス静止 / `requestAnimationFrame` が発火しない (ただし headless のオンデマンド描画では rAF 停止自体は正常なので、これ単体では確定しない)
- **確定手順: `pmset -g log | grep "Display is turned"` の off 時刻と失敗開始時刻を突合**。`system_profiler SPDisplaysDataType | grep "Display Asleep"` が Yes なら黒
- 紛らわしい点: `pmset -g` は「displaysleep prevented by Google Chrome for Testing」を表示するが、**既に眠っているディスプレイを起こす効力はない** (アサーションは今後のスリープを防ぐだけ)

## Why

headless=new でも macOS では WindowServer / GPU 側の frame 供給に依存しており、ディスプレイスリープで GPU がパークすると compositor が BeginFrame を出せなくなる。captureScreenshot は新規フレームの合成を待つため、永久に返らない。

## How to apply

撮影セッションの前に display-wake を確保する:

```sh
# 即座に起こす + 30 分維持 (撮影中は生かしておく)
nohup caffeinate -d -u -t 1800 > /dev/null 2>&1 &
```

- `-u` がユーザーアクティビティ模擬 (眠っているディスプレイを**起こす**)、`-d` が維持
- 起きたことの確認: `pmset -g log | grep "Display is turned" | tail -1` が on になる。直後に captureScreenshot が即復活する (実測: 点灯 10 秒後に成功)
- スクショを長時間セッションでやるなら**最初に caffeinate を張るのを標準手順にする**。途中で眠られると「さっきまで撮れていたのに」型の混乱に落ちる (同症状の別原因: [[gotcha/headless-screenshot-backdrop-filter-timeout]] — こちらはページ固有・display は無関係)

## 関連

- [[gotcha/headless-screenshot-backdrop-filter-timeout]] — 同じ `captureScreenshot timed out` でも、backdrop-filter 起因はページ固有 (軽いページは撮れる)。**example.com も撮れないなら本 gotcha を疑う**
- [[tool-quirk/chrome-for-testing]] — CDP 直叩きの手順 (MCP の protocolTimeout を回避したいとき)
