(() => {
  'use strict';
  const $ = id => document.getElementById(id), bridge = window.chrome && window.chrome.webview;
  const view = new AgentMessages.MessageView($('reader'), $('messages'), $('jump'));
  let ready = false, busy = false, ctrlEnter = false, attachmentCount = 0;
  function post(action, data = {}) { if (bridge) bridge.postMessage(JSON.stringify({version:1,action,...data})); }
  function receive(message) {
    if (!message || message.version !== 1) return;
    if (message.type === 'upsert') view.upsert(message.item);
    if (message.type === 'reset') view.reset();
    if (message.type === 'state') {
      ready = true; busy = !!message.busy;
      $('status').textContent = message.status || (busy ? '正在回复…' : '就绪');
      $('model').textContent = message.model || 'deepseek-v4-flash';
      document.body.classList.toggle('light', message.theme === 'light');
      $('send').disabled = false; $('send').textContent = busy ? '停止' : '发送';
      ctrlEnter = !!message.ctrlEnter;
      if (Array.isArray(message.sessions)) {
        $('sessions').replaceChildren(...message.sessions.map(s => {const o=document.createElement('option');o.value=s.key;o.textContent=s.title;return o;}));
        $('sessions').value=message.selected || '';
        $('sessions').disabled=busy;
      }
      if (Array.isArray(message.attachments)) {
        attachmentCount=message.attachments.length;
        $('attachments').replaceChildren(...message.attachments.map((name,index)=>{const b=document.createElement('button');b.textContent=name+' ×';b.title='移除 '+name;b.onclick=()=>post('remove',{index:String(index)});return b;}));
      }
    }
    if (message.type === 'accepted') { $('input').value = ''; }
    if (message.type === 'draft') { $('input').value = message.text || ''; }
  }
  function send() { if (!ready) return; if (busy) { post('stop'); return; } const text = $('input').value.trim(); if (text || attachmentCount) post('send',{text}); }
  $('send').onclick = send;
  $('input').onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.keyCode !== 229 && (!ctrlEnter || e.ctrlKey)) { e.preventDefault(); send(); } };
  $('input').oninput=()=>post('draft',{text:$('input').value});
  $('history').onclick=()=>{$('history-panel').hidden=!$('history-panel').hidden;$('menu').hidden=true;};
  $('more').onclick=()=>{$('menu').hidden=!$('menu').hidden;$('history-panel').hidden=true;};
  $('sessions').onchange=()=>{post('session',{key:$('sessions').value});$('history-panel').hidden=true;};
  $('quick').onchange=()=>{if($('quick').value!=='')post('quick',{index:$('quick').value});$('quick').value='';$('menu').hidden=true;};
  document.querySelectorAll('[data-action]').forEach(b => b.onclick = () => {post(b.dataset.action);$('menu').hidden=true;});
  if (bridge) { bridge.addEventListener('message', e => receive(e.data)); post('ready'); }
  else $('status').textContent = '未连接 IDE，发送不可用';
})();
