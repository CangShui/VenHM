import { Comic, Comment } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { Res } from '../model/Res';
import { BrowserLoginSnapshot } from '../model/BrowserLogin';
import { RankingData } from './RankingData';
import { DetailsCapabilities } from './DetailsCapabilities';

/**
 * Comic source capability types.
 *
 * Dart original: lib/features/comic_source/types.dart + source.dart.
 * Dart exposes ~34 positional constructor parameters; ArkTS assigns the
 * capability fields directly on the subclass instead, which keeps a source
 * implementation readable and avoids a 34-argument constructor.
 */

export type LoadComicInfoFunc = (id: string) => Promise<Res<ComicDetails>>;

export type LoadComicPagesFunc = (id: string, ep?: string) => Promise<Res<string[]>>;

export type SearchPageFunc = (keyword: string, page: number, options: string[]) => Promise<Res<Comic[]>>;

export type SearchNextFunc = (keyword: string, next: string, options: string[]) => Promise<Res<Comic[]>>;

export type ExploreLoadFunc = (page: number) => Promise<Res<Comic[]>>;

export type ExploreNextFunc = (next: string) => Promise<Res<Comic[]>>;

export type CommentsLoader = (id: string, subId: string | undefined, page: number,
                              replyTo: string | undefined) => Promise<Res<Comment[]>>;

export type ChapterCommentsLoader = (comicId: string, epId: string, page: number,
                                     replyTo: string | undefined) => Promise<Res<Comment[]>>;

export type ImageHeadersFunc = (imageUrl: string, comicId: string, epId: string)
  => Promise<Map<string, string>>;

/** Per-image request override returned by a source's onImageLoad hook. */
export class ImageRequestConfig {
  url: string = '';
  headers: Map<string, string> = new Map<string, string>();
  modifyImage: string = '';
  method: string = 'GET';
  data?: Object;
  onResponse?: Object;
  onLoadFailed?: Object;
  /** Must not silently render scrambled images or discard required POST data. */
  unsupported: string[] = [];
}

export enum ExplorePageType {
  multiPageComicList = 0,
  singlePageWithMultiPart = 1,
  mixed = 2,
  override = 3
}

export class ExplorePagePart {
  title: string = '';
  comics: Comic[] = [];
}

export class ExplorePageData {
  cursorOnly: boolean = false;
  title: string = '';
  type: ExplorePageType = ExplorePageType.multiPageComicList;
  loadPage?: ExploreLoadFunc;
  loadNext?: ExploreNextFunc;
}

export class SearchOptions {
  label: string = '';
  type: string = 'select';
  options: Map<string, string> = new Map<string, string>();
  /** JSON serialization of the declared source default, matching upstream parser. */
  defaultVal?: string;
}

export class SearchPageData {
  /** loadPage may be a first-request adapter around a loadNext-only script. */
  cursorOnly: boolean = false;
  searchOptions?: SearchOptions[];
  optionsLoader?: () => Promise<Res<SearchOptions[]>>;
  loadPage?: SearchPageFunc;
  loadNext?: SearchNextFunc;
}

export class CategoryComicsOptions {
  label: string = '';
  options: Map<string, string> = new Map<string, string>();
  showWhen?: string[];
  notShowWhen: string[] = [];
}

/** One tappable category entry. Dart: category.dart `CategoryItem`. */
export class CategoryItem {
  label: string = '';
  /** Target page key, e.g. "search" / "category" (Dart: PageJumpTarget.page). */
  page: string = 'category';
  attributes: Map<string, string> = new Map<string, string>();
  initialOptions: string[] = [];
}

/** A titled group of category entries. Dart: `FixedCategoryPart` etc. */
export class CategoryPart {
  title: string = '';
  items: CategoryItem[] = [];
}

/** Category landing data. Dart: category.dart `CategoryData`. */
export class CategoryData {
  title: string = '';
  parts: CategoryPart[] = [];
  enableRankingPage: boolean = false;
}

export type CategoryComicsLoader = (category: string, param: string | undefined,
                                       options: string[], page: number)
  => Promise<Res<Comic[]>>;

export class CategoryComicsData {
  rankingData?: RankingData;
  options?: CategoryComicsOptions[];
  optionsLoader?: (category: string, param?: string) => Promise<Res<CategoryComicsOptions[]>>;
  load?: CategoryComicsLoader;
}

export type AddOrDelFavFunc = (comicId: string, folderId: string, isAdding: boolean,
                               favId: string | undefined) => Promise<Res<boolean>>;

export class FavoriteData {
  key: string = '';
  title: string = '';
  multiFolder: boolean = false;
  loadComic?: (page: number, folder?: string) => Promise<Res<Comic[]>>;
  loadNext?: (next: string | null, folder?: string) => Promise<Res<Comic[]>>;
  loadFolders?: (comicId?: string) => Promise<Res<Map<string, string>>>;
  addOrDelFavorite?: AddOrDelFavFunc;
}

