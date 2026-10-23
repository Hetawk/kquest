<script lang="ts">
	import type { LeaderboardEntry } from '../types';
	import CharacterAvatar from './CharacterAvatar.svelte';
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

	const podiumPlaces = $derived([
		entries.find((entry) => entry.rank === 2),
		entries.find((entry) => entry.rank === 1),
		entries.find((entry) => entry.rank === 3)
	]);
	const podiumCharacterKey = $derived(
		podiumPlaces.map((entry) => (entry ? (entry.avatar_id ?? 'fox') : '-')).join('|')
	);
	let renderedCharacterKey = $state('');
</script>

<section class="podium-card" aria-labelledby="podium-title">
	<div class="podium-heading">
		<div>
			<p class="eyebrow">{finalized ? 'Final results' : 'Standings so far'}</p>
			<h2 id="podium-title">{finalized ? 'Your champions' : 'Leading the quest'}</h2>
		</div>
		<span class:final-badge={finalized} class="status-badge">
			{finalized ? 'Final' : 'Provisional'}
		</span>
	</div>

	{#if entries.length === 0}
		<p class="empty-state">The podium is ready. It will appear as players complete a quest.</p>
	{:else}
		<div class="podium-stage" aria-label="Top three players">
			<span class="stage-sparkle sparkle-one" aria-hidden="true">✦</span>
			<span class="stage-sparkle sparkle-two" aria-hidden="true">✧</span>
			<div class="podium-places" class:scene-ready={renderedCharacterKey === podiumCharacterKey}>
				{#key podiumCharacterKey}
					<PodiumScene
						characterIds={podiumPlaces.map((entry) => (entry ? (entry.avatar_id ?? 'fox') : null))}
						onReady={() => (renderedCharacterKey = podiumCharacterKey)}
						onFailure={() => (renderedCharacterKey = '')}
					/>
				{/key}
				{#each podiumPlaces as entry, index (`${entry?.rank ?? 'empty'}-${index}`)}
					{@const rank = index === 1 ? 1 : index === 0 ? 2 : 3}
					{#if entry}
						<article
							class="winner"
							class:place-first={rank === 1}
							class:place-second={rank === 2}
							class:place-third={rank === 3}
						>
							<div class="winner-avatar">
								<CharacterAvatar avatarId={entry.avatar_id} size="large" />
							</div>
							<div class="podium-block" class:gold-block={rank === 1}>
								<span class="place-label"
									>{rank === 1 ? '1st place' : rank === 2 ? '2nd place' : '3rd place'}</span
								>
								<strong class="place-name">{entry.learner_name}</strong>
								<span class="place-score">{entry.score} <small>points</small></span>
							</div>
						</article>
					{:else}
						<div
							class="podium-placeholder"
							class:placeholder-first={rank === 1}
							class:placeholder-second={rank === 2}
							aria-hidden="true"
						></div>
					{/if}
				{/each}
			</div>
			<p class="stage-caption">A place on the podium, earned one answer at a time.</p>
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
		color: var(--gold-deep);
		font-size: 0.64rem;
		font-weight: 850;
		letter-spacing: 0.14em;
	}

	.podium-heading h2 {
		margin: 0.3rem 0 0;
		color: var(--navy);
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

	.podium-stage {
		position: relative;
		min-height: 18rem;
		overflow: hidden;
		margin-top: 1.15rem;
		padding: 1.25rem 0.75rem 0;
		border-radius: 1rem;
		background:
			radial-gradient(ellipse at 50% 95%, rgb(204 175 119 / 23%), transparent 54%),
			linear-gradient(180deg, #fffefa 0%, #fbf6eb 100%);
	}

	.podium-places {
		position: relative;
		position: relative;
		display: grid;
		height: 15.3rem;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		align-items: end;
		gap: clamp(0.4rem, 2vw, 1rem);
		max-width: 39rem;
		margin-inline: auto;
	}

	.winner {
		z-index: 1;
		display: flex;
		min-width: 0;
		height: 76%;
		flex-direction: column;
		align-items: center;
		justify-content: flex-end;
		animation: podium-arrive 600ms cubic-bezier(0.2, 0.75, 0.25, 1) both;
	}

	.winner.place-second {
		animation-delay: 120ms;
	}

	.winner.place-first {
		height: 100%;
		animation-delay: 0ms;
	}

	.winner.place-third {
		animation-delay: 240ms;
	}

	.winner-avatar {
		z-index: 2;
		display: grid;
		place-items: center;
		margin-bottom: -0.8rem;
		filter: drop-shadow(0 5px 5px rgb(32 34 42 / 14%));
		animation: avatar-pop 500ms 220ms cubic-bezier(0.2, 0.75, 0.25, 1) both;
	}

	.scene-ready .winner-avatar {
		visibility: hidden;
	}

	.winner.place-second .winner-avatar {
		animation-delay: 320ms;
	}

	.winner.place-third .winner-avatar {
		animation-delay: 440ms;
	}

	.podium-block,
	.podium-placeholder {
		position: relative;
		display: flex;
		width: 100%;
		min-height: 8.1rem;
		flex: 1;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 0.38rem;
		padding: 1.2rem 0.45rem 0.65rem;
		border: 1px solid #c7cbd0;
		border-radius: 0.55rem 0.55rem 0.2rem 0.2rem;
		background: linear-gradient(145deg, #f5f6f6 0%, #d7dbe0 100%);
		box-shadow:
			0 0.35rem 0 #aeb4ba,
			0 0.75rem 1.15rem rgb(51 50 45 / 10%);
		text-align: center;
	}

	.podium-block::before,
	.podium-placeholder::before {
		position: absolute;
		top: -0.55rem;
		right: -0.08rem;
		left: -0.08rem;
		height: 0.65rem;
		border: 1px solid #d9dbde;
		border-radius: 0.42rem 0.42rem 0.16rem 0.16rem;
		background: linear-gradient(180deg, #fff, #e5e7e9);
		content: '';
	}

	.place-first .podium-block {
		min-height: 10rem;
		border-color: #c59b4c;
		background: linear-gradient(145deg, #f4dfad, #d5ae66);
		box-shadow:
			0 0.35rem 0 #ae8340,
			0 0.8rem 1.4rem rgb(128 94 37 / 16%);
	}

	.place-first .podium-block::before {
		border-color: #d9b86f;
		background: linear-gradient(180deg, #fff3d2, #e8ca8d);
	}

	.winner.place-third .podium-block {
		border-color: #c88e68;
		background: linear-gradient(145deg, #efd0b8, #cc936d);
		box-shadow:
			0 0.35rem 0 #a56e4d,
			0 0.75rem 1.15rem rgb(51 50 45 / 10%);
	}

	.winner.place-third .podium-block::before {
		border-color: #d8aa8c;
		background: linear-gradient(180deg, #ffecdc, #e7b99b);
	}

	.podium-placeholder {
		height: 76%;
		min-height: 5.5rem;
		flex: none;
		opacity: 0.42;
	}

	.placeholder-first {
		height: 100%;
		min-height: 8rem;
	}

	.place-label {
		color: #5d5b57;
		font-size: clamp(0.6rem, 1.6vw, 0.7rem);
		font-weight: 800;
		text-transform: uppercase;
		letter-spacing: 0.06em;
	}

	.place-first .place-label {
		color: #674918;
	}

	.place-name {
		max-width: 100%;
		overflow-wrap: anywhere;
		color: #282a2d;
		font-size: clamp(0.72rem, 2.4vw, 0.95rem);
		line-height: 1.25;
	}

	.place-score {
		color: #233b6b;
		font-size: clamp(0.82rem, 2.6vw, 1rem);
		font-weight: 900;
	}

	.place-score small {
		color: #5d5b57;
		font-size: 0.65rem;
		font-weight: 650;
	}

	.stage-caption {
		margin: 0.65rem 0 0;
		color: var(--ink-muted);
		font-size: 0.67rem;
		text-align: center;
	}

	.stage-sparkle {
		position: absolute;
		z-index: 2;
		color: #b88b49;
		animation: sparkle 2.4s ease-in-out infinite;
	}

	.sparkle-one {
		top: 1.7rem;
		left: 24%;
		font-size: 1.25rem;
	}

	.sparkle-two {
		top: 3.4rem;
		right: 22%;
		font-size: 1.5rem;
		animation-delay: 900ms;
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

	@keyframes podium-arrive {
		from {
			opacity: 0;
			transform: translateY(1.2rem);
		}
		to {
			opacity: 1;
			transform: translateY(0);
		}
	}

	@keyframes avatar-pop {
		from {
			opacity: 0;
			transform: translateY(0.65rem) scale(0.8);
		}
		to {
			opacity: 1;
			transform: translateY(0) scale(1);
		}
	}

	@keyframes sparkle {
		50% {
			opacity: 0.35;
			transform: scale(0.82) rotate(12deg);
		}
	}

	@media (max-width: 440px) {
		.podium-stage {
			min-height: 16rem;
			padding-inline: 0.35rem;
		}

		.podium-places {
			height: 13.5rem;
			gap: 0.3rem;
		}

		.podium-block {
			padding-inline: 0.2rem;
		}

		.place-first .podium-block {
			min-height: 9rem;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.winner,
		.winner-avatar,
		.stage-sparkle {
			animation: none;
		}
	}
</style>
