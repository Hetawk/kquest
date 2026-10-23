<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import {
		answerPlayQuestion,
		fetchActivity,
		fetchLeaderboard,
		renamePlaySession,
		startPlaySession
	} from '#lib/features/activities/api.js';
	import Podium from '#lib/features/activities/components/Podium.svelte';
	import SoundControl from '#lib/features/audio/SoundControl.svelte';
	import type {
		AttemptResult,
		PlayLeaderboard,
		PlayActivity,
		PlaySessionProgress
	} from '#lib/features/activities/types.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	let activity = $state<PlayActivity | null>(null);
	let attempt = $state<AttemptResult | null>(null);
	let leaderboard = $state<PlayLeaderboard | null>(null);
	let learnerName = $state('');
	let currentQuestion = $state(0);
	let selectedOptionIds = $state<string[]>([]);
	let loading = $state(true);
	let submitting = $state(false);
	let starting = $state(false);
	let started = $state(false);
	let error = $state('');
	let playSessionId = $state('');
	let secondsRemaining = $state(0);
	let soundEnabled = $state(true);
	let audioVolume = $state(1);
	let audioUnavailable = $state(false);
	let soundNeedsGesture = $state(false);
	let podiumRevealPlayed = false;
	let feedbackMessage = $state('');
	let editingName = $state(false);
	let savingName = $state(false);
	let pendingOptionIds = $state<string[] | undefined>(undefined);
	let sessionStartKey = $state('');
	let sessionLearnerName = '';
	let answerRequestKey = '';
	let deadlineAt = 0;
	let timeoutSubmittedForIndex = -1;
	let lastTickSecond = -1;
	let gameAudio: import('#lib/features/audio/GameAudio.js').GameAudio | null = null;

	onMount(() => {
		let disposed = false;
		const timer = window.setInterval(() => {
			if (!started || !current || !current.time_limit_seconds || attempt) return;

			const remaining = Math.max(0, Math.ceil((deadlineAt - performance.now()) / 1000));
			secondsRemaining = remaining;
			if (remaining > 0 && remaining <= 5 && remaining !== lastTickSecond) {
				lastTickSecond = remaining;
				gameAudio?.playTick();
			}
			if (
				remaining === 0 &&
				pendingOptionIds === undefined &&
				timeoutSubmittedForIndex !== currentQuestion
			) {
				timeoutSubmittedForIndex = currentQuestion;
				void submitAnswer([]);
			}
		}, 200);
		const leaderboardTimer = window.setInterval(() => {
			if (!attempt) return;
			void fetchLeaderboard(data.shareCode)
				.then((result) => {
					if (!disposed) applyLeaderboard(result);
				})
				.catch((cause: unknown) => {
					if (!disposed)
						error =
							cause instanceof Error
								? cause.message
								: 'The shared standings could not be refreshed.';
				});
		}, 5000);

		void import('#lib/features/audio/GameAudio.js')
			.then(({ GameAudio }) => {
				if (disposed) return;
				gameAudio = new GameAudio(
					() => (audioUnavailable = true),
					() => (soundNeedsGesture = true),
					() => (soundNeedsGesture = false)
				);
				audioUnavailable = false;
				gameAudio.setVolume(audioVolume);
				if (!soundEnabled) gameAudio.setEnabled(false);
				if (started && !attempt) gameAudio.start();
			})
			.catch(() => {
				audioUnavailable = true;
			});

		void fetchActivity(data.shareCode)
			.then((result) => {
				activity = result;
			})
			.catch((cause: unknown) => {
				error =
					cause instanceof Error
						? cause.message
						: 'We couldn’t find that game. Check the code and try again.';
			})
			.finally(() => {
				loading = false;
			});

		return () => {
			disposed = true;
			window.clearInterval(timer);
			window.clearInterval(leaderboardTimer);
			gameAudio?.dispose();
			gameAudio = null;
		};
	});

	async function beginGame(event: SubmitEvent) {
		event.preventDefault();
		learnerName = learnerName.trim();
		if (!activity || learnerName.length === 0 || learnerName.length > 80 || starting) return;

		if (!sessionStartKey) {
			sessionStartKey = crypto.randomUUID();
			sessionLearnerName = learnerName;
		}
		starting = true;
		error = '';
		gameAudio?.start();
		const requestStartedAt = performance.now();
		try {
			const session = await startPlaySession({
				shareCode: activity.share_code,
				learnerName: sessionLearnerName,
				idempotencyKey: sessionStartKey
			});
			playSessionId = session.id;
			currentQuestion = session.question_index;
			started = true;
			setQuestionClock(
				session.time_limit_seconds,
				session.time_remaining_seconds,
				requestStartedAt
			);
			gameAudio?.start();
		} catch (cause) {
			gameAudio?.stopAmbient();
			error = cause instanceof Error ? cause.message : 'The quest could not be started.';
		} finally {
			starting = false;
		}
	}

	async function submitAnswer(optionIds: string[]) {
		if (!activity || !current || !playSessionId || submitting || attempt) return;
		const submittedOptionIds = pendingOptionIds === undefined ? optionIds : pendingOptionIds;
		pendingOptionIds = submittedOptionIds;
		submitting = true;
		error = '';
		const requestStartedAt = performance.now();
		if (!answerRequestKey) answerRequestKey = crypto.randomUUID();
		try {
			const progress: PlaySessionProgress = await answerPlayQuestion({
				shareCode: activity.share_code,
				sessionId: playSessionId,
				questionId: current.id,
				...(current.question_type === 'multiple_select'
					? { optionIds: submittedOptionIds }
					: { optionId: submittedOptionIds[0] ?? null }),
				idempotencyKey: answerRequestKey
			});
			if (!progress.timed_out) gameAudio?.playAnswerCue(progress.is_correct);
			feedbackMessage = progress.timed_out
				? 'Time ran out for that question. Keep going.'
				: progress.is_correct
					? 'That’s right. Well done.'
					: 'Not quite. Keep going; every question is a chance to learn.';

			if (progress.complete) {
				attempt = progress.attempt;
				gameAudio?.playCompletionCue();
				gameAudio?.stopAmbient();
				void fetchLeaderboard(activity.share_code)
					.then(applyLeaderboard)
					.catch((cause: unknown) => {
						error =
							cause instanceof Error
								? cause.message
								: 'Your score was saved, but the shared standings could not be loaded.';
					});
			} else {
				currentQuestion = progress.question_index;
				selectedOptionIds = [];
				setQuestionClock(
					progress.time_limit_seconds,
					progress.time_limit_seconds,
					requestStartedAt
				);
			}

			pendingOptionIds = undefined;
			answerRequestKey = '';
			error = '';
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your answers could not be submitted.';
		} finally {
			submitting = false;
		}
	}

	async function saveName(event: SubmitEvent) {
		event.preventDefault();
		if (!activity || !playSessionId || savingName) return;
		savingName = true;
		error = '';
		try {
			const updated = await renamePlaySession({
				shareCode: activity.share_code,
				sessionId: playSessionId,
				learnerName
			});
			learnerName = updated.learner_name;
			editingName = false;
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your display name could not be changed.';
		} finally {
			savingName = false;
		}
	}

	function setQuestionClock(timeLimit: number, remaining: number, requestStartedAt: number) {
		if (timeLimit === 0) {
			deadlineAt = 0;
			secondsRemaining = 0;
			return;
		}

		const elapsedRequestSeconds = (performance.now() - requestStartedAt) / 2000;
		const adjustedRemaining = Math.max(0, remaining - elapsedRequestSeconds);
		deadlineAt = performance.now() + adjustedRemaining * 1000;
		secondsRemaining = Math.ceil(adjustedRemaining);
		lastTickSecond = -1;
		timeoutSubmittedForIndex = -1;
	}

	function toggleSound() {
		if (soundNeedsGesture) {
			gameAudio?.start();
			return;
		}
		soundEnabled = !soundEnabled;
		gameAudio?.setEnabled(soundEnabled);
	}

	function changeVolume(volume: number) {
		audioVolume = volume;
		gameAudio?.setVolume(volume);
	}

	function applyLeaderboard(result: PlayLeaderboard) {
		leaderboard = result;
		if (!podiumRevealPlayed && result.podium.length > 0) {
			podiumRevealPlayed = true;
			gameAudio?.playPodiumReveal();
		}
	}

	function formatDuration(seconds: number | null) {
		if (seconds === null) return 'Not available';
		const minutes = Math.floor(seconds / 60);
		const remainder = seconds % 60;
		return minutes ? `${minutes}m ${remainder}s` : `${remainder}s`;
	}

	const current = $derived(activity?.questions[currentQuestion]);
	const questionExpired = $derived(Boolean(current?.time_limit_seconds && secondsRemaining === 0));
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
			<p class="duration-summary">Time spent: {formatDuration(attempt.duration_seconds)}</p>
			<SoundControl
				enabled={soundEnabled}
				volume={audioVolume}
				unavailable={audioUnavailable}
				needsGesture={soundNeedsGesture}
				onToggle={toggleSound}
				onVolumeChange={changeVolume}
			/>
			<div
				class="score-display"
				aria-label="Your score: {attempt.score} out of {attempt.max_score} points"
			>
				<strong>{attempt.score}</strong><span>/ {attempt.max_score} points</span>
			</div>
			{#if leaderboard}
				<Podium
					entries={leaderboard.podium}
					finalized={false}
					participantCount={leaderboard.participant_count}
				/>
				{#if leaderboard.standings.length > 0}
					<div class="shared-standings">
						<h2>Shared provisional standings</h2>
						{#each leaderboard.standings as entry (entry.rank)}
							<div class="standing-row">
								<span>#{entry.rank}</span><strong>{entry.learner_name}</strong><b
									>{entry.score} pts</b
								>
							</div>
						{/each}
					</div>
				{/if}
			{/if}

			<div class="answer-review">
				<h2>Your answers</h2>
				{#each attempt.results as result, index (result.question_id)}
					<article class="review-row">
						<span
							class="review-marker"
							class:review-correct={result.points_awarded > 0}
							aria-label={result.timed_out
								? 'Time ran out'
								: result.points_awarded > 0
									? 'Correct'
									: 'Keep learning'}
						>
							{result.points_awarded > 0 ? '✓' : '·'}
						</span>
						<div>
							<p class="review-question">{index + 1}. {result.prompt}</p>
							<p class="review-feedback">
								{result.timed_out
									? `Time ran out; no answer was recorded. A correct choice could earn up to ${result.points_possible} points.`
									: result.points_awarded > 0
										? `You got it — ${result.base_points} base${result.speed_bonus ? ` + ${result.speed_bonus} speed bonus` : ''} = ${result.points_awarded} points`
										: `A correct choice could earn up to ${result.points_possible} points`}
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
			{#if activity.cover_image_url}
				<img class="quest-cover" src={activity.cover_image_url} alt="" />
			{/if}
			<p class="page-intro">
				{activity.questions.length}
				{activity.questions.length === 1 ? 'question' : 'questions'}.
				{activity.questions.some((question) => question.time_limit_seconds > 0)
					? 'Each question has its own time limit, set by your educator.'
					: 'Take the time you need; this quest has no timers.'}
			</p>
			<p class="sound-intro">
				Soft ambient sounds start with your quest. You can turn them off anytime.
			</p>
			<p class="guest-choice">
				Join as a guest without an account, or
				<a href={resolve('/auth')}>sign in to your account</a> if you prefer.
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
					disabled={starting || Boolean(sessionStartKey && error)}
				/>
				{#if error}<p class="error-message" role="alert">{error}</p>{/if}
				<button class="button button-primary" type="submit" disabled={starting}>
					{starting
						? 'Preparing your quest…'
						: sessionStartKey
							? 'Retry starting quest'
							: 'Start quest with soft sounds'}
					{#if !starting}<span aria-hidden="true">↗</span>{/if}
				</button>
			</form>
		</section>
	{:else if current}
		<section class="play-card question-card" aria-labelledby="question-heading">
			<div class="game-topline">
				<a href={resolve('/join')} class="exit-link">← Leave game</a>
				<div class="game-actions">
					<span class="game-code">{activity.share_code}</span>
					<SoundControl
						enabled={soundEnabled}
						volume={audioVolume}
						unavailable={audioUnavailable}
						needsGesture={soundNeedsGesture}
						onToggle={toggleSound}
						onVolumeChange={changeVolume}
					/>
				</div>
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
				<span
					>{current.points} BASE + {current.speed_scoring && current.time_limit_seconds > 0
						? `${current.speed_bonus_points ?? current.points} MAX SPEED BONUS`
						: 'NO SPEED BONUS'}</span
				>
			</div>
			<div class="player-name-line">
				<span>Playing as <strong>{learnerName}</strong></span>
				<button class="name-edit" type="button" onclick={() => (editingName = !editingName)}
					>Change name</button
				>
			</div>
			{#if editingName}
				<form class="rename-inline" onsubmit={saveName}>
					<label for="active-learner-name">Display name</label>
					<input
						id="active-learner-name"
						class="text-input"
						maxlength="80"
						bind:value={learnerName}
						required
					/>
					<button class="button button-outline" type="submit" disabled={savingName}
						>{savingName ? 'Saving…' : 'Save name'}</button
					>
				</form>
			{/if}

			{#if current.time_limit_seconds > 0}
				<div
					class="countdown"
					role="timer"
					aria-label="{secondsRemaining} seconds remaining"
					class:countdown-low={secondsRemaining <= 5}
				>
					<strong>{secondsRemaining}</strong>
					<span>seconds remaining</span>
				</div>
				<div class="countdown-track" aria-hidden="true">
					<span
						class:countdown-track-low={secondsRemaining <= 5}
						style="width: {Math.min(100, (secondsRemaining / current.time_limit_seconds) * 100)}%"
					></span>
				</div>
			{:else}
				<p class="untimed-label">No countdown in participant-paced play</p>
			{/if}

			<h1 id="question-heading" class="question-prompt">{current.prompt}</h1>

			<fieldset
				class="answer-options"
				disabled={submitting || questionExpired || pendingOptionIds !== undefined}
			>
				<legend>
					{current.question_type === 'multiple_select'
						? 'Choose every answer that is correct.'
						: 'Choose the answer that feels right.'}
				</legend>
				{#each current.options as option, optionIndex (option.id)}
					<label
						class="answer-option"
						class:answer-selected={selectedOptionIds.includes(option.id)}
					>
						<input
							type={current.question_type === 'multiple_select' ? 'checkbox' : 'radio'}
							name="answer-{current.id}"
							value={option.id}
							checked={selectedOptionIds.includes(option.id)}
							onchange={() => {
								selectedOptionIds =
									current.question_type === 'multiple_select'
										? selectedOptionIds.includes(option.id)
											? selectedOptionIds.filter((id) => id !== option.id)
											: [...selectedOptionIds, option.id]
										: [option.id];
							}}
						/>
						<span class="answer-letter" aria-hidden="true"
							>{String.fromCharCode(65 + optionIndex)}</span
						>
						<span class="answer-text">{option.text}</span>
						<span class="answer-check" aria-hidden="true">✓</span>
					</label>
				{/each}
			</fieldset>

			{#if feedbackMessage}<p class="feedback-message" role="status">{feedbackMessage}</p>{/if}
			{#if audioUnavailable}
				<p class="audio-note" role="status">
					Optional sounds are unavailable; your quest will continue normally.
				</p>
			{/if}
			{#if error}<p class="error-message" role="alert">{error}</p>{/if}

			<div class="question-navigation">
				<button
					class="button button-primary"
					type="button"
					disabled={submitting ||
						(pendingOptionIds === undefined && (!selectedOptionIds.length || questionExpired))}
					onclick={() => submitAnswer(selectedOptionIds)}
				>
					{submitting
						? 'Saving your answer…'
						: pendingOptionIds !== undefined
							? 'Retry answer'
							: currentQuestion === activity.questions.length - 1
								? 'Finish quest'
								: 'Submit answer'}
					{#if !submitting}<span aria-hidden="true"
							>{currentQuestion === activity.questions.length - 1 ? '✦' : '→'}</span
						>{/if}
				</button>
			</div>
			{#if pendingOptionIds !== undefined && error}
				<p class="retry-note">Your response can be safely retried without advancing twice.</p>
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

	.sound-intro {
		margin: 0.55rem 0 0;
		color: var(--ink-muted);
		font-size: 0.78rem;
	}

	.guest-choice {
		margin: 0.45rem 0 0;
		color: var(--ink-muted);
		font-size: 0.76rem;
	}
	.guest-choice a {
		color: var(--navy);
		font-weight: 700;
	}
	.player-name-line {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.6rem;
		margin-top: 1rem;
		padding: 0.6rem 0.75rem;
		border-radius: 0.65rem;
		background: #f7f5ef;
		color: var(--ink-muted);
		font-size: 0.75rem;
	}
	.player-name-line strong {
		color: var(--navy);
	}
	.name-edit {
		border: 0;
		background: transparent;
		color: var(--navy);
		font: inherit;
		font-weight: 700;
		cursor: pointer;
	}
	.rename-inline {
		display: flex;
		flex-wrap: wrap;
		gap: 0.55rem;
		align-items: end;
		margin-top: 0.7rem;
	}
	.rename-inline label {
		flex-basis: 100%;
		color: var(--navy);
		font-size: 0.75rem;
		font-weight: 700;
	}
	.rename-inline .text-input {
		flex: 1 1 12rem;
	}
	.shared-standings {
		width: 100%;
		margin-block: 1rem;
		text-align: left;
	}
	.shared-standings h2 {
		color: var(--navy);
		font-size: 1rem;
	}
	.standing-row {
		display: grid;
		grid-template-columns: 2.5rem 1fr auto;
		gap: 0.6rem;
		padding: 0.7rem 0;
		border-top: 1px solid var(--line);
		font-size: 0.8rem;
	}
	.standing-row span {
		color: var(--gold-deep);
		font-weight: 800;
	}

	.quest-cover {
		display: block;
		width: min(100%, 34rem);
		max-height: 20rem;
		margin: 0.8rem 0 1rem;
		border-radius: 1rem;
		object-fit: cover;
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

	.game-actions {
		display: flex;
		align-items: center;
		gap: 0.55rem;
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

	.countdown {
		display: flex;
		align-items: baseline;
		gap: 0.45rem;
		margin-top: 1.3rem;
		color: var(--navy);
		font-variant-numeric: tabular-nums;
	}

	.countdown strong {
		font-family: Manrope, sans-serif;
		font-size: 1.45rem;
		font-weight: 800;
	}

	.countdown span {
		color: var(--ink-muted);
		font-size: 0.76rem;
	}

	.countdown-low strong {
		color: #a45e35;
	}

	.countdown-track {
		height: 0.25rem;
		overflow: hidden;
		margin-top: 0.35rem;
		border-radius: 1rem;
		background: #f0ede7;
	}

	.countdown-track span {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: #829b86;
		transition: width 180ms linear;
	}

	.countdown-track span.countdown-track-low {
		background: #c28c60;
	}

	.untimed-label {
		margin: 1.25rem 0 0;
		color: var(--ink-muted);
		font-size: 0.75rem;
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
		justify-content: flex-end;
		gap: 0.8rem;
		margin-top: 1.5rem;
	}

	.feedback-message,
	.audio-note {
		margin: 0.9rem 0 0;
		color: var(--ink-soft);
		font-size: 0.82rem;
		line-height: 1.5;
	}

	.audio-note {
		color: var(--ink-muted);
		font-size: 0.74rem;
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
			width: 100%;
			min-width: 0;
			padding-inline: 0.75rem;
			font-size: 0.79rem;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.play-card,
		.loader {
			animation: none;
		}

		.progress-track span,
		.countdown-track span {
			transition: none;
		}
	}
</style>
