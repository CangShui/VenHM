import { router, promptAction } from '@kit.ArkUI';
import { AppContext } from '../foundation/AppContext';
import { AppInit } from '../foundation/AppInit';
import { SourceManager } from '../source/SourceManager';
import { Comment } from '../model/Comic';
import { DetailsCommentsParams } from '../source/DetailsCapabilities';
import { DetailsComments } from '../features/DetailsComments';
import { AsyncComicImage } from '../components/ComicWidgets';
import { UiTheme, UiIcon, UiPageHeader } from '../components/UiKit';
import { UiStyles } from '../components/UiModifiers';

@Entry
@Component
struct CommentsPage {
  @State params: DetailsCommentsParams = { sourceKey: '', comicId: '', title: '' };
  @State comments: Comment[] = [];
  @State loading: boolean = false;
  @State writing: boolean = false;
  @State ended: boolean = false;
  @State error: string = '';
  @State draft: string = '';
  @State canSend: boolean = false;
  @State canLike: boolean = false;
  @State canVote: boolean = false;
  private session: DetailsComments = new DetailsComments();
  private disposed: boolean = false;
  private version: number = 0;
  private initialized: boolean = false;

  aboutToAppear(): void {
    this.disposed = false;
    AppContext.ensureInitialized(this.getUIContext().getHostContext());
    const params = router.getParams() as DetailsCommentsParams;
    if (params !== undefined && params !== null) { this.params = params; }
    this.initialize();
  }
  onPageHide(): void { this.disposed = true; this.version++; this.session.invalidate(); this.loading = false; this.writing = false; }
  aboutToDisappear(): void { this.onPageHide(); }
  onPageShow(): void {
    if (this.disposed) { this.disposed = false; if (!this.initialized) { this.initialize(); } else { this.sync(); } }
  }
  private sync(): void {
    this.comments = this.session.rows.slice(); this.loading = this.session.loading;
    this.writing = this.session.writing; this.ended = this.session.ended; this.error = this.session.error;
    this.canSend = this.session.canSend; this.canLike = this.session.canLike; this.canVote = this.session.canVote;
  }
  private async initialize(): Promise<void> {
    const version = ++this.version; this.loading = true; this.error = '';
    try {
      await AppInit.init();
      if (this.disposed || version !== this.version) { return; }
      const source = SourceManager.find(this.params.sourceKey);
      if (source === undefined) { this.error = '原始漫画源已不可用'; this.loading = false; return; }
      this.session.start(source, this.params); this.initialized = true;
      await this.loadMore();
    } catch (error) {
      if (!this.disposed && version === this.version) { this.loading = false; this.error = '评论初始化失败，请重试'; }
    }
  }
  private async loadMore(reset: boolean = false): Promise<void> {
    if (this.disposed) { return; }
    const version = this.version;
    const request = this.session.more(reset); this.sync();
    await request;
    if (!this.disposed && version === this.version) { this.sync(); }
  }
  private openReplies(comment: Comment): void {
    if (this.disposed || comment.id === undefined || comment.id.length === 0 || comment.replyCount === undefined) { return; }
    const params: DetailsCommentsParams = { sourceKey: this.params.sourceKey, comicId: this.params.comicId,
      title: this.params.title, subId: this.params.subId, epId: this.params.epId, replyTo: comment.id,
      replyUser: comment.userName, replyContent: comment.content };
    router.pushUrl({ url: 'pages/CommentsPage', params: params }).catch(() => {
      if (!this.disposed) { promptAction.showToast({ message: '无法打开回复' }); }
    });
  }
  private async send(): Promise<void> {
    if (this.disposed || this.writing || !this.canSend || this.draft.trim().length === 0) { return; }
    const version = this.version; const content = this.draft;
    // Explicit send tap is the sole entry. No automatic login or automatic write retry.
    const request = this.session.send(content); this.sync();
    const success = await request;
    if (this.disposed || version !== this.version) { return; }
    if (success && this.draft === content) { this.draft = ''; }
    this.sync();
  }
  private async react(comment: Comment, action: string): Promise<void> {
    if (this.disposed || this.writing) { return; }
    const version = this.version; const request = this.session.react(comment, action); this.sync();
    await request;
    if (!this.disposed && version === this.version) { this.sync(); }
  }

