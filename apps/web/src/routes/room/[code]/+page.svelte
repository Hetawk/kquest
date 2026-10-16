<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import Podium from '#lib/features/activities/components/Podium.svelte';
	import {
		answerGameRoomQuestion,
		fetchGameRoom,
		joinGameRoom,
		renameGameRoomParticipant
	} from '#lib/features/activities/api.js';
	import type { GameRoom } from '#lib/features/activities/types.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	const roomCode = $derived(data.code.toUpperCase());
	let room = $state<GameRoom | null>(null);
	let name = $state('');
	let sessionId = $state('');
	let selectedOption = $state('');
	let error = $state('');
	let feedback = $state('');
	let loading = $state(true);
	let joining = $state(false);
	let submitting = $state(false);
	let savingName = $state(false);
	let editingName = $state(false);
	let remaining = $state(0);
	let deadlineAt = 0;
	let answerKey = '';
	let answeredLocally = $state(false);
	let timeoutSent = $state(false);

	onMount(() => {
		let disposed = false;
		const storageKey = `kquest-room:${roomCode}`;
		const stored = window.localStorage.getItem(storageKey);
		if (stored) {
			try {
				const parsed = JSON.parse(stored) as { sessionId?: string; name?: string };
				sessionId = parsed.sessionId ?? '';
				name = parsed.name ?? '';
			} catch {
				window.localStorage.removeItem(storageKey);
			}
		}

		const refresh = async () => {
			try {
				const requestStarted = performance.now();
				const updated = await fetchGameRoom(roomCode, sessionId || undefined);
				if (disposed) return;
				const previousIndex = room?.question_index;
				room = updated;
				if (updated.participant) {
					name = updated.participant.learner_name;
					if (previousIndex !== updated.question_index) {
						selectedOption = '';
						feedback = '';
						answeredLocally = false;
						answerKey = '';
						timeoutSent = false;
					}
					if (updated.participant.answered) answeredLocally = true;
					window.localStorage.setItem(storageKey, JSON.stringify({ sessionId, name }));
				}
				const adjustedSeconds = Math.max(
					0,
					updated.time_remaining_seconds - (performance.now() - requestStarted) / 1000
				);
				remaining = adjustedSeconds;
				deadlineAt = performance.now() + adjustedSeconds * 1000;
				error = '';
			} catch (cause) {
				if (!disposed)
					error = cause instanceof Error ? cause.message : 'Could not refresh the live room.';
			} finally {
				if (!disposed) loading = false;
			}
		};

		void refresh();
		const poll = window.setInterval(() => void refresh(), 1000);
		const clock = window.setInterval(() => {
			if (
				!room?.current_question?.time_limit_seconds ||
				room.status !== 'active' ||
				answeredLocally
			)
				return;
			remaining = Math.max(0, (deadlineAt - performance.now()) / 1000);
			if (remaining <= 0 && !timeoutSent && !submitting) {
				timeoutSent = true;
				void submitAnswer(null);
			}
		}, 150);
		return () => {
			disposed = true;
			window.clearInterval(poll);
			window.clearInterval(clock);
		};
	});

	async function join(event: SubmitEvent) {
		event.preventDefault();
		if (!room || joining || name.trim().length === 0) return;
		joining = true;
		error = '';
		try {
			const joined = await joinGameRoom({
				roomCode,
				learnerName: name.trim(),
				idempotencyKey: crypto.randomUUID()
			});
			sessionId = joined.session_id;
			name = joined.learner_name;
			room = joined.room;
			window.localStorage.setItem(`kquest-room:${roomCode}`, JSON.stringify({ sessionId, name }));
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'You could not join this room.';
		} finally {
			joining = false;
		}
	}

	async function saveName(event: SubmitEvent) {
		event.preventDefault();
		if (!sessionId || savingName || name.trim().length === 0) return;
		savingName = true;
		error = '';
		try {
			const updated = await renameGameRoomParticipant({
				roomCode,
				sessionId,
				learnerName: name.trim()
			});
			name = updated.learner_name;
			window.localStorage.setItem(`kquest-room:${roomCode}`, JSON.stringify({ sessionId, name }));
			editingName = false;
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your display name could not be changed.';
		} finally {
			savingName = false;
		}
	}

	async function submitAnswer(optionId: string | null) {
		const question = room?.current_question;
		if (!question || !sessionId || submitting || answeredLocally || !room) return;
		submitting = true;
		error = '';
		if (!answerKey) answerKey = crypto.randomUUID();
		try {
			const result = await answerGameRoomQuestion({
				roomCode,
				sessionId,
				questionId: question.id,
				optionId,
				idempotencyKey: answerKey
			});
			answeredLocally = true;
			feedback = result.timed_out
				? 'Time ran out. Your group will move on together.'
				: result.is_correct
					? `Correct — ${result.points_awarded} points${result.speed_bonus ? `, including ${result.speed_bonus} speed bonus` : ''}.`
					: 'Not quite. Keep going with your group.';
			error = '';
			answerKey = '';
			void fetchGameRoom(roomCode, sessionId).then((updated) => (room = updated));
		} catch (cause) {
			if (optionId === null) timeoutSent = false;
			error = cause instanceof Error ? cause.message : 'Your answer could not be saved.';
		} finally {
			submitting = false;
		}
	}

	const questionExpired = $derived(
		Boolean(room?.current_question?.time_limit_seconds && remaining <= 0)
	);
