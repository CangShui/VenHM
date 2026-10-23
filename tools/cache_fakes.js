'use strict';
// Shared ArkTS runtime fakes for cache tests: @ohos.file.fs over the REAL temp
// filesystem, and the @kit.ArkTS util text codecs. Keeping one copy means the
// cache suites cannot drift into testing different filesystem semantics.
const fsNode = require('node:fs');
const path = require('node:path');

/** fileIo facade backed by the real filesystem (same paths the app uses). */
function fakeFs() {
  const OM = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 };
  return {
    OpenMode: OM,
    accessSync: p => { try { fsNode.accessSync(p); return true; } catch (error) { return false; } },
    mkdirSync: (p, recursive) => { fsNode.mkdirSync(p, { recursive: recursive === true }); },
    openSync: (p, mode) => {
      if ((mode & OM.CREATE) !== 0) {
        fsNode.mkdirSync(path.dirname(p), { recursive: true });
        fsNode.closeSync(fsNode.openSync(p, (mode & OM.TRUNC) !== 0 ? 'w' : 'a'));
      }
      return { fd: fsNode.openSync(p, (mode & OM.WRITE_ONLY) !== 0 ? 'r+' : 'r') };
    },
    closeSync: handle => { try { fsNode.closeSync(handle.fd); } catch (error) { /* already closed */ } },
    readSync: (fd, buffer) => fsNode.readSync(fd, Buffer.from(buffer), 0, buffer.byteLength, 0),
    writeSync: (fd, data) => {
      if (typeof data === 'string') {
        fsNode.writeSync(fd, data, 0, 'utf8');
        return Buffer.byteLength(data);
      }
      const view = Buffer.from(data);
      fsNode.writeSync(fd, view, 0, view.length, 0);
      return view.length;
    },
    statSync: p => {
      const stat = fsNode.statSync(p);
      return {
        size: stat.size,
        mtime: stat.mtimeMs,
        isFile: () => stat.isFile(),
        isDirectory: () => stat.isDirectory()
      };
    },
    unlinkSync: p => fsNode.unlinkSync(p),
    renameSync: (from, to) => fsNode.renameSync(from, to),
    listFileSync: p => fsNode.readdirSync(p),
    readTextSync: p => fsNode.readFileSync(p, 'utf8')
  };
}

function utilFake() {
  return {
    TextEncoder: class { encodeInto(value) { return new TextEncoder().encode(value); } },
    TextDecoder: {
      create: charset => ({ decodeToString: value => new TextDecoder(charset).decode(value) })
    }
  };
}

module.exports = { fakeFs, utilFake };
