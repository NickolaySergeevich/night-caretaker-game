#!/usr/bin/env node
'use strict';

// Offline regression tests for the exported Godot loader. No browser, network,
// account, or exported artifact is modified. Pass the patched export directory
// (or its index.js) as the first argument.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const requested = path.resolve(process.argv[2] || path.join(root, 'build/godot-web-loader02'));
const jsPath = requested.endsWith('.js') ? requested : path.join(requested, 'index.js');
const htmlPath = path.join(path.dirname(jsPath), 'index.html');
const source = fs.readFileSync(jsPath, 'utf8');
const html = fs.readFileSync(htmlPath, 'utf8');
const wrapperStart = source.indexOf('const Features =');
assert(wrapperStart >= 0, 'Godot export must expose the expected Features/Preloader wrapper');
const wrapper = source.slice(wrapperStart);
const tests = [];
const test = (name, fn) => tests.push({ name, fn });
const validWasm = Uint8Array.of(0, 97, 115, 109, 1, 0, 0, 0);
class PendingOperationError extends Error {}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((yes, no) => { resolve = yes; reject = no; });
  return { promise, resolve, reject };
}

async function flush() {
  for (let i = 0; i < 20; i++) await Promise.resolve();
}

async function settled(promise, label = 'operation') {
  let timer;
  try {
    return await Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new PendingOperationError(`${label} stayed pending instead of settling`)), 1500);
      }),
    ]);
  } finally {
    clearTimeout(timer);
  }
}

async function rejects(promise, expected) {
  let rejected = false;
  try {
    await promise;
  } catch (error) {
    // A test harness timeout is a failed test, never evidence that the loader
    // rejected. This distinction is essential when testing infinite hangs.
    if (error instanceof PendingOperationError) throw error;
    rejected = true;
    if (expected instanceof RegExp) assert.match(String(error.message || error), expected);
    else if (typeof expected === 'function') assert.equal(expected(error), true);
  }
  assert(rejected, 'operation unexpectedly fulfilled instead of rejecting');
}

function fakeClock() {
  let now = 0;
  let nextId = 1;
  const timers = new Map();
  return {
    timers,
    now: () => now,
    setTimeout(fn, delay = 0, ...args) {
      const id = nextId++;
      timers.set(id, { due: now + Number(delay), fn: () => fn(...args), delay: Number(delay) });
      return id;
    },
    clearTimeout(id) { timers.delete(id); },
    async advance(ms) {
      const target = now + ms;
      for (;;) {
        const item = [...timers].sort((a, b) => a[1].due - b[1].due)[0];
        if (!item || item[1].due > target) break;
        now = item[1].due;
        timers.delete(item[0]);
        item[1].fn();
        await flush();
      }
      now = target;
      await flush();
    },
  };
}

function responseFor(chunks, options = {}) {
  let position = 0;
  const state = { reads: 0, cancels: 0, releases: 0 };
  const reader = {
    async read() {
      state.reads++;
      if (position >= chunks.length) return { done: true };
      const value = chunks[position++];
      if (value instanceof Error) throw value;
      if (typeof value === 'function') return value();
      if (value && typeof value.then === 'function') return value;
      return { done: false, value: Uint8Array.from(value) };
    },
    async cancel() { state.cancels++; options.onCancel?.(); },
    releaseLock() { state.releases++; },
  };
  const response = {
    ok: options.ok ?? true,
    status: options.status ?? 200,
    statusText: options.statusText || 'OK',
    url: 'https://example.invalid/index.wasm',
    headers: new Headers(options.headers || {}),
    body: options.noBody ? null : { getReader: () => reader },
    async arrayBuffer() {
      if (options.arrayBufferError) throw options.arrayBufferError;
      return Uint8Array.from(chunks.flat()).buffer;
    },
  };
  return { response, state, reader };
}

