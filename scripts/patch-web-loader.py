#!/usr/bin/env python3
"""Harden the Godot 4.6.3 WEB shell, never the minified engine runtime.

The normal Godot streaming loader loses some rejected read/compile promises.
This version validates complete local assets before passing wasmBinary through
Emscripten's standard buffered compilation path. Exact anchors fail closed if
the upstream shell changes. No browser restrictions or feature checks change.
"""
from pathlib import Path
import argparse

PRELOADER = r'''const Preloader = function () {
    const loadingFiles = {};
    let progressFunc = null;
    function report() {
        const values = Object.values(loadingFiles);
        const total = values.every(v => v.total > 0) ? values.reduce((n,v) => n+v.total,0) : 0;
        if (progressFunc) progressFunc(values.reduce((n,v) => n+v.loaded,0),total);
    }
    this.animateProgress = report;
    this.setProgressFunc = function(callback) { progressFunc = callback; report(); };
    this.loadPromise = async function(file, expectedBytes = 0, raw = false) {
        const stat = loadingFiles[file] = {total:expectedBytes,loaded:0,done:false};
        const abort = new AbortController();
        let reader = null;
        let timer = null;
        let rejectTimeout;
        const timeout = new Promise((resolve,reject) => { rejectTimeout = reject; });
        const arm = function() {
            clearTimeout(timer);
            timer = setTimeout(function() {
                const error = new Error('Загрузка ' + file + ' остановилась: 45 секунд без данных.');
                rejectTimeout(error);
                abort.abort();
                if (reader) Promise.resolve(reader.cancel()).catch(() => {});
            },45000);
        };
        report(); arm();
        const download = async function() {
            const response = await fetch(file,{signal:abort.signal});
            if (!response.ok) throw new Error('Не удалось загрузить ' + file + ': HTTP ' + response.status);
            if (!response.body) throw new Error('Пустой ответ для ' + file);
            reader = response.body.getReader();
            const chunks = [];
            while (true) {
                const result = await reader.read();
                if (result.done) break;
                if (!result.value || !result.value.byteLength) continue;
                stat.loaded += result.value.byteLength;
                if (expectedBytes && stat.loaded > expectedBytes) throw new Error('Неверный размер ' + file);
                chunks.push(result.value);
                report(); arm();
            }
            if (expectedBytes && stat.loaded !== expectedBytes) {
                throw new Error('Неполная загрузка ' + file + ': ' + stat.loaded + ' из ' + expectedBytes + ' байт.');
            }
            const bytes = new Uint8Array(stat.loaded);
            let offset = 0;
            for (const chunk of chunks) { bytes.set(chunk,offset); offset += chunk.byteLength; }
            stat.done = true; report();
            return raw ? new Response(bytes,{headers:{'Content-Type':'application/wasm'}}) : bytes.buffer;
        };
        try { return await Promise.race([download(),timeout]); }
        finally {
            clearTimeout(timer);
            abort.abort();
            if (reader) Promise.resolve(reader.cancel()).catch(() => {});
        }
    };
    this.preloadedFiles = [];
    this.preload = function(pathOrBuffer,destPath,fileSize) {
        if (typeof pathOrBuffer === 'string') {
            return this.loadPromise(pathOrBuffer,fileSize).then(buffer => {
                this.preloadedFiles.push({path:destPath || pathOrBuffer,buffer});
            });
        }
        if (pathOrBuffer instanceof ArrayBuffer || ArrayBuffer.isView(pathOrBuffer)) {
            this.preloadedFiles.push({path:destPath,buffer:pathOrBuffer});
            return Promise.resolve();
        }
        return Promise.reject(new Error('Invalid object for preloading'));
    };
};'''

DO_INIT = '''function doInit(promise) {
                    // Keep all download, compile, and filesystem rejections in the chain.
                    return promise.then(response => response.arrayBuffer())
                        .then(bytes => Godot(me.config.getModuleConfig(loadPath,new Uint8Array(bytes))))
                        .then(module => module['initFS'](me.config.persistentPaths).then(() => {
                            me.rtenv = module;
                            if (me.config.unloadAfterInit) Engine.unload();
                        }));
                }
                '''

