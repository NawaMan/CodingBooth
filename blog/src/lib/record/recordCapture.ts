// recordCapture — the browser half of the VOD recorder's video: capture the slides tab,
// redraw every frame onto a canvas of exactly the output size, mix in the microphone,
// and record it to a file. See specs/VOD-RECORD-1.md ("Why this shape", 2–3).
//
// The decisions (container, bitrate, letterbox) are pure and live in timelineCore; this
// file is only the plumbing between browser APIs, and it is Chromium-first: it uses
// MediaStreamTrackProcessor/Generator to resize frames and the File System Access API to
// stream the file to disk. Each has a fallback that still records, with a warning.

import { extensionFor, letterbox, pickMime, sameAspect, videoBitrate } from './timelineCore';

export interface CaptureOptions {
	/** Output size in px — the video's exact frame size. */
	width: number;
	height: number;
	fps: number;
	/** Record the microphone too. */
	mic: boolean;
	micDeviceId?: string;
	/** Record the slides tab's own sound (a <Video> on a slide). */
	tabAudio: boolean;
}

/** Where the recorded bytes go: a file streamed to as it records, or memory (downloaded at
    the end). */
export interface FileSink {
	name: string;
	write(data: Blob): Promise<void>;
	close(): Promise<void>;
}

export interface Capture {
	mime: string;
	ext: string;
	/** The captured tab's frame size, as first seen. */
	sourceWidth: number;
	sourceHeight: number;
	/** Things the speaker should know before trusting the result. */
	warnings: string[];
	/** Start writing frames. Resolves once the recorder has actually started. */
	start(sink: FileSink | null): Promise<void>;
	/** Stop and finish the file. Resolves with the recording when it was kept in memory. */
	stop(): Promise<Blob | null>;
	/** Freeze the picture on the last frame (true) while the slides window changes page, so
	    the video cuts straight from one slide to the next instead of showing the blank page
	    in between; false lets frames through again. The video keeps its timing either way. */
	hold(on: boolean): void;
	/** Called once if the speaker ends the share from the browser's own UI. */
	onEnded(cb: () => void): void;
	/** Release everything without recording (a cancelled start). */
	dispose(): void;
}

/** Does this browser have what a recording needs at all? An empty string when it does. */
export function captureUnsupportedReason(): string {
	if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getDisplayMedia) {
		return 'This browser cannot capture a tab (no getDisplayMedia).';
	}
	if (typeof MediaRecorder === 'undefined') return 'This browser cannot record video (no MediaRecorder).';
	return '';
}

/** The extension the recording will have with these options — known before the share
    dialog, so a file can be chosen first. */
export function expectedExtension(opts: Pick<CaptureOptions, 'mic' | 'tabAudio'>): string {
	if (typeof MediaRecorder === 'undefined') return 'webm';
	return extensionFor(pickMime((t) => MediaRecorder.isTypeSupported(t), opts.mic || opts.tabAudio));
}

/** Ask for a file to stream the video into (File System Access API). null when the
    browser has no picker or the speaker cancelled — the recording is downloaded instead. */
export async function chooseVideoFile(suggestedName: string, ext: string): Promise<FileSink | null> {
	const picker = (window as unknown as { showSaveFilePicker?: (o: unknown) => Promise<FileSystemFileHandleLike> }).showSaveFilePicker;
	if (!picker) return null;
	try {
		const handle = await picker({
			suggestedName: `${suggestedName}.${ext}`,
			types: [{ description: 'Video', accept: { [ext === 'mp4' ? 'video/mp4' : 'video/webm']: [`.${ext}`] } }]
		});
		const writable = await handle.createWritable();
		let chain = Promise.resolve();
		return {
			name: handle.name,
			write(data: Blob) {
				chain = chain.then(() => writable.write(data));
				return chain;
			},
			async close() {
				await chain;
				await writable.close();
			}
		};
	} catch {
		return null; // cancelled
	}
}

