import { Comic, ComicChapters } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { Res } from '../model/Res';
import { ComicSource, ImageRequestConfig } from './ComicSource';
import { SourceManager } from './SourceManager';
import { HttpClient, HttpResponse } from '../network/HttpClient';
import { image } from '@kit.ImageKit';
import { AppContext } from '../foundation/AppContext';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Settings } from '../foundation/Settings';
import { Log } from '../foundation/Log';
import { JsEngine } from './JsEngine';
import { SourceDataStore } from './SourceDataStore';
import { ImageRequests } from './ImageRequests';
import { ImagePipeline } from '../network/ImagePipeline';

/**
 * Full-chain self-test for comic sources.
 *
 * The first version only checked that `search.loadPage()` returned an array,
 * which said nothing about whether the source actually works: covers could fail
 * to load, details could throw, chapters could be empty and page images could be
 * unreachable. This version walks the whole reader chain per source and logs a
 * verdict for every stage:
 *
 *   search -> loadInfo -> chapters -> loadEp -> first image download
 *
 * Results are written to hilog so the matrix can be read off the device after an
 * install, with no UI interaction.
 */
export class SourceSelfTest {
  private static running: boolean = false;
  private static stopRequested: boolean = false;
  static get isRunning(): boolean { return SourceSelfTest.running; }
  static stopAfterCurrentSource(): void { SourceSelfTest.stopRequested = true; }
  /** Collected report lines; also written to filesDir/selftest.txt. */
  private static lines: string[] = [];
  /** Deep-mode search sweep uses one ASCII and one CJK keyword. */
  private static readonly ASCII_KEYWORD: string = 'a';
  private static readonly CJK_KEYWORD: string = '魔法';

  private static report(line: string): void {
    SourceSelfTest.lines.push(line);
    Log.info('SelfTestReport', line);
  }

  private static warn(line: string): void {
    SourceSelfTest.lines.push(line);
    Log.warn('SelfTestReport', line);
  }

