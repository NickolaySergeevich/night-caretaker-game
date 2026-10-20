/* Caretaker's opt-in Godot 4.6.3 Sample adapter. Local experimental candidate.
 * Executed by JavaScriptBridge.eval(source, false), inside the exported runtime.
 * No patched/minified export, new AudioContext, timers, or AudioServer buses.
 * The stock driver still owns decoding, Sample lifetime, Master and ordinary pan.
 * Only streams explicitly registered below are adapted. Fail closed to Stream.
 */
(function installCaretakerAudio(audio) {
  'use strict';
  const VERSION = 'caretaker-sample-4.6.3-v1';
  if (!audio || !audio.SampleNode || !audio.Sample || !audio.Bus || !audio.ctx ||
      !audio.sampleNodes || !audio.samples || typeof audio.ctx.createBuffer !== 'function' ||
      typeof audio.ctx.createBufferSource !== 'function' ||
      typeof audio.ctx.createPanner !== 'function' || typeof audio.ctx.createBiquadFilter !== 'function' ||
      typeof audio.SampleNode.prototype.connectPositionWorklet !== 'function' ||
      typeof audio.SampleNode.prototype.getSampleNodeBus !== 'function' ||
      typeof audio.SampleNode.prototype.clear !== 'function') return false;
  if (audio.caretaker) return audio.caretaker.version === VERSION;
  const probe = audio.ctx.createPanner();
  if (!['X', 'Y', 'Z'].every(axis => probe['position' + axis] && typeof probe['position' + axis].setValueAtTime === 'function')) { probe.disconnect(); return false; }
  probe.disconnect();
  const streams = new Map();
  const softBuffers = new Map();
  let replyPCM = [];
  let replyFloat = [];
  let replyRate = 48000;
  const stockConnect = audio.SampleNode.prototype.connectPositionWorklet;
  const quantum = () => 128 / audio.ctx.sampleRate;
  const roundPCM = value => value < 0 ? -Math.round(-value) : Math.round(value);
  function decodePCM(encoded) {
    const binary = atob(encoded);
    if (!binary.length || binary.length % 2) throw new Error('Invalid reply PCM16');
    const pcm = new Int16Array(binary.length / 2);
    for (let i = 0; i < pcm.length; i++) pcm[i] = binary.charCodeAt(i * 2) | (binary.charCodeAt(i * 2 + 1) << 8);
    return pcm;
  }
  function soften(data, rate, cutoff, attackSeconds) {
    // Two non-resonant one-pole stages cannot overshoot the source range.
    // A raised-cosine attack avoids a hard edge, without normalizing/raising gain.
    const alpha = 1 - Math.exp(-2 * Math.PI * cutoff / rate);
    const attack = Math.max(1, Math.round(attackSeconds * rate));
    const result = new Float32Array(data.length);
    let first = 0, second = 0;
    for (let i = 0; i < data.length; i++) {
      first += alpha * (data[i] - first); second += alpha * (first - second);
      result[i] = second * (i < attack ? .5 - .5 * Math.cos(Math.PI * i / attack) : 1);
    }
    return result;
  }
  function softenBuffer(buffer, info) {
    const key = info.softKey + ':' + buffer.sampleRate + ':' + buffer.length;
    if (softBuffers.has(key)) return softBuffers.get(key);
    const result = audio.ctx.createBuffer(buffer.numberOfChannels, buffer.length, buffer.sampleRate);
    for (let channel = 0; channel < buffer.numberOfChannels; channel++) {
      result.copyToChannel(soften(buffer.getChannelData(channel), buffer.sampleRate, info.cutoff || 4700, info.attack || .010), channel);
    }
    // Only the finite in-game one-shot palette is cached, never runtime phrases.
    if (softBuffers.size < 24) softBuffers.set(key, result);
    return result;
  }
  function phraseBuffer(info, keep = info.onsets.length) {
    // PCM arithmetic deliberately matches compile_phrase, including round-half-away
    // from zero. Both the initial and cancelled sources use this same sample rate.
    const data = new Float32Array(info.frames);
    let previousEnd = 0;
    for (let tap = 0; tap < keep; tap++) {
      const source = replyFloat[tap % 3];
      const onset = info.onsets[tap];
      const count = Math.min(source.length, data.length - onset);
      const overlap = Math.max(0, Math.min(previousEnd - onset, count));
      // Preserve untouched PCM spans with native typed-array copies. Only actual
      // overlaps need scalar addition; never walk several seconds of silence.
      for (let i = 0; i < overlap; i++) data[onset + i] += source[i];
      data.set(source.subarray(overlap, count), onset + overlap);
      previousEnd = Math.max(previousEnd, onset + count);
    }
    if (info.normalization !== 1) for (let i = 0; i < data.length; i++) data[i] = roundPCM(data[i] * 32768 * info.normalization) / 32768;
    // HRTF takes mono; a non-HRTF/unsupported speaker layout keeps both stock
    // Sample channels instead of silently losing the right channel.
    const channels = info.spatial ? 1 : 2;
    const buffer = audio.ctx.createBuffer(channels, data.length, replyRate);
    for (let channel = 0; channel < channels; channel++) buffer.copyToChannel(data, channel);
    return buffer;
  }
  function setParam(param, value, smooth = true) {
    if (smooth && typeof param.setTargetAtTime === 'function') param.setTargetAtTime(value, audio.ctx.currentTime, .035);
    else param.setValueAtTime(value, audio.ctx.currentTime);
  }
  function spatial(node, info, smooth = true) {
    if (!node._caretakerPanner) return;
    const pos = info.position || [0, 0, -1];
    ['X', 'Y', 'Z'].forEach((axis, i) => setParam(node._caretakerPanner['position' + axis], pos[i], smooth));
    setParam(node._caretakerFilter.frequency, info.closed ? 2900 : 7200, smooth);
  }
  function connectSource(node) {
    node._source.disconnect();
    if (node._caretakerPanner) node._source.connect(node._caretakerFilter);
    else for (const bus of node._sampleNodeBuses.values()) node._source.connect(bus.getInputNode());
  }
  function configureSource(node) {
    const sample = node.getSample();
    // WebAudio permits only one non-null buffer assignment per source, even
    // before start(). Unchanged door/device sources already own this buffer.
    if (node._source.buffer !== node._caretakerBuffer) node._source.buffer = node._caretakerBuffer;
    node._source.playbackRate.value = node.getPlaybackRate() * node.getPitchScale();
    // Stock 4.6.3 restarts a forward loop from a JS ended callback. Hardware looping
    // is independent of that callback and cannot insert a long-frame seam.
    node._source.loop = sample.loopMode === 'forward';
    node._source.loopStart = 0;
    node._source.loopEnd = node._caretakerBuffer.duration;
    node._onended = () => {
      if (!node.isPaused && !node.isCanceled) node.stop();
    };
    node._source.addEventListener('ended', node._onended);
    connectSource(node);
  }
  function positionAt(node, at = audio.ctx.currentTime) {
    if (!node.isStarted || node.isPaused) return node.offset;
    const elapsed = Math.max(0, at - node._sourceStartTime) * node.getPlaybackRate() * node.getPitchScale();
    const position = node.offset + elapsed;
    return node._source.loop ? position % node._caretakerBuffer.duration : Math.min(position, node._caretakerBuffer.duration);
  }
  function detachSource(node, stopAt) {
    node._source.removeEventListener('ended', node._onended);
    if (node.isStarted) node._source.stop(stopAt);
  }
  function newSource(node, when, offset, retiring = true) {
    const old = node._source;
    if (retiring) node._caretakerRetired.add(old);
    else old.disconnect();
    node._source = audio.ctx.createBufferSource();
    node.offset = offset;
    configureSource(node);
    node._sourceStartTime = when;
    node._source.start(when, offset);
    node.isStarted = true;
    // Disconnect only once the old source ends. Disconnecting immediately would
    // remove the final render quantum before a scheduled replacement.
    if (retiring) old.addEventListener('ended', () => { old.disconnect(); node._caretakerRetired.delete(old); }, { once: true });
  }
  function adapt(node, info) {
    if (!node._source || !(node._sampleNodeBuses instanceof Map) ||
        !node.getSample().getAudioBuffer || !node._source.buffer) throw new Error('Godot Sample shape changed');
    node._source.removeEventListener('ended', node._onended);
    node._caretakerBuffer = info.onsets ? phraseBuffer(info) : (info.softKey ? softenBuffer(node._source.buffer, info) : node._source.buffer);
    if (node._source.buffer !== node._caretakerBuffer) {
      // The stock constructor already assigned its immutable snapshot. A derived
      // phrase/softened buffer needs a fresh, not-yet-started source, not a second
      // buffer assignment. The abandoned stock node must never remain connected.
      node._source.disconnect();
      node._source = audio.ctx.createBufferSource();
    }
    node._caretakerInfo = info;
    node._caretakerRetired = new Set();
    if (info.spatial) {
      node._caretakerFilter = audio.ctx.createBiquadFilter();
      node._caretakerFilter.type = 'lowpass';
      node._caretakerFilter.Q.value = .6;
      node._caretakerPanner = audio.ctx.createPanner();
      node._caretakerPanner.panningModel = 'HRTF';
      node._caretakerPanner.distanceModel = 'inverse';
      node._caretakerPanner.rolloffFactor = 0;
      node._caretakerFilter.connect(node._caretakerPanner);
      for (const bus of node._sampleNodeBuses.values()) node._caretakerPanner.connect(bus.getInputNode());
      // Preserve the engine's scalar gain/Master, replace only its left/right
      // direction with HRTF. Otherwise two independent pans would attenuate twice.
      const stockVolumes = node.setVolumes;
      node.setVolumes = function (buses, volumes) {
        const gains = Float32Array.from(volumes);
        for (let i = 0; i < gains.length; i += audio.MAX_VOLUME_CHANNELS) {
          const gain = Math.hypot(gains[i], gains[i + 1]);
          gains[i] = gain; gains[i + 1] = gain;
        }
        stockVolumes.call(this, buses, gains);
      };
      spatial(node, info, false);
    }
    configureSource(node);
    node.start = function () {
      if (this.isStarted || this.isPaused || this.isCanceled) return;
      this._sourceStartTime = audio.ctx.currentTime + 2 * quantum();
      this._source.start(this._sourceStartTime, this.offset);
      this.isStarted = true;
    };
    node.getPlaybackPosition = function () { return positionAt(this); };
    node._pause = function () {
      if (this.isPaused || this.isCanceled) return;
      // Stop against the same audio clock; never use the delayed Worklet message.
      this.offset = positionAt(this);
      this.isPaused = true;
      detachSource(this, audio.ctx.currentTime);
      this._source.disconnect();
      this.isStarted = false;
    };
    node._unpause = function () {
      if (!this.isPaused || this.isCanceled) return;
      this.isPaused = false;
      // The paused source may have ended long ago (or never started). Do not
      // retain it waiting for an ended event that cannot fire a second time.
      newSource(this, audio.ctx.currentTime + 2 * quantum(), this.offset, false);
    };
    const stockClear = node.clear;
    node.clear = function () {
      for (const old of this._caretakerRetired) { try { old.stop(); } catch (_) {} old.disconnect(); }
      this._caretakerRetired.clear();
      if (this._caretakerFilter) this._caretakerFilter.disconnect();
      if (this._caretakerPanner) this._caretakerPanner.disconnect();
      stockClear.call(this);
    };
  }
  // This hook runs in the stock constructor, after Sample/Master/pan nodes exist.
  // Other unregistered streams use the untouched engine implementation.
  audio.SampleNode.prototype.connectPositionWorklet = function (start) {
    const info = streams.get(this.streamObjectId);
    if (!info) return stockConnect.call(this, start);
    try {
      adapt(this, info);
      // AudioBufferSourceNode renders by itself. No position Worklet or frame
      // refill is required. The microtask lets the engine set initial pan/gain.
      return Promise.resolve().then(() => { if (start) this.start(); });
    } catch (error) {
      // Incompatibility is loud in diagnostics, never a silent claim of success.
      audio.caretaker.errors.push(String(error));
      return stockConnect.call(this, start);
    }
  };
  audio.caretaker = {
    version: VERSION, errors: [],
    setup(rate, sources, softenReplies = false) {
      if (!Number.isInteger(rate) || rate < 8000 || rate > 192000 || sources.length !== 3) return false;
      replyPCM = sources.map(decodePCM);
      if (softenReplies) replyPCM = replyPCM.map(pcm => {
        const filtered = soften(pcm, rate, 5200, .008);
        return Int16Array.from(filtered, roundPCM);
      });
      replyFloat = replyPCM.map(pcm => Float32Array.from(pcm, value => value / 32768));
      replyRate = rate; return true;
    },
    register(id, info = {}) {
      if (info.onsets && (replyPCM.length !== 3 || info.onsets.length < 1 || info.onsets.length > 6 ||
          !Number.isInteger(info.frames) || info.frames < 1 || info.frames > 8 * replyRate ||
          info.onsets.some((x, i, a) => !Number.isInteger(x) || x < 0 || x >= info.frames || (i && x < a[i - 1])) ||
          !(info.normalization > 0 && info.normalization <= 1))) return false;
      streams.set(String(id), info); return true;
    },
    release(id) { streams.delete(String(id)); },
    update(id, position, closed) {
      const info = streams.get(String(id)); if (!info) return false;
      info.position = position; info.closed = closed;
      for (const node of audio.sampleNodes.values()) if (node.streamObjectId === String(id)) spatial(node, info);
      return true;
    },
    cancel(id) {
      const info = streams.get(String(id)); if (!info || !info.onsets) return null;
      const node = [...audio.sampleNodes.values()].find(n => n.streamObjectId === String(id));
      if (!node || !node._caretakerInfo || node.isCanceled) return { ok: false, reason: 'sample not active' };
      const isRunning = node.isStarted && !node.isPaused;
      let at, cursor, frontier, keep = -1, prefix;
      // Prepare before committing a replacement time. If preparation crosses an
      // attack frontier, preserve that newly committed tap too. At most six taps.
      for (;;) {
        at = audio.ctx.currentTime + (isRunning ? 2 * quantum() : 0);
        cursor = positionAt(node, at);
        frontier = Math.round(cursor * replyRate);
        const committed = info.onsets.filter(onset => onset < frontier).length;
        if (!committed) { node.stop(); return { ok: true, keep: 0, frontier }; }
        if (committed === keep) break;
        keep = committed;
        prefix = phraseBuffer(info, keep);
      }
      node._caretakerBuffer = prefix;
      if (isRunning) {
        detachSource(node, at);
        newSource(node, at, cursor);
      }
      // Paused playback swaps only its future immutable buffer; no tail is played.
      return { ok: true, keep, frontier };
    },
    reset() {
      for (const node of [...audio.sampleNodes.values()]) if (streams.has(node.streamObjectId)) node.stop();
      streams.clear(); softBuffers.clear(); replyPCM = []; replyFloat = [];
    },
    stats() { return { version: VERSION, registered: streams.size, active: [...audio.sampleNodes.values()].filter(n => streams.has(n.streamObjectId)).length, errors: this.errors.slice() }; }
  };
  return true;
})(typeof GodotAudio === 'undefined' ? null : GodotAudio);
