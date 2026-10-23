<script lang="ts">
	import type { LeaderboardEntry } from '../types';
	import PodiumScene from './PodiumScene.svelte';

	let {
		entries,
		finalized,
		participantCount
	}: {
		entries: LeaderboardEntry[];
		finalized: boolean;
		participantCount: number;
	} = $props();
</script>

<section class="podium-card" aria-labelledby="podium-title">
	<div class="podium-heading">
		<div>
			<p class="eyebrow">{finalized ? 'Final results' : 'Standings so far'}</p>
			<h2 id="podium-title">The top three</h2>
		</div>
		<span class:final-badge={finalized} class="status-badge">
			{finalized ? 'Final' : 'Provisional'}
		</span>
	</div>

	{#if entries.length === 0}
		<p class="empty-state">The podium is ready. It will appear as players complete a quest.</p>
	{:else}
		<PodiumScene />
		<div class="podium" aria-label="Top three players">
			{#each [entries[1], entries[0], entries[2]] as entry, index (`${entry?.rank ?? 'empty'}-${index}`)}
				{#if entry}
					<article
						class="place-card"
						class:place-first={entry.rank === 1}
						class:place-second={entry.rank === 2}
						class:place-third={entry.rank === 3}
					>
						<span class="place-medal" aria-hidden="true"
							>{entry.rank === 1 ? '✦' : entry.rank === 2 ? 'Ⅱ' : 'Ⅲ'}</span
						>
						<span class="place-label"
							>{entry.rank === 1 ? '1st place' : entry.rank === 2 ? '2nd place' : '3rd place'}</span
						>
						<strong class="place-name">{entry.learner_name}</strong>
						<span class="place-score">{entry.score} <small>points</small></span>
					</article>
				{/if}
			{/each}
		</div>
	{/if}

	<p class="podium-footnote">
		{participantCount}
		{participantCount === 1 ? 'player' : 'players'}
		{finalized ? 'finished' : 'have finished'}.
		{#if !finalized}Standings can change as more players finish.{/if}
	</p>
</section>

<style>
	.podium-card {
		width: 100%;
		margin: 1.6rem 0;
		padding: clamp(1rem, 4vw, 1.5rem);
		border: 1px solid var(--line);
		border-radius: 1.1rem;
		background: linear-gradient(150deg, #fffdf8, #f8f4eb);
		text-align: left;
	}

	.podium-heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}

	.podium-heading .eyebrow {
		margin: 0;
	}
	.podium-heading h2 {
		margin: 0.3rem 0 0;
		font-size: 1.2rem;
	}

	.status-badge {
		padding: 0.36rem 0.62rem;
		border-radius: 99px;
		background: #f7ebd3;
		color: #775326;
		font-size: 0.68rem;
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.07em;
	}

	.final-badge {
		background: #e4f1e8;
		color: #276040;
	}
	.podium {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		align-items: end;
		gap: 0.55rem;
		margin-top: 1.2rem;
	}

	.place-card {
		display: flex;
		min-width: 0;
		min-height: 7rem;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.35rem;
		padding: 0.75rem 0.4rem;
		border: 1px solid #e8dfcd;
		border-radius: 0.8rem 0.8rem 0.35rem 0.35rem;
		background: white;
		text-align: center;
	}

	.place-first {
		grid-column: 2;
		min-height: 9rem;
		border-color: #cfa85d;
		background: #fffaf0;
		box-shadow: 0 8px 24px rgb(128 94 37 / 12%);
	}
	.place-second {
		grid-column: 1;
		min-height: 7.7rem;
	}
	.place-third {
		grid-column: 3;
	}
	.place-medal {
		color: var(--gold-deep);
		font-size: 1.25rem;
	}
	.place-label {
		color: var(--ink-muted);
		font-size: 0.67rem;
		font-weight: 700;
		text-transform: uppercase;
	}
	.place-name {
		max-width: 100%;
		overflow-wrap: anywhere;
		font-size: clamp(0.72rem, 2.5vw, 0.9rem);
	}
	.place-score {
		color: var(--navy);
		font-size: 0.9rem;
		font-weight: 800;
	}
	.place-score small {
		color: var(--ink-muted);
		font-size: 0.65rem;
		font-weight: 600;
	}
	.podium-footnote,
	.empty-state {
		margin: 1rem 0 0;
		color: var(--ink-muted);
		font-size: 0.76rem;
		line-height: 1.6;
	}
	.empty-state {
		margin-top: 1.4rem;
		text-align: center;
	}

	@media (prefers-reduced-motion: no-preference) {
		.place-card {
			animation: arrive 350ms ease both;
		}
		.place-first {
			animation-delay: 80ms;
		}
	}
</style>
