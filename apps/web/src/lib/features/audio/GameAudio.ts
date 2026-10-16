import { Howl } from 'howler';

export class GameAudio {
	private readonly ambient: Howl;
	private readonly tick: Howl;
	private readonly correct: Howl;
	private readonly incorrect: Howl;
	private enabled = true;
	private started = false;
	private timerUrgency = 0;
	private ambientStopTimer: ReturnType<typeof setTimeout> | undefined;

	constructor(
		onLoadError: () => void,
		onPlaybackBlocked: () => void = onLoadError,
		onPlaybackStarted: () => void = () => {}
	) {
		const handleLoadError = () => onLoadError();
		const handlePlaybackBlocked = () => onPlaybackBlocked();
		this.ambient = new Howl({
			src: ['/audio/ambient-pad.wav'],
			loop: true,
			volume: 0.12,
			preload: true,
			onloaderror: handleLoadError,
			onplayerror: handlePlaybackBlocked,
			onplay: onPlaybackStarted
		});
		this.tick = new Howl({
			src: ['/audio/soft-tick.wav'],
			volume: 0.08,
			preload: true,
			onloaderror: handleLoadError,
			onplayerror: handlePlaybackBlocked,
			onplay: onPlaybackStarted
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
		const wasStarted = this.started;
		this.started = true;
		if (!this.enabled) return;

		this.clearAmbientStop();
		if (this.ambient.playing()) {
			if (!wasStarted) {
				this.ambient.fade(this.ambient.volume(), this.ambientTargetVolume(), 700);
			}
		} else {
			this.ambient.volume(0);
			this.ambient.play();
			this.ambient.fade(0, this.ambientTargetVolume(), 1200);
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

	playTick(urgency = 0) {
		if (!this.enabled || !this.started) return;
		this.tick.volume(0.08 + Math.max(0, Math.min(urgency, 1)) * 0.22);
		this.tick.play();
	}

	setTimerUrgency(urgency: number) {
		this.timerUrgency = Math.max(0, Math.min(urgency, 1));
		if (!this.enabled || !this.started || !this.ambient.playing()) return;

		this.ambient.fade(this.ambient.volume(), this.ambientTargetVolume(), 450);
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

	private ambientTargetVolume() {
		return 0.12 + this.timerUrgency * 0.08;
	}
}
