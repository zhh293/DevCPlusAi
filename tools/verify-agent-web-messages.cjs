const {chromium} = require('playwright');
const assert = require('node:assert/strict');
const {pathToFileURL} = require('node:url');
const path = require('node:path');
(async () => {
  const browser = await chromium.launch({channel:'msedge',headless:true});
  try {
    const page = await browser.newPage({viewport:{width:480,height:780}});
    const errors=[]; page.on('pageerror', e=>errors.push(e.message));
    await page.addInitScript(() => {
      window.sent=[]; window.chrome={webview:{postMessage:s=>sent.push(JSON.parse(s)),addEventListener:(name,fn)=>window.deliver=data=>fn({data})}};
    });
    await page.goto(pathToFileURL(path.resolve('Source/AgentWeb/index.html')).href);
    const deliver = async data => {await page.evaluate(data=>window.deliver({version:1,...data}),data); await page.evaluate(()=>new Promise(requestAnimationFrame));};
    const item = async (id,kind,text,extra={})=>deliver({type:'upsert',item:{id,kind,text,...extra}});
    await deliver({type:'state',model:'deepseek-v4-flash'});
    await item('a','assistant','# 标题\n\n**粗体** 与 `代码`\n\n| 名称 | 复杂度 |\n| --- | --- |\n| 查找 | O(1) |\n\n- 一级\n  - 二级\n\n```cpp\nint main() {}\n```');
    assert.equal(await page.locator('h1').textContent(),'标题');
    assert.equal(await page.locator('table tbody td').count(),2);
    assert.equal(await page.locator('ul ul').count(),1);
    assert.equal(await page.locator('pre code').textContent(),'int main() {}');
    await item('t','tool','输入：dir',{name:'Bash',status:'执行中'});
    await page.locator('summary').click();
    await item('b','assistant','下一段回复');
    await item('t','tool','输出：完成',{name:'Bash',status:'完成'});
    assert.equal(await page.locator('details').getAttribute('open'),'');
    assert.deepEqual(await page.locator('#messages > *').evaluateAll(ns=>ns.map(n=>n.dataset.id)),['a','t','b']);
    await item('unsafe','assistant','<img src=x onerror="window.pwned=1">\n\n[危险](javascript:alert(1))');
    assert.equal(await page.locator('#messages img,#messages script,#messages a').count(),0);
    assert.equal(await page.evaluate(()=>window.pwned),undefined);
    for(let i=0;i<30;i++) await item('long'+i,'assistant','第 '+i+' 段\n\n内容\n\n更多内容');
    assert.ok(await page.locator('#reader').evaluate(n=>n.scrollHeight-n.scrollTop-n.clientHeight<3));
    await page.locator('#reader').evaluate(n=>{n.scrollTop=150;n.dispatchEvent(new Event('scroll'));});
    const top=await page.locator('#reader').evaluate(n=>n.scrollTop);
    await item('long29','assistant','更多流式输出\n\n'.repeat(30));
    assert.equal(await page.locator('#reader').evaluate(n=>n.scrollTop),top);
    await page.locator('#jump').click();
    assert.ok(await page.locator('#reader').evaluate(n=>n.scrollHeight-n.scrollTop-n.clientHeight<3));
    await page.fill('#input','你好');
    await page.locator('#input').dispatchEvent('keydown',{key:'Enter',isComposing:true});
    assert.equal(await page.evaluate(()=>sent.filter(x=>x.action==='send').length),0);
    await page.click('#send');
    assert.equal(await page.evaluate(()=>sent.find(x=>x.action==='send').text),'你好');
    assert.equal(await page.inputValue('#input'),'你好');
    await deliver({type:'accepted'}); assert.equal(await page.inputValue('#input'),'');
    for(const width of [320,480,800]) {
      await page.setViewportSize({width,height:780});
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
    }
    await deliver({type:'reset'}); await item('sample','assistant','## 哈希表实现\n\n使用 **链地址法** 处理冲突，每个桶维护一个链表。\n\n| 操作 | 平均复杂度 |\n| --- | --- |\n| 查找 | O(1) |\n| 插入 | O(1) |\n\n```cpp\nbool contains(const K& key) const {\n    V value;\n    return find(key, value);\n}\n```');
    await page.setViewportSize({width:480,height:780});
    await page.screenshot({path:'.tools/ui-redesign/messages.png'});
    assert.deepEqual(errors,[]);
    console.log('PASS: Markdown, safe DOM, ordered tool updates, expansion, follow/reading scroll, IME, host acknowledgment, 3 widths');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exit(1)});
