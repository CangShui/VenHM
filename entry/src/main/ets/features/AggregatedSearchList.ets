import { AggregatedSearchGroup } from './AggregatedSearchSession';
import { Comic } from '../model/Comic';

/** Immutable UI snapshots; changing source A never remounts source B's cards. */
export class AggregatedSearchList implements IDataSource {
  private rows: AggregatedSearchGroup[] = [];
  private signatures: string[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.rows.length; }
  getData(index: number): AggregatedSearchGroup { return this.rows[index]; }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) { this.listeners.push(listener); }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    this.listeners = this.listeners.filter((entry: DataChangeListener) => entry !== listener);
  }
  update(groups: AggregatedSearchGroup[]): AggregatedSearchGroup[] {
    const reordered = groups.length !== this.rows.length || groups.some((group: AggregatedSearchGroup, index: number) =>
      group.sourceKey !== this.rows[index].sourceKey);
    const signatures: string[] = [];
    const rows: AggregatedSearchGroup[] = [];
    const changed: number[] = [];
    for (let index = 0; index < groups.length; index++) {
      const group = groups[index];
      const signature = JSON.stringify([group.sourceName, group.status, group.error,
        group.results.map((comic: Comic) => `${comic.sourceKey}:${comic.id}:${comic.title}:${comic.cover}`)]);
      signatures.push(signature);
      if (!reordered && this.signatures[index] === signature) { rows.push(this.rows[index]); continue; }
      const snapshot = new AggregatedSearchGroup();
      snapshot.sourceKey = group.sourceKey; snapshot.sourceName = group.sourceName;
      snapshot.status = group.status; snapshot.error = group.error; snapshot.results = group.results.slice();
      snapshot.uiVersion = (this.rows[index]?.uiVersion ?? 0) + 1;
      rows.push(snapshot); changed.push(index);
    }
    this.rows = rows; this.signatures = signatures;
    if (reordered) { for (const listener of this.listeners) { listener.onDataReloaded(); } }
    else { for (const index of changed) { for (const listener of this.listeners) { listener.onDataChanged(index); } } }
    return this.rows.slice();
  }
}
