/**
 * Res<T> - result wrapper carrying data, optional sub data and an error message.
 *
 * Dart original: lib/foundation/res.dart. Every comic source callback returns
 * Res<T>; `subData` carries pagination info (maxPage / next) or side data.
 */
export class Res<T> {
  private readonly dataValue: T | undefined;
  readonly errorMessage: string | undefined;
  readonly subData: Object | undefined;

  constructor(data: T | undefined, errorMessage?: string, subData?: Object) {
    this.dataValue = data;
    this.errorMessage = errorMessage;
    this.subData = subData;
  }

  static ok<T>(data: T, subData?: Object): Res<T> {
    return new Res<T>(data, undefined, subData);
  }

  static fail<T>(message: string, subData?: Object): Res<T> {
    return new Res<T>(undefined, message, subData);
  }

  get error(): boolean {
    return this.errorMessage !== undefined;
  }

  get success(): boolean {
    return this.errorMessage === undefined;
  }

  get data(): T {
    const value = this.dataValue;
    if (value === undefined) {
      throw new Error(this.errorMessage ?? 'Res has no data');
    }
    return value;
  }

  get dataOrNull(): T | undefined {
    return this.dataValue;
  }

  /** maxPage / next page token when subData is a number or string. */
  get subDataString(): string | undefined {
    const sub = this.subData;
    if (sub === undefined || sub === null) {
      return undefined;
    }
    return String(sub);
  }
}
