/* OFFLINE REVIEW PROPOSAL, NOT AUTO-INSTALLED OR AUTO-INJECTED.
 * Source-side list/home parsing only. Preserve desktop branches; call this ONLY
 * after positively recognizing captured mobile templates. Detail/reader/account
 * templates need separate captures before claiming WNACG is fully usable.
 * Search uses loadNext and the site's exact paginator href (including cursor c).
 */
(() => {
  function fail(stage) {
    throw new Error('WNACG unsupported HTML template (' + stage + '). HTTP success is not a parsed comic page; check domain/template or use a reviewed source update.');
  }
  function text(e) { return e ? e.text.replace(/\s+/g, ' ').trim() : ''; }
  function absolute(value, base, sameOrigin) {
    value = String(value || '').trim();
    const origin = String(base).match(/^https?:\/\/[^/?#]+/i);
    if (!origin) fail('base URL');
    let result;
    if (/^https?:\/\//i.test(value)) result = value;
    else if (value.startsWith('//')) result = 'https:' + value;
    else if (value.startsWith('/')) result = origin[0] + value;
    else if (value && !/^[a-z][a-z0-9+.-]*:/i.test(value) && !value.startsWith('#')) result = origin[0] + '/' + value.replace(/^\.\//, '');
    else fail('URL');
    if (sameOrigin && result.match(/^https?:\/\/[^/?#]+/i)[0] !== origin[0]) fail('cross-origin navigation');
    return result;
  }
  function parseCard(c, base) {
    const link = c.querySelector('a.ImgA');
    const img = link && link.querySelector('img');
    const title = c.querySelector('a.txtA') || (link && link.querySelector('span'));
    const info = c.querySelector('span.info');
    const href = link && link.attributes.href;
    const id = href && href.match(/(?:^|\/)photos-index-aid-(\d+)\.html(?:[?#]|$)/);
    if (!id || !img || !text(title)) fail('mobile comic card');
    const attrs = img.attributes;
    const cover = absolute(attrs['data-original'] || attrs['data-src'] || attrs.src, base, false);
    return new Comic({id:id[1],title:text(title),cover:cover,description:text(info)});
  }
  function home(document, base) {
    const boxes = document.querySelectorAll('div.imgBox');
    if (!boxes.length) fail('mobile home');
    return boxes.map(box => {
      const heading = box.querySelector('div.Sub_H2');
      const title = heading && heading.querySelector('span.Title');
      const link = heading && heading.querySelector('a[href]');
      const cards = box.querySelectorAll('ul.col_3_2 > li');
      if (!text(title) || !link || !cards.length) fail('mobile home section');
      const href = absolute(link.attributes.href, base, true);
      if (!/\/albums(?:[-.]|$)/.test(href)) fail('mobile section navigation');
      return {title:text(title),comics:cards.map(c=>parseCard(c,base)),viewMore:'category:'+text(title)+'@'+href.slice(String(base).match(/^https?:\/\/[^/?#]+/i)[0].length)};
    });
  }
  function search(document, base) {
    const container = document.querySelector('ul#classify_container');
    if (!container || !document.querySelector('div.Sub_H2.classify')) fail('mobile search');
    const cards = container.querySelectorAll('li');
    const current = document.querySelector('div.f_left.paginator > span.thispage');
    const currentPage = Number(text(current) || '1');
    if (!Number.isInteger(currentPage) || currentPage < 1) fail('mobile search current page');
    let next = null;
    for (const a of document.querySelectorAll('div.f_left.paginator > a')) {
      const href = a.attributes.href || '';
      const page = href.match(/[?&]p=(\d+)(?:&|$)/);
      if (page && Number(page[1]) === currentPage+1) {
        next = absolute(href, base, true);
        if (!/\/search\//.test(next)) fail('search pagination URL');
        break;
      }
    }
    // No p.result count is present in these captures. Do not invent maxPage=10
    // from a sliding-window pager; return cursor URL rather than a fake total.
    return {comics:cards.map(c=>parseCard(c,base)),next:next};
  }
  globalThis.WnacgMobileCompatProposal = {home,search,absolute};
})();
