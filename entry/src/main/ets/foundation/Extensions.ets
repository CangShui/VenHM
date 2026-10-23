/**
 * Small collection helpers.
 *
 * Dart original: package:collection extensions used throughout VeneraNext
 * (firstWhereOrNull, mapNotNull, elementAtOrNull, ...). ArkTS has no such
 * package, so the handful actually used by the ported code lives here.
 */

export function firstWhereOrNull<T>(list: T[], test: (item: T) => boolean): T | undefined {
  for (let i = 0; i < list.length; i++) {
    if (test(list[i])) {
      return list[i];
    }
  }
  return undefined;
}

export function elementAtOrNull<T>(list: T[], index: number): T | undefined {
  if (index < 0 || index >= list.length) {
    return undefined;
  }
  return list[index];
}

export function indexWhere<T>(list: T[], test: (item: T) => boolean): number {
  for (let i = 0; i < list.length; i++) {
    if (test(list[i])) {
      return i;
    }
  }
  return -1;
}

export function mapNotNull<T, R>(list: T[], transform: (item: T) => R | undefined): R[] {
  const out: R[] = [];
  for (let i = 0; i < list.length; i++) {
    const value: R | undefined = transform(list[i]);
    if (value !== undefined) {
      out.push(value);
    }
  }
  return out;
}

export function distinct<T>(list: T[]): T[] {
  const out: T[] = [];
  for (let i = 0; i < list.length; i++) {
    if (out.indexOf(list[i]) < 0) {
      out.push(list[i]);
    }
  }
  return out;
}

/** Splits a string and drops empty entries - used by tag/path parsing. */
export function splitNonEmpty(text: string, separator: string): string[] {
  const out: string[] = [];
  const parts: string[] = text.split(separator);
  for (let i = 0; i < parts.length; i++) {
    const p: string = parts[i].trim();
    if (p.length > 0) {
      out.push(p);
    }
  }
  return out;
}

/** Reads an int from unknown JSON values without throwing. */
export function toIntOrNull(value: Object | undefined | null): number | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'number') {
    return Math.trunc(value as number);
  }
  if (typeof value === 'string') {
    const n: number = parseInt(value as string, 10);
    return isNaN(n) ? undefined : n;
  }
  return undefined;
}

/** Reads a double from unknown JSON values without throwing. */
export function toDoubleOrNull(value: Object | undefined | null): number | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'number') {
    return value as number;
  }
  if (typeof value === 'string') {
    const n: number = parseFloat(value as string);
    return isNaN(n) ? undefined : n;
  }
  return undefined;
}

/** Reads a string from unknown JSON values without throwing. */
export function toStringOrNull(value: Object | undefined | null): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'string') {
    return value as string;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return undefined;
}

export function toBoolOrNull(value: Object | undefined | null): boolean | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }
  if (typeof value === 'boolean') {
    return value as boolean;
  }
  if (typeof value === 'string') {
    const s: string = (value as string).toLowerCase();
    if (s === 'true') {
      return true;
    }
    if (s === 'false') {
      return false;
    }
  }
  if (typeof value === 'number') {
    return (value as number) !== 0;
  }
  return undefined;
}
