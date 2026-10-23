import { Settings } from './Settings';
import { ReaderModes } from '../features/ReaderModes';

export type ReaderSettingValue = string | number | boolean;
export type ReaderSettingScope = 'global' | 'device' | 'comic';

/** Implemented settings only; names/defaults match fixed upstream appdata.dart. */
export class ReaderOptions {
  readerMode: string = 'waterfallTopToBottom';
  readerScreenPicNumberForPortrait: number = 1;
  readerScreenPicNumberForLandscape: number = 1;
  showSingleImageOnFirstPage: boolean = false;
  splitDualPage: boolean = false;
  splitDualPageInvert: boolean = false;
  readerSideMargin: number = 0;
  autoPageTurningInterval: number = 5;
  autoReadingAcrossChapters: boolean = true;
  enableTapToTurnPages: boolean = true;
  reverseTapToTurnPages: boolean = false;
  enableDoubleTapToZoom: boolean = true;
  enablePageAnimation: boolean = true;
  enableTurnPageByVolumeKey: boolean = true;
  readerBrightnessEnabled: boolean = false;
  readerBrightness: number = 50;
  showPageNumberInReader: boolean = true;
  enableClockAndBatteryInfoInReader: boolean = true;
  limitImageWidth: boolean = true;
  longPressAction: string = 'zoom';
  longPressZoomPosition: string = 'press';
  autoScrollStyle: string = 'smooth';
  autoScrollSpeed: number = 80;
  autoScrollFrequency: number = 2;
  autoScrollDistance: number = 40;
  /** HM region customization; upstream's fixed 30% remains the default. */
  tapRegionPercent: number = 30;
  centerTapAction: string = 'none';
}
export class ReaderProfile {
  enabled: boolean = false;
  values: Record<string, ReaderSettingValue> = {};
}
export class ReaderSettingsDocument {
  version: number = 1;
  deviceKey: string = '';
  global: Record<string, ReaderSettingValue> = {};
  devices: Record<string, ReaderProfile> = {};
  comics: Record<string, ReaderProfile> = {};
}
export class ReaderSettings {
  private static readonly key: string = 'readerSettingsV1';
  private static state: ReaderSettingsDocument | undefined = undefined;
  private static tail: Promise<void> = Promise.resolve();
  private static readonly boolKeys: string[] = ['showSingleImageOnFirstPage', 'splitDualPage',
    'splitDualPageInvert', 'autoReadingAcrossChapters', 'enableTapToTurnPages', 'reverseTapToTurnPages',
    'enableDoubleTapToZoom', 'enablePageAnimation', 'enableTurnPageByVolumeKey', 'readerBrightnessEnabled',
    'showPageNumberInReader', 'enableClockAndBatteryInfoInReader', 'limitImageWidth', 'enableLongPressToZoom'];
  private static readonly numberNames: string[] = ['readerBrightness', 'autoScrollSpeed', 'autoScrollFrequency',
    'autoScrollDistance', 'tapRegionPercent'];
  private static readonly numberDefaults: number[] = [50, 80, 2, 40, 30];
  private static readonly stringNames: string[] = ['longPressAction', 'longPressZoomPosition', 'autoScrollStyle', 'centerTapAction'];
  private static readonly stringDefaults: string[] = ['zoom', 'press', 'smooth', 'none'];

