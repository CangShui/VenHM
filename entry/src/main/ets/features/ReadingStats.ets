/** Disjoint local-calendar day segments; DST boundaries use calendar arithmetic, not 24h. */
export class ReadingDaySegment {
  day: string = '';
  durationMs: number = 0;
}
export class ReadingStats {
  static day(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }
  static split(end: number, durationMs: number): ReadingDaySegment[] {
    const result: ReadingDaySegment[] = [];
    if (!Number.isFinite(end) || !Number.isFinite(durationMs) || durationMs <= 0) { return result; }
    let cursor = Math.max(0, end - Math.floor(durationMs));
    while (cursor < end) {
      const date = new Date(cursor);
      const next = new Date(date.getFullYear(), date.getMonth(), date.getDate() + 1).getTime();
      const stop = Math.min(end, next);
      if (stop <= cursor) { break; }
      const segment = new ReadingDaySegment(); segment.day = ReadingStats.day(cursor);
      segment.durationMs = stop - cursor; result.push(segment); cursor = stop;
    }
    return result;
  }
  static duration(ms: number): string {
    const seconds = Math.max(0, Math.floor(ms / 1000));
    return `${Math.floor(seconds / 3600)}小时 ${Math.floor(seconds / 60) % 60}分 ${seconds % 60}秒`;
  }
}
