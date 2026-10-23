/*
 * HTML / CSS selector engine for VenHM.
 *
 * Why this exists: comic sources scrape web pages through the `HtmlDocument` /
 * `HtmlElement` / `HtmlNode` API defined in assets/init.js. Those classes reach
 * the host through `sendMessage({ method: 'html', function: ... })`. OHOS has no
 * equivalent of Dart's package:html, so the DOM lives here, in JavaScript,
 * inside QuickJS.
 *
 * This file is loaded after init.js and after sendmessage_shim.js, and wraps the
 * global `sendMessage` again: `html` messages are answered locally and never
 * reach the native side. init.js stays byte-identical to upstream.
 *
 * Handle model: every node of a document lives in one flat array in document
 * order, and a "key" handed to a script is simply that node's index. Elements
 * and non-elements therefore share one index space, which is what the
 * node_to_element / getNodes / getChildren actions expect.
 */
(() => {
  const innerSendMessage = globalThis.sendMessage;
  const documents = Object.create(null);
  let documentCounter = 0;
  let requestCounter = 0;

  // ------------------------------------------------------------------ parser

  const VOID_ELEMENTS = {
    area: 1, base: 1, br: 1, col: 1, embed: 1, hr: 1, img: 1, input: 1,
    link: 1, meta: 1, param: 1, source: 1, track: 1, wbr: 1
  };

  const RAW_TEXT_ELEMENTS = { script: 1, style: 1, textarea: 1, title: 1 };

  function findTagEnd(html, start) {
    let quote = '';
    for (let i = start + 1; i < html.length; i++) {
      const ch = html[i];
      if (quote) {
        if (ch === quote) {
          quote = '';
        }
      } else if (ch === '"' || ch === "'") {
        quote = ch;
      } else if (ch === '>') {
        return i;
      }
    }
    return -1;
  }

  const ATTRIBUTE_PATTERN =
    /([^\s=\/>]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+)))?/g;

  function parseStartTag(raw) {
    const nameMatch = /^([a-zA-Z][^\s\/>]*)/.exec(raw);
    if (!nameMatch) {
      return null;
    }
    const tag = nameMatch[1].toLowerCase();
    const attrs = Object.create(null);
    const rest = raw.substring(nameMatch[0].length);
    ATTRIBUTE_PATTERN.lastIndex = 0;
    let match = ATTRIBUTE_PATTERN.exec(rest);
    while (match) {
      const name = match[1].toLowerCase();
      if (name !== '/') {
        const value = match[2] !== undefined ? match[2]
          : (match[3] !== undefined ? match[3]
            : (match[4] !== undefined ? match[4] : ''));
        // HTML tokenization retains the FIRST attribute of a given ASCII-
        // case-insensitive name, including an empty first value. Last-wins
        // erased real WNACG title_sort/bodywrap classes on duplicate class tags.
        if (!Object.prototype.hasOwnProperty.call(attrs, name)) {
          attrs[name] = decodeEntities(value);
        }
      }
      match = ATTRIBUTE_PATTERN.exec(rest);
    }
    return {
      tag: tag,
      attrs: attrs,
      selfClosing: /\/\s*$/.test(raw)
    };
  }

  function decodeEntities(text) {
    if (text.indexOf('&') < 0) {
      return text;
    }
    const named = {
      amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", nbsp: '\u00a0',
      copy: '\u00a9', reg: '\u00ae', hellip: '\u2026', mdash: '\u2014',
      ndash: '\u2013', ldquo: '\u201c', rdquo: '\u201d', lsquo: '\u2018',
      rsquo: '\u2019', middot: '\u00b7', times: '\u00d7', laquo: '\u00ab',
      raquo: '\u00bb', deg: '\u00b0', bull: '\u2022'
    };
    return text.replace(/&(#(?:[xX][0-9a-fA-F]+|[0-9]+)|[a-zA-Z]+);/g, (whole, body) => {
      if (body[0] === '#') {
        const code = body[1] === 'x' || body[1] === 'X'
          ? parseInt(body.substring(2), 16)
          : parseInt(body.substring(1), 10);
        if (!Number.isFinite(code) || code === 0 || code > 0x10ffff ||
            (code >= 0xd800 && code <= 0xdfff)) {
          return '\ufffd';
        }
        return String.fromCodePoint(code);
      }
      const value = named[body.toLowerCase()];
      return value === undefined ? whole : value;
    });
  }

  function parseHtml(html) {
    const root = {
      type: 'document', tag: '#document', attrs: {}, children: [], parent: null
    };
    const stack = [root];
    let i = 0;
    const length = html.length;

    function appendText(text) {
      if (!text) {
        return;
      }
      const parent = stack[stack.length - 1];
      parent.children.push({
        type: 'text', tag: '#text',
        text: parent.tag === 'script' || parent.tag === 'style' ? text : decodeEntities(text),
        attrs: {}, children: [], parent: parent
      });
    }

    while (i < length) {
      const lt = html.indexOf('<', i);
      if (lt < 0) {
        appendText(html.substring(i));
        break;
      }
      if (lt > i) {
        appendText(html.substring(i, lt));
      }

      if (html.startsWith('<!--', lt)) {
        const close = html.indexOf('-->', lt + 4);
        const parent = stack[stack.length - 1];
        parent.children.push({
          type: 'comment', tag: '#comment',
          text: html.substring(lt + 4, close < 0 ? length : close),
          attrs: {}, children: [], parent: parent
        });
        i = close < 0 ? length : close + 3;
        continue;
      }

      if (html.startsWith('<!', lt) || html.startsWith('<?', lt)) {
        const close = html.indexOf('>', lt);
        i = close < 0 ? length : close + 1;
        continue;
      }

      if (html[lt + 1] === '/') {
        const close = html.indexOf('>', lt);
        const name = html.substring(lt + 2, close < 0 ? length : close)
          .trim().toLowerCase().split(/\s/)[0];
        for (let depth = stack.length - 1; depth > 0; depth--) {
          if (stack[depth].tag === name) {
            stack.length = depth;
            break;
          }
        }
        i = close < 0 ? length : close + 1;
        continue;
      }

      const end = findTagEnd(html, lt);
      if (end < 0) {
        appendText(html.substring(lt));
        break;
      }
      const parsed = parseStartTag(html.substring(lt + 1, end));
      if (parsed === null) {
        i = end + 1;
        continue;
      }

      const parent = stack[stack.length - 1];
      const node = {
        type: 'element', tag: parsed.tag, attrs: parsed.attrs,
        children: [], parent: parent
      };
      parent.children.push(node);

      const isVoid = parsed.selfClosing || VOID_ELEMENTS[parsed.tag] === 1;
      if (!isVoid) {
        stack.push(node);
        if (RAW_TEXT_ELEMENTS[parsed.tag] === 1) {
          // Consume raw text up to the matching close tag.
          const closeTag = '</' + parsed.tag;
          const closeIndex = html.toLowerCase().indexOf(closeTag, end + 1);
          const rawEnd = closeIndex < 0 ? length : closeIndex;
          const raw = html.substring(end + 1, rawEnd);
          if (raw) {
            node.children.push({
              type: 'text', tag: '#text', text: raw, attrs: {},
              children: [], parent: node
            });
          }
          i = closeIndex < 0 ? length : html.indexOf('>', closeIndex) + 1;
          stack.pop();
          continue;
        }
      }
      i = end + 1;
    }
    return root;
  }

  // --------------------------------------------------------- selector engine

  function parseSelector(selector) {
    // Returns an array of { parts: [{compound, combinator}] } - one per group.
    const groups = [];
    const groupTexts = splitTopLevel(selector, ',');
    for (let g = 0; g < groupTexts.length; g++) {
      const text = groupTexts[g].trim();
      if (!text) {
        continue;
      }
      const tokens = tokenizeCompound(text);
      if (tokens.length > 0) {
        groups.push(tokens);
      }
    }
    return groups;
  }

  function splitTopLevel(text, separator) {
    const out = [];
    let depth = 0;
    let current = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text[i];
      if (ch === '(' || ch === '[') {
        depth++;
      } else if (ch === ')' || ch === ']') {
        depth--;
      }
      if (ch === separator && depth === 0) {
        out.push(current);
        current = '';
      } else {
        current += ch;
      }
    }
    out.push(current);
    return out;
  }

  function tokenizeCompound(text) {
    // Produces [{ combinator, compound }] left to right.
    const tokens = [];
    let i = 0;
    let combinator = ' ';
    let buffer = '';
    let depth = 0;

    function flush() {
      const compound = buffer.trim();
      if (compound) {
        tokens.push({ combinator: tokens.length === 0 ? ' ' : combinator, compound: compound });
      }
      buffer = '';
    }

    while (i < text.length) {
      const ch = text[i];
      if (ch === '(' || ch === '[') {
        depth++;
        buffer += ch;
      } else if (ch === ')' || ch === ']') {
        depth--;
        buffer += ch;
      } else if (depth === 0 && (ch === '>' || ch === '+' || ch === '~')) {
        flush();
        combinator = ch;
      } else if (depth === 0 && /\s/.test(ch)) {
        // Whitespace AFTER an explicit operator must not turn it into a
        // descendant relation: "p > b" and "p>b" are the same selector.
        const hadCompound = buffer.trim().length > 0;
        flush();
        if (hadCompound) {
          combinator = ' ';
        }
        // skip run of whitespace
        while (i + 1 < text.length && /\s/.test(text[i + 1])) {
          i++;
        }
        // a combinator may follow the whitespace
        const next = text[i + 1];
        if (next === '>' || next === '+' || next === '~') {
          combinator = next;
          i++;
        }
      } else {
        buffer += ch;
      }
      i++;
    }
    flush();
    return tokens;
  }

  function matchCompound(node, compound) {
    if (node.type !== 'element') {
      return false;
    }
    const pattern = /([#.]?[A-Za-z0-9_\-*]+)|(\[[^\]]+\])|(:[a-zA-Z-]+(?:\([^)]*\))?)/g;
    let match = pattern.exec(compound);
    let sawAny = false;
    while (match) {
      sawAny = true;
      const token = match[0];
      if (token[0] === '#') {
        if ((node.attrs.id || '') !== token.substring(1)) {
          return false;
        }
      } else if (token[0] === '.') {
        const classes = (node.attrs.class || '').split(/\s+/);
        if (classes.indexOf(token.substring(1)) < 0) {
          return false;
        }
      } else if (token[0] === '[') {
        if (!matchAttribute(node, token.substring(1, token.length - 1))) {
          return false;
        }
      } else if (token[0] === ':') {
        if (!matchPseudo(node, token)) {
          return false;
        }
      } else if (token !== '*') {
        if (node.tag !== token.toLowerCase()) {
          return false;
        }
      }
      match = pattern.exec(compound);
    }
    return sawAny;
  }

  function matchAttribute(node, expression) {
    const eq = expression.search(/[~^$*|]?=/);
    let name = expression;
    let operator = '';
    let expected = '';
    if (eq >= 0) {
      let opEnd = eq;
      while ('~^$*|'.indexOf(expression[opEnd]) >= 0) {
        opEnd++;
      }
      name = expression.substring(0, eq).trim();
      operator = expression.substring(eq, opEnd + 1).trim();
      expected = expression.substring(opEnd + 1).trim();
      if ((expected[0] === '"' && expected[expected.length - 1] === '"') ||
        (expected[0] === "'" && expected[expected.length - 1] === "'")) {
        expected = expected.substring(1, expected.length - 1);
      }
    }
    const actual = node.attrs[name.toLowerCase()];
    if (actual === undefined) {
      return false;
    }
    if (operator === '') {
      return true;
    }
    if (operator === '=') {
      return actual === expected;
    }
    if (operator === '*=') {
      return actual.indexOf(expected) >= 0;
    }
    if (operator === '^=') {
      return actual.indexOf(expected) === 0;
    }
    if (operator === '$=') {
      return actual.length >= expected.length &&
        actual.substring(actual.length - expected.length) === expected;
    }
    if (operator === '~=') {
      return (' ' + actual + ' ').indexOf(' ' + expected + ' ') >= 0;
    }
    if (operator === '|=') {
      return actual === expected || actual.indexOf(expected + '-') === 0;
    }
    return false;
  }

  function elementSiblings(node) {
    const parent = node.parent;
    if (parent === null) {
      return [node];
    }
    const out = [];
    for (let i = 0; i < parent.children.length; i++) {
      if (parent.children[i].type === 'element') {
        out.push(parent.children[i]);
      }
    }
    return out;
  }

  function matchPseudo(node, token) {
    const name = token.substring(1).replace(/\(.*\)$/, '').toLowerCase();
    const argument = /\((.*)\)$/.exec(token);
    const siblings = elementSiblings(node);
    const position = siblings.indexOf(node);
    if (name === 'first-child') {
      return position === 0;
    }
    if (name === 'last-child') {
      return position === siblings.length - 1;
    }
    if (name === 'only-child') {
      return siblings.length === 1;
    }
    if (name === 'nth-child' && argument) {
      return matchNth(argument[1], position + 1);
    }
    if (name === 'nth-last-child' && argument) {
      return matchNth(argument[1], siblings.length - position);
    }
    if (name === 'not' && argument) {
      return !matchCompound(node, argument[1].trim());
    }
    if (name === 'empty') {
      return node.children.length === 0;
    }
    if (name === 'root') {
      return node.parent !== null && node.parent.type === 'document';
    }
    // Unknown pseudo-classes are treated as non-matching rather than throwing,
    // so one exotic selector cannot break a whole source.
    return false;
  }

  function matchNth(expression, position) {
    const text = expression.trim().toLowerCase();
    if (text === 'odd') {
      return position % 2 === 1;
    }
    if (text === 'even') {
      return position % 2 === 0;
    }
    const formula = /^([+-]?\d*)n\s*([+-]\s*\d+)?$/.exec(text.replace(/\s/g, ''));
    if (formula) {
      const aText = formula[1];
      const a = aText === '' || aText === '+' ? 1 : (aText === '-' ? -1 : parseInt(aText, 10));
      const b = formula[2] === undefined ? 0 : parseInt(formula[2].replace(/\s/g, ''), 10);
      if (a === 0) {
        return position === b;
      }
      const delta = position - b;
      return delta % a === 0 && delta / a >= 0;
    }
    const exact = parseInt(text, 10);
    return !isNaN(exact) && position === exact;
  }

  function matchesSelector(node, selector) {
    const groups = parseSelector(selector);
    for (let g = 0; g < groups.length; g++) {
      if (matchesGroup(node, groups[g])) {
        return true;
      }
    }
    return false;
  }

  function matchesGroup(node, tokens) {
    let current = node;
    for (let i = tokens.length - 1; i >= 0; i--) {
      const token = tokens[i];
      if (!matchCompound(current, token.compound)) {
        return false;
      }
      if (i === 0) {
        return true;
      }
      const combinator = tokens[i].combinator;
      if (combinator === '>') {
        current = current.parent;
        if (current === null || current.type !== 'element') {
          return false;
        }
      } else if (combinator === '+') {
        current = previousElementSibling(current);
        if (current === null) {
          return false;
        }
      } else if (combinator === '~') {
        current = previousElementSibling(current);
        if (current === null) {
          return false;
        }
        while (current !== null && !matchCompound(current, tokens[i - 1].compound)) {
          current = previousElementSibling(current);
        }
        if (current === null) {
          return false;
        }
      } else {
        current = current.parent;
        while (current !== null && current.type !== 'element') {
          current = current.parent;
        }
        if (current === null) {
          return false;
        }
        while (current !== null && !matchCompound(current, tokens[i - 1].compound)) {
          current = current.parent;
          while (current !== null && current.type !== 'element') {
            current = current.parent;
          }
        }
        if (current === null) {
          return false;
        }
      }
    }
    return true;
  }

  function previousElementSibling(node) {
    const parent = node.parent;
    if (parent === null) {
      return null;
    }
    const index = parent.children.indexOf(node);
    for (let i = index - 1; i >= 0; i--) {
      if (parent.children[i].type === 'element') {
        return parent.children[i];
      }
    }
    return null;
  }

  function nextElementSibling(node) {
    const parent = node.parent;
    if (parent === null) {
      return null;
    }
    const index = parent.children.indexOf(node);
    for (let i = index + 1; i < parent.children.length; i++) {
      if (parent.children[i].type === 'element') {
        return parent.children[i];
      }
    }
    return null;
  }

  // ------------------------------------------------------------ handle model

  function indexDocument(root) {
    const nodes = [];
    (function walk(node) {
      nodes.push(node);
      node.__index = nodes.length - 1;
      for (let i = 0; i < node.children.length; i++) {
        walk(node.children[i]);
      }
    })(root);
    return nodes;
  }

  function textOf(node) {
    if (node.type === 'text') {
      return node.text;
    }
    let out = '';
    for (let i = 0; i < node.children.length; i++) {
      const child = node.children[i];
      if (child.type === 'text') {
        out += child.text;
      } else if (child.type === 'element') {
        if (child.tag === 'script' || child.tag === 'style') {
          continue;
        }
        if (child.tag === 'br') {
          out += '\n';
          continue;
        }
        out += textOf(child);
      }
    }
    return out;
  }

  function innerHtmlOf(node) {
    let out = '';
    for (let i = 0; i < node.children.length; i++) {
      out += serialize(node.children[i]);
    }
    return out;
  }

  function serialize(node) {
    if (node.type === 'text') {
      if (node.parent && (node.parent.tag === 'script' || node.parent.tag === 'style')) {
        return node.text;
      }
      return node.text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
    if (node.type === 'comment') {
      return '<!--' + node.text + '-->';
    }
    let out = '<' + node.tag;
    for (const name of Object.keys(node.attrs)) {
      const value = node.attrs[name].replace(/&/g, '&amp;').replace(/"/g, '&quot;')
        .replace(/</g, '&lt;').replace(/>/g, '&gt;');
      out += ' ' + name + '="' + value + '"';
    }
    out += '>';
    if (VOID_ELEMENTS[node.tag]) {
      return out;
    }
    out += innerHtmlOf(node);
    out += '</' + node.tag + '>';
    return out;
  }

  function nodeTypeName(node) {
    if (node.type === 'element') {
      return 'element';
    }
    if (node.type === 'text') {
      return 'text';
    }
    if (node.type === 'comment') {
      return 'comment';
    }
    if (node.type === 'document') {
      return 'document';
    }
    return 'unknown';
  }

  function findElements(document, scope, selector) {
    const results = [];
    const start = scope === null ? document.root : scope;
    (function walk(node) {
      for (let i = 0; i < node.children.length; i++) {
        const child = node.children[i];
        if (child.type === 'element') {
          if (matchesSelector(child, selector)) {
            results.push(child);
          }
          walk(child);
        }
      }
    })(start);
    return results;
  }

  function handleHtml(message) {
    const action = message['function'];
    const key = message['key'];

    if (action === 'parse') {
      // init.js owns numeric document keys and ignores parse's return value.
      // Keep one canonical entry, not both "docN" and a numeric alias. Never
      // evict live documents: asynchronous sources may still be using them.
      // The upstream contract releases a document only through dispose().
      const docKey = key !== undefined && key !== null ? key : 'doc' + (documentCounter++);
      const root = parseHtml(String(message['data'] === undefined ? '' : message['data']));
      documents[docKey] = { root: root, nodes: indexDocument(root) };
      return docKey;
    }

    // Document-level actions (parse/querySelector/querySelectorAll/
    // getElementById/dispose) carry the document key in `key`. Element- and
    // node-level actions carry the element index in `key` and the document key
    // in `doc` - looking up `documents[key]` there always missed and returned
    // null, which broke every HtmlElement accessor.
    const docKey = message['doc'] !== undefined && message['doc'] !== null
      ? message['doc'] : key;
    const document = documents[docKey];
    if (!document) {
      return null;
    }
    const nodes = document.nodes;
    const nodeAt = (index) => (index === null || index === undefined || index < 0)
      ? null : nodes[index];

    switch (action) {
      case 'querySelector': {
        const found = findElements(document, document.root, message['query']);
        return found.length > 0 ? found[0].__index : null;
      }
      case 'querySelectorAll': {
        const found = findElements(document, document.root, message['query']);
        return found.map((node) => node.__index);
      }
      case 'dom_querySelector': {
        const scope = nodeAt(message['key']);
        const found = findElements(document, scope, message['query']);
        return found.length > 0 ? found[0].__index : null;
      }
      case 'dom_querySelectorAll': {
        const scope = nodeAt(message['key']);
        const found = findElements(document, scope, message['query']);
        return found.map((node) => node.__index);
      }
      case 'getText': {
        const node = nodeAt(message['key']);
        return node === null ? null : textOf(node).trim();
      }
      case 'getAttributes': {
        const node = nodeAt(message['key']);
        return node === null ? {} : Object.assign(Object.create(null), node.attrs);
      }
      case 'getChildren': {
        const node = nodeAt(message['key']);
        if (node === null) {
          return [];
        }
        return node.children
          .filter((child) => child.type === 'element')
          .map((child) => child.__index);
      }
      case 'getNodes': {
        const node = nodeAt(message['key']);
        if (node === null) {
          return [];
        }
        return node.children.map((child) => child.__index);
      }
      case 'getInnerHTML': {
        const node = nodeAt(message['key']);
        return node === null ? null : innerHtmlOf(node);
      }
      case 'getParent': {
        const node = nodeAt(message['key']);
        return node === null || node.parent === null ? null : node.parent.__index;
      }
      case 'node_text': {
        const node = nodeAt(message['key']);
        return node === null ? null : node.text;
      }
      case 'node_type': {
        const node = nodeAt(message['key']);
        return node === null ? 'unknown' : nodeTypeName(node);
      }
      // init.js HtmlNode.toElement uses camelCase; keep the historical spelling
      // as an alias for direct bridge callers.
      case 'node_toElement':
      case 'node_to_element': {
        const node = nodeAt(message['key']);
        return node === null || node.type !== 'element' ? null : node.__index;
      }
      case 'dispose':
        delete documents[docKey];
        return null;
      case 'getClassNames': {
        const node = nodeAt(message['key']);
        if (node === null || node.type !== 'element') {
          return [];
        }
        const classes = (node.attrs['class'] || '').trim();
        return classes.length === 0 ? [] : classes.split(/\s+/);
      }
      case 'getId': {
        const node = nodeAt(message['key']);
        return node === null ? null : (node.attrs['id'] || null);
      }
      case 'getLocalName': {
        const node = nodeAt(message['key']);
        return node === null ? null : node.tag;
      }
      case 'getElementById': {
        const found = findElements(document, document.root, '#' + message['id']);
        return found.length > 0 ? found[0].__index : null;
      }
      case 'getPreviousSibling': {
        const node = nodeAt(message['key']);
        if (node === null) {
          return null;
        }
        const sibling = previousElementSibling(node);
        return sibling === null ? null : sibling.__index;
      }
      case 'getNextSibling': {
        const node = nodeAt(message['key']);
        if (node === null) {
          return null;
        }
        const sibling = nextElementSibling(node);
        return sibling === null ? null : sibling.__index;
      }
      default:
        return null;
    }
  }

  globalThis.sendMessage = function (message) {
    if (message && message.method === 'html') {
      const trace = 'html-' + (requestCounter++);
      function audit(stage, summary) {
        innerSendMessage({method:'log',level:'info',title:'HtmlAudit',
          content:'TraceID=' + trace + ' [' + stage + '] ' + summary});
      }
      audit('请求到达', '操作=' + message.function + '；不记录HTML、属性或查询内容');
      try {
        const result = handleHtml(message);
        audit('响应返回', '类型=' + (result === null ? 'null' : typeof result) +
          '；活动文档数=' + Object.keys(documents).length +
          (Array.isArray(result) ? '；条目数=' + result.length : ''));
        return result;
      } catch (error) {
        audit('异常', 'HTML操作失败；具体异常回传调用方，不记录页面内容');
        throw error;
      }
    }
    return innerSendMessage(message);
  };

  globalThis.__veneraHtmlEngineLoaded = true;
})();
