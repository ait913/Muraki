---
title: オンプレ aiserver2 (富士通 ESPRIMO D552/K, JIH81Y2) のビープ解釈と CMOS 電池交換の罠
category: gotcha
tags: [onprem, aiserver, fujitsu, esprimo-d552, bios, beep, cmos, memory, cpu]
created: 2026-10-19
project: global
sources:
  - http://www.fmworld.net/biz/fmv/support/fmvmanual/pdf/B5FK/B5FK5061.pdf
  - https://azby.fmworld.net/app/customer/driversearch/pc/drvdownload?driverNumber=E1019140
  - sessions/2026-10-18-f65683e6.md
---

## Context

2026-10-18〜19 に aiserver2 (192.168.3.17、Coolify ホスト) のメモリ増設 (2+8 GB → 8+8 GB) と CPU 交換 (Celeron G1840 → Core i3-4170) を実施。CPU 交換後に起動せず、ビープの解釈を誤って遠回りした。

機体の素性 (dmidecode):

| 項目 | 値 |
|---|---|
| 型名 | FMVD1300K = ESPRIMO D552/K |
| マザー | FUJITSU JIH81Y2 (= JIB85Y)、H81、LGA1150 |
| BIOS | 4.08 (2015-03-05)。公式最新は 4.15 (Spectre マイクロコード、CPU 対応追加は全版なし) |
| メモリ | DDR3 2 スロット、最大 16 GB (到達済)。Crucial CT102464BA160B × 2、i3 で 1600 MT/s |
| 起動モード | UEFI (`/sys/firmware/efi` あり) |

## What

- **ビープは全部エラー音**。製品ガイド 7.2.2 に正常時のビープは無い。「1 回 = 正常」は一般論で、この機種には当てはまらない
- **4 回 (ピッ×4) = メモリ未検出**。メモリ無し / DIMM3 (スロット 3) 単独 で鳴る。**1 枚挿しはスロット 1 のみ対応** (製品ガイド 3.3.2 の対応表)。DIMM3 単独の 4 回は「チャネル死亡」ではなく非対応構成の拒否
- **DVD ドライブにアクセスした後の 1 回 = 起動デバイスが見つからない** (`Bootable Device was not found`)。POST は通っている。画面が出ていればメッセージと Enter → BIOS セットアップ誘導が表示されている
- **CMOS 電池を交換すると BIOS 設定が初期化**され、セキュアブート「使用する」/ CSM「使用しない」/ 起動順位リセットになり、Ubuntu の UEFI エントリを見失って上記 1 回ビープになる。復旧は F2 押しっぱなしで電源 ON → 起動順位で SSD を選ぶ
- **BIOS / FUJITSU ロゴの表示先** (2026-10-28 実測): **DVI-D→HDMI 変換先の HDMI モニタには firmware 段では出ない** (単独接続でも不可。OS 起動後は i915 が交渉し直すので映る)。EDID を返すモニタを D-Sub 直結すれば BIOS もロゴも出る。DDC 線の無い D-Sub ケーブルは「モニタ無し」扱い (Linux から EDID 0 バイト)。保守は**古いモニタ + D-Sub 直結**、マニュアル指定どおり「モニタの電源を PC より先に入れる」
- **ssh から BIOS に落とす**: `sudo systemctl reboot --firmware-setup`。firmware は `OsIndicationsSupported` ビット 0 対応 (実測 `01`)、Windows の Shift+再起動と同じ UEFI 変数経路。F2 のタイミングもロゴも不要。終了すれば Ubuntu が通常起動 (フラグは 1 回で消費)。GRUB にも「UEFI Firmware Settings」エントリあるが GRUB_TIMEOUT=0 なので実用性低
- i3-4170 は G1840 / i3-4160 と同じ CPUID (06_3C stepping 3) で、出荷 BIOS 4.06 の時点で対応。BIOS 更新不要で動いた
- BIOS 更新は Windows 専用ツール (System Update Tool + Fujitsu BIOS Driver)。Ubuntu からは当てられない。D586 系の「ジャンパ + USB 復旧」は欧州 FTS 板の手順で D552 には無い
- カバー開放検知は無い。ケースを開けたままでも起動する

## Why

Haswell はメモリコントローラも iGPU 出力も CPU 内蔵なので、CPU 着脱直後の不調は何でも「メモリエラー」に見える。そこに CMOS 電池交換 (= 設定リセット) が重なり、「CPU が悪い」「ソケットのピンが曲がった」と原因を誤推定した。決め手は「ビープが鳴るタイミング」(DVD アクセス後 = POST 通過後) だった。

## How to apply

- 作業前に `sudo dmidecode -s bios-version; ls /sys/firmware/efi` と BIOS の起動順位をメモしておく
- CMOS 電池を交換したら「BIOS 設定が全部飛んだ」前提で、起動後に F2 でセキュアブート / CSM / 起動順位を確認する
- ビープの切り分けは「回数」より「**どの段階で鳴るか**」(ファン回転直後 / ドライブアクセス後) を先に聞く
- 切り分けの 1 枚挿しは必ず DIMM1 (スロット 1) で行う
- 作業中はモニタ + USB キーボードを背面に繋ぎ、モニタを先に ON にしておく
- 停止/起動の遠隔手順: LAN なら `ssh ais@192.168.3.17 -p 51000 'sudo -n shutdown -h now'`。起動後 1 分で ssh 可、44 コンテナと cloudflared は自動復帰する
