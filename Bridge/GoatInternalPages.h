#pragma once

#include <string>

inline std::string GoatNewTabHTML() {
  return R"PAGE(<!doctype html><html><head><meta charset="utf-8"><title>New Tab</title>
<style>
:root{--bg:#ffffff;--fg:#16181d;--dim:#6b7280;--pill:rgba(0,0,0,.05);--border:rgba(0,0,0,.08)}
@media (prefers-color-scheme:dark){:root{--bg:#1b1e26;--fg:#e8eaf0;--dim:#9aa1b2;--pill:rgba(255,255,255,.06);--border:rgba(255,255,255,.09)}}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
body{font-family:-apple-system,system-ui,sans-serif;background:var(--bg);color:var(--fg);display:flex;align-items:center;justify-content:center;-webkit-font-smoothing:antialiased}
.wrap{width:min(600px,86%);text-align:center;transform:translateY(-6%)}
.mark{width:52px;height:52px;border-radius:15px;margin:0 auto 20px;display:flex;align-items:center;justify-content:center;font-size:28px;background:linear-gradient(135deg,#2f7cf6,#7c5cf0);box-shadow:0 10px 26px rgba(60,90,220,.3)}
.date{font-size:14px;color:var(--dim);margin-bottom:18px}
form{position:relative}
input{width:100%;height:54px;border-radius:16px;border:1px solid var(--border);background:var(--pill);padding:0 20px 0 48px;font-size:16px;color:var(--fg);outline:none}
input::placeholder{color:var(--dim)}
.sic{position:absolute;left:18px;top:50%;transform:translateY(-50%);color:var(--dim);font-size:15px}
.dial{display:grid;grid-template-columns:repeat(6,1fr);gap:14px;margin-top:30px}
a.site{display:flex;flex-direction:column;align-items:center;gap:8px;text-decoration:none;color:var(--dim);padding:10px 4px;border-radius:12px}
a.site:hover{background:var(--pill)}
.tile{width:48px;height:48px;border-radius:13px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:15px;font-weight:700;box-shadow:0 3px 10px rgba(0,0,0,.15)}
.nm{font-size:11px}
</style></head><body>
<div class="wrap">
  <div class="mark">&#128016;</div>
  <div class="date" id="date"></div>
  <form onsubmit="return go(event)">
    <span class="sic">&#128269;</span>
    <input id="q" placeholder="Search or enter address" autofocus autocomplete="off" spellcheck="false">
  </form>
  <div class="dial" id="dial"></div>
</div>
<script>
document.getElementById('date').textContent=new Date().toLocaleDateString(undefined,{weekday:'long',month:'long',day:'numeric'});
var sites=[['GH','GitHub','https://github.com','#242424'],['M','Gmail','https://mail.google.com','#d64b3f'],['▶','YouTube','https://youtube.com','#d42a2a'],['Li','Linear','https://linear.app','#5b57d6'],['Fi','Figma','https://figma.com','#c14fb0'],['D','Docs','https://docs.google.com','#2f7cf6']];
document.getElementById('dial').innerHTML=sites.map(function(s){return '<a class="site" href="'+s[2]+'"><span class="tile" style="background:'+s[3]+'">'+s[0]+'</span><span class="nm">'+s[1]+'</span></a>'}).join('');
function go(e){e.preventDefault();var q=document.getElementById('q').value.trim();if(!q)return false;var u;if(/^[a-z]+:\/\//i.test(q))u=q;else if(/^[^\s]+\.[^\s]{2,}(\/.*)?$/.test(q))u='https://'+q;else u='https://www.google.com/search?q='+encodeURIComponent(q);location.href=u;return false;}
</script></body></html>)PAGE";
}

inline std::string GoatErrorHTML() {
  return R"PAGE(<!doctype html><html><head><meta charset="utf-8"><title>Problem loading page</title>
<style>
:root{--bg:#ffffff;--fg:#16181d;--dim:#6b7280;--pill:rgba(0,0,0,.05);--border:rgba(0,0,0,.08);--accent:#2f7cf6}
@media (prefers-color-scheme:dark){:root{--bg:#1b1e26;--fg:#e8eaf0;--dim:#9aa1b2;--pill:rgba(255,255,255,.06);--border:rgba(255,255,255,.09);--accent:#4f8cff}}
*{box-sizing:border-box;margin:0;padding:0}
html,body{height:100%}
body{font-family:-apple-system,system-ui,sans-serif;background:var(--bg);color:var(--fg);display:flex;align-items:center;justify-content:center;-webkit-font-smoothing:antialiased}
.wrap{width:min(460px,86%);text-align:center}
.emoji{font-size:44px;margin-bottom:16px}
h1{font-size:22px;font-weight:600;margin-bottom:10px}
p{font-size:14px;line-height:1.5;color:var(--dim);margin-bottom:24px;word-break:break-all}
.row{display:flex;gap:10px;justify-content:center}
button{height:38px;padding:0 18px;border-radius:10px;border:1px solid var(--border);background:var(--pill);color:var(--fg);font-size:13px;font-weight:500;cursor:pointer}
button.primary{background:var(--accent);color:#fff;border-color:transparent}
</style></head><body>
<div class="wrap">
  <div class="emoji">&#9888;&#65039;</div>
  <h1 id="title">This page didn&#8217;t load</h1>
  <p id="msg"></p>
  <div class="row"><button onclick="history.back()">Back</button><button class="primary" onclick="retry()">Try Again</button></div>
</div>
<script>
var p=new URLSearchParams(location.search);
var url=p.get('url')||'';var text=p.get('text')||'';
document.getElementById('msg').textContent=(text?text:'The site could not be reached.')+(url?'  ·  '+url:'');
function retry(){if(url)location.href=url;}
</script></body></html>)PAGE";
}

inline std::string GoatInternalPageHTML(const std::string& host) {
  if (host == "newtab") return GoatNewTabHTML();
  if (host == "error") return GoatErrorHTML();
  return "<!doctype html><meta charset=\"utf-8\"><title>Goat</title>"
         "<body style=\"font-family:-apple-system\">Goat Browser</body>";
}
