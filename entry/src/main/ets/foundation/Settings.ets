import { preferences } from '@kit.ArkData';
import { AppContext } from './AppContext';
import { Log } from './Log';

/**
 * Application settings store.
 *
 * Dart original: lib/foundation/appdata.dart (`Appdata.settings`, ~100 keys,
 * persisted to appdata.json). ArkTS uses @ohos.data.preferences, which gives
 * synchronous reads plus asynchronous flush - the same shape the ported UI needs.
 */
export class Settings {
  private static store: preferences.Preferences | undefined = undefined;
  private static readonly STORE_NAME: string = 'venera_hm_settings';

  static async init(): Promise<void> {
    if (Settings.store !== undefined) {
      return;
    }
    Settings.store = await preferences.getPreferences(AppContext.context, Settings.STORE_NAME);
    Log.info('Settings', 'preferences opened');
  }

  private static require(): preferences.Preferences {
    const store = Settings.store;
    if (store === undefined) {
      throw new Error('Settings.init() has not been called');
    }
    return store;
  }

  static getString(key: string, defaultValue: string): string {
    const value = Settings.require().getSync(key, defaultValue);
    return typeof value === 'string' ? value as string : defaultValue;
  }

  static getInt(key: string, defaultValue: number): number {
    const value = Settings.require().getSync(key, defaultValue);
    return typeof value === 'number' ? Math.trunc(value as number) : defaultValue;
  }

  static getBool(key: string, defaultValue: boolean): boolean {
    const value = Settings.require().getSync(key, defaultValue);
    return typeof value === 'boolean' ? value as boolean : defaultValue;
  }

  static async setString(key: string, value: string): Promise<void> {
    const store = Settings.require();
    await store.put(key, value);
    await store.flush();
  }

  static async setInt(key: string, value: number): Promise<void> {
    const store = Settings.require();
    await store.put(key, value);
    await store.flush();
  }

  static async setBool(key: string, value: boolean): Promise<void> {
    const store = Settings.require();
    await store.put(key, value);
    await store.flush();
  }

  static async remove(key: string): Promise<void> {
    const store = Settings.require();
    await store.delete(key);
    await store.flush();
  }

  // ---- well-known keys (subset of the Dart key set) ----

  static get readerMode(): string {
    return Settings.getString('readerMode', 'galleryRightToLeft');
  }

  static set readerMode(value: string) {
    Settings.setString('readerMode', value);
  }

  static get imageCacheLimitMb(): number {
    return Settings.getInt('imageCacheLimitMb', 512);
  }

  /**
   * Deep source self-test sampling (SOURCE_ACCEPTANCE.md L2/L3 depth: every
   * explore page, every category part, 2 keywords x 2 search pages, chapter
   * first/middle/last and three decoded images per chapter). Off by default:
   * one deep pass costs roughly ten image downloads per source.
   */
  static get sourceSelfTestDeep(): boolean {
    return Settings.getBool('sourceSelfTestDeep', false);
  }

  static set sourceSelfTestDeep(value: boolean) {
    Settings.setBool('sourceSelfTestDeep', value);
  }
}