</script>

<svelte:head>
	<title>{room?.title ? `${room.title} — Join live game` : 'Join live game'} — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell room-page">
	{#if loading && !room}
		<section class="room-card">
			<p class="eyebrow">Joining your group</p>
			<h1>Opening the live room…</h1>
		</section>
	{:else if !room}
		<section class="room-card">
			<p class="eyebrow">Live room</p>
			<h1>We couldn’t find this room.</h1>
			<p>{error}</p>
			<a class="button button-primary" href={resolve('/join')}>Enter a different code</a>
		</section>
	{:else if room.status === 'completed'}
		<section class="room-card">
			<p class="eyebrow">Live game complete</p>
			<h1>Well played, {name || 'everyone'}.</h1>
			<Podium entries={room.podium} finalized={true} participantCount={room.participant_count} />
			<div class="standings">
				<h2>Final standings</h2>
				{#each room.standings as entry (entry.rank)}<div class="standing-row">
						<span>#{entry.rank}</span><strong>{entry.learner_name}</strong><b>{entry.score} pts</b>
					</div>{/each}
			</div>
		</section>
	{:else if !sessionId}
		<section class="room-card">
			<p class="eyebrow">You’re invited</p>
			<h1>{room.title}</h1>
			<p class="intro">
				Join as a guest — no account is required. Choose a name your group will recognize.
			</p>
			<form class="name-form" onsubmit={join}>
				<label for="room-name">Your display name</label>
				<input
					id="room-name"
					class="name-input"
					maxlength="80"
					autocomplete="nickname"
					bind:value={name}
					required
				/>
				<button
					class="button button-primary"
					type="submit"
					disabled={joining || room.status !== 'waiting'}
				>
					{room.status !== 'waiting'
						? 'This game has already started'
						: joining
							? 'Joining room…'
							: 'Join as a guest'}
				</button>
			</form>
			<p class="guest-note">
				Want an account? <a href={resolve('/auth')}>Sign in</a> first, or continue here without one.
			</p>
			<p>{room.participant_count} players are in this room.</p>
		</section>
	{:else}
		<section class="room-card">
			<div class="room-heading">
				<div>
					<p class="eyebrow">
						{room.status === 'waiting' ? 'Waiting room' : 'Live with your group'}
					</p>
					<h1>{room.title}</h1>
				</div>
				<span class="room-code">{room.room_code}</span>
			</div>
			{#if editingName}
				<form class="rename-form" onsubmit={saveName}>
					<label for="rename-player">Display name</label>
					<input id="rename-player" class="name-input" maxlength="80" bind:value={name} required />
					<button type="submit" class="button button-outline" disabled={savingName}
						>{savingName ? 'Saving…' : 'Save name'}</button
					>
					<button type="button" class="text-button" onclick={() => (editingName = false)}
						>Cancel</button
					>
				</form>
			{:else}
				<div class="player-label">
					<span>Playing as <strong>{name}</strong></span><button
						type="button"
						class="text-button"
						onclick={() => (editingName = true)}
						disabled={room.status === 'active' && Boolean(room.participant?.answered)}
						>Change name</button
					>
				</div>
			{/if}

			{#if room.status === 'waiting'}
				<div class="waiting-state">
					<span class="waiting-orb" aria-hidden="true">✦</span>
					<h2>You’re in!</h2>
					<p>Waiting for the host to start. You can still change your display name.</p>
					<strong>{room.participant_count} players joined</strong>
				</div>
			{:else if room.current_question}
				<div class="question-meta">
					<span>QUESTION {room.question_index + 1} OF {room.question_count}</span><span
						>{room.answered_count}/{room.participant_count} answered</span
					>
				</div>
				{#if room.current_question.time_limit_seconds > 0}
					<div class="round-clock" class:clock-low={remaining <= 5}>
						<strong>{Math.ceil(remaining)}</strong><span>seconds</span>
					</div>
					<div class="clock-track">
						<span
							style={`width:${Math.min(100, (remaining / room.current_question.time_limit_seconds) * 100)}%`}
						></span>
					</div>
				{:else}<p class="untimed">Your host will move the group on when ready.</p>{/if}
				<h2 class="question-prompt">{room.current_question.prompt}</h2>
				<fieldset class="answer-list" disabled={submitting || answeredLocally || questionExpired}>
					<legend>Choose your answer</legend>
					{#each room.current_question.options as option, index (option.id)}
						<label class="answer-option" class:selected={selectedOption === option.id}>
							<input
								type="radio"
								name="live-answer"
								value={option.id}
								bind:group={selectedOption}
							/>
							<span>{String.fromCharCode(65 + index)}</span><strong>{option.text}</strong>
						</label>
					{/each}
				</fieldset>
				{#if feedback}<p class="feedback" role="status">{feedback}</p>{/if}
				{#if !room.participant?.answered && !answeredLocally}
					<button
						class="button button-primary submit-button"
						type="button"
						disabled={submitting || (!selectedOption && !questionExpired)}
						onclick={() => submitAnswer(selectedOption || null)}
					>
						{submitting ? 'Saving answer…' : questionExpired ? 'Submit timeout' : 'Lock in answer'}
						<span aria-hidden="true">↗</span>
					</button>
				{:else}<div class="waiting-answer" role="status">
						<strong>Answer locked in</strong><span>Waiting for the host to advance the round.</span>
					</div>{/if}
			{/if}
			{#if error}<p class="error-message" role="alert">{error}</p>{/if}
		</section>
	{/if}
</main>

<style>
	.room-page {
		min-height: 75vh;
		padding-block: 2rem 4rem;
	}
	.room-card {
		width: min(100%, 48rem);
		margin-inline: auto;
		padding: clamp(1.2rem, 5vw, 2.5rem);
		border: 1px solid var(--line);
		border-radius: 1.3rem;
		background: white;
		box-shadow: var(--shadow-card);
	}
	.room-card > h1,
	.room-heading h1 {
		margin: 0.35rem 0;
		color: var(--navy);
		font-family: Manrope, sans-serif;
		font-size: clamp(1.8rem, 6vw, 3rem);
		letter-spacing: -0.06em;
	}
	.intro {
		color: var(--ink-muted);
		font-size: 0.86rem;
		line-height: 1.6;
	}
	.name-form {
		display: grid;
		gap: 0.7rem;
		margin-top: 1.4rem;
	}
	.name-form label,
	.rename-form label {
		color: var(--navy);
		font-size: 0.78rem;
		font-weight: 700;
	}
	.name-input {
		width: 100%;
		padding: 0.9rem 1rem;
		border: 1px solid var(--line);
		border-radius: 0.7rem;
		font: inherit;
	}
	.guest-note {
		margin-top: 1.2rem;
		color: var(--ink-muted);
		font-size: 0.75rem;
	}
	.guest-note a {
		color: var(--navy);
		font-weight: 700;
	}
	.room-heading {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}
	.room-heading h1 {
		font-size: clamp(1.5rem, 5vw, 2.3rem);
	}
	.room-code {
		padding: 0.45rem 0.65rem;
		border-radius: 0.5rem;
		background: #f7f0e2;
		color: var(--navy);
		font-size: 0.7rem;
		font-weight: 800;
		letter-spacing: 0.1em;
	}
	.player-label {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
		margin-block: 1rem;
		padding: 0.65rem 0.8rem;
		border-radius: 0.65rem;
		background: #f7f5ef;
		color: var(--ink-muted);
		font-size: 0.78rem;
	}
	.player-label strong {
		color: var(--navy);
	}
	.text-button {
		padding: 0.35rem;
		border: 0;
		background: transparent;
		color: var(--navy);
		font: inherit;
		font-weight: 700;
		cursor: pointer;
	}
	.text-button:disabled {
		color: var(--ink-muted);
		cursor: not-allowed;
	}
	.rename-form {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.55rem;
		margin-block: 1rem;
	}
	.rename-form label {
		flex-basis: 100%;
	}
	.rename-form .name-input {
		flex: 1 1 12rem;
	}
	.waiting-state {
		display: grid;
		justify-items: center;
		margin-top: 1.6rem;
		padding: 2rem 1rem;
		border-radius: 1rem;
		background: linear-gradient(135deg, #fcf8ef, #f6f3eb);
		text-align: center;
	}
	.waiting-orb {
		display: grid;
		width: 3rem;
		height: 3rem;
		place-items: center;
		border-radius: 1rem;
		background: #f5e7c9;
		color: var(--gold-deep);
		font-size: 1.3rem;
	}
	.waiting-state h2 {
		margin: 0.7rem 0 0;
		color: var(--navy);
	}
	.waiting-state p,
	.waiting-state strong {
		color: var(--ink-muted);
		font-size: 0.8rem;
	}
	.question-meta {
		display: flex;
		justify-content: space-between;
		gap: 0.5rem;
		margin-top: 1.5rem;
		color: var(--ink-muted);
		font-size: 0.68rem;
		font-weight: 800;
	}
	.round-clock {
		display: grid;
		width: 5rem;
		height: 5rem;
		place-content: center;
		margin: 1.2rem auto 0.8rem;
		border: 3px solid #e5d4ad;
		border-radius: 50%;
		color: var(--navy);
		text-align: center;
	}
	.round-clock strong {
		font-size: 1.6rem;
		line-height: 1;
	}
	.round-clock span {
		margin-top: 0.2rem;
		color: var(--ink-muted);
		font-size: 0.58rem;
	}
	.clock-low {
		border-color: #bd6752;
		color: #9a3f2d;
	}
	.clock-track {
		height: 0.45rem;
		overflow: hidden;
		border-radius: 99px;
		background: #eee9df;
	}
	.clock-track span {
		display: block;
		height: 100%;
		background: var(--gold-deep);
		transition: width 150ms linear;
	}
	.untimed {
		color: var(--ink-muted);
		font-size: 0.75rem;
		text-align: center;
	}
	.question-prompt {
		margin: 1.4rem 0;
		color: var(--navy);
		font-size: clamp(1.3rem, 4vw, 2rem);
		line-height: 1.3;
	}
	.answer-list {
		display: grid;
		gap: 0.55rem;
		padding: 0;
		border: 0;
	}
	.answer-list legend {
		margin-bottom: 0.65rem;
		color: var(--ink-muted);
		font-size: 0.75rem;
	}
	.answer-option {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.85rem;
		border: 1px solid var(--line);
		border-radius: 0.75rem;
		cursor: pointer;
	}
	.answer-option.selected {
		border-color: var(--gold-deep);
		background: #fffaf0;
	}
	.answer-option input {
		accent-color: var(--navy);
	}
	.answer-option > span {
		display: grid;
		width: 1.7rem;
		height: 1.7rem;
		flex: 0 0 1.7rem;
		place-items: center;
		border-radius: 50%;
		background: #f3efe6;
		color: var(--navy);
		font-size: 0.7rem;
		font-weight: 800;
	}
	.answer-option strong {
		font-size: 0.84rem;
	}
	.answer-option:disabled {
		opacity: 0.75;
		cursor: not-allowed;
	}
	.submit-button {
		display: flex;
		width: 100%;
		justify-content: center;
		margin-top: 1rem;
	}
	.feedback {
		padding: 0.7rem;
		border-radius: 0.65rem;
		background: #edf5ee;
		color: #276040;
		font-size: 0.8rem;
	}
	.waiting-answer {
		display: grid;
		gap: 0.25rem;
		margin-top: 1rem;
		padding: 0.9rem;
		border-radius: 0.7rem;
		background: #eef4ef;
		color: #276040;
		font-size: 0.8rem;
		text-align: center;
	}
	.waiting-answer span {
		font-size: 0.72rem;
	}
	.standings h2 {
		color: var(--navy);
		font-size: 1rem;
	}
	.standing-row {
		display: grid;
		grid-template-columns: 2.5rem 1fr auto;
		gap: 0.6rem;
		padding: 0.7rem 0;
		border-top: 1px solid var(--line);
		font-size: 0.82rem;
	}
	.standing-row span {
		color: var(--gold-deep);
		font-weight: 800;
	}
</style>
