import { Comment, parseCommentList } from '../model/Comic';
import { Res } from '../model/Res';
import { JsEngine } from './JsEngine';
import { DetailsCapabilities } from './DetailsCapabilities';
import { SourceFailure } from '../features/SourceFailure';
import { Log } from '../foundation/Log';

/** parser.dart at 7110c19: comic.loadThumbnails/loadComments, not guessed aliases. */
export class JsDetailsAdapter {
  static create(key: string, scriptPath: string, has: Record<string, Object>): DetailsCapabilities {
    const adapter = new JsDetailsAdapter(key, scriptPath);
    const data = new DetailsCapabilities();
    if (has['loadThumbnails'] === true) {
      data.loadComicThumbnail = (id: string, next: string | null): Promise<Res<string[]>> => adapter.thumbnails(id, next);
    }
    if (has['loadComments'] === true) {
      data.loadComments = (id: string, subId: string | undefined, page: number, replyTo: string | undefined): Promise<Res<Comment[]>> =>
        adapter.comments('loadComments', id, subId, page, replyTo);
    }
    if (has['loadChapterComments'] === true) {
      data.loadChapterComments = (id: string, epId: string, page: number, replyTo: string | undefined): Promise<Res<Comment[]>> =>
        adapter.comments('loadChapterComments', id, epId, page, replyTo);
    }
    if (has['sendComment'] === true) {
      data.sendComment = (id: string, subId: string | undefined, content: string, replyTo: string | undefined): Promise<Res<boolean>> =>
        adapter.send('sendComment', id, subId, content, replyTo);
    }
    if (has['sendChapterComment'] === true) {
      data.sendChapterComment = (id: string, epId: string, content: string, replyTo: string | undefined): Promise<Res<boolean>> =>
        adapter.send('sendChapterComment', id, epId, content, replyTo);
    }
    if (has['likeComment'] === true) {
      data.likeComment = (id: string, subId: string | undefined, commentId: string, isLiking: boolean): Promise<Res<number>> =>
        adapter.score('likeComment', [id, subId ?? null, commentId, isLiking]);
    }
    if (has['voteComment'] === true) {
      data.voteComment = (id: string, subId: string | undefined, commentId: string, isUp: boolean, isCancel: boolean): Promise<Res<number>> =>
        adapter.score('voteComment', [id, subId ?? null, commentId, isUp, isCancel]);
    }
    return data;
  }

  private key: string;
  private scriptPath: string;
  constructor(key: string, scriptPath: string) { this.key = key; this.scriptPath = scriptPath; }

  private async call(method: string, args: (string | number | boolean | null)[]): Promise<Object | null> {
    const trace = `details-${method}-${Date.now()}`;
    Log.audit(trace, '详情源回调到达', '锁定入口源；不记录ID、游标、评论、账号或响应正文');
    try {
      // Serialize each positional argument; missing optional values are null like jsonEncode upstream.
      const values = args.map((value: string | number | boolean | null): string => JSON.stringify(value)).join(',');
      const result = await JsEngine.callJson(`ComicSource.sources[${JSON.stringify(this.key)}].comic.${method}(${values})`, this.scriptPath, trace);
      Log.audit(trace, '详情源回调返回', '回调完成；写操作只从明确用户动作到达，不自动重放');
      return result;
    } catch (error) {
      Log.audit(trace, '详情源回调异常', '保留失败阶段，不记录异常正文；写操作不自动重试/重新登录');
      throw new Error(SourceFailure.message(error));
    }
  }

  private static record(value: Object | null | undefined): Record<string, Object> {
    if (value === undefined || value === null || typeof value !== 'object' || Array.isArray(value)) { throw new Error('Invalid data'); }
    return value as Record<string, Object>;
  }

  private async thumbnails(id: string, next: string | null): Promise<Res<string[]>> {
    try {
      const record = JsDetailsAdapter.record(await this.call('loadThumbnails', [id, next]));
      const items = record['thumbnails'];
      if (!Array.isArray(items) || !(items as Object[]).every((item: Object): boolean => typeof item === 'string')) { throw new Error('Invalid thumbnails'); }
      const cursor = record['next'];
      if (cursor !== undefined && cursor !== null && typeof cursor !== 'string') { throw new Error('Invalid next'); }
      return Res.ok<string[]>(items as string[], cursor === null ? undefined : cursor);
    } catch (error) { return Res.fail<string[]>(SourceFailure.message(error)); }
  }

  private async comments(method: string, id: string, subId: string | undefined, page: number, replyTo: string | undefined): Promise<Res<Comment[]>> {
    try {
      const record = JsDetailsAdapter.record(await this.call(method, [id, subId ?? null, page, replyTo ?? null]));
      const rows = record['comments'];
      if (!Array.isArray(rows) || !(rows as Object[]).every((row: Object): boolean => row !== null && typeof row === 'object' && !Array.isArray(row))) { throw new Error('Invalid comments'); }
      const maxPage = record['maxPage'];
      if (maxPage !== undefined && maxPage !== null && (typeof maxPage !== 'number' || !Number.isInteger(maxPage) || (maxPage as number) < 1)) { throw new Error('Invalid maxPage'); }
      return Res.ok<Comment[]>(parseCommentList(rows), maxPage === null ? undefined : maxPage);
    } catch (error) { return Res.fail<Comment[]>(SourceFailure.message(error)); }
  }

  private async send(method: string, id: string, subId: string | undefined, content: string, replyTo: string | undefined): Promise<Res<boolean>> {
    try {
      // Upstream: any completed return (including undefined/false/string) means success.
      await this.call(method, [id, subId ?? null, content, replyTo ?? null]);
      return Res.ok<boolean>(true);
    } catch (error) { return Res.fail<boolean>(SourceFailure.message(error)); }
  }

  private async score(method: string, args: (string | number | boolean | null)[]): Promise<Res<number>> {
    try {
      const value = await this.call(method, args);
      return Res.ok<number>(typeof value === 'number' && Number.isFinite(value) ? Math.trunc(value) : 0);
    } catch (error) { return Res.fail<number>(SourceFailure.message(error)); }
  }
}
