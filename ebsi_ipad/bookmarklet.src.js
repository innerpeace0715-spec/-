(function(){
var RE=/https?:\/\/[^'"\s)]+?\.(?:pdf|hwp|hwpx|mp3|zip)/gi;
var KEY='ebsiDL';
var docs=[document];
for(var i=0;i<frames.length;i++){try{docs.push(frames[i].document);}catch(e){}}
var found=[],dbg=[];
docs.forEach(function(d){
d.querySelectorAll('a,button,[onclick],[data-url],[data-href]').forEach(function(el){
var raw=[el.getAttribute('href'),el.getAttribute('onclick'),el.getAttribute('data-url'),el.getAttribute('data-href')].filter(Boolean).join(' ');
var txt=(el.innerText||el.title||'').trim();
var m=raw.match(RE);
if(!m){if(/문제|해설|정답|듣기/.test(txt)&&dbg.length<5)dbg.push(txt+' => '+raw.slice(0,200));return;}
var row=el.closest('li,tr')||el.parentElement;var t=row?(row.innerText||'').trim().split('\n')[0]:'';
m.forEach(function(u){found.push({u:u,t:(t+' '+txt).trim()});});
});});
var old=[];try{old=JSON.parse(localStorage.getItem(KEY)||'[]');}catch(e){}
var seen={};var all=[];
old.concat(found).forEach(function(x){if(!seen[x.u]){seen[x.u]=1;all.push(x);}});
try{localStorage.setItem(KEY,JSON.stringify(all));}catch(e){}
var p=document.getElementById('ebsiDLp');if(p)p.remove();
p=document.createElement('div');p.id='ebsiDLp';
p.style.cssText='position:fixed;z-index:2147483647;top:10px;left:10px;right:10px;max-height:80vh;overflow:auto;background:#fff;color:#111;border:2px solid #1a5fd0;border-radius:12px;padding:14px;font:15px/1.5 sans-serif;box-shadow:0 6px 30px rgba(0,0,0,.35)';
var h='<b>이 페이지 '+found.length+'개 / 누적 '+all.length+'개</b><br>';
h+='<button id="ebsiC" style="margin:8px 6px 8px 0;padding:10px 14px;font-size:15px;background:#1a5fd0;color:#fff;border:0;border-radius:8px">누적 링크 전부 복사</button>';
h+='<button id="ebsiR" style="margin:8px 6px 8px 0;padding:10px 14px;font-size:15px;border-radius:8px">누적 비우기</button>';
h+='<button id="ebsiX" style="margin:8px 0;padding:10px 14px;font-size:15px;border-radius:8px">닫기</button>';
if(!found.length&&dbg.length){h+='<div style="color:#b00;font-size:13px;margin:6px 0">링크를 못 찾음. 이 화면 캡처해서 보내주세요:<br>'+dbg.map(function(s){return s.replace(/</g,'&lt;');}).join('<br>')+'</div>';}
h+='<ol style="padding-left:20px;margin:6px 0">';
found.forEach(function(x){h+='<li><a href="'+x.u+'" target="_blank" style="color:#1a5fd0">'+(x.t||x.u).replace(/</g,'&lt;')+'</a></li>';});
h+='</ol>';
p.innerHTML=h;document.body.appendChild(p);
document.getElementById('ebsiX').onclick=function(){p.remove();};
document.getElementById('ebsiR').onclick=function(){localStorage.removeItem(KEY);p.remove();alert('비웠습니다');};
document.getElementById('ebsiC').onclick=function(){
var txt=all.map(function(x){return x.u;}).join('\n');
var done=function(){alert(all.length+'개 복사됨. 단축어 실행하세요');};
if(navigator.clipboard&&navigator.clipboard.writeText){navigator.clipboard.writeText(txt).then(done,function(){fb(txt);});}else fb(txt);
function fb(s){var ta=document.createElement('textarea');ta.value=s;document.body.appendChild(ta);ta.select();document.execCommand('copy');ta.remove();done();}
};
})();
