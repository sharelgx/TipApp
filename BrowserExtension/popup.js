(async()=>{
 const state=await chrome.storage.local.get(['enabled','lastBridge']);
 document.getElementById('enabled').checked=state.enabled!==false;
 const b=state.lastBridge;
 document.getElementById('state').textContent=!b?'尚未连接，请先安装本机桥接并登录 X。':!b.ok?'连接失败：'+b.error:b.status==='ok'?'已连接，本次读取 '+b.count+' 条。':b.status==='needs_login'?'需要在专用标签中登录 X。':'页面不可用，应用将使用备用来源。';
 document.getElementById('enabled').onchange=e=>chrome.runtime.sendMessage({type:'enabled',value:e.target.checked});
 document.getElementById('refresh').onclick=()=>chrome.runtime.sendMessage({type:'refresh'});
})();