export type LoginFunc = (account: string, password: string, trace?: string) => Promise<Res<boolean>>;

export class AccountConfig {
  login?: LoginFunc;
  logout?: () => Promise<void>;
  loginWebsite?: string;
  registerWebsite?: string;
  cookieFields?: string[];
  validateCookies?: (values: string[], trace?: string) => Promise<Res<boolean>>;
  checkLoginStatus?: (url: string, title: string, trace?: string) => Promise<boolean>;
  finishWebLogin?: (snapshot: BrowserLoginSnapshot, stillCurrent: () => boolean, trace?: string) => Promise<Res<boolean>>;
  canRelogin?: () => boolean;
  relogin?: (trace?: string) => Promise<Res<boolean>>;
  /** True when the source can be logged into from the UI. */
  get canLogin(): boolean {
    return this.login !== undefined || this.validateCookies !== undefined ||
      (this.loginWebsite !== undefined && this.checkLoginStatus !== undefined && this.finishWebLogin !== undefined);
  }
}

export class LinkHandler {
  domains: string[] = [];
  linkToId?: (url: string) => string | undefined;
}

export class ArchiveDownloader {
  getArchives?: (comicId: string) => Promise<Res<string[]>>;
  getDownloadUrl?: (comicId: string, archiveId: string) => Promise<Res<string>>;
}

/**
 * Base class of every comic source.
 *
 * A source declares its identity (key/name/version) and the capabilities it
 * supports; unsupported capabilities stay undefined so the UI can hide them -
 * the same contract VeneraNext enforces ("do not ship empty stubs").
 */
export class ComicSource {
  readonly key: string;
  readonly name: string;
  version: string = '1.0.0';
  /** Original script/API URL for update checks; may be empty for built-ins. */
  url: string = '';
  description: string = '';

  // --- access capabilities ---
  search?: SearchPageData;
  explorePages: ExplorePageData[] = [];
  categoryComics?: CategoryComicsData;
  /** Category landing data, loaded lazily from the script. */
  categoryData?: CategoryData;
  loadCategoryData?: () => Promise<CategoryData | undefined>;
  /**
   * Cached details for instant paint. Returns undefined when nothing is cached;
   * the page then falls back to loadComicInfo and refreshes in the background.
   */
  loadCachedComicInfo?: (id: string) => Promise<ComicDetails | undefined>;
  /** Original comic.onClickTag target, always evaluated in this source. */
  tagTarget?: (namespace: string, tag: string) => Promise<CategoryItem | undefined>;

  // --- comic capabilities ---
  loadComicInfo?: LoadComicInfoFunc;
  detailsMedia?: DetailsCapabilities;
  loadComicPages?: LoadComicPagesFunc;
  loadComicComments?: CommentsLoader;
  loadChapterComments?: ChapterCommentsLoader;
  getImageHeaders?: ImageHeadersFunc;
  getThumbnailConfig?: (imageUrl: string, trace?: string) => Promise<ImageRequestConfig>;
  /** Source-provided image request override (headers / rewritten url). */
  getImageConfig?: (imageUrl: string, comicId: string, epId: string, trace?: string)
    => Promise<ImageRequestConfig>;

  // --- account / favorites ---
  account?: AccountConfig;
  favoriteData?: FavoriteData;

  // --- link handling ---
  linkHandler?: LinkHandler;
  archiveDownloader?: ArchiveDownloader;

  /** Per-source persistent data (settings/account/tokens). */
  private dataStore: Map<string, string> = new Map<string, string>();

  constructor(key: string, name: string) {
    this.key = key;
    this.name = name;
  }

  get isLogged(): boolean {
    return this.dataStore.has('account');
  }

  get supportsSearch(): boolean {
    return this.search !== undefined && this.search.loadPage !== undefined;
  }

  get supportsExplore(): boolean {
    return this.explorePages.length > 0;
  }

  get supportsFavorites(): boolean {
    return this.favoriteData !== undefined;
  }

  get supportsCategory(): boolean {
    return this.categoryData !== undefined || this.loadCategoryData !== undefined ||
      (this.categoryComics !== undefined && this.categoryComics.load !== undefined);
  }

  getData(key: string): string | undefined {
    return this.dataStore.get(key);
  }

  setData(key: string, value: string): void {
    this.dataStore.set(key, value);
  }

  removeData(key: string): void {
    this.dataStore.delete(key);
  }

  loadDataFrom(map: Map<string, string>): void {
    this.dataStore = map;
  }

  exportData(): Map<string, string> {
    return this.dataStore;
  }

  toString(): string {
    return `ComicSource(${this.key})`;
  }
}
