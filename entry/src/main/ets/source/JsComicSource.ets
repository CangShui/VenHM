import { Comic } from '../model/Comic';
import { ComicChapters } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { Res } from '../model/Res';
import { parseComic, parseComicList, parseStringList } from '../model/Comic';
import {
  AccountConfig, CategoryComicsData, CategoryComicsOptions, CategoryData, CategoryItem, CategoryPart, ComicSource,
  ExplorePageData, ExplorePageType, SearchPageData, ImageRequestConfig
} from './ComicSource';
import { JsEngine } from './JsEngine';
import { JsSearchOptionsAdapter } from './JsSearchOptionsAdapter';
import { JsRankingAdapter } from './JsRankingAdapter';
import { JsDetailsAdapter } from './JsDetailsAdapter';
import { JsFavoritesAdapter } from './JsFavoritesAdapter';
import { SourceDataStore } from './SourceDataStore';
import { compareSemVer } from '../foundation/Semver';
import { APP_VERSION } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { ImageConfigParser } from './ImageConfigParser';
import { BrowserLoginSnapshot } from '../model/BrowserLogin';
import { CookieJar, CookieImportReceipt } from '../network/CookieJar';
import { AuthLogScope } from './AuthLogScope';
import { toStringOrNull, toIntOrNull } from '../foundation/Extensions';
import { CacheManager } from '../storage/CacheSettings';

/**
 * A comic source backed by a `.js` script running in QuickJS.
 *
 * Dart original: lib/features/comic_source/parser.dart built a `ComicSource`
 * whose callbacks were Dart closures that invoked JS. ArkTS cannot hold JS
 * function handles, so each capability re-evaluates an expression against the
 * script's registered instance (`ComicSource.sources[key]`) and reads the
 * result back as JSON via JsEngine.callJson.
 */
export class JsComicSource extends ComicSource {
  private readonly scriptPath: string;
  private accountBusy: boolean = false;

  constructor(key: string, name: string, version: string, scriptPath: string) {
    super(key, name);
    this.version = version;
    this.scriptPath = scriptPath;
  }

  /** JS accounts live in SourceDataStore, not ComicSource's base dataStore. */
  override get isLogged(): boolean {
    const account = SourceDataStore.get(this.key, 'account');
    return account !== null && account !== undefined;
  }

  /** Build a JS expression targeting this source instance. */
  private expr(path: string): string {
    return `ComicSource.sources[${JSON.stringify(this.key)}].${path}`;
  }

  /** Quote a JS argument. Missing values become `null`, not `""`, because
   *  scripts branch on falsy/absent ep ids (a single-chapter comic has none). */
  private static arg(value: string | undefined | null): string {
    return JSON.stringify(value === undefined || value === null ? null : value);
  }

  private static argNumber(value: number): string {
    return `${value}`;
  }

  private static argArray(values: string[]): string {
    return JSON.stringify(values);
  }

  /** Enable the capabilities the script actually declares. */
  configure(has: Record<string, Object>, exploreTitles: string[], exploreTypes: Object[],
    accountMeta?: Record<string, Object>, exploreCursorFlags: boolean[] = []): void {
    if (has['search'] === true || has['searchNext'] === true) {
      this.setupSearch(has['search'] === true, has['searchNext'] === true);
    }
    if (has['explore'] === true) {
      this.setupExplore(exploreTitles, exploreTypes, exploreCursorFlags);
    }
    if (has['loadInfo'] === true) {
      this.loadComicInfo = (id: string): Promise<Res<ComicDetails>> => this.jsLoadInfo(id);
      // Instant paint from disk; the page still refreshes over the network.
      this.loadCachedComicInfo = (id: string): Promise<ComicDetails | undefined> => this.cachedInfo(id);
    }
    if (has['loadEp'] === true) {
      this.loadComicPages = (id: string, ep?: string): Promise<Res<string[]>> =>
        this.jsLoadEp(id, ep);
    }
    this.detailsMedia = JsDetailsAdapter.create(this.key, this.scriptPath, has);
    this.loadComicComments = this.detailsMedia.loadComments;
    this.loadChapterComments = this.detailsMedia.loadChapterComments;
    if (has['favorites'] === true) {
      this.favoriteData = JsFavoritesAdapter.create(this.key, this.scriptPath,
        has['favoritesPage'] === true, has['favoritesNext'] === true,
        has['favoritesFolders'] === true, has['favoritesMutation'] === true,
        has['favoritesMultiFolder'] === true);
      this.favoriteData.title = this.name;
    }
    if (has['onImageLoad'] === true) {
      this.getImageConfig = (url: string, comicId: string, epId: string, trace?: string):
        Promise<ImageRequestConfig> => this.jsImageConfig(url, comicId, epId, 'onImageLoad', trace);
    }
    if (has['onThumbnailLoad'] === true) {
      this.getThumbnailConfig = (url: string, trace?: string): Promise<ImageRequestConfig> =>
        this.jsImageConfig(url, '', '', 'onThumbnailLoad', trace);
    }
    if (has['account'] === true) {
      const account = new AccountConfig();
      if (has['passwordLogin'] === true) {
        account.login = (user: string, password: string, trace?: string): Promise<Res<boolean>> => this.jsLogin(user, password, trace);
        account.canRelogin = (): boolean => {
          const saved = SourceDataStore.get(this.key, 'account');
          return Array.isArray(saved) && saved.length === 2 && typeof saved[0] === 'string' && typeof saved[1] === 'string';
        };
        account.relogin = async (trace?: string): Promise<Res<boolean>> => {
          const saved = SourceDataStore.get(this.key, 'account');
          if (!Array.isArray(saved) || saved.length !== 2 || typeof saved[0] !== 'string' || typeof saved[1] !== 'string') {
            Log.audit(trace ?? 'source-relogin', '重新登录拒绝', '没有已保存的密码账号元组；不能把Cookie/Web标记当密码');
            return Res.fail<boolean>('没有可重新登录的已保存账号');
          }
          return this.jsLogin(saved[0] as string, saved[1] as string, trace);
        };
      }
      account.logout = (): Promise<void> => this.jsLogout();
      if (accountMeta !== undefined) {
        const webUrl = toStringOrNull(accountMeta['webUrl']);
        const registerUrl = toStringOrNull(accountMeta['registerUrl']);
        if (webUrl !== undefined && webUrl.length > 0 && accountMeta['hasWebCheck'] === true) {
          account.loginWebsite = webUrl;
          account.checkLoginStatus = (url: string, title: string, trace?: string): Promise<boolean> =>
            this.jsCheckWebLogin(url, title, trace);
          account.finishWebLogin = (snapshot: BrowserLoginSnapshot, current: () => boolean, trace?: string):
            Promise<Res<boolean>> => this.jsFinishWebLogin(snapshot, current, trace);
        }
        account.registerWebsite = registerUrl;
        const fields = parseStringList(accountMeta['cookieFields']);
        const rawFields = accountMeta['cookieFields'];
        if (Array.isArray(rawFields) && (rawFields as Object[]).every((field: Object) => typeof field === 'string') &&
          accountMeta['hasCookieValidate'] === true) {
          account.cookieFields = fields;
          account.validateCookies = (values: string[], trace?: string): Promise<Res<boolean>> =>
            this.jsCookieLogin(values, trace);
        }
      }
      this.account = account;
    }
    if (has['settings'] === true) {
      this.description = '含源设置项，可从源设置入口配置';
    }
    if (has['category'] === true || has['categoryLanding'] === true) {
      this.loadCategoryData = (): Promise<CategoryData | undefined> => this.jsCategoryData();
    }
    if (has['category'] === true) {
      const categoryComics = new CategoryComicsData();
      if (has['categoryLoad'] !== false) {
        categoryComics.load = (category: string, param: string | undefined,
          options: string[], page: number): Promise<Res<Comic[]>> => this.jsCategoryLoad(category, param, options, page);
      }
      categoryComics.optionsLoader = (category: string, param?: string): Promise<Res<CategoryComicsOptions[]>> =>
        this.jsCategoryOptions(category, param);
      if (has['ranking'] === true) {
        categoryComics.rankingData = JsRankingAdapter.create(this.key, this.scriptPath,
          has['rankingLoad'] === true, has['rankingNext'] === true);
      }
      this.categoryComics = categoryComics;
    }
    if (has['onClickTag'] === true) {
      this.tagTarget = (namespace: string, tag: string): Promise<CategoryItem | undefined> => this.jsTagTarget(namespace, tag);
    }
  }

