/**
 * Semver comparison ported from VeneraNext.
 *
 * Dart original: lib/foundation/comic_source/parser.dart compareSemVer().
 * Returns true when ver1 > ver2. Both versions are compared segment by segment
 * over the first three numeric segments; a fourth segment (pre-release suffix)
 * is compared as text.
 */
export function compareSemVer(ver1: string, ver2: string): boolean {
  const a: string = ver1.replace('-', '.');
  const b: string = ver2.replace('-', '.');
  const v1: string[] = a.split('.');
  const v2: string[] = b.split('.');

  for (let i = 0; i < 3; i++) {
    const n1: number = parseInt(v1[i] ?? '0', 10);
    const n2: number = parseInt(v2[i] ?? '0', 10);
    if (n1 > n2) {
      return true;
    } else if (n1 < n2) {
      return false;
    }
  }

  const v14: string | undefined = v1.length > 3 ? v1[3] : undefined;
  const v24: string | undefined = v2.length > 3 ? v2[3] : undefined;
  if (v14 === undefined && v24 === undefined) {
    return false;
  }
  if (v14 === undefined) {
    return false;
  }
  if (v24 === undefined) {
    return true;
  }
  return v14 > v24;
}

/** True when `version` is a plain three-segment numeric version. */
export function isSemver(version: string): boolean {
  return new RegExp('^\\d+\\.\\d+\\.\\d+([.\\-].+)?$').test(version);
}
