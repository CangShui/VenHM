import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';

const DOMAIN: number = 0x0001;
const APP_TAG: string = 'VeneraHM';

/** Thin wrapper over hilog so every module logs through one place. */
export class Log {
  private static directory: string = '';

  /** Use the application sandbox, never a public directory or console-only log. */
  static configureFileLogging(filesDir: string): void {
    const directory = `${filesDir}/logs`;
    try {
      if (!fs.accessSync(directory)) {
        fs.mkdirSync(directory, true);
      }
      Log.directory = directory;
    } catch (error) {
      hilog.error(DOMAIN, APP_TAG, 'Cannot initialize file logs: %{public}s', String(error));
    }
  }

  private static persist(level: string, tag: string, msg: string): void {
    if (Log.directory.length === 0) {
      return;
    }
    try {
      const now = new Date();
      const day = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
      const file = fs.openSync(`${Log.directory}/app-dev-${day}.log`,
        fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.APPEND);
      try {
        fs.writeSync(file.fd, `${now.toISOString()} ${level} [${tag}] ${msg}\n`);
      } finally {
        fs.closeSync(file);
      }
    } catch (error) {
      // Logging must never crash the operation it is explaining.
      hilog.error(DOMAIN, APP_TAG, 'File log write failed: %{public}s', String(error));
    }
  }

  static audit(traceId: string, stage: string, message: string): void {
    Log.info('Audit', `TraceID=${traceId} [${stage}] ${message}`);
  }

  /** Device diagnostics can check actual disk contents, not just HiLog output. */
  static isTracePersisted(traceId: string): boolean {
    if (Log.directory.length === 0) {
      return false;
    }
    try {
      const now = new Date();
      const day = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
      return fs.readTextSync(`${Log.directory}/app-dev-${day}.log`).includes(`TraceID=${traceId} `);
    } catch (error) {
      Log.warn('Log', `Cannot verify audit file: ${error}`);
      return false;
    }
  }

  static debug(tag: string, msg: string): void {
    hilog.debug(DOMAIN, APP_TAG, '[%{public}s] %{public}s', tag, msg);
    Log.persist('DEBUG', tag, msg);
  }

  static info(tag: string, msg: string): void {
    hilog.info(DOMAIN, APP_TAG, '[%{public}s] %{public}s', tag, msg);
    Log.persist('INFO', tag, msg);
  }

  static warn(tag: string, msg: string): void {
    hilog.warn(DOMAIN, APP_TAG, '[%{public}s] %{public}s', tag, msg);
    Log.persist('WARN', tag, msg);
  }

  static error(tag: string, msg: string): void {
    hilog.error(DOMAIN, APP_TAG, '[%{public}s] %{public}s', tag, msg);
    Log.persist('ERROR', tag, msg);
  }
}
