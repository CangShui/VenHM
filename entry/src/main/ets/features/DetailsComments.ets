import { Comment } from '../model/Comic';
import { ComicSource } from '../source/ComicSource';
import { DetailsCommentsParams } from '../source/DetailsCapabilities';
import { Res } from '../model/Res';
import { SourceFailure } from './SourceFailure';

/** A locked comment thread. All writes are opt-in public action methods, never loads/lifecycle. */
export class DetailsComments {
  rows: Comment[] = [];
  page: number = 0;
  loading: boolean = false;
  writing: boolean = false;
  ended: boolean = false;
  error: string = '';
  canSend: boolean = false;
  canLike: boolean = false;
  canVote: boolean = false;
  private source?: ComicSource;
  private params?: DetailsCommentsParams;
  private generation: number = 0;
  private maxPage?: number;

  start(source: ComicSource, params: DetailsCommentsParams): void {
    this.invalidate(); this.source = source; this.params = params;
    this.rows = params.replyTo === undefined ? (params.initialComments ?? []).slice() : [];
    this.page = 0; this.maxPage = undefined; this.error = ''; this.ended = false;
    const data = source.detailsMedia;
    this.canSend = params.epId === undefined ? data?.sendComment !== undefined : data?.sendChapterComment !== undefined;
    this.canLike = params.epId === undefined && data?.likeComment !== undefined;
    this.canVote = params.epId === undefined && data?.voteComment !== undefined;
    if (source.key !== params.sourceKey || !this.hasLoader()) {
      this.ended = true;
      if (this.rows.length === 0) { this.error = '原始漫画源未声明此评论加载能力'; }
    }
  }

  private hasLoader(): boolean {
    return this.params?.epId === undefined ? this.source?.loadComicComments !== undefined : this.source?.loadChapterComments !== undefined;
  }

  invalidate(): void { this.generation++; this.loading = false; this.writing = false; }

  async more(reset: boolean = false): Promise<void> {
    if (this.loading || this.writing || (!reset && this.ended) || !this.hasLoader()) { return; }
    const source = this.source; const params = this.params;
    if (source === undefined || params === undefined || source.key !== params.sourceKey) { return; }
    const generation = this.generation; const page = reset ? 1 : this.page + 1;
    this.loading = true; this.error = '';
    try {
      let result: Res<Comment[]>;
      if (params.epId !== undefined) {
        result = await source.loadChapterComments!(params.comicId, params.epId, page, params.replyTo);
      } else {
        result = await source.loadComicComments!(params.comicId, params.subId, page, params.replyTo);
      }
      if (generation !== this.generation) { return; }
      if (result.error || result.dataOrNull === undefined) { throw new Error(result.errorMessage ?? 'Invalid comments'); }
      const incoming = result.data;
      const existing = page === 1 ? [] : this.rows.slice();
      let added = 0;
      for (const row of incoming) {
        if (row.id !== undefined && existing.some((item: Comment): boolean => item.id === row.id)) { continue; }
        existing.push(row); added++;
      }
      this.rows = existing; this.page = page;
      this.maxPage = typeof result.subData === 'number' ? result.subData as number : (reset ? undefined : this.maxPage);
      this.ended = incoming.length === 0 || (page > 1 && added === 0) || (this.maxPage !== undefined && page >= this.maxPage);
    } catch (error) { if (generation === this.generation) { this.error = SourceFailure.message(error); } }
    finally { if (generation === this.generation) { this.loading = false; } }
  }

  async send(content: string): Promise<boolean> {
    const source = this.source; const params = this.params;
    if (!this.canSend || this.loading || this.writing || content.trim().length === 0 || source === undefined || params === undefined) { return false; }
    const generation = this.generation; this.writing = true; this.error = '';
    let success = false;
    try {
      let result: Res<boolean>;
      if (params.epId !== undefined) {
        result = await source.detailsMedia!.sendChapterComment!(params.comicId, params.epId, content, params.replyTo);
      } else {
        result = await source.detailsMedia!.sendComment!(params.comicId, params.subId, content, params.replyTo);
      }
      if (generation !== this.generation) { return false; }
      if (result.error) { throw new Error(result.errorMessage ?? 'Send failed'); }
      success = true;
    } catch (error) { if (generation === this.generation) { this.error = SourceFailure.message(error); } }
    finally { if (generation === this.generation) { this.writing = false; } }
    if (success && generation === this.generation) { await this.more(true); }
    return success;
  }

  async react(comment: Comment, action: string): Promise<void> {
    const source = this.source; const params = this.params;
    if (this.writing || this.loading || source === undefined || params === undefined ||
      comment.id === undefined || comment.id.length === 0 || !this.rows.includes(comment) || comment.score === undefined) { return; }
    if ((action === 'like' && !this.canLike) || (action !== 'like' && !this.canVote) || !['like', 'up', 'down'].includes(action)) { return; }
    const generation = this.generation; this.writing = true; this.error = '';
    const liking = !(comment.isLiked ?? false); const up = action === 'up';
    const cancel = comment.voteStatus === (up ? 1 : -1);
    try {
      const result = action === 'like'
        ? await source.detailsMedia!.likeComment!(params.comicId, params.subId, comment.id, liking)
        : await source.detailsMedia!.voteComment!(params.comicId, params.subId, comment.id, up, cancel);
      if (generation !== this.generation) { return; }
      if (result.error) { throw new Error(result.errorMessage ?? 'Reaction failed'); }
      if (action === 'like') { comment.isLiked = liking; comment.score = (comment.score ?? 0) + (liking ? 1 : -1); }
      else { comment.voteStatus = cancel ? 0 : (up ? 1 : -1); comment.score = result.data; }
      this.rows = this.rows.slice();
    } catch (error) { if (generation === this.generation) { this.error = SourceFailure.message(error); } }
    finally { if (generation === this.generation) { this.writing = false; } }
  }
}
