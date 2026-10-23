// Generated-data browser oracle. Run with Playwright unsafe filename loader.
// DOMParser only, detached document; never navigate to fixture HTML or run its scripts.
async (page) => {
  const fixtures = __HOME_FIXTURES__;
  return await page.evaluate(fixtures => {
    const results = fixtures.map(ref => {
      const d = new DOMParser().parseFromString(ref.text, 'text/html');
      const counts = Object.fromEntries(ref.selectors.map(s => [s, d.querySelectorAll(s).length]));
      const heads = [...d.querySelectorAll('div.title_sort')], bodies = [...d.querySelectorAll('div.bodywrap')];
      const sections = heads.map((head, i) => ({title:head.querySelector('div.title_h2').textContent.replace(/\s+/g,''), count:bodies[i].querySelectorAll('div.gallary_wrap > ul.cc > li').length, ids:[...bodies[i].querySelectorAll('div.gallary_wrap > ul.cc > li')].map(li => li.querySelector('div.pic_box > a').getAttribute('href').match(/-aid-(\d+)/)[1])}));
      if (JSON.stringify(sections) !== JSON.stringify(ref.expected)) throw Error('browser cards differ from independent lxml ownership '+ref.file);
      return {file:ref.file,sha256:ref.sha256,counts,sections};
    });
    const d=new DOMParser().parseFromString('<div class="first" CLASS="last"></div><img src="" SRC="bad"><a href="/safe" HREF="javascript:bad">x</a><script>globalThis.homeScriptExecuted=true</script>', 'text/html');
    const micros={class:d.querySelector('div').getAttribute('class'),src:d.querySelector('img').getAttribute('src'),href:d.querySelector('a').getAttribute('href'),scriptExecuted:globalThis.homeScriptExecuted===true};
    if(micros.class!=='first'||micros.src!==''||micros.href!=='/safe'||micros.scriptExecuted) throw Error('browser micro contract failed');
    return {scope:'OFFLINE Chromium DOMParser detached documents on about:blank; no HTML scripts or resources executed',pass:true,results,micros};
  }, fixtures);
}
