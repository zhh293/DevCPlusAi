// Usage: NODE_PATH=<directory containing playwright> node tools/verify-agent-web-preview.cjs
const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {pathToFileURL} = require('node:url');
(async () => {
  const browser = await chromium.launch({channel:'msedge',headless:true});
  try {
    const page = await browser.newPage({viewport:{width:1100,height:980}});
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(pathToFileURL(path.resolve('Source/AgentWeb/preview.html')).href);
    let cases = 0;
    for (const theme of ['dark','light']) {
      if (theme === 'light') await page.click('#theme');
      for (const width of ['320','480','800']) {
        await page.selectOption('#width',width);
        for (const state of ['chat','markdown','tools','approval','empty','error']) {
          await page.selectOption('#state',state);
          assert.equal(await page.locator('.app').evaluate(e=>e.scrollWidth>e.clientWidth),false,`${theme}/${width}/${state}`);
          const composer = await page.locator('.composer').boundingBox();
          const frame = await page.locator('.app').boundingBox();
          assert.ok(composer.y+composer.height<=frame.y+frame.height,'Composer clipped');
          assert.equal(await page.locator('#send').isVisible(),true);
          cases++;
        }
      }
    }
    await page.selectOption('#state','tools');
    assert.equal(await page.locator('details[open]').count(),2);
    await page.locator('details summary').first().click();
    assert.equal(await page.locator('details[open]').count(),1);
    await page.selectOption('#state','approval');
    await page.getByRole('button',{name:'拒绝',exact:true}).click();
    assert.match(await page.locator('.approval').innerText(),/未执行/);
    await page.click('#new');
    await page.fill('#input','<img src=x onerror=alert(1)>');
    await page.click('#send');
    assert.equal(await page.locator('.user img').count(),0);
    assert.match(await page.locator('.user').last().innerText(),/onerror/);
    await page.fill('#input','中文候选');
    await page.locator('#input').evaluate(e=>e.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',isComposing:true,bubbles:true})));
    assert.equal(await page.inputValue('#input'),'中文候选');
    await page.click('#remove');
    assert.equal(await page.locator('.chip').count(),0);
    await page.selectOption('#width','480');
    await page.selectOption('#state','markdown');
    fs.mkdirSync('.tools/ui-redesign',{recursive:true});
    await page.screenshot({path:'.tools/ui-redesign/light.png'});
    await page.click('#theme');
    await page.screenshot({path:'.tools/ui-redesign/dark.png'});
    assert.deepEqual(errors,[]);
    console.log(`PASS: ${cases} layouts, tool collapse, deny, safe text, IME event, attachment removal`);
  } finally { await browser.close(); }
})().catch(e=>{console.error(e);process.exitCode=1});
