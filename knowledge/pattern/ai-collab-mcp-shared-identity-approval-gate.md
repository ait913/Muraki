---
title: AI が人間 identity を共有する MCP での「承認ゲート」設計 (構造ゲートで代理)
category: pattern
tags: [mcp, oauth, decision, daci, approval-gate, identity, agent-driven, optimistic-lock]
created: 2026-07-09
project: agent-hub
sources:
  - Muraki/projects/agent-hub/.designs/20260709-mcp-server-mvp.md
  - Muraki/knowledge/pattern/remote-mcp-multitenant-self-as.md
---

## Context

AI グループ開発ツール (agent-hub 等) で「意思決定は人間が承認する (ブラックボックス化を防ぐ)」を
実装したい。しかし各メンバーの AI は**そのメンバー自身の GitHub OAuth token** で接続するため、
サーバーから見ると「AI が押した操作」と「人間が押した操作」は同一 identity で区別できない。
DACI の Approver ゲートを token レベルで検証できない、という構造的制約に当たる。

## What

- 「人間 vs AI」を token で判別する実装は**不能** (共有 identity)。強制すると偽の検証になる。
- 実効的な代理 = **構造ゲート**にする:
  1. **driver ≠ approver** を DB で強制 (提案者本人は自分の提案を採択できない = 必ず第三者を通す)。
  2. 提案時に **designated_approver を指名可**にし、指名時はその identity のみが採択できる (DACI の 1 名 Approver)。
  3. 採択は `status='proposed'` のときだけ許し、遷移は **version 楽観ロック** (`WHERE version=?`) で並行採択の二重確定を防ぐ。
- 決定の不変性は**上書きせず被代替 (supersede)**: 旧決定の内容列 (title/body/rationale/driver/created_at) は
  INSERT 後二度と UPDATE せず、遷移で動くのは status/decided_by/decided_at/superseded_by_id/version のみ。
  supersede は「新決定 (proposed) を積む → それが accepted された瞬間に旧を superseded へ」の 2 段にすると、
  置換が承認されるまで旧が現行のまま残り、組織記憶に穴が空かない。

## Why

- 共有 identity 下で「第三者承認」までは構造的に担保できる (自己採択の禁止)。「別メンバーの AI が
  代理承認する」余地は残るが、それは token でなく運用/信頼の領域であり、サーバーの責務外と割り切る。
  真に人間クリックを唯一経路にしたいなら Web ダッシュボード (AI が叩けない面) を後付けする。
- 不変+被代替は ADR の思想。決定を上書きすると「なぜそう決めたか」の系譜が消え、判断の
  ブラックボックス化を防ぐという目的自体が壊れる。

## How to apply

- AI 駆動 MCP で承認・ロック系を設計するとき、まず「この主体は token で一意に人間と特定できるか?」を
  問う。できないなら人間 vs AI の判別を要件から外し、driver≠approver / 指名 approver / 楽観ロックの
  構造ゲートに落とす。承認ゲートを「人間フラグ引数」で自己申告させるのは最悪 (identity 自己申告と同じ罠)。
- 「不変にすべき記録 (Decision)」と「更新・削除してよい記録 (Knowledge=handbook)」を分ける。前者は
  supersede、後者はフル CRUD。両者を同じ CRUD で扱うと、片方が陳腐化の山、もう片方が記憶の穴になる。
- 承認ゲートを token で完全強制できない旨は設計 doc の「判断論点」に必ず上げ、人間クリック経路
  (dashboard) を足すか受容するかを承認ゲートで裁定してもらう。