  private static flush(): void {
    try {
      const path = `${AppContext.filesDir}/selftest.txt`;
      const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, SourceSelfTest.lines.join('\n'));
      } finally {
        fs.closeSync(file);
      }
      SourceSelfTest.report(`report written to ${path}`);
    } catch (error) {
      SourceSelfTest.warn(`cannot write report: ${error}`);
    }
  }

  static async run(): Promise<void> {
    if (SourceSelfTest.running) {
      return;
    }
    // Normal app launches must not silently crawl every source or download
    // test images. Preserve an explicit existing opt-in, otherwise stay offline.
    if (!Settings.getBool('sourceSelfTest', false)) {
      return;
    }
    SourceSelfTest.running = true;
    SourceSelfTest.stopRequested = false;
    try {
      await SourceSelfTest.runBody();
    } finally {
      SourceSelfTest.flush();
      SourceSelfTest.running = false;
    }
  }

  private static async runBody(): Promise<void> {
    SourceSelfTest.lines = [];
    const keyword = Settings.getString('sourceSelfTestKeyword', 'a');
    // `sourceSelfTestOnly` (a source key) narrows the matrix while debugging one
    // source; empty means "all searchable sources".
    const only = Settings.getString('sourceSelfTestOnly', '');
    const all = SourceManager.searchable();
    const sources = only.length === 0
      ? all
      : all.filter((item: ComicSource) => item.key === only);
    // Deep mode is the L2/L3 sampling depth SOURCE_ACCEPTANCE.md requires:
    // every explore page + page 2, every category part, two keywords x two
    // search pages, chapter first/middle/last and three decoded images per
    // chapter. That is ~10 image downloads per source, so it stays opt-in
    // instead of running on every launch.
    const deep = Settings.getBool('sourceSelfTestDeep', false);
    SourceSelfTest.report(
      `=== full-chain test: ${sources.length} source(s), keyword="${keyword}", deep=${deep} ===`);
    // L1 is offline and cheap, so it is always emitted: capability bitmap,
    // declared settings count and account mode per source.
    for (let i = 0; i < sources.length; i++) {
      if (SourceSelfTest.stopRequested) {
        SourceSelfTest.report('startup smoke stopped for explicit deep matrix');
        break;
      }
      SourceSelfTest.reportL1(sources[i]);
    }
    // Check parser contracts before any network requests. This still runs when
    // the device VPN is down, unlike the search/image probes below.
    const cursorSource = SourceManager.find('ehentai');
    if (cursorSource !== undefined && cursorSource.search?.loadPage !== undefined &&
        cursorSource.search?.loadNext !== undefined) {
      SourceSelfTest.report('offline | PASS | ehentai loadNext-only search registered');
    } else {
      SourceSelfTest.warn('offline | FAIL | ehentai loadNext-only search missing');
    }
    const categorySource = SourceManager.find('hcomic');
    if (categorySource !== undefined && categorySource.loadCategoryData !== undefined) {
      try {
        const categories = await categorySource.loadCategoryData();
        const count = categories?.parts[0]?.items.length ?? 0;
        const first = categories?.parts[0]?.items[1];
        if (count > 0 && first?.attributes.get('category') === '全彩' &&
            first?.attributes.get('param') === '全彩') {
          SourceSelfTest.report(`offline | PASS | hcomic category ${count} items with target attributes`);
        } else {
          SourceSelfTest.warn(`offline | FAIL | hcomic category count=${count}`);
        }
      } catch (error) {
        SourceSelfTest.warn(`offline | FAIL | hcomic category ${SourceSelfTest.messageOf(error)}`);
      }
    }
    let passed = 0;
    for (let i = 0; i < sources.length; i++) {
      if (SourceSelfTest.stopRequested) {
        SourceSelfTest.report('startup smoke stopped for explicit deep matrix');
        break;
      }
      const source = sources[i];
      const ok = await SourceSelfTest.testSource(source, keyword, deep);
      if (ok) {
        passed++;
      }
    }
    SourceSelfTest.report(`=== sampled chain: ${passed}/${sources.length}; NOT full L0-L5 or real login acceptance ===`);
    // Six searches per source are expensive and can trigger anti-bot limits;
    // opt in when diagnosing keywords instead of doing this at every startup.
    if (!SourceSelfTest.stopRequested && Settings.getBool('sourceSelfTestKeywordSweep', false)) {
      await SourceSelfTest.sweepKeywords(sources);
    }
  }

  /**
   * Search-path stress sweep.
   *
   * The single keyword "a" cannot distinguish "the port is wrong" from "this
   * source has nothing for a": sources that only accept digits, CJK or a
   * minimum length all look broken. This runs the search stage alone over a set
   * of probe keywords and reports the first keyword that works per source, so a
   * genuinely broken search path is visible next to one that simply needs a
   * different query.
   */
  private static async sweepKeywords(sources: ComicSource[]): Promise<void> {
    const keywords = ['a', '1', '魔法', 'ab', 'love', '海贼'];
    SourceSelfTest.report(
      `--- keyword sweep over ${keywords.length} probe keyword(s) ---`);
    for (let i = 0; i < sources.length; i++) {
      const source = sources[i];
      const search = source.search;
      if (search === undefined || search.loadPage === undefined) {
        continue;
      }
      let firstOk = '';
      let firstError = '';
      let counts = '';
      for (let k = 0; k < keywords.length; k++) {
        const keyword = keywords[k];
        let items = 0;
        let failure = '';
        try {
          const result: Res<Comic[]> = await search.loadPage(keyword, 1, []);
          if (result.error) {
            failure = result.errorMessage ?? 'error';
          } else {
            items = (result.dataOrNull ?? []).length;
            if (items === 0) {
              failure = '0 results';
            }
          }
        } catch (error) {
          failure = SourceSelfTest.messageOf(error);
        }
        counts += `${keyword}:${items} `;
        if (failure.length === 0 && firstOk.length === 0) {
          firstOk = keyword;
        }
        if (failure.length > 0 && firstError.length === 0) {
          firstError = `${keyword} -> ${failure}`;
        }
      }
      if (firstOk.length > 0) {
        SourceSelfTest.report(
          `${source.key} | sweep OK | first="${firstOk}" counts[${counts.trim()}]`);
      } else {
        SourceSelfTest.warn(
          `${source.key} | sweep NONE | every keyword failed, first: ${firstError}`);
      }
    }
  }

  private static async testSource(source: ComicSource, keyword: string,
                                  deep: boolean): Promise<boolean> {
    // ---- stage 0: explore (every declared page; page 2 + parts in deep mode) ----
    await SourceSelfTest.probeExplore(source, deep);
    if (deep) {
      await SourceSelfTest.probeCategory(source);
      await SourceSelfTest.probeSearchNext(source);
      const complement = SourceSelfTest.isAscii(keyword)
        ? SourceSelfTest.CJK_KEYWORD
        : SourceSelfTest.ASCII_KEYWORD;
      await SourceSelfTest.probeSearchPages(source, keyword);
      if (complement !== keyword) {
        await SourceSelfTest.probeSearchPages(source, complement);
      }
    }

    const search = source.search;
    if (search === undefined || search.loadPage === undefined) {
      SourceSelfTest.warn(`${source.key} | SKIP | no search capability`);
      return false;
    }

    // ---- stage 1: search ----
    let comics: Comic[] = [];
    try {
      const result: Res<Comic[]> = await search.loadPage(keyword, 1, []);
      if (result.error) {
        SourceSelfTest.warn(`${source.key} | FAIL search | ${result.errorMessage ?? 'error'}`);
        return false;
      }
      comics = result.dataOrNull ?? [];
      if (comics.length === 0) {
        SourceSelfTest.warn(`${source.key} | FAIL search | 0 results`);
        return false;
      }
    } catch (error) {
      SourceSelfTest.warn(
        `${source.key} | FAIL search | ${SourceSelfTest.messageOf(error)}`);
      return false;
    }

    // ---- stage 1b: the fields the UI actually renders ----
    const first = comics[0];
    const missing: string[] = [];
    if (first.id.length === 0) {
      missing.push('id');
    }
    if (first.title.length === 0) {
      missing.push('title');
    }
    if (first.cover.length === 0) {
      missing.push('cover');
    }
    if (missing.length > 0) {
      SourceSelfTest.warn(
        `${source.key} | FAIL search | missing field(s): ${missing.join(',')}`);
      return false;
    }
    SourceSelfTest.report(
      `${source.key} | ok search | ${comics.length} results, first="${first.title}"`);

    // ---- stage 2: details ----
    if (source.loadComicInfo === undefined) {
      SourceSelfTest.warn(`${source.key} | FAIL details | not supported`);
      return false;
    }
    let details: ComicDetails | undefined = undefined;
    try {
      const result: Res<ComicDetails> = await source.loadComicInfo(first.id);
      if (result.error) {
        SourceSelfTest.warn(
          `${source.key} | FAIL details | ${result.errorMessage ?? 'error'}`);
        return false;
      }
      details = result.dataOrNull;
    } catch (error) {
      SourceSelfTest.warn(
        `${source.key} | FAIL details | ${SourceSelfTest.messageOf(error)}`);
      return false;
    }
    if (details === undefined) {
      SourceSelfTest.warn(`${source.key} | FAIL details | null`);
      return false;
    }
    const chapters: ComicChapters | undefined = details.chapters;
    // Single-chapter comics (most doujin sites) legitimately return no chapter
    // list; upstream treats the whole comic as one implicit chapter. Only a
    // missing details object is a failure.
    const hasChapters = chapters !== undefined && chapters.length > 0;
    SourceSelfTest.report(
      `${source.key} | ok details | "${details.title}", ` +
      (hasChapters ? `${chapters.length} chapter(s)` : 'single chapter'));

    // ---- stage 3: chapter pages ----
    if (source.loadComicPages === undefined) {
      SourceSelfTest.warn(`${source.key} | FAIL pages | not supported`);
      return false;
    }
    const totalChapters = hasChapters ? chapters.length : 1;
    // Deep mode samples first / middle / last chapter and three images per
    // chapter; the default launch keeps one chapter and first+last.
    const chapterIndices: number[] = deep
      ? SourceSelfTest.chapterIndices(totalChapters)
      : [0];
    const firstEpId: string | undefined = hasChapters ? chapters.ids[chapterIndices[0]] : undefined;
    let lastPageCount = 0;
    let imagesOk = true;
    for (let c = 0; c < chapterIndices.length; c++) {
      const index = chapterIndices[c];
      const epId: string | undefined = hasChapters ? chapters.ids[index] : undefined;
      let images: string[] = [];
      try {
        const result: Res<string[]> = await source.loadComicPages(first.id, epId ?? '');
        if (result.error) {
          SourceSelfTest.warn(
            `${source.key} | FAIL pages | chapter ${index + 1}: ${result.errorMessage ?? 'error'}`);
          return false;
        }
        images = result.dataOrNull ?? [];
      } catch (error) {
        SourceSelfTest.warn(
          `${source.key} | FAIL pages | chapter ${index + 1}: ${SourceSelfTest.messageOf(error)}`);
        return false;
      }
      if (images.length === 0) {
        SourceSelfTest.warn(`${source.key} | FAIL pages | chapter ${index + 1}: 0 images`);
        return false;
      }
      lastPageCount = images.length;
      SourceSelfTest.report(
        `${source.key} | ok pages | chapter ${index + 1}/${totalChapters}, ` +
        `${images.length} image(s)`);
      // ---- stage 4: the images the reader will actually decode ----
      const samples = SourceSelfTest.imageIndices(images.length, deep);
      for (let s = 0; s < samples.length; s++) {
        const position = samples[s];
        const label = `ch${index + 1} page${position + 1}`;
        const ok = await SourceSelfTest.probeImage(source, images[position], first.id, epId, label);
        if (!ok) {
          imagesOk = false;
        }
      }
    }

    const coverOk = await SourceSelfTest.probeImage(source, first.cover, first.id, firstEpId, 'cover');
    if (!coverOk || !imagesOk) {
      return false;
    }

    const chapterLabel = hasChapters
      ? `${chapterIndices.length}/${totalChapters} chapter(s)`
      : 'single chapter';
    SourceSelfTest.report(
      `${source.key} | PASS | search->details->${chapterLabel} x ${lastPageCount} pages, ` +
      `cover+${deep ? 'first+mid+last' : 'first+last'} decoded`);
    return true;
  }

  /** Decode dimensions via ImageKit; empty string when the bytes are not an image. */
  private static async decodeSize(bytes: ArrayBuffer): Promise<string> {
    try {
      const source = image.createImageSource(bytes);
      try {
        const pixel = await source.createPixelMap();
        try {
          const info = await pixel.getImageInfo();
          const width = info.size.width;
          const height = info.size.height;
          return (width > 0 && height > 0) ? `${width}x${height}` : '';
        } finally { await pixel.release(); }
      } finally { await source.release(); }
    } catch (error) {
      return '';
    }
  }

  /** Download the first bytes of an image, applying the source's image config. */
  private static async probeImage(source: ComicSource, url: string, comicId: string,
                                  epId: string | undefined, label: string): Promise<boolean> {
    if (url.length === 0) {
      SourceSelfTest.warn(`${source.key} | FAIL ${label} | empty url`);
      return false;
    }
    const trace = `source-image-${Date.now()}-${source.key}`;
    let request = new ImageRequestConfig();
    request.url = url;
    {
      try {
        const config: ImageRequestConfig = await ImageRequests.resolve(source, url, label === 'cover', comicId, epId ?? '',
          trace);
        request = config;
      } catch (error) {
        SourceSelfTest.warn(
          `${source.key} | FAIL ${label} | onImageLoad: ${SourceSelfTest.messageOf(error)}`);
        return false;
      }
    }
    try {
      const modified = await ImagePipeline.fetch(request, trace);
      const size = modified.byteLength;
      if (size < 64) {
        SourceSelfTest.warn(`${source.key} | FAIL ${label} | ${size} bytes`);
        return false;
      }
      // Decoding is the real proof the reader can render it: an error page or a
      // truncated file is still larger than 64 bytes.
      const dimensions = await SourceSelfTest.decodeSize(modified);
      if (dimensions.length === 0) {
        SourceSelfTest.warn(
          `${source.key} | FAIL ${label} | ${Math.round(size / 1024)} KB but not decodable`);
        return false;
      }
      SourceSelfTest.report(
        `${source.key} | ok ${label} | ${Math.round(size / 1024)} KB ${dimensions}`);
      return true;
    } catch (error) {
      SourceSelfTest.warn(
        `${source.key} | FAIL ${label} | ${SourceSelfTest.messageOf(error)}`);
      return false;
    }
  }

  /** Items the grid cannot render (missing id / title / cover). */
  private static countBroken(items: Comic[]): number {
    let broken = 0;
    for (let i = 0; i < items.length; i++) {
      if (items[i].id.length === 0 || items[i].title.length === 0 ||
        items[i].cover.length === 0) {
        broken++;
      }
    }
    return broken;
  }

  // ------------------------------------------------------------ L1 / L2

  /**
   * Offline capability bitmap, declared settings count and account mode.
   * SOURCE_ACCEPTANCE.md §3: this is L1 and must not depend on the network.
   */
  private static reportL1(source: ComicSource): void {
    const caps: string[] = [];
    if (source.search?.loadPage !== undefined) {
      caps.push('search');
    }
    if (source.search?.loadNext !== undefined) {
      caps.push('searchNext');
    }
    if (source.explorePages.length > 0) {
      caps.push(`explore:${source.explorePages.length}`);
    }
    if (source.loadComicInfo !== undefined) {
      caps.push('info');
    }
    if (source.loadComicPages !== undefined) {
      caps.push('ep');
    }
    if (source.loadCategoryData !== undefined) {
      caps.push('cat');
    }
    if (source.getImageConfig !== undefined) {
      caps.push('img');
    }
    if (source.getThumbnailConfig !== undefined) {
      caps.push('thumb');
    }
    if (source.account !== undefined) {
      caps.push('account');
    }
    if (source.favoriteData !== undefined) {
      caps.push('fav');
    }
    if (source.archiveDownloader !== undefined) {
      caps.push('archive');
    }
    let settings = 0;
    const defaults = SourceDataStore.get(source.key, 'setting_defaults');
    if (defaults !== null && typeof defaults === 'object') {
      settings = Object.keys(defaults as Record<string, Object>).length;
    }
    SourceSelfTest.report(
      `${source.key} | L1 | v${source.version} | ` +
      `caps=${caps.length === 0 ? 'none' : caps.join(',')} | ` +
      `settings=${settings} | account=${SourceSelfTest.accountMode(source)}`);
  }

  private static accountMode(source: ComicSource): string {
    const account = source.account;
    if (account === undefined) {
      return 'none';
    }
    if (account.login !== undefined) {
      return 'password';
    }
    if (account.loginWebsite !== undefined) {
      return 'web';
    }
    if (account.cookieFields !== undefined) {
      return 'cookie';
    }
    return 'other';
  }

  /** Every declared explore page; page 2 and per-part counts only in deep mode. */
  private static async probeExplore(source: ComicSource, deep: boolean): Promise<void> {
    for (let i = 0; i < source.explorePages.length; i++) {
      const explore = source.explorePages[i];
      const loadPage = explore.loadPage;
      if (loadPage === undefined) {
        SourceSelfTest.warn(`${source.key} | FAIL explore[${i}] | no loader`);
        continue;
      }
      const pages = deep ? 2 : 1;
      for (let page = 1; page <= pages; page++) {
        try {
          const result: Res<Comic[]> = await loadPage(page);
          if (result.error) {
            SourceSelfTest.warn(
              `${source.key} | FAIL explore[${i}] p${page} | ${result.errorMessage ?? 'error'}`);
            continue;
          }
          const items = result.dataOrNull ?? [];
          const broken = SourceSelfTest.countBroken(items);
          if (items.length === 0) {
            SourceSelfTest.warn(`${source.key} | FAIL explore[${i}] p${page} | 0 items`);
          } else if (broken > 0) {
            SourceSelfTest.warn(
              `${source.key} | FAIL explore[${i}] p${page} | ` +
              `${broken}/${items.length} missing id/title/cover`);
          } else {
            SourceSelfTest.report(
              `${source.key} | ok explore[${i}] p${page} | "${explore.title}", ` +
              `${items.length} items`);
          }
        } catch (error) {
          SourceSelfTest.warn(
            `${source.key} | FAIL explore[${i}] p${page} | ${SourceSelfTest.messageOf(error)}`);
        }
      }
      if (deep) {
        await SourceSelfTest.probeExploreParts(source, i);
      }
    }
  }

  /**
   * Raw part structure of one explore page. The flattened `Comic[]` the UI
   * renders loses part boundaries, so "every part has data" can only be judged
   * on the script's own return value.
   */
  private static async probeExploreParts(source: ComicSource, index: number): Promise<void> {
    const expr = `ComicSource.sources[${JSON.stringify(source.key)}].explore[${index}]`;
    try {
      const raw = await JsEngine.callJson(
        `(() => { const e = ${expr}; if (!e || typeof e.load !== 'function') { return null; } ` +
        'return (e.type === "mixed") ? e.load(0) : e.load(); })()', '<explore-parts>');
      const summary = SourceSelfTest.partSummary(raw);
      if (summary.length === 0) {
        SourceSelfTest.report(`${source.key} | L2 explore[${index}] parts | flat list, no parts`);
      } else {
        SourceSelfTest.report(`${source.key} | L2 explore[${index}] parts | ${summary}`);
      }
    } catch (error) {
      SourceSelfTest.warn(
        `${source.key} | L2 explore[${index}] parts | ${SourceSelfTest.messageOf(error)}`);
    }
  }

  /** `{name: [comics]}` or `[{title, comics}]` -> "name=count"; empty parts get a "!". */
  private static partSummary(raw: Object | null): string {
    if (raw === null || raw === undefined || typeof raw !== 'object') {
      return '';
    }
    const notes: string[] = [];
    if (Array.isArray(raw)) {
      const list = raw as Object[];
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        if (item === null || typeof item !== 'object' || Array.isArray(item)) {
          continue;
        }
        const record = item as Record<string, Object>;
        const comics = record['comics'];
        if (!Array.isArray(comics)) {
          continue;
        }
        const rawTitle = record['title'];
        const title = typeof rawTitle === 'string' ? rawTitle as string : `#${i + 1}`;
        notes.push(SourceSelfTest.partNote(title, (comics as Object[]).length));
      }
      return notes.join(', ');
    }
    const record = raw as Record<string, Object>;
    const names = Object.keys(record);
    for (let i = 0; i < names.length; i++) {
      const value = record[names[i]];
      if (Array.isArray(value)) {
        notes.push(SourceSelfTest.partNote(names[i], (value as Object[]).length));
      }
    }
    return notes.join(', ');
  }

  private static partNote(name: string, count: number): string {
    return count === 0 ? `${name}=0!` : `${name}=${count}`;
  }

  /** Every category part, first two entries each (SOURCE_ACCEPTANCE §4.2). */
  private static async probeCategory(source: ComicSource): Promise<void> {
    const loader = source.loadCategoryData;
    if (loader === undefined) {
      return;
    }
    try {
      const data = await loader();
      if (data === undefined || data.parts.length === 0) {
        SourceSelfTest.warn(`${source.key} | L2 category | no parts`);
        return;
      }
      const notes: string[] = [];
      let incomplete = 0;
      for (let p = 0; p < data.parts.length; p++) {
        const part = data.parts[p];
        if (part.items.length === 0) {
          incomplete++;
          notes.push(`${part.title}=EMPTY`);
          continue;
        }
        const sample = Math.min(2, part.items.length);
        let usable = 0;
        for (let k = 0; k < sample; k++) {
          const item = part.items[k];
          if (item.label.length > 0 && item.page.length > 0) {
            usable++;
          }
        }
        if (usable < sample) {
          incomplete++;
        }
        notes.push(`${part.title}=${part.items.length} items, ${usable}/${sample} usable`);
      }
      const line = `${source.key} | L2 category | ${data.parts.length} part(s) | ${notes.join('; ')}`;
      if (incomplete > 0) {
        SourceSelfTest.warn(`${line} | ${incomplete} part(s) incomplete`);
      } else {
        SourceSelfTest.report(line);
      }
    } catch (error) {
      SourceSelfTest.warn(`${source.key} | L2 category | ${SourceSelfTest.messageOf(error)}`);
    }
  }

  /** Two pages of one keyword; page 2 must not repeat page 1 (§4.3). */
  private static async probeSearchPages(source: ComicSource, keyword: string): Promise<void> {
    const search = source.search;
    if (search === undefined) {
      return;
    }
    const loadPage = search.loadPage;
    if (loadPage === undefined) {
      return;
    }
    const notes: string[] = [];
    let firstPrint = '';
    let cursor: string | undefined = undefined;
    for (let page = 1; page <= 2; page++) {
      try {
        const result: Res<Comic[]> = page === 2 && search.cursorOnly && search.loadNext !== undefined &&
          cursor !== undefined ? await search.loadNext(keyword, cursor, []) : await loadPage(keyword, page, []);
        if (result.error) {
          SourceSelfTest.warn(
            `${source.key} | L2 search "${keyword}" p${page} | ${result.errorMessage ?? 'error'}`);
          return;
        }
        const items = result.dataOrNull ?? [];
        if (items.length === 0) {
          SourceSelfTest.warn(`${source.key} | L2 search "${keyword}" p${page} | 0 results`);
          return;
        }
        const broken = SourceSelfTest.countBroken(items);
        notes.push(`p${page}=${items.length}(broken ${broken})`);
        if (page === 1) {
          firstPrint = SourceSelfTest.idFingerprint(items);
          cursor = result.subDataString;
          if (search.cursorOnly && (cursor === undefined || cursor.length === 0)) {
            SourceSelfTest.warn(`${source.key} | L2 search "${keyword}" | no next cursor`);
            return;
          }
        } else if (firstPrint === SourceSelfTest.idFingerprint(items)) {
          SourceSelfTest.warn(
            `${source.key} | L2 search "${keyword}" | ${notes.join(' ')} | p2 identical to p1`);
          return;
        }
      } catch (error) {
        SourceSelfTest.warn(
          `${source.key} | L2 search "${keyword}" p${page} | ${SourceSelfTest.messageOf(error)}`);
        return;
      }
    }
    SourceSelfTest.report(
      `${source.key} | L2 search "${keyword}" | ${notes.join(' ')} | p2 differs from p1`);
  }

  /**
   * Sources that only expose `search.loadNext`: the first request must carry a
   * null cursor and the second the cursor the first page returned
   * (parser.dart picks loadNext when load is absent).
   */
  private static async probeSearchNext(source: ComicSource): Promise<void> {
    const search = source.search;
    if (search === undefined || !search.cursorOnly || search.loadNext === undefined) {
      return;
    }
    const expr = `ComicSource.sources[${JSON.stringify(source.key)}].search.loadNext`;
    try {
      const keyword = JSON.stringify(SourceSelfTest.ASCII_KEYWORD);
      const first = await JsEngine.callJson(
        `(() => ${expr}(${keyword}, [], null))()`, '<searchnext-first>');
      const firstCount = SourceSelfTest.listLength(first);
      const cursor = SourceSelfTest.nextCursor(first);
      if (firstCount === 0 || cursor.length === 0) {
        SourceSelfTest.warn(
          `${source.key} | L2 searchNext | first page items=${firstCount}, cursor="${cursor}"`);
        return;
      }
      const second = await JsEngine.callJson(
        `(() => ${expr}(${keyword}, [], ${JSON.stringify(cursor)}))()`, '<searchnext-second>');
      const secondCount = SourceSelfTest.listLength(second);
      if (secondCount === 0) {
        SourceSelfTest.warn(`${source.key} | L2 searchNext | cursor "${cursor}" returned 0 items`);
      } else {
        SourceSelfTest.report(
          `${source.key} | L2 searchNext | cursor path OK, p1=${firstCount} p2=${secondCount}`);
      }
    } catch (error) {
      SourceSelfTest.warn(`${source.key} | L2 searchNext | ${SourceSelfTest.messageOf(error)}`);
    }
  }

  /** Item count of a raw payload: bare array, `{data: []}` or `{comics: []}`. */
  private static listLength(value: Object | null): number {
    if (value === null || value === undefined) {
      return 0;
    }
    if (Array.isArray(value)) {
      return (value as Object[]).length;
    }
    if (typeof value === 'object') {
      const record = value as Record<string, Object>;
      const data = record['data'];
      if (Array.isArray(data)) {
        return (data as Object[]).length;
      }
      const comics = record['comics'];
      if (Array.isArray(comics)) {
        return (comics as Object[]).length;
      }
    }
    return 0;
  }

  /** `next` / `maxPage` cursor of a raw payload, "" when absent. */
  private static nextCursor(value: Object | null): string {
    if (value === null || value === undefined || typeof value !== 'object' || Array.isArray(value)) {
      return '';
    }
    const record = value as Record<string, Object>;
    const next = record['next'] ?? record['maxPage'];
    if (next === undefined || next === null) {
      return '';
    }
    return String(next);
  }

  private static isAscii(text: string): boolean {
    for (let i = 0; i < text.length; i++) {
      if (text.charCodeAt(i) > 127) {
        return false;
      }
    }
    return true;
  }

  /** First few ids, to tell "page 2 differs" from "pagination was ignored". */
  private static idFingerprint(items: Comic[]): string {
    const parts: string[] = [];
    const limit = items.length;
    for (let i = 0; i < limit; i++) {
      parts.push(items[i].id);
    }
    return parts.join('|');
  }

  /** Chapter sampling: first / middle / last (SOURCE_ACCEPTANCE §5.1). */
  private static chapterIndices(count: number): number[] {
    if (count <= 1) {
      return [0];
    }
    if (count === 2) {
      return [0, 1];
    }
    return [0, Math.floor(count / 2), count - 1];
  }

  /** Image sampling inside one chapter: first+last, plus middle in deep mode. */
  private static imageIndices(count: number, deep: boolean): number[] {
    if (count <= 1) {
      return [0];
    }
    if (!deep) {
      return [0, count - 1];
    }
    return SourceSelfTest.uniqueIndices([0, Math.floor(count / 2), count - 1]);
  }

  private static uniqueIndices(values: number[]): number[] {
    const out: number[] = [];
    for (let i = 0; i < values.length; i++) {
      if (out.indexOf(values[i]) < 0) {
        out.push(values[i]);
      }
    }
    return out;
  }

  private static messageOf(error: Object): string {
    if (error instanceof Error) {
      return error.message;
    }
    return String(error);
  }
}