  private static primitive(value: Object): ReaderSettingValue {
    if (typeof value === 'string' || typeof value === 'boolean') { return value; }
    if (typeof value === 'number' && Number.isFinite(value)) { return value; }
    throw new Error('阅读设置记录包含无效值；未重置用户设置');
  }
  private static values(value: Object): Record<string, ReaderSettingValue> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('阅读设置记录格式错误；未重置用户设置');
    }
    const record = value as Record<string, Object>;
    const result: Record<string, ReaderSettingValue> = {};
    for (const name of Object.keys(record)) {
      if (name === '__proto__' || name === 'constructor' || name === 'prototype') { throw new Error('阅读设置键无效；未改写用户设置'); }
      result[name] = ReaderSettings.primitive(record[name]);
    }
    return result;
  }
  private static profiles(value: Object): Record<string, ReaderProfile> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) {
      throw new Error('阅读设置分组格式错误；未重置用户设置');
    }
    const input = value as Record<string, Object>;
    const result: Record<string, ReaderProfile> = {};
    for (const name of Object.keys(input)) {
      if (name === '__proto__' || name === 'constructor' || name === 'prototype') { throw new Error('阅读档案身份键无效'); }
      const raw = input[name];
      if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) { throw new Error('阅读设置档案错误'); }
      const profile = raw as Record<string, Object>;
      if (typeof profile['enabled'] !== 'boolean') { throw new Error('阅读设置档案开关错误'); }
      const item = new ReaderProfile(); item.enabled = profile['enabled'] as boolean;
      item.values = ReaderSettings.values(profile['values']); result[name] = item;
    }
    return result;
  }
  private static parse(text: string): ReaderSettingsDocument {
    const record = JSON.parse(text) as Record<string, Object>;
    if (record === null || typeof record !== 'object' || Array.isArray(record) || record['version'] !== 1 ||
      typeof record['deviceKey'] !== 'string' || (record['deviceKey'] as string).length === 0) {
      throw new Error('阅读设置版本或设备标识无效；未重置用户设置');
    }
    const result = new ReaderSettingsDocument(); result.deviceKey = record['deviceKey'] as string;
    result.global = ReaderSettings.values(record['global']); result.devices = ReaderSettings.profiles(record['devices']);
    result.comics = ReaderSettings.profiles(record['comics']); return result;
  }
  private static load(): ReaderSettingsDocument {
    if (ReaderSettings.state !== undefined) { return ReaderSettings.state; }
    const text = Settings.getString(ReaderSettings.key, '');
    if (text.length > 0) { ReaderSettings.state = ReaderSettings.parse(text); }
    else {
      const result = new ReaderSettingsDocument();
      // Local, random preference identity; never reads a hardware ID or credentials.
      result.deviceKey = `reader-local-${Date.now()}-${Math.floor(Math.random() * 1000000000)}`;
      ReaderSettings.state = result;
    }
    return ReaderSettings.state;
  }
  private static comicKey(comicId: string, sourceKey: string): string {
    if (comicId.length === 0 || sourceKey.length === 0) { throw new Error('本漫画阅读设置缺少源或漫画身份'); }
    return `${encodeURIComponent(sourceKey)}:${encodeURIComponent(comicId)}`;
  }
  private static validate(name: string, value: ReaderSettingValue): ReaderSettingValue {
    if (name === 'readerMode' || name === 'readerModeOverride') {
      if (typeof value !== 'string' || (value !== 'default' && ReaderModes.normalize(value) !== value)) {
        throw new Error('阅读模式无效');
      }
      if (name === 'readerMode' && value === 'default') { throw new Error('全局阅读模式不能为继承'); }
      return value;
    }
    if (ReaderSettings.boolKeys.includes(name)) {
      if (typeof value !== 'boolean') { throw new Error('阅读设置必须是开关值'); }
      return value;
    }
    if (ReaderSettings.stringNames.includes(name)) {
      const choices: Record<string, string[]> = { 'longPressAction': ['zoom', 'autoReading', 'menu', 'none'],
        'longPressZoomPosition': ['press', 'center'], 'autoScrollStyle': ['smooth', 'stepped'],
        'centerTapAction': ['none', 'toolbar'] };
      if (typeof value !== 'string' || !choices[name].includes(value)) { throw new Error('阅读设置选项无效'); }
      return value;
    }
    let min: number = 0; let max: number = 0;
    if (name === 'readerScreenPicNumberForPortrait' || name === 'readerScreenPicNumberForLandscape') { min = 1; max = 5; }
    else if (name === 'readerSideMargin') { min = 0; max = 30; }
    else if (name === 'autoPageTurningInterval') { min = 1; max = 20; }
    else if (name === 'readerBrightness') { min = 20; max = 100; }
    else if (name === 'autoScrollSpeed') { min = 10; max = 1000; }
    else if (name === 'autoScrollFrequency') { min = 1; max = 10; }
    else if (name === 'autoScrollDistance') { min = 10; max = 500; }
    else if (name === 'tapRegionPercent') { min = 10; max = 45; }
    else { throw new Error('未实现的阅读设置；拒绝保存无效开关'); }
    if (typeof value !== 'number' || !Number.isFinite(value) || Math.floor(value) !== value || value < min || value > max) {
      throw new Error(`阅读设置范围无效：${name}`);
    }
    return value;
  }
  private static raw(name: string, comicId: string, sourceKey: string, includeDevice: boolean = true): ReaderSettingValue | undefined {
    const state = ReaderSettings.load();
    const comic = comicId.length > 0 && sourceKey.length > 0 ? state.comics[ReaderSettings.comicKey(comicId, sourceKey)] : undefined;
    if (comic !== undefined && comic.enabled && comic.values[name] !== undefined) { return comic.values[name]; }
    const device = state.devices[state.deviceKey];
    if (includeDevice && device !== undefined && device.enabled && device.values[name] !== undefined) { return device.values[name]; }
    return state.global[name];
  }
  private static boolean(name: string, fallback: boolean, comicId: string, sourceKey: string, includeDevice: boolean): boolean {
    const value = ReaderSettings.raw(name, comicId, sourceKey, includeDevice);
    if (value === undefined) { return Settings.getBool(name, fallback); }
    return ReaderSettings.validate(name, value) as boolean;
  }
  private static integer(name: string, fallback: number, comicId: string, sourceKey: string, includeDevice: boolean): number {
    const value = ReaderSettings.raw(name, comicId, sourceKey, includeDevice);
    return ReaderSettings.validate(name, value ?? Settings.getInt(name, fallback)) as number;
  }
  private static text(name: string, fallback: string, comicId: string, sourceKey: string, includeDevice: boolean): string {
    return ReaderSettings.validate(name, ReaderSettings.raw(name, comicId, sourceKey, includeDevice) ?? Settings.getString(name, fallback)) as string;
  }
  static resolve(comicId: string, sourceKey: string): ReaderOptions {
    return ReaderSettings.resolveForScope('comic', comicId, sourceKey);
  }
  static resolveForScope(scope: ReaderSettingScope, comicId: string, sourceKey: string): ReaderOptions {
    if (scope !== 'comic') { comicId = ''; sourceKey = ''; }
    const includeDevice: boolean = scope !== 'global';
    const result = new ReaderOptions();
    const state = ReaderSettings.load();
    let mode = ReaderSettings.raw('readerMode', comicId, sourceKey, includeDevice) ?? Settings.getString('readerMode', result.readerMode);
    if (comicId.length > 0 && sourceKey.length > 0) {
      const comic = state.comics[ReaderSettings.comicKey(comicId, sourceKey)];
      // Upstream comic mode override is independent of the other-settings switch.
      const override = comic?.values['readerModeOverride'];
      if (override !== undefined) {
        mode = override === 'default'
          ? ReaderSettings.raw('readerMode', '', '') ?? Settings.getString('readerMode', result.readerMode)
          : override;
      }
    }
    result.readerMode = ReaderSettings.validate('readerMode', mode) as string;
    result.readerScreenPicNumberForPortrait = ReaderSettings.integer('readerScreenPicNumberForPortrait', 1, comicId, sourceKey, includeDevice);
    result.readerScreenPicNumberForLandscape = ReaderSettings.integer('readerScreenPicNumberForLandscape', 1, comicId, sourceKey, includeDevice);
    result.showSingleImageOnFirstPage = ReaderSettings.boolean('showSingleImageOnFirstPage', false, comicId, sourceKey, includeDevice);
    result.splitDualPage = ReaderSettings.boolean('splitDualPage', false, comicId, sourceKey, includeDevice);
    result.splitDualPageInvert = ReaderSettings.boolean('splitDualPageInvert', false, comicId, sourceKey, includeDevice);
    result.readerSideMargin = ReaderSettings.integer('readerSideMargin', 0, comicId, sourceKey, includeDevice);
    // Earlier HM exposed a different interval key; preserve an explicitly saved value.
    const legacy = Settings.getInt('autoReadIntervalSeconds', -1);
    const interval = ReaderSettings.raw('autoPageTurningInterval', comicId, sourceKey, includeDevice);
    if (interval === undefined && legacy >= 1 && legacy <= 60) {
      result.autoPageTurningInterval = legacy;
    } else { result.autoPageTurningInterval = ReaderSettings.integer('autoPageTurningInterval', 5, comicId, sourceKey, includeDevice); }
    result.autoReadingAcrossChapters = ReaderSettings.boolean('autoReadingAcrossChapters', true, comicId, sourceKey, includeDevice);
    result.enableTapToTurnPages = ReaderSettings.boolean('enableTapToTurnPages', true, comicId, sourceKey, includeDevice);
    result.reverseTapToTurnPages = ReaderSettings.boolean('reverseTapToTurnPages', false, comicId, sourceKey, includeDevice);
    result.enableDoubleTapToZoom = ReaderSettings.boolean('enableDoubleTapToZoom', true, comicId, sourceKey, includeDevice);
    result.enablePageAnimation = ReaderSettings.boolean('enablePageAnimation', true, comicId, sourceKey, includeDevice);
    result.enableTurnPageByVolumeKey = ReaderSettings.boolean('enableTurnPageByVolumeKey', true, comicId, sourceKey, includeDevice);
    result.readerBrightnessEnabled = ReaderSettings.boolean('readerBrightnessEnabled', false, comicId, sourceKey, includeDevice);
    result.showPageNumberInReader = ReaderSettings.boolean('showPageNumberInReader', true, comicId, sourceKey, includeDevice);
    result.enableClockAndBatteryInfoInReader = ReaderSettings.boolean('enableClockAndBatteryInfoInReader', true, comicId, sourceKey, includeDevice);
    result.limitImageWidth = ReaderSettings.boolean('limitImageWidth', true, comicId, sourceKey, includeDevice);
    result.readerBrightness = ReaderSettings.integer('readerBrightness', 50, comicId, sourceKey, includeDevice);
    result.autoScrollSpeed = ReaderSettings.integer('autoScrollSpeed', 80, comicId, sourceKey, includeDevice);
    result.autoScrollFrequency = ReaderSettings.integer('autoScrollFrequency', 2, comicId, sourceKey, includeDevice);
    result.autoScrollDistance = ReaderSettings.integer('autoScrollDistance', 40, comicId, sourceKey, includeDevice);
    result.tapRegionPercent = ReaderSettings.integer('tapRegionPercent', 30, comicId, sourceKey, includeDevice);
    const action = ReaderSettings.raw('longPressAction', comicId, sourceKey, includeDevice);
    result.longPressAction = ReaderSettings.validate('longPressAction', action ?? Settings.getString('longPressAction',
      ReaderSettings.boolean('enableLongPressToZoom', true, comicId, sourceKey, includeDevice) ? 'zoom' : 'none')) as string;
    result.longPressZoomPosition = ReaderSettings.text('longPressZoomPosition', 'press', comicId, sourceKey, includeDevice);
    result.autoScrollStyle = ReaderSettings.text('autoScrollStyle', 'smooth', comicId, sourceKey, includeDevice);
    result.centerTapAction = ReaderSettings.text('centerTapAction', 'none', comicId, sourceKey, includeDevice);
    return result;
  }
  static enabled(scope: ReaderSettingScope, comicId: string = '', sourceKey: string = ''): boolean {
    if (scope === 'global') { return true; }
    const state = ReaderSettings.load();
    const profile = scope === 'device' ? state.devices[state.deviceKey] : state.comics[ReaderSettings.comicKey(comicId, sourceKey)];
    return profile?.enabled === true;
  }
  private static async change(mutate: (state: ReaderSettingsDocument) => void): Promise<void> {
    const operation = ReaderSettings.tail.then(async (): Promise<void> => {
      const before = ReaderSettings.load(); const previous = JSON.stringify(before);
      const next = ReaderSettings.parse(previous); mutate(next);
      try { await Settings.setString(ReaderSettings.key, JSON.stringify(next)); }
      catch (error) {
        // Keep the last confirmed in-memory profile; best effort restores a put
        // that may have succeeded before flush failed. Never report 'saved'.
        try { await Settings.setString(ReaderSettings.key, previous); } catch (rollbackError) { /* surfaced by original failure */ }
        throw new Error('阅读设置未确认保存；保留最后确认值，请检查存储');
      }
      ReaderSettings.state = next;
    });
    ReaderSettings.tail = operation.catch((): void => {}); return await operation;
  }
  private static profile(state: ReaderSettingsDocument, scope: ReaderSettingScope,
    comicId: string, sourceKey: string): ReaderProfile {
    const map = scope === 'device' ? state.devices : state.comics;
    const key = scope === 'device' ? state.deviceKey : ReaderSettings.comicKey(comicId, sourceKey);
    let profile = map[key];
    if (profile === undefined) { profile = new ReaderProfile(); map[key] = profile; }
    return profile;
  }
  static async set(scope: ReaderSettingScope, comicId: string, sourceKey: string, name: string, value: ReaderSettingValue): Promise<void> {
    const storedName = scope === 'comic' && name === 'readerMode' ? 'readerModeOverride' : name;
    const checked = ReaderSettings.validate(storedName, value);
    await ReaderSettings.change((state: ReaderSettingsDocument): void => {
      if (scope === 'global') { state.global[storedName] = checked; }
      else { ReaderSettings.profile(state, scope, comicId, sourceKey).values[storedName] = checked; }
    });
  }
  static async setEnabled(scope: ReaderSettingScope, enabled: boolean, comicId: string = '', sourceKey: string = ''): Promise<void> {
    if (scope === 'global') { return; }
    await ReaderSettings.change((state: ReaderSettingsDocument): void => { ReaderSettings.profile(state, scope, comicId, sourceKey).enabled = enabled; });
  }
  private static withoutProfile(values: Record<string, ReaderProfile>, key: string): Record<string, ReaderProfile> {
    const result: Record<string, ReaderProfile> = {};
    for (const name of Object.keys(values)) { if (name !== key) { result[name] = values[name]; } }
    return result;
  }
  private static defaults(): Record<string, ReaderSettingValue> {
    const result: Record<string, ReaderSettingValue> = {};
    result['readerMode'] = 'waterfallTopToBottom';
    result['readerScreenPicNumberForPortrait'] = 1; result['readerScreenPicNumberForLandscape'] = 1;
    result['showSingleImageOnFirstPage'] = false; result['splitDualPage'] = false; result['splitDualPageInvert'] = false;
    result['readerSideMargin'] = 0; result['autoPageTurningInterval'] = 5; result['autoReadingAcrossChapters'] = true;
    result['enableTapToTurnPages'] = true; result['reverseTapToTurnPages'] = false;
    result['enableDoubleTapToZoom'] = true; result['enablePageAnimation'] = true;
    result['enableTurnPageByVolumeKey'] = true; result['readerBrightnessEnabled'] = false;
    result['showPageNumberInReader'] = true; result['enableClockAndBatteryInfoInReader'] = true;
    result['limitImageWidth'] = true;
    for (let i = 0; i < ReaderSettings.numberNames.length; i++) { result[ReaderSettings.numberNames[i]] = ReaderSettings.numberDefaults[i]; }
    for (let i = 0; i < ReaderSettings.stringNames.length; i++) { result[ReaderSettings.stringNames[i]] = ReaderSettings.stringDefaults[i]; }
    return result;
  }
  static async reset(scope: ReaderSettingScope, comicId: string = '', sourceKey: string = ''): Promise<void> {
    await ReaderSettings.change((state: ReaderSettingsDocument): void => {
      if (scope === 'global') { state.global = ReaderSettings.defaults(); }
      else if (scope === 'device') { state.devices = ReaderSettings.withoutProfile(state.devices, state.deviceKey); }
      else { state.comics = ReaderSettings.withoutProfile(state.comics, ReaderSettings.comicKey(comicId, sourceKey)); }
    });
  }
  static async setActive(comicId: string, sourceKey: string, name: string, value: ReaderSettingValue): Promise<void> {
    const checked = ReaderSettings.validate(name, value);
    await ReaderSettings.change((state: ReaderSettingsDocument): void => {
      // Resolve active scope INSIDE the ordered commit, after earlier enable/reset
      // operations have been confirmed. A queued enable must not redirect this
      // write to stale global state.
      const comic = comicId.length > 0 && sourceKey.length > 0 ? state.comics[ReaderSettings.comicKey(comicId, sourceKey)] : undefined;
      const override = comic?.values['readerModeOverride'];
      const useComic = comic?.enabled === true || (name === 'readerMode' && override !== undefined && override !== 'default');
      const device = state.devices[state.deviceKey];
      const scope: ReaderSettingScope = useComic ? 'comic' : device?.enabled === true ? 'device' : 'global';
      const storedName = scope === 'comic' && name === 'readerMode' ? 'readerModeOverride' : name;
      if (scope === 'global') { state.global[storedName] = checked; }
      else { ReaderSettings.profile(state, scope, comicId, sourceKey).values[storedName] = checked; }
    });
  }
}