  /**
   * Run the script's `account.login(account, password)`.
   * On success the credentials are stored under "account" so `isLogged` (and
   * `loadData("account")` inside the script) report a logged-in state.
   */
  private async jsLogin(user: string, password: string, requestTrace?: string): Promise<Res<boolean>> {
    const trace = requestTrace ?? `source-login-${Date.now()}-${this.key}`;
    Log.audit(trace, '登录到达', '准备调用站点login；账号、密码、Cookie和脚本请求内容不落盘');
    if (this.accountBusy) {
      Log.audit(trace, '登录拒绝', '该源已有登录/登出在执行；未调用站点');
      return Res.fail<boolean>('该源已有登录/登出在执行');
    }
    this.accountBusy = true;
    const baseline = SourceDataStore.failureEpoch(this.key);
    const logScope = AuthLogScope.enter(trace);
    try {
      await JsEngine.callJson(
        `${this.expr('account.login')}(${JsComicSource.arg(user)}, ` +
        `${JsComicSource.arg(password)})`,
        this.scriptPath, trace);
      await SourceDataStore.awaitSourceWrites(this.key, baseline, trace);
      // Upstream parser.dart treats a completed login call as success, whatever
      // its return value (copy_manga returns "ok", komga returns a username).
      Log.audit(trace, '站点登录返回', '脚本login正常完成；等待账号状态有序落盘，不能提前显示登录成功');
      await SourceDataStore.setAndWait(this.key, 'account', [user, password], trace);
      Log.audit(trace, '登录返回', '账号状态已落盘；站点能力还需真实账号操作验收');
      return new Res<boolean>(true);
    } catch (error) {
      Log.audit(trace, '登录异常', '脚本或数据库失败；不显示登录成功；不记录凭据/服务器正文');
      return Res.fail<boolean>(JsComicSource.messageOf(error));
    } finally { AuthLogScope.leave(logScope); this.accountBusy = false; }
  }

  private async jsLogout(): Promise<void> {
    const trace = `source-logout-${Date.now()}-${this.key}`;
    Log.audit(trace, '登出到达', '准备等待站点logout，再删除已保存的账号状态');
    if (this.accountBusy) {
      Log.audit(trace, '登出拒绝', '该源已有登录/登出在执行；不会并发清理新会话');
      throw new Error('该源已有登录/登出在执行');
    }
    this.accountBusy = true;
    const baseline = SourceDataStore.failureEpoch(this.key);
    const logScope = AuthLogScope.enter(trace);
    try {
      await JsEngine.callJson(`typeof ${this.expr('account.logout')} === 'function' ? ` +
        `${this.expr('account.logout')}() : undefined`, this.scriptPath, trace);
      await SourceDataStore.awaitSourceWrites(this.key, baseline, trace);
      await SourceDataStore.removeAndWait(this.key, 'account', trace);
      Log.audit(trace, '登出返回', '站点回调和账号状态删除均完成；脚本自己负责对应Cookie清理');
    } catch (error) {
      Log.audit(trace, '登出异常', '站点/数据库失败；不冒充退出成功，不强删其他源Cookie');
      throw new Error(JsComicSource.messageOf(error));
    } finally { AuthLogScope.leave(logScope); this.accountBusy = false; }
  }

  private async jsCookieLogin(values: string[], requestTrace?: string): Promise<Res<boolean>> {
    const trace = requestTrace ?? `source-cookie-login-${Date.now()}-${this.key}`;
    Log.audit(trace, 'Cookie登录到达', `字段数=${values.length}；只由用户页面提交；字段值不落盘`);
    if (this.accountBusy || values.length !== this.account?.cookieFields?.length) {
      Log.audit(trace, 'Cookie登录拒绝', '已有账号操作或字段数量不符合源声明；未调用validate');
      return Res.fail<boolean>('账号操作正忙或Cookie字段数量不正确');
    }
    this.accountBusy = true;
    const baseline = SourceDataStore.failureEpoch(this.key);
    const logScope = AuthLogScope.enter(trace);
    try {
      const result = await JsEngine.callJson(`${this.expr('account.loginWithCookies.validate')}(` +
        `${JSON.stringify(values)})`, this.scriptPath, trace);
      if (result !== true) {
        Log.audit(trace, 'Cookie登录校验拒绝', '站点validate未返回true；未标记登录成功');
        return new Res<boolean>(false);
      }
      await SourceDataStore.awaitSourceWrites(this.key, baseline, trace);
      await SourceDataStore.setAndWait(this.key, 'account', 'ok', trace);
      Log.audit(trace, 'Cookie登录返回', '站点validate=true且账号标记已落盘；需要真实账号/冷启动验收');
      return new Res<boolean>(true);
    } catch (error) {
      Log.audit(trace, 'Cookie登录异常', '源校验/持久化失败；不记录Cookie值或站点正文');
      return Res.fail<boolean>('Cookie校验或保存失败，请重试');
    } finally { AuthLogScope.leave(logScope); this.accountBusy = false; }
  }

