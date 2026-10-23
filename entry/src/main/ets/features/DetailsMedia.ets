import { Res } from '../model/Res';
import { DetailsCapabilities } from '../source/DetailsCapabilities';
import { SourceFailure } from './SourceFailure';

/** Source/comic-locked thumbnail cursor state; does not enumerate full chapter URLs. */
export class DetailsMedia {
  images: string[] = [];
  loading: boolean = false;
  ended: boolean = true;
  error: string = '';
  private version: number = 0;
  private next: string | null = null;
  private cursors: string[] = [];
  private loader?: (id: string, next: string | null) => Promise<Res<string[]>>;
  private comicId: string = '';

  start(id: string, initial: string[], capability?: DetailsCapabilities): void {
    this.invalidate(); this.comicId = id; this.images = initial.slice();
    this.next = null; this.cursors = []; this.error = '';
    this.loader = capability?.loadComicThumbnail; this.ended = this.loader === undefined;
  }

  invalidate(): void { this.version++; this.loading = false; }

  async more(): Promise<void> {
    const loader = this.loader;
    if (this.loading || this.ended || loader === undefined) { return; }
    const version = ++this.version; const cursor = this.next;
    this.loading = true; this.error = '';
    try {
      const result = await loader(this.comicId, cursor);
      if (version !== this.version) { return; }
      if (result.error || result.dataOrNull === undefined) { throw new Error(result.errorMessage ?? 'Invalid thumbnails'); }
      // Preserve positions: duplicate thumbnails can intentionally represent different pages.
      const incoming = result.data;
      this.images = this.images.concat(incoming);
      const next = typeof result.subData === 'string' ? result.subData as string : null;
      this.ended = incoming.length === 0 || next === null || next.length === 0 || this.cursors.includes(next);
      if (cursor !== null) { this.cursors.push(cursor); }
      if (next === cursor) { this.ended = true; }
      this.next = next;
    } catch (error) { if (version === this.version) { this.error = SourceFailure.message(error); } }
    finally { if (version === this.version) { this.loading = false; } }
  }
}

/** Share only title and explicitly safe public origin URL; never source/account state. */
export class DetailsSharePayload {
  title: string = '';
  url: string = '';
  text: string = '';
  /**
   * Upstream `share()` shares the comic's own site URL when the source provides
   * one, and only the title otherwise. Many sources do not return `url`, so we
   * fall back to the comic id when it is already an absolute link, then to the
   * source's own site origin. The address is always the ORIGINAL site, never an
   * app-internal route.
   */
  static create(title: string, origin?: string, comicId?: string, siteDomain?: string): DetailsSharePayload {
    const payload = new DetailsSharePayload();
    payload.title = title.replace(/[\u0000-\u001f\u007f]/g, ' ').trim().slice(0, 300);
    const candidates: string[] = [];
    if (origin !== undefined) { candidates.push(origin.trim()); }
    if (comicId !== undefined) { candidates.push(comicId.trim()); }
    for (const value of candidates) {
      if (DetailsSharePayload.safeLink(value)) { payload.url = value; break; }
    }
    if (payload.url.length === 0 && siteDomain !== undefined) {
      const host = siteDomain.trim().replace(/^https?:\/\//i, '').replace(/\/.*$/, '');
      if (/^[^\s\/@?#\\]+(?::\d+)?$/i.test(host)) { payload.url = `https://${host}`; }
    }
    payload.text = payload.url.length > 0 ? `${payload.title}\n${payload.url}` : payload.title;
    return payload;
  }

  /** Fail closed on userinfo, backslashes, credentials/query/fragment. */
  private static safeLink(value: string): boolean {
    if (!/^https?:\/\/[^\s\/@?#\\]+(?::\d+)?(?:\/[^\s?#\\]*)?$/i.test(value)) { return false; }
    if (/[\u0000-\u0020\u007f]/.test(value)) { return false; }
    if (/%(?:00|0a|0d|40)/i.test(value)) { return false; }
    return true;
  }
}

/** Upstream EH sprites append @x=start-end&y=start-end, in source pixels. */
export class DetailsImageRegion {
  url: string = '';
  x: number = 0;
  y: number = 0;
  width: number = 0;
  height: number = 0;
  cropped: boolean = false;
  static parse(value: string): DetailsImageRegion {
    const region = new DetailsImageRegion(); region.url = value;
    const match = value.match(/@x=(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?)(?:&y=(\d+(?:\.\d+)?)-(\d+(?:\.\d+)?))?$/);
    if (match === null) { return region; }
    const x = Number(match[1]); const width = Number(match[2]) - x;
    const y = match[3] === undefined ? 0 : Number(match[3]);
    const height = match[4] === undefined ? 0 : Number(match[4]) - y;
    if (width <= 0 || height < 0) { return region; }
    region.url = value.slice(0, value.length - match[0].length);
    region.x = x; region.y = y; region.width = width; region.height = height; region.cropped = true;
    return region;
  }
}

/** Viewer math independent from image loading; zoom never triggers another HTTP request. */
export class DetailsViewerTransform {
  static scale(value: number): number { return Number.isFinite(value) ? Math.max(1, Math.min(4, value)) : 1; }
  static offset(value: number, extent: number, scale: number): number {
    const limit = Math.max(0, extent * (scale - 1) / 2);
    return Math.max(-limit, Math.min(limit, value));
  }
}
