/* Marked supplies tokens only. Untrusted HTML never enters an HTML sink. */
(() => {
  'use strict';
  const el = (tag, text) => { const n = document.createElement(tag); if (text !== undefined) n.textContent = text; return n; };
  function formatContextSummary(value) {
    if (!value) return '';
    if (String(value)==='context disabled') return '本次请求未附加 IDE 上下文';
    const parts=String(value).split(' | ');
    const file=parts.shift() || '当前文件';
    const details=parts.map(part=>{
      if(part==='saved')return '已保存';
      if(part==='unsaved')return '未保存';
      let match=/^selection L(\d+)-L(\d+)$/i.exec(part);
      if(match)return '选区 L'+match[1]+'–L'+match[2];
      match=/^cursor L(\d+)$/i.exec(part);
      if(match)return '光标 L'+match[1];
      match=/^(\d+) compiler diagnostics$/i.exec(part);
      if(match)return match[1]+' 条编译诊断';
      match=/^(\d+) raw build lines$/i.exec(part);
      if(match)return '编译输出 '+match[1]+' 行';
      return part;
    });
    return [file,...details].join(' · ');
  }
  function formatSystemMessage(value) {
    return String(value||'')
      .replace(/^(\s*)\[Claude failure\]\s*/i,'$1AI 服务失败：')
      .replace(/^(\s*)\[Claude\]\s*/i,'$1AI 状态：')
      .replace(/^(\s*)\[Rate limit\]\s*/i,'$1请求频率限制：')
      .replace(/^(\s*)\[Error\]\s*/i,'$1错误：')
      .replace(/^(\s*)\[Notice\]\s*/i,'$1提示：')
      .replace(/^(\s*)\[Suggestion\]\s*/i,'$1建议：')
      .replace(/\bTurn finished: error\b/gi,'本轮因错误结束')
      .replace(/\bTurn finished\b/gi,'本轮已结束')
      .replace(/,\s*duration\b/gi,'，耗时')
      .replace(/,\s*cost\b/gi,'，费用')
      .replace(/,\s*permission denied/gi,'，权限被拒绝')
      .replace(/\bAPI retry\b/gi,'接口正在重试')
      .replace(/\(retry in ([^)]+)\)/gi,'($1 后重试)');
  }
  function looksLikeMojibake(value) {
    const text=String(value||'');
    if(/[\uFFFD]|(?:锟斤拷|Ã.|Â.|ï»¿)/.test(text))return true;
    const cjk=text.match(/[\u3400-\u9fff]/g)||[];
    const suspicious=text.match(/[鍩媺鎵樻柉鐗绛涙硶锛璇鏄鏈鍐鎴绔鏂瀹鍔闂]/g)||[];
    return suspicious.length>=5&&suspicious.length/Math.max(cjk.length,1)>=0.14;
  }
  function safeExternalUrl(value) {
    try {
      const url=new URL(String(value||''));
      if(!['http:','https:'].includes(url.protocol)||!url.hostname||url.username||url.password)return '';
      return url.href;
    } catch { return ''; }
  }
  function setCodeLineNumbers(code, enabled, language) {
    const source=code.textContent;
    if(!enabled){
      const replacement=window.AgentHighlight?AgentHighlight(source,language):el('code',source);
      code.replaceWith(replacement);
      return;
    }
    const sourceNodes=[],clonedNodes=[],rows=[];
    const makeRow=index=>{const row=el('span');row.className='code-line';row.dataset.line=String(index+1);rows.push(row);return row;};
    let currentRow=makeRow(0);
    const currentParent=()=>clonedNodes.length?clonedNodes[clonedNodes.length-1]:currentRow;
    const nextRow=()=>{
      currentRow=makeRow(rows.length);
      clonedNodes.length=0;
      let parent=currentRow;
      for(const sourceNode of sourceNodes){const clone=sourceNode.cloneNode(false);parent.append(clone);clonedNodes.push(clone);parent=clone;}
    };
    const appendNode=node=>{
      if(node.nodeType===Node.TEXT_NODE){
        const parts=node.textContent.split('\n');
        parts.forEach((part,index)=>{if(part)currentParent().append(document.createTextNode(part));if(index<parts.length-1)nextRow();});
      } else if(node.nodeType===Node.ELEMENT_NODE){
        const clone=node.cloneNode(false);currentParent().append(clone);sourceNodes.push(node);clonedNodes.push(clone);
        for(const child of Array.from(node.childNodes))appendNode(child);
        sourceNodes.pop();clonedNodes.pop();
      } else currentParent().append(node.cloneNode(true));
    };
    for(const child of Array.from(code.childNodes))appendNode(child);
    code.replaceChildren();
    rows.forEach((row,index)=>{
      code.append(row);
      if(index<rows.length-1)code.append(document.createTextNode('\n'));
    });
  }
  const pendingCodeCopies = new Map();
  const toolLabels=Object.freeze({
    Write:'写入文件',Edit:'修改文件',MultiEdit:'批量修改文件',Bash:'执行命令',
    Read:'读取文件',Glob:'搜索文件',Grep:'搜索内容',LS:'浏览目录',
    Task:'运行子任务',Agent:'运行子代理',AskUserQuestion:'询问用户',
    WebSearch:'搜索网页',WebFetch:'读取网页',TodoRead:'查看任务清单',
    TodoWrite:'更新任务清单',NotebookEdit:'编辑笔记本'
  });
  let codeCopySequence = 0;
  function copyIdleText(button) {
    if(!button.dataset.copyIdleText)button.dataset.copyIdleText=button.textContent;
    return button.dataset.copyIdleText;
  }
  function showCopied(button, idleText='复制') {
    clearTimeout(button.copyResetTimer);
    button.textContent = '已复制';
    button.title = '已复制到剪贴板';
    button.copyResetTimer=setTimeout(() => { button.textContent = idleText; button.title = ''; }, 1800);
  }
  function requestHostCopy(button, text, code, selectionLabel='代码') {
    const requestId = 'code-copy-' + (++codeCopySequence);
    const pending = {button, code, selectionLabel, idleText:copyIdleText(button), timer:0};
    pending.timer = setTimeout(() => {
      pendingCodeCopies.delete(requestId);
      selectCodeForManualCopy(pending);
    }, 5000);
    pendingCodeCopies.set(requestId, pending);
    button.textContent = '复制中…';
    document.dispatchEvent(new CustomEvent('agent-copy-code', {
      detail:{requestId, text:String(text||'')}
    }));
  }
  async function copyText(button, text, code, selectionLabel='代码') {
    const idleText=copyIdleText(button);
    clearTimeout(button.copyResetTimer);
    try {
      await navigator.clipboard.writeText(String(text||''));
      showCopied(button,idleText);
    } catch {
      requestHostCopy(button,text,code,selectionLabel);
    }
  }
  function selectCodeForManualCopy(pending) {
    if (!pending.button.isConnected) return;
    const box = pending.button.closest('.codebox');
    if (box?.classList.contains('collapsed')) {
      box.classList.remove('collapsed');
      const fold = box.querySelector('.code-actions button[aria-expanded]');
      if (fold) { fold.textContent = '折叠'; fold.setAttribute('aria-expanded', 'true'); }
    }
    requestAnimationFrame(() => requestAnimationFrame(() => {
      const code = box?.querySelector('pre code') || pending.code;
      if (!code || !code.isConnected) return;
      const selection = window.getSelection();
      const range = document.createRange();
      range.selectNodeContents(code);
      selection.removeAllRanges();
      selection.addRange(range);
      pending.button.textContent = '按 Ctrl+C';
      pending.button.title = '自动复制失败，'+pending.selectionLabel+'已选中；按 Ctrl+C 复制。';
    }));
  }
  document.addEventListener('agent-copy-code-result', event => {
    const result = event.detail || {};
    const requestId = String(result.requestId || '');
    const pending = pendingCodeCopies.get(requestId);
    if (!pending) return;
    clearTimeout(pending.timer);
    pendingCodeCopies.delete(requestId);
    if (result.success) showCopied(pending.button,pending.idleText);
    else selectCodeForManualCopy(pending);
  });
  function requestPermission(data) {
    document.dispatchEvent(new CustomEvent('agent-permission', {detail:data}));
  }
  function inline(tokens, parent) {
    for (const t of tokens || []) {
      let n;
      switch (t.type) {
        case 'strong': case 'em': case 'del': n = el(t.type); inline(t.tokens, n); break;
        case 'codespan': n = el('code', t.text); break;
        case 'br': n = el('br'); break;
        case 'link': {
          const href=safeExternalUrl(t.href);
          n=el(href?'a':'span');inline(t.tokens,n);
          if(href){
            n.href=href;n.target='_blank';n.rel='noopener noreferrer';n.className='external-link';
            n.title='在默认浏览器打开：'+href;
            n.addEventListener('click',event=>{
              event.preventDefault();
              document.dispatchEvent(new CustomEvent('agent-open-link',{detail:href}));
            });
          }else n.title='已禁用非 HTTP/HTTPS 链接';
          break;
        }
        case 'image': n = el('span', t.text || '[图片]'); break;
        default:
          n = el('span');
          if (t.tokens) inline(t.tokens, n); else n.textContent = t.text || t.raw || '';
      }
      parent.append(n);
    }
  }
  function blocks(tokens, parent) {
    for (const t of tokens) {
      let n;
      switch (t.type) {
        case 'space': continue;
        case 'heading': n = el('h' + Math.min(6, Math.max(1, t.depth))); inline(t.tokens, n); break;
        case 'paragraph': case 'text': n = el('p'); inline(t.tokens || [{type:'text',text:t.text}], n); break;
        case 'hr': n = el('hr'); break;
        case 'blockquote': n = el('blockquote'); blocks(t.tokens, n); break;
        case 'list':
          n = el(t.ordered ? 'ol' : 'ul'); if (t.ordered) n.start = t.start;
          for (const item of t.items) { const li = el('li'); if (item.task) li.append(el('span', item.checked ? '☑ ' : '☐ ')); blocks(item.tokens, li); n.append(li); } break;
        case 'code': {
          n = el('section'); n.className = 'codebox';
          const header = el('div', (t.lang || '代码').split(/\s/)[0]); header.className = 'codebar';
          const copy = el('button', '复制'); copy.type = 'button'; copy.className = 'code-copy';
          copy.onclick = () => {
            const code = n.querySelector('code');
            copyText(copy,code.textContent,code);
          };
          const wrap=el('button','换行'); wrap.type='button'; wrap.setAttribute('aria-pressed','false');
          wrap.onclick=()=>{const on=n.classList.toggle('wrap');wrap.setAttribute('aria-pressed',String(on));};
          const lineNumbers=el('button','行号');lineNumbers.type='button';lineNumbers.setAttribute('aria-pressed','false');
          lineNumbers.title='显示行号；复制、打开和插入仍使用不带行号的原始代码';
          if(t.text.length>100000||t.text.split('\n').length>5000){lineNumbers.disabled=true;lineNumbers.title='代码块过大，暂不显示行号';}
          lineNumbers.onclick=()=>{
            const enabled=!n.classList.contains('line-numbered');
            const code=n.querySelector('code');
            if(code)setCodeLineNumbers(code,enabled,t.lang||'');
            n.classList.toggle('line-numbered',enabled);
            lineNumbers.setAttribute('aria-pressed',String(enabled));
          };
          const fold=el('button','折叠'); fold.type='button'; fold.setAttribute('aria-expanded','true');
          fold.onclick=()=>{const closed=n.classList.toggle('collapsed');fold.textContent=closed?'展开':'折叠';fold.setAttribute('aria-expanded',String(!closed));};
          const open=el('button','打开');open.type='button';open.title='在编辑器中打开这段代码';
          open.onclick=()=>document.dispatchEvent(new CustomEvent('agent-open-code',{detail:n.querySelector('code').textContent}));
          const insert=el('button','插入');insert.type='button';insert.className='code-insert';insert.title='插入到当前文件光标处；有选区时会替换选区';insert.disabled=!!window.AgentBusy;
          insert.onclick=()=>document.dispatchEvent(new CustomEvent('agent-insert-code',{detail:n.querySelector('code').textContent}));
          const actions=el('div');actions.className='code-actions';actions.append(wrap,lineNumbers,fold,open,insert,copy);
          header.append(actions); const pre = el('pre'); pre.append(window.AgentHighlight ? AgentHighlight(t.text, t.lang) : el('code', t.text)); n.append(header, pre); break;
        }
        case 'table': {
          n = el('div'); n.className = 'table-scroll'; const table = el('table');
          const row = (cells, tag) => { const tr = el('tr'); cells.forEach((c, i) => { const cell = el(tag); inline(c.tokens, cell); if (['left','right','center'].includes(t.align[i])) cell.style.textAlign = t.align[i]; tr.append(cell); }); return tr; };
          const head = el('thead'); head.append(row(t.header, 'th')); const body = el('tbody'); t.rows.forEach(r => body.append(row(r,'td'))); table.append(head,body); n.append(table); break;
        }
        default: n = el('p', t.text || t.raw || '');
      }
      parent.append(n);
    }
  }
  function markdown(text) { const n = document.createDocumentFragment(); blocks(marked.lexer(text, {gfm:true}), n); return n; }
  function displayCode(text, language) {
    const pre=el('pre');
    pre.append(window.AgentHighlight ? AgentHighlight(String(text||''),language||'') : el('code',String(text||'')));
    return pre;
  }
  function splitWindowsPath(value) {
    const path=String(value||'').replace(/\//g,'\\');
    let root='',parts=[];
    const drive=/^([a-zA-Z]:)\\?/.exec(path);
    if(drive){root=drive[1].toUpperCase()+'\\';parts=path.slice(drive[0].length).split('\\');}
    else if(path.startsWith('\\\\')){
      const unc=path.slice(2).split('\\').filter(Boolean);
      if(unc.length>=2){root='\\\\'+unc.shift()+'\\'+unc.shift();parts=unc;}
      else {root='\\\\';parts=unc;}
    } else if(path.startsWith('\\')){root='\\';parts=path.slice(1).split('\\');}
    return {root,parts};
  }
  function canonicalWindowsPath(value, base) {
    const raw=String(value||'').trim().replace(/\//g,'\\');
    if(!raw)return '';
    const absolute=/^[a-zA-Z]:\\/.test(raw)||raw.startsWith('\\\\');
    let root='',parts=[];
    if(absolute){const parsed=splitWindowsPath(raw);root=parsed.root;parts=parsed.parts;}
    else if(raw.startsWith('\\')){
      const parsed=splitWindowsPath(base||'');
      root=/^[a-zA-Z]:\\$/.test(parsed.root)?parsed.root:'\\';parts=raw.slice(1).split('\\');
    } else {
      const parsed=splitWindowsPath(base||'');root=parsed.root;parts=parsed.parts.concat(raw.split('\\'));
    }
    const normalized=[];
    for(const part of parts){if(!part||part==='.')continue;if(part==='..'){if(normalized.length)normalized.pop();continue;}normalized.push(part);}
    const prefix=root+(root&&!root.endsWith('\\')?'\\':'');
    return (prefix+normalized.join('\\')).replace(/\\$/,'').toLocaleLowerCase();
  }
  function formatFileDiffSummary(value) {
    const summary=String(value||'');
    const counts=/^\+(\d+) \/ -(\d+) lines$/.exec(summary);
    if(counts)return '+'+counts[1]+' / -'+counts[2]+' 行';
    const labels={
      'Diff unavailable':'差异暂不可用',
      'File deleted':'文件已删除',
      'Diff omitted to keep this review responsive':'变更过大，已跳过逐行比较'
    };
    return labels[summary]||summary;
  }
  function fileUndoMessage(code) {
    const labels={
      editor_dirty:'编辑器里有未保存内容。请先保存或关闭文件，再恢复。',
      busy:'AI 正在处理本轮任务。请等它完成后再撤销，避免覆盖后续写入。',
      stale:'文件在本轮修改后又发生了变化。为避免覆盖新内容，已取消恢复。',
      restore_failed:'恢复失败，文件没有被覆盖。请检查文件是否被占用或只读。',
      unavailable:'这条变更没有可用的安全恢复记录。'
    };
    return labels[code]||'无法安全恢复此文件，请先检查当前文件状态。';
  }
  function permissionMeta(item, data) {
    const card=el('section');card.className='permission-card';
    const tool=String(item.name||'工具操作');
    card.append(el('strong',({Write:'写入文件',Edit:'修改文件',Bash:'执行命令'}[tool]||('需要批准：'+tool))));
    const proposedText=tool==='Write'?data.content:tool==='Edit'?data.new_string:'';
    if(typeof proposedText==='string'&&looksLikeMojibake(proposedText)){
      const warning=el('div');
      warning.className='permission-integrity-warning';warning.setAttribute('role','alert');card.append(warning);
      warning.append(el('span','检测到内容可能有编码错乱，请检查下面的预览再批准。'));
      const rewrite=el('button','拒绝并让 AI 重写');rewrite.type='button';rewrite.className='permission-rewrite';
      rewrite.title='拒绝这次写入，并把编码问题反馈给 AI';
      rewrite.onclick=()=>requestPermission({
        requestId:item.requestId,decision:'deny',
        reason:'你提交的文件内容存在疑似字符编码错乱（例如中文注释出现乱码）。请重新生成并核对完整文件内容，确保中文可读并保持源文件编码；修复前不要重复提交相同文本。'
      });
      warning.append(rewrite);
    }
    const path=String(data.file_path||data.path||'');
    if(path){
      const target=el('div');target.className='permission-target';target.append(el('span','目标文件'),el('code',path));card.append(target);
      if(item.workDir){
        const base=canonicalWindowsPath(item.workDir,''),file=canonicalWindowsPath(path,item.workDir),inside=!!base&&(file===base||file.startsWith(base+'\\'));
        const where=el('div',inside?'位于当前工作目录':'目标位于工作目录之外');
        where.className='permission-scope '+(inside?'inside':'outside');card.append(where);
      }
    }
    if(data.command){
      if(item.workDir){
        const directory=el('div');directory.className='permission-workdir';
        directory.append(el('span','工作目录'),el('code',String(item.workDir)));
        card.append(directory);
      }
      const command=el('pre');command.className='permission-command';command.textContent=String(data.command);card.append(el('h4','将执行的命令'),command);
    }
    if(tool==='Write'&&data.content!==undefined){
      const language=(path.split('.').pop()||'').toLowerCase();card.append(el('h4','将写入的内容'),displayCode(data.content,language));
    } else if(tool==='Edit'){
      if(data.old_string!==undefined){card.append(el('h4','原内容'),displayCode(data.old_string,''));}
      if(data.new_string!==undefined){card.append(el('h4','替换为'),displayCode(data.new_string,''));}
    }
    const extra=el('details');extra.className='permission-raw';extra.append(el('summary','查看完整参数'),displayCode(JSON.stringify(data,null,2),'json'));card.append(extra);
    return card;
  }
  function answerQuestion(item, body, data) {
    const questions=Array.isArray(data.questions)?data.questions:null;
    const heading=el('section');heading.className='permission-card';heading.append(el('strong','需要你补充信息'));body.append(heading);
    if(!questions||questions.length<1||questions.length>4||questions.some(q=>!q||typeof q.question!=='string'||!Array.isArray(q.options)||q.options.length<2||q.options.length>4)){
      body.append(el('p','问题格式无效，无法安全提交答案。'));
      const raw=el('details');raw.append(el('summary','查看收到的内容'),displayCode(item.input,'json'));body.append(raw);
      const deny=el('button','取消问题');deny.type='button';deny.className='permission-deny';deny.onclick=()=>requestPermission({requestId:item.requestId,decision:'deny'});body.append(deny);return;
    }
    const form=el('form');form.className='question-form';const controls=[];
    questions.forEach((q,index)=>{
      const field=el('fieldset');field.append(el('legend',q.header||('问题 '+(index+1))),el('p',q.question));
      const name='question-'+item.requestId+'-'+index;const choices=[];
      for(const option of q.options){
        const label=el('label');const input=el('input');input.type=q.multiSelect?'checkbox':'radio';input.name=name;input.value=String(option.label||'');
        label.append(input,el('span',String(option.label||'选项')));
        if(option.description)label.append(el('small',String(option.description)));
        field.append(label);choices.push({input,value:String(option.label||'')});
      }
      const otherLabel=el('label');const other=el('input');other.type=q.multiSelect?'checkbox':'radio';other.name=name;other.value='__other__';otherLabel.append(other,el('span','其他'));field.append(otherLabel);
      const custom=el('input');custom.type='text';custom.className='question-other';custom.placeholder='填写自定义回答';custom.setAttribute('aria-label','自定义回答');custom.hidden=true;field.append(custom);
      controls.push({question:q.question,choices,other,custom});
      field.addEventListener('change',()=>{custom.hidden=!other.checked;validate();});custom.addEventListener('input',validate);form.append(field);
    });
    const errorBox=el('p');errorBox.className='permission-error';errorBox.textContent=item.output||'';form.append(errorBox);
    const actions=el('div');actions.className='permission-actions';
    const deny=el('button','取消');deny.type='button';deny.className='permission-deny';
    const submit=el('button','提交回答');submit.type='submit';submit.className='permission-allow';submit.disabled=true;actions.append(deny,submit);form.append(actions);
    function values(){
      const result={};
      for(const c of controls){
        const picked=c.choices.filter(o=>o.input.checked).map(o=>o.value);
        if(c.other.checked){const custom=c.custom.value.trim();if(!custom)return null;picked.push(custom);}
        if(!picked.length)return null;
        result[c.question]=picked.join(', ');
      }
      return result;
    }
    function validate(){submit.disabled=!values();}
    form.validateAnswers=validate;
    deny.onclick=()=>requestPermission({requestId:item.requestId,decision:'deny'});
    form.onsubmit=e=>{e.preventDefault();const answers=values();if(!answers)return;requestPermission({requestId:item.requestId,decision:'answer',answers:JSON.stringify(answers)});form.classList.add('submitting');form.setAttribute('aria-busy','true');for(const control of form.elements)control.disabled=true;};
    body.append(form);
  }
  function approvalCard(item, body) {
    let data={};try{data=JSON.parse(item.input||'{}');}catch{}
    body.append(permissionMeta(item,data));
    const error=el('p');error.className='permission-error';error.textContent=item.output||'';body.append(error);
    const actions=el('div');actions.className='permission-actions';
    const deny=el('button','拒绝');deny.type='button';deny.className='permission-deny';
    const allow=el('button','允许一次');allow.type='button';allow.className='permission-allow';
    deny.onclick=()=>requestPermission({requestId:item.requestId,decision:'deny'});
    allow.onclick=()=>requestPermission({requestId:item.requestId,decision:'allow'});
    actions.append(deny,allow);body.append(actions);
  }
  function renderPermission(item, body) {
    if(item.name==='AskUserQuestion'){
      let data={};try{data=JSON.parse(item.input||'{}');}catch{}
      answerQuestion(item,body,data);
    } else approvalCard(item,body);
  }
  function renderSubmittedAnswers(item, body) {
    let data={};try{data=JSON.parse(item.input||'{}');}catch{}
    const answers=data.answers&&typeof data.answers==='object'?data.answers:{};
    body.append(el('h4','已提交回答'));
    const summary=Object.keys(answers).map(question=>question+'\n  '+String(answers[question])).join('\n\n');
    body.append(el('pre',summary||'回答已提交'));
    if(item.output)body.append(el('p',item.output));
  }
  function reconcile(parent, fresh) {
    const incoming=[...fresh.childNodes];
    incoming.forEach((next,index)=>{
      const current=parent.childNodes[index];
      if (!current) {parent.append(next);return;}
      if (current.isEqualNode(next)) return;
      if (current.nodeType!==next.nodeType || current.nodeName!==next.nodeName) {current.replaceWith(next);return;}
      if (current.nodeType===Node.TEXT_NODE) {current.data=next.data;return;}
      if (current.classList?.contains('codebox') && next.classList.contains('codebox')) {
        // Preserve code controls, collapsed/wrap/line-number state and horizontal reading position.
        const pre=current.querySelector('pre'), left=pre.scrollLeft, top=pre.scrollTop;
        const lineNumbers=current.classList.contains('line-numbered');
        current.querySelector('.codebar').firstChild.textContent=next.querySelector('.codebar').firstChild.textContent;
        if(lineNumbers){
          const code=next.querySelector('code');
          if(code){
            pre.replaceChildren(code);
            setCodeLineNumbers(code,true,next.querySelector('.codebar').firstChild.textContent);
          } else reconcile(pre,next.querySelector('pre'));
        } else reconcile(pre,next.querySelector('pre'));
        pre.scrollLeft=left;pre.scrollTop=top;return;
      }
      if (current.nodeType===Node.ELEMENT_NODE) {
        for(const attribute of [...current.attributes]) if(!next.hasAttribute(attribute.name)) current.removeAttribute(attribute.name);
        for(const attribute of next.attributes) current.setAttribute(attribute.name,attribute.value);
      }
      reconcile(current,next);
    });
    while(parent.childNodes.length>incoming.length) parent.lastChild.remove();
  }
  class MessageView {
    constructor(reader, root, jump) {
      this.reader = reader; this.root = root; this.jump = jump; this.items = new Map(); this.pending = new Map(); this.follow = true; this.busy = false;
      reader.addEventListener('scroll', () => { this.follow = reader.scrollHeight-reader.scrollTop-reader.clientHeight < 48; this.positionJump(); });
      jump.onclick = () => { this.follow = true; reader.scrollTop = reader.scrollHeight; this.positionJump(); };
      document.addEventListener('agent-permission-error',e=>this.permissionError(e.detail||{}));
      document.addEventListener('agent-file-undo-result',e=>this.fileUndoResult(e.detail||{}));
      this.positionJump();
      document.addEventListener('selectionchange',()=>{
        if (document.getSelection().isCollapsed && this.pending.size) this.schedule();
      });
    }
    setBusy(value) {
      this.busy=!!value;
      for(const button of this.root.querySelectorAll('.file-change-undo')) {
        if(this.busy&&button.dataset.confirm==='yes') {
          clearTimeout(button._confirmTimer);
          delete button.dataset.confirm;
          button.textContent='撤销本轮改动';
        }
        this.syncUndoButton(button);
      }
    }
    syncUndoButton(button) {
      const terminal=['restored','stale'].includes(button.dataset.undoState);
      const pending=button.dataset.undoPending==='yes';
      button.disabled=this.busy||pending||terminal;
      button.title=this.busy
        ? 'AI 正在处理本轮任务，请等完成后再撤销。'
        : '仅当文件仍保持本轮 AI 写入的内容时才会恢复';
    }
    reset() { this.pending.clear(); this.items.clear(); this.root.replaceChildren(); this.follow = true; this.jump.hidden = true; }
    positionJump() {
      const readerRect=this.reader.getBoundingClientRect(), footer=document.querySelector('footer');
      const footerTop=footer?footer.getBoundingClientRect().top:window.innerHeight;
      const height=this.jump.offsetHeight||36, top=Math.min(readerRect.bottom-height-8,footerTop-height-8);
      this.jump.style.top=Math.max(readerRect.top+8,top)+'px';
      this.jump.style.right=Math.max(8,window.innerWidth-readerRect.right+12)+'px';
      this.jump.style.bottom='auto';
      this.jump.hidden=this.follow||readerRect.height<height+16;
    }
    layoutChanged() {
      if(this.follow)this.reader.scrollTop=this.reader.scrollHeight;
      this.positionJump();
    }
    permissionError(message) {
      const requestId=String(message.requestId||'');
      for(const entry of this.items.values()){
        if(entry.permissionRequestId!==requestId)continue;
        const form=entry.body.querySelector('.question-form');
        if(form){
          form.classList.remove('submitting');form.removeAttribute('aria-busy');
          for(const control of form.elements)control.disabled=false;
          if(form.validateAnswers)form.validateAnswers();
        }
        const error=entry.body.querySelector('.permission-error');
        if(error)error.textContent=message.message||'提交失败，请检查回答后重试。';
      }
    }
    fileUndoResult(message) {
      const token=String(message.undoToken||'');
      for(const entry of this.items.values()){
        const button=[...entry.body.querySelectorAll('.file-change-undo')].find(n=>n.dataset.undoToken===token);
        if(!button)continue;
        let status=entry.body.querySelector('.file-undo-status');
        if(!status){
          status=el('div');status.className='file-undo-status';
          const card=entry.body.querySelector('.file-change-card');
          if(card)card.append(status);else entry.body.append(status);
        }
        if(message.success){
          button.dataset.undoState='restored';button.textContent='已恢复';
          status.textContent='已恢复到本轮 AI 修改前的内容。';status.classList.add('restored');
        }else if(message.stale){
          button.dataset.undoState='stale';button.textContent='文件已变化';
          status.textContent=fileUndoMessage('stale');
        }else{
          delete button.dataset.undoState;button.textContent='撤销本轮改动';
          delete button.dataset.confirm;
          status.textContent=fileUndoMessage(message.errorCode);
        }
        delete button.dataset.undoPending;
        this.syncUndoButton(button);
        break;
      }
    }
    upsert(item) {
      if (!item || typeof item.id !== 'string' || !['user','assistant','tool','system','file-change'].includes(item.kind)) return;
      this.pending.set(item.id, {...item});
      this.schedule();
    }
    schedule() {
      if (!this.frame) this.frame = requestAnimationFrame(() => { this.frame = 0; this.flush(); });
    }
    flush() {
      const reader = this.reader, top = reader.scrollTop;
      const anchor = [...this.root.children].find(n => n.getBoundingClientRect().bottom > reader.getBoundingClientRect().top);
      const offset = anchor ? anchor.getBoundingClientRect().top : 0;
      for (const [id, item] of this.pending) {
        let entry = this.items.get(id);
        if (entry && entry.kind !== item.kind) continue;
        if (!entry) {
          const node = el(item.kind === 'tool'||item.kind==='file-change' ? 'details' : 'article'); node.className = item.kind; node.dataset.id = id;
          if(item.kind==='tool'&&item.status==='approval')node.open=true;
          const body = el('div'); body.className = 'body';
          let title;
          if (item.kind === 'tool'||item.kind==='file-change') { title = el('summary'); node.append(title); }
          node.append(body); entry = {node,body,title,kind:item.kind,text:null};
          if(item.kind==='assistant') {
            const actions=el('div');actions.className='assistant-actions';
            const copy=el('button','复制回答');copy.type='button';copy.className='assistant-copy';
            copy.disabled=true;
            copy.title='复制整条 AI 回答（Markdown）';copy.setAttribute('aria-label','复制整条 AI 回答');
            copy.onclick=()=>copyText(copy,entry.text,entry.body,'回答');
            actions.append(copy);node.append(actions);entry.copyButton=copy;
          }
          this.root.append(node); this.items.set(id,entry);
        }
        if (entry.title && item.kind==='file-change') {
          const labels={Added:'新增',Modified:'修改',Renamed:'重命名',Deleted:'删除','Written/edited':'已写入/编辑'};
          const title=el('span',(labels[item.fileState]||item.fileState||'文件变化')+' · '+(item.path||'未知文件'));
          title.className='file-change-title';
          entry.title.replaceChildren(title);
          if(item.diffSummary){const summary=el('span',formatFileDiffSummary(item.diffSummary));summary.className='file-change-count';entry.title.append(summary);}
          entry.node.classList.toggle('failed',item.fileState==='Deleted');
        } else if (entry.title) {
          const states={running:'执行中',done:'已完成',failed:'失败',approval:'等待处理',authorized:'已允许 · 等待执行',answered:'已回答 · 等待继续',denied:'已拒绝',interrupted:'请求已失效'};
          const rawName=(item.name||'工具调用').replace(/\s*\[(Done|Failed)\]/g,'');
          entry.title.textContent = (toolLabels[rawName]||rawName) + (item.status ? ' · ' + (states[item.status]||item.status) : '');
          entry.node.classList.toggle('failed',item.status==='failed');
          entry.node.classList.toggle('approval',item.status==='approval');
        }
        const text = item.kind==='tool' ? JSON.stringify([item.text,item.input,item.output,item.requestId,item.workDir,item.status,item.name]) : item.kind==='file-change' ? JSON.stringify([item.text,item.path,item.fileState,item.diffSummary,item.canOpen,item.undoToken,item.canUndo,item.undoState]) : item.kind==='user' ? JSON.stringify([item.text,item.contextSummary,item.contextPayload]) : String(item.text || '');
        if(item.kind==='system') {
          const message=String(item.text||'');
          entry.node.classList.toggle('failed',/^\s*\[(?:Error|Claude failure)\]/i.test(message));
          entry.node.classList.toggle('retrying',/\bAPI retry\b/i.test(message));
          entry.node.classList.toggle('warning',/^\s*\[(?:Rate limit|Notice)\]/i.test(message));
        }
        const selection=document.getSelection();
        if (entry.text!==text && !selection.isCollapsed && selection.containsNode(entry.body,true)) continue;
        if (entry.text !== text) {
          entry.text = text;
          if(entry.copyButton)entry.copyButton.disabled=!text;
          if (item.kind === 'assistant') reconcile(entry.body,markdown(text));
          else if (item.kind === 'tool' && item.status==='approval' && item.requestId) {
            if(entry.permissionRequestId===item.requestId){
              const error=entry.body.querySelector('.permission-error');if(error)error.textContent=item.output||'';
            } else {
              entry.body.replaceChildren();renderPermission(item,entry.body);entry.permissionRequestId=item.requestId;
            }
          } else if (item.kind === 'tool') {
            entry.permissionRequestId='';
            const content=document.createDocumentFragment();
            if(item.status==='answered'&&item.name==='AskUserQuestion')renderSubmittedAnswers(item,content);
            else {
              if (item.input) content.append(el('h4','输入'),el('pre',item.input));
              if (item.output) content.append(el('h4','输出'),el('pre',item.output));
            }
            if (!item.input && !item.output) content.append(el('pre',item.text||''));
            reconcile(entry.body,content);
          }
          else if(item.kind==='file-change') {
            const card=el('div');card.className='file-change-card';
            const meta=el('div',formatFileDiffSummary(item.diffSummary)||'变更预览');meta.className='file-change-meta';
            const pre=el('pre');pre.className='file-diff';
            const code=el('code');
            let diffText=String(item.text||'');
            const fallbackText={
              'This change came from a shell or unsupported file tool. Open the current file to review it.':'此更改来自命令行或未识别的文件工具，请打开当前文件审阅。',
              'The file was deleted during this turn; there is no current file to open.':'本轮删除了此文件，目前已无文件可打开。'
            };
            diffText=fallbackText[diffText]||diffText;
            let oldLine=1,newLine=1;
            for(const line of diffText.replace(/\r/g,'').split('\n')) {
              const removed=line.startsWith('- '),added=line.startsWith('+ '),context=line.startsWith('  ');
              const row=el('span');row.className='diff-line '+(added?'added':removed?'removed':'context');row.textContent=line||' ';
              if(removed){row.dataset.line=String(oldLine++);row.title='原文件第'+row.dataset.line+'行';}
              else if(added){row.dataset.line=String(newLine++);row.title='修改后第'+row.dataset.line+'行';}
              else if(context){row.dataset.line=String(newLine++);row.title='修改后第'+row.dataset.line+'行';oldLine++;}
              code.append(row,document.createTextNode('\n'));
            }
            pre.append(code);card.append(meta,pre);
            if(/^\+\d+ \/ -\d+ lines$/.test(String(item.diffSummary||''))){
              const copy=el('button','复制差异');copy.type='button';copy.className='file-change-copy';
              copy.onclick=()=>copyText(copy,diffText,code,'差异');card.append(copy);
            }
            const open=el('button',item.canOpen?'在编辑器中打开':'文件当前不可打开');open.type='button';open.className='file-change-open';open.disabled=!item.canOpen;
            open.onclick=e=>{e.preventDefault();e.stopPropagation();if(item.canOpen)document.dispatchEvent(new CustomEvent('agent-open-file',{detail:item.path}));};
            const actions=el('div');actions.className='file-change-actions';
            const copyButton=card.querySelector('.file-change-copy');
            if(copyButton)actions.append(copyButton);
            if(item.canUndo&&item.undoToken){
              const undo=el('button','撤销本轮改动');undo.type='button';
              undo.className='file-change-undo';undo.dataset.undoToken=item.undoToken;
              this.syncUndoButton(undo);
              undo.onclick=e=>{
                e.preventDefault();e.stopPropagation();
                if(this.busy)return;
                if(undo.dataset.confirm!=='yes'){
                  undo.dataset.confirm='yes';undo.textContent='再次点击恢复';
                  clearTimeout(undo._confirmTimer);
                  undo._confirmTimer=setTimeout(()=>{
                    if(!undo.isConnected)return;
                    delete undo.dataset.confirm;
                    undo.textContent='撤销本轮改动';
                  },5000);
                  return;
                }
                clearTimeout(undo._confirmTimer);
                undo.dataset.undoPending='yes';undo.disabled=true;undo.textContent='正在恢复…';
                document.dispatchEvent(new CustomEvent('agent-undo-file',{
                  detail:{undoToken:item.undoToken}
                }));
              };
              actions.append(undo);
            }
            if(item.undoState==='restored'){
              const restored=el('span','已恢复');restored.className='file-change-undo-state restored';actions.append(restored);
            } else if(item.undoState==='stale'){
              const stale=el('span','文件已变化，已禁用恢复');stale.className='file-change-undo-state stale';actions.append(stale);
            }
            actions.append(open);card.append(actions);
            if(item.undoState==='restored'){
              const note=el('div','已恢复到本轮 AI 修改前的内容。');note.className='file-undo-status restored';card.append(note);
            } else if(item.undoState==='stale'){
              const note=el('div',fileUndoMessage('stale'));note.className='file-undo-status';note.setAttribute('role','status');card.append(note);
            }
            const content=document.createDocumentFragment();content.append(card);
            reconcile(entry.body,content);
          }
          else if(item.kind==='user') {
            const content=document.createDocumentFragment();
            const message=el('div',item.text||'');message.className='user-text';content.append(message);
            if(item.contextSummary) {
              const meta=el('div');meta.className='context-summary';
              meta.setAttribute('aria-label','本次请求附带的 IDE 上下文');
              const summary=el('span',formatContextSummary(item.contextSummary));
              summary.title=summary.textContent;
              meta.append(el('span','IDE 上下文'),summary);content.append(meta);
            }
            if(item.contextPayload) {
              const details=el('details');details.className='user-context';
              const summary=el('summary','查看本次 AI 看到的代码与诊断 · '+item.contextPayload.length.toLocaleString()+' 字符');
              const pre=el('pre');pre.textContent=item.contextPayload;
              details.append(summary,pre);content.append(details);
            }
            reconcile(entry.body,content);
          }
          else if(item.kind==='system') entry.body.textContent = formatSystemMessage(text);
          else entry.body.textContent = text;
        }
        this.pending.delete(id);
      }
      if (this.follow) reader.scrollTop = reader.scrollHeight;
      else if (anchor && anchor.isConnected) reader.scrollTop = top + anchor.getBoundingClientRect().top-offset;
      this.positionJump();
    }
  }
  window.AgentMessages = {markdown, MessageView, formatContextSummary};
})();