  private async jsCheckWebLogin(url: string, title: string, requestTrace?: string): Promise<boolean> {
    const trace = requestTrace ?? `source-web-check-${Date.now()}-${this.key}`;
    const logScope = AuthLogScope.enter(trace);
    Log.audit(trace, '网页登录校验到达', '传入当前页面URL与标题；内容不落盘');
    try {
      const result = await JsEngine.callJson(`${this.expr('account.loginWithWebview.checkStatus')}(` +
        `${JSON.stringify(url)},${JSON.stringify(title)})`, this.scriptPath, trace);
      Log.audit(trace, '网页登录校验返回', `登录条件满足=${result === true}；尚未提交会话`);
      return result === true;
    } catch (error) {
      Log.audit(trace, '网页登录校验异常', '不将回调异常或非布尔值当作登录成功');
      throw new Error('网页登录状态校验失败');
    } finally { AuthLogScope.leave(logScope); }
  }

  private async jsFinishWebLogin(snapshot: BrowserLoginSnapshot, current: () => boolean, requestTrace?: string):
    Promise<Res<boolean>> {
    const trace = requestTrace ?? `source-web-finish-${Date.now()}-${this.key}`;
    Log.audit(trace, '网页登录提交到达', `Cookie数=${snapshot.cookies.length}；准备校验→暂存→回调→账号标记`);
    if (this.accountBusy || !current()) {
      Log.audit(trace, '网页登录提交拒绝', '账号操作正忙或网页已退出/变更；不导入凭据');
      return Res.fail<boolean>('网页状态已变化或账号操作正忙');
    }
    this.accountBusy = true;
    const baseline = SourceDataStore.failureEpoch(this.key);
    const logScope = AuthLogScope.enter(trace);
    const previousStorage = SourceDataStore.get(this.key, '_localStorage');
    const previousAccount = SourceDataStore.get(this.key, 'account');
    const imports: CookieImportReceipt[] = [];
    let staged = false;
    let markerWritten = false;
    try {
      if (!await this.jsCheckWebLogin(snapshot.url, snapshot.title, trace) || !current()) {
        Log.audit(trace, '网页登录二次校验拒绝', '条件不满足或页面变更；未提交');
        return new Res<boolean>(false);
      }
      await SourceDataStore.setAndWait(this.key, '_localStorage', snapshot.localStorage, trace);
      staged = true;
      if (!current()) { throw new Error('网页已退出'); }
      // All cookies are validated against the actual page host, not a source's arbitrary URL.
      imports.push(CookieJar.importBrowser(snapshot.url, snapshot.cookies, trace));
      await JsEngine.callJson(`typeof ${this.expr('account.loginWithWebview.onLoginSuccess')} === 'function' ? ` +
        `${this.expr('account.loginWithWebview.onLoginSuccess')}() : undefined`, this.scriptPath, trace);
      await SourceDataStore.awaitSourceWrites(this.key, baseline, trace);
      if (!current()) { throw new Error('网页已退出'); }
      await SourceDataStore.setAndWait(this.key, 'account', 'ok', trace);
      markerWritten = true;
      if (!current()) { throw new Error('网页已退出'); }
      Log.audit(trace, '网页登录提交返回', 'localStorage、Cookie、异步success回调与账号标记均完成；不保存浏览器整个全局会话');
      return new Res<boolean>(true);
    } catch (error) {
      if (markerWritten) {
        try { await SourceDataStore.restoreIfCurrent(this.key, 'account', 'ok', previousAccount, trace); }
        catch (rollbackError) { Log.audit(trace, '账号标记回滚异常', '未确认取消后的账号状态，不能宣称已清除'); }
      }
      for (const receipt of imports) {
        try { CookieJar.rollbackBrowser(receipt, trace); }
        catch (rollbackError) { Log.audit(trace, '网页Cookie回滚异常', '没有清除其他域；需要重试/查看会话状态'); }
      }
      if (staged) {
        try { await SourceDataStore.restoreIfCurrent(this.key, '_localStorage', snapshot.localStorage, previousStorage, trace); }
        catch (rollbackError) { Log.audit(trace, '网页存储回滚异常', '数据状态未确认，未宣称登录成功'); }
      }
      Log.audit(trace, '网页登录提交异常', '本次暂存尝试恢复；源callback自身副作用无法通用撤销；未确认账号成功');
      return Res.fail<boolean>('网页会话校验或保存失败，请重试');
    } finally { AuthLogScope.leave(logScope); this.accountBusy = false; }
  }

  /** Normalize modern and legacy PageJumpTarget in the source realm. */
  private static readonly TARGET_HELPER: string =
    'const target=(t)=>{let page,attributes={};' +
    'if(typeof t==="string"){const cut=t.indexOf(":");page=cut<0?t:t.slice(0,cut);const value=cut<0?"":t.slice(cut+1);' +
    'if(page==="search")attributes={text:value};else if(page==="category"){const at=value.indexOf("@");attributes={category:at<0?value:value.slice(0,at),param:at<0?null:value.slice(at+1)};}}' +
    'else if(t&&typeof t==="object"){if(t.page!=null){page=t.page;attributes=t.attributes||{};}' +
    'else if(t.action!=null){page=t.action;attributes=page==="search"?{text:t.keyword}:{category:t.keyword,param:t.param};}}' +
    'if(typeof page!=="string"||!attributes||typeof attributes!=="object"||Array.isArray(attributes))throw Error("SOURCE_TARGET_INVALID");' +
    'const options=attributes.options;if(options!=null&&(!Array.isArray(options)||options.some(v=>typeof v!=="string")))throw Error("SOURCE_TARGET_OPTIONS_INVALID");' +
    'const clean={};for(const [k,v]of Object.entries(attributes)){if(k!=="options"&&v!=null){if(typeof v!=="string")throw Error("SOURCE_TARGET_ATTRIBUTE_INVALID");clean[k]=v;}}' +
    'return {page,attributes:clean,initialOptions:options||[]};};';

