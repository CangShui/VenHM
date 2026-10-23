/** Pure UI icon metrics: numeric ArkUI lengths are vp, never font/density-scaled. */
export function uiIconSize(value: number): number {
  if (!Number.isFinite(value) || value <= 0) {
    return 24;
  }
  return Math.min(72, Math.max(16, value));
}

/**
 * Row-first RGBA 4x5 matrix for packaged white, fill-none SVG strokes.
 * Image.colorFilter accepts new ColorFilter(number[]) in the installed SDK.
 * Multiply RGB only; the alpha row is identity so antialiasing stays intact.
 */
export function uiIconTintMatrix(color: string): number[] {
  const hex: string = /^#[0-9a-fA-F]{6}$/.test(color) ? color : '#171A21';
  const red: number = parseInt(hex.substring(1, 3), 16) / 255;
  const green: number = parseInt(hex.substring(3, 5), 16) / 255;
  const blue: number = parseInt(hex.substring(5, 7), 16) / 255;
  return [
    red, 0, 0, 0, 0,
    0, green, 0, 0, 0,
    0, 0, blue, 0, 0,
    0, 0, 0, 1, 0
  ];
}
