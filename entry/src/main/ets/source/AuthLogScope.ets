/** Auth-owned continuations may outlive their root call; keep their source text redacted. */
export class AuthLogScope {
  private static next: number = 1;
  private static readonly frames: Map<number, string> = new Map<number, string>();
  private static readonly sensitiveOwners: Set<string> = new Set<string>();
  static enter(trace: string): number {
    const id = AuthLogScope.next++;
    AuthLogScope.frames.set(id, trace);
    AuthLogScope.sensitiveOwners.add(trace);
    return id;
  }
  static leave(id: number): void { AuthLogScope.frames.delete(id); }
  static owns(trace: string): boolean {
    return AuthLogScope.sensitiveOwners.has(trace);
  }
  static current(): string | undefined {
    let latest: string | undefined = undefined;
    for (const trace of AuthLogScope.frames.values()) { latest = trace; }
    return latest;
  }
}
