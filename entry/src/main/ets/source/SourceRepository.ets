import { HttpClient, HttpResponse } from '../network/HttpClient';
import { Settings } from '../foundation/Settings';
import { Log } from '../foundation/Log';
import { firstWhereOrNull } from '../foundation/Extensions';

/**
 * Comic source repositories (catalogs).
 *
 * Dart original: lib/features/comic_source/source_repositories.dart.
 * A repository is a URL returning a JSON array of entries:
 *   { name, key, version, fileName | url, description? }
 * Relative `fileName` values resolve against the URL that actually served the
 * catalog (after redirects), which is what VeneraNext does as well.
 */

export class SourceCatalogEntry {
  key: string = '';
  name: string = '';
  version: string = '';
  /** Absolute download URL of the .js script. */
  url: string = '';
  description: string = '';

  toString(): string {
    return `${this.key}@${this.version}`;
  }
}

export class SourceCatalog {
  entries: SourceCatalogEntry[] = [];
  /** Labels of entries rejected by validation, for user feedback. */
  skipped: string[] = [];
}

export class SourceRepository {
  id: string = '';
  name: string = '';
  url: string = '';

  toJson(): Record<string, string> {
    const record: Record<string, string> = {};
    record.id = this.id;
    record.name = this.name;
    record.url = this.url;
    return record;
  }
}

const KEY_PATTERN = new RegExp('^\\w+$');
const VERSION_PATTERN = new RegExp('^\\d+\\.\\d+\\.\\d+([.\\-].+)?$');

/** Resolve a catalog-relative path against the catalog URL. */
export function resolveCatalogUrl(base: string, target: string): string {
  const trimmed = target.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  if (trimmed.startsWith('/')) {
    const schemeEnd = base.indexOf('://');
    if (schemeEnd < 0) {
      return trimmed;
    }
    const hostEnd = base.indexOf('/', schemeEnd + 3);
    const origin = hostEnd < 0 ? base : base.substring(0, hostEnd);
    return origin + trimmed;
  }
  const lastSlash = base.lastIndexOf('/');
  if (lastSlash < 0) {
    return trimmed;
  }
  return base.substring(0, lastSlash + 1) + trimmed;
}

export class SourceRepositories {
  /** Repositories the user added, persisted as a JSON array in preferences. */
  static all(): SourceRepository[] {
    const raw = Settings.getString('comicSourceRepositories', '');
    if (raw.length === 0) {
      return [];
    }
    const out: SourceRepository[] = [];
    try {
      const parsed = JSON.parse(raw) as Object;
      if (!Array.isArray(parsed)) {
        return [];
      }
      const list = parsed as Object[];
      for (let i = 0; i < list.length; i++) {
        const record = list[i] as Record<string, Object>;
        const url = record.url;
        if (typeof url !== 'string' || (url as string).length === 0) {
          continue;
        }
        const repo = new SourceRepository();
        repo.id = typeof record.id === 'string' ? record.id as string : `repo_${i}`;
        repo.name = typeof record.name === 'string' ? record.name as string : `仓库 ${i + 1}`;
        repo.url = url as string;
        out.push(repo);
      }
    } catch (error) {
      Log.warn('SourceRepositories', `cannot parse stored repositories: ${error}`);
    }
    return out;
  }

  static async save(repositories: SourceRepository[]): Promise<void> {
    const records: Record<string, string>[] = [];
    for (let i = 0; i < repositories.length; i++) {
      records.push(repositories[i].toJson());
    }
    await Settings.setString('comicSourceRepositories', JSON.stringify(records));
  }

  static async add(name: string, url: string): Promise<SourceRepository> {
    const repositories = SourceRepositories.all();
    const existing = firstWhereOrNull(repositories, (r: SourceRepository) => r.url === url);
    if (existing !== undefined) {
      return existing;
    }
    const repo = new SourceRepository();
    repo.id = `repo_${Date.now()}`;
    repo.name = name.trim().length > 0 ? name.trim() : SourceRepositories.hostOf(url);
    repo.url = url.trim();
    repositories.push(repo);
    await SourceRepositories.save(repositories);
    return repo;
  }

  static async remove(id: string): Promise<void> {
    const remaining = SourceRepositories.all().filter((r: SourceRepository) => r.id !== id);
    await SourceRepositories.save(remaining);
  }

  static hostOf(url: string): string {
    const schemeEnd = url.indexOf('://');
    if (schemeEnd < 0) {
      return url;
    }
    const start = schemeEnd + 3;
    const end = url.indexOf('/', start);
    return end < 0 ? url.substring(start) : url.substring(start, end);
  }

  static normalizeUrl(value: string): string {
    const trimmed = value.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      throw new Error('请输入完整的 http(s) 仓库地址');
    }
    return trimmed;
  }

  /** Fetch and validate a catalog. Invalid entries are skipped, not fatal. */
  static async load(url: string): Promise<SourceCatalog> {
    const normalized = SourceRepositories.normalizeUrl(url);
    const response: HttpResponse = await HttpClient.getText(normalized);
    if (!response.ok) {
      throw new Error(`仓库返回 HTTP ${response.status}`);
    }
    return SourceRepositories.parseCatalog(response.body, normalized);
  }

  static parseCatalog(contents: string, baseUrl: string): SourceCatalog {
    const catalog = new SourceCatalog();
    let parsed: Object;
    try {
      parsed = JSON.parse(contents) as Object;
    } catch (error) {
      throw new Error('仓库地址必须返回 JSON 格式的源列表');
    }
    if (!Array.isArray(parsed)) {
      throw new Error('仓库地址必须返回 JSON 数组');
    }
    const list = parsed as Object[];
    for (let i = 0; i < list.length; i++) {
      const record = list[i] as Record<string, Object>;
      const key = record.key;
      const label = typeof key === 'string' && (key as string).length > 0
        ? key as string
        : `#${i + 1}`;
      const name = record.name;
      const version = record.version;
      if (typeof key !== 'string' || !KEY_PATTERN.test(key as string) ||
        typeof name !== 'string' || typeof version !== 'string' ||
        !VERSION_PATTERN.test(version as string)) {
        catalog.skipped.push(label);
        continue;
      }
      const urlValue = record.url;
      const fileNameValue = record.fileName;
      let target: string | undefined = undefined;
      if (typeof urlValue === 'string' && (urlValue as string).trim().length > 0) {
        target = urlValue as string;
      } else if (typeof fileNameValue === 'string' && (fileNameValue as string).trim().length > 0) {
        target = fileNameValue as string;
      }
      if (target === undefined) {
        catalog.skipped.push(label);
        continue;
      }
      const entry = new SourceCatalogEntry();
      entry.key = key as string;
      entry.name = name as string;
      entry.version = version as string;
      entry.url = resolveCatalogUrl(baseUrl, target);
      const description = record.description;
      entry.description = typeof description === 'string' ? description as string : '';
      catalog.entries.push(entry);
    }
    if (catalog.entries.length === 0 && catalog.skipped.length > 0) {
      throw new Error('仓库中没有任何可用的源条目');
    }
    return catalog;
  }
}
