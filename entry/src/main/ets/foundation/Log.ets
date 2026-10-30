import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const DOMAIN: number = 0x0001;
const APP_TAG: string = 'VenHM';

/** Operational warnings only. No per-page, reading-action or activity log file. */
export class Log {
  /** Upgrade cleanup of ONLY the old app-owned diagnostic files. Never creates
   * a new log directory, reads a file's contents or touches other sandbox data. */
  static configureFileLogging(filesDir: string): void {
    if (!filesDir.startsWith('/') || filesDir.includes('\\') ||
      filesDir.split('/').some((part: string) => part === '..' || part === '.')) { return; }
    const directory = `${filesDir}/logs`;
    try {
      if (!fs.accessSync(directory) || fs.lstatSync(directory).isSymbolicLink() ||
        !fs.statSync(directory).isDirectory()) { return; }
      for (const name of fs.listFileSync(directory)) {
        if (!/^app-dev-\d{4}-\d{2}-\d{2}[.]log$/.test(name)) { continue; }
        const target = `${directory}/${name}`;
        if (fs.lstatSync(target).isSymbolicLink() || !fs.statSync(target).isFile()) { continue; }
        fs.unlinkSync(target);
      }
    } catch (error) {
      hilog.warn(DOMAIN, APP_TAG, 'Old diagnostic log cleanup unavailable');
    }
  }

  /** Deliberately disabled: diagnostic trace events must not track user actions. */
  static audit(traceId: string, stage: string, message: string): void {}
  static debug(tag: string, msg: string): void {}
  static info(tag: string, msg: string): void {}

  /** Compatibility with retained offline diagnostics; no files are produced. */
  static isTracePersisted(traceId: string): boolean { return false; }

  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, APP_TAG, '[%{public}s] %{public}s', tag, msg);
  }
  static error(tag: string, msg: string): void {
    hilog.error(DOMAIN, APP_TAG, '[%{public}s] %{public}s', tag, msg);
  }
}
