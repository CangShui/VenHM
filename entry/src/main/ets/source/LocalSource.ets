import { fileIo as fs } from '@kit.CoreFileKit';
import { Comic, ComicItem } from '../model/Comic';
import { ComicChapters } from '../model/Comic';
import { ComicDetails } from '../model/ComicDetails';
import { Res } from '../model/Res';
import { AppContext } from '../foundation/AppContext';
import { Log } from '../foundation/Log';
import { ComicSource, ExplorePageData, SearchPageData } from './ComicSource';

const IMAGE_EXTENSIONS: string[] = ['.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp', '.avif'];

/**
 * Local comics source - reads a folder tree from the app sandbox.
 *
 * Dart original: lib/features/local_comics/local.dart (`LocalManager`) plus
 * lib/features/comic_storage/file_system_layout.dart (layout inference).
 * This port deliberately implements only the layout rules needed by the
 * minimal loop: a comic is a directory; its sub directories are chapters when
 * they exist, otherwise the directory's own images are a single chapter.
 *
 * Page "urls" use the `file://` scheme so the image loader can tell them apart
 * from network URLs.
 */
export class LocalSource extends ComicSource {
  constructor() {
    super('local', '本地漫画');
    this.version = '1.0.0';
    this.description = '读取应用沙箱 local_comics 目录下的图片目录';

    const search = new SearchPageData();
    search.loadPage = (keyword: string, page: number, options: string[]): Promise<Res<Comic[]>> =>
      this.searchLocal(keyword, page);
    this.search = search;

    const explore = new ExplorePageData();
    explore.title = '本地漫画';
    explore.loadPage = (page: number): Promise<Res<Comic[]>> => this.loadAll(page);
    this.explorePages = [explore];

    this.loadComicInfo = (id: string): Promise<Res<ComicDetails>> => this.loadInfo(id);
    this.loadComicPages = (id: string, ep?: string): Promise<Res<string[]>> =>
      this.loadPages(id, ep);
  }

  private rootDir(): string {
    return AppContext.localComicDir;
  }

  private ensureRoot(): void {
    const root = this.rootDir();
    if (!fs.accessSync(root)) {
      fs.mkdirSync(root, true);
      Log.info('LocalSource', `created ${root}`);
    }
  }

  private listDirectories(path: string): string[] {
    const out: string[] = [];
    try {
      const entries = fs.listFileSync(path, { recursion: false });
      for (let i = 0; i < entries.length; i++) {
        const name = entries[i];
        if (name.startsWith('.')) {
          continue;
        }
        const full = `${path}/${name}`;
        try {
          if (fs.statSync(full).isDirectory()) {
            out.push(name);
          }
        } catch (error) {
          Log.warn('LocalSource', `stat failed: ${full}`);
        }
      }
    } catch (error) {
      Log.warn('LocalSource', `list failed: ${path}`);
    }
    out.sort();
    return out;
  }

  private listImages(path: string): string[] {
    const out: string[] = [];
    try {
      const entries = fs.listFileSync(path, { recursion: false });
      for (let i = 0; i < entries.length; i++) {
        const name = entries[i];
        if (name.startsWith('.')) {
          continue;
        }
        const lower = name.toLowerCase();
        for (let e = 0; e < IMAGE_EXTENSIONS.length; e++) {
          if (lower.endsWith(IMAGE_EXTENSIONS[e])) {
            const full = `${path}/${name}`;
            if (fs.statSync(full).isFile()) { out.push(name); }
            break;
          }
        }
      }
    } catch (error) {
      Log.warn('LocalSource', `list images failed: ${path}`);
    }
    out.sort((a: string, b: string) => LocalSource.compareNatural(a, b));
    return out;
  }

  /** Natural sort so `2.jpg` precedes `10.jpg`. */
  static compareNatural(a: string, b: string): number {
    const ra = /(\d+)|(\D+)/g;
    const rb = /(\d+)|(\D+)/g;
    const ma = a.match(ra) ?? [];
    const mb = b.match(rb) ?? [];
    const len = Math.min(ma.length, mb.length);
    for (let i = 0; i < len; i++) {
      const sa = ma[i];
      const sb = mb[i];
      const na = parseInt(sa, 10);
      const nb = parseInt(sb, 10);
      if (!isNaN(na) && !isNaN(nb)) {
        if (na !== nb) {
          return na - nb;
        }
      } else if (sa !== sb) {
        return sa < sb ? -1 : 1;
      }
    }
    return ma.length - mb.length;
  }

