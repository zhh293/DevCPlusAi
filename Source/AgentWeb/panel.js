(() => {
  'use strict';
  const $ = id => document.getElementById(id), bridge = window.chrome && window.chrome.webview;
  const view = new AgentMessages.MessageView($('reader'), $('messages'), $('jump'));
  let ready = false, busy = false, ctrlEnter = false, attachmentCount = 0, contextEnabled = true, contextPayload = '';
  let pending = null, requestSequence = 0, permissionMode='manual', requestedPermissionMode='', modeSwitchPending=false, modeSwitchFeedback='';
  let sessions=[], selected='', sessionsSignature='';
  const permissionModes={
    plan:{label:'规划模式',description:'读取代码并制定计划，不编辑源文件。'},
    manual:{label:'逐次审批',description:'执行敏感操作前先请求你的确认。'},
    acceptEdits:{label:'自动编辑',description:'允许编辑文件；命令仍受 CLI 权限规则控制。'}
  };
  function resetSessionRemoval(button) {
    clearTimeout(button._confirmTimer);
    delete button.dataset.confirm;
    button.textContent='移除';
    button.title='从历史列表移除，保留本地记录';
  }
  function closePopups() {
    document.querySelectorAll('.session-remove[data-confirm="yes"]').forEach(resetSessionRemoval);
    $('history-panel').hidden=true;$('menu').hidden=true;
    $('history').setAttribute('aria-expanded','false');$('more').setAttribute('aria-expanded','false');
    $('changes-panel').hidden=true;$('changes').setAttribute('aria-expanded','false');
    $('permission-menu').hidden=true;$('permission-mode').setAttribute('aria-expanded','false');
  }
  function renderChangeOverview(items) {
    items=Array.isArray(items)?items:[];
    const files=new Map();let operations=0,added=0,removed=0,knownDiffs=0;
    for(const item of items) {
      const path=String(item.path||'').trim();if(!path)continue;
      const key=path.replace(/\//g,'\\').toLocaleLowerCase();
      const file=files.get(key)||{path,count:0,latest:item};
      file.count++;file.latest=item;operations++;
      files.delete(key);files.set(key,file);
      const counts=/^\+(\d+) \/ -(\d+) lines$/.exec(String(item.diffSummary||''));
      if(counts){added+=Number(counts[1]);removed+=Number(counts[2]);knownDiffs++;}
    }
    const count=files.size,button=$('changes');
    button.hidden=count===0;
    $('changes-count').textContent=count>99?'99+':String(count);
    button.setAttribute('aria-label',count?'查看本次对话改动，'+count+' 个文件':'查看本次对话的文件改动');
    if(!count){$('changes-panel').hidden=true;button.setAttribute('aria-expanded','false');$('change-list').replaceChildren();return;}
    $('changes-summary').textContent=count+' 个文件 · '+operations+' 项改动'+(knownDiffs?' · +'+added+' / −'+removed+' 行':'');
    $('changes-note').textContent=knownDiffs<operations?'选择文件跳到差异；部分改动无法逐行比较。':'选择文件跳到对话中的差异。';
    const labels={Added:'新增',Modified:'修改',Renamed:'重命名',Deleted:'删除','Written/edited':'已写入/编辑'};
    const fragment=document.createDocumentFragment();
    for(const file of files.values()) {
      const row=document.createElement('button');row.type='button';row.className='change-entry';row.dataset.targetId=file.latest.id;row.title=file.path;
      const pathText=document.createElement('span');pathText.className='change-entry-path';pathText.textContent=file.path;
      const state=file.latest.undoState==='restored'?'已撤销':(labels[file.latest.fileState]||file.latest.fileState||'文件变更');
      const diff=/^\+(\d+) \/ -(\d+) lines$/.exec(String(file.latest.diffSummary||''));
      const detail=[state,file.count>1?file.count+' 次改动':'',diff?'+'+diff[1]+' / −'+diff[2]+' 行':file.latest.diffSummary==='Diff unavailable'?'差异暂不可用':''].filter(Boolean).join(' · ');
      const meta=document.createElement('span');meta.className='change-entry-meta';meta.textContent=detail;
      row.append(pathText,meta);
      row.onclick=()=>{
        const entry=view.items.get(row.dataset.targetId);
        closePopups();
        if(!entry)return;
        entry.node.open=true;entry.node.scrollIntoView({block:'center',behavior:'smooth'});
        entry.title?.focus({preventScroll:true});
      };
      fragment.append(row);
    }
    $('change-list').replaceChildren(fragment);
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
      const remove=document.createElement('button');remove.textContent='移除';remove.className='session-remove';remove.disabled=busy;remove.title='从历史列表移除，保留本地记录';
      remove.onclick=()=>{
        if(remove.dataset.confirm==='yes'){
          clearTimeout(remove._confirmTimer);delete remove.dataset.confirm;
          post('delete-session',{key:session.key});remove.disabled=true;
        }else{
          remove.dataset.confirm='yes';remove.textContent='确认移除';remove.title='再次点击确认；按 Esc、点到面板外或等待 5 秒可取消';
          clearTimeout(remove._confirmTimer);
          remove._confirmTimer=setTimeout(()=>{if(remove.isConnected)resetSessionRemoval(remove);},5000);
        }
      };
      row.append(button,rename,remove);fragment.append(row);
    }
    if(!fragment.childNodes.length){const note=document.createElement('p');note.textContent='没有匹配的会话';fragment.append(note);}
    $('sessions').replaceChildren(fragment);
  }
  function resizeInput() {
    $('input').style.height='auto';
    $('input').style.height=Math.min(180,Math.max(72,$('input').scrollHeight))+'px';
    view.layoutChanged();
  }
  function selectedAssistantText() {
    const selection=window.getSelection();
    if(!selection||selection.isCollapsed||!selection.rangeCount)return null;
    const range=selection.getRangeAt(0);
    const element=node=>node.nodeType===Node.ELEMENT_NODE?node:node.parentElement;
    const start=element(range.startContainer),end=element(range.endContainer);
    const article=start?.closest('article.assistant');
    if(!article||article!==end?.closest('article.assistant'))return null;
    const body=article.querySelector('.body');
    if(!body?.contains(range.startContainer)||!body.contains(range.endContainer))return null;
    const text=selection.toString().trim();
    if(!text)return null;
    const startCode=start.closest('.codebox'),endCode=end.closest('.codebox');
    const codebox=startCode&&startCode===endCode?startCode:null;
    const language=codebox?.querySelector('.codebar')?.firstChild?.textContent.trim()||'';
    return {range,text,codebox,language};
  }
  function updateSelectionAction() {
    const button=$('ask-selection'),selected=selectedAssistantText();
    if(!selected){button.hidden=true;return;}
    const rect=selected.range.getBoundingClientRect(),readerRect=$('reader').getBoundingClientRect();
    if(rect.width<=0||rect.height<=0||rect.bottom<readerRect.top||rect.top>readerRect.bottom){button.hidden=true;return;}
    button.hidden=false;
    const width=button.offsetWidth,height=button.offsetHeight,footerTop=document.querySelector('.composer').getBoundingClientRect().top;
    const lowerEdge=Math.min(window.innerHeight-8,footerTop-8),below=rect.bottom+7;
    const top=below+height<=lowerEdge?below:Math.max(readerRect.top+8,rect.top-height-7);
    const left=Math.max(8,Math.min(rect.left,window.innerWidth-width-8));
    button.style.top=top+'px';button.style.left=left+'px';
  }
  function formatSelectionPrompt(selected) {
    if(selected.codebox) {
      const language=/^[\p{L}\p{N}_+#.-]{1,24}$/u.test(selected.language)?selected.language:'';
      const longestTickRun=Math.max(0,...(selected.text.match(/`+/g)||[]).map(run=>run.length));
      const fence='`'.repeat(Math.max(3,longestTickRun+1));
      return '请解释下面这段代码，并结合上下文说明它的作用：\n\n'+fence+language+'\n'+selected.text+'\n'+fence;
    }
    return '请解释下面这段内容，并结合上下文说明它的作用：\n\n'+selected.text.split('\n').map(line=>'> '+line).join('\n');
  }
  const askSelection=$('ask-selection');
  askSelection.addEventListener('pointerdown',event=>event.preventDefault());
  askSelection.onclick=()=>{
    const selected=selectedAssistantText();
    if(!selected){askSelection.hidden=true;return;}
    const prompt=formatSelectionPrompt(selected),input=$('input');
    window.getSelection().removeAllRanges();askSelection.hidden=true;
    input.value+=input.value?'\n\n'+prompt:prompt;
    input.focus();input.setSelectionRange(input.value.length,input.value.length);
    resizeInput();post('draft',{text:input.value});
  };
  function updateSend() {
    $('send').disabled = !ready || !!pending;
    $('send').textContent = pending ? '发送中…' : busy ? '停止' : '发送';
    syncPermissionModeControl();
  }
  function syncPermissionModeControl() {
    const info=permissionModes[permissionMode]||{label:'高级权限',description:'当前使用高级 CLI 权限设置。'};
    const locked=!ready||busy||!!pending||modeSwitchPending;
    $('permission-mode-label').textContent=modeSwitchPending?'切换中…':info.label;
    $('permission-mode').title=info.description+(modeSwitchPending?' 正在重启 CLI 并尝试续接会话。':' 点击切换；运行中的任务结束后才能更改。');
    $('permission-mode').setAttribute('aria-label','当前运行方式：'+info.label+'。点击更改');
    $('permission-mode').disabled=locked;
    document.querySelectorAll('[data-permission-mode]').forEach(button=>{
      button.disabled=locked;
      button.setAttribute('aria-pressed',String(button.dataset.permissionMode===permissionMode));
    });
    if(modeSwitchPending)$('permission-mode-feedback').textContent='正在重启 Agent CLI，并尝试续接当前会话…';
    else $('permission-mode-feedback').textContent=modeSwitchFeedback||'切换会重启 Agent CLI，并尝试续接当前会话。';
  }
  function positionPermissionMenu() {
    const menu=$('permission-menu'),trigger=$('permission-mode');
    if(menu.hidden)return;
    const triggerRect=trigger.getBoundingClientRect(),width=Math.min(320,window.innerWidth-16);
    menu.style.width=width+'px';
    const height=menu.offsetHeight,left=Math.max(8,Math.min(triggerRect.left,window.innerWidth-width-8));
    const composerTop=document.querySelector('.composer').getBoundingClientRect().top;
    let top=Math.min(triggerRect.top-8,composerTop-8)-height;
    if(top<8)top=Math.min(triggerRect.bottom+8,window.innerHeight-height-8);
    menu.style.left=left+'px';menu.style.top=Math.max(8,top)+'px';
  }
  function updateContextControl() {
    $('context-toggle').checked=contextEnabled;
    $('context-preview').classList.toggle('context-off',!contextEnabled);
    $('context-toggle').title=contextEnabled
      ? '发送时自动附加当前编辑器选区或光标附近代码，以及可用的编译诊断；偏好会保存在设置中。'
      : '已关闭：消息只包含你输入的内容和手动添加的附件；偏好会保存在设置中。';
    const summary=$('context-summary-text').textContent;
    $('context-summary').title=contextEnabled
      ? (summary||'上下文摘要将在发送前自动获取')
      : (summary ? '当前摘要仅供查看；关闭状态下不会发送给 AI。' : '未发送 IDE 代码或编译诊断。');
    $('context-toggle').disabled=busy;
    $('context-note').textContent=!contextEnabled
      ? '已关闭 IDE 上下文；以下内容仅供核对，不会随消息发送。'
      : busy
        ? '本次正在运行的请求使用该快照。发送后会随本地会话保存，供之后复盘。'
        : '这是最近一次采集的快照。每次发送前 IDE 会自动重新读取当前文件和编译诊断；点击“刷新”可提前核对。实际发送的快照会保存在本地会话中。';
  }
  function updateContextPreview() {
    $('context-content').textContent=contextPayload || '当前没有可附加的代码或编译诊断。';
    $('context-size').textContent=contextPayload ? contextPayload.length.toLocaleString()+' 个字符' : '空';
    $('context-summary').disabled=!contextPayload && $('context-summary-text').textContent==='发送前会自动获取当前代码上下文';
    updateContextControl();
  }
  function formatStatus(value, isBusy) {
    const labels={
      'Ready':'就绪',
      'Thinking...':'正在思考…',
      'Working...':'正在执行工具…',
      'Waiting for approval...':'等待你审批…',
      'Error':'发生错误',
      'Disconnected':'未连接'
    };
    const raw=String(value||'').trim();
    return raw ? (labels[raw]||raw) : (isBusy?'正在回复…':'就绪');
  }
  function post(action, data = {}) { if (bridge) bridge.postMessage(JSON.stringify({version:1,action,...data})); }
  function receive(message) {
    if (!message || message.version !== 1) return;
    if (message.type === 'upsert') {$('empty').hidden=true;view.upsert(message.item);}
    if (message.type === 'reset') {$('empty').hidden=false;view.reset();}
    if (message.type === 'state') {
      ready = true; busy = !!message.busy;
      window.AgentBusy = busy;
      view.setBusy(busy);
      if (typeof message.contextEnabled === 'boolean') contextEnabled=message.contextEnabled;
      if (typeof message.contextPayload === 'string') contextPayload=message.contextPayload;
      if(typeof message.permission==='string')permissionMode=message.permission;
      if(modeSwitchPending&&message.permission===requestedPermissionMode){modeSwitchPending=false;requestedPermissionMode='';modeSwitchFeedback='';}
      document.querySelectorAll('.code-insert').forEach(b=>b.disabled=busy);
      $('status').textContent = formatStatus(message.status,busy);
      $('model').textContent = message.model || 'deepseek-v4-flash';
      $('model').title='当前模型：'+(message.model||'deepseek-v4-flash');
      if (typeof message.contextSummary === 'string') {
        const summary=AgentMessages.formatContextSummary(message.contextSummary);
        $('context-summary-text').textContent = summary || (contextPayload ? '查看已同步上下文' : '发送前会自动获取当前代码上下文');
        $('context-summary').title = summary || '上下文摘要将在发送前自动获取';
        $('context-summary').disabled = !summary && !contextPayload;
        if (!summary && !contextPayload) {
          $('context-preview').classList.remove('expanded');
          $('context-summary').setAttribute('aria-expanded','false');
        }
        $('context-preview').classList.toggle('refreshed', !!message.contextSummary);
      }
      $('context-details').hidden=!$('context-preview').classList.contains('expanded');
      updateContextPreview();
      $('context-refresh').disabled=busy;
      document.body.classList.toggle('light', message.theme === 'light');
      const size=Math.min(24,Math.max(8,Number(message.fontSize)||14));
      document.documentElement.style.setProperty('--chat-font-size',size+'px');
      document.documentElement.style.setProperty('--chat-code-font-size',Math.max(10,size-1)+'px');
      const font=typeof message.fontName==='string'&&/^[\p{L}\p{N} _-]{1,64}$/u.test(message.fontName)?message.fontName:'';
      if(font)document.documentElement.style.setProperty('--chat-font-family','"'+font+'", "Segoe UI", "Microsoft YaHei UI", sans-serif');
      updateSend();
      ctrlEnter = !!message.ctrlEnter;
      view.layoutChanged();
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
        const files=message.attachments.map(entry=>typeof entry==='string'?{name:entry,path:''}:{name:String(entry.name||'附件'),path:String(entry.path||'')});
        const counts=new Map();
        files.forEach(file=>{const key=file.name.toLowerCase();counts.set(key,(counts.get(key)||0)+1);});
        $('attachments').replaceChildren(...files.map((file,index)=>{
          const parts=file.path.replace(/\//g,'\\').split('\\').filter(Boolean);
          const parent=parts.length>1?parts[parts.length-2]:'';
          const duplicate=counts.get(file.name.toLowerCase())>1;
          const label=duplicate&&parent?parent+' / '+file.name:file.name;
          const b=document.createElement('button');
          b.textContent=label+' ×';
          b.title=(file.path?'路径：'+file.path+'\n':'')+'点击移除附件';
          b.setAttribute('aria-label','移除附件 '+label+(file.path?'，路径 '+file.path:''));
          b.onclick=()=>post('remove',{index:String(index)});
          return b;
        }));
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
    if (message.type === 'permission-error') {
      $('status').textContent=message.message||'此请求已失效';
      document.dispatchEvent(new CustomEvent('agent-permission-error',{detail:message}));
    }
    if(message.type==='permission-mode-result'){
      modeSwitchPending=false;requestedPermissionMode='';
      if(message.success){permissionMode=message.mode||permissionMode;modeSwitchFeedback='';}
      else{
        const reasons={busy:'本轮任务正在运行，请结束后再切换。',unsupported:'该模式请到“更多权限设置”中选择。',unavailable:'当前无法更改运行方式。',failed:'切换失败，AI 状态和会话记录已保留。'};
        modeSwitchFeedback=(reasons[message.reason]||'切换失败，请检查 AI 状态后重试。')+(message.detail?' '+message.detail:'');
      }
      syncPermissionModeControl();
    }
    if (message.type === 'code-copy-result')
      document.dispatchEvent(new CustomEvent('agent-copy-code-result',{detail:message}));
    if (message.type === 'file-undo-result')
      document.dispatchEvent(new CustomEvent('agent-file-undo-result',{detail:message}));
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
  document.addEventListener('selectionchange',updateSelectionAction);
  $('reader').addEventListener('scroll',updateSelectionAction,{passive:true});
  window.addEventListener('resize',()=>{view.layoutChanged();updateSelectionAction();positionPermissionMenu();});
  document.addEventListener('agent-open-code', e=>post('open-code-block',{text:e.detail}));
  document.addEventListener('agent-copy-code', e=>post('copy-code-block',e.detail||{}));
  document.addEventListener('agent-insert-code', e=>{if(!busy)post('insert-code-block',{text:e.detail});});
  document.addEventListener('agent-open-file', e=>post('open-file',{path:e.detail}));
  document.addEventListener('agent-open-link',e=>post('open-link',{url:e.detail}));
  document.addEventListener('agent-undo-file',e=>post('undo-file-change',e.detail||{}));
  document.addEventListener('agent-file-changes',e=>renderChangeOverview(e.detail));
  document.addEventListener('agent-permission', e=>post('permission',e.detail||{}));
  $('history').onclick=()=>{const open=$('history-panel').hidden;closePopups();$('history-panel').hidden=!open;$('history').setAttribute('aria-expanded',String(open));if(open)$('session-search').focus();};
  $('changes').onclick=()=>{const open=$('changes-panel').hidden;closePopups();if(!open)return;$('changes-panel').hidden=false;$('changes').setAttribute('aria-expanded','true');$('change-list').querySelector('button')?.focus();};
  $('changes-close').onclick=()=>{closePopups();$('changes').focus();};
  $('context-summary').onclick=()=>{const expanded=$('context-preview').classList.toggle('expanded');$('context-details').hidden=!expanded;$('context-summary').setAttribute('aria-expanded',String(expanded));view.layoutChanged();};
  $('context-refresh').onclick=()=>{if(!busy)post('context');};
  $('context-toggle').onchange=()=>{if(busy){updateContextControl();return;}contextEnabled=$('context-toggle').checked;updateContextControl();post('context-enabled',{enabled:String(contextEnabled)});};
  $('more').onclick=()=>{const open=$('menu').hidden;closePopups();$('menu').hidden=!open;$('more').setAttribute('aria-expanded',String(open));};
  $('permission-mode').onclick=()=>{
    const open=$('permission-menu').hidden;closePopups();
    if(!open)return;
    $('permission-menu').hidden=false;$('permission-mode').setAttribute('aria-expanded','true');
    syncPermissionModeControl();positionPermissionMenu();
    ($('permission-menu').querySelector('[aria-pressed="true"]')||$('permission-menu').querySelector('[data-permission-mode]'))?.focus();
  };
  $('session-search').oninput=renderSessions;
  document.addEventListener('keydown',e=>{if(e.key==='Escape'){const closeMode=!$('permission-menu').hidden,closeChanges=!$('changes-panel').hidden;closePopups();if(closeMode)$('permission-mode').focus();else if(closeChanges)$('changes').focus();}});
  document.addEventListener('pointerdown',e=>{if(!e.target.closest('.popup,#history,#changes,#more,#permission-menu,#permission-mode'))closePopups();});
  document.querySelectorAll('[data-quick]').forEach(b=>b.onclick=()=>{if(!busy)post('quick',{index:b.dataset.quick});});
  $('quick').onchange=()=>{if($('quick').value!=='')post('quick',{index:$('quick').value});$('quick').value='';$('menu').hidden=true;};
  document.querySelectorAll('[data-permission-mode]').forEach(button=>button.onclick=()=>{
    const mode=button.dataset.permissionMode;
    if(!permissionModes[mode]||busy||pending||modeSwitchPending)return;
    closePopups();
    if(mode===permissionMode)return;
    modeSwitchPending=true;requestedPermissionMode=mode;modeSwitchFeedback='';syncPermissionModeControl();
    post('permission-mode',{mode});
  });
  document.querySelectorAll('[data-action]').forEach(b => b.onclick = () => {post(b.dataset.action);closePopups();});
  if (bridge) { bridge.addEventListener('message', e => receive(e.data)); post('ready'); }
  else $('status').textContent = '未连接 IDE，发送不可用';
})();
