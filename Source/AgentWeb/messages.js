/* Marked supplies tokens only. Untrusted HTML never enters an HTML sink. */
(() => {
  'use strict';
  const el = (tag, text) => { const n = document.createElement(tag); if (text !== undefined) n.textContent = text; return n; };
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
        case 'link':
          n = el('span'); inline(t.tokens, n); n.title = t.href; break;
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
          const copy = el('button', '复制'); copy.type = 'button';
          copy.onclick = async () => {
            try {await navigator.clipboard.writeText(n.querySelector('code').textContent);copy.textContent='已复制';}
            catch {copy.textContent='请选中复制';}
            setTimeout(()=>copy.textContent='复制',1800);
          };
          const wrap=el('button','换行'); wrap.type='button'; wrap.setAttribute('aria-pressed','false');
          wrap.onclick=()=>{const on=n.classList.toggle('wrap');wrap.setAttribute('aria-pressed',String(on));};
          const fold=el('button','折叠'); fold.type='button'; fold.setAttribute('aria-expanded','true');
          fold.onclick=()=>{const closed=n.classList.toggle('collapsed');fold.textContent=closed?'展开':'折叠';fold.setAttribute('aria-expanded',String(!closed));};
          const open=el('button','打开');open.type='button';open.title='在编辑器中打开这段代码';
          open.onclick=()=>document.dispatchEvent(new CustomEvent('agent-open-code',{detail:n.querySelector('code').textContent}));
          const actions=el('div');actions.className='code-actions';actions.append(wrap,fold,open,copy);
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
  function permissionMeta(item, data) {
    const card=el('section');card.className='permission-card';
    const tool=String(item.name||'工具操作');
    card.append(el('strong',({Write:'写入文件',Edit:'修改文件',Bash:'执行命令'}[tool]||('需要批准：'+tool))));
    const path=String(data.file_path||data.path||'');
    if(path){
      const target=el('div');target.className='permission-target';target.append(el('span','目标文件'),el('code',path));card.append(target);
      if(item.workDir){
        const norm=value=>String(value).replace(/\//g,'\\').replace(/\\+$/,'').toLocaleLowerCase();
        const base=norm(item.workDir),file=norm(path),inside=file===base||file.startsWith(base+'\\');
        const where=el('div',inside?'位于当前工作目录':'目标位于工作目录之外');
        where.className='permission-scope '+(inside?'inside':'outside');card.append(where);
      }
    }
    if(data.command){const command=el('pre');command.className='permission-command';command.textContent=String(data.command);card.append(el('h4','将执行的命令'),command);}
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
    deny.onclick=()=>requestPermission({requestId:item.requestId,decision:'deny'});
    form.onsubmit=e=>{e.preventDefault();const answers=values();if(!answers)return;requestPermission({requestId:item.requestId,decision:'answer',answers:JSON.stringify(answers)});form.classList.add('submitting');for(const control of form.elements)control.disabled=true;};
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
  function reconcile(parent, fresh) {
    const incoming=[...fresh.childNodes];
    incoming.forEach((next,index)=>{
      const current=parent.childNodes[index];
      if (!current) {parent.append(next);return;}
      if (current.isEqualNode(next)) return;
      if (current.nodeType!==next.nodeType || current.nodeName!==next.nodeName) {current.replaceWith(next);return;}
      if (current.nodeType===Node.TEXT_NODE) {current.data=next.data;return;}
      if (current.classList?.contains('codebox') && next.classList.contains('codebox')) {
        // Preserve code controls, collapsed/wrap state and horizontal reading position.
        const pre=current.querySelector('pre'), left=pre.scrollLeft, top=pre.scrollTop;
        current.querySelector('.codebar').firstChild.textContent=next.querySelector('.codebar').firstChild.textContent;
        reconcile(pre,next.querySelector('pre'));pre.scrollLeft=left;pre.scrollTop=top;return;
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
      this.reader = reader; this.root = root; this.jump = jump; this.items = new Map(); this.pending = new Map(); this.follow = true;
      reader.addEventListener('scroll', () => { this.follow = reader.scrollHeight-reader.scrollTop-reader.clientHeight < 48; jump.hidden = this.follow; });
      jump.onclick = () => { this.follow = true; reader.scrollTop = reader.scrollHeight; jump.hidden = true; };
      document.addEventListener('selectionchange',()=>{
        if (document.getSelection().isCollapsed && this.pending.size) this.schedule();
      });
    }
    reset() { this.pending.clear(); this.items.clear(); this.root.replaceChildren(); this.follow = true; this.jump.hidden = true; }
    upsert(item) {
      if (!item || typeof item.id !== 'string' || !['user','assistant','tool','system'].includes(item.kind)) return;
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
          const node = el(item.kind === 'tool' ? 'details' : 'article'); node.className = item.kind; node.dataset.id = id;
          if(item.kind==='tool'&&item.status==='approval')node.open=true;
          const body = el('div'); body.className = 'body';
          let title;
          if (item.kind === 'tool') { title = el('summary'); node.append(title); }
          node.append(body); this.root.append(node); entry = {node,body,title,kind:item.kind,text:null}; this.items.set(id,entry);
        }
        if (entry.title) {
          const states={running:'执行中',done:'已完成',failed:'失败',approval:'等待处理',denied:'已拒绝',interrupted:'请求已失效'};
          entry.title.textContent = (item.name || '工具调用').replace(/\s*\[(Done|Failed)\]/g,'') + (item.status ? ' · ' + (states[item.status]||item.status) : '');
          entry.node.classList.toggle('failed',item.status==='failed');
          entry.node.classList.toggle('approval',item.status==='approval');
        }
        const text = item.kind==='tool' ? JSON.stringify([item.text,item.input,item.output,item.requestId,item.workDir,item.status,item.name]) : String(item.text || '');
        const selection=document.getSelection();
        if (entry.text!==text && !selection.isCollapsed && selection.containsNode(entry.body,true)) continue;
        if (entry.text !== text) {
          entry.text = text;
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
            if (item.input) content.append(el('h4','输入'),el('pre',item.input));
            if (item.output) content.append(el('h4','输出'),el('pre',item.output));
            if (!item.input && !item.output) content.append(el('pre',item.text||''));
            reconcile(entry.body,content);
          }
          else entry.body.textContent = text;
        }
        this.pending.delete(id);
      }
      if (this.follow) reader.scrollTop = reader.scrollHeight;
      else if (anchor && anchor.isConnected) reader.scrollTop = top + anchor.getBoundingClientRect().top-offset;
      this.jump.hidden = this.follow;
    }
  }
  window.AgentMessages = {markdown, MessageView};
})();
