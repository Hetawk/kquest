<script lang="ts">
	let {
		enabled,
		volume,
		unavailable = false,
		needsGesture = false,
		notice = '',
		onToggle,
		onVolumeChange
	}: {
		enabled: boolean;
		volume: number;
		unavailable?: boolean;
		needsGesture?: boolean;
		notice?: string;
		onToggle: () => void;
		onVolumeChange: (volume: number) => void;
	} = $props();
</script>

<div class="sound-control">
	<button
		class="sound-toggle"
		type="button"
		aria-pressed={enabled && !needsGesture}
		disabled={unavailable}
		onclick={onToggle}
	>
		{unavailable
			? 'Sound unavailable'
			: needsGesture
				? 'Enable sound'
				: `Sound ${enabled ? 'on' : 'off'}`}
	</button>
	<label class="volume-control">
		<span>Volume</span>
		<input
			type="range"
			min="0"
			max="1"
			step="0.05"
			value={volume}
			aria-label="Sound volume"
			disabled={unavailable}
			oninput={(event) => onVolumeChange(Number(event.currentTarget.value))}
		/>
	</label>
	{#if unavailable || needsGesture}
		<span class="sound-notice" role="status">
			{notice ||
				(unavailable
					? 'Optional audio is unavailable; play can continue.'
					: 'Tap enable sound if your browser blocked playback.')}
		</span>
	{/if}
</div>

<style>
	.sound-control {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.65rem;
	}

	.sound-toggle {
		padding: 0.4rem 0.6rem;
		border: 1px solid var(--line);
		border-radius: 0.55rem;
		background: white;
		color: var(--ink-soft);
		font: inherit;
		font-size: 0.7rem;
		font-weight: 700;
		cursor: pointer;
	}

	.sound-toggle:hover:not(:disabled) {
		border-color: var(--gold-deep);
	}

	.sound-toggle:disabled {
		cursor: not-allowed;
		opacity: 0.65;
	}

	.volume-control {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		color: var(--ink-muted);
		font-size: 0.68rem;
		font-weight: 700;
	}

	.volume-control input {
		width: 5.5rem;
		accent-color: var(--gold-deep);
	}

	.sound-notice {
		flex-basis: 100%;
		color: var(--ink-muted);
		font-size: 0.68rem;
		line-height: 1.4;
	}
</style>
