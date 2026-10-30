/** Pure reading-position rules; no source runtime, router, database or ArkUI dependency. */
export class ReadingPosition {
  chapterIndex: number = -1;
  error: string = '';

  /** epIndex is 1-based, exactly like History.ep. An explicit '' is a real single-chapter id. */
  static resolveChapter(chapterIds: string[], epId?: string, epIndex?: number): ReadingPosition {
    const position = new ReadingPosition();
    if (chapterIds.length === 0) {
      position.error = '该漫画没有可用章节';
      return position;
    }
    if (epId !== undefined) {
      position.chapterIndex = chapterIds.indexOf(epId);
      if (position.chapterIndex < 0) {
        position.error = '要阅读的章节已不存在，请返回详情手动选择章节；原阅读记录已保留。';
      }
      return position;
    }
    if (epIndex !== undefined) {
      if (!Number.isFinite(epIndex) || Math.floor(epIndex) !== epIndex ||
        epIndex < 1 || epIndex > chapterIds.length) {
        position.error = '旧阅读记录的章节序号已失效，请返回详情手动选择章节；原阅读记录已保留。';
        return position;
      }
      position.chapterIndex = epIndex - 1;
      return position;
    }
    position.chapterIndex = 0;
    return position;
  }

  /** Convert a persisted 1-based page to a bounded UI index; an empty chapter has no valid index. */
  static pageIndex(page: number | undefined, pageCount: number): number {
    if (!Number.isFinite(pageCount) || pageCount < 1) {
      return -1;
    }
    if (page === undefined || !Number.isFinite(page) || page < 1) {
      return 0;
    }
    return Math.min(Math.floor(page) - 1, Math.floor(pageCount) - 1);
  }
}
