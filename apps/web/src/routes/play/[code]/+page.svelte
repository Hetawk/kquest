<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import { fetchActivity, submitAttempt } from '#lib/features/activities/api.js';
	import type { AttemptResult, PlayActivity } from '#lib/features/activities/types.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	let activity = $state<PlayActivity | null>(null);
	let attempt = $state<AttemptResult | null>(null);
	let learnerName = $state('');
	let currentQuestion = $state(0);
	let answers = $state<Record<string, string>>({});
	let loading = $state(true);
	let submitting = $state(false);
	let started = $state(false);
	let error = $state('');
	let submissionKey = $state('');
	let lockedPayload:
		| {
				learnerName: string;
				responses: { question_id: string; option_id: string }[];
		  }
		| undefined;

	onMount(async () => {
		try {
			activity = await fetchActivity(data.shareCode);
		} catch (cause) {
			error =
				cause instanceof Error
					? cause.message
					: 'We couldn’t find that game. Check the code and try again.';
		} finally {
			loading = false;
		}
	});

	function beginGame(event: SubmitEvent) {
		event.preventDefault();
		learnerName = learnerName.trim();
		if (learnerName.length > 0 && learnerName.length <= 80) {
			started = true;
			error = '';
		}
	}

	async function finishGame() {
		if (!activity || submitting || !allQuestionsAnswered) return;

		if (!submissionKey) {
			submissionKey = crypto.randomUUID();
			lockedPayload = {
				learnerName,
				responses: activity.questions.map((question) => ({
					question_id: question.id,
					option_id: answers[question.id]
				}))
			};
		}

		submitting = true;
		error = '';
		try {
			attempt = await submitAttempt({
				shareCode: activity.share_code,
				learnerName: lockedPayload!.learnerName,
				responses: lockedPayload!.responses,
				idempotencyKey: submissionKey
			});
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your answers could not be submitted.';
		} finally {
			submitting = false;
		}
	}

	const current = $derived(activity?.questions[currentQuestion]);
	const allQuestionsAnswered = $derived(
		activity !== null && activity.questions.every((question) => Boolean(answers[question.id]))
	);
	const percent = $derived(
		activity && current ? Math.round(((currentQuestion + 1) / activity.questions.length) * 100) : 0
	);
</script>

