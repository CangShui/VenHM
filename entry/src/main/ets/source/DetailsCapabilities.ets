import { Comment } from '../model/Comic';
import { Res } from '../model/Res';

/** Exact fixed-upstream comic callbacks. Undeclared callbacks remain absent. */
export class DetailsCapabilities {
  loadComicThumbnail?: (id: string, next: string | null) => Promise<Res<string[]>>;
  loadComments?: (id: string, subId: string | undefined, page: number, replyTo: string | undefined) => Promise<Res<Comment[]>>;
  loadChapterComments?: (id: string, epId: string, page: number, replyTo: string | undefined) => Promise<Res<Comment[]>>;
  sendComment?: (id: string, subId: string | undefined, content: string, replyTo: string | undefined) => Promise<Res<boolean>>;
  sendChapterComment?: (id: string, epId: string, content: string, replyTo: string | undefined) => Promise<Res<boolean>>;
  likeComment?: (id: string, subId: string | undefined, commentId: string, isLiking: boolean) => Promise<Res<number>>;
  voteComment?: (id: string, subId: string | undefined, commentId: string, isUp: boolean, isCancel: boolean) => Promise<Res<number>>;
}

export interface DetailsViewerParams {
  sourceKey: string;
  comicId: string;
  title: string;
  images: string[];
  index: number;
  /** Preview/cover URLs use onThumbnailLoad, never loadEp/onImageLoad. */
  thumbnail: boolean;
}

export interface DetailsCommentsParams {
  sourceKey: string;
  comicId: string;
  title: string;
  subId?: string;
  epId?: string;
  replyTo?: string;
  replyUser?: string;
  replyContent?: string;
  initialComments?: Comment[];
}
