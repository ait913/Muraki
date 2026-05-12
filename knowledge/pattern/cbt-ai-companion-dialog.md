---
title: CBT 系 AI コンパニオン対話の設計パターン (System prompt + 安全境界)
category: pattern
tags: [llm, mental-health, cbt, system-prompt, safety, claude]
created: 2026-05-11
project: global
sources:
  - https://woebothealth.com/clinical-results/
  - https://www.wysa.com/digital-therapeutics
  - https://www.apa.org/monitor/2023/07/ai-mental-health-apps
  - https://www.who.int/publications/i/item/9789240029200
---

## Context
メンタルウェルネス / 生活リズム改善 / AI 秘書系アプリで、LLM (Claude Haiku 4.5 等) を「相談相手」として配置する場面。Woebot / Wysa / Earkick / Replika / Pi / Rosebud / Mindsera の 2025-2026 時点の設計を整理した。コーチではなく「伴走者 (Companion)」を目指す場合の指針。

## What

### 役割定義の定石
- **Companion 型** (Woebot): 診断しない・ソクラテス式質問で気づきを引き出す
- **Validation 重視型** (Wysa): 全リソースの ~40% を感情の検証 (Validation) に投下
- **Mirror 型** (Pi / Inflection): ユーザーの発話を要約して返す Reflective Listening

### 対話ターンの 4 段階 (Reframing Loop)
1. **Open Question**: 「今、何が起きてる?」
2. **Validate**: 「それは〜という状況で、〜と感じるのは自然」
3. **Inquire / Reframe**: 「別の角度から見ると?」 (自動思考の特定 → 再構成)
4. **Action / Commitment**: 「次にその感情が来たら、1 分でできることは?」

### 押し付け禁止 (Advice-Pushing の排除)
- Bad: 「散歩に行くといいですよ」
- Good: 「以前気分が晴れたと言っていた活動、覚えてる?」
- 「〜すべき (should)」を避ける。CBT-i の基本でもある。

### 安全境界 (危険発言検知 → エスカレーション)
- 二層構え: (a) キーワード / セマンティック検出 (b) LLM 文脈判断
- 検知瞬間に **LLM 生成を停止し、ハードコードの crisis card** を出す。LLM に判断を委ねない
- AI 過剰共感の事故例: Replika (恋愛依存 → サービス変更で精神被害), Character.ai 訴訟
- 対策: 「私は AI で、人間ではない」境界を会話に自然に織り込むプロンプト

### セッション長の研究値
- ウェルネス対話の sweet spot: **1 回 5-10 分 / 8-12 ターン**
- それ以上は **Rumination (反芻思考) のリスク** が上がる
- システム側から「今日はこのくらいに」とクローズする責任を持つ
- 朝の対話 (睡眠慣性下) は **1-3 ターン限界**。夜の振り返りは **3-5 ターン** が満足度ピーク (NNG 知見)

## Why
- LLM の最大リスクは hallucination ではなく **不適切な共感** (依存形成 + 危機介入失敗)
- CBT は「自分で気づく」プロセスが治療効果の本体。AI が解を出すと逆効果
- ターン数を絞るのは UX 上の理由だけでなく、反芻による悪化を防ぐため

## How to apply
System prompt の骨子:

```
# Role
あなたは CBT 技法に基づくメンタルウェルネス・コンパニオン。
ユーザーの安全を最優先し、温かく専門的な境界線を維持。

# Constraints
1. 診断・医療助言は絶対にしない
2. 解決策の前に必ず Validation を入れる
3. 1 回の返答は最大 3 文
4. 自殺/自傷の兆候を検知したら [CRISIS_HANDOFF] を起動

# Conversational Flow (CBT)
- Phase 1: 感情のラベリング
- Phase 2: 自動思考の特定
- Phase 3: 適応的思考への誘導
- Phase 4: スモールステップの提案

# Tone
- 穏やか・非審判的・エンパワリング
- 「〜すべき」ではなく「〜という選択肢もある」
```

実装上のチェック:
- crisis 検知は LLM 任せにせず、別パス (regex + 補助分類器) を併設
- セッション終了をシステム側から提案する仕組みを入れる (ターン数 / 経過時間で trigger)
- 朝と夜でターン上限を変える (朝 3 / 夜 5-8)