  private static targetItem(value: Object, label: string): CategoryItem {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error('源标签/分类目标不是有效对象'); }
    const record = value as Record<string, Object>;
    const page = toStringOrNull(record['page']);
    if (page === undefined || page.length === 0) { throw new Error('源标签/分类目标缺少页面类型'); }
    const item = new CategoryItem(); item.label = label; item.page = page;
    const attributes = record['attributes'];
    if (attributes === null || typeof attributes !== 'object' || Array.isArray(attributes)) { throw new Error('源标签/分类属性格式无效'); }
    const map = attributes as Record<string, Object>;
    for (const name of Object.keys(map)) {
      if (typeof map[name] !== 'string') { throw new Error('源标签/分类属性必须为字符串'); }
      item.attributes.set(name, map[name] as string);
    }
    const options = record['initialOptions'];
    if (!Array.isArray(options) || !(options as Object[]).every((option: Object) => typeof option === 'string')) {
      throw new Error('源标签/分类 options 格式无效');
    }
    item.initialOptions = (options as string[]).slice(); return item;
  }

  private async jsTagTarget(namespace: string, tag: string): Promise<CategoryItem | undefined> {
    const trace = `tag-target-${Date.now()}-${this.key}`;
    Log.audit(trace, '源标签目标到达', '使用原始namespace/value，不输出标签内容');
    const value = await JsEngine.callJson('(async()=>{' + JsComicSource.TARGET_HELPER +
      `const raw=await ${this.expr('comic.onClickTag')}(${JSON.stringify(namespace)},${JSON.stringify(tag)});` +
      'if(raw==null)return null;if(typeof raw!=="object"||Array.isArray(raw))throw Error("SOURCE_TAG_TARGET_INVALID");return target(raw);})()', this.scriptPath, trace);
    if (value === null || value === undefined) { return undefined; }
    const item = JsComicSource.targetItem(value, namespace.length > 0 ? `${namespace}:${tag}` : tag);
    Log.audit(trace, '源标签目标返回', `页面类型=${item.page}；筛选项数=${item.initialOptions.length}`); return item;
  }

  private static categoryOptions(value: Object | null): CategoryComicsOptions[] {
    if (!Array.isArray(value)) { throw new Error('分类 optionLoader 必须返回数组'); }
    const result: CategoryComicsOptions[] = [];
    for (const raw of value as Object[]) {
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('分类选项组必须是对象'); }
      const item = raw as Record<string, Object>; const group = new CategoryComicsOptions();
      group.label = toStringOrNull(item['label']) ?? '';
      const options = item['options'];
      if (options !== undefined && options !== null && !Array.isArray(options)) { throw new Error('分类 options 必须为数组'); }
      for (const option of (options ?? []) as Object[]) {
        if (typeof option !== 'string') { throw new Error('分类 option 必须为字符串'); }
        const split = option.indexOf('-'); if (split < 0) { continue; }
        group.options.set(option.slice(0, split), option.slice(split + 1));
      }
      for (const name of ['showWhen', 'notShowWhen']) {
        const conditions = item[name];
        if (conditions !== undefined && conditions !== null &&
          (!Array.isArray(conditions) || !(conditions as Object[]).every((entry: Object) => typeof entry === 'string'))) {
          throw new Error('分类选项显示条件必须为字符串数组');
        }
        if (name === 'showWhen' && conditions !== undefined && conditions !== null) { group.showWhen = (conditions as string[]).slice(); }
        if (name === 'notShowWhen') { group.notShowWhen = conditions === undefined || conditions === null ? [] : (conditions as string[]).slice(); }
      }
      result.push(group);
    }
    return result;
  }
  private async jsCategoryOptions(category: string, param?: string): Promise<Res<CategoryComicsOptions[]>> {
    const trace = `category-options-${Date.now()}-${this.key}`;
    try {
      const value = await JsEngine.callJson(`(async()=>{const c=${this.expr('categoryComics')};return typeof c.optionLoader==='function'?await c.optionLoader(` +
        `${JsComicSource.arg(category)},${JsComicSource.arg(param)}):(c.optionList??[]);})()`, this.scriptPath, trace);
      return Res.ok<CategoryComicsOptions[]>(JsComicSource.categoryOptions(value));
    } catch (error) { return Res.fail<CategoryComicsOptions[]>(JsComicSource.messageOf(error)); }
  }

  /** Category landing structure (parts + tappable entries). */
  private async jsCategoryData(): Promise<CategoryData | undefined> {
    try {
      const value = await JsEngine.callJson(
        '(async()=>{' + JsComicSource.TARGET_HELPER +
        `const s=ComicSource.sources[${JSON.stringify(this.key)}];` +
        'if(!s||!s.category)return null;const parts=[];const sourceParts=s.category.parts||[];' +
        'for(const p of sourceParts){if(!p)continue;let cats=p.categories;' +
        'if(p.type==="dynamic"&&cats==null){if(typeof p.loader!=="function")throw Error("DYNAMIC_CATEGORY_LOADER_MISSING");cats=await p.loader();}' +
        'if(!Array.isArray(cats))throw Error("CATEGORY_PART_ITEMS_INVALID");const items=[];' +
        'for(let i=0;i<cats.length;i++){const c=cats[i];let parsed;' +
        'if(c&&typeof c==="object"){if(typeof c.label!=="string")throw Error("CATEGORY_LABEL_INVALID");parsed=target(c.target);parsed.label=c.label;}' +
        'else if(typeof c==="string"){const kind=p.itemType||"category";let page=kind,attributes={};' +
        'if(kind==="category"){attributes={category:c,param:p.groupParam!=null?p.groupParam:p.categoryParams?.[i]};}' +
        'else if(kind==="search"||kind==="search_with_namespace"){page="search";attributes={keyword:kind==="search"?c:p.name+":"+c};}' +
        'parsed=target({page,attributes});parsed.label=c;}' +
        'else throw Error("CATEGORY_ITEM_INVALID");items.push(parsed);}' +
        'if(items.length>0){let shown=items;if(p.type==="random"){const n=Math.max(1,Math.min(items.length,Number(p.randomNumber)||1));const start=Math.floor(Math.random()*(items.length-n+1));shown=items.slice(start,start+n);}parts.push({title:p.name||"",items:shown});}}' +
        'return {title:s.category.title||"",parts,enableRankingPage:s.category.enableRankingPage===true};})()',
        this.scriptPath, `category-landing-${Date.now()}-${this.key}`);
      if (value === null || value === undefined) {
        return undefined;
      }
      const parsed = value as Record<string, Object>;
      const data = new CategoryData();
      data.title = toStringOrNull(parsed['title']) ?? this.name;
      data.enableRankingPage = parsed['enableRankingPage'] === true;
      const rawParts = parsed['parts'];
      if (Array.isArray(rawParts)) {
        const partList = rawParts as Object[];
        for (let i = 0; i < partList.length; i++) {
          const partRecord = partList[i] as Record<string, Object>;
          const part = new CategoryPart();
          part.title = toStringOrNull(partRecord['title']) ?? '';
          const rawItems = partRecord['items'];
          if (Array.isArray(rawItems)) {
            const itemList = rawItems as Object[];
            for (let j = 0; j < itemList.length; j++) {
              const itemRecord = itemList[j] as Record<string, Object>;
              part.items.push(JsComicSource.targetItem(itemRecord, toStringOrNull(itemRecord['label']) ?? ''));
            }
          }
          data.parts.push(part);
        }
      }
      return data;
    } catch (error) {
      Log.audit(`category-landing-${Date.now()}-${this.key}`, '分类落地异常', '源返回或桥接异常，向UI传播错误；参数内容不落盘');
      throw new Error(JsComicSource.messageOf(error));
    }
  }

  private async jsCategoryLoad(category: string, param: string | undefined,
                               options: string[], page: number): Promise<Res<Comic[]>> {
    try {
      const value = await JsEngine.callJson(
        `${this.expr('categoryComics.load')}(${JsComicSource.arg(category)}, ` +
        `${JsComicSource.arg(param)}, ${JsComicSource.argArray(options)}, ` +
        `${JsComicSource.argNumber(page)})`,
        this.scriptPath);
      return JsComicSource.toComicListResult(value, this.key);
    } catch (error) {
      return Res.fail<Comic[]>(JsComicSource.messageOf(error));
    }
  }

  private setupSearch(hasPage: boolean, hasNext: boolean): void {
    const page = new SearchPageData();
    page.optionsLoader = () => JsSearchOptionsAdapter.load(this.key, this.scriptPath);
    page.cursorOnly = !hasPage && hasNext;
    if (hasPage) {
      page.loadPage = (keyword: string, pageNumber: number, options: string[]):
        Promise<Res<Comic[]>> => this.jsSearch(keyword, options, pageNumber);
    } else if (hasNext) {
      // Upstream parser.dart chooses loadNext when load is absent. The first
      // request has no cursor; it must receive null, not page number 1.
      page.loadPage = (keyword: string, pageNumber: number, options: string[]):
        Promise<Res<Comic[]>> => this.jsSearchNext(keyword, options, undefined);
    }
    if (hasNext) {
      page.loadNext = (keyword: string, next: string, options: string[]):
        Promise<Res<Comic[]>> => this.jsSearchNext(keyword, options, next);
    }
    this.search = page;
  }

  private setupExplore(titles: string[], types: Object[], cursors: boolean[]): void {
    const pages: ExplorePageData[] = [];
    for (let i = 0; i < titles.length; i++) {
      const explore = new ExplorePageData();
      explore.title = titles[i];
      explore.type = JsComicSource.explorePageType(i < types.length ? types[i] : undefined);
      const cursor = i < cursors.length && cursors[i];
      explore.cursorOnly = cursor;
      explore.loadPage = (page: number): Promise<Res<Comic[]>> => cursor ? this.jsExploreNext(i, undefined) : this.jsExplore(i, page);
      if (cursor) { explore.loadNext = (next: string): Promise<Res<Comic[]>> => this.jsExploreNext(i, next); }
      pages.push(explore);
    }
    this.explorePages = pages;
    this.exploreTypes = types;
  }

  /**
   * Explore page kinds. Upstream switches on the *string* `explore[i].type`
   * ("singlePageWithMultiPart" / "multiPageComicList" / "multiPartPage" /
   * "mixed"); comparing it against 1/2 silently sent every `mixed` source down
   * the `{comics, maxPage}` path.
   */
  private static explorePageType(type: Object | undefined): ExplorePageType {
    if (type === 'singlePageWithMultiPart' || type === 'multiPartPage') {
      return ExplorePageType.singlePageWithMultiPart;
    }
    if (type === 'mixed') {
      return ExplorePageType.mixed;
    }
    return ExplorePageType.multiPageComicList;
  }

  /** Raw `type` values, index-aligned with `explorePages`. */
  private exploreTypes: Object[] = [];

  /**
   * Normalise `{comics, maxPage}` / `{comics, next}` / bare array results.
   *
   * `value` is the source's return value converted by the native bridge, so a
   * `Map` of chapters or a `Set` of ids has already become an object/array.
   */
  private static toComicListResult(value: Object | null, sourceKey: string): Res<Comic[]> {
    if (value === null || value === undefined) {
      return new Res<Comic[]>([]);
    }
    const list = JsComicSource.asList(value);
    if (list !== undefined) {
      return new Res<Comic[]>(JsComicSource.checked(parseComicList(list, sourceKey), value, sourceKey));
    }
    const record = value as Record<string, Object>;
    const comics = parseComicList(record['comics'], sourceKey);
    const sub = record['maxPage'] ?? record['next'];
    return new Res<Comic[]>(JsComicSource.checked(comics, value, sourceKey), undefined, sub);
  }

  /** Log the raw payload when parsing lost information. */
  private static checked(comics: Comic[], value: Object | null, sourceKey: string): Comic[] {
    const empty = comics.length === 0;
    const lost = comics.length > 0 && comics[0].id.length === 0 && comics[0].title.length === 0;
    if (empty || lost) {
      Log.audit(`source-parse-${sourceKey}`, '漫画列表结构检查',
        `可用条目=${comics.length}；首项字段缺失=${lost}；不记录原始响应正文`);
    }
    return comics;
  }

  /** Short readable form of a payload, for diagnostics only. */
  private static preview(value: Object | null): string {
    if (value === null || value === undefined) {
      return 'null';
    }
    try {
      const text = JSON.stringify(value);
      return text === undefined ? String(value) : (text.length > 500 ? text.substring(0, 500) : text);
    } catch (error) {
      return String(value);
    }
  }

  private searchOptionsExpression(options: string[]): string {
    // Original search option types are positional. Missing UI selections must
    // be filled from source defaults, especially multi-select JSON arrays.
    return `(()=>{const groups=${this.expr('search.optionList')}||[];const supplied=${JSON.stringify(options)};` +
      'const out=groups.map((g,i)=>{if(supplied[i]!==undefined)return supplied[i];' +
      'if(g.type==="multi-select")return JSON.stringify(Array.isArray(g.default)?g.default:[]);' +
      'if(g.default!=null)return typeof g.default==="string"?g.default:String(g.default);' +
      'if(g.type==="dropdown")return null;const first=(g.options||[]).find(v=>typeof v==="string"&&v.includes("-"));' +
      'return first===undefined?null:first.slice(0,first.indexOf("-"));});' +
      'if(supplied.length>out.length)out.push(...supplied.slice(out.length));return out;})()';
  }

  private async jsSearch(keyword: string, options: string[], page: number): Promise<Res<Comic[]>> {
    try {
      const value = await JsEngine.callJson(
        `${this.expr('search.load')}(${JsComicSource.arg(keyword)}, ` +
        `${this.searchOptionsExpression(options)}, ${JsComicSource.argNumber(page)})`,
        this.scriptPath);
      return JsComicSource.toComicListResult(value, this.key);
    } catch (error) {
      return Res.fail<Comic[]>(JsComicSource.messageOf(error));
    }
  }

  private async jsSearchNext(keyword: string, options: string[], next: string | undefined): Promise<Res<Comic[]>> {
    try {
      const value = await JsEngine.callJson(
        `${this.expr('search.loadNext')}(${JsComicSource.arg(keyword)}, ` +
        `${this.searchOptionsExpression(options)}, ${JsComicSource.arg(next)})`,
        this.scriptPath);
      return JsComicSource.toComicListResult(value, this.key);
    } catch (error) {
      return Res.fail<Comic[]>(JsComicSource.messageOf(error));
    }
  }

  private async jsExploreNext(index: number, next?: string): Promise<Res<Comic[]>> {
    try {
      const value = await JsEngine.callJson(`${this.expr(`explore[${index}].loadNext`)}(${JsComicSource.arg(next)})`,
        this.scriptPath, `explore-cursor-${Date.now()}-${this.key}-${index}`);
      return JsComicSource.toComicListResult(value, this.key);
    } catch (error) { return Res.fail<Comic[]>(JsComicSource.messageOf(error)); }
  }

  private async jsExplore(index: number, page: number): Promise<Res<Comic[]>> {
    const rawType = index < this.exploreTypes.length ? this.exploreTypes[index] : undefined;
    try {
      if (rawType === 'singlePageWithMultiPart' || rawType === 'multiPartPage') {
        // Upstream calls load() with no argument for both part-based kinds.
        const value = await JsEngine.callJson(
          `${this.expr(`explore[${index}].load`)}()`, this.scriptPath);
        return new Res<Comic[]>(JsComicSource.flattenParts(value, this.key));
      }
      if (rawType === 'mixed') {
        // mixed: load(sectionIndex) returns comics and/or {title, comics} parts.
        const value = await JsEngine.callJson(
          `${this.expr(`explore[${index}].load`)}(0)`, this.scriptPath);
        return new Res<Comic[]>(JsComicSource.flattenMixed(value, this.key));
      }
      const value = await JsEngine.callJson(
        `${this.expr(`explore[${index}].load`)}(${JsComicSource.argNumber(page)})`,
        this.scriptPath);
      return JsComicSource.toComicListResult(value, this.key);
    } catch (error) {
      return Res.fail<Comic[]>(JsComicSource.messageOf(error));
    }
  }

  /**
   * Unwrap the list out of a source result.
   * Sources return a bare array, or an object carrying it under `data`
   * (nhentai's explore returns `{data: [{title, comics}]}`).
   */
  private static asList(value: Object | null): Object[] | undefined {
    if (value === null || value === undefined) {
      return undefined;
    }
    if (Array.isArray(value)) {
      return value as Object[];
    }
    if (typeof value === 'object') {
      const record = value as Record<string, Object>;
      const data = record['data'];
      if (Array.isArray(data)) {
        return data as Object[];
      }
    }
    return undefined;
  }

  /**
   * Part-based explore results -> flat comic list.
   *
   * Upstream (`parser.dart`, `singlePageWithMultiPart`) iterates `res.keys` and
   * treats each entry as `ExplorePagePart(key, res[key] as List)`, so the
   * documented shape is `{sectionName: [comic, ...]}` - comick and copy_manga
   * both return exactly that. The array form `[{title, comics}]` (nhentai) and
   * a `{data: [...]}` wrapper are also accepted.
   */
  private static flattenParts(value: Object | null, sourceKey: string): Comic[] {
    const out: Comic[] = [];
    const list = JsComicSource.asList(value);
    if (list !== undefined) {
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        if (item === null || typeof item !== 'object') {
          continue;
        }
        const record = item as Record<string, Object>;
        const nested = record['comics'];
        if (nested !== undefined) {
          JsComicSource.appendAll(out, parseComicList(nested, sourceKey));
        } else if (Array.isArray(item)) {
          JsComicSource.appendAll(out, parseComicList(item, sourceKey));
        } else {
          out.push(parseComic(item, sourceKey));
        }
      }
    } else if (value !== null && value !== undefined && typeof value === 'object') {
      const record = value as Record<string, Object>;
      for (const name of Object.keys(record)) {
        const section = record[name];
        if (Array.isArray(section)) {
          JsComicSource.appendAll(out, parseComicList(section, sourceKey));
        }
      }
    }
    if (out.length === 0) {
      Log.warn('JsComicSource',
        `${sourceKey} explore parts yielded 0 items; raw response content omitted`);
    }
    return out;
  }

  private static appendAll(target: Comic[], items: Comic[]): void {
    for (let i = 0; i < items.length; i++) {
      target.push(items[i]);
    }
  }

  /**
   * `mixed` results interleave plain comics and `{title, comics}` sections,
   * possibly wrapped in a `data` field; all shapes are flattened here.
   */
  private static flattenMixed(value: Object | null, sourceKey: string): Comic[] {
    const out: Comic[] = [];
    const list = JsComicSource.asList(value);
    if (list !== undefined) {
      for (let i = 0; i < list.length; i++) {
        const item = list[i];
        if (item === null || typeof item !== 'object') {
          continue;
        }
        const record = item as Record<string, Object>;
        if (record['comics'] !== undefined) {
          const nested = parseComicList(record['comics'], sourceKey);
          for (let j = 0; j < nested.length; j++) {
            out.push(nested[j]);
          }
        } else {
          out.push(parseComic(item, sourceKey));
        }
      }
    } else if (value !== null && value !== undefined && typeof value === 'object') {
      out.push(...parseComicList((value as Record<string, Object>)['comics'], sourceKey));
    }
    if (out.length === 0) {
      Log.warn('JsComicSource',
        `${sourceKey} mixed explore yielded 0 items from: ${JsComicSource.preview(value)}`);
    }
    return out;
  }

  private async jsLoadInfo(id: string): Promise<Res<ComicDetails>> {
    try {
      const value = await JsEngine.callJson(
        `${this.expr('comic.loadInfo')}(${JsComicSource.arg(id)})`, this.scriptPath);
      if (value === null || value === undefined) {
        return Res.fail<ComicDetails>('Invalid data');
      }
      const details = ComicDetails.fromJson(value, this.key, id);
      if (details === undefined) {
        return Res.fail<ComicDetails>('Invalid data');
      }
      // Write through the raw source JSON: the parsed model has Maps that would
      // not survive JSON.stringify, so cache the original record instead.
      try { CacheManager.payloads().rememberDetail(this.key, id, value); }
      catch (error) { Log.warn('JsComicSource', '详情缓存写入失败，不影响本次加载'); }
      return new Res<ComicDetails>(details);
    } catch (error) {
      return Res.fail<ComicDetails>(JsComicSource.messageOf(error));
    }
  }

  /** Cached details for instant paint; undefined on miss or unusable cache. */
  private async cachedInfo(id: string): Promise<ComicDetails | undefined> {
    try {
      const raw = CacheManager.payloads().detailPayload(this.key, id);
      if (raw === undefined) { return undefined; }
      return ComicDetails.fromJson(raw, this.key, id);
    } catch (error) {
      Log.warn('JsComicSource', '详情缓存读取失败，回退到网络加载');
      return undefined;
    }
  }

  private async jsLoadEp(id: string, ep?: string): Promise<Res<string[]>> {
    try {
      const value = await JsEngine.callJson(
        `${this.expr('comic.loadEp')}(${JsComicSource.arg(id)}, ${JsComicSource.arg(ep)})`,
        this.scriptPath);
      if (value === null || value === undefined) {
        return Res.fail<string[]>('该章节没有图片');
      }
      if (Array.isArray(value)) {
        return new Res<string[]>(parseStringList(value));
      }
      const record = value as Record<string, Object>;
      const images = parseStringList(record['images']);
      if (images.length === 0) {
        return Res.fail<string[]>('该章节没有图片');
      }
      // Cached for reference only; downloads keep trusting the live list so a
      // stale entry can never make a checkpoint look invalid.
      try { CacheManager.payloads().rememberPageList(this.key, id, ep ?? '', images); }
      catch (error) { Log.warn('JsComicSource', '正文列表缓存写入失败，不影响本次加载'); }
      return new Res<string[]>(images);
    } catch (error) {
      return Res.fail<string[]>(JsComicSource.messageOf(error));
    }
  }

  private async jsImageConfig(url: string, comicId: string, epId: string, hook: string = 'onImageLoad', requestTrace?: string):
    Promise<ImageRequestConfig> {
    const trace = requestTrace ?? `image-config-${Date.now()}-${this.key}`;
    Log.audit(trace, '源图片钩子到达', `源=${this.key}；钩子=${hook}；参数内容不落盘`);
    try {
      const args = hook === 'onThumbnailLoad' ? JsComicSource.arg(url) :
        `${JsComicSource.arg(url)}, ${JsComicSource.arg(comicId)}, ${JsComicSource.arg(epId)}`;
      const value = await JsEngine.callJson(`${this.expr(`comic.${hook}`)}(${args})`, this.scriptPath, trace);
      return ImageConfigParser.parse(value, url, trace);
    } catch (error) {
      Log.audit(trace, '源图片钩子异常', `钩子=${hook}；不会发送未配置的裸请求`);
      throw new Error(JsComicSource.messageOf(error));
    }
  }

  private static messageOf(error: Object): string {
    return error instanceof Error ? error.message : String(error);
  }
}