<svelte:head>
	<title>{activity ? `${activity.title} — KINGDOM Quest` : 'Play a quest — KINGDOM Quest'}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell play-page">
	{#if loading}
		<section class="play-card loading-card" aria-live="polite">
			<div class="loader" aria-hidden="true"></div>
			<p>Finding your adventure…</p>
		</section>
	{:else if !activity}
		<section class="play-card not-found">
			<div class="result-icon" aria-hidden="true">?</div>
			<p class="eyebrow">A little detour</p>
			<h1 class="page-heading">We can’t find that game.</h1>
			<p class="page-intro">{error}</p>
			<a class="button button-primary" href={resolve('/join')}>Check the game code</a>
		</section>
	{:else if attempt}
		<section class="play-card result-card" aria-labelledby="result-heading">
			<div class="result-icon" aria-hidden="true">
				{attempt.score === attempt.max_score ? '✦' : '✓'}
			</div>
			<p class="eyebrow">Quest complete</p>
			<h1 id="result-heading" class="result-heading">
				{attempt.score === attempt.max_score ? 'Brilliant work.' : 'Look how far you came.'}
			</h1>
			<p class="result-intro">
				Thanks for playing, {attempt.learner_name}. Every question is another chance to learn.
			</p>
			<div
				class="score-display"
				aria-label="Your score: {attempt.score} out of {attempt.max_score} points"
			>
				<strong>{attempt.score}</strong><span>/ {attempt.max_score} points</span>
			</div>

			<div class="answer-review">
				<h2>Your answers</h2>
				{#each attempt.results as result, index (result.question_id)}
					<article class="review-row">
						<span
							class="review-marker"
							class:review-correct={result.points_awarded > 0}
							aria-label={result.points_awarded > 0 ? 'Correct' : 'Keep learning'}
						>
							{result.points_awarded > 0 ? '✓' : '·'}
						</span>
						<div>
							<p class="review-question">{index + 1}. {result.prompt}</p>
							<p class="review-feedback">
								{result.points_awarded > 0
									? `You got it — ${result.points_awarded} points`
									: `The correct choice earned ${result.points_possible} points`}
							</p>
						</div>
					</article>
				{/each}
			</div>

			<a class="button button-primary" href={resolve('/join')}>Play another quest</a>
		</section>
	{:else if !started}
		<section class="play-card welcome-card" aria-labelledby="welcome-heading">
			<div class="quest-badge" aria-hidden="true">✦</div>
			<p class="eyebrow">A quest is calling</p>
			<h1 id="welcome-heading" class="page-heading">{activity.title}</h1>
			<p class="page-intro">
				{activity.questions.length}
				{activity.questions.length === 1 ? 'question' : 'questions'}. Your own pace. One curious
				mind.
			</p>

			<form class="welcome-form" onsubmit={beginGame}>
				<label class="field-label" for="learner-name">What should we call you?</label>
				<input
					id="learner-name"
					class="text-input learner-input"
					type="text"
					autocomplete="given-name"
					maxlength="80"
					placeholder="Your name"
					bind:value={learnerName}
					required
				/>
				<button class="button button-primary" type="submit">
					Let’s play <span aria-hidden="true">↗</span>
				</button>
			</form>
		</section>
	{:else if current}
		<section class="play-card question-card" aria-labelledby="question-heading">
			<div class="game-topline">
				<a href={resolve('/join')} class="exit-link">← Leave game</a>
				<span class="game-code">{activity.share_code}</span>
			</div>

			<div
				class="progress-track"
				role="progressbar"
				aria-label="Question progress"
				aria-valuemin="0"
				aria-valuemax="100"
				aria-valuenow={percent}
			>
				<span style="width: {percent}%"></span>
			</div>

			<div class="question-meta">
				<span
					>QUESTION {String(currentQuestion + 1).padStart(2, '0')} OF {String(
						activity.questions.length
					).padStart(2, '0')}</span
				>
				<span>{current.points} POINTS</span>
			</div>

			<h1 id="question-heading" class="question-prompt">{current.prompt}</h1>

			<fieldset class="answer-options">
				<legend>Choose the answer that feels right.</legend>
				{#each current.options as option, optionIndex (option.id)}
					<label class="answer-option" class:answer-selected={answers[current.id] === option.id}>
						<input
							type="radio"
							name="answer-{current.id}"
							value={option.id}
							checked={answers[current.id] === option.id}
							onchange={() => (answers[current.id] = option.id)}
						/>
						<span class="answer-letter" aria-hidden="true"
							>{String.fromCharCode(65 + optionIndex)}</span
						>
						<span class="answer-text">{option.text}</span>
						<span class="answer-check" aria-hidden="true">✓</span>
					</label>
				{/each}
			</fieldset>

			{#if error}<p class="error-message" role="alert">{error}</p>{/if}

			<div class="question-navigation">
				<button
					class="button button-outline"
					type="button"
					disabled={currentQuestion === 0 || submitting || Boolean(submissionKey)}
					onclick={() => (currentQuestion -= 1)}
				>
					← Previous
				</button>
				{#if currentQuestion < activity.questions.length - 1}
					<button
						class="button button-primary"
						type="button"
						disabled={!answers[current.id] || submitting || Boolean(submissionKey)}
						onclick={() => (currentQuestion += 1)}
					>
						Next question <span aria-hidden="true">→</span>
					</button>
				{:else}
					<button
						class="button button-primary"
						type="button"
						disabled={!allQuestionsAnswered || submitting}
						onclick={finishGame}
					>
						{submitting ? 'Checking your answers…' : 'See my score'}
						{#if !submitting}<span aria-hidden="true">✦</span>{/if}
					</button>
				{/if}
			</div>
			{#if submissionKey && error}
				<p class="retry-note">
					Your answers are saved on this device. Retry to safely check the same submission.
				</p>
				<button class="retry-button" type="button" disabled={submitting} onclick={finishGame}>
					{submitting ? 'Retrying…' : 'Retry submission'}
				</button>
			{/if}
		</section>
	{/if}
</main>

<style>
	.play-page {
		display: grid;
		min-height: calc(100vh - 5rem);
		place-items: center;
		padding-block: 2rem 4rem;
	}

	.play-card {
		width: min(100%, 46rem);
		padding: clamp(1.25rem, 5vw, 2.5rem);
		border: 1px solid var(--line);
		border-radius: 1.4rem;
		background: white;
		box-shadow: var(--shadow-card);
		animation: arrive 320ms ease both;
	}

	.loading-card,
	.not-found,
	.result-card,
	.welcome-card {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
	}

	.loading-card {
		min-height: 15rem;
		justify-content: center;
		color: var(--ink-soft);
	}

	.loading-card p {
		font-size: 0.9rem;
	}

	.loader {
		width: 2.4rem;
		height: 2.4rem;
		border: 2px solid #e8e0d0;
		border-top-color: var(--gold-deep);
		border-radius: 50%;
		animation: spin 800ms linear infinite;
	}

	.quest-badge,
	.result-icon {
		display: grid;
		width: 3.5rem;
		height: 3.5rem;
		place-items: center;
		margin-bottom: 1.15rem;
		border-radius: 1.1rem;
		background: #fbf0db;
		color: var(--gold-deep);
		font-size: 1.5rem;
	}

	.result-icon {
		background: #e8f3ed;
		color: var(--success);
	}

	.not-found .result-icon {
		background: #fbf0db;
		color: var(--gold-deep);
	}

	.welcome-card .eyebrow,
	.result-card .eyebrow,
	.not-found .eyebrow {
		justify-content: center;
	}

	.welcome-card .eyebrow::after,
	.result-card .eyebrow::after,
	.not-found .eyebrow::after {
		width: 1.6rem;
		height: 1px;
		background: currentColor;
		content: '';
	}

	.welcome-card .page-heading,
	.not-found .page-heading {
		max-width: 35rem;
		font-size: clamp(1.9rem, 6vw, 3rem);
	}

	.welcome-card .page-intro,
	.not-found .page-intro {
		max-width: 31rem;
	}

	.welcome-form {
		display: grid;
		width: min(100%, 24rem);
		gap: 0.7rem;
		margin-top: 1.7rem;
		text-align: left;
	}

	.learner-input {
		padding: 0.88rem 1rem;
	}

	.welcome-form .button {
		width: 100%;
		margin-top: 0.25rem;
	}

	.not-found .button {
		margin-top: 1.5rem;
	}

	.game-topline {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		margin-bottom: 1.1rem;
	}

	.exit-link {
		color: var(--ink-muted);
		font-size: 0.78rem;
		font-weight: 600;
		text-decoration: none;
	}

	.exit-link:hover {
		color: var(--navy);
	}

	.game-code {
		padding: 0.4rem 0.6rem;
		border-radius: 0.5rem;
		background: var(--paper);
		color: var(--navy);
		font-family: Manrope, monospace;
		font-size: 0.7rem;
		font-weight: 800;
		letter-spacing: 0.12em;
	}

	.progress-track {
		height: 0.4rem;
		overflow: hidden;
		border-radius: 1rem;
		background: #f0ede7;
	}

	.progress-track span {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: linear-gradient(90deg, var(--navy), #5a72ad);
		transition: width 250ms ease;
	}

	.question-meta {
		display: flex;
		justify-content: space-between;
		gap: 1rem;
		margin-top: 1.5rem;
		color: var(--ink-muted);
		font-size: 0.66rem;
		font-weight: 800;
		letter-spacing: 0.1em;
	}

	.question-prompt {
		margin: 1rem 0 1.5rem;
		font-family: Manrope, sans-serif;
		font-size: clamp(1.65rem, 5vw, 2.5rem);
		font-weight: 800;
		letter-spacing: -0.06em;
		line-height: 1.2;
	}

	.answer-options {
		display: grid;
		gap: 0.7rem;
		min-width: 0;
		margin: 0;
		padding: 0;
		border: 0;
	}

	.answer-options legend {
		margin-bottom: 0.75rem;
		color: var(--ink-muted);
		font-size: 0.79rem;
	}

	.answer-option {
		display: flex;
		min-height: 3.8rem;
		align-items: center;
		gap: 0.85rem;
		padding: 0.75rem 0.9rem;
		border: 1px solid var(--line);
		border-radius: 0.85rem;
		background: white;
		cursor: pointer;
		transition:
			border-color 150ms ease,
			background 150ms ease,
			transform 150ms ease;
	}

	.answer-option:hover {
		transform: translateY(-1px);
		border-color: #d4c29e;
	}

	.answer-option input {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		opacity: 0;
	}

	.answer-option:has(input:focus-visible) {
		outline: 3px solid rgb(200 160 97 / 66%);
		outline-offset: 3px;
	}

	.answer-option.answer-selected {
		border-color: var(--navy);
		background: #f1f3f9;
	}

	.answer-letter {
		display: grid;
		width: 2rem;
		height: 2rem;
		flex: 0 0 2rem;
		place-items: center;
		border-radius: 0.65rem;
		background: #f5f2ec;
		color: var(--ink-soft);
		font-size: 0.72rem;
		font-weight: 800;
	}

	.answer-selected .answer-letter {
		background: var(--navy);
		color: white;
	}

	.answer-text {
		flex: 1;
		font-size: 0.92rem;
		line-height: 1.45;
	}

	.answer-check {
		color: var(--navy);
		font-size: 0.9rem;
		opacity: 0;
	}

	.answer-selected .answer-check {
		opacity: 1;
	}

	.question-navigation {
		display: flex;
		justify-content: space-between;
		gap: 0.8rem;
		margin-top: 1.5rem;
	}

	.result-heading {
		margin: 0.2rem 0 0;
		font-family: Manrope, sans-serif;
		font-size: clamp(1.8rem, 6vw, 2.8rem);
		font-weight: 800;
		letter-spacing: -0.06em;
	}

	.result-intro {
		max-width: 29rem;
		margin: 0.6rem 0 0;
		color: var(--ink-soft);
		font-size: 0.9rem;
		line-height: 1.7;
	}

	.score-display {
		display: flex;
		align-items: baseline;
		gap: 0.5rem;
		margin: 1.4rem 0;
		color: var(--navy);
	}

	.score-display strong {
		font-family: Manrope, sans-serif;
		font-size: 3.2rem;
		font-weight: 800;
		letter-spacing: -0.08em;
	}

	.score-display span {
		color: var(--ink-muted);
		font-size: 0.82rem;
		font-weight: 600;
	}

	.answer-review {
		width: 100%;
		margin-bottom: 1.5rem;
		padding-top: 1.2rem;
		border-top: 1px solid var(--line);
		text-align: left;
	}

	.answer-review h2 {
		margin: 0 0 0.8rem;
		font-family: Manrope, sans-serif;
		font-size: 0.9rem;
		font-weight: 800;
	}

	.review-row {
		display: flex;
		align-items: flex-start;
		gap: 0.7rem;
		padding: 0.75rem 0;
		border-top: 1px solid #f1eee8;
	}

	.review-marker {
		display: grid;
		width: 1.45rem;
		height: 1.45rem;
		flex: 0 0 1.45rem;
		place-items: center;
		border-radius: 50%;
		background: #f5f2ec;
		color: var(--ink-muted);
		font-size: 0.75rem;
		font-weight: 800;
	}

	.review-correct {
		background: #e6f3eb;
		color: var(--success);
	}

	.review-question {
		margin: 0;
		font-size: 0.83rem;
		font-weight: 700;
		line-height: 1.5;
	}

	.review-feedback {
		margin: 0.3rem 0 0;
		color: var(--ink-muted);
		font-size: 0.74rem;
	}

	.retry-note {
		margin: 0.8rem 0 0;
		color: var(--ink-muted);
		font-size: 0.75rem;
		line-height: 1.6;
		text-align: center;
	}

	.retry-button {
		display: block;
		margin: 0.5rem auto 0;
		padding: 0.5rem;
		border: 0;
		background: transparent;
		color: var(--navy);
		font-size: 0.8rem;
		font-weight: 700;
		cursor: pointer;
	}

	@keyframes arrive {
		from {
			transform: translateY(8px);
			opacity: 0;
		}
		to {
			transform: translateY(0);
			opacity: 1;
		}
	}

	@keyframes spin {
		to {
			transform: rotate(1turn);
		}
	}

	@media (max-width: 540px) {
		.play-card {
			border-radius: 1.1rem;
		}

		.question-navigation {
			align-items: stretch;
		}

		.question-navigation .button {
			min-width: 0;
			padding-inline: 0.75rem;
			font-size: 0.79rem;
		}
	}
</style>
