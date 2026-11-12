/* Markfetti — GitHub-flavoured Markdown renderer.
 *
 * Pipeline: markdown-it (+ footnotes, task lists, emoji, math, alerts)
 *        → DOMPurify (GitHub-like allowlist)
 *        → post-processing on the sanitised DOM: heading anchors, KaTeX,
 *          relative URLs, Mermaid, GeoJSON/TopoJSON maps, STL models, copy buttons.
 *
 * Swift calls window.markfetti.render({markdown, baseURL, rootURL, path}).
 */
(() => {
  'use strict';

  const $content = document.getElementById('content');
  const $source = document.getElementById('source');
  const $outline = document.getElementById('outline');
  const dark = window.matchMedia('(prefers-color-scheme: dark)');

  // ---------------------------------------------------------------- helpers
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => (
    { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const scriptPromises = {};
  function loadScript(src) {
    if (!scriptPromises[src]) {
      scriptPromises[src] = new Promise((resolve, reject) => {
        const s = document.createElement('script');
        s.src = src; s.onload = resolve;
        s.onerror = () => reject(new Error('Could not load ' + src));
        document.head.appendChild(s);
      });
    }
    return scriptPromises[src];
  }

  function errorBox(title, detail, source) {
    const div = document.createElement('div');
    div.className = 'render-error';
    div.innerHTML = `<p class="render-error-title">${esc(title)}</p>` +
      (detail ? `<p>${esc(detail)}</p>` : '') +
      (source != null ? `<pre><code>${esc(source)}</code></pre>` : '');
    return div;
  }

  // ------------------------------------------------------- syntax highlight
  const SPECIAL_FENCES = new Set(['mermaid', 'geojson', 'topojson', 'stl', 'math']);
  const LANG_ALIASES = {
    console: 'shell', 'shell-session': 'shell', sh: 'bash', zsh: 'bash', jsonc: 'json', json5: 'json',
    'objective-c': 'objectivec', objc: 'objectivec', 'c++': 'cpp', 'c#': 'csharp', 'f#': 'fsharp',
    tsx: 'typescript', jsx: 'javascript', mjs: 'javascript', cjs: 'javascript', vue: 'xml', html: 'xml',
    svg: 'xml', plist: 'xml', toml: 'ini', conf: 'ini', proto: 'protobuf', tex: 'latex', ps1: 'powershell',
    docker: 'dockerfile', yml: 'yaml', patch: 'diff', 'python3': 'python', py3: 'python', rs: 'rust',
    kt: 'kotlin', golang: 'go', terraform: 'ini', hcl: 'ini', make: 'makefile', mk: 'makefile', text: 'plaintext', txt: 'plaintext',
  };

  function highlight(code, lang) {
    lang = (lang || '').toLowerCase();
    if (!lang || SPECIAL_FENCES.has(lang)) return '';
    const name = hljs.getLanguage(lang) ? lang : LANG_ALIASES[lang];
    if (!name || !hljs.getLanguage(name)) return '';
    try { return hljs.highlight(code, { language: name, ignoreIllegals: true }).value; } catch (_) { return ''; }
  }

  // ------------------------------------------------------------ markdown-it
  const md = window.markdownit({ html: true, linkify: true, typographer: false, breaks: false, highlight });
  md.linkify.set({ fuzzyEmail: false });
  md.use(window.markdownitFootnote);
  md.use(window.markdownitTaskLists, { enabled: false, label: false });
  md.use(window.markdownitEmoji.full || window.markdownitEmoji);

  // GitHub doesn't add "class=footnote-ref" brackets: render [1] as plain superscript number.
  md.renderer.rules.footnote_caption = (tokens, idx) => {
    let n = Number(tokens[idx].meta.id + 1).toString();
    if (tokens[idx].meta.subId > 0) n += ':' + tokens[idx].meta.subId;
    return n;
  };
  md.renderer.rules.footnote_block_open = () =>
    '<section class="footnotes" data-footnotes>\n<h2 class="sr-only" id="footnote-label">Footnotes</h2>\n<ol class="footnotes-list">\n';

  // ---- Math: $…$, $`…`$, $$…$$ (inline or block) and ```math fences, following GitHub's rules.
  const isWS = (c) => c === 0x20 || c === 0x09 || c === 0x0a || c === 0x0d;
  const isEscaped = (src, pos) => { let n = 0; while (pos - 1 - n >= 0 && src.charCodeAt(pos - 1 - n) === 0x5c) n++; return n % 2 === 1; };

  function mathInline(state, silent) {
    const src = state.src, start = state.pos, max = state.posMax;
    if (src.charCodeAt(start) !== 0x24 /* $ */) return false;
    let content, display = false, end;

    if (src.charCodeAt(start + 1) === 0x60 /* ` */) {            // $`…`$
      end = src.indexOf('`$', start + 2);
      if (end < 0 || end + 2 > max) return false;
      content = src.slice(start + 2, end); end += 2;
    } else if (src.charCodeAt(start + 1) === 0x24) {               // $$…$$
      end = start + 2;
      for (;;) {
        end = src.indexOf('$$', end);
        if (end < 0 || end + 2 > max) return false;
        if (!isEscaped(src, end)) break;
        end += 2;
      }
      content = src.slice(start + 2, end); end += 2; display = true;
    } else {                                                        // $…$
      if (start + 1 >= max || isWS(src.charCodeAt(start + 1))) return false;
      end = start + 1;
      for (;;) {
        end = src.indexOf('$', end);
        if (end < 0 || end >= max) return false;
        if (!isEscaped(src, end) && !isWS(src.charCodeAt(end - 1))) break;
        end++;
      }
      const after = src.charCodeAt(end + 1);
      if (after >= 0x30 && after <= 0x39) return false;              // "$5 and $6" is money, not math
      content = src.slice(start + 1, end); end += 1;
    }
    if (!content.trim()) return false;
    if (!silent) {
      const t = state.push('math_inline', 'span', 0);
      t.content = content; t.meta = { display };
    }
    state.pos = end;
    return true;
  }

  function mathBlock(state, startLine, endLine, silent) {
    let pos = state.bMarks[startLine] + state.tShift[startLine];
    const max = state.eMarks[startLine];
    if (state.sCount[startLine] - state.blkIndent >= 4) return false;
    if (state.src.slice(pos, pos + 2) !== '$$') return false;
    pos += 2;
    let first = state.src.slice(pos, max), last = '', next = startLine, found = false;
    const firstTrim = first.trim();
    if (firstTrim.endsWith('$$') && firstTrim.length >= 2) {
      first = firstTrim.slice(0, -2); found = true;
      if (!first.trim()) return false;
    } else if (first.includes('$$')) {
      return false; // e.g. "$$a$$ and more" — leave it to the inline rule
    } else {
      for (next = startLine + 1; next < endLine; next++) {
        const p = state.bMarks[next] + state.tShift[next], m = state.eMarks[next];
        if (p < m && state.sCount[next] < state.blkIndent) break;
        const line = state.src.slice(p, m).trim();
        if (line.endsWith('$$') && !isEscaped(line, line.length - 2)) { last = line.slice(0, -2); found = true; break; }
      }
    }
    if (!found) return false;
    if (silent) return true;
    const middle = next > startLine + 1 ? state.getLines(startLine + 1, next, state.tShift[startLine], false) : '';
    const t = state.push('math_block', 'div', 0);
    t.block = true;
    t.content = [first.trim() ? first : '', middle, last].filter(Boolean).join('\n');
    t.map = [startLine, next + 1];
    state.line = next + 1;
    return true;
  }

  md.inline.ruler.before('escape', 'math_inline', mathInline);
  md.block.ruler.before('fence', 'math_block', mathBlock, { alt: ['paragraph', 'reference', 'blockquote', 'list'] });
  md.renderer.rules.math_inline = (tokens, idx) => {
    const t = tokens[idx];
    return `<span class="math ${t.meta.display ? 'math-display' : 'math-inline'}">${esc(t.content)}</span>`;
  };
  md.renderer.rules.math_block = (tokens, idx) => `<div class="math math-display">${esc(tokens[idx].content)}</div>\n`;

  const defaultFence = md.renderer.rules.fence;
  md.renderer.rules.fence = (tokens, idx, options, env, self) => {
    const t = tokens[idx];
    const lang = (t.info || '').trim().split(/\s+/)[0].toLowerCase();
    if (lang === 'math') return `<div class="math math-display">${esc(t.content)}</div>\n`;
    return defaultFence(tokens, idx, options, env, self);
  };

  // ---- GitHub alerts: > [!NOTE] / [!TIP] / [!IMPORTANT] / [!WARNING] / [!CAUTION]
  const OCT = (d) => `<svg class="octicon" viewBox="0 0 16 16" width="16" height="16" aria-hidden="true"><path d="${d}"></path></svg>`;
  const ALERTS = {
    note: ['Note', OCT('M0 8a8 8 0 1 1 16 0A8 8 0 0 1 0 8Zm8-6.5a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13ZM6.5 7.75A.75.75 0 0 1 7.25 7h1a.75.75 0 0 1 .75.75v2.75h.25a.75.75 0 0 1 0 1.5h-2a.75.75 0 0 1 0-1.5h.25v-2h-.25a.75.75 0 0 1-.75-.75ZM8 6a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z')],
    tip: ['Tip', OCT('M8 1.5c-2.363 0-4 1.69-4 3.75 0 .984.424 1.625.984 2.304l.214.253c.223.264.47.556.673.848.284.411.537.896.621 1.49a.75.75 0 0 1-1.484.211c-.04-.282-.163-.547-.37-.847a8.456 8.456 0 0 0-.542-.68c-.084-.1-.173-.205-.268-.32C3.201 7.75 2.5 6.766 2.5 5.25 2.5 2.31 4.863 0 8 0s5.5 2.31 5.5 5.25c0 1.516-.701 2.5-1.328 3.259-.095.115-.184.22-.268.319-.207.245-.383.453-.541.681-.208.3-.33.565-.37.847a.751.751 0 0 1-1.485-.212c.084-.593.337-1.078.621-1.489.203-.292.45-.584.673-.848.075-.088.147-.173.213-.253.561-.679.985-1.32.985-2.304 0-2.06-1.637-3.75-4-3.75ZM5.75 12h4.5a.75.75 0 0 1 0 1.5h-4.5a.75.75 0 0 1 0-1.5ZM6 15.25a.75.75 0 0 1 .75-.75h2.5a.75.75 0 0 1 0 1.5h-2.5a.75.75 0 0 1-.75-.75Z')],
    important: ['Important', OCT('M0 1.75C0 .784.784 0 1.75 0h12.5C15.216 0 16 .784 16 1.75v9.5A1.75 1.75 0 0 1 14.25 13H8.06l-2.573 2.573A1.458 1.458 0 0 1 3 14.543V13H1.75A1.75 1.75 0 0 1 0 11.25Zm1.75-.25a.25.25 0 0 0-.25.25v9.5c0 .138.112.25.25.25h2a.75.75 0 0 1 .75.75v2.19l2.72-2.72a.749.749 0 0 1 .53-.22h6.5a.25.25 0 0 0 .25-.25v-9.5a.25.25 0 0 0-.25-.25Zm7 2.25v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 9a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z')],
    warning: ['Warning', OCT('M6.457 1.047c.659-1.234 2.427-1.234 3.086 0l6.082 11.378A1.75 1.75 0 0 1 14.082 15H1.918a1.75 1.75 0 0 1-1.543-2.575Zm1.763.707a.25.25 0 0 0-.44 0L1.698 13.132a.25.25 0 0 0 .22.368h12.164a.25.25 0 0 0 .22-.368Zm.53 3.996v2.5a.75.75 0 0 1-1.5 0v-2.5a.75.75 0 0 1 1.5 0ZM9 11a1 1 0 1 1-2 0 1 1 0 0 1 2 0Z')],
    caution: ['Caution', OCT('M4.47.22A.749.749 0 0 1 5 0h6c.199 0 .389.079.53.22l4.25 4.25c.141.14.22.331.22.53v6a.749.749 0 0 1-.22.53l-4.25 4.25A.749.749 0 0 1 11 16H5a.749.749 0 0 1-.53-.22L.22 11.53A.749.749 0 0 1 0 11V5c0-.199.079-.389.22-.53Zm.84 1.28L1.5 5.31v5.38l3.81 3.81h5.38l3.81-3.81V5.31L10.69 1.5ZM8 4a.75.75 0 0 1 .75.75v3.5a.75.75 0 0 1-1.5 0v-3.5A.75.75 0 0 1 8 4Zm0 8a1 1 0 1 1 0-2 1 1 0 0 1 0 2Z')],
  };

  md.core.ruler.after('block', 'github_alerts', (state) => {
    const t = state.tokens;
    for (let i = 0; i < t.length; i++) {
      if (t[i].type !== 'blockquote_open' || t[i].level !== 0) continue;
      const p = t[i + 1], inl = t[i + 2];
      if (!p || p.type !== 'paragraph_open' || !inl || inl.type !== 'inline') continue;
      const m = /^\[!(NOTE|TIP|IMPORTANT|WARNING|CAUTION)\][ \t]*(?:\n|$)/i.exec(inl.content);
      if (!m) continue;
      const kind = m[1].toLowerCase();
      let depth = 0, j = i;
      for (; j < t.length; j++) {
        if (t[j].type === 'blockquote_open') depth++;
        else if (t[j].type === 'blockquote_close' && --depth === 0) break;
      }
      t[i].tag = 'div'; t[i].attrSet('class', `markdown-alert markdown-alert-${kind}`);
      if (t[j]) t[j].tag = 'div';
      const title = new state.Token('html_block', '', 0);
      title.content = `<p class="markdown-alert-title">${ALERTS[kind][1]}${ALERTS[kind][0]}</p>\n`;
      inl.content = inl.content.slice(m[0].length);
      if (!inl.content.trim()) t.splice(i + 1, 3, title); else t.splice(i + 1, 0, title);
    }
  });

  // ------------------------------------------------------------- sanitising
  const PURIFY = {
    FORBID_TAGS: ['style', 'form', 'button', 'textarea', 'select', 'option', 'iframe', 'frame', 'frameset',
      'object', 'embed', 'applet', 'link', 'meta', 'base', 'dialog', 'template'],
    FORBID_ATTR: ['style', 'class-name', 'autofocus', 'srcdoc', 'formaction'],
    ADD_ATTR: ['align', 'target'],
  };
  DOMPurify.addHook('uponSanitizeElement', (node, data) => {
    if (data.tagName === 'input' && (node.getAttribute('type') || '').toLowerCase() !== 'checkbox') node.remove();
  });
  DOMPurify.addHook('afterSanitizeAttributes', (node) => {
    if (node.tagName === 'INPUT') node.setAttribute('disabled', '');
  });

  // ----------------------------------------------------------- post-process
  const LINK_ICON = OCT('m7.775 3.275 1.25-1.25a3.5 3.5 0 1 1 4.95 4.95l-2.5 2.5a3.5 3.5 0 0 1-4.95 0 .751.751 0 0 1 .018-1.042.751.751 0 0 1 1.042-.018 1.998 1.998 0 0 0 2.83 0l2.5-2.5a2.002 2.002 0 0 0-2.83-2.83l-1.25 1.25a.751.751 0 0 1-1.042-.018.751.751 0 0 1-.018-1.042Zm-4.69 9.64a1.998 1.998 0 0 0 2.83 0l1.25-1.25a.751.751 0 0 1 1.042.018.751.751 0 0 1 .018 1.042l-1.25 1.25a3.5 3.5 0 1 1-4.95-4.95l2.5-2.5a3.5 3.5 0 0 1 4.95 0 .751.751 0 0 1-.018 1.042.751.751 0 0 1-1.042.018 1.998 1.998 0 0 0-2.83 0l-2.5 2.5a1.998 1.998 0 0 0 0 2.83Z').replace('class="octicon"', 'class="octicon octicon-link"');

  function githubSlug(text) {
    return text.trim().toLowerCase().replace(/[^\p{L}\p{M}\p{N}\p{Pc}\- ]/gu, '').replace(/ /g, '-');
  }

  function addHeadingAnchors(root) {
    const seen = new Map();
    const items = [];
    root.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach((h) => {
      if (h.closest('.markdown-alert-title, .footnotes')) return;
      const base = githubSlug(h.textContent) || 'section';
      const n = seen.get(base) || 0; seen.set(base, n + 1);
      const slug = n ? `${base}-${n}` : base;
      h.id = slug;
      const a = document.createElement('a');
      a.className = 'anchor'; a.href = '#' + slug; a.setAttribute('aria-hidden', 'true');
      a.innerHTML = LINK_ICON;
      h.prepend(a);
      items.push({ level: Number(h.tagName[1]), text: h.textContent.trim(), slug });
    });
    return items;
  }

  function resolveURLs(root, baseURL, rootURL) {
    if (!baseURL) return;
    const resolve = (v) => {
      v = (v || '').trim();
      if (!v || v.startsWith('#') || /^[a-z][a-z0-9+.-]*:/i.test(v) || v.startsWith('//')) return null;
      try { return new URL(v, v.startsWith('/') && rootURL ? rootURL + '.' + v : baseURL).href; } catch (_) { return null; }
    };
    root.querySelectorAll('[src], [href], [poster]').forEach((el) => {
      for (const attr of ['src', 'href', 'poster']) {
        const r = el.hasAttribute(attr) && resolve(el.getAttribute(attr));
        if (r) el.setAttribute(attr, r);
      }
    });
    root.querySelectorAll('[srcset]').forEach((el) => {
      el.setAttribute('srcset', el.getAttribute('srcset').split(',').map((part) => {
        const [u, ...rest] = part.trim().split(/\s+/);
        return [resolve(u) || u, ...rest].join(' ');
      }).join(', '));
    });
    // Like GitHub, a linked image opens the image itself
    root.querySelectorAll('img').forEach((img) => { img.loading = 'lazy'; });
  }

  function renderMath(root) {
    root.querySelectorAll('.math').forEach((el) => {
      const tex = el.textContent;
      const display = el.classList.contains('math-display');
      try {
        katex.render(tex, el, { displayMode: display, throwOnError: false, trust: false, strict: 'ignore', output: 'htmlAndMathml' });
      } catch (e) {
        el.textContent = tex; el.classList.add('math-error'); el.title = e.message;
      }
    });
  }

  function addCopyButtons(root) {
    root.querySelectorAll('pre').forEach((pre) => {
      if (pre.closest('.render-error')) return;
      const wrap = document.createElement('div');
      wrap.className = 'highlight-wrap';
      pre.replaceWith(wrap); wrap.appendChild(pre);
      const btn = document.createElement('span');
      btn.className = 'copy-btn'; btn.setAttribute('role', 'button'); btn.title = 'Copy';
      btn.innerHTML = OCT('M0 6.75C0 5.784.784 5 1.75 5h1.5a.75.75 0 0 1 0 1.5h-1.5a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-1.5a.75.75 0 0 1 1.5 0v1.5A1.75 1.75 0 0 1 9.25 16h-7.5A1.75 1.75 0 0 1 0 14.25Z M5 1.75C5 .784 5.784 0 6.75 0h7.5C15.216 0 16 .784 16 1.75v7.5A1.75 1.75 0 0 1 14.25 11h-7.5A1.75 1.75 0 0 1 5 9.25Zm1.75-.25a.25.25 0 0 0-.25.25v7.5c0 .138.112.25.25.25h7.5a.25.25 0 0 0 .25-.25v-7.5a.25.25 0 0 0-.25-.25Z');
      btn.addEventListener('click', () => {
        const text = pre.innerText;
        if (window.webkit?.messageHandlers?.markfetti) window.webkit.messageHandlers.markfetti.postMessage({ copy: text });
        else navigator.clipboard?.writeText(text);
        btn.classList.add('copied'); setTimeout(() => btn.classList.remove('copied'), 1200);
      });
      wrap.appendChild(btn);
    });
  }

  // ---- Mermaid
  let mermaidCounter = 0;
  async function renderMermaid(blocks) {
    if (!blocks.length) return;
    await loadScript('vendor/mermaid/mermaid.min.js');
    window.mermaid.initialize({
      startOnLoad: false, securityLevel: 'strict', theme: dark.matches ? 'dark' : 'default',
      fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif',
    });
    for (const { pre, src } of blocks) {
      const div = document.createElement('div');
      div.className = 'mermaid-diagram';
      pre.replaceWith(div);
      try {
        const { svg } = await window.mermaid.render('mermaid-' + (++mermaidCounter), src);
        div.innerHTML = svg;
      } catch (e) {
        div.replaceWith(errorBox('Unable to render Mermaid diagram', String(e.message || e).split('\n')[0], src));
        document.querySelectorAll('body > [id^="dmermaid-"]').forEach((n) => n.remove());
      }
    }
  }

  // ---- GeoJSON / TopoJSON
  async function renderMaps(blocks) {
    if (!blocks.length) return;
    await loadScript('vendor/leaflet/leaflet.js');
    await loadScript('vendor/leaflet/topojson-client.min.js');
    L.Icon.Default.imagePath = 'vendor/leaflet/images/';
    for (const { pre, src, lang } of blocks) {
      let data;
      try {
        data = JSON.parse(src);
        if (lang === 'topojson') {
          if (data.type !== 'Topology') throw new Error('Expected a TopoJSON "Topology" object');
          data = { type: 'FeatureCollection', features: Object.values(data.objects).flatMap((o) => {
            const f = topojson.feature(data, o); return f.type === 'FeatureCollection' ? f.features : [f];
          }) };
        }
      } catch (e) {
        pre.replaceWith(errorBox(`Unable to render ${lang === 'topojson' ? 'TopoJSON' : 'GeoJSON'} map`, e.message, src));
        continue;
      }
      const div = document.createElement('div');
      div.className = 'map-view';
      pre.replaceWith(div);
      const map = L.map(div, { scrollWheelZoom: false, attributionControl: true });
      const base = dark.matches ? 'Canvas/World_Dark_Gray_Base' : 'Canvas/World_Light_Gray_Base';
      L.tileLayer(`https://server.arcgisonline.com/ArcGIS/rest/services/${base}/MapServer/tile/{z}/{y}/{x}`, {
        maxZoom: 16, attribution: 'Tiles &copy; Esri &mdash; Esri, HERE, Garmin, &copy; OpenStreetMap contributors',
      }).addTo(map);
      const layer = L.geoJSON(data, {
        style: (f) => ({ color: f?.properties?.stroke || '#0969da', weight: f?.properties?.['stroke-width'] || 2,
          fillColor: f?.properties?.fill || '#0969da', fillOpacity: f?.properties?.['fill-opacity'] ?? 0.2 }),
        onEachFeature: (f, l) => {
          const props = f.properties || {};
          const keys = Object.keys(props);
          if (keys.length) {
            l.bindPopup('<table class="map-props">' + keys.map((k) =>
              `<tr><th>${esc(k)}</th><td>${esc(typeof props[k] === 'object' ? JSON.stringify(props[k]) : props[k])}</td></tr>`).join('') + '</table>');
          }
        },
      }).addTo(map);
      const b = layer.getBounds();
      if (b.isValid()) map.fitBounds(b, { padding: [20, 20], maxZoom: 14 }); else map.setView([0, 0], 1);
      new ResizeObserver(() => map.invalidateSize()).observe(div);
      if ((current?.mode || 'app') !== 'app') {
        // macOS doesn't let Quick Look extensions use the network, so there are no map tiles.
        const note = document.createElement('div');
        note.className = 'map-offline-note';
        note.textContent = 'Map tiles load when the file is opened in Markfetti';
        div.appendChild(note);
      }
    }
  }

  // ---- STL
  async function renderSTL(blocks) {
    if (!blocks.length) return;
    const THREE = await import('three');
    const { STLLoader } = await import('three/addons/loaders/STLLoader.js');
    const { OrbitControls } = await import('three/addons/controls/OrbitControls.js');
    for (const { pre, src } of blocks) {
      let geom;
      try {
        geom = new STLLoader().parse(src);
        if (!geom.attributes.position || geom.attributes.position.count === 0) throw new Error('No triangles found');
      } catch (e) {
        pre.replaceWith(errorBox('Unable to render STL model', e.message, src));
        continue;
      }
      const div = document.createElement('div');
      div.className = 'stl-view';
      pre.replaceWith(div);
      geom.rotateX(-Math.PI / 2); // STL is Z-up; three.js is Y-up
      geom.computeVertexNormals(); geom.center(); geom.computeBoundingSphere();
      const r = geom.boundingSphere.radius || 1;
      const scene = new THREE.Scene();
      const camera = new THREE.PerspectiveCamera(40, 1, r / 100, r * 100);
      camera.position.set(r * 1.4, r * 1.2, r * 2.0);
      scene.add(new THREE.HemisphereLight(0xffffff, 0x444444, 1.6));
      const sun = new THREE.DirectionalLight(0xffffff, 1.8); sun.position.set(1, 2, 3); camera.add(sun); scene.add(camera);
      const mesh = new THREE.Mesh(geom, new THREE.MeshStandardMaterial({ color: 0x4f8fe6, metalness: 0.1, roughness: 0.55, flatShading: true }));
      scene.add(mesh);
      const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
      renderer.setPixelRatio(window.devicePixelRatio);
      div.appendChild(renderer.domElement);
      const controls = new OrbitControls(camera, renderer.domElement);
      controls.enableZoom = true;
      const draw = () => renderer.render(scene, camera);
      controls.addEventListener('change', draw);
      const fit = () => {
        const w = div.clientWidth, h = div.clientHeight;
        renderer.setSize(w, h); camera.aspect = w / h; camera.updateProjectionMatrix(); draw();
      };
      new ResizeObserver(fit).observe(div);
      fit();
    }
  }

  function collectSpecial(root) {
    const out = { mermaid: [], maps: [], stl: [] };
    root.querySelectorAll('pre > code[class*="language-"]').forEach((code) => {
      const lang = [...code.classList].find((c) => c.startsWith('language-'))?.slice(9).toLowerCase();
      const item = { pre: code.parentElement, src: code.textContent, lang };
      if (lang === 'mermaid') out.mermaid.push(item);
      else if (lang === 'geojson' || lang === 'topojson') out.maps.push(item);
      else if (lang === 'stl') out.stl.push(item);
    });
    return out;
  }

  // ----------------------------------------------------------------- outline
  function buildOutline(items) {
    $outline.innerHTML = items.length
      ? '<p class="outline-title">Outline</p><ul>' + items.map((i) =>
        `<li class="lvl-${i.level}"><a href="#${esc(i.slug)}">${esc(i.text)}</a></li>`).join('') + '</ul>'
      : '<p class="outline-title">No headings</p>';
  }

  // Quick Look extensions can't reach the network (and in the App Store build can't read files
  // next to the document), so images that fail to load become a small labelled placeholder.
  function markOfflineImages(root) {
    for (const img of root.querySelectorAll('img')) {
      img.addEventListener('error', () => {
        const ph = document.createElement('span');
        ph.className = 'offline-image';
        ph.title = img.src;
        ph.textContent = img.alt || 'image';
        img.replaceWith(ph);
      }, { once: true });
    }
  }

  // ------------------------------------------------------------------ render
  let current = null;
  let generation = 0;

  async function render(payload, { keepScroll } = {}) {
    const same = keepScroll ?? (current && current.path === payload.path);
    current = payload;
    const gen = ++generation;
    const y = same ? window.scrollY : 0;

    const html = DOMPurify.sanitize(md.render(payload.markdown || ''), PURIFY);
    const root = document.createElement('div');
    root.innerHTML = html;
    const outline = addHeadingAnchors(root);
    resolveURLs(root, payload.baseURL, payload.rootURL);
    renderMath(root);
    const special = collectSpecial(root);
    const mode = payload.mode || 'app';
    document.body.dataset.mode = mode;
    if (mode === 'thumbnail') {
      // Finder thumbnails are static snapshots: draw simple placeholders for maps and 3D models.
      for (const [items, label] of [[special.maps, 'Map'], [special.stl, '3D model']]) {
        for (const { pre } of items) {
          const div = document.createElement('div');
          div.className = 'static-placeholder';
          div.textContent = label;
          pre.replaceWith(div);
        }
        items.length = 0;
      }
    }
    addCopyButtons(root);

    if (mode !== 'app') markOfflineImages(root);
    $content.replaceChildren(...root.childNodes);
    $source.textContent = payload.markdown || '';
    buildOutline(outline);
    window.scrollTo(0, y);
    document.title = payload.title || 'Markfetti';

    const jobs = [
      renderMermaid(special.mermaid),
      renderMaps(special.maps),
      renderSTL(special.stl),
    ].map((p) => p.catch((e) => console.error(e)));
    await Promise.all(jobs);
    if (gen === generation && same) window.scrollTo(0, y);
    if (gen === generation && payload.anchor) scrollToAnchor(payload.anchor);
  }

  function scrollToAnchor(name) {
    if (!name) return false;
    let id = name.replace(/^#/, '');
    try { id = decodeURIComponent(id); } catch (_) {}
    const el = document.getElementById(id) || document.getElementById('user-content-' + id) ||
      document.getElementById(githubSlug(id));
    if (el) { el.scrollIntoView({ block: 'start' }); return true; }
    return false;
  }

  // In-page anchor links (#foo) scroll without navigating
  document.addEventListener('click', (e) => {
    const a = e.target.closest('a[href^="#"]');
    if (!a) return;
    e.preventDefault();
    if (scrollToAnchor(a.getAttribute('href'))) history.replaceState(null, '', a.getAttribute('href'));
  });

  // Re-render when the system switches light/dark (Mermaid themes, map tiles)
  dark.addEventListener('change', () => { if (current) render(current, { keepScroll: true }); });

  // Printing: WebKit's PDF output drops the alpha of translucent SVG gradients, so badges
  // (shields.io etc.) come out dark gray. Before printing, swap SVG <img>s for canvases drawn
  // at 4× (canvas rendering is correct, and drawing cross-origin images for display is allowed).
  const SVG_IMAGE_HOSTS = /(^|\.)(shields\.io|badgen\.net|badge\.fury\.io|forthebadge\.com)$/i;
  function isSVGImage(img) {
    const src = img.currentSrc || img.src;
    if (!src) return false;
    if (/^data:image\/svg\+xml/i.test(src)) return true;
    try {
      const u = new URL(src);
      return /\.svgz?$/i.test(u.pathname) || SVG_IMAGE_HOSTS.test(u.hostname);
    } catch { return false; }
  }
  // Resolves once every image has loaded or failed, or after `ms` milliseconds.
  function imagesLoaded(imgs = [...$content.querySelectorAll('img')], ms = 3000) {
    return Promise.all(imgs.map((img) => new Promise((done) => {
      if (img.complete) return done();
      img.addEventListener('load', done, { once: true });
      img.addEventListener('error', done, { once: true });
      setTimeout(done, ms);
    })));
  }
  let printSwaps = [];
  async function preparePrint() {
    restorePrint();
    const imgs = [...$content.querySelectorAll('img')].filter(isSVGImage);
    // Wait for any still-downloading images, e.g. badges on a cold cache.
    await imagesLoaded(imgs, 5000);
    for (const img of imgs) {
      if (!img.isConnected || !img.complete) continue;
      const w = img.clientWidth, h = img.clientHeight;
      if (!w || !h || !img.naturalWidth) continue;
      const scale = 4;
      const canvas = document.createElement('canvas');
      canvas.width = Math.round(w * scale);
      canvas.height = Math.round(h * scale);
      const cs = getComputedStyle(img);
      Object.assign(canvas.style, {
        width: w + 'px', height: h + 'px', verticalAlign: cs.verticalAlign, float: cs.float,
        margin: cs.margin, padding: cs.padding, border: cs.border, boxSizing: 'content-box',
      });
      canvas.setAttribute('role', 'img');
      canvas.setAttribute('aria-label', img.alt || '');
      try { canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height); } catch { continue; }
      img.replaceWith(canvas);
      printSwaps.push([canvas, img]);
    }
    return printSwaps.length;
  }
  function restorePrint() {
    for (const [canvas, img] of printSwaps) if (canvas.isConnected) canvas.replaceWith(img);
    printSwaps = [];
  }

  window.markfetti = {
    render,
    scrollToAnchor,
    preparePrint,
    restorePrint,
    // Sandboxed (App Store) build: the document's images are in a folder it hasn't been granted.
    showAccessBanner() {
      if (document.getElementById('access-banner')) return;
      const bar = document.createElement('div');
      bar.id = 'access-banner';
      bar.innerHTML = '<span>Some images are in a folder Markfetti hasn\u2019t been given access to.</span>';
      const button = document.createElement('button');
      button.textContent = 'Allow Access\u2026';
      button.addEventListener('click', () =>
        window.webkit?.messageHandlers?.markfetti?.postMessage({ requestFolderAccess: true }));
      bar.appendChild(button);
      document.getElementById('page').prepend(bar);
    },
    async imagesLoaded(ms) { await imagesLoaded(undefined, ms); },
    setSourceMode(on) { $content.hidden = !!on; $source.hidden = !on; },
    setOutline(on) { document.body.classList.toggle('show-outline', !!on); },
  };

  // Development: open index.html?file=path/to/file.md over http to preview without the app.
  const devFile = new URLSearchParams(location.search).get('file');
  if (devFile && location.protocol.startsWith('http')) {
    fetch(devFile).then((r) => r.text()).then((text) => {
      const u = new URL(devFile, location.href);
      render({ markdown: text, baseURL: new URL('.', u).href, rootURL: location.origin + '/', path: devFile, title: devFile });
    });
  }
  window.webkit?.messageHandlers?.markfetti?.postMessage({ ready: true });
})();
