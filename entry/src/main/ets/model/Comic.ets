import { toStringOrNull, toDoubleOrNull, toIntOrNull, toBoolOrNull } from '../foundation/Extensions';

/**
 * Comic - the unit shown in lists, grids and history.
 *
 * Dart original: lib/features/comic_source/models.dart `class Comic`.
 * In Dart `Comic` is a concrete class that `FavoriteItem`, `History` and
 * `LocalComic` implement. ArkTS has no structural typing, so the shared shape is
 * declared as an interface and those classes implement it explicitly.
 */
export interface Comic {
  id: string;
  title: string;
  subtitle: string;
  cover: string;
  tags: string[];
  description: string;
  sourceKey: string;
  maxPage?: number;
  language?: string;
  favoriteId?: string;
  /** 0-5 */
  stars?: number;
}

/** Concrete Comic built from a source callback result. */
export class ComicItem implements Comic {
  id: string = '';
  title: string = '';
  subtitle: string = '';
  cover: string = '';
  tags: string[] = [];
  description: string = '';
  sourceKey: string = '';
  maxPage?: number;
  language?: string;
  favoriteId?: string;
  stars?: number;

  constructor(sourceKey: string) {
    this.sourceKey = sourceKey;
  }

  toString(): string {
    return `${this.sourceKey}@${this.id}`;
  }
}

/** Comic identifier independent of the source instance. */
export class ComicID {
  readonly type: string;
  readonly id: string;

  constructor(type: string, id: string) {
    this.type = type;
    this.id = id;
  }

  equals(other: ComicID): boolean {
    return this.type === other.type && this.id === other.id;
  }

  toString(): string {
    return `${this.type}@${this.id}`;
  }
}

/** A single comment. Dart: models.dart `class Comment`. */
export class Comment {
  userName: string = '';
  avatar?: string;
  content: string = '';
  time?: string;
  replyCount?: number;
  id?: string;
  score?: number;
  isLiked?: boolean;
  /** 1: upvote, -1: downvote, 0: none */
  voteStatus?: number;

  /**
   * Dart: Comment.parseTime - epoch seconds (< 1e10) are scaled to ms,
   * anything else is stringified and truncated to 19 chars.
   */
  static parseTime(value: Object | undefined): string | undefined {
    if (value === undefined || value === null) {
      return undefined;
    }
    if (typeof value === 'number') {
      const n = value as number;
      const ms: number = n < 10000000000 ? n * 1000 : n;
      const d = new Date(ms);
      return Comment.formatDate(d);
    }
    return String(value);
  }

  private static pad(n: number): string {
    return n < 10 ? `0${n}` : `${n}`;
  }

  static formatDate(d: Date): string {
    return `${d.getFullYear()}-${Comment.pad(d.getMonth() + 1)}-${Comment.pad(d.getDate())} ` +
      `${Comment.pad(d.getHours())}:${Comment.pad(d.getMinutes())}:${Comment.pad(d.getSeconds())}`;
  }
}

/** Archive descriptor for the "download archive" capability. */
export class ArchiveInfo {
  title: string = '';
  description: string = '';
  id: string = '';
}

/**
 * Chapter map - either a flat `{id: title}` map or a grouped
 * `{group: {id: title}}` map. Dart: models.dart `class ComicChapters`.
 */
export class ComicChapters {
  private readonly flat: Map<string, string> | undefined;
  private readonly grouped: Map<string, Map<string, string>> | undefined;

  private constructor(flat: Map<string, string> | undefined,
                      grouped: Map<string, Map<string, string>> | undefined) {
    this.flat = flat;
    this.grouped = grouped;
  }

  static flatOf(chapters: Map<string, string>): ComicChapters {
    return new ComicChapters(chapters, undefined);
  }

  static groupedOf(groups: Map<string, Map<string, string>>): ComicChapters {
    return new ComicChapters(undefined, groups);
  }

  static empty(): ComicChapters {
    return new ComicChapters(new Map<string, string>(), undefined);
  }

  get isGrouped(): boolean {
    return this.grouped !== undefined && (this.grouped as Map<string, Map<string, string>>).size > 0;
  }

  get groupNames(): string[] {
    const g = this.grouped;
    return g === undefined ? [] : Array.from(g.keys());
  }

  getGroup(name: string): Map<string, string> {
    const g = this.grouped;
    if (g === undefined) {
      return new Map<string, string>();
    }
    return g.get(name) ?? new Map<string, string>();
  }

  getGroupByIndex(index: number): Map<string, string> {
    const names = this.groupNames;
    if (index < 0 || index >= names.length) {
      return new Map<string, string>();
    }
    return this.getGroup(names[index]);
  }

  get groupCount(): number {
    return this.groupNames.length;
  }

