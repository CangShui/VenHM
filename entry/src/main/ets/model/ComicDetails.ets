import { Comic, ComicChapters, Comment, parseComicList, parseCommentList, parseStringList } from './Comic';
import { ComicType } from './ComicType';
import { toBoolOrNull, toDoubleOrNull, toIntOrNull, toStringOrNull } from '../foundation/Extensions';

/**
 * ComicDetails - the comic detail payload returned by a source's loadInfo.
 *
 * Dart original: lib/features/comic_source/models.dart `class ComicDetails`.
 * Differences worth noting:
 *  - `tags` is a namespace -> values map (list pages use a flat string list).
 *  - `subtitle` is spelled `subTitle` in Dart; kept here for JSON compatibility.
 *  - `findUpdateTime()` validates the date so follow-update does not act on junk.
 */
export class ComicDetails {
  title: string = '';
  subTitle?: string;
  cover: string = '';
  description?: string;
  tags: Map<string, string[]> = new Map<string, string[]>();
  chapters?: ComicChapters;
  thumbnails?: string[];
  recommend?: Comic[];
  sourceKey: string = '';
  comicId: string = '';
  isFavorite?: boolean;
  subId?: string;
  isLiked?: boolean;
  likesCount?: number;
  commentCount?: number;
  uploader?: string;
  uploadTime?: string;
  updateTime?: string;
  url?: string;
  /** 0-5 */
  stars?: number;
  maxPage?: number;
  comments?: Comment[];

  get id(): string {
    return this.comicId;
  }

  get comicType(): ComicType {
    return ComicType.fromKey(this.sourceKey);
  }

  /** Flatten tags to `namespace:value` strings (Dart: plainTags). */
  get plainTags(): string[] {
    const out: string[] = [];
    for (const key of this.tags.keys()) {
      const values = this.tags.get(key) as string[];
      for (let i = 0; i < values.length; i++) {
        out.push(`${key}:${values[i]}`);
      }
    }
    return out;
  }

  /** First value of an author-like namespace. Dart: findAuthor(). */
  findAuthor(): string | undefined {
    const namespaces: string[] = ['author', 'authors', 'artist', 'artists', '作者', '画师'];
    for (const key of this.tags.keys()) {
      if (namespaces.indexOf(key.toLowerCase()) >= 0) {
        const values = this.tags.get(key) as string[];
        if (values.length > 0) {
          return values[0];
        }
      }
    }
    return undefined;
  }

  /** Validated YYYY-M-D date from updateTime or an update-like tag. */
  findUpdateTime(): string | undefined {
    const direct = this.updateTime;
    if (direct !== undefined && direct.length > 0) {
      return ComicDetails.validateUpdateTime(direct);
    }
    const accepted: string[] = ['更新', '最後更新', '最后更新', 'update', 'last update'];
    for (const key of this.tags.keys()) {
      if (accepted.indexOf(key.toLowerCase()) >= 0) {
        const values = this.tags.get(key) as string[];
        if (values.length > 0) {
          return ComicDetails.validateUpdateTime(values[0]);
        }
      }
    }
    return undefined;
  }

  private static validateUpdateTime(time: string): string | undefined {
    const datePart: string = time.split(' ')[0];
    const segments: string[] = datePart.split('-');
    if (segments.length !== 3) {
      return undefined;
    }
    const year = parseInt(segments[0], 10);
    const month = parseInt(segments[1], 10);
    const day = parseInt(segments[2], 10);
    if (isNaN(year) || isNaN(month) || isNaN(day)) {
      return undefined;
    }
    if (year < 2000 || year > 3000) {
      return undefined;
    }
    if (month < 1 || month > 12) {
      return undefined;
    }
    if (day < 1 || day > 31) {
      return undefined;
    }
    return `${year}-${month}-${day}`;
  }

  /**
   * Parse a source's loadInfo result.
   * Dart rejects the payload when `tags` is not a map, so a missing tags field
   * yields undefined here too - callers must treat it as "Invalid data".
   */
  static fromJson(value: Object, sourceKey: string, comicId: string): ComicDetails | undefined {
    if (value === null || typeof value !== 'object') {
      return undefined;
    }
    const record = value as Record<string, Object>;
    const details = new ComicDetails();
    details.sourceKey = sourceKey;
    details.comicId = comicId;
    details.title = toStringOrNull(record['title']) ?? '';
    details.subTitle = toStringOrNull(record['subtitle']) ?? toStringOrNull(record['subTitle']);
    details.cover = toStringOrNull(record['cover']) ?? '';
    details.description = toStringOrNull(record['description']);
    details.tags = ComicDetails.parseTags(record['tags']);
    details.chapters = ComicChapters.fromJson(record['chapters']);
    const thumbnails = record['thumbnails'];
    if (thumbnails !== undefined && thumbnails !== null) {
      details.thumbnails = parseStringList(thumbnails);
    }
    const recommend = record['recommend'];
    if (recommend !== undefined && recommend !== null) {
      details.recommend = parseComicList(recommend, sourceKey);
    }
    const comments = record['comments'];
    if (comments !== undefined && comments !== null) {
      details.comments = parseCommentList(comments);
    }
    details.isFavorite = toBoolOrNull(record['isFavorite']);
    details.subId = toStringOrNull(record['subId']);
    details.isLiked = toBoolOrNull(record['isLiked']);
    details.likesCount = toIntOrNull(record['likesCount']);
    details.commentCount = toIntOrNull(record['commentCount']);
    details.uploader = toStringOrNull(record['uploader']);
    details.uploadTime = toStringOrNull(record['uploadTime']);
    details.updateTime = toStringOrNull(record['updateTime']);
    details.url = toStringOrNull(record['url']);
    details.stars = toDoubleOrNull(record['stars']);
    details.maxPage = toIntOrNull(record['maxPage']);
    return details;
  }

  private static parseTags(value: Object | undefined): Map<string, string[]> {
    const tags = new Map<string, string[]>();
    if (value === undefined || value === null || typeof value !== 'object') {
      return tags;
    }
    const record = value as Record<string, Object>;
    for (const key of Object.keys(record)) {
      const entry = record[key];
      if (Array.isArray(entry)) {
        tags.set(key, parseStringList(entry));
      }
    }
    return tags;
  }
}
