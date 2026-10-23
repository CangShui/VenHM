/** Credential-bearing values: never serialize to development logs or route parameters. */
export class BrowserCookie {
  name: string = '';
  value: string = '';
  domain: string = '';
  path: string = '/';
  hostOnly: boolean = true;
  secure: boolean = false;
  httpOnly: boolean = false;
  expiresAt: number = 0;
  sameSite: string = '';
  metadataComplete: boolean = true;
}

export class BrowserLoginSnapshot {
  url: string = '';
  title: string = '';
  cookies: BrowserCookie[] = [];
  localStorage: Record<string, Object> = {};
  cookieMetadataComplete: boolean = true;
}
