// Only the managed Tibo public timeline pages are sampled; no cookies or DMs.
(() => {
  if (!['/thsottiaux', '/thsottiaux/with_replies'].includes(location.pathname) || location.hash !== '#tibo-watch') return;
  let last = '', lastSent = 0, sending = false;
  async function capture() {
    if (sending) return;
    const posts = [];
    for (const article of document.querySelectorAll('article[data-testid="tweet"]')) {
      const name = article.querySelector('[data-testid="User-Name"]');
      if (!name || !Array.from(name.querySelectorAll('a')).some(a => a.getAttribute('href')?.toLowerCase() === '/thsottiaux')) continue;
      const time = article.querySelector('time[datetime]');
      const href = time?.closest('a')?.getAttribute('href') || '';
      if (!/^\/thsottiaux\/status\/\d+$/.test(href)) continue;
      const texts = Array.from(article.querySelectorAll('[data-testid="tweetText"]')).map(n => n.innerText);
      if (!texts[0]) continue;
      posts.push({url:'https://x.com'+href, date:time.getAttribute('datetime'), text:texts[0].slice(0,12000), quote:texts.slice(1).join('\n').slice(0,12000), truncated:!!article.querySelector('[data-testid="tweet-text-show-more-link"]')});
    }
    const login = !posts.length && !!document.querySelector('a[href="/login"],a[href="/i/flow/login"]');
    const snapshot = {version:1,pageURL:location.origin+location.pathname,capturedAt:new Date().toISOString(),pageLoadedAt:new Date(performance.timeOrigin).toISOString(),status:posts.length?'ok':login?'needs_login':'unavailable',posts};
    const signature = JSON.stringify(posts);
    const changed = signature !== last;
    if (!changed && Date.now()-lastSent<30000) return;
    last = signature;
    lastSent=Date.now();
    sending = true;
    try { await chrome.runtime.sendMessage({type:'snapshot',snapshot,changed}); }
    catch (_) { /* The app reports a stale connection if the bridge stops. */ }
    finally { sending = false; }
  }
  let debounce;
  new MutationObserver(() => { clearTimeout(debounce); debounce=setTimeout(capture,1500); }).observe(document.body,{childList:true,subtree:true});
  setInterval(capture,30000);
  capture();
})();
