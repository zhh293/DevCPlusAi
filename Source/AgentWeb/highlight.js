/* Small offline lexer. Tokens become text nodes, never executable HTML. */
(() => {
  'use strict';
  const aliases = {c:'cpp',cc:'cpp',cxx:'cpp','c++':'cpp',hpp:'cpp',h:'cpp',js:'javascript',jsx:'javascript',ts:'javascript',typescript:'javascript',py:'python',sh:'shell',bash:'shell',zsh:'shell'};
  const keywords = new Set(('alignas alignof asm auto bool break case catch char char8_t char16_t char32_t class concept const consteval constexpr constinit const_cast continue co_await co_return co_yield decltype default delete do double dynamic_cast else enum explicit export extern float for friend goto if inline int long mutable namespace new noexcept nullptr operator private protected public register reinterpret_cast requires return short signed sizeof static static_assert static_cast struct switch template this thread_local throw try typedef typeid typename union unsigned using virtual void volatile wchar_t while let var function async await yield import from extends implements interface package instanceof typeof of in def lambda pass with as elif except finally raise global nonlocal assert del and or not is then fi done esac function').split(' '));
  const literals = new Set(['true','false','null','undefined','True','False','None','NULL']);
  const types = new Set(['string','wstring','vector','map','unordered_map','set','size_t','std','array','unique_ptr','shared_ptr','cout','cin','endl','printf','scanf','print','console']);
  const languageKeywords = {
    python:new Set('False None True and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield'.split(' ')),
    javascript:new Set('async await break case catch class const continue debugger default delete do else export extends finally for function if import in instanceof let new return static super switch this throw try typeof var void while with yield interface implements type'.split(' ')),
    shell:new Set('if then else elif fi for in do done case esac while until function select time'.split(' ')),
    json:new Set()
  };
  window.AgentHighlight = (source, label) => {
    const code = document.createElement('code');
    let language = String(label || '').trim().split(/\s/)[0].toLowerCase();
    language = aliases[language] || language;
    if (!language && /#include\s*[<"]|\b(?:std::|int\s+main\s*\()/.test(source)) language='cpp';
    if (!['cpp','javascript','python','json','shell'].includes(language) || source.length > 100000) {code.textContent=source;return code;}
    code.dataset.language=language;
    const hashComment=language==='python'||language==='shell';
    const pattern = /R"([^\s()\\]{0,16})\([\s\S]*?\)\1"|\/\*[\s\S]*?(?:\*\/|$)|\/\/[^\r\n]*|"""[\s\S]*?(?:"""|$)|'''[\s\S]*?(?:'''|$)|"(?:\\[\s\S]|[^"\\])*"?|'(?:\\[\s\S]|[^'\\])*'?|`(?:\\[\s\S]|[^`\\])*`?|#[^\r\n]*|\b(?:0[xX][\da-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)[uUlLfF]*\b|\b[A-Za-z_$][\w$]*\b|[{}()[\];,.]|[+*/%=!<>?:&|~^-]+/g;
    let end=0;
    const hashPattern = /"""[\s\S]*?(?:"""|$)|'''[\s\S]*?(?:'''|$)|"(?:\\[\s\S]|[^"\\])*"?|'(?:\\[\s\S]|[^'\\])*'?|`(?:\\[\s\S]|[^`\\])*`?|#[^\r\n]*|\b(?:0[xX][\da-fA-F]+|0[bB][01]+|\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b|\b[A-Za-z_$][\w$]*\b|[{}()[\];,.]|[+*/%=!<>?:&|~^-]+/g;
    for (const match of source.matchAll(hashComment ? hashPattern : pattern)) {
      code.append(document.createTextNode(source.slice(end,match.index)));
      const text=match[0]; let kind='';
      if ((!hashComment && (text.startsWith('//')||text.startsWith('/*')))||(hashComment&&text[0]==='#')) kind='comment';
      else if (text[0]==='#') kind='directive';
      else if (/^(?:R"|["'`])/.test(text)) kind='string';
      else if (/^\d/.test(text)) kind='number';
      else if (literals.has(text)) kind='literal';
      else if ((languageKeywords[language] || keywords).has(text)) kind='keyword';
      else if (types.has(text)) kind='type';
      else if (/^[A-Za-z_$]/.test(text)&&/^\s*\(/.test(source.slice(match.index+text.length))) kind='function';
      else if (/^[{}()[\];,.]$/.test(text)) kind='punctuation';
      else if (/^[+*/%=!<>?:&|~^-]+$/.test(text)) kind='operator';
      if (kind) {const span=document.createElement('span');span.className='syntax-'+kind;span.textContent=text;code.append(span);} else code.append(document.createTextNode(text));
      end=match.index+text.length;
    }
    code.append(document.createTextNode(source.slice(end)));
    return code;
  };
})();
