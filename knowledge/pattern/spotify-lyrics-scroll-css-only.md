---
title: Spotify 歌詞風縦スクロール UI を framer-motion なしで実装するパターン
category: pattern
tags: [react, css, scroll, ux, scrollIntoView, snap, spotify-lyrics, jsdom-pitfall, chrome-devtools-mcp]
created: 2026-05-26
project: global
sources:
  - Atender Phase 4 設計 doc (.designs/20260526-v3-rooms-friends.md §4.1)
  - https://developer.mozilla.org/en-US/docs/Web/API/Element/scrollIntoView
  - https://developer.mozilla.org/ja/docs/Web/CSS/CSS_scroll_snap
  - https://github.com/mebtte/react-lrc
---

## Context

Spotify / Apple Music 歌詞のような「今のラインが画面中央に固定、過去は薄く流れ、未来は下に並ぶ」UI を React + Tailwind で実装したいケース。Atender の Today 画面 (現在進行中の授業を中央表示) で採用。

候補ライブラリ:
- `framer-motion` / `motion-one` — 強力だが MVP には過剰、bundle size +60KB
- `@applemusic-like-lyrics/react` — 完成度高いが Atender の歌詞ではない用途には合わない
- `react-lrc` — LRC 形式専用、不適合

→ **CSS transition + `scrollIntoView` + native scroll-snap** で十分。

## What

### コア実装パターン

```tsx
function LyricsScrollList({ items, activeIndex }: Props) {
  const containerRef = useRef<HTMLUListElement>(null);
  const [isManualScroll, setIsManualScroll] = useState(false);
  const prefersReducedMotion = usePrefersReducedMotion();

  // 1. active 切替で中央スクロール (手動 scroll 中はスキップ)
  useEffect(() => {
    if (isManualScroll) return;
    const el = containerRef.current?.children[activeIndex] as HTMLElement | undefined;
    el?.scrollIntoView({
      behavior: prefersReducedMotion ? "auto" : "smooth",
      block: "center",
    });
  }, [activeIndex, isManualScroll, prefersReducedMotion]);

  // 2. 手動 scroll 検知 (smooth scroll 自体は発火しないことに依存)
  const handleManualScroll = (e: WheelEvent | TouchEvent) => {
    if (("deltaY" in e && e.deltaY !== 0) || "touches" in e) {
      setIsManualScroll(true);
    }
  };

  return (
    <>
      <ul
        ref={containerRef}
        className="overflow-y-auto snap-y snap-mandatory scroll-pt-[40%] scroll-pb-[40%]"
        onWheel={handleManualScroll}
        onTouchMove={handleManualScroll}
      >
        {items.map((item, i) => (
          <li
            key={item.id}
            className={cn(
              "snap-center py-6 transition-all duration-500 ease-out",
              i < activeIndex && "opacity-30 scale-90 -translate-y-2",
              i === activeIndex && "opacity-100 scale-105 font-bold ring-2 ring-accent-500",
              i > activeIndex && "opacity-70 scale-100"
            )}
          >
            {item.content}
          </li>
        ))}
      </ul>
      {isManualScroll && (
        <ReturnToNowFAB onClick={() => setIsManualScroll(false)} />
      )}
    </>
  );
}
```

### 状態 3 段階の CSS class

| state | class | 用途 |
|---|---|---|
| `past` (i < activeIndex) | `opacity-30 scale-90 -translate-y-2` | 過去 (薄く上に流れる) |
| `current` (i === activeIndex) | `opacity-100 scale-105 font-bold ring-2 ring-accent-500 bg-bg-elevated shadow-card` | 現在 (主役) |
| `future` (i > activeIndex) | `opacity-70 scale-100` | 未来 (控えめ) |

全 state 共通: `snap-center py-6 transition-all duration-500 ease-out`

### scroll-padding でセンタリング精度を上げる

container に `scroll-pt-[40%] scroll-pb-[40%]` (上下 40% パディング) を付けると、`block: "center"` でのスクロール先が画面中央寄りで安定する。`scroll-padding-block` (`scroll-pt-` + `scroll-pb-`) はネイティブ CSS、Tailwind v4 で arbitrary value 対応。

### 手動 scroll 検知の鍵

- `onWheel` の `deltaY !== 0` 条件: smooth scroll の補間で deltaY が 0 のイベントが発火しても無視
- `onTouchMove`: モバイルの慣性スクロールも対応
- Chrome (Chromium 系) は `scrollIntoView({behavior: "smooth"})` の途中で `onWheel` を発火**しない**。Firefox / Safari は grey area だが `deltaY !== 0` 条件で実害なし

### `prefers-reduced-motion` 対応

```tsx
function usePrefersReducedMotion() {
  const [reduced, setReduced] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    setReduced(mq.matches);
    const listener = (e: MediaQueryListEvent) => setReduced(e.matches);
    mq.addEventListener("change", listener);
    return () => mq.removeEventListener("change", listener);
  }, []);
  return reduced;
}
```

`scrollIntoView` の `behavior` を `"auto"` に切替 (即時スクロール)。transition 自体は CSS の `transition-all` で残るが、prefers-reduced-motion 時にこれも止めたい場合は media query 内で `transition-none` を当てる。

## Why

- `scrollIntoView({block:"center"})` は IE 以外フルサポート (caniuse 2026 時点)、ライブラリ依存ゼロ
- `scroll-snap` ネイティブが iOS Safari 11+ / Android 7+ で安定
- CSS transition は GPU アクセラレーション効くので 60fps、framer-motion 不要
- bundle size 削減 (framer-motion ≈ 60KB が浮く)
- React 19 の Suspense / Concurrent Mode と完全に互換 (subscribe 系の library が無いので)

### jsdom の罠

- jsdom では `scrollIntoView` が **no-op**。`element.scrollIntoView()` を呼んでも実際に scrollTop が変わらない
- vitest + RTL でのテストは「呼ばれた回数 / 引数」を `vi.spyOn(HTMLElement.prototype, 'scrollIntoView')` で assert するのみ
- 実際の位置検証は **chrome-devtools MCP の E2E** に振る (Chrome for Testing headless)
- 関連: [gotcha/jsdom-getboundingclientrect-zero](../gotcha/jsdom-getboundingclientrect-zero.md)

## How to apply

「現在進行中の項目を画面中央に固定」UI を作るときの順序:

1. **依存追加なし**で `scrollIntoView` + CSS transition で実装。framer-motion は最後の手段
2. activeIndex の算出を memo 化 (`useMemo`)、deps は外部状態 (`useNow(60_000)` 等)
3. `useEffect` で `scrollIntoView` を呼ぶ deps を `[activeIndex, isManualScroll, prefersReducedMotion]` の 3 つに絞る
4. 手動 scroll 検知は `onWheel (deltaY !== 0)` + `onTouchMove` の 2 系統
5. 「今に戻る」FAB は `isManualScroll === true` のときだけ表示、tap で `setIsManualScroll(false)`
6. テストは jsdom で `scrollIntoView` spy + state class assert、実 scroll は MCP に振る
7. `prefers-reduced-motion: reduce` 時に `behavior: "auto"` に切替 (a11y 必須)

不採用案 (再検討しない):
- framer-motion / motion-one (bundle 増、ハマる要素なし)
- 自前 IntersectionObserver で current 判定 (scrollIntoView で済む)
- 過去要素を `display: none` で DOM から除外 (DOM 数 5-50 程度なら opacity 操作で十分)
- 秒単位 polling での active 再算出 (1 分単位で十分)
- jsdom で scroll 位置を assert (no-op で常に 0、MCP に振る)
