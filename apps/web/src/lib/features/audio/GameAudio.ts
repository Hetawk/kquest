import { Howl } from 'howler';

export class GameAudio {
	private readonly ambient: Howl;
	private readonly tick: Howl;
	private readonly correct: Howl;
	private readonly incorrect: Howl;
	private readonly completion: Howl;
	private readonly podium: Howl;
	private enabled = true;
	private started = false;
	private unlocked = false;
	private timerUrgency = 0;
	private masterVolume = 1;
	private ambientStopTimer: ReturnType<typeof setTimeout> | undefined;
	private podiumTimer: ReturnType<typeof setTimeout> | undefined;

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
		this.completion = new Howl({
			src: ['/audio/completion-chime.wav'],
			volume: 0.24,
			preload: true,
			onloaderror: handleLoadError
		});
		this.podium = new Howl({
			src: ['/audio/podium-reveal.wav'],
			volume: 0.28,
			preload: true,
			onloaderror: handleLoadError
		});
	}

	start() {
		const wasStarted = this.started;
		this.started = true;
		this.unlocked = true;
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
		if (!enabled) this.clearPodiumTimer();
		for (const sound of this.sounds()) {
			sound.mute(!enabled);
		}

		if (enabled && this.started) this.start();
		if (!enabled) this.ambient.pause();
	}

	setVolume(volume: number) {
		this.masterVolume = Math.max(0, Math.min(volume, 1));
		this.ambient.volume(0.12 * this.masterVolume);
		this.tick.volume((0.08 + this.timerUrgency * 0.22) * this.masterVolume);
		this.correct.volume(0.2 * this.masterVolume);
		this.incorrect.volume(0.16 * this.masterVolume);
		this.completion.volume(0.24 * this.masterVolume);
		this.podium.volume(0.28 * this.masterVolume);
	}

	playTick(urgency = 0) {
		if (!this.enabled || !this.started) return;
		this.tick.volume((0.08 + Math.max(0, Math.min(urgency, 1)) * 0.22) * this.masterVolume);
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

	playCompletionCue() {
		if (!this.enabled || !this.unlocked) return;
		this.completion.play();
	}

	playPodiumReveal() {
		if (!this.enabled || !this.unlocked) return;
		this.clearPodiumTimer();
		this.podiumTimer = setTimeout(() => {
			this.podiumTimer = undefined;
			if (this.enabled && this.unlocked) this.podium.play();
		}, 600);
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
		this.clearPodiumTimer();
		for (const sound of this.sounds()) {
			sound.stop();
			sound.unload();
		}
	}

	private sounds() {
		return [this.ambient, this.tick, this.correct, this.incorrect, this.completion, this.podium];
	}

	private clearAmbientStop() {
		if (!this.ambientStopTimer) return;
		clearTimeout(this.ambientStopTimer);
		this.ambientStopTimer = undefined;
	}

	private clearPodiumTimer() {
		if (!this.podiumTimer) return;
		clearTimeout(this.podiumTimer);
		this.podiumTimer = undefined;
	}

	private ambientTargetVolume() {
		return (0.12 + this.timerUrgency * 0.08) * this.masterVolume;
	}
}
