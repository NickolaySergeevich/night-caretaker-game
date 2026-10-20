#!/usr/bin/env node
'use strict';
// Executes the actual exported 4.6.3 Sample implementation against a deterministic
// WebAudio graph/clock mock. These are contract tests, NOT browser/output listening.
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '..');
if (!process.argv[2]) { console.error('Usage: node scripts/test-caretaker-web-audio.cjs /absolute/or/relative/export/index.js'); process.exit(2); }
const exportPath = path.resolve(process.argv[2]);
const exported = fs.readFileSync(exportPath, 'utf8');
const from = exported.indexOf('var GodotAudio=');
const to = exported.indexOf(';function _godot_audio', from);
assert(from > 0 && to > from, 'exact exported Sample implementation can be extracted');
const engine = exported.slice(from, to + 1);
const adapter = fs.readFileSync(path.join(root, 'godot/scripts/caretaker_web_audio.js'), 'utf8');
class Param {
  constructor(value = 0) { this.value = value; this.events = []; }
  setValueAtTime(value, at) { this.value = value; this.events.push(['set',value,at]); }
  setTargetAtTime(value, at, smooth) { this.value = value; this.events.push(['target',value,at,smooth]); }
}
class GraphNode {
  constructor() { this.connections = []; this.gain = new Param(1); }
  connect(node, output = 0, input = 0) { this.connections.push({ node, output, input }); return node; }
  disconnect() { this.connections = []; this.disconnected = true; }
}
class Buffer {
  constructor(channels, length, sampleRate) { this.numberOfChannels = channels; this.length = length; this.sampleRate = sampleRate; this.duration = length/sampleRate; this.channels = Array.from({length:channels},()=>new Float32Array(length)); }
  copyToChannel(data,ch) { this.channels[ch].set(data); }
  getChannelData(ch) { return this.channels[ch]; }
}
class Source extends GraphNode {
  constructor(ctx) { super();this.ctx=ctx;this.playbackRate=new Param(1);this.events=new Map();this.loop=false;this.started=null;this.stopped=Infinity; }
  set buffer(value) {
    if (value !== null && this._bufferAssigned) throw new DOMException('AudioBufferSourceNode buffer already assigned non-null', 'InvalidStateError');
    this._buffer = value;
    if (value !== null) this._bufferAssigned = true;
  }
  get buffer() { return this._buffer; }
  addEventListener(type,fn) { if(!this.events.has(type))this.events.set(type,new Set());this.events.get(type).add(fn); }
  removeEventListener(type,fn) { this.events.get(type)?.delete(fn); }
  start(when=0,offset=0) { assert.equal(this.started,null,'source starts exactly once');this.started={when:Math.max(when,this.ctx.currentTime),offset}; }
  stop(when=0) { this.stopped=when||this.ctx.currentTime; }
  valueAt(time) { if(!this.started||time<this.started.when||time>=this.stopped)return 0;let pos=this.started.offset+(time-this.started.when);if(this.loop)pos%=this.buffer.duration;const i=Math.round(pos*this.buffer.sampleRate);return this.buffer.getChannelData(0)[i]||0; }
}
function fixture() {
  const sources=[];
  const ctx={currentTime:0,sampleRate:48000,destination:new GraphNode(),
    createBuffer:(...a)=>new Buffer(...a),createGain:()=>new GraphNode(),createChannelSplitter:()=>new GraphNode(),createChannelMerger:()=>new GraphNode(),
    createBufferSource(){const source=new Source(ctx);sources.push(source);return source;},
    createBiquadFilter(){const n=new GraphNode();n.frequency=new Param();n.Q=new Param();return n;},
    createPanner(){const n=new GraphNode();for(const a of ['X','Y','Z'])n['position'+a]=new Param();return n;}}
  const sandbox=vm.createContext({console,Float32Array,Int16Array,Int32Array,Map,Set,Promise,atob,Math,Number,
    GodotRuntime:{allocString:s=>s,free:()=>{},error:(...v)=>{throw new Error(v.join(' '));}},GodotConfig:{},AudioWorkletNode:class {constructor(){throw new Error('Opted-in Sample must not wait for a position worklet');}}});
  vm.runInContext(engine,sandbox);
  const audio=sandbox.GodotAudio;
  audio.ctx=ctx;audio.samples=new Map();audio.sampleNodes=new Map();audio.buses=[];audio.audioPositionWorkletNodes=[];audio.audioPositionWorkletPromise=Promise.resolve();audio.sampleFinishedCallback=()=>{};
  audio.Bus.create();
  assert.equal(vm.runInContext(adapter,sandbox),true);
  return {audio,ctx,sources,sandbox};
}
const tests=[];const test=(name,fn)=>tests.push({name,fn});
function impulsePCM() { return Array.from({length:3},(_,j)=>{const a=new Int16Array(17280);for(let i=0;i<a.length;i++)a[i]=i===8+j*4?12000:(i>100&&i<16000?500:0);return a;}); }
function base64(pcm){return global.Buffer.from(pcm.buffer).toString('base64');}
function register(f,id,info={},loopMode='disabled') {
  const b=f.ctx.createBuffer(2,96000,48000);b.getChannelData(0).fill(.1);b.getChannelData(1).fill(.1);
  f.audio.Sample.create({id,audioBuffer:b},{numberOfChannels:2,sampleRate:48000,loopMode});
  assert.equal(f.audio.caretaker.register(id,info),true);
}
function start(f,id,offset=0) {
  return f.audio.SampleNode.create({id:'node-'+id,streamObjectId:id,busIndex:0},{volume:Float32Array.from([.4,.4,0,0,0,0,0,0]),playbackRate:1,pitchScale:1,offset,start:true});
}
const flush=()=>Promise.resolve().then(()=>Promise.resolve());
function phrase(f,id='phrase',onsets=[9600,27840,50880]) {
  f.audio.caretaker.setup(48000,impulsePCM().map(base64));
  register(f,id,{onsets,frames:onsets.at(-1)+17280,normalization:1,spatial:true,position:[-2,0,-3],closed:true});return start(f,id);
}
test('real WebAudio single-assignment rule rejects rebinding and derived voices use one fresh source without ghost connections',async()=>{
  const f=fixture(),probe=f.ctx.createBufferSource(),buffer=f.ctx.createBuffer(1,32,48000);
  probe.buffer=buffer;assert.throws(()=>{probe.buffer=buffer;},{name:'InvalidStateError'});
  probe.buffer=null;assert.throws(()=>{probe.buffer=buffer;},{name:'InvalidStateError'});probe.disconnect();
  const n=phrase(f);await flush();assert(n.isStarted);assert.equal(f.audio.caretaker.errors.length,0);
  const started=f.sources.filter(s=>s.started);assert.equal(started.length,1);assert.equal(started[0],n._source);
  const unused=f.sources.filter(s=>!s.started);assert(unused.length>=2);assert(unused.every(s=>s.disconnected&&s.connections.length===0));
});
test('exact export exposes runtime PCM registration, snapshot copy and no-thread refill',()=>{
  assert(exported.includes('audioBuffer.copyToChannel(new Float32Array(subLeft),0,0)'));
  assert(exported.includes('this._source.buffer=this.getSample().getAudioBuffer()'));
  assert(exported.includes('out_callback(wpos,pending_samples)'));
});
test('capability gate rejects incompatible runtimes, repeated install is idempotent',()=>{
  assert.equal(vm.runInNewContext(adapter,{}),false);
  const f=fixture();const fn=f.audio.SampleNode.prototype.connectPositionWorklet;
  assert.equal(vm.runInContext(adapter,f.sandbox),true);assert.equal(f.audio.SampleNode.prototype.connectPositionWorklet,fn);
  assert.equal(f.audio.caretaker.register('bad',{onsets:[0],frames:999999999,normalization:1}),false);
});
test('phrase is an autonomous immutable AudioBuffer with exact attack spacing across 700 ms main-thread gap',async()=>{
  const f=fixture(),n=phrase(f);await flush();assert(n.isStarted);assert.equal(n._positionWorklet,null);
  const startTime=n._source.started.when;f.ctx.currentTime=.9; // no engine tick or message callback
  assert.equal(n._source.valueAt(startTime+.2+8/48000),12000/32768);
  assert.equal(n._source.valueAt(startTime+.58+12/48000),12000/32768);
  assert.equal(n._source.valueAt(startTime+1.06+16/48000),12000/32768);
  assert(Math.abs(n.getPlaybackPosition()-(.9-startTime))<1e-10);
});
test('cancel before asynchronous start stops all future attacks without replay',async()=>{
  const f=fixture();const n=phrase(f);const result=f.audio.caretaker.cancel('phrase');assert.equal(result.keep,0);await flush();assert.equal(f.audio.sampleNodes.size,0);assert(!n.isStarted);
});
test('partial cancellation uses audio clock, preserves complete first tail and removes future taps',async()=>{
  const f=fixture(),n=phrase(f);await flush();const old=n._source;const start=old.started.when;f.ctx.currentTime=start+.30;
  const result=f.audio.caretaker.cancel('phrase');assert.equal(result.keep,1);
  const at=old.stopped;assert.equal(n._source.started.when,at);assert(Math.abs(n._source.started.offset-(at-start))<1e-10);
  for(let i=0;i<17280;i++)assert.equal(n._source.buffer.getChannelData(0)[9600+i],old.buffer.getChannelData(0)[9600+i]);
  assert(n._source.buffer.getChannelData(0).slice(27840).every(x=>x===0));
  assert.equal(f.audio.sampleNodes.size,1);assert.equal(f.sources.filter(x=>x.started).length,2);
});
test('immediate pause, repeated pause/resume and cancel while paused never leak or restart the phrase',async()=>{
  const f=fixture(),n=phrase(f);n.pause(true);await flush();assert(!n.isStarted);assert(n.isPaused);n.pause(false);const first=n._source;f.ctx.currentTime=first.started.when+.31;n.pause(true);const paused=n.offset;
  f.ctx.currentTime+=2;n.pause(true);assert.equal(n.offset,paused);const result=f.audio.caretaker.cancel('phrase');assert.equal(result.keep,1);assert(n.isPaused);
  n.pause(false);const resumed=n._source;assert.equal(resumed.started.offset,paused);f.ctx.currentTime=resumed.started.when+.10;n.pause(true);assert(Math.abs(n.offset-(paused+.1))<1e-9);
  f.ctx.currentTime+=3;n.pause(false);assert(Math.abs(n._source.started.offset-(paused+.1))<1e-9);assert.equal(f.audio.sampleNodes.size,1);assert.equal(n._caretakerRetired.size,0,'repeated pause cannot retain ended sources indefinitely');
});
test('forward device loops use AudioBufferSource.loop, not main-thread ended callbacks',async()=>{
  const f=fixture();register(f,'fan',{},'forward');const n=start(f,'fan');await flush();assert.equal(n._source.loop,true);assert.equal(n._source.loopEnd,2);f.ctx.currentTime=15;assert(n.getPlaybackPosition()<2);assert.equal(n._source.valueAt(15),.10000000149011612);assert.equal(f.sources.length,1);
});
test('ordinary door PCM/pan/Master are unchanged; replies use one HRTF pan with bounded wall filtering',async()=>{
  const f=fixture();register(f,'door');const door=start(f,'door');const n=phrase(f);await flush();const master=f.audio.buses[0];master.setVolumeDb(-6);assert.equal(f.audio.buses.length,1);assert(!door._caretakerPanner);assert.equal(door._source.buffer.getChannelData(0)[0],.10000000149011612);
  door.setVolumes([master],Float32Array.from([.2,.4,0,0,0,0,0,0]));const db=door._sampleNodeBuses.get(master);assert.equal(db._l.gain.value,.20000000298023224);assert.equal(db._r.gain.value,.4000000059604645);
  n.setVolumes([master],Float32Array.from([.2,.4,0,0,0,0,0,0]));const nb=n._sampleNodeBuses.get(master);assert.equal(nb._l.gain.value,nb._r.gain.value);assert(Math.abs(nb._l.gain.value-Math.hypot(.2,.4))<1e-7);
  assert.equal(n._caretakerPanner.panningModel,'HRTF');assert.equal(n._caretakerPanner.rolloffFactor,0);assert.equal(n._caretakerFilter.frequency.value,2900);
  f.audio.caretaker.update('phrase',[3,0,4],false);assert.equal(n._caretakerPanner.positionX.value,3);assert.equal(n._caretakerPanner.positionZ.value,4);assert.equal(n._caretakerFilter.frequency.value,7200);
});
test('scene reset stops active and retired sources, clears registration and leaves Master intact',async()=>{
  const f=fixture(),n=phrase(f);await flush();f.ctx.currentTime=.31;f.audio.caretaker.cancel('phrase');register(f,'door');start(f,'door');await flush();f.audio.caretaker.reset();assert.equal(f.audio.sampleNodes.size,0);assert.equal(f.audio.caretaker.stats().registered,0);assert.equal(f.audio.buses.length,1);for(const s of f.sources)assert(s.disconnected);assert.equal(n._caretakerRetired.size,0);
});
test('soft palette attenuates high-frequency edges and attack without gain normalization; door source remains exact',async()=>{
  const f=fixture();register(f,'soft',{softKey:'step',cutoff:4700,attack:.01});const n=start(f,'soft');await flush();const a=n._source.buffer.getChannelData(0);assert.equal(a[0],0);assert(a[48]<.01);assert(a[480]>.09);assert(a.every(x=>x<=.10000001));
  const original=impulsePCM();f.audio.caretaker.setup(48000,original.map(base64),true);register(f,'soft-reply',{onsets:[0],frames:17280,normalization:1,spatial:true});const r=start(f,'soft-reply');await flush();assert(r._source.buffer.getChannelData(0)[8]<original[0][8]/32768*.01);assert(r._source.buffer.getChannelData(0).every(x=>Math.abs(x)<12000/32768));
});
test('dense overlap and attenuation retain integer PCM rounding without clipping',async()=>{
  const f=fixture();const pcm=[0,1,2].map(()=>{const a=new Int16Array(200);a.fill(-12000);return a;});f.audio.caretaker.setup(48000,pcm.map(base64));
  register(f,'dense',{onsets:[0,0,0,0,0,0],frames:200,normalization:.4323,spatial:true});const n=start(f,'dense');await flush();const expected=-Math.round(72000*.4323)/32768;assert.equal(n._source.buffer.getChannelData(0)[0],expected);assert(Math.abs(expected)<.95);
});
test('GDScript opts in only after version/resource/capability checks and keeps native fallback',()=>{
  const gd=fs.readFileSync(path.join(root,'godot/scripts/caretaker_audio.gd'),'utf8');
  assert(gd.includes('int(version.major) != 4 or int(version.minor) != 6 or int(version.patch) != 3'));
  assert(gd.includes('AudioServer.PLAYBACK_TYPE_SAMPLE if web_sample_active else AudioServer.PLAYBACK_TYPE_STREAM'));
  assert(gd.includes('FileAccess.file_exists(WEB_ADAPTER_PATH)'));assert(gd.includes('JSON.stringify(value)'));
  assert(gd.includes('if web_sample_active: _web_call("reset")'));assert(gd.includes('player.notification(NOTIFICATION_INTERNAL_PHYSICS_PROCESS)'));
});
test('actual exported JavaScriptBridge local eval sees GodotAudio closure and preserves 64-bit string IDs end to end',async()=>{
  const segment=(start,end)=>{const a=exported.indexOf(start);const b=exported.indexOf(end,a);assert(a>=0&&b>a);return exported.slice(a,b);};
  const evalSource=segment('function _godot_js_eval(', 'var IDHandler=');
  const registerSource=segment('function _godot_audio_sample_register_stream(', 'function _godot_audio_sample_set_');
  // Adjacent export functions are retained verbatim; none is a hand-written stand-in.
  const startSource=segment('function _godot_audio_sample_start(', 'function _godot_audio_sample_stop(');
  const writes=[],errors=[],heap=new Float32Array(408);heap.fill(.05,0,400);heap.set([.2,.4,0,0,0,0,0,0],400);
  const runtime={parseString:x=>x,allocString:x=>x,free:()=>{},setHeapValue:(_p,v,t)=>writes.push({value:v,type:t}),heapSub:(h,p,n)=>h.subarray(p/4,p/4+n),error:e=>errors.push(String(e))};
  const realm=vm.createContext({console,Float32Array,Int16Array,Int32Array,Map,Set,Promise,atob,Math,Number,GodotRuntime:runtime,HEAPF32:heap,GodotConfig:{}});
  const scoped=vm.runInContext('(function(){'+engine+evalSource+registerSource+startSource+';return {audio:GodotAudio,evalJs:_godot_js_eval,register:_godot_audio_sample_register_stream,start:_godot_audio_sample_start};})()',realm);
  const f=fixture();const a=scoped.audio;a.ctx=f.ctx;a.samples=new Map();a.sampleNodes=new Map();a.buses=[];a.audioPositionWorkletNodes=[];a.audioPositionWorkletPromise=Promise.resolve();a.sampleFinishedCallback=()=>{};a.Bus.create();
  assert.equal(scoped.evalJs('typeof GodotAudio',false,0),4);assert.equal(writes.at(-1).value,'object');
  assert.equal(scoped.evalJs('typeof GodotAudio',true,0),4);assert.equal(writes.at(-1).value,'undefined');
  assert.equal(scoped.evalJs(adapter,false,0),1);assert.equal(writes.at(-1).value,true);
  const resource='9223372036854775807',playback='9007199254740995';
  const command='JSON.stringify(GodotAudio.caretaker.register('+JSON.stringify(resource)+',{}))';
  assert.equal(scoped.evalJs(command,false,0),4);assert.equal(writes.at(-1).value,'true');
  scoped.register(resource,0,200,'disabled',0,0);assert(a.samples.has(resource));
  scoped.start(playback,resource,0,0,1,400*4);await flush();assert(a.sampleNodes.has(playback));assert.equal(a.sampleNodes.get(playback).streamObjectId,resource);assert(a.sampleNodes.get(playback)._caretakerInfo);
  assert.equal(scoped.evalJs('JSON.stringify(GodotAudio.caretaker.noSuchMethod())',false,0),0);assert.equal(errors.length,1);
  scoped.evalJs('JSON.stringify(GodotAudio.caretaker.cancel("missing"))',false,0);assert.equal(writes.at(-1).value,'null');
  a.caretaker.register('absent-node',{onsets:[0],frames:100,normalization:1});assert.equal(a.caretaker.cancel('absent-node'),null); // unprepared phrase is rejected
  a.caretaker.reset();assert.equal(a.sampleNodes.size,0);
});
test('real-source adapter preparation/cancel cost is measured separately from engine/WASM and rendering',async()=>{
  const pcm=[1,2,3].map(i=>{
    const bytes=fs.readFileSync(path.join(root,'godot/data/audio/knock_reply_0'+i+'.wav'));
    assert.equal(bytes.toString('ascii',0,4),'RIFF');let at=12;
    while(at+8<=bytes.length){const size=bytes.readUInt32LE(at+4);if(bytes.toString('ascii',at,at+4)==='data')return bytes.subarray(at+8,at+8+size).toString('base64');at+=8+size+(size%2);}
    throw new Error('Original reply WAV has no PCM chunk');
  });const f=fixture();const rows=[];
  for(let i=0;i<40;i++){
    let at=performance.now();f.audio.caretaker.setup(48000,pcm,true);const setup=performance.now()-at;
    register(f,'bench',{onsets:[9600,27840,50880],frames:68160,normalization:1,spatial:true,position:[-2,0,3],closed:true});
    at=performance.now();const n=start(f,'bench');await flush();const startMs=performance.now()-at;
    f.ctx.currentTime=n._sourceStartTime+.3;at=performance.now();f.audio.caretaker.cancel('bench');const cancelMs=performance.now()-at;
    rows.push({setup,startMs,cancelMs});f.audio.caretaker.reset();f.audio.samples.clear();f.sources.length=0;
  }
  const report={scope:process.version+' + deterministic graph mock, real source PCM. Excludes C++/WASM sample registration, actual WebAudio node cost, rendering and listening.',iterations:rows.length,metrics:{}};
  for(const key of ['setup','startMs','cancelMs']){const values=rows.map(r=>r[key]).sort((a,b)=>a-b);report.metrics[key]={p50_ms:values[Math.floor(values.length*.5)],p95_ms:values[Math.floor(values.length*.95)],max_ms:values.at(-1)};}
  fs.mkdirSync(path.join(root,'build/qa-audio-04'),{recursive:true});
  fs.writeFileSync(path.join(root,'build/qa-audio-04/adapter-node-cost.json'),JSON.stringify(report,null,2)+'\n');console.log('COST',JSON.stringify(report.metrics));assert.equal(f.audio.caretaker.errors.length,0);
});
(async()=>{let failures=0;for(const {name,fn} of tests){try{await fn();console.log('PASS',name);}catch(e){failures++;console.error('FAIL',name,e.stack);}}console.log(`WEB AUDIO CONTRACT ${tests.length} tests, ${failures} failures. Mock graph/clock over real exported Sample JS; NOT browser or listening acceptance.`);process.exitCode=failures?1:0;})();