/**
 * Turns a source script into a live ComicSource.
 *
 * Dart original: lib/features/comic_source/parser.dart `ComicSourceParser`.
 * Sequence preserved: normalise newlines -> find the entry class -> instantiate
 * -> read metadata -> validate key -> register into the JS-side registry
 * `ComicSource.sources[key]`.
 */
export class ComicSourceParser {
  private static readonly CLASS_PATTERN: string =
    '^\\s*class\\s+([a-zA-Z_$][a-zA-Z0-9_$]*)\\s+extends\\s+ComicSource\\b';
  private static readonly KEY_PATTERN: string = '^[a-zA-Z_][a-zA-Z0-9_]*$';

  static sourceClassName(script: string): string {
    const match = new RegExp(ComicSourceParser.CLASS_PATTERN, 'm')
      .exec(script.replace('\uFEFF', ''));
    if (match === null) {
      throw new Error('脚本缺少 extends ComicSource 的入口类');
    }
    return match[1];
  }

  private static readonly SUMMARY_SCRIPT: string =
    '(() => {\n' +
    '  const s = this[\'temp\'];\n' +
    '  const has = {\n' +
    '    search: !!(s.search && s.search.load),\n' +
    '    searchNext: !!(s.search && s.search.loadNext),\n' +
    '    explore: !!(s.explore && s.explore.length),\n' +
    '    loadInfo: !!(s.comic && s.comic.loadInfo),\n' +
    '    loadEp: !!(s.comic && s.comic.loadEp),\n' +
    '    onImageLoad: !!(s.comic && s.comic.onImageLoad),\n' +
    '    onThumbnailLoad: !!(s.comic && s.comic.onThumbnailLoad),\n' +
    '    onClickTag: !!(s.comic && typeof s.comic.onClickTag === "function"),\n' +
    '    categoryLanding: !!s.category,\n' +
    '    categoryLoad: !!(s.categoryComics && typeof s.categoryComics.load === "function"),\n' +
    '    ranking: !!(s.categoryComics && s.categoryComics.ranking),\n' +
    '    rankingLoad: !!(s.categoryComics && s.categoryComics.ranking && typeof s.categoryComics.ranking.load === "function"),\n' +
    '    rankingNext: !!(s.categoryComics && s.categoryComics.ranking && typeof s.categoryComics.ranking.loadWithNext === "function"),\n' +
    '    favorites: !!s.favorites,\n' +
    '    account: !!s.account,\n' +
    '    passwordLogin: !!(s.account && typeof s.account.login === "function"),\n' +
    '    settings: !!s.settings,\n' +
    '    init: !!s.init,\n' +
    '    category: !!s.categoryComics\n' +
    '  };\n' +
    '  const exploreTitles = [];\n' +
    '  const exploreTypes = [];\n' +
    '  const exploreCursorFlags = [];\n' +
    '  if (s.explore) { for (const e of s.explore) { exploreTitles.push(e.title || \'\'); exploreTypes.push(e.type === undefined ? null : e.type); exploreCursorFlags.push(typeof e.load!=="function"&&typeof e.loadNext==="function"); } }\n' +    '  const settingsDefaults = {};\n' +
    '  if (s.settings) {\n' +
    '    for (const name of Object.keys(s.settings)) {\n' +
    '      const item = s.settings[name];\n' +
    '      if (item && item.default !== undefined) { settingsDefaults[name] = item.default; }\n' +
    '    }\n' +
    '  }\n' +
    '  return JSON.stringify({\n' +
    '    name: s.name, key: s.key, version: s.version,\n' +
    '    minAppVersion: s.minAppVersion, url: s.url,\n' +
    '    has: has, exploreTitles: exploreTitles, exploreTypes: exploreTypes, exploreCursorFlags: exploreCursorFlags, settingsDefaults: settingsDefaults,\n' +
    '    accountMeta:s.account?{webUrl:s.account.loginWithWebview?.url,registerUrl:s.account.registerWebsite,' +
    'hasWebCheck:typeof s.account.loginWithWebview?.checkStatus==="function",' +
    'cookieFields:s.account.loginWithCookies?.fields,hasCookieValidate:typeof s.account.loginWithCookies?.validate==="function"}:null\n' +
    '  });\n' +
    '})()';

