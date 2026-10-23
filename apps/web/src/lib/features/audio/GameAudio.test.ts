import { afterEach, describe, expect, it, vi } from 'vitest';

const audioInstances = vi.hoisted(
	() =>
		[] as Array<{
			play: ReturnType<typeof vi.fn>;
			volume: ReturnType<typeof vi.fn>;
		}>
);

vi.mock('howler', () => ({
	Howl: class {
		play = vi.fn();
		volume = vi.fn().mockReturnValue(0.12);
		playing = vi.fn().mockReturnValue(false);
		fade = vi.fn();
		mute = vi.fn();
		pause = vi.fn();
		stop = vi.fn();
		unload = vi.fn();

		constructor() {
			audioInstances.push({ play: this.play, volume: this.volume });
		}
	}
}));

import { GameAudio } from './GameAudio';

afterEach(() => {
	vi.useRealTimers();
	audioInstances.length = 0;
});

describe('GameAudio', () => {
	it('applies the master volume to every original sound', () => {
		const audio = new GameAudio(vi.fn());

		audio.setVolume(0.5);

		expect(audioInstances).toHaveLength(6);
		expect(audioInstances.map((sound) => sound.volume.mock.calls.at(-1)?.[0])).toEqual([
			0.06, 0.04, 0.1, 0.08, 0.12, 0.14
		]);

		audio.dispose();
	});

	it('plays the completion cue only after activation and delays the podium reveal', () => {
		vi.useFakeTimers();
		const audio = new GameAudio(vi.fn());
		const completion = audioInstances[4];
		const podium = audioInstances[5];

		audio.playCompletionCue();
		audio.playPodiumReveal();
		expect(completion.play).not.toHaveBeenCalled();
		expect(podium.play).not.toHaveBeenCalled();

		audio.start();
		audio.playCompletionCue();
		audio.playPodiumReveal();
		expect(completion.play).toHaveBeenCalledOnce();
		expect(podium.play).not.toHaveBeenCalled();

		vi.advanceTimersByTime(600);
		expect(podium.play).toHaveBeenCalledOnce();
		audio.dispose();
	});
});