  /** Flat chapter map; grouped maps are merged in group order. */
  get allChapters(): Map<string, string> {
    const flat = this.flat;
    if (flat !== undefined) {
      return flat;
    }
    const merged = new Map<string, string>();
    const g = this.grouped as Map<string, Map<string, string>>;
    for (const name of g.keys()) {
      const inner = g.get(name) as Map<string, string>;
      for (const id of inner.keys()) {
        merged.set(id, inner.get(id) as string);
      }
    }
    return merged;
  }

  get ids(): string[] {
    return Array.from(this.allChapters.keys());
  }

  get titles(): string[] {
    return Array.from(this.allChapters.values());
  }

  get length(): number {
    return this.allChapters.size;
  }

  titleOf(id: string): string | undefined {
    return this.allChapters.get(id);
  }

  indexOf(id: string): number {
    return this.ids.indexOf(id);
  }

  /**
   * Parse the JS `chapters` value. Dart returns flat when any flat entry exists,
   * otherwise grouped, otherwise an empty flat map.
   */
  static fromJson(value: Object | undefined): ComicChapters | undefined {
    if (value === undefined || value === null) {
      return undefined;
    }
    if (typeof value !== 'object') {
      return undefined;
    }
    const record = value as Record<string, Object>;
    const flat = new Map<string, string>();
    const grouped = new Map<string, Map<string, string>>();
    for (const key of Object.keys(record)) {
      const entry: Object = record[key];
      if (entry !== null && typeof entry === 'object' && !Array.isArray(entry)) {
        const innerRecord = entry as Record<string, Object>;
        const inner = new Map<string, string>();
        for (const innerKey of Object.keys(innerRecord)) {
          inner.set(innerKey, String(innerRecord[innerKey]));
        }
        grouped.set(key, inner);
      } else {
        flat.set(key, entry === null || entry === undefined ? '' : String(entry));
      }
    }
    if (flat.size > 0) {
      return ComicChapters.flatOf(flat);
    }
    if (grouped.size > 0) {
      return ComicChapters.groupedOf(grouped);
    }
    return ComicChapters.flatOf(flat);
  }
}

/** Parses one comic object returned by a source. */
export function parseComic(value: Object, sourceKey: string): ComicItem {
  const record = value as Record<string, Object>;
  const comic = new ComicItem(sourceKey);
  comic.id = toStringOrNull(record['id']) ?? '';
  comic.title = toStringOrNull(record['title']) ?? '';
  comic.subtitle = toStringOrNull(record['subtitle']) ?? toStringOrNull(record['subTitle']) ?? '';
  comic.cover = toStringOrNull(record['cover']) ?? '';
  comic.tags = parseStringList(record['tags']);
  comic.description = toStringOrNull(record['description']) ?? '';
  comic.maxPage = toIntOrNull(record['maxPage']);
  comic.language = toStringOrNull(record['language']);
  comic.favoriteId = toStringOrNull(record['favoriteId']);
  comic.stars = toDoubleOrNull(record['stars']);
  return comic;
}

export function parseComicList(value: Object | undefined, sourceKey: string): ComicItem[] {
  const out: ComicItem[] = [];
  if (value === undefined || value === null || !Array.isArray(value)) {
    return out;
  }
  const list = value as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && typeof item === 'object') {
      out.push(parseComic(item, sourceKey));
    }
  }
  return out;
}

export function parseStringList(value: Object | undefined): string[] {
  const out: string[] = [];
  if (value === undefined || value === null || !Array.isArray(value)) {
    return out;
  }
  const list = value as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item === null || item === undefined) {
      continue;
    }
    out.push(String(item));
  }
  return out;
}

export function parseComment(value: Object): Comment {
  const record = value as Record<string, Object>;
  const comment = new Comment();
  comment.userName = toStringOrNull(record['userName']) ?? '';
  comment.avatar = toStringOrNull(record['avatar']);
  comment.content = toStringOrNull(record['content']) ?? '';
  comment.time = Comment.parseTime(record['time']);
  comment.replyCount = toIntOrNull(record['replyCount']);
  const id = toStringOrNull(record['id']);
  comment.id = id;
  comment.score = toIntOrNull(record['score']);
  comment.isLiked = toBoolOrNull(record['isLiked']);
  comment.voteStatus = toIntOrNull(record['voteStatus']);
  return comment;
}

export function parseCommentList(value: Object | undefined): Comment[] {
  const out: Comment[] = [];
  if (value === undefined || value === null || !Array.isArray(value)) {
    return out;
  }
  const list = value as Object[];
  for (let i = 0; i < list.length; i++) {
    const item = list[i];
    if (item !== null && typeof item === 'object') {
      out.push(parseComment(item));
    }
  }
  return out;
}
