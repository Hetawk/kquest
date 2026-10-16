import { Howl } from 'howler';

export class GameAudio {
	private readonly ambient: Howl;
	private readonly tick: Howl;
	private readonly correct: Howl;
	private readonly incorrect: Howl;
	private enabled = true;
	private started = false;
	private ambientStopTimer: ReturnType<typeof setTimeout> | undefined;

	constructor(onLoadError: () => void) {
		const handleLoadError = () => onLoadError();
		this.ambient = new Howl({
			src: ['/audio/ambient-pad.wav'],
			loop: true,
			volume: 0.12,
			preload: true,
			onloaderror: handleLoadError
		});
		this.tick = new Howl({
			src: ['/audio/soft-tick.wav'],
			volume: 0.08,
			preload: true,
			onloaderror: handleLoadError
		});
		this.correct = new Howl({
			src: ['/audio/warm-chord.wav'],
			volume: 0.2,
			preload: true,
			onloaderror: handleLoadError
		});
		this.incorrect = new Howl({
			src: ['/audio/soft-thud.wav'],
			volume: 0.16,
			preload: true,
			onloaderror: handleLoadError
		});
	}

	start() {
		this.started = true;
		if (!this.enabled) return;

		this.clearAmbientStop();
		if (this.ambient.playing()) {
			this.ambient.fade(this.ambient.volume(), 0.12, 700);
		} else {
			this.ambient.volume(0);
			this.ambient.play();
			this.ambient.fade(0, 0.12, 1200);
		}
	}

	setEnabled(enabled: boolean) {
		this.enabled = enabled;
		this.clearAmbientStop();
		for (const sound of [this.ambient, this.tick, this.correct, this.incorrect]) {
			sound.mute(!enabled);
		}

		if (enabled && this.started) this.start();
		if (!enabled) this.ambient.pause();
	}

	playTick() {
		if (this.enabled && this.started) this.tick.play();
	}

	playAnswerCue(isCorrect: boolean) {
		if (!this.enabled || !this.started) return;
		(isCorrect ? this.correct : this.incorrect).play();
	}

	stopAmbient() {
		this.started = false;
		if (!this.ambient.playing()) return;
		if (!this.enabled) {
			this.ambient.pause();
			return;
		}

		this.ambient.fade(this.ambient.volume(), 0, 500);
		this.ambientStopTimer = setTimeout(() => this.ambient.pause(), 520);
	}

	dispose() {
		this.clearAmbientStop();
		for (const sound of [this.ambient, this.tick, this.correct, this.incorrect]) {
			sound.stop();
			sound.unload();
		}
	}

	private clearAmbientStop() {
		if (!this.ambientStopTimer) return;
		clearTimeout(this.ambientStopTimer);
		this.ambientStopTimer = undefined;
	}
}
