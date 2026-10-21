const HOST='local.tibowatch.x';
const PAGES=['https://x.com/thsottiaux#tibo-watch','https://x.com/thsottiaux/with_replies#tibo-watch'];
async function ensureTabs(refresh=false) {
  const state=await chrome.storage.local.get(['enabled','managedTabs']);
  if (state.enabled===false) return;
  const ids=[];
  for (let i=0;i<PAGES.length;i++) {
    let tab;
    try { tab=await chrome.tabs.get(state.managedTabs?.[i]); } catch (_) {}
    if (!tab || tab.url!==PAGES[i]) tab=await chrome.tabs.create({url:PAGES[i],active:false});
    else if(refresh) await chrome.tabs.reload(tab.id);
    ids.push(tab.id);
  }
  await chrome.storage.local.set({managedTabs:ids});
}
chrome.runtime.onInstalled.addListener(()=>{chrome.alarms.create('refresh',{periodInMinutes:1.5});ensureTabs();});
chrome.runtime.onStartup.addListener(()=>{chrome.alarms.create('refresh',{periodInMinutes:1.5});ensureTabs();});
chrome.alarms.onAlarm.addListener(a=>{if(a.name==='refresh')ensureTabs(true);});
chrome.runtime.onMessage.addListener((message,sender,sendResponse)=>{
  (async()=>{
    if(message.type==='snapshot') {
      const u=new URL(sender.url||'about:blank');
      const state=await chrome.storage.local.get('enabled');
      if(state.enabled===false || u.origin!=='https://x.com' || !['/thsottiaux','/thsottiaux/with_replies'].includes(u.pathname) || u.hash!=='#tibo-watch')throw Error('Rejected sender');
      const result=await chrome.runtime.sendNativeMessage(HOST,{...message.snapshot,changed:message.changed});
      if(result.ok!==true)throw Error(result.error||"Bridge rejected snapshot");
      await chrome.storage.local.set({lastBridge:{at:Date.now(),ok:true,status:message.snapshot.status,count:result.captured||0}});
      return result;
    }
    if(!sender.tab && message.type==='enabled') {
      await chrome.storage.local.set({enabled:message.value});
      if(message.value)await ensureTabs(true);
      return {ok:true};
    }
    if(!sender.tab && message.type==='refresh') {await ensureTabs(true);return {ok:true};}
    throw Error('Unknown request');
  })().then(sendResponse,async error=>{
    await chrome.storage.local.set({lastBridge:{at:Date.now(),ok:false,error:String(error.message||error)}});
    sendResponse({ok:false,error:String(error.message||error)});
  });
  return true;
});
