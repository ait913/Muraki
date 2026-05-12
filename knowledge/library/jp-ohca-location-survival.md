---
title: 日本のOHCA場所別生存率と現着時間の真実 (JAMA 2019・東京令和5年・全国Utstein 2018)
category: library
tags: [emergency, japan, OHCA, statistics, location, survival, AED, bystander-CPR]
created: 2026-05-10
project: global
sources:
  - https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2729470
  - https://www.tfd.metro.tokyo.lg.jp/content/000071938.pdf
  - https://www.jstage.jst.go.jp/article/jsem/25/5/25_827/_article/-char/ja/
  - https://pubmed.ncbi.nlm.nih.gov/30654927/
  - https://pmc.ncbi.nlm.nih.gov/articles/PMC8591414/
---

## Context
救急関連プロダクトで「平均14分」「20分以上ロングテール」の上位の話を求めるとき。OHCAの生存率は **発生場所で18倍違う**。EMS現着時間自体の場所差は1分しかない。設計判断を誤らないために必読。

## What

### 場所別の生存率は最大18倍 (東京令和5年・心停止13,444人)
- 住宅 (専用・共同): 2.6% ← 全心停止の68.9%が発生
- 一般道路: 10.2%
- 駅: 25.6%
- 会社・オフィス: 25.2%
- スポーツ・運動施設: 46.4%
- 特養老人ホーム: 1.3%

出典: 東京消防庁 図表3-15 (https://www.tfd.metro.tokyo.lg.jp/content/000071938.pdf)

### 場所別 EMS現着時間の差はわずか1分 (JAMA 2019・全国233,511例)
| 場所 | 現着中央値 | bystander CPR率 | AED使用率 | 初期VF率 | 1ヶ月生存率 | CPC1-2率 |
|---|---:|---:|---:|---:|---:|---:|
| 住宅 | 9分 | 45.2% | 0.1% | 4.8% | 2.8% | 1.0% |
| 公共 | 8分 | 49.6% | 4.0% | 21.3% | 7.9% | 4.5% |
| 介護施設 | 9分 | 79.0% | 2.9% | 4.8% | 2.6% | 0.6% |

調整OR (住宅基準): 公共1.36、介護施設0.62

出典: JAMA Network Open 2019 (https://jamanetwork.com/journals/jamanetworkopen/fullarticle/2729470)

### 真の決定要因 = bystander介入の場所差
- AED使用率: 公共4.0% vs 住宅0.1% = **40倍差** (全国・JAMA)
- AED使用率: 駅44.4%・運動施設46.4% vs 住宅8.3% = **5-6倍差** (東京TFD)
- 初期VF率: 公共21.3% vs 住宅4.8% = 4倍差 → AEDが効く症例の絶対数も場所で違う

### 現着時間1分の差 = 救命確率0.15倍 (J-STAGE 2018, 全国Utstein 218,699例)
- 多重ロジスティック回帰: 覚知→接触1分延長 → オッズ比 0.150 (95%CI 0.042-0.533, p=0.003)
- BS-CPR率1%上昇 → オッズ比 1.194 (95%CI 1.000-1.425, p=0.050)
- 決定木カットオフ: 覚知→接触8.95分・BS-CPR率51.05%

出典: J-STAGE jsem 25(5):827 (https://www.jstage.jst.go.jp/article/jsem/25/5/25_827/_article/-char/ja/)

### 自宅OHCAの戸建vs共同住宅 (Resuscitation 2019, 212,722例 3年分)
- 自宅発生 = 全OHCAの **65.0%**
- 戸建て: 186,219件 (88%) / 共同住宅: 26,503件 (12%)
- bystander CPR率: 27.9-47.1% (場所により広く変動)
- AED使用率: 0.0-0.2%
- 1ヶ月CPC1-2: 0.3-2.3%
- ★ フルテキスト未取得のため戸建vs共同住宅の個別中央値・調整ORは不明 (有料論文)

出典: PubMed 30654927 (https://pubmed.ncbi.nlm.nih.gov/30654927/)

## Why
日本の救急救命プロダクト設計で「平均14分」「現着遅い」を訴求すると的を外す。生存率の決定要因は **「現着前7-9分のbystander介入」**であり、これは場所 (=bystander密度) とAED近接性で40倍の差がつく。EMS現着時間の場所差は1分以内 = 介入差の方が桁違いに大きい。

ユーザー仮説「平均14分は二極化平均」の検証では:
- 二極化はある (公共25-46% vs 自宅2.6%) が、それは**生存率の二極化**
- **EMS到着時間の二極化ではない** (中央値も平均値もほぼ同じ ≈ 14分)
- 東京現着分布: 5分以下 0.5% / 10-20分 60.7% / 20分以上 16% = 太い山+右ロングテール

## How to apply

- 訴求コピーは「自宅で倒れたら生存率2.6%、公共46%」を主軸 (現着時間ではなく生存率の場所差)
- アプリ機能優先: bystander誘導 > AED位置 > 現着予測 (現着予測は意外に役立たない、場所差1分)
- 「鍵で入れない」シナリオは絶対数の根拠データなし → 訴求主軸にせず補強材料に
- 介護施設は bystander CPR率79%もあるのに生存率2.6%と最低 → CPR質と早期通報が課題
- Drennan 2016 (カナダ・高層階生存率5倍差) の日本版は未確認、引用するなら海外データと明記