function loaderContext(options = {}) {
  const clock = fakeClock();
  const fetchCalls = [];
  const animationFrames = [];
  const events = [];
  const logs = [];
  const window = {
    dispatchEvent(event) { events.push(event); return true; },
    addEventListener() {},
    removeEventListener() {},
  };
  const context = vm.createContext({
    ArrayBuffer, Uint8Array, Promise, Error, TypeError, Response, Headers,
    ReadableStream, AbortController, DOMException, WebAssembly,
    CustomEvent: class CustomEvent { constructor(type, init = {}) { this.type = type; Object.assign(this, init); } },
    console: { log: (...args) => logs.push(args), warn: (...args) => logs.push(args), error: (...args) => logs.push(args) },
    window,
    navigator: { language: 'ru-RU', languages: ['ru-RU'] },
    document: {},
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    requestAnimationFrame: (fn) => { animationFrames.push(fn); return animationFrames.length; },
    cancelAnimationFrame() {},
    fetch: (...args) => {
      fetchCalls.push(args);
      return options.fetch ? options.fetch(...args) : Promise.resolve(responseFor([validWasm]).response);
    },
    Godot: options.Godot || (() => Promise.resolve({ initFS: () => Promise.resolve() })),
  });
  vm.runInContext(`${wrapper}\nglobalThis.__loader = { Preloader, InternalConfig, Engine };`, context, { filename: jsPath });
  return { ...context.__loader, context, clock, fetchCalls, animationFrames, events, logs };
}

test('complete exported JavaScript parses', () => { new vm.Script(source, { filename: jsPath }); });

test('decoded bytes, not compressed Content-Length, determine validity and progress', async () => {
  const input = responseFor([[1, 2], [3, 4, 5]], { headers: { 'content-length': '2', 'content-encoding': 'gzip' } });
  const env = loaderContext({ fetch: async () => input.response });
  const loader = new env.Preloader();
  const progress = [];
  loader.setProgressFunc((loaded, total) => progress.push([loaded, total]));
  const bytes = await settled(loader.loadPromise('index.pck', 5));
  loader.animateProgress();
  assert(bytes instanceof ArrayBuffer);
  assert.deepEqual([...new Uint8Array(bytes)], [1, 2, 3, 4, 5]);
  assert.deepEqual(progress.at(-1), [5, 5]);
  assert.equal(env.clock.timers.size, 0, 'successful request must clear its inactivity timer');
});

test('raw WASM response is fully buffered and carries the correct MIME type', async () => {
  const env = loaderContext({ fetch: async () => responseFor([validWasm], { headers: { 'content-type': 'text/plain' } }).response });
  const result = await settled(new env.Preloader().loadPromise('index.wasm', 8, true));
  assert(result instanceof Response);
  assert.equal(result.headers.get('content-type'), 'application/wasm');
  assert.deepEqual([...new Uint8Array(await result.arrayBuffer())], [...validWasm]);
  assert.equal(env.clock.timers.size, 0);
});

test('raw response does not resolve while the source reader is unfinished', async () => {
  const finalRead = deferred();
  const env = loaderContext({ fetch: async () => responseFor([validWasm, finalRead.promise]).response });
  let done = false;
  const promise = new env.Preloader().loadPromise('index.wasm', 8, true).then((result) => { done = true; return result; });
  await flush();
  assert.equal(done, false, 'returning an unconsumed streaming response revives the Safari race');
  finalRead.resolve({ done: true });
  await settled(promise);
  assert.equal(done, true);
});

test('fetch rejection propagates without a hidden retry loop', async () => {
  const env = loaderContext({ fetch: async () => { throw new Error('offline fixture'); } });
  await rejects(settled(new env.Preloader().loadPromise('index.wasm', 8)), /offline fixture/);
  assert.equal(env.fetchCalls.length, 1);
  assert.equal(env.clock.timers.size, 0);
});

test('non-2xx HTTP response rejects', async () => {
  const env = loaderContext({ fetch: async () => responseFor([], { ok: false, status: 503 }).response });
  await rejects(settled(new env.Preloader().loadPromise('index.wasm', 8)));
  assert.equal(env.clock.timers.size, 0);
});

test('response with no readable body rejects with no lingering timer', async () => {
  const env = loaderContext({ fetch: async () => responseFor([], { noBody: true }).response });
  await rejects(settled(new env.Preloader().loadPromise('index.wasm', 8)));
  assert.equal(env.clock.timers.size, 0);
});

test('reader failure reaches the caller rather than hanging a replacement stream', async () => {
  const env = loaderContext({ fetch: async () => responseFor([[1, 2], new Error('reader fixture')]).response });
  await rejects(settled(new env.Preloader().loadPromise('index.wasm', 8)), /reader fixture/);
  assert.equal(env.clock.timers.size, 0);
});