  /**
   * Parse and register a source script.
   * The script must already be loaded into the sandbox; `filePath` is only used
   * as the script name in stack traces.
   */
  static async parse(script: string, filePath: string): Promise<JsComicSource> {
    if (!JsEngine.isAvailable) {
      throw new Error(`QuickJS 不可用: ${JsEngine.error}`);
    }
    const normalized = script.replace(new RegExp('\r\n', 'g'), '\n');
    const className = ComicSourceParser.sourceClassName(normalized);

    JsEngine.evaluate(
      `(() => {\n${normalized}\nthis['temp'] = new ${className}();\n}).call(this)`, filePath);

    let summaryJson: string;
    try {
      summaryJson = JsEngine.evaluate(ComicSourceParser.SUMMARY_SCRIPT, filePath);
    } catch (error) {
      JsEngine.evaluate("delete this['temp'];", filePath);
      throw new Error(error instanceof Error ? error.message : String(error));
    }

    const summary = JSON.parse(summaryJson) as Record<string, Object>;
    const key = toStringOrNull(summary['key']);
    const name = toStringOrNull(summary['name']);
    const version = toStringOrNull(summary['version']);
    if (key === undefined || key.length === 0) {
      JsEngine.evaluate("delete this['temp'];", filePath);
      throw new Error('源缺少 key');
    }
    if (!new RegExp(ComicSourceParser.KEY_PATTERN).test(key)) {
      JsEngine.evaluate("delete this['temp'];", filePath);
      throw new Error(`key ${key} 不合法`);
    }

    const minAppVersion = toStringOrNull(summary['minAppVersion']);
    if (minAppVersion !== undefined && minAppVersion.length > 0) {
      // compareSemVer(minAppVersion, appVersion) === true means min > current.
      if (compareSemVer(minAppVersion, APP_VERSION)) {
        JsEngine.evaluate("delete this['temp'];", filePath);
        throw new Error(`需要应用版本 ${minAppVersion}`);
      }
    }

    // Register into the JS-side registry the callbacks are evaluated against.
    JsEngine.evaluate(
      `void (ComicSource.sources[${JSON.stringify(key)}] = this['temp']);`, filePath);
    JsEngine.evaluate("delete this['temp'];", filePath);

    const source = new JsComicSource(key, name ?? key, version ?? '1.0.0', filePath);
    const has = summary['has'] as Record<string, Object>;
    const titles: string[] = [];
    const rawTitles = summary['exploreTitles'];
    if (Array.isArray(rawTitles)) {
      const list = rawTitles as Object[];
      for (let i = 0; i < list.length; i++) {
        titles.push(String(list[i]));
      }
    }
    const types: Object[] = [];
    const rawTypes = summary['exploreTypes'];
    if (Array.isArray(rawTypes)) {
      const list = rawTypes as Object[];
      for (let i = 0; i < list.length; i++) {
        // Kept verbatim: upstream switches on the declared string
        // ("mixed" / "multiPartPage" / "multiPageComicList" /
        // "singlePageWithMultiPart"). Collapsing it to a number here is what
        // sent every `mixed` source down the wrong explore branch.
        types.push(list[i]);
      }
    }
    const accountMeta = summary['accountMeta'];
    const cursors: boolean[] = [];
    const rawCursors = summary['exploreCursorFlags'];
    if (Array.isArray(rawCursors)) { for (const flag of rawCursors as Object[]) { cursors.push(flag === true); } }
    source.configure(has, titles, types, accountMeta !== null && typeof accountMeta === 'object'
      ? accountMeta as Record<string, Object> : undefined, cursors);

    // Declared setting defaults must be reachable from load_setting, exactly as
    // upstream did: user value -> declared default -> throw.
    const defaults = summary['settingsDefaults'];
    if (defaults !== undefined && defaults !== null && typeof defaults === 'object') {
      SourceDataStore.set(key, 'setting_defaults', defaults as Object);
    }

    Log.info('ComicSourceParser',
      `loaded ${key} v${version ?? '?'} (search=${has['search'] || has['searchNext']}, info=${has['loadInfo']}, ep=${has['loadEp']})`);
    if (has['init'] === true) {
      // Upstream parser.dart schedules init() shortly after registration and
      // data preload, without blocking the other sources while it awaits HTTP.
      setTimeout(() => {
        JsEngine.callJson(`ComicSource.sources[${JSON.stringify(key)}].init()`, filePath)
          .then(() => {
            Log.info('ComicSourceParser', `${key} init() completed`);
          })
          .catch((error: Object) => {
            Log.warn('ComicSourceParser', `${key} init() failed: ${error}`);
          });
      }, 50);
    }
    return source;
  }
}
