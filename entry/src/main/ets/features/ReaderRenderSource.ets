import { ReaderModes } from './ReaderModes';
import { ReaderSpread } from './ReaderSpreads';

/** Metadata only. Creating a chapter source never starts image hooks, hashing or decoding. */
export class ReaderRenderItem {
  key: string = '';
  url: string = '';
  display: number = 0;
  actual: number = 0;
  generation: number = 0;
  spread: ReaderSpread = new ReaderSpread();
}

/**
 * API 21 LazyForEach source. Keep the source and unchanged records alive across
 * counter updates / rotation; only a changed chapter or grouping notifies ArkUI.
 * No reusable image nodes: each key owns one canonical source image/spread.
 */
export class ReaderRenderSource implements IDataSource {
  private items: ReaderRenderItem[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number { return this.items.length; }
  getData(index: number): ReaderRenderItem { return this.items[index]; }

  private replace(items: ReaderRenderItem[]): void {
    let changed = items.length !== this.items.length;
    for (let index = 0; index < items.length; index++) {
      const old = this.items[index];
      const next = items[index];
      if (old !== undefined && old.key === next.key && old.url === next.url &&
        old.generation === next.generation) {
        items[index] = old;
      } else { changed = true; }
    }
    if (!changed) { return; }
    this.items = items;
    for (const listener of this.listeners) { listener.onDataReloaded(); }
  }

  setFlow(scope: string, images: string[], mode: string, generation: number): void {
    const items: ReaderRenderItem[] = [];
    for (let display = 0; display < images.length; display++) {
      const actual = ReaderModes.toActualIndex(mode, display, images.length);
      const item = new ReaderRenderItem();
      item.key = `${scope}:image:${actual}`;
      item.url = images[actual];
      item.display = display;
      item.actual = actual;
      item.generation = generation;
      items.push(item);
    }
    this.replace(items);
  }

  setSpreads(scope: string, spreads: ReaderSpread[], generation: number): void {
    const items: ReaderRenderItem[] = [];
    for (let display = 0; display < spreads.length; display++) {
      const spread = spreads[display];
      const item = new ReaderRenderItem();
      // Include ordered source membership, not zoomReset/currentPage/URL hashes.
      item.key = `${scope}:spread:${spread.imageIndices.join(',')}`;
      item.display = display;
      item.actual = spread.start;
      item.generation = generation;
      item.spread = spread;
      items.push(item);
    }
    this.replace(items);
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const index = this.listeners.indexOf(listener);
    if (index >= 0) { this.listeners.splice(index, 1); }
  }
}