  private buildComic(dirName: string): ComicItem {
    const comic = new ComicItem(this.key);
    comic.id = dirName;
    comic.title = this.displayTitle(dirName);
    comic.subtitle = '';
    comic.description = '';
    const cover = this.findCover(dirName);
    comic.cover = cover;
    return comic;
  }

  private displayTitle(dirName: string): string {
    if (!/^DL_[0-9]+_[0-9]+$/.test(dirName)) { return dirName; }
    try {
      const path = `${this.rootDir()}/${dirName}/download.json`;
      if (!fs.accessSync(path)) { return dirName; }
      const metadata = JSON.parse(fs.readTextSync(path)) as Record<string, Object>;
      if (metadata['owner'] === dirName && typeof metadata['title'] === 'string') {
        return metadata['title'] as string;
      }
    } catch (error) { Log.warn('LocalSource', 'download metadata invalid; using folder name'); }
    return dirName;
  }
  private findCover(dirName: string): string {
    const dir = `${this.rootDir()}/${dirName}`;
    const images = this.listImages(dir);
    if (images.length > 0) {
      return `file://${dir}/${images[0]}`;
    }
    const chapters = this.listDirectories(dir);
    for (let i = 0; i < chapters.length; i++) {
      const chapterImages = this.listImages(`${dir}/${chapters[i]}`);
      if (chapterImages.length > 0) {
        return `file://${dir}/${chapters[i]}/${chapterImages[0]}`;
      }
    }
    return '';
  }

  private async loadAll(page: number): Promise<Res<Comic[]>> {
    this.ensureRoot();
    const names = this.listDirectories(this.rootDir());
    const comics: Comic[] = [];
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      // Old explicitly-created diagnostic samples are not the user's library.
      // Only exclude the strict test name WITH its exact ownership marker.
      if (/^HM_OFFLINE_READER_[0-9]+_[0-9]+$/.test(name)) {
        const marker = `${this.rootDir()}/${name}/.venera-usability`;
        try { if (fs.accessSync(marker) && fs.readTextSync(marker) === name) { continue; } } catch (error) {}
      }
      const comic = this.buildComic(name);
      // A task placeholder, empty folder or metadata-only orphan is not yet a
      // readable comic. Keep every actual local comic; never delete directories.
      if (comic.cover.length > 0) { comics.push(comic); }
    }
    return new Res<Comic[]>(comics, undefined, comics.length > 0 ? 1 : 0);
  }

  private async searchLocal(keyword: string, page: number): Promise<Res<Comic[]>> {
    const all = await this.loadAll(page);
    const list = all.dataOrNull ?? [];
    const trimmed = keyword.trim().toLowerCase();
    if (trimmed.length === 0) {
      return new Res<Comic[]>(list);
    }
    const filtered: Comic[] = list.filter((item: Comic) => item.title.toLowerCase().includes(trimmed));
    return new Res<Comic[]>(filtered);
  }

  private async loadInfo(id: string): Promise<Res<ComicDetails>> {
    this.ensureRoot();
    const dir = `${this.rootDir()}/${id}`;
    if (!fs.accessSync(dir)) {
      return Res.fail<ComicDetails>(`本地漫画不存在: ${id}`);
    }
    const details = new ComicDetails();
    details.sourceKey = this.key;
    details.comicId = id;
    details.title = this.displayTitle(id);
    details.cover = this.findCover(id);

    const chapters = new Map<string, string>();
    const chapterDirs = this.listDirectories(dir);
    if (chapterDirs.length > 0) {
      for (let i = 0; i < chapterDirs.length; i++) {
        chapters.set(chapterDirs[i], chapterDirs[i]);
      }
    } else {
      chapters.set('default', '正文');
    }
    details.chapters = ComicChapters.flatOf(chapters);
    return new Res<ComicDetails>(details);
  }

  private async loadPages(id: string, ep?: string): Promise<Res<string[]>> {
    const dir = `${this.rootDir()}/${id}`;
    const chapterDirs = this.listDirectories(dir);
    const target: string = chapterDirs.length > 0
      ? `${dir}/${ep ?? chapterDirs[0]}`
      : dir;
    const images = this.listImages(target);
    if (images.length === 0) {
      return Res.fail<string[]>(`该章节没有图片: ${target}`);
    }
    const urls: string[] = [];
    for (let i = 0; i < images.length; i++) {
      urls.push(`file://${target}/${images[i]}`);
    }
    return new Res<string[]>(urls);
  }
}