interface FileSystemFileHandleLike {
	name: string;
	createWritable(): Promise<{ write(d: Blob): Promise<void>; close(): Promise<void> }>;
}

// The insertable-streams constructors are not in every lib.dom.
type ProcessorCtor = new (init: { track: MediaStreamTrack }) => { readable: ReadableStream<VideoFrame> };
type GeneratorCtor = new (init: { kind: 'video' }) => MediaStreamTrack & { writable: WritableStream<VideoFrame> };

/** Redraw every frame of `track` onto a `width×height` canvas, letterboxed in black, and
    return the resulting track, plus the switch that freezes it on its last frame. null when
    the browser lacks the APIs. */
function resizeTrack(
	track: MediaStreamTrack,
	width: number,
	height: number
): { track: MediaStreamTrack; hold: (on: boolean) => void } | null {
	const g = globalThis as unknown as { MediaStreamTrackProcessor?: ProcessorCtor; MediaStreamTrackGenerator?: GeneratorCtor };
	if (!g.MediaStreamTrackProcessor || !g.MediaStreamTrackGenerator || typeof OffscreenCanvas === 'undefined') return null;
	const processor = new g.MediaStreamTrackProcessor({ track });
	const generator = new g.MediaStreamTrackGenerator({ kind: 'video' });
	const canvas = new OffscreenCanvas(width, height);
	const ctx = canvas.getContext('2d', { alpha: false });
	if (!ctx) return null;
	ctx.imageSmoothingQuality = 'high';
	let held = false;
	let drawn = false;
	const resize = new TransformStream<VideoFrame, VideoFrame>({
		transform(frame, controller) {
			try {
				// Held: leave the canvas as it is and send it again under this frame's time.
				if (!held || !drawn) {
					const r = letterbox(frame.displayWidth, frame.displayHeight, width, height);
					ctx.fillStyle = '#000';
					ctx.fillRect(0, 0, width, height);
					ctx.drawImage(frame, r.x, r.y, r.width, r.height);
					drawn = true;
				}
				controller.enqueue(new VideoFrame(canvas, { timestamp: frame.timestamp }));
			} finally {
				frame.close();
			}
		}
	});
	processor.readable.pipeThrough(resize).pipeTo(generator.writable).catch(() => {
		/* the source ended — the generator ends with it */
	});
	return {
		track: generator,
		hold: (on) => {
			held = on;
		}
	};
}

/** Ask the speaker for the slides tab (and the mic), and build the recorder around it.
    Must be called from a click. Throws when the share is refused. */