for (const [name, bytes] of [['truncated', [1, 2]], ['oversized', [1, 2, 3, 4, 5]]]) {
  test(`${name} decoded file rejects exact-size validation`, async () => {
    const env = loaderContext({ fetch: async () => responseFor([bytes]).response });
    await rejects(settled(new env.Preloader().loadPromise('index.pck', 4)));
    assert.equal(env.clock.timers.size, 0);
  });
}

test('unknown expected size does not validate against compressed Content-Length', async () => {
  const env = loaderContext({ fetch: async () => responseFor([[1, 2, 3, 4]], { headers: { 'content-length': '2', 'content-encoding': 'gzip' } }).response });
  const result = await settled(new env.Preloader().loadPromise('unknown.pck', 0));
  assert.deepEqual([...new Uint8Array(result)], [1, 2, 3, 4]);
});

test('preload preserves the requested path and downloaded bytes', async () => {
  const env = loaderContext({ fetch: async () => responseFor([[5, 6, 7]]).response });
  const loader = new env.Preloader();
  await settled(loader.preload('source.pck', '/game.pck', 3));
  assert.equal(loader.preloadedFiles.length, 1);
  assert.equal(loader.preloadedFiles[0].path, '/game.pck');
  assert.deepEqual([...new Uint8Array(loader.preloadedFiles[0].buffer)], [5, 6, 7]);
});

test('failed preload does not register an incomplete file', async () => {
  const env = loaderContext({ fetch: async () => responseFor([[5]]).response });
  const loader = new env.Preloader();
  await rejects(settled(loader.preload('source.pck', '/game.pck', 3)));
  assert.equal(loader.preloadedFiles.length, 0);
});

test('preload retains existing ArrayBuffer and typed-view support without fetch', async () => {
  const env = loaderContext();
  const loader = new env.Preloader();
  const buffer = Uint8Array.of(7, 8).buffer;
  const view = Uint8Array.of(9, 10);
  await loader.preload(buffer, '/buffer.bin');
  await loader.preload(view, '/view.bin');
  assert.equal(loader.preloadedFiles[0].buffer, buffer);
  assert.equal(loader.preloadedFiles[1].buffer, view);
  assert.equal(env.fetchCalls.length, 0);
  await rejects(loader.preload({ unsupported: true }, '/bad.bin'));
});

test('45-second fetch inactivity aborts and rejects', async () => {
  let signal;
  const env = loaderContext({ fetch: (_url, options) => {
    signal = options.signal;
    return new Promise((_, reject) => signal.addEventListener('abort', () => reject(new DOMException('Aborted fixture', 'AbortError'))));
  } });
  const promise = new env.Preloader().loadPromise('index.wasm', 8);
  const rejection = rejects(settled(promise, 'fetch inactivity timeout'));
  await flush();
  assert(signal instanceof AbortSignal, 'fetch must receive an abort signal');
  await env.clock.advance(44999);
  assert.equal(signal.aborted, false);
  await env.clock.advance(1);
  await rejection;
  assert.equal(signal.aborted, true);
  assert.equal(env.clock.timers.size, 0);
});

test('45-second reader inactivity cancels the reader and cannot become a false success', async () => {
  const stuckRead = deferred();
  const input = responseFor([[1], stuckRead.promise], { onCancel: () => stuckRead.resolve({ done: true }) });
  let signal;
  const env = loaderContext({ fetch: async (_url, options) => { signal = options.signal; return input.response; } });
  const promise = new env.Preloader().loadPromise('unknown.pck', 0);
  const rejection = rejects(settled(promise, 'reader inactivity timeout'));
  await flush();
  await env.clock.advance(45000);
  await rejection;
  assert.equal(signal.aborted, true);
  assert(input.state.cancels >= 1, 'stalled reader must be cancelled');
  assert.equal(env.clock.timers.size, 0);
});

test('timeout rejection does not depend on fetch honoring AbortSignal', async () => {
  const env = loaderContext({ fetch: () => new Promise(() => {}) });
  const rejection = rejects(settled(new env.Preloader().loadPromise('ignored-abort.wasm', 8)), /45/);
  await flush();
  await env.clock.advance(45000);
  await rejection;
  assert.equal(env.clock.timers.size, 0);
});

