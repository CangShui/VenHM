import { ComicChapters } from '../model/Comic';
import { Log } from '../foundation/Log';

export class ChapterEntry {
  id: string = '';
  title: string = '';
  canonicalIndex: number = 0;
}
export class ChapterSection {
  name: string = '';
  entries: ChapterEntry[] = [];
}

/** Presentation order must not renumber persisted positions or mutate ComicChapters. */
export class ChapterNavigation {
  static sections(chapters: ComicChapters | undefined, reverse: boolean, trace: string): ChapterSection[] {
    const result: ChapterSection[] = [];
    const ids = chapters?.ids ?? [];
    const titles = chapters?.titles ?? [];
    const indices = new Map<string, number>();
    ids.forEach((id: string, index: number) => { indices.set(id, index); });
    const seen = new Set<string>();
    let aliases = 0;
    const names = chapters?.isGrouped ? chapters.groupNames : [''];
    for (const name of names) {
      const source = chapters?.isGrouped ? chapters.getGroup(name) : chapters?.allChapters ?? new Map<string, string>();
      const section = new ChapterSection(); section.name = name;
      source.forEach((title: string, id: string) => {
        const index = indices.get(id);
        if (index === undefined || seen.has(id)) { aliases++; return; }
        seen.add(id);
        const entry = new ChapterEntry(); entry.id = id; entry.title = titles[index] ?? title; entry.canonicalIndex = index;
        section.entries.push(entry);
      });
      if (reverse) { section.entries.reverse(); }
      if (section.entries.length > 0) { result.push(section); }
    }
    Log.audit(trace, '章节分组返回', `模型章节=${ids.length}；显示分组=${result.length}；唯一显示ID=${seen.size}；重复/不在模型ID=${aliases}；组内倒序=${reverse}；存储序号不变`);
    return result;
  }
}
