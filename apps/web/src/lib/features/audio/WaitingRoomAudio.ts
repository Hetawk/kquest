import { Howl } from 'howler';

export class WaitingRoomAudio {
	private readonly ambient: Howl;
	private enabled = true;
	private disposed = false;

	constructor(
		onLoadError: () => void,
		onPlaybackBlocked: () => void,
		onPlaybackStarted: () => void
	) {
		this.ambient = new Howl({
			src: ['/audio/ambient-pad.wav'],
			loop: true,
			volume: 0.09,
			preload: true,
			onloaderror: onLoadError,
			onplayerror: onPlaybackBlocked,
			onplay: onPlaybackStarted
		});
	}

	start() {
		if (this.disposed || !this.enabled || this.ambient.playing()) return;
		this.ambient.play();
	}

	stop() {
		if (!this.disposed) this.ambient.pause();
	}

	setEnabled(enabled: boolean) {
		this.enabled = enabled;
		this.ambient.mute(!enabled);
		if (enabled) this.start();
		else this.stop();
	}

	dispose() {
		this.disposed = true;
		this.ambient.stop();
		this.ambient.unload();
	}
}
