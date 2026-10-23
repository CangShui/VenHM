import { Comic, ComicChapters, parseComicList } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { ComicSource } from './ComicSource';
import { SourceManager } from './SourceManager';
import { SourceDao } from '../storage/SourceDao';
import { HttpClient, HttpRequestOptions } from '../network/HttpClient';
import { http } from '@kit.NetworkKit';
import { ImageRequests } from './ImageRequests';
import { ImagePipeline } from '../network/ImagePipeline';
import { JsEngine } from './JsEngine';
import { Log } from '../foundation/Log';
import { AppContext } from '../foundation/AppContext';
import { fileIo as fs } from '@kit.CoreFileKit';
import { image } from '@kit.ImageKit';
import { window } from '@kit.ArkUI';
import { SourceSelfTest } from './SourceSelfTest';

class SearchSample {
  keyword: string = '';
  comics: Comic[] = [];
  passed: boolean = false;
  failedRequest: boolean = false;
}

export class AcceptanceRow {
  key: string = '';
  l0: string = 'PARTIAL_COMMON_CONTRACTS';
  l1: string = 'NOT_RUN';
  explore: string = 'NOT_RUN';
  category: string = 'NOT_RUN';
  search: string = 'NOT_RUN';
  l3: string = 'NOT_RUN';
  l4: string = 'NOT_TESTED_REAL_LOGIN';
  l5: string = 'NOT_TESTED_SITE_SPECIFICS';
  classification: string = 'UNDETERMINED';
}

/**
 * Explicit, read-only deep matrix. Stage success is never promoted to full
 * L0-L5 PASS: real login, HTTP cookies and remaining common contracts are
 * separate acceptance work. One source at a time; no login/post/favorite calls.
 */
export class SourceAcceptance {
  static running: boolean = false;
  static status: string = '尚未运行深度矩阵';
  static rows: AcceptanceRow[] = [];
  private static cancelled: boolean = false;
  private static runId: string = '';
  private static file: string = '';
  private static candidates: Map<string, Comic[]> = new Map<string, Comic[]>();
  private static notes: Map<string, string[]> = new Map<string, string[]>();

  /** Attribute each failure to a migration gap, a source rule needing DOM
   * comparison, or a site/auth limit. Never label 401/403 as a bad source.
   */
  private static classify(key: string): string {
    const text = (SourceAcceptance.notes.get(key) ?? []).join(' | ').toLowerCase();
    if (text.length === 0) { return 'UNDETERMINED'; }
    // Observations, not a regex verdict about whose implementation is wrong.
    // HTTP403 may involve our headers; SDK code401 is NOT an HTTP401 response.
    if (/image_config_unsupported/.test(text)) { return 'A_APPLICATION_IMAGE_GAP'; }
    if (/未迁移目标类型|迁移能力无load/.test(text)) { return 'A_APPLICATION_CAPABILITY_GAP'; }
    if (/not logged in|login expired|need login|未登录/.test(text)) { return 'LOGIN_REQUIRED_OBSERVED'; }
    if (/setting not found|requires configuration|需要配置/.test(text)) { return 'CONFIGURATION_REQUIRED_OBSERVED'; }
    if (/(?:http|status(?: code)?|状态码)[\s:=]+[45]\d\d\b/.test(text)) { return 'HTTP_FAILURE_OBSERVED'; }
    if (/\bcode\s+\d+|timed? ?out|timeout|econn|网络请求失败|network response/.test(text)) { return 'TRANSPORT_OR_SDK_ERROR_OBSERVED'; }
    if (/different=false/.test(text)) { return 'PAGINATION_COMPARISON_REQUIRED'; }
    // Callable/type/JSON/selector errors can originate in either source or port;
    // paired replay and stage evidence, not wording, must determine the cause.
    return 'UNDETERMINED';
  }

  static cancel(): void {
    SourceAcceptance.cancelled = true;
    SourceAcceptance.status = '正在停止（等待当前请求返回）';
  }

