import { AppContext } from '../foundation/AppContext';
import { CacheStats, CacheStore, PayloadCache } from '../foundation/CacheStore';
import { Log } from '../foundation/Log';
import { Settings } from '../foundation/Settings';

/** One selectable total-cache cap shown on the cache settings page. */
export class CacheLimitOption {
  label: string = '';
  bytes: number = 0;

  constructor(label: string = '', bytes: number = 0) {
    this.label = label;
    this.bytes = bytes;
  }
}

/**
 * Persisted cache policy.
 *
 * Dart original: the settings half of venera's image cache (`imageCacheLimitMb`).
 * The port keeps a single total cap in bytes for the whole disk cache (covers,
 * reader pages, cached details and page lists) because they share one directory
 * and one LRU; a per-kind budget would let one kind starve the others.
 *
 * Stored through the existing `Settings` key-value helper (no new DB table), and
 * reads are defensive: before `Settings.init()` runs, or with a hand-edited
 * preference, the default 1 GiB applies instead of throwing.
 */
export class CacheSettings {
  /** Default cap: 1 GiB. */
  static readonly DEFAULT_LIMIT_BYTES: number = 1024 * 1024 * 1024;
  static readonly MIN_LIMIT_BYTES: number = 256 * 1024 * 1024;
  static readonly MAX_LIMIT_BYTES: number = 4 * 1024 * 1024 * 1024;
  /** Selectable caps in MiB; 1024 is the default. */
  static readonly OPTION_MB: number[] = [256, 512, 1024, 2048, 4096];
  private static readonly LIMIT_KEY: string = 'cacheMaxBytes';

  static options(): CacheLimitOption[] {
    const list: CacheLimitOption[] = [];
    for (let i = 0; i < CacheSettings.OPTION_MB.length; i++) {
      const megabytes = CacheSettings.OPTION_MB[i];
      list.push(new CacheLimitOption(CacheSettings.label(CacheSettings.bytesOf(megabytes)),
        CacheSettings.bytesOf(megabytes)));
    }
    return list;
  }

  /** True when the value is a usable cap (finite, inside the supported range). */
  static isValidLimit(bytes: number): boolean {
    return Number.isFinite(bytes) && bytes >= CacheSettings.MIN_LIMIT_BYTES &&
      bytes <= CacheSettings.MAX_LIMIT_BYTES;
  }

  /** Coerce a stored value: anything unusable becomes the 1 GiB default. */
  static normalizeLimit(bytes: number): number {
    return CacheSettings.isValidLimit(bytes) ? Math.trunc(bytes) : CacheSettings.DEFAULT_LIMIT_BYTES;
  }

  /** Current cap; never throws, even before Settings.init(). */
  static limitBytes(): number {
    try {
      return CacheSettings.normalizeLimit(
        Settings.getInt(CacheSettings.LIMIT_KEY, CacheSettings.DEFAULT_LIMIT_BYTES));
    } catch (error) {
      // Previewer/first frame: image loading must not depend on preferences.
      return CacheSettings.DEFAULT_LIMIT_BYTES;
    }
  }

  /** Persist a new cap. Rejects values outside the supported range. */
  static async setLimitBytes(bytes: number): Promise<number> {
    if (!CacheSettings.isValidLimit(bytes)) {
      throw new Error(`缓存上限无效：${bytes}；允许范围 ${CacheSettings.label(CacheSettings.MIN_LIMIT_BYTES)}` +
        ` - ${CacheSettings.label(CacheSettings.MAX_LIMIT_BYTES)}`);
    }
    const accepted = Math.trunc(bytes);
    await Settings.setInt(CacheSettings.LIMIT_KEY, accepted);
    Log.info('CacheSettings', `缓存上限已保存：${accepted} 字节`);
    return accepted;
  }

  static bytesOf(megabytes: number): number {
    return megabytes * 1024 * 1024;
  }

  /** "256 MB" / "1 GB" / "1.5 GB" - shared by the page and the toasts. */
  static label(bytes: number): string {
    if (bytes >= CacheSettings.bytesOf(1024)) {
      return `${CacheSettings.trim(bytes / CacheSettings.bytesOf(1024))} GB`;
    }
    return `${CacheSettings.trim(bytes / CacheSettings.bytesOf(1))} MB`;
  }

  private static trim(value: number): string {
    const rounded = Math.round(value * 10) / 10;
    return Number.isInteger(rounded) ? `${Math.trunc(rounded)}` : `${rounded}`;
  }
}

/**
 * The single disk cache instance plus the operations the settings page needs.
 *
 * Only cache payloads are ever touched: downloads live under
 * `AppContext.filesDir/local_comics`, reading history in the RDB under
 * `AppContext.filesDir`, so clearing the cache cannot delete either of them.
 */
export class CacheManager {
  private static store: CacheStore | undefined = undefined;

  /** Shared cache: covers, reader pages, cached details and page lists. */
  static imageStore(): CacheStore {
    const existing = CacheManager.store;
    if (existing !== undefined) {
      return existing;
    }
    // `CacheStore.shared` keeps one instance per directory even if this method
    // runs before the page; applying the persisted cap here makes the limit
    // authoritative for whichever caller arrived first.
    const limit = CacheSettings.limitBytes();
    const created = CacheStore.shared(AppContext.imageCacheDir, CacheStore.DEFAULT_SUFFIX, limit);
    created.setMaxBytes(limit);
    CacheManager.store = created;
    return created;
  }

  static stats(): CacheStats {
    return CacheManager.imageStore().stats();
  }

  /** Payload helpers for comic details and chapter page lists. */
  static payloads(): PayloadCache {
    return new PayloadCache(CacheManager.imageStore());
  }

  /** Persist the cap, apply it to the live store and evict down to it. */
  static async setLimit(bytes: number): Promise<number> {
    const accepted = await CacheSettings.setLimitBytes(bytes);
    const store = CacheManager.imageStore();
    const evicted = store.setMaxBytes(accepted);
    Log.info('CacheManager', `缓存上限 ${accepted} 字节已生效；本次清理 ${evicted} 项`);
    return accepted;
  }

  /** Clear every cached payload (covers/details/pages) and reset accounting. */
  static clear(): CacheStats {
    const store = CacheManager.imageStore();
    const removed = store.clear();
    Log.info('CacheManager', `已清除 ${removed} 个缓存项；下载与阅读历史未改动`);
    return store.stats();
  }
}
