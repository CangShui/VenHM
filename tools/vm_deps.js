'use strict';
// Canonical ArkTS dependency lists for VM harnesses. Keeping them in one place
// avoids every suite drifting when a production module gains a new import.
const fs = require('node:fs'), path = require('node:path');
const root = path.resolve(__dirname, '..');
const read = relative => fs.readFileSync(path.join(root, relative), 'utf8')
  .replace(/^import[\s\S]*?;\r?\n/gm, '').replace(/\bexport /g, '');

/** Everything JsComicSource.configure() touches while registering a source. */
const SOURCE_FILES = [
  'entry/src/main/ets/foundation/Extensions.ets',
  'entry/src/main/ets/foundation/Semver.ets',
  'entry/src/main/ets/model/Comic.ets',
  'entry/src/main/ets/model/Res.ets',
  'entry/src/main/ets/model/ComicDetails.ets',
  'entry/src/main/ets/model/BrowserLogin.ets',
  'entry/src/main/ets/features/SourceFailure.ets',
  'entry/src/main/ets/source/AuthLogScope.ets',
  'entry/src/main/ets/source/DetailsCapabilities.ets',
  'entry/src/main/ets/source/JsDetailsAdapter.ets',
  'entry/src/main/ets/source/RankingData.ets',
  'entry/src/main/ets/source/JsRankingAdapter.ets',
  'entry/src/main/ets/source/JsFavoritesAdapter.ets',
  'entry/src/main/ets/source/ComicSource.ets',
  'entry/src/main/ets/source/JsComicSource.ets'
];

/** Details page plus the feature helpers it now imports. */
const DETAILS_FILES = [
  'entry/src/main/ets/foundation/Extensions.ets',
  'entry/src/main/ets/model/Comic.ets',
  'entry/src/main/ets/model/Res.ets',
  'entry/src/main/ets/model/ComicDetails.ets',
  'entry/src/main/ets/model/ComicType.ets',
  'entry/src/main/ets/features/SourceFailure.ets',
  'entry/src/main/ets/features/ReaderImageLayout.ets',
  'entry/src/main/ets/source/DetailsCapabilities.ets',
  'entry/src/main/ets/source/JsDetailsAdapter.ets',
  'entry/src/main/ets/features/DetailsMedia.ets',
  'entry/src/main/ets/features/DetailsComments.ets'
];

/** Reader-only helpers the page now depends on. */
const READER_FILES = [
  'entry/src/main/ets/features/ReaderVolumeKeys.ets'
];

/**
 * Inert stand-ins for suites that only exercise chapter/tag/route logic.
 * DetailsMedia/DetailsMediaImage and the ShareKit/UTD/Ability facades are not
 * under test there; their real behaviour is covered by tools/details_cases.js.
 */
const DETAILS_STUBS = `
class DetailsMedia { constructor() {} get thumbnails() { return []; } get comments() { return []; } }
class DetailsMediaImage { constructor() {} }
class CollectionActionsPanel {}
class DetailsSharePayload { constructor() { this.text = ''; this.uri = ''; } }
const systemShare = { SharedData: class {}, ShareController: class { static async show() {} } };
const uniformTypeDescriptor = { UniformDataType: { PLAIN_TEXT: 'text/plain', PNG: 'image/png' } };
const common = { UIAbilityContext: class {} };
`;

function join(files) { return files.map(read).join('\n'); }

module.exports = { SOURCE_FILES, DETAILS_FILES, READER_FILES, DETAILS_STUBS, read, join };
