(() => {
  'use strict';
  const $ = id => document.getElementById(id), bridge = window.chrome && window.chrome.webview;
  const view = new AgentMessages.MessageView($('reader'), $('messages'), $('jump'));
  let ready = false, busy = false, ctrlEnter = false, attachmentCount = 0;
  let pending = null, requestSequence = 0;
  let sessions=[], selected='', sessionsSignature='';
  function closePopups() {
    $('history-panel').hidden=true;$('menu').hidden=true;
    $('history').setAttribute('aria-expanded','false');$('more').setAttribute('aria-expanded','false');
  }
  function renderSessions() {
    const query=$('session-search').value.trim().toLocaleLowerCase();
    const fragment=document.createDocumentFragment();
    let group='';
    for(const session of [...sessions].reverse().filter(s=>s.title.toLocaleLowerCase().includes(query))) {
      const date=/^\d{4}-\d{2}-\d{2}/.exec(session.key)?.[0] || '其他会话';
      if(date!==group){const heading=document.createElement('h4');heading.textContent=date;fragment.append(heading);group=date;}
      const button=document.createElement('button');button.textContent=session.title;button.title=session.title;
      button.disabled=busy;button.setAttribute('aria-current',String(session.key===selected));
      button.onclick=()=>{post('session',{key:session.key});closePopups();};
      const row=document.createElement('div');row.className='session-row';
      const rename=document.createElement('button');rename.textContent='重命名';rename.disabled=busy;
      rename.onclick=()=>{
        const input=document.createElement('input');input.value=session.title.replace(/ \(\d{4}-\d{2}-\d{2}.*\)$/,'');input.maxLength=120;input.setAttribute('aria-label','会话名称');
        const save=document.createElement('button');save.textContent='保存';
        const cancel=document.createElement('button');cancel.textContent='取消';cancel.onclick=renderSessions;
        save.onclick=()=>{if(input.value.trim()){post('rename-session',{key:session.key,title:input.value.trim()});renderSessions();}};
        input.onkeydown=e=>{if(e.key==='Enter')save.click();if(e.key==='Escape'){e.stopPropagation();renderSessions();}};
        row.replaceChildren(input,save,cancel);input.focus();input.select();
      };
      const remove=document.createElement('button');remove.textContent='移除';remove.disabled=busy;remove.title='从历史列表移除，保留本地记录';
      remove.onclick=()=>{if(remove.dataset.confirm==='yes'){post('delete-session',{key:session.key});remove.disabled=true;}else{remove.dataset.confirm='yes';remove.textContent='确认移除';}};
      row.append(button,rename,remove);fragment.append(row);
    }
    if(!fragment.childNodes.length){const note=document.createElement('p');note.textContent='没有匹配的会话';fragment.append(note);}
    $('sessions').replaceChildren(fragment);
  }
  function resizeInput() {
    $('input').style.height='auto';
    $('input').style.height=Math.min(180,Math.max(72,$('input').scrollHeight))+'px';
  }
  function updateSend() {
    $('send').disabled = !ready || !!pending;
    $('send').textContent = pending ? '发送中…' : busy ? '停止' : '发送';
  }
  function post(action, data = {}) { if (bridge) bridge.postMessage(JSON.stringify({version:1,action,...data})); }
  function receive(message) {
    if (!message || message.version !== 1) return;
    if (message.type === 'upsert') {$('empty').hidden=true;view.upsert(message.item);}
    if (message.type === 'reset') {$('empty').hidden=false;view.reset();}
    if (message.type === 'state') {
      ready = true; busy = !!message.busy;
      $('status').textContent = message.status || (busy ? '正在回复…' : '就绪');
      $('model').textContent = message.model || 'deepseek-v4-flash';
      document.body.classList.toggle('light', message.theme === 'light');
      updateSend();
      ctrlEnter = !!message.ctrlEnter;
      const modes={manual:'逐次审批',acceptEdits:'自动批准编辑',auto:'自动审批',bypassPermissions:'免审批',dontAsk:'不询问',plan:'规划模式'};
      $('model').title='审批模式：'+(modes[message.permission]||message.permission||'逐次审批');
      $('status').textContent+=' · '+(modes[message.permission]||message.permission||'逐次审批');
      $('send-hint').textContent=(ctrlEnter?'Ctrl+Enter':'Enter')+' 发送 · Shift+Enter 换行';
      document.querySelectorAll('[data-quick],[data-action="new"]').forEach(b=>b.disabled=busy);
      if (Array.isArray(message.sessions)) {
        const signature=JSON.stringify([message.sessions,message.selected,busy]);
        if(signature!==sessionsSignature){sessionsSignature=signature;sessions=message.sessions;selected=message.selected||'';renderSessions();}
        const title=sessions.find(s=>s.key===selected)?.title || '新会话';
        $('chat-title').textContent=title;$('chat-title').title=title;
      }
      if (Array.isArray(message.attachments)) {
        attachmentCount=message.attachments.length;
        $('attachments').replaceChildren(...message.attachments.map((name,index)=>{const b=document.createElement('button');b.textContent=name+' ×';b.title='移除 '+name;b.onclick=()=>post('remove',{index:String(index)});return b;}));
      }
    }
    if ((message.type === 'accepted' || message.type === 'rejected') && pending && message.requestId === pending.id) {
      if (message.type === 'accepted' && $('input').value === pending.text) $('input').value = '';
      pending = null;
      if (message.type === 'rejected') $('status').textContent = message.reason || '消息未发送，草稿已保留';
      post('draft',{text:$('input').value});
      resizeInput();
      updateSend();
    }
    if (message.type === 'draft') { $('input').value = message.text || ''; resizeInput(); }
  }
  function send() {
    if (!ready || busy || pending) return;
    const text = $('input').value;
    if (!text.trim() && !attachmentCount) return;
    pending = {id:String(++requestSequence),text}; updateSend();
    post('send',{text,requestId:pending.id});
  }
  $('send').onclick = () => { if (busy && !pending) post('stop'); else send(); };
  $('input').onkeydown = e => { if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && e.keyCode !== 229 && (!ctrlEnter || e.ctrlKey)) { e.preventDefault(); send(); } };
  $('input').oninput=()=>{resizeInput();post('draft',{text:$('input').value});};
  document.addEventListener('agent-open-code', e=>post('open-code-block',{text:e.detail}));
  $('history').onclick=()=>{const open=$('history-panel').hidden;closePopups();$('history-panel').hidden=!open;$('history').setAttribute('aria-expanded',String(open));if(open)$('session-search').focus();};
  $('more').onclick=()=>{const open=$('menu').hidden;closePopups();$('menu').hidden=!open;$('more').setAttribute('aria-expanded',String(open));};
  $('session-search').oninput=renderSessions;
  document.addEventListener('keydown',e=>{if(e.key==='Escape')closePopups();});
  document.addEventListener('pointerdown',e=>{if(!e.target.closest('.popup,#history,#more'))closePopups();});
  document.querySelectorAll('[data-quick]').forEach(b=>b.onclick=()=>{if(!busy)post('quick',{index:b.dataset.quick});});
  $('quick').onchange=()=>{if($('quick').value!=='')post('quick',{index:$('quick').value});$('quick').value='';$('menu').hidden=true;};
  document.querySelectorAll('[data-action]').forEach(b => b.onclick = () => {post(b.dataset.action);$('menu').hidden=true;});
  if (bridge) { bridge.addEventListener('message', e => receive(e.data)); post('ready'); }
  else $('status').textContent = '未连接 IDE，发送不可用';
})();