export async function openCapture(opts: CaptureOptions): Promise<Capture> {
	const warnings: string[] = [];
	const display = await navigator.mediaDevices.getDisplayMedia({
		video: { frameRate: { ideal: opts.fps, max: opts.fps }, displaySurface: 'browser' },
		audio: opts.tabAudio,
		// Offer tabs first, never this Recorder window itself.
		preferCurrentTab: false,
		selfBrowserSurface: 'exclude',
		surfaceSwitching: 'exclude',
		systemAudio: 'exclude'
	} as DisplayMediaStreamOptions);

	const owned: MediaStreamTrack[] = [...display.getTracks()];
	let audioCtx: AudioContext | null = null;
	const release = () => {
		for (const t of owned) t.stop();
		void audioCtx?.close().catch(() => {});
	};

	try {
		const source = display.getVideoTracks()[0];
		if (!source) throw new Error('The share has no video.');
		const s = source.getSettings();
		const sourceWidth = s.width ?? 0;
		const sourceHeight = s.height ?? 0;
		if (s.displaySurface && s.displaySurface !== 'browser') {
			warnings.push(`You shared a ${s.displaySurface}, not a browser tab — the video shows exactly that.`);
		}

		const resized = resizeTrack(source, opts.width, opts.height);
		let video: MediaStreamTrack;
		let hold: (on: boolean) => void = () => {};
		if (resized) {
			video = resized.track;
			hold = resized.hold;
			owned.push(video);
		} else {
			video = source;
			warnings.push(`This browser cannot resize frames, so the video is the tab's own size (${sourceWidth}×${sourceHeight}), not ${opts.width}×${opts.height}.`);
		}
		if (sourceWidth && sourceHeight && !sameAspect(sourceWidth, sourceHeight, opts.width, opts.height)) {
			warnings.push(`The slides tab is ${sourceWidth}×${sourceHeight}, not the shape of ${opts.width}×${opts.height}, so the video has black bars. Make the window that shape (or full screen on a matching monitor) for an edge-to-edge picture.`);
		}

		// Sound: the tab's, the mic's, or both mixed into one track.
		const audioIn: MediaStreamTrack[] = [...display.getAudioTracks()];
		if (opts.tabAudio && audioIn.length === 0) warnings.push('The tab was shared without its sound (tick "Share tab audio" in the browser dialog).');
		if (opts.mic) {
			try {
				const mic = await navigator.mediaDevices.getUserMedia({
					audio: {
						deviceId: opts.micDeviceId ? { exact: opts.micDeviceId } : undefined,
						echoCancellation: true,
						noiseSuppression: true
					}
				});
				owned.push(...mic.getTracks());
				audioIn.push(...mic.getAudioTracks());
			} catch {
				warnings.push('The microphone was refused — recording without it.');
			}
		}
		let audioOut: MediaStreamTrack[] = audioIn;
		if (audioIn.length > 1) {
			audioCtx = new AudioContext();
			const mix = audioCtx.createMediaStreamDestination();
			for (const t of audioIn) audioCtx.createMediaStreamSource(new MediaStream([t])).connect(mix);
			audioOut = mix.stream.getAudioTracks();
			owned.push(...audioOut);
		}

		const mime = pickMime((t) => MediaRecorder.isTypeSupported(t), audioOut.length > 0);
		const recorder = new MediaRecorder(new MediaStream([video, ...audioOut]), {
			mimeType: mime || undefined,
			videoBitsPerSecond: videoBitrate(opts.width, opts.height, opts.fps),
			audioBitsPerSecond: 192_000
		});
		const chunks: Blob[] = [];
		let sink: FileSink | null = null;
		let writes = Promise.resolve();
		recorder.ondataavailable = (e) => {
			if (!e.data || e.data.size === 0) return;
			if (sink) {
				const s2 = sink;
				writes = writes.then(() => s2.write(e.data)).catch(() => {});
			} else chunks.push(e.data);
		};

		let endedCb: (() => void) | null = null;
		source.addEventListener('ended', () => endedCb?.());

		return {
			mime: recorder.mimeType || mime,
			ext: extensionFor(recorder.mimeType || mime),
			sourceWidth,
			sourceHeight,
			warnings,
			start(target) {
				sink = target;
				return new Promise((resolve, reject) => {
					recorder.onstart = () => resolve();
					recorder.onerror = (e) => reject((e as unknown as { error?: Error }).error ?? new Error('recorder error'));
					recorder.start(1000); // a chunk a second, so a long take streams to disk
				});
			},
			stop() {
				return new Promise((resolve) => {
					const finish = async () => {
						await writes;
						if (sink) await sink.close().catch(() => {});
						release();
						resolve(sink ? null : new Blob(chunks, { type: recorder.mimeType || mime || 'video/webm' }));
					};
					if (recorder.state === 'inactive') return void finish();
					recorder.onstop = () => void finish();
					recorder.stop();
				});
			},
			hold,
			onEnded(cb) {
				endedCb = cb;
			},
			dispose: release
		};
	} catch (e) {
		release();
		throw e;
	}
}

/** Hand a blob to the browser as a download. */
export function downloadBlob(blob: Blob, filename: string): void {
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = filename;
	document.body.appendChild(a);
	a.click();
	a.remove();
	setTimeout(() => URL.revokeObjectURL(url), 60_000);
}