test('timeout rejection does not depend on the reader honoring cancellation', async () => {
  const input = responseFor([[1], new Promise(() => {})]);
  const env = loaderContext({ fetch: async () => input.response });
  const rejection = rejects(settled(new env.Preloader().loadPromise('ignored-cancel.pck', 0)), /45/);
  await flush();
  await env.clock.advance(45000);
  await rejection;
  assert(input.state.cancels >= 1);
  assert.equal(env.clock.timers.size, 0);
});

test('empty chunks do not falsely reset the no-data timeout', async () => {
  const next = deferred();
  const input = responseFor([[1], next.promise, new Promise(() => {})]);
  const env = loaderContext({ fetch: async () => input.response });
  const rejection = rejects(settled(new env.Preloader().loadPromise('empty-chunks.pck', 0)), /45/);
  await flush();
  await env.clock.advance(44000);
  next.resolve({ done: false, value: new Uint8Array(0) });
  await flush();
  await env.clock.advance(1000);
  await rejection;
});

test('download activity refreshes the inactivity deadline, not a fixed total-duration limit', async () => {
  const second = deferred();
  const last = deferred();
  const input = responseFor([[1], second.promise, last.promise]);
  let signal;
  const env = loaderContext({ fetch: async (_url, options) => { signal = options.signal; return input.response; } });
  const promise = new env.Preloader().loadPromise('slow.pck', 2);
  await flush();
  await env.clock.advance(44000);
  second.resolve({ done: false, value: Uint8Array.of(2) });
  await flush();
  await env.clock.advance(44000);
  assert.equal(signal.aborted, false, 'active 88-second transfer must not be timed out');
  last.resolve({ done: true });
  assert.deepEqual([...new Uint8Array(await settled(promise))], [1, 2]);
  assert.equal(env.clock.timers.size, 0);
});

test('module configuration delegates buffered WASM compilation to Emscripten', () => {
  const env = loaderContext();
  const config = new env.InternalConfig({ executable: 'index' });
  const moduleConfig = config.getModuleConfig('index', validWasm);
  assert(moduleConfig.wasmBinary instanceof Uint8Array);
  assert.deepEqual([...moduleConfig.wasmBinary], [...validWasm]);
  assert.equal('instantiateWasm' in moduleConfig, false, 'custom unhandled instantiateWasm must be removed');
});

test('Engine.init passes complete validated bytes and waits for filesystem initialization', async () => {
  const initFs = deferred();
  let configSeen;
  let pathsSeen;
  const runtime = { initFS(paths) { pathsSeen = paths; return initFs.promise; } };
  const env = loaderContext({ Godot: async (config) => { configSeen = config; return runtime; } });
  const engine = new env.Engine({ executable: 'index', fileSizes: { 'index.wasm': 8 }, persistentPaths: ['/save'], unloadAfterInit: false });
  let complete = false;
  const promise = engine.init('index').then(() => { complete = true; });
  await new Promise((resolve) => setImmediate(resolve));
  await flush();
  assert.deepEqual([...configSeen.wasmBinary], [...validWasm]);
  assert.deepEqual(Array.from(pathsSeen), ['/save']);
  assert.equal(complete, false);
  initFs.resolve();
  await settled(promise);
  assert.equal(engine.rtenv, runtime);
});

test('Engine.init rejects a failed WASM download before calling Godot', async () => {
  let called = false;
  const env = loaderContext({ fetch: async () => { throw new Error('engine download fixture'); }, Godot: async () => { called = true; } });
  const engine = new env.Engine({ fileSizes: { 'index.wasm': 8 } });
  await rejects(settled(engine.init('index')), /engine download fixture/);
  assert.equal(called, false);
});

test('Engine.init propagates real WebAssembly compilation failure', async () => {
  const broken = Uint8Array.of(1, 2, 3, 4);
  const env = loaderContext({
    fetch: async () => responseFor([broken]).response,
    Godot: (config) => WebAssembly.instantiate(config.wasmBinary, {}),
  });
  const engine = new env.Engine({ fileSizes: { 'index.wasm': 4 } });
  await rejects(settled(engine.init('index')), (error) => error instanceof WebAssembly.CompileError);
});

test('Engine.init propagates rejected Godot initialization', async () => {
  const env = loaderContext({ Godot: async () => { throw new Error('Godot fixture'); } });
  const engine = new env.Engine({ fileSizes: { 'index.wasm': 8 } });
  await rejects(settled(engine.init('index')), /Godot fixture/);
});

