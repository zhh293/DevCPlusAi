(() => {
  'use strict';
  // Owns review selection and preview DOM. Message storage stays with MessageView.
  class ChangeReview {
    constructor(element, getEntry) {
      this.element=element;
      this.getEntry=getEntry;
      this.selectedChange='';
    }
    render(items) {
      const $=this.element;
      const {files,operations,added,removed,knownDiffs}=AgentMessages.summarizeFileChanges(items);
      if(!files.has(this.selectedChange)){this.selectedChange='';$('change-preview').replaceChildren();}
      const count=files.size,button=$('changes');
      button.hidden=count===0;
      $('changes-count').textContent=count>99?'99+':String(count);
      button.setAttribute('aria-label',count?'查看本次对话改动，'+count+' 个文件':'查看本次对话的文件改动');
      if(!count){$('changes-panel').hidden=true;button.setAttribute('aria-expanded','false');$('change-list').replaceChildren();$('change-preview').replaceChildren();return;}
      $('changes-summary').textContent=count+' 个文件 · '+operations+' 项改动'+(knownDiffs?' · +'+added+' / −'+removed+' 行':'');
      $('changes-note').textContent='选择文件查看改动，不影响对话阅读。'+(knownDiffs<operations?' 部分文件仅记录了修改结果。':'');
      const fragment=document.createDocumentFragment();
      for(const file of files.values()) {
        const row=document.createElement('button');row.type='button';row.className='change-entry';row.dataset.targetId=file.latest.id;row.title=file.path;
        const pathText=document.createElement('span');pathText.className='change-entry-path';pathText.textContent=file.path;
        row.setAttribute('aria-pressed',String(file.key===this.selectedChange));
        const state=AgentMessages.fileStateLabel(file.latest);
        const diff=AgentMessages.parseDiffCounts(file.latest.diffSummary);
        const detail=[state,file.count>1?file.count+' 次改动':'',diff?'+'+diff.added+' / −'+diff.removed+' 行':file.latest.diffSummary==='Diff unavailable'?'查看当前文件':''].filter(Boolean).join(' · ');
        const meta=document.createElement('span');meta.className='change-entry-meta';meta.textContent=detail;
        row.append(pathText,meta);
        row.onclick=()=>{
          const entry=this.getEntry(row.dataset.targetId);
          if(!entry)return;
          this.selectedChange=file.key;
          for(const button of $('change-list').querySelectorAll('button'))button.setAttribute('aria-pressed',String(button===row));
          $('change-preview').replaceChildren(entry.node);
          entry.node.open=true;
          entry.title?.focus({preventScroll:true});
        };
        fragment.append(row);
        if(file.key===this.selectedChange){
          const entry=this.getEntry(file.latest.id);
          if(entry&&$('change-preview').firstChild!==entry.node){$('change-preview').replaceChildren(entry.node);entry.node.open=true;}
        }
      }
      $('change-list').replaceChildren(fragment);
    }
  }
  window.AgentChangeReview=ChangeReview;
})();