  private static emit(key: string, stage: string, note: string): void {
    const trace = `${SourceAcceptance.runId}-${key}`;
    const line = `${key} | ${stage} | ${note}`;
    Log.audit(trace, stage, note);
    Log.info('DeepMatrix', line);
    const bucket = SourceAcceptance.notes.get(key);
    if (bucket === undefined) { SourceAcceptance.notes.set(key, [note]); }
    else if (bucket.length < 64) { bucket.push(note); }
    if (SourceAcceptance.file.length > 0) {
      const handle = fs.openSync(SourceAcceptance.file,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      try {
        fs.writeSync(handle.fd, JSON.stringify({ trace: trace, source: key, stage: stage, note: note }) + '\n');
      } finally {
        fs.closeSync(handle);
      }
    }
  }

  static async run(): Promise<string[]> {
    if (SourceAcceptance.running) {
      return ['已有深度矩阵在执行，请勿重复运行'];
    }
    SourceAcceptance.running = true;
    SourceAcceptance.cancelled = false;
    SourceAcceptance.rows = [];
    SourceAcceptance.candidates.clear();
    SourceAcceptance.notes.clear();
    SourceAcceptance.runId = `deep-${Date.now()}`;
    SourceAcceptance.file = `${AppContext.filesDir}/logs/${SourceAcceptance.runId}.jsonl`;
    let host: window.Window | undefined = undefined;
    let oldKeepScreenOn = false;
    try {
      host = await window.getLastWindow(AppContext.context);
      oldKeepScreenOn = host.getWindowProperties().isKeepScreenOn;
      await host.setWindowKeepScreenOn(true);
      SourceSelfTest.stopAfterCurrentSource();
      while (SourceSelfTest.isRunning) {
        SourceAcceptance.status = '等待启动浅回归结束当前源，避免两轮并发请求';
        if (SourceAcceptance.cancelled) { return ['运行在开始前已取消']; }
        await new Promise<void>((resolve: () => void) => { setTimeout(resolve, 500); });
      }
      const installed = await SourceDao.list();
      SourceAcceptance.emit('matrix', 'BEGIN',
        `installed=${installed.length}；ASCII=a/CJK=魔法；L0仍有待验项，禁止汇总为全部可用`);
      await SourceAcceptance.publicWnacgCapture();
      for (let i = 0; i < installed.length; i++) {
        if (SourceAcceptance.cancelled) { break; }
        const row = new AcceptanceRow();
        row.key = installed[i].key;
        SourceAcceptance.rows.push(row);
        SourceAcceptance.status = `${i + 1}/${installed.length} · ${row.key}`;
        const source = SourceManager.find(row.key);
        if (source === undefined) {
          row.l1 = 'FAIL_REGISTRATION';
          row.classification = 'A_APPLICATION_REGISTRATION_GAP';
          SourceAcceptance.emit(row.key, 'L1', '未注册，不能继续测试');
          SourceAcceptance.emit(row.key, 'ROW', JSON.stringify(row));
          continue;
        }
        await SourceAcceptance.test(source, row);
        // Attribute the failure only when a stage actually failed; a fully
        // sampled chain keeps UNDETERMINED because login/site specifics remain.
        const categoryPassed = row.category === 'NOT_APPLICABLE' ||
          row.category === 'PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE';
        const passed = row.explore.startsWith('SAMPLED') && categoryPassed && row.search.startsWith('TWO_KEYWORDS') &&
          row.l3.startsWith('SAMPLE_CHAIN_OK');
        if (row.classification === 'UNDETERMINED') {
          row.classification = passed ? 'NO_PUBLIC_FAILURE_OBSERVED' : SourceAcceptance.classify(row.key);
        }
        SourceAcceptance.emit(row.key, 'CLASSIFY', row.classification);
        SourceAcceptance.emit(row.key, 'ROW', JSON.stringify(row));
      }
      const summaries = SourceAcceptance.rows.map((row: AcceptanceRow): string =>
        `${row.key} | L0=${row.l0} | L1=${row.l1} | L2=${row.explore}/${row.category}/${row.search} | ` +
        `L3=${row.l3} | L4=${row.l4} | L5=${row.l5} | ${row.classification}`);
      SourceAcceptance.status = SourceAcceptance.cancelled ? '矩阵已停止，保留已完成记录' : '矩阵执行完成（不等于全部通过）';
      SourceAcceptance.emit('matrix', 'END', `${SourceAcceptance.status}；rows=${summaries.length}`);
      return summaries;
    } catch (error) {
      SourceAcceptance.status = `矩阵异常：${SourceAcceptance.message(error)}`;
      SourceAcceptance.emit('matrix', 'ERROR', SourceAcceptance.status);
      throw new Error(SourceAcceptance.status);
    } finally {
      if (host !== undefined) {
        try { await host.setWindowKeepScreenOn(oldKeepScreenOn); }
        catch (error) { Log.warn('SourceAcceptance', 'cannot restore keep-screen-on'); }
      }
      SourceAcceptance.running = false;
    }
  }

  /** Exact current PUBLIC WNACG response for independent DOM comparison.
   * Reads only the effective public base URL; never account/cookie/source_data.
   * No Cookie jar send/receive, no refresh-domain bypass, no private paths.
   */
  static async runPublicTemplateProbe(sourceKey: string = 'wnacg'): Promise<string[]> {
    if (sourceKey !== 'wnacg' && sourceKey !== 'ehentai') { throw new Error('公开探针只允许已固定的公开源路径'); }
    if (SourceAcceptance.running) { throw new Error('已有矩阵/模板诊断运行中，请勿重复发请求'); }
    SourceAcceptance.running = true; SourceAcceptance.cancelled = false;
    SourceAcceptance.runId = `public-template-${Date.now()}-${sourceKey}`;
    SourceAcceptance.file = `${AppContext.filesDir}/logs/${SourceAcceptance.runId}.jsonl`;
    SourceAcceptance.notes.clear();
    try {
      SourceAcceptance.emit(sourceKey, 'PUBLIC_PROBE_BEGIN', '同手机公开模板诊断；无Cookie、不登录；不代表全源矩阵');
      if (sourceKey === 'ehentai') { await SourceAcceptance.publicEhCapture(); }
      else { await SourceAcceptance.publicWnacgCapture(); }
      return (SourceAcceptance.notes.get(sourceKey) ?? []).slice();
    } finally { SourceAcceptance.emit(sourceKey, 'PUBLIC_PROBE_END', '公开模板诊断结束'); SourceAcceptance.running = false; }
  }

  /** Fixed public EH root/popular/search only: NEVER use configured ExHentai,
   * watched, favorites, account APIs, current source cookies or login data. */
  private static async publicEhCapture(): Promise<void> {
    if (SourceManager.find('ehentai') === undefined || SourceAcceptance.cancelled) { return; }
    const urls: string[] = ['https://e-hentai.org', 'https://e-hentai.org/popular',
      'https://e-hentai.org/?f_search=a', 'https://e-hentai.org/?f_search=%E9%AD%94%E6%B3%95'];
    for (let index = 0; index < urls.length; index++) {
      if (SourceAcceptance.cancelled) { return; }
      const name = `${SourceAcceptance.runId}-eh-public-${index}`;
      try {
        const options = new HttpRequestOptions(); options.traceId = name;
        options.useCookieJar = false; options.retries = 0; options.maxDecodedBytes = 2 * 1024 * 1024;
        options.connectTimeoutMs = 8000; options.readTimeoutMs = 12000;
        options.headers.set('User-Agent', 'VeneraNext/v1.17.0');
        const response = await HttpClient.request(urls[index], http.RequestMethod.GET, options);
        if (response.body.length > 2 * 1024 * 1024) { throw new Error('公开响应超过导出上限'); }
        const proof: Record<string, Object> = {};
        proof['source'] = 'ehentai'; proof['requestedUrl'] = urls[index]; proof['status'] = response.status;
        proof['requestUserAgent'] = 'VeneraNext/v1.17.0'; proof['cookieJarSent'] = false; proof['cookieJarUpdated'] = false;
        proof['characters'] = response.body.length;
        proof['responseCharsetHeader'] = response.headers.get('content-type') ?? response.headers.get('Content-Type') ?? '';
        // SDK does not expose effective URL/redirect chain here; do not claim
        // that requested URL is the final URL, or export any secret headers.
        proof['redirectChainKnown'] = false; proof['exportIsDecodedTextNotWireBytes'] = true;
        const file = fs.openSync(`${AppContext.filesDir}/logs/${name}.proof.json`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        try { fs.writeSync(file.fd, JSON.stringify(proof)); } finally { fs.closeSync(file); }
        if (response.status === 200) {
          const body = fs.openSync(`${AppContext.filesDir}/logs/${name}.html`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
          try { fs.writeSync(body.fd, response.body); } finally { fs.closeSync(body); }
        }
        SourceAcceptance.emit('ehentai', 'PUBLIC_CAPTURE', `file=${name} status=${response.status} chars=${response.body.length}；无Cookie、无原文日志`);
        if (response.status === 401 || response.status === 403) { break; }
      } catch (error) {
        SourceAcceptance.emit('ehentai', 'PUBLIC_CAPTURE_FAIL', `file=${name} ${SourceAcceptance.message(error)}`);
        break; // One bounded failure, no alternate-host or challenge retries.
      }
    }
  }

  private static async publicWnacgCapture(): Promise<void> {
    const source = SourceManager.find('wnacg');
    if (source === undefined || SourceAcceptance.cancelled) { return; }
    const trace = `${SourceAcceptance.runId}-wnacg-public`;
    try {
      const baseValue = await JsEngine.callJson('ComicSource.sources.wnacg.baseUrl', '<public-wnacg-base>', trace);
      if (typeof baseValue !== 'string' || !/^https:\/\/[a-z0-9.-]+\/?$/i.test(baseValue)) {
        SourceAcceptance.emit('wnacg', 'PUBLIC_CAPTURE_REFUSED', '基址不是无凭据公开HTTPS根路径'); return;
      }
      const base = baseValue.replace(/\/$/, '');
      const host = base.substring(8).toLowerCase();
      if (!/^(?:[a-z0-9-]+\.)?(?:wnacg[0-9]*\.[a-z]{2,}|wnhentai\.com|hentaicomic\.[a-z]{2,})$/.test(host)) {
        SourceAcceptance.emit('wnacg', 'PUBLIC_CAPTURE_REFUSED', '基址不在已知公共域名模式内，不抓取自定义/私人站点'); return;
      }
      const urls = [base, `${base}/search/?q=a&f=_all&s=create_time_DESC&syn=yes&p=1`,
        `${base}/search/?q=${encodeURIComponent('魔法')}&f=_all&s=create_time_DESC&syn=yes&p=1`];
      for (let index = 0; index < urls.length; index++) {
        if (SourceAcceptance.cancelled) { return; }
        const options = new HttpRequestOptions(); options.traceId = trace;
        options.useCookieJar = false; options.retries = 0; options.maxDecodedBytes = 2 * 1024 * 1024;
        options.headers.set('User-Agent', 'VeneraNext/v1.17.0');
        // Public diagnostic must not stall the whole matrix on a blocked host.
        options.connectTimeoutMs = 8000; options.readTimeoutMs = 12000;
        const response = await HttpClient.request(urls[index], http.RequestMethod.GET, options);
        const name = `${SourceAcceptance.runId}-wnacg-public-${index}`;
        if (response.body.length > 2 * 1024 * 1024) { throw new Error('公开诊断HTML超过上限'); }
        const proof: Record<string, Object> = {};
        proof['source'] = 'wnacg'; proof['url'] = urls[index]; proof['status'] = response.status;
        proof['publicPathOnly'] = true; proof['cookieJarSent'] = false; proof['cookieJarUpdated'] = false;
        proof['characters'] = response.body.length;
        proof['requestUserAgent'] = 'VeneraNext/v1.17.0';
        proof['responseCharsetHeader'] = response.headers.get('content-type') ?? response.headers.get('Content-Type') ?? '';
        const file = fs.openSync(`${AppContext.filesDir}/logs/${name}.proof.json`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
        try { fs.writeSync(file.fd, JSON.stringify(proof)); } finally { fs.closeSync(file); }
        if (response.status === 200) {
          const htmlFile = fs.openSync(`${AppContext.filesDir}/logs/${name}.html`, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
          try { fs.writeSync(htmlFile.fd, response.body); } finally { fs.closeSync(htmlFile); }
        }
        SourceAcceptance.emit('wnacg', 'PUBLIC_CAPTURE', `file=${name} status=${response.status} chars=${response.body.length}；无Cookie、无原文日志`);
        if (response.status === 401 || response.status === 403) { break; } // stop, no bypass/retry
      }
    } catch (error) { SourceAcceptance.emit('wnacg', 'PUBLIC_CAPTURE_FAIL', SourceAcceptance.message(error)); }
  }

  private static async test(source: ComicSource, row: AcceptanceRow): Promise<void> {
    try {
      const meta = await JsEngine.callJson('(() => { const s=ComicSource.sources[' + JSON.stringify(source.key) + '];' +
        'if(!s)return null; return {key:s.key,name:s.name,version:s.version,minAppVersion:s.minAppVersion||"", ' +
        'settings:Object.keys(s.settings||{}).map(k=>({key:k,type:s.settings[k].type})), ' +
        'account:s.account?(typeof s.account.login==="function"?"password":"web/cookie"):"none",' +
        'translated:!!(s.translation&&s.translation.zh_CN)};})()', '<acceptance-metadata>');
      if (meta === null) { throw new Error('JS source missing'); }
      const data = meta as Record<string, Object>;
      row.l1 = data['key'] === source.key && typeof data['name'] === 'string' && source.name.length > 0 &&
        /^\d+\.\d+\.\d+/.test(source.version) ? 'METADATA_OK' : 'FAIL_METADATA';
      SourceAcceptance.emit(source.key, 'L1', JSON.stringify(meta));
      if (row.l1 !== 'METADATA_OK') { return; }
      // Each stage is isolated: an unexpected throw in one stage must not erase
      // the other stages' real status or block the downstream chain, otherwise
      // the verification harness itself fabricates "source failures".
      try { row.explore = await SourceAcceptance.explore(source); }
      catch (error) { row.explore = 'FAIL'; SourceAcceptance.emit(source.key, 'L2_EXPLORE', SourceAcceptance.message(error)); }
      try { row.category = await SourceAcceptance.category(source); }
      catch (error) { row.category = 'FAIL'; SourceAcceptance.emit(source.key, 'L2_CATEGORY', SourceAcceptance.message(error)); }
      const samples: SearchSample[] = [];
      for (const keyword of ['a', '魔法']) {
        if (SourceAcceptance.cancelled) { return; }
        samples.push(await SourceAcceptance.search(source, keyword));
      }
      const chosen = samples.find((sample: SearchSample) => sample.passed);
      row.search = chosen !== undefined ? (samples.some((sample: SearchSample): boolean => sample.failedRequest)
        ? 'PARTIAL_KEYWORD_REQUEST_FAILURE' : 'TWO_KEYWORDS_SAMPLED_ONE_PASSED') : 'FAIL_OR_NEEDS_CONFIGURATION';
      let candidate = chosen;
      if (candidate === undefined) {
        const fallback = samples.find((sample: SearchSample) => sample.comics.length > 0 && SourceAcceptance.broken(sample.comics) === 0);
        const publicCandidates = SourceAcceptance.candidates.get(source.key);
        candidate = fallback;
        if (candidate === undefined && publicCandidates !== undefined && publicCandidates.length > 0) {
          candidate = new SearchSample(); candidate.comics = publicCandidates;
          SourceAcceptance.emit(source.key, 'CHAIN_CANDIDATE', '搜索未通过，改用公开探索/分类候选独立测阅读链路；搜索失败状态仍保留');
        }
      }
      if (candidate === undefined) { row.l3 = 'BLOCKED_NO_PUBLIC_CANDIDATE'; return; }
      try {
        row.l3 = await SourceAcceptance.chain(source, candidate);
      } catch (error) {
        row.l3 = 'FAIL_CHAIN';
        SourceAcceptance.emit(source.key, 'L3_ERROR', SourceAcceptance.message(error));
      }
      if (chosen === undefined && row.l3 === 'SAMPLE_CHAIN_OK') { row.l3 = 'SAMPLE_CHAIN_OK_SEARCH_NOT_PASSED'; }
      // Independent stage status: a chain can work while explore/category is
      // broken. Never hide those failures behind a generic "source PASS".
    } catch (error) {
      const message = SourceAcceptance.message(error);
      row.l3 = 'FAIL';
      row.classification = message.includes('IMAGE_CONFIG_UNSUPPORTED')
        ? 'A_APPLICATION_GAP' : 'UNDETERMINED';
      SourceAcceptance.emit(source.key, 'ERROR', message);
    }
  }

  private static broken(comics: Comic[]): number {
    return comics.filter((comic: Comic) => comic.id.length === 0 || comic.title.length === 0 || comic.cover.length === 0).length;
  }

  private static fingerprint(comics: Comic[]): string {
    return comics.map((comic: Comic) => comic.id).join('\u0000');
  }

  private static async search(source: ComicSource, keyword: string): Promise<SearchSample> {
    const sample = new SearchSample();
    sample.keyword = keyword;
    const search = source.search;
    if (search?.loadPage === undefined) { return sample; }
    try {
      const first = await search.loadPage(keyword, 1, []);
      if (first.error) { throw new Error(first.errorMessage ?? 'search failed'); }
      const items = first.dataOrNull ?? [];
      sample.comics = items;
      if (items.length === 0 || SourceAcceptance.broken(items) > 0) {
        SourceAcceptance.emit(source.key, 'L2_SEARCH', `${keyword}:p1=${items.length} broken=${SourceAcceptance.broken(items)}`);
        return sample;
      }
      const cursor = first.subDataString;
      const finite = typeof first.subData === 'number' && Number.isFinite(first.subData) && first.subData <= 1;
      // Komiic explicitly returns maxPage:1 and does not accept a page cursor.
      // Do not invent a second page and call its identical results a port bug.
      if ((!search.cursorOnly && finite) || (search.cursorOnly && (cursor === undefined || cursor.length === 0))) {
        sample.passed = true;
        SourceAcceptance.emit(source.key, 'L2_SEARCH', `${keyword}:p1=${items.length} declaredEnd=true；有限结果，未请求不存在的第二页`);
        return sample;
      }
      if (search.cursorOnly && search.loadNext === undefined) { throw new Error('source cursor loader missing'); }
      const second = search.cursorOnly && search.loadNext !== undefined && cursor !== undefined
        ? await search.loadNext(keyword, cursor, []) : await search.loadPage(keyword, 2, []);
      if (second.error) { throw new Error(second.errorMessage ?? 'page2 failed'); }
      const next = second.dataOrNull ?? [];
      sample.passed = next.length > 0 && SourceAcceptance.broken(next) === 0 &&
        SourceAcceptance.fingerprint(items) !== SourceAcceptance.fingerprint(next);
      SourceAcceptance.emit(source.key, 'L2_SEARCH',
        `${keyword}:p1=${items.length} p2=${next.length} cursorOnly=${search.cursorOnly} different=${sample.passed}`);
    } catch (error) {
      sample.failedRequest = true;
      SourceAcceptance.emit(source.key, 'L2_SEARCH', `${keyword}: ${SourceAcceptance.message(error)}`);
    }
    return sample;
  }

  private static async explore(source: ComicSource): Promise<string> {
    if (source.explorePages.length === 0) { return 'NOT_APPLICABLE'; }
    let ok = true;
    for (let i = 0; i < source.explorePages.length; i++) {
      if (SourceAcceptance.cancelled) { return 'CANCELLED'; }
      try {
        const script = '(async()=>{const e=ComicSource.sources[' + JSON.stringify(source.key) + '].explore[' + i + '];' +
          'const t=e.type||"multiPageComicList";const paged=t==="multiPageComicList";' +
          'const cursor=paged&&typeof e.load!=="function"&&typeof e.loadNext==="function";' +
          'const first=cursor?await e.loadNext(null):await(paged?e.load(1):t==="mixed"?e.load(0):e.load());' +
          'const second=cursor?(first?.next!=null?await e.loadNext(first.next):null):paged?await e.load(2):t==="mixed"?await e.load(1):null;' +
          'return {type:t,cursor,first,second};})()';
        const raw = await JsEngine.callJson(script, '<acceptance-explore>');
        if (raw === null) { throw new Error('empty explore response'); }
        const value = raw as Record<string, Object>;
        const partOk = SourceAcceptance.parts(source.key, i, value['first'] ?? null);
        ok = partOk && ok;
        if (value['type'] === 'multiPageComicList' || value['type'] === 'mixed') {
          if (value['second'] !== null && value['second'] !== undefined) {
            ok = SourceAcceptance.parts(source.key, i, value['second']) && ok;
          } else if (value['cursor'] !== true) { ok = false; }
        }
      } catch (error) {
        ok = false;
        SourceAcceptance.emit(source.key, 'L2_EXPLORE', `page=${i + 1} ${SourceAcceptance.message(error)}`);
      }
    }
    return ok ? 'SAMPLED_PAGES_PARTS_MIXED_0_1_NOT_EXHAUSTIVE' : 'FAIL_OR_UNSUPPORTED_TYPE';
  }

  private static parts(key: string, index: number, raw: Object | null): boolean {
    if (raw === null || raw === undefined) { return false; }
    const value = raw as Record<string, Object>;
    const payload = !Array.isArray(raw) ? value['data'] ?? value['comics'] ?? raw : raw;
    let count = 0;
    let ok = true;
    const inspect = (title: string, list: Object): void => {
      const comics = parseComicList(list, key);
      const broken = SourceAcceptance.broken(comics);
      if (comics.length > 0 && broken === 0 && !SourceAcceptance.candidates.has(key)) {
        SourceAcceptance.candidates.set(key, comics);
      }
      count++;
      ok = ok && comics.length > 0 && broken === 0;
      SourceAcceptance.emit(key, 'L2_EXPLORE_PART', `page=${index + 1} part=${title} items=${comics.length} broken=${broken}`);
    };
    if (Array.isArray(payload)) {
      const list = payload as Object[];
      if (list.some((item: Object) => item !== null && typeof item === 'object' &&
          Array.isArray((item as Record<string, Object>)['comics']))) {
        for (let p = 0; p < list.length; p++) {
          const part = list[p] as Record<string, Object>;
          if (Array.isArray(part['comics'])) { inspect(`#${p + 1}`, part['comics']); }
          else { ok = false; }
        }
      } else { inspect('flat', payload); }
    } else if (typeof payload === 'object') {
      const parts = payload as Record<string, Object>;
      for (const name of Object.keys(parts)) {
        if (Array.isArray(parts[name])) { inspect(name, parts[name]); }
      }
    }
    return count > 0 && ok;
  }

  private static async category(source: ComicSource): Promise<string> {
    if (source.loadCategoryData === undefined) { return 'NOT_APPLICABLE'; }
    let stagePhase = 'landing';
    try {
      const data = await source.loadCategoryData();
      stagePhase = 'parts';
      if (data === undefined || data.parts.length === 0) { return 'FAIL_EMPTY_PARTS'; }
      let ok = true;
      for (let partIndex = 0; partIndex < data.parts.length; partIndex++) {
        const part = data.parts[partIndex];
        const sample = part.items.slice(0, 2);
        let valid = 0;
        for (let itemIndex = 0; itemIndex < sample.length; itemIndex++) {
          const item = sample[itemIndex];
          if (SourceAcceptance.cancelled) { return 'CANCELLED'; }
          let phase = 'target';
          try {
            if (item.label.length === 0 || item.page.length === 0 || item.attributes.size === 0) { continue; }
            if (item.page === 'category') {
              if (source.categoryComics?.load === undefined) {
                SourceAcceptance.emit(source.key, 'L2_CATEGORY_TARGET', '分类目标存在但迁移能力无load；应用/兼容缺口，不能作为静态标签成功'); continue;
              }
              const category = item.attributes.get('category');
              if (category === undefined || category.length === 0) { continue; }
              let options = item.initialOptions?.slice() ?? [];
              if (source.categoryComics.optionsLoader !== undefined) {
                phase = 'options';
                const loaded = await source.categoryComics.optionsLoader(category, item.attributes.get('param'));
                if (loaded.error) { throw new Error(loaded.errorMessage ?? 'category options failed'); }
                phase = 'options_normalize';
                if (options.length === 0) {
                  options = (loaded.dataOrNull ?? []).filter((option) =>
                    (option.showWhen === undefined || option.showWhen.includes(category)) && !option.notShowWhen.includes(category))
                    .map((option) => Array.from(option.options.keys())[0] ?? '');
                }
              }
              phase = 'load';
              const result = await source.categoryComics.load(category, item.attributes.get('param'), options, 1);
              if (result.error) { throw new Error(result.errorMessage ?? 'category target failed'); }
              const comics = result.dataOrNull ?? [];
              if (comics.length > 0 && SourceAcceptance.broken(comics) === 0) {
                valid++; if (!SourceAcceptance.candidates.has(source.key)) { SourceAcceptance.candidates.set(source.key, comics); }
              }
              SourceAcceptance.emit(source.key, 'L2_CATEGORY_TARGET', `实际分类请求items=${comics.length} broken=${SourceAcceptance.broken(comics)}；目标内容不落盘`);
            } else if (item.page === 'search') {
              if (source.search?.loadPage === undefined) { continue; }
              const keyword = item.attributes.get('text') ?? item.attributes.get('keyword');
              if (keyword === undefined) { continue; }
              phase = 'load_search_target';
              const result = await source.search.loadPage(keyword, 1, item.initialOptions ?? []);
              if (result.error) { throw new Error(result.errorMessage ?? 'category search target failed'); }
              const comics = result.dataOrNull ?? [];
              if (comics.length > 0 && SourceAcceptance.broken(comics) === 0) {
                valid++; if (!SourceAcceptance.candidates.has(source.key)) { SourceAcceptance.candidates.set(source.key, comics); }
              }
              SourceAcceptance.emit(source.key, 'L2_CATEGORY_TARGET', `实际搜索目标items=${comics.length} broken=${SourceAcceptance.broken(comics)}；关键词不落盘`);
            } else { SourceAcceptance.emit(source.key, 'L2_CATEGORY_TARGET', `未迁移目标类型=${item.page}；不静默称通过`); }
          } catch (error) {
            // A target failure must not suppress the other sampled targets or
            // later parts. Numeric coordinates avoid logging source parameters.
            SourceAcceptance.emit(source.key, 'L2_CATEGORY_TARGET_FAIL',
              `part=${partIndex + 1} item=${itemIndex + 1} phase=${phase} ${SourceAcceptance.message(error)}`);
          }
        }
        ok = ok && sample.length > 0 && valid === sample.length;
        SourceAcceptance.emit(source.key, 'L2_CATEGORY', `part=${part.title} sampled=${sample.length} executable=${valid}`);
      }
      return ok ? 'PARTS_AND_REAL_TARGETS_SAMPLED_OK_NOT_EXHAUSTIVE' : 'FAIL_TARGETS';
    } catch (error) {
      SourceAcceptance.emit(source.key, 'L2_CATEGORY', `phase=${stagePhase} ${SourceAcceptance.message(error)}`);
      return 'FAIL';
    }
  }

  private static samples(chapters: ComicChapters | undefined): number[] {
    const count = chapters?.length ?? 0;
    if (count <= 1) { return [0]; }
    const selected = [0, count - 1];
    if (count > 2) { selected.push(1 + Math.floor(Math.random() * (count - 2))); }
    if (chapters?.isGrouped) {
      const ids = chapters.ids;
      for (const name of chapters.groupNames) {
        const group = chapters.getGroup(name);
        if (group.size > 0) {
          const index = ids.indexOf(Array.from(group.keys())[0]);
          if (index >= 0 && !selected.includes(index)) { selected.push(index); }
        }
      }
    }
    return selected;
  }

  private static async chain(source: ComicSource, sample: SearchSample): Promise<string> {
    if (source.loadComicInfo === undefined || source.loadComicPages === undefined) { return 'FAIL_CAPABILITIES'; }
    const comic = sample.comics[0];
    const info = await source.loadComicInfo(comic.id);
    if (info.error) { throw new Error(info.errorMessage ?? 'details failed'); }
    const details: ComicDetails | undefined = info.dataOrNull;
    if (details === undefined || details.title.length === 0 || details.cover.length === 0) { return 'FAIL_DETAILS_FIELDS'; }
    SourceAcceptance.emit(source.key, 'L2_DETAILS', `title=true cover=true author=${details.findAuthor() !== undefined} chapters=${details.chapters?.length ?? 0}`);
    let imageOk = true;
    let applicationGap = false;
    try { await SourceAcceptance.probe(source, details.cover, true, comic.id, '', 'cover'); }
    catch (error) {
      imageOk = false;
      applicationGap = SourceAcceptance.message(error).includes('IMAGE_CONFIG_UNSUPPORTED');
      SourceAcceptance.emit(source.key, 'L3_IMAGE_FAIL', `cover ${SourceAcceptance.message(error)}`);
    }
    for (const chapter of SourceAcceptance.samples(details.chapters)) {
      if (SourceAcceptance.cancelled) { return 'CANCELLED'; }
      const ep = details.chapters?.ids[chapter] ?? '';
      const pages = await source.loadComicPages(comic.id, ep);
      if (pages.error) {
        imageOk = false;
        SourceAcceptance.emit(source.key, 'L3_CHAPTER_FAIL', `chapter=${chapter + 1} ${pages.errorMessage ?? 'error'}`);
        continue;
      }
      const urls = pages.dataOrNull ?? [];
      if (urls.length === 0) {
        imageOk = false;
        SourceAcceptance.emit(source.key, 'L3_CHAPTER_FAIL', `chapter=${chapter + 1} no images`);
        continue;
      }
      const indices = Array.from(new Set<number>([0, Math.floor(urls.length / 2), urls.length - 1]));
      for (const page of indices) {
        if (SourceAcceptance.cancelled) { return 'CANCELLED'; }
        try {
          await SourceAcceptance.probe(source, urls[page], false, comic.id, ep, `chapter=${chapter + 1} page=${page + 1}/${urls.length}`);
        } catch (error) {
          imageOk = false;
          applicationGap = applicationGap || SourceAcceptance.message(error).includes('IMAGE_CONFIG_UNSUPPORTED');
          SourceAcceptance.emit(source.key, 'L3_IMAGE_FAIL', `chapter=${chapter + 1} page=${page + 1} ${SourceAcceptance.message(error)}`);
        }
      }
    }
    return applicationGap ? 'FAIL_APPLICATION_IMAGE_GAP' : imageOk ? 'SAMPLE_CHAIN_OK' : 'FAIL_IMAGES_OR_CHAPTERS';
  }

  private static async probe(source: ComicSource, url: string, thumbnail: boolean,
    comicId: string, ep: string, label: string): Promise<void> {
    const config = await ImageRequests.resolve(source, url, thumbnail, comicId, ep,
      `${SourceAcceptance.runId}-${source.key}`);
    const bytes = await ImagePipeline.fetch(config, `${SourceAcceptance.runId}-${source.key}`,
      (): boolean => !SourceAcceptance.cancelled);
    const decoder = image.createImageSource(bytes);
    try {
      const pixel = await decoder.createPixelMap();
      try {
        const info = await pixel.getImageInfo();
        if (info.size.width <= 0 || info.size.height <= 0) { throw new Error('invalid dimensions'); }
        SourceAcceptance.emit(source.key, 'L3_IMAGE', `${label} decoded=${info.size.width}x${info.size.height} thumbnail=${thumbnail} modified=${config.modifyImage.length > 0}；解码不等于真实内容人工验收`);
      } finally { await pixel.release(); }
    } finally { await decoder.release(); }
  }

  private static message(error: Object): string {
    const text = error instanceof Error ? error.message : String(error);
    return text.replace(/https?:\/\/\S+/g, '[URL]').slice(0, 240);
  }
}