test('Engine.init propagates rejected initFS', async () => {
  const env = loaderContext({ Godot: async () => ({ initFS: async () => { throw new Error('filesystem fixture'); } }) });
  const engine = new env.Engine({ fileSizes: { 'index.wasm': 8 } });
  await rejects(settled(engine.init('index')), /filesystem fixture/);
});

test('Engine.startGame rejects a truncated PCK without starting the game', async () => {
  let started = false;
  const env = loaderContext({
    fetch: async (url) => responseFor([url.endsWith('.wasm') ? validWasm : [1]]).response,
    Godot: async () => ({ initFS: async () => {}, callMain() { started = true; } }),
  });
  const engine = new env.Engine({ executable: 'index', fileSizes: { 'index.wasm': 8, 'index.pck': 3 } });
  await rejects(settled(engine.startGame()));
  assert.equal(started, false);
});

test('Engine.startGame delivers the validated PCK to the runtime before callMain', async () => {
  const calls = [];
  const runtime = {
    initFS: async () => {},
    initConfig(config) { calls.push(['config', config]); },
    copyToFS(file, bytes) { calls.push(['copy', file, [...new Uint8Array(bytes)]]); },
    callMain(args) { calls.push(['main', Array.from(args)]); },
  };
  const env = loaderContext({
    fetch: async (url) => responseFor([url.endsWith('.wasm') ? validWasm : [1, 2, 3]]).response,
    Godot: async () => runtime,
  });
  class Canvas { constructor() { this.tabIndex = -1; } }
  env.context.HTMLCanvasElement = Canvas;
  const engine = new env.Engine({
    canvas: new Canvas(), executable: 'index',
    fileSizes: { 'index.wasm': 8, 'index.pck': 3 },
  });
  await settled(engine.startGame());
  assert.deepEqual(calls.map((call) => call[0]), ['config', 'copy', 'main']);
  assert.deepEqual(calls[1], ['copy', 'index.pck', [1, 2, 3]]);
  assert.deepEqual(calls[2], ['main', ['--main-pack', 'index.pck']]);
  assert.equal(env.clock.timers.size, 0);
});

