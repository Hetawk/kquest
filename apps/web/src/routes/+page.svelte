<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import QuestOrb from '#lib/components/QuestOrb.svelte';
	import { getCurrentUser } from '#lib/features/activities/api.js';

	let showOrb = $state(false);
	let dashboardCheckError = $state('');

	onMount(() => {
		showOrb = true;
		void getCurrentUser()
			.then((user) => {
				if (user) window.location.replace(resolve('/dashboard'));
			})
			.catch((cause: unknown) => {
				dashboardCheckError =
					cause instanceof Error ? cause.message : 'Your sign-in could not be checked.';
			});
	});
</script>

<svelte:head>
	<title>KINGDOM Quest — Learning, made unforgettable</title>
</svelte:head>

<main>
	{#if dashboardCheckError}
		<p class="page-shell" role="status">{dashboardCheckError}</p>
	{/if}
	<section class="hero page-shell">
		<div class="hero-copy">
			<p class="eyebrow">A little wonder goes a long way</p>
			<h1>Make learning<br />feel like <span>an adventure.</span></h1>
			<p class="hero-description">
				Turn what you teach into moments learners want to come back to. Create a quick quest, share
				it with your people, and watch curiosity take the lead.
			</p>

			<div class="hero-actions">
				<a class="button button-primary" href={resolve('/create')}>
					Create your first quest
					<span aria-hidden="true">↗</span>
				</a>
				<a class="button button-outline" href={resolve('/join')}>
					<span class="play-icon" aria-hidden="true">▶</span>
					I have a game code
				</a>
			</div>

			<div class="hero-note">
				<span class="sparkle" aria-hidden="true">✦</span>
				<span>Built for brave questions and bright minds.</span>
			</div>
		</div>

		<div class="hero-art" aria-label="A golden 3D learning constellation">
			{#if showOrb}
				<QuestOrb />
			{:else}
				<div class="orb-placeholder" aria-hidden="true"></div>
			{/if}
			<div class="floating-card card-one" aria-hidden="true">
				<span class="card-icon correct">✓</span>
				<span><strong>Curiosity</strong><small>is always the right answer</small></span>
			</div>
			<div class="floating-card card-two" aria-hidden="true">
				<span class="card-icon streak">✦</span>
				<span><strong>Little wins</strong><small>add up to big growth</small></span>
			</div>
			<div class="art-glow" aria-hidden="true"></div>
		</div>
	</section>

	<section class="studio page-shell" aria-labelledby="studio-heading">
		<div class="studio-heading">
			<div>
				<p class="eyebrow">Your learning studio</p>
				<h2 id="studio-heading">Pick up where wonder begins.</h2>
			</div>
			<p>A great learning moment is only a couple of clicks away.</p>
		</div>

		<div class="studio-cards">
			<a class="studio-card create-card" href={resolve('/create')}>
				<span class="studio-card-top"
					><span class="tile-icon">✳</span><span>FOR EDUCATORS</span></span
				>
				<h3>Build a quest</h3>
				<p>Write questions, choose the right answers, and make something worth sharing.</p>
				<span class="card-link">Start creating <span aria-hidden="true">↗</span></span>
			</a>
			<a class="studio-card join-card" href={resolve('/join')}>
				<span class="studio-card-top"
					><span class="tile-icon">→</span><span>FOR LEARNERS</span></span
				>
				<h3>Jump into a game</h3>
				<p>Have a code? There’s a seat waiting for you. Bring your curiosity.</p>
				<span class="card-link">Enter a code <span aria-hidden="true">↗</span></span>
			</a>
			<div class="studio-card values-card">
				<span class="studio-card-top"
					><span class="tile-icon">✦</span><span>MADE TO MATTER</span></span
				>
				<h3>Practice with purpose</h3>
				<p>Friendly feedback, thoughtful play, and progress you can feel good about.</p>
				<span class="values-note">Purpose first. Always.</span>
			</div>
		</div>
	</section>

	<footer class="home-footer page-shell">
		<span>KINGDOM Quest <span aria-hidden="true">·</span> An EKD Digital product</span>
		<span>Make room for wonder.</span>
	</footer>
</main>

<style>
	.hero {
		position: relative;
		display: grid;
		min-height: 39rem;
		grid-template-columns: 1.04fr 0.96fr;
		align-items: center;
		gap: 1rem;
		padding-block: 3.2rem 2.8rem;
	}

	.hero-copy {
		position: relative;
		z-index: 2;
		padding-block: 2rem;
		animation: arrive 650ms cubic-bezier(0.18, 0.75, 0.25, 1) both;
	}

	h1 {
		margin: 1.35rem 0 1.1rem;
		font-family: Manrope, 'DM Sans', sans-serif;
		font-size: clamp(3.15rem, 6.3vw, 5.5rem);
		font-weight: 800;
		letter-spacing: -0.075em;
		line-height: 1.02;
	}

	h1 span {
		color: var(--navy);
	}

	.hero-description {
		max-width: 35rem;
		margin: 0;
		color: var(--ink-soft);
		font-size: clamp(1rem, 1.35vw, 1.12rem);
		line-height: 1.8;
	}

	.hero-actions {
		display: flex;
		flex-wrap: wrap;
		gap: 0.8rem;
		margin-top: 1.8rem;
	}

	.hero-actions .button {
		min-height: 3.25rem;
		padding-inline: 1.25rem;
	}

	.play-icon {
		font-size: 0.72rem;
	}

	.hero-note {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		margin-top: 2.3rem;
		color: var(--ink-muted);
		font-size: 0.82rem;
	}

	.sparkle {
		color: var(--gold-deep);
		font-size: 1rem;
	}

	.hero-art {
		position: relative;
		display: grid;
		min-width: 0;
		place-items: center;
	}

	.hero-art :global(.orb-scene) {
		z-index: 1;
	}

	.art-glow {
		position: absolute;
		z-index: 0;
		width: 75%;
		aspect-ratio: 1;
		border-radius: 50%;
		background: radial-gradient(circle, rgb(212 175 106 / 18%), transparent 68%);
		filter: blur(0.4rem);
	}

	.orb-placeholder {
		width: min(100%, 31rem);
		aspect-ratio: 1;
	}

	.floating-card {
		position: absolute;
		z-index: 2;
		display: flex;
		align-items: center;
		gap: 0.7rem;
		padding: 0.8rem 1rem 0.8rem 0.8rem;
		border: 1px solid rgb(255 255 255 / 80%);
		border-radius: 1rem;
		background: rgb(255 255 255 / 86%);
		box-shadow: 0 1rem 2.4rem rgb(35 31 24 / 12%);
		backdrop-filter: blur(14px);
		animation: arrive 600ms 200ms ease both;
	}

	.floating-card > span:last-child {
		display: grid;
		gap: 0.15rem;
	}

	.floating-card strong {
		font-size: 0.82rem;
	}

	.floating-card small {
		color: var(--ink-muted);
		font-size: 0.68rem;
	}

	.card-icon {
		display: grid;
		width: 2.2rem;
		height: 2.2rem;
		place-items: center;
		border-radius: 0.7rem;
		font-weight: 800;
	}

	.correct {
		background: #e6f3eb;
		color: var(--success);
	}

	.streak {
		background: #fbf0db;
		color: var(--gold-deep);
	}

	.card-one {
		top: 23%;
		right: -1%;
	}

	.card-two {
		bottom: 19%;
		left: -1%;
		animation-delay: 350ms;
	}

	.studio {
		padding-block: 2.3rem 4rem;
		border-top: 1px solid var(--line);
	}

	.studio-heading {
		display: flex;
		align-items: end;
		justify-content: space-between;
		gap: 2rem;
		margin-bottom: 1.5rem;
	}

	.studio-heading h2 {
		margin: 0.7rem 0 0;
		font-family: Manrope, sans-serif;
		font-size: clamp(1.55rem, 3vw, 2.2rem);
		font-weight: 800;
		letter-spacing: -0.05em;
	}

	.studio-heading > p {
		max-width: 18rem;
		margin: 0 0 0.2rem;
		color: var(--ink-muted);
		font-size: 0.85rem;
		line-height: 1.6;
	}

	.studio-cards {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 1rem;
	}

	.studio-card {
		display: flex;
		min-height: 14.3rem;
		flex-direction: column;
		padding: 1.35rem;
		border: 1px solid var(--line);
		border-radius: 1.1rem;
		background: white;
		text-decoration: none;
		transition:
			transform 200ms ease,
			box-shadow 200ms ease,
			border-color 200ms ease;
	}

	a.studio-card:hover {
		transform: translateY(-4px);
		border-color: #d9c8a4;
		box-shadow: 0 1.2rem 2.5rem rgb(35 31 24 / 8%);
	}

	.create-card {
		background: linear-gradient(145deg, #fff, #fbf6ea);
	}

	.join-card {
		background: linear-gradient(145deg, #fff, #f1f3fa);
	}

	.values-card {
		background: var(--navy-deep);
		color: white;
	}

	.studio-card-top {
		display: flex;
		align-items: center;
		gap: 0.55rem;
		color: var(--ink-muted);
		font-size: 0.62rem;
		font-weight: 800;
		letter-spacing: 0.11em;
	}

	.values-card .studio-card-top {
		color: rgb(255 255 255 / 62%);
	}

	.tile-icon {
		display: grid;
		width: 1.9rem;
		height: 1.9rem;
		place-items: center;
		border-radius: 0.6rem;
		background: white;
		color: var(--gold-deep);
		font-size: 1rem;
		box-shadow: 0 2px 8px rgb(35 31 24 / 7%);
	}

	.join-card .tile-icon {
		color: var(--navy);
	}

	.values-card .tile-icon {
		background: rgb(255 255 255 / 12%);
		color: #f1d59f;
	}

	.studio-card h3 {
		margin: 1rem 0 0.35rem;
		font-family: Manrope, sans-serif;
		font-size: 1.2rem;
		font-weight: 800;
		letter-spacing: -0.04em;
	}

	.studio-card p {
		max-width: 20rem;
		margin: 0;
		color: var(--ink-soft);
		font-size: 0.83rem;
		line-height: 1.6;
	}

	.values-card p {
		color: rgb(255 255 255 / 70%);
	}

	.card-link,
	.values-note {
		display: flex;
		align-items: center;
		gap: 0.45rem;
		margin-top: auto;
		padding-top: 1.1rem;
		color: var(--navy);
		font-size: 0.77rem;
		font-weight: 800;
	}

	.values-note {
		color: #f1d59f;
	}

	.home-footer {
		display: flex;
		justify-content: space-between;
		gap: 1rem;
		padding-block: 1.3rem 1.8rem;
		border-top: 1px solid var(--line);
		color: var(--ink-muted);
		font-size: 0.73rem;
	}

	@keyframes arrive {
		from {
			transform: translateY(12px);
			opacity: 0;
		}
		to {
			transform: translateY(0);
			opacity: 1;
		}
	}

	@media (max-width: 900px) {
		.hero {
			min-height: 34rem;
			grid-template-columns: 1.05fr 0.95fr;
		}

		.card-one {
			right: -2%;
		}

		.card-two {
			left: -4%;
		}
	}

	@media (max-width: 700px) {
		.hero {
			min-height: unset;
			grid-template-columns: 1fr;
			gap: 0;
			padding-top: 3rem;
		}

		.hero-copy {
			padding-block: 0;
		}

		h1 {
			font-size: clamp(3rem, 12vw, 4.8rem);
		}

		.hero-art {
			width: min(100%, 31rem);
			margin: -0.4rem auto 0;
		}

		.card-one {
			top: 22%;
			right: -1%;
		}

		.card-two {
			bottom: 18%;
			left: -1%;
		}

		.studio-heading {
			align-items: start;
			flex-direction: column;
			gap: 0.55rem;
		}

		.studio-cards {
			grid-template-columns: 1fr;
		}

		.studio-card {
			min-height: 12.5rem;
		}
	}

	@media (max-width: 420px) {
		.hero-actions {
			align-items: stretch;
			flex-direction: column;
		}

		.hero-actions .button {
			width: 100%;
		}

		.floating-card {
			gap: 0.5rem;
			padding: 0.55rem 0.7rem 0.55rem 0.55rem;
		}

		.floating-card strong {
			font-size: 0.72rem;
		}

		.floating-card small {
			font-size: 0.6rem;
		}

		.card-icon {
			width: 1.8rem;
			height: 1.8rem;
		}

		.home-footer {
			flex-direction: column;
		}
	}
</style>