def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('Unexpected Godot shell: anchor count for ' + old[:70])
    return text.replace(old,new,1)

def patch_js(text):
    if 'const Preloader = function ()' in text:
        raise ValueError('Loader already patched')
    start=text.index('const Preloader = /** @constructor */ function () {')
    end=text.index('\n/**\n * An object used to configure',start)
    text=text[:start]+PRELOADER+'\n'+text[end:]
    text=once(text,'Config.prototype.getModuleConfig = function (loadPath, response) {\n\t\tlet r = response;',
              'Config.prototype.getModuleConfig = function (loadPath, wasmBytes) {')
    start=text.index("\t\t\t'instantiateWasm': function (imports, onSuccess) {")
    end=text.index("\t\t\t'locateFile':",start)
    text=text[:start]+"\t\t\t'wasmBinary': wasmBytes,\n"+text[end:]
    start=text.index('function doInit(promise) {')
    end=text.index('preloader.setProgressFunc',start)
    text=text[:start]+DO_INIT+text[end:]
    return text

def patch_html(text):
    text=once(text,'<html lang="en">','<html lang="ru">')
    text=once(text,'<div id="status-notice"></div>',
              '<div id="status-notice"></div>\n<div id="load-detail" role="status" aria-live="polite"></div>\n<button id="load-retry" hidden>Попробовать снова</button>')
    text=once(text,'\t\t</style>', '''#load-detail { position:absolute; bottom:16%; padding:0 24px; font:16px Arial,sans-serif; text-align:center; }
#load-retry { position:absolute; bottom:5%; padding:12px 22px; color:#131c1f; background:#d78c56; border:0; cursor:pointer; font:16px Arial,sans-serif; }
        </style>''')
    text=once(text,"\tlet initializing = true;",'''    const loadDetail = document.getElementById('load-detail');
    const retryButton = document.getElementById('load-retry');
    retryButton.addEventListener('click', () => window.location.reload());
    loadDetail.textContent = 'Загрузка ночной смены…';
    let startupTimer = null;
    let initializing = true;''')
    text=once(text,"\t\tif (mode === 'hidden') {", "\t\tif (mode === 'hidden') {\n            clearTimeout(startupTimer);")
    text=once(text,'\tfunction displayFailureNotice(err) {\n\t\tconsole.error(err);', '''    function displayFailureNotice(err) {
        if (!initializing) return;
        clearTimeout(startupTimer);
        retryButton.hidden = false;
        loadDetail.textContent = 'Смена ещё не началась. Можно попробовать загрузить её снова.';
        console.error(err);''')
    text=once(text,'\tconst missing = Engine.getMissingFeatures({', '''    window.addEventListener('error', event => {
        if (initializing) displayFailureNotice(event.error || event.message || 'Ошибка запуска.');
    });
    window.addEventListener('unhandledrejection', event => {
        if (initializing) displayFailureNotice(event.reason || 'Ошибка загрузки.');
    });
    const missing = Engine.getMissingFeatures({''')
    text=once(text,"\t\tsetStatusMode('progress');", "\t\tsetStatusMode('progress');\n        startupTimer = setTimeout(() => displayFailureNotice('Не удалось запустить игру за две минуты.'),120000);")
    text=once(text,'\t\t\t\t\tstatusProgress.max = total;', '''                    statusProgress.max = total;
                    loadDetail.textContent = current < total
                        ? 'Загрузка: ' + Math.min(100,Math.round(current/total*100)) + '% · ' + (current/1048576).toFixed(1) + ' / ' + (total/1048576).toFixed(1) + ' МБ'
                        : 'Файлы загружены. Запускаем смену…';''')
    return text

def main():
    parser=argparse.ArgumentParser();parser.add_argument('directory',type=Path);args=parser.parse_args()
    for filename,patch in [('index.js',patch_js),('index.html',patch_html)]:
        path=args.directory/filename;path.write_text(patch(path.read_text()))
    print('Applied reproducible Godot 4.6.3 buffered loader + bounded error UI')

if __name__=='__main__':main()
