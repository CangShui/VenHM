/** Route parameter bags. Dart used typed page constructors instead. */

export interface ComicDetailsParams {
  sourceKey: string;
  comicId: string;
  title: string;
  cover: string;
}

export interface ReaderParams {
  sourceKey: string;
  comicId: string;
  title: string;
  /** Origin controls the reader's explicit back policy. */
  origin?: string;
  /** Re-read current history after loading chapters; used by details and HistoryNavigation.resume. */
  resume?: boolean;
  /** Explicit chapter id, including '' for an implicit single chapter. Never fall back from an invalid id. */
  epId?: string;
  /** 1-based legacy chapter ordinal (History.ep), used only when epId is undefined. */
  epIndex?: number;
  /** 1-based page to open at; explicit chapter taps pass 1. */
  page?: number;
  /** Cover fallback while the authoritative detail payload is loaded. */
  cover?: string;
}

export interface ReaderResult {
  epId: string;
  page: number;
}

export interface CategoryComicsParams {
  sourceKey: string;
  label: string;
  page: string;
  category?: string;
  param?: string;
  keyword?: string;
  /** Source-provided ordered option keys; never stringify/flatten target arrays. */
  options?: string[];
}

export interface RankingParams {
  sourceKey: string;
}

export interface NetworkFavoritesParams {
  sourceKey?: string;
}

export interface RepositoryParams {
  repositoryId: string;
  repositoryName: string;
  repositoryUrl: string;
}