  build() {
    Scroll() {
      Column() {
        UiPageHeader({ title: this.params.replyTo === undefined ? '评论' : '回复', subtitle: this.params.title, onBack: () => { router.back(); } })
        Column({ space: 16 }) {
        Button('刷新').attributeModifier(UiStyles.secondary).enabled(!this.loading && !this.writing)
          .onClick(() => { if (this.initialized) { this.loadMore(true); } else { this.initialize(); } })
        if (this.params.replyTo !== undefined) {
          Column({ space: 10 }) {
            Text(this.params.replyUser ?? '').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
            Text(this.params.replyContent ?? '').fontSize(13).lineHeight(21).fontColor(UiTheme.secondary).maxLines(5)
          }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }
        if (this.error.length > 0) {
          Column({ space: 12 }) {
            Text(this.error).fontSize(13).lineHeight(20).fontColor(UiTheme.danger).width('100%')
            Button('重试加载').attributeModifier(UiStyles.secondary).enabled(!this.loading && !this.writing).onClick(() => {
              if (this.initialized) { this.loadMore(this.comments.length === 0); } else { this.initialize(); }
            })
          }.padding(20).width('100%').alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }
        ForEach(this.comments, (comment: Comment, index: number) => {
          Column({ space: 14 }) {
            Row({ space: 12 }) {
              if ((comment.avatar ?? '').length > 0) {
                Column() { AsyncComicImage({ url: comment.avatar ?? '', sourceKey: this.params.sourceKey, comicId: this.params.comicId, thumbnail: true }) }
                  .width(44).height(44).borderRadius(16).clip(true)
              }
              Column({ space: 5 }) {
                Text(comment.userName).fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink).width('100%')
                if (comment.time !== undefined) { Text(comment.time).fontSize(12).fontColor(UiTheme.muted).width('100%') }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
            }.width('100%').alignItems(VerticalAlign.Top)
            // Plain selectable text, not executable Web content; rich HTML rendering remains separate.
            Text(comment.content).fontSize(14).lineHeight(23).fontColor(UiTheme.ink).copyOption(CopyOptions.LocalDevice).width('100%')
            Flex({ wrap: FlexWrap.Wrap, alignItems: ItemAlign.Center }) {
              if (comment.score !== undefined) { Text(`评分 ${comment.score}`).fontSize(12).fontColor(UiTheme.secondary).margin({ right: 8, bottom: 8 }).constraintSize({ minHeight: 44 }) }
              if (comment.id !== undefined && comment.score !== undefined && this.canLike) {
                Button(comment.isLiked ? '取消赞' : '赞').attributeModifier(UiStyles.quiet).height(44).margin({ right: 8, bottom: 8 }).enabled(!this.writing && !this.loading).onClick(() => { this.react(comment, 'like'); })
              }
              if (comment.id !== undefined && comment.score !== undefined && this.canVote) {
                Button(comment.voteStatus === 1 ? '取消顶' : '顶').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).enabled(!this.writing && !this.loading).onClick(() => { this.react(comment, 'up'); })
                Button(comment.voteStatus === -1 ? '取消踩' : '踩').attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).enabled(!this.writing && !this.loading).onClick(() => { this.react(comment, 'down'); })
              }
              if (comment.id !== undefined && comment.replyCount !== undefined) {
                Button(`回复 ${comment.replyCount}`).attributeModifier(UiStyles.secondary).margin({ right: 8, bottom: 8 }).onClick(() => { this.openReplies(comment); })
              }
            }.width('100%')
          }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }, (comment: Comment, index: number) => `${index}:${comment.id ?? ''}`)
        Column({ space: 12 }) {
          if (this.loading) { LoadingProgress().width(28).height(28).color(UiTheme.accent) }
          else if (this.comments.length === 0 && this.error.length === 0) { Text('暂无评论').fontSize(14).fontColor(UiTheme.muted) }
          Button(this.ended ? '没有更多评论' : '加载更多').attributeModifier(UiStyles.secondary)
            .enabled(!this.loading && !this.writing && !this.ended).onClick(() => { this.loadMore(); })
        }.width('100%').padding(20)
        if (this.canSend) {
          Column({ space: 12 }) {
            Row({ space: 10 }) {
              UiIcon({ name: 'message', iconSize: 21, color: UiTheme.accent })
              Text(this.params.replyTo === undefined ? '写评论' : '写回复').fontSize(16).fontWeight(FontWeight.Medium).fontColor(UiTheme.ink)
            }.width('100%')
            TextArea({ placeholder: this.params.replyTo === undefined ? '写评论（点击发送才提交）' : '写回复（点击发送才提交）', text: this.draft })
              .width('100%').height(108).fontSize(14).backgroundColor(UiTheme.page).borderRadius(16).onChange((value: string) => { this.draft = value; })
            Button(this.writing ? '提交中…' : '发送').attributeModifier(UiStyles.primary)
              .enabled(!this.writing && !this.loading && this.draft.trim().length > 0).onClick(() => { this.send(); })
          }.width('100%').padding(20).alignItems(HorizontalAlign.Start).backgroundColor(UiTheme.surface).borderRadius(UiTheme.cardRadius)
        }
      }.width('100%').padding({ left: UiTheme.gutter, right: UiTheme.gutter, bottom: UiTheme.bottomInset }).alignItems(HorizontalAlign.Start)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').height('100%').scrollBar(BarState.Off).backgroundColor(UiTheme.page)
  }
}
