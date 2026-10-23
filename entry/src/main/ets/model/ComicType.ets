/**
 * ComicType - identifies which comic source a record belongs to.
 *
 * Dart original: lib/foundation/comic_type.dart used `key.hashCode` as the
 * persisted integer. Dart's String.hashCode is not reproducible outside the VM,
 * so the port uses a documented, stable FNV-1a 32-bit hash instead.
 *
 * NOTE: this value is persisted in the database. Never change the algorithm
 * without a migration, otherwise stored favorites/history lose their source.
 */
export class ComicType {
  readonly value: number;

  constructor(value: number) {
    this.value = value;
  }

  static readonly local: ComicType = new ComicType(0);

  /** FNV-1a 32-bit - stable across runs and platforms. */
  static hashKey(key: string): number {
    let hash: number = 0x811c9dc5;
    for (let i = 0; i < key.length; i++) {
      hash = hash ^ key.charCodeAt(i);
      // hash *= 16777619 with 32-bit overflow semantics
      hash = (hash + ((hash << 1) + (hash << 4) + (hash << 7) + (hash << 8) + (hash << 24))) >>> 0;
    }
    return hash >>> 0;
  }

  static fromKey(key: string): ComicType {
    if (key === 'local') {
      return ComicType.local;
    }
    return new ComicType(ComicType.hashKey(key));
  }

  static fromValue(value: number): ComicType {
    return new ComicType(value);
  }

  get isLocal(): boolean {
    return this.value === 0;
  }

  equals(other: ComicType): boolean {
    return this.value === other.value;
  }

  toString(): string {
    return `ComicType(${this.value})`;
  }
}