test('HTML includes failure listeners, a reload action, and an initialization watchdog', () => {
  assert.match(html, /addEventListener\s*\(\s*['"]error['"]/);
  assert.match(html, /addEventListener\s*\(\s*['"]unhandledrejection['"]/);
  assert.match(html, /(?:location\s*\.\s*reload|location\s*\[\s*['"]reload['"]\s*\])/);
  assert.match(html, /(?:120000|120_000|120\s*\*\s*1000)/);
  assert.match(html, /[А-Яа-яЁё]/, 'failure UI must include readable Russian text');
});

function shellContext(options = {}) {
  const clock = fakeClock();
  const startup = deferred();
  const listeners = new Map();
  const nodes = new Map();
  const state = { reloads: 0, starts: 0, startupOptions: null };
  class Element {
    constructor(tag = 'div') {
      this.tagName = tag.toUpperCase();
      this.children = [];
      this.style = {};
      this.hidden = false;
      this.removed = false;
      this.textContent = '';
      this.listeners = new Map();
    }
    get lastChild() { return this.children.at(-1) || null; }
    appendChild(node) { this.children.push(node); return node; }
    removeChild(node) { this.children.splice(this.children.indexOf(node), 1); }
    remove() { this.removed = true; }
    removeAttribute(name) { delete this[name]; }
    setAttribute(name, value) { this[name] = value; }
    addEventListener(type, fn) { this.listeners.set(type, fn); }
  }
  for (const id of ['canvas', 'status', 'status-progress', 'status-notice', 'load-detail', 'load-retry']) {
    const element = new Element(id === 'load-retry' ? 'button' : 'div');
    element.hidden = id === 'load-retry';
    nodes.set(id, element);
  }
  class Engine {
    constructor(config) { this.config = config; }
    static getMissingFeatures() { return options.missingFeatures || []; }
    startGame(config) { state.starts++; state.startupOptions = config; return startup.promise; }
  }
  const context = vm.createContext({
    Engine, Error, Promise,
    console: { log() {}, warn() {}, error() {} },
    navigator: {},
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    window: {
      location: { reload() { state.reloads++; } },
      addEventListener(type, fn) { listeners.set(type, fn); },
    },
    document: {
      getElementById: (id) => nodes.get(id),
      createElement: (tag) => new Element(tag),
      createTextNode: (text) => ({ textContent: text }),
    },
  });
  const scripts = [...html.matchAll(/<script\b[^>]*>([\s\S]*?)<\/script>/gi)].map((match) => match[1]).filter((text) => text.trim());
  assert(scripts.length > 0, 'HTML must contain its startup script');
  for (const script of scripts) vm.runInContext(script, context, { filename: htmlPath });
  const noticeText = () => nodes.get('status-notice').children.map((node) => node.textContent).join('');
  return { clock, startup, listeners, nodes, state, noticeText };
}

test('HTML displays the actual startup rejection and its reload button works', async () => {
  const env = shellContext();
  env.startup.reject(new Error('WASM startup fixture'));
  await flush();
  assert.equal(env.nodes.get('status-notice').style.display, 'block');
  assert.match(env.noticeText(), /WASM startup fixture/);
  assert.equal(env.nodes.get('load-retry').hidden, false);
  assert.match(env.nodes.get('load-detail').textContent, /[А-Яа-яЁё]/);
  env.nodes.get('load-retry').listeners.get('click')();
  assert.equal(env.state.reloads, 1);
  assert.equal(env.clock.timers.size, 0);
});

for (const type of ['error', 'unhandledrejection']) {
  test(`HTML ${type} listener turns a startup failure into a visible reason`, async () => {
    const env = shellContext();
    const error = new Error(`${type} fixture`);
    env.listeners.get(type)({ error, reason: error, message: error.message });
    await flush();
    assert.match(env.noticeText(), new RegExp(`${type} fixture`));
    assert.equal(env.nodes.get('load-retry').hidden, false);
    assert.equal(env.clock.timers.size, 0);
  });
}

test('HTML 120-second watchdog ends an otherwise pending startup', async () => {
  const env = shellContext();
  await env.clock.advance(119999);
  assert.equal(env.nodes.get('load-retry').hidden, true);
  await env.clock.advance(1);
  assert.equal(env.nodes.get('load-retry').hidden, false);
  assert.equal(env.nodes.get('status-notice').style.display, 'block');
  assert.match(env.noticeText(), /две минуты/);
  assert.equal(env.clock.timers.size, 0);
  env.startup.resolve();
  await flush();
  assert.equal(env.nodes.get('status').removed, false, 'late success must not hide an already reported failure');
});

test('HTML successful startup removes overlay and disarms stale startup errors', async () => {
  const env = shellContext();
  env.startup.resolve();
  await flush();
  assert.equal(env.nodes.get('status').removed, true);
  assert.equal(env.clock.timers.size, 0);
  await env.clock.advance(120000);
  env.listeners.get('unhandledrejection')({ reason: new Error('late unrelated fixture') });
  assert.equal(env.nodes.get('load-retry').hidden, true);
  assert.equal(env.noticeText(), '');
});

test('HTML progress distinguishes transfer from engine initialization', () => {
  const env = shellContext();
  env.state.startupOptions.onProgress(50, 100);
  assert.equal(env.nodes.get('status-progress').value, 50);
  assert.equal(env.nodes.get('status-progress').max, 100);
  assert.match(env.nodes.get('load-detail').textContent, /50%/);
  env.state.startupOptions.onProgress(100, 100);
  assert.match(env.nodes.get('load-detail').textContent, /Запускаем/);
});

test('HTML missing-feature branch exposes its reason without trying to start', () => {
  const env = shellContext({ missingFeatures: ['WebGL2 fixture'] });
  assert.equal(env.state.starts, 0);
  assert.match(env.noticeText(), /WebGL2 fixture/);
  assert.equal(env.nodes.get('load-retry').hidden, false);
});

(async () => {
  let failed = 0;
  for (const { name, fn } of tests) {
    try {
      await fn();
      console.log(`PASS ${name}`);
    } catch (error) {
      failed++;
      console.error(`FAIL ${name}\n${error.stack || error}`);
    }
  }
  console.log(`\n${tests.length - failed}/${tests.length} offline loader checks passed (${path.relative(root, jsPath)}).`);
  console.log('These mocked/offline checks do not constitute a real Safari, browser rendering, or owner playtest.');
  process.exitCode = failed ? 1 : 0;
})();
