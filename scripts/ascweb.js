// ASC Web を headless Chrome for Testing (MCP と同じプロファイル) で駆動する小スクリプト。
// 使い方: node ascweb.js steps.json   (steps は [{op, ...}] の配列)
//   goto {url} / text {sel?} / elements {sel?} / click {text|sel, index?} / eval {js} / upload {sel, path} / shot {path} / wait {ms} / type {sel, value}
const puppeteer = require('puppeteer-core');
const fs = require('fs');
const CHROME = '/Users/touri/.cache/chrome-devtools-mcp/browsers/chrome/mac_arm-148.0.7778.97/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing';
const PROFILE = '/Users/touri/.cache/chrome-devtools-mcp/chrome-profile';

(async () => {
  const steps = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await puppeteer.launch({
    executablePath: CHROME, headless: true, userDataDir: PROFILE,
    args: ['--use-mock-keychain', '--no-first-run', '--window-size=1400,1000'],
    defaultViewport: { width: 1400, height: 1000 },
  });
  const page = (await browser.pages())[0] || (await browser.newPage());
  const out = [];
  try {
    for (const s of steps) {
      if (s.op === 'goto') { await page.goto(s.url, { waitUntil: 'networkidle2', timeout: 60000 }); out.push({ op: 'goto', url: page.url(), title: await page.title() }); }
      else if (s.op === 'wait') { await new Promise(r => setTimeout(r, s.ms)); }
      else if (s.op === 'text') { const t = await page.evaluate(sel => (document.querySelector(sel || 'body') || {}).innerText || '', s.sel); out.push({ op: 'text', text: t.slice(0, s.max || 4000) }); }
      else if (s.op === 'elements') {
        const els = await page.evaluate(sel => Array.from(document.querySelectorAll(sel || 'button, a, [role=button], input, textarea')).map((e, i) => ({ i, tag: e.tagName, text: (e.innerText || e.value || e.getAttribute('aria-label') || '').trim().slice(0, 80), type: e.type || null, disabled: !!e.disabled })).filter(e => e.text || e.tag === 'INPUT' || e.tag === 'TEXTAREA'), s.sel);
        out.push({ op: 'elements', els });
      }
      else if (s.op === 'click') {
        const ok = await page.evaluate((text, sel, index) => {
          const cands = Array.from(document.querySelectorAll(sel || 'button, a, [role=button], [role=menuitem], label, span, div'));
          const hits = cands.filter(e => (e.innerText || '').trim() === text);
          const el = hits[index || 0]; if (!el) return false; el.click(); return true;
        }, s.text, s.sel, s.index);
        await new Promise(r => setTimeout(r, s.ms || 1500));
        out.push({ op: 'click', text: s.text, ok, url: page.url() });
      }
      else if (s.op === 'clicksel') { await page.click(s.sel); await new Promise(r => setTimeout(r, s.ms || 1500)); out.push({ op: 'clicksel', sel: s.sel }); }
      else if (s.op === 'type') { await page.click(s.sel); await page.type(s.sel, s.value, { delay: 5 }); out.push({ op: 'type', sel: s.sel, len: s.value.length }); }
      else if (s.op === 'eval') { const r = await page.evaluate(s.js); out.push({ op: 'eval', r }); }
      else if (s.op === 'upload') { const h = await page.$(s.sel); await h.uploadFile(s.path); out.push({ op: 'upload', path: s.path }); }
      else if (s.op === 'shot') { await page.screenshot({ path: s.path, fullPage: !!s.full }); out.push({ op: 'shot', path: s.path }); }
    }
  } catch (e) { out.push({ error: String(e), url: page.url() }); }
  console.log(JSON.stringify(out, null, 1));
  await browser.close();
})();
