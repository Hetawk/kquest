<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import Podium from '#lib/features/activities/components/Podium.svelte';
	import SoundControl from '#lib/features/audio/SoundControl.svelte';
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
	let selectedOptionIds = $state<string[]>([]);
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
	let soundEnabled = $state(true);
	let audioVolume = $state(1);
	let soundNeedsGesture = $state(false);
	let audioUnavailable = $state(false);
	let waitingAudio: import('#lib/features/audio/WaitingRoomAudio.js').WaitingRoomAudio | null =
		null;
	let liveAudio: import('#lib/features/audio/GameAudio.js').GameAudio | null = null;
	let lastAudioQuestionIndex = -1;
	let lastTickSecond = -1;
	let lastUrgencySecond = -1;
	let lastAudioPhase = '';

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
				const previousPhase = room?.round_phase;
				const previousStatus = room?.status;
				room = updated;
				if (previousStatus !== 'completed' && updated.status === 'completed') {
					liveAudio?.playCompletionCue();
					liveAudio?.playPodiumReveal();
				}
				if (
					previousPhase === 'leaderboard' &&
					updated.round_phase === 'answer' &&
					!updated.participant?.answered
				) {
					liveAudio?.playAnswerCue(true);
				}
				if (updated.participant) {
					name = updated.participant.learner_name;
					if (previousIndex !== updated.question_index) {
						selectedOptionIds = [];
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
		void import('#lib/features/audio/WaitingRoomAudio.js')
			.then(({ WaitingRoomAudio }) => {
				if (disposed) return;
				waitingAudio = new WaitingRoomAudio(
					() => (audioUnavailable = true),
					() => (soundNeedsGesture = true),
					() => (soundNeedsGesture = false)
				);
				waitingAudio.setVolume(audioVolume);
				if (room?.status === 'waiting' && sessionId) waitingAudio.start();
			})
			.catch(() => {
				audioUnavailable = true;
			});
		void import('#lib/features/audio/GameAudio.js')
			.then(({ GameAudio }) => {
				if (disposed) return;
				liveAudio = new GameAudio(
					() => (audioUnavailable = true),
					() => (soundNeedsGesture = true),
					() => (soundNeedsGesture = false)
				);
				liveAudio.setVolume(audioVolume);
				if (!soundEnabled) liveAudio.setEnabled(false);
				if (room?.status === 'active') liveAudio.start();
			})
			.catch(() => {
				audioUnavailable = true;
			});
		const clock = window.setInterval(() => {
			if (
				!room?.current_question?.time_limit_seconds ||
				room.status !== 'active' ||
				room.round_phase !== 'question' ||
				room.current_question.closed ||
				answeredLocally
			)
				return;
			remaining = Math.max(0, (deadlineAt - performance.now()) / 1000);
			if (remaining <= 0 && !timeoutSent && !submitting) {
				timeoutSent = true;
				void submitAnswer([]);
			}
		}, 150);
		return () => {
			disposed = true;
			window.clearInterval(poll);
			window.clearInterval(clock);
			waitingAudio?.dispose();
			waitingAudio = null;
			liveAudio?.dispose();
			liveAudio = null;
		};
	});

	$effect(() => {
		const currentRoom = room;
		if (currentRoom?.status === 'waiting' && sessionId) waitingAudio?.start();
		else waitingAudio?.stop();

		if (currentRoom?.status !== 'active' || !currentRoom.current_question) {
			liveAudio?.stopAmbient();
			return;
		}

		liveAudio?.start();
		if (currentRoom.round_phase !== 'question') {
			lastAudioPhase = currentRoom.round_phase;
			lastUrgencySecond = -1;
			lastTickSecond = -1;
			liveAudio?.setTimerUrgency(0);
			return;
		}
		if (
			currentRoom.current_question.closed ||
			answeredLocally ||
			currentRoom.participant?.answered
		) {
			lastAudioPhase = 'question';
			lastUrgencySecond = -1;
			lastTickSecond = -1;
			liveAudio?.setTimerUrgency(0);
			return;
		}
		if (lastAudioQuestionIndex !== currentRoom.question_index) {
			lastAudioQuestionIndex = currentRoom.question_index;
			lastTickSecond = -1;
			lastUrgencySecond = -1;
		}
		if (lastAudioPhase !== 'question') {
			lastTickSecond = -1;
			lastUrgencySecond = -1;
		}
		lastAudioPhase = 'question';
		const seconds = Math.ceil(remaining);
		if (seconds !== lastUrgencySecond) {
			lastUrgencySecond = seconds;
			const urgency = Math.max(0, Math.min((11 - seconds) / 10, 1));
			liveAudio?.setTimerUrgency(urgency);
			if (seconds > 0 && seconds <= 10 && seconds !== lastTickSecond) {
				lastTickSecond = seconds;
				liveAudio?.playTick(urgency);
			}
		}
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

	async function submitAnswer(optionIds: string[]) {
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
				...(question.question_type === 'multiple_select'
					? { optionIds }
					: { optionId: optionIds[0] ?? null }),
				idempotencyKey: answerKey
			});
			answeredLocally = true;
			liveAudio?.playAnswerCue(result.is_correct);
			feedback = result.timed_out
				? 'Time ran out. Your group will move on together.'
				: result.is_correct
					? `Correct — ${result.points_awarded} points${result.speed_bonus ? `, including ${result.speed_bonus} speed bonus` : ''}.`
					: 'Not quite. Keep going with your group.';
			error = '';
			answerKey = '';
			void fetchGameRoom(roomCode, sessionId).then((updated) => (room = updated));
		} catch (cause) {
			if (optionIds.length === 0) timeoutSent = false;
			error = cause instanceof Error ? cause.message : 'Your answer could not be saved.';
		} finally {
			submitting = false;
		}
	}

	function toggleWaitingSound() {
		if (soundNeedsGesture) {
			waitingAudio?.start();
			liveAudio?.start();
			return;
		}
		soundEnabled = !soundEnabled;
		waitingAudio?.setEnabled(soundEnabled);
		liveAudio?.setEnabled(soundEnabled);
	}

	function changeVolume(volume: number) {
		audioVolume = volume;
		waitingAudio?.setVolume(volume);
		liveAudio?.setVolume(volume);
	}

	const questionExpired = $derived(
		Boolean(room?.current_question?.time_limit_seconds && remaining <= 0)
	);

	function isCorrectOption(optionId: string) {
		const question = room?.current_question;
		if (!question) return false;
		return question.question_type === 'multiple_select'
			? (question.correct_option_ids?.includes(optionId) ?? false)
			: question.correct_option_id === optionId;
	}
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
			<SoundControl
				enabled={soundEnabled}
				volume={audioVolume}
				unavailable={audioUnavailable}
				needsGesture={soundNeedsGesture}
				onToggle={toggleWaitingSound}
				onVolumeChange={changeVolume}
			/>
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
			<SoundControl
				enabled={soundEnabled}
				volume={audioVolume}
				unavailable={audioUnavailable}
				needsGesture={soundNeedsGesture}
				onToggle={toggleWaitingSound}
				onVolumeChange={changeVolume}
			/>

			{#if room.status === 'waiting'}
				<div class="waiting-state">
					<span class="waiting-orb" aria-hidden="true">✦</span>
					<h2>You’re in!</h2>
					<p>Waiting for the host to start. You can still change your display name.</p>
					<strong>{room.participant_count} players joined</strong>
				</div>
			{:else if room.current_question && room.round_phase === 'leaderboard'}
				<section class="post-round-state" aria-live="polite">
					<div class="waiting-orbit" aria-hidden="true"><span></span><span></span><b>✦</b></div>
					<p class="eyebrow">ROUND {room.question_index + 1} COMPLETE</p>
					<h2>Leaderboard</h2>
					<p class="round-state-caption">
						You’re locked in. The host will reveal the correct answer next.
					</p>
					<ol class="player-leaderboard">
						{#each room.standings as entry (entry.rank)}
							<li class:player-leader={entry.rank === 1}>
								<span class="player-rank">#{entry.rank}</span>
								<strong>{entry.learner_name}</strong>
								<b>{entry.score} pts</b>
							</li>
						{/each}
					</ol>
				</section>
			{:else if room.current_question && room.round_phase === 'answer'}
				<section class="answer-reveal-state" aria-live="polite">
					<div class="reveal-sparkle" aria-hidden="true">✦</div>
					<p class="eyebrow">ANSWER REVEALED</p>
					<h2>Here is the correct answer</h2>
					<p class="revealed-question">{room.current_question.prompt}</p>
					{#if feedback}<p class="locked-feedback">{feedback}</p>{/if}
					<div class="revealed-options">
						{#each room.current_question.options as option, index (option.id)}
							<div
								class:correct-option={isCorrectOption(option.id)}
								class:selected-option={selectedOptionIds.includes(option.id)}
							>
								<span>{String.fromCharCode(65 + index)}</span>
								<strong>{option.text}</strong>
								{#if isCorrectOption(option.id)}<b>Correct answer</b>{/if}
							</div>
						{/each}
					</div>
					<p class="round-state-caption">The host will start the next question shortly.</p>
				</section>
			{:else if room.current_question && (room.current_question.closed || answeredLocally || room.participant?.answered)}
				<section class="answer-waiting-state" aria-live="polite">
					<div class="waiting-orbit" aria-hidden="true"><span></span><span></span><b>✦</b></div>
					<p class="eyebrow">
						{room.current_question.closed ? 'ROUND CLOSED' : 'ANSWER LOCKED IN'}
					</p>
					<h2>
						{room.current_question.closed ? 'This round is closed' : 'Your answer is locked in'}
					</h2>
					{#if feedback}<p class="locked-feedback">{feedback}</p>{/if}
					<p class="round-state-caption">
						{room.current_question.closed
							? 'The group is reviewing the leaderboard and answer.'
							: 'Keep an eye on the host screen while everyone finishes this round.'}
					</p>
					<div class="waiting-dots" aria-hidden="true"><span></span><span></span><span></span></div>
				</section>
			{:else if room.current_question}
				<div class="question-meta">
					<span>QUESTION {room.question_index + 1} OF {room.question_count}</span><span
						>{room.answered_count}/{room.participant_count} answered</span
					>
				</div>
				<div
					class="round-clock"
					class:clock-warning={remaining <= 10}
					class:clock-low={remaining <= 5}
					role="timer"
					aria-live="off"
					aria-label="{Math.ceil(remaining)} seconds remaining"
				>
					<strong>{Math.ceil(remaining)}</strong><span>seconds</span>
				</div>
				<div class="clock-track">
					<span
						style={`width:${Math.min(100, (remaining / room.current_question.time_limit_seconds) * 100)}%`}
					></span>
				</div>
				<h2 class="question-prompt">{room.current_question.prompt}</h2>
				<fieldset class="answer-list" disabled={submitting || answeredLocally || questionExpired}>
					<legend>
						{room.current_question.question_type === 'multiple_select'
							? 'Choose every answer that is correct.'
							: 'Choose your answer.'}
					</legend>
					{#each room.current_question.options as option, index (option.id)}
						<label class="answer-option" class:selected={selectedOptionIds.includes(option.id)}>
							<input
								type={room.current_question.question_type === 'multiple_select'
									? 'checkbox'
									: 'radio'}
								name="live-answer"
								value={option.id}
								checked={selectedOptionIds.includes(option.id)}
								onchange={() => {
									selectedOptionIds =
										room?.current_question?.question_type === 'multiple_select'
											? selectedOptionIds.includes(option.id)
												? selectedOptionIds.filter((id) => id !== option.id)
												: [...selectedOptionIds, option.id]
											: [option.id];
								}}
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
						disabled={submitting || (!selectedOptionIds.length && !questionExpired)}
						onclick={() => submitAnswer(selectedOptionIds)}
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
	.answer-waiting-state,
	.post-round-state,
	.answer-reveal-state {
		display: grid;
		justify-items: center;
		gap: 0.7rem;
		min-height: 27rem;
		align-content: center;
		padding-block: 1.5rem;
		text-align: center;
	}
	.answer-waiting-state h2,
	.post-round-state h2,
	.answer-reveal-state h2 {
		margin: 0;
		color: var(--navy);
		font-family: Manrope, sans-serif;
		font-size: clamp(1.5rem, 6vw, 2.2rem);
		letter-spacing: -0.045em;
		line-height: 1.15;
	}
	.answer-waiting-state .eyebrow,
	.post-round-state .eyebrow,
	.answer-reveal-state .eyebrow {
		margin: 0;
	}
	.waiting-orbit {
		position: relative;
		display: grid;
		width: 6.2rem;
		height: 6.2rem;
		place-items: center;
		margin-bottom: 0.3rem;
		border: 1px solid #e5d4ad;
		border-radius: 50%;
		background: radial-gradient(circle, #fffdf8 0 25%, #fff5dd 67%, #f1e5cc);
		color: var(--gold-deep);
		font-size: 1.7rem;
		box-shadow:
			0 0 0 0.6rem #c8a06112,
			0 0.7rem 1.8rem #142a4310;
	}
	.waiting-orbit span {
		position: absolute;
		inset: 0.45rem;
		border: 1px solid #c79d574d;
		border-radius: 50%;
		animation: player-orbit 7s linear infinite;
	}
	.waiting-orbit span:nth-child(2) {
		inset: 0.12rem;
		border-style: dashed;
		animation-direction: reverse;
		animation-duration: 13s;
	}
	.waiting-orbit span::after {
		position: absolute;
		top: -0.17rem;
		left: 50%;
		width: 0.36rem;
		height: 0.36rem;
		border-radius: 50%;
		background: #c79d57;
		content: '';
	}
	.waiting-orbit b {
		animation: player-sparkle 1.8s ease-in-out infinite alternate;
	}
	@keyframes player-orbit {
		to {
			transform: rotate(360deg);
		}
	}
	@keyframes player-sparkle {
		to {
			transform: scale(1.15);
			opacity: 0.65;
		}
	}
	.round-state-caption,
	.locked-feedback {
		max-width: 30rem;
		margin: 0;
		color: var(--ink-muted);
		font-size: 0.82rem;
		line-height: 1.55;
	}
	.locked-feedback {
		padding: 0.65rem 0.9rem;
		border: 1px solid #dbece0;
		border-radius: 0.7rem;
		background: #f1f8f2;
		color: #276040;
		font-weight: 750;
	}
	.waiting-dots {
		display: flex;
		align-items: center;
		gap: 0.32rem;
		margin: 0.2rem 0;
	}
	.waiting-dots span {
		width: 0.38rem;
		height: 0.38rem;
		border-radius: 50%;
		background: #c8a061;
		animation: player-dots 1s ease-in-out infinite alternate;
	}
	.waiting-dots span:nth-child(2) {
		animation-delay: 180ms;
	}
	.waiting-dots span:nth-child(3) {
		animation-delay: 360ms;
	}
	@keyframes player-dots {
		to {
			transform: translateY(-0.28rem);
			opacity: 0.45;
		}
	}
	.player-leaderboard {
		display: grid;
		width: min(100%, 34rem);
		gap: 0.4rem;
		max-height: 17rem;
		overflow: auto;
		margin: 0.4rem 0;
		padding: 0.2rem;
		list-style: none;
		text-align: left;
	}
	.player-leaderboard li {
		display: flex;
		align-items: center;
		gap: 0.65rem;
		padding: 0.65rem;
		border: 1px solid #eeece6;
		border-radius: 0.7rem;
		background: white;
	}
	.player-leaderboard li.player-leader {
		border-color: #e5d4ad;
		background: #fffaf0;
	}
	.player-rank {
		display: grid;
		width: 1.9rem;
		height: 1.9rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f1eee7;
		color: var(--navy);
		font-size: 0.66rem;
		font-weight: 850;
	}
	.player-leader .player-rank {
		background: #f4e3b6;
	}
	.player-leaderboard li strong {
		overflow: hidden;
		color: var(--ink);
		font-size: 0.78rem;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.player-leaderboard li b {
		margin-left: auto;
		color: var(--navy);
		font-size: 0.74rem;
		white-space: nowrap;
	}
	.reveal-sparkle {
		display: grid;
		width: 3.1rem;
		height: 3.1rem;
		place-items: center;
		border-radius: 1rem;
		background: #edf7ef;
		color: #25744d;
		font-size: 1.7rem;
		animation: player-sparkle 1.4s ease-in-out infinite alternate;
	}
	.revealed-question {
		max-width: 36rem;
		margin: 0;
		color: var(--ink-muted);
		font-size: 0.9rem;
		line-height: 1.5;
	}
	.revealed-options {
		display: grid;
		width: min(100%, 37rem);
		gap: 0.45rem;
		margin-block: 0.45rem;
		text-align: left;
	}
	.revealed-options > div {
		display: flex;
		align-items: center;
		gap: 0.65rem;
		padding: 0.7rem;
		border: 1px solid var(--line);
		border-radius: 0.7rem;
		color: var(--ink);
		font-size: 0.78rem;
	}
	.revealed-options > div.correct-option {
		border-color: #99c9a9;
		background: #edf7ef;
		color: #1f643c;
	}
	.revealed-options > div.selected-option:not(.correct-option) {
		border-color: #d7a59a;
		background: #fff4f1;
	}
	.revealed-options > div > span {
		display: grid;
		width: 1.6rem;
		height: 1.6rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f3efe6;
		font-size: 0.66rem;
		font-weight: 850;
	}
	.revealed-options > div.correct-option > span {
		background: #d6ecdc;
	}
	.revealed-options > div > b {
		margin-left: auto;
		font-size: 0.62rem;
		white-space: nowrap;
	}
	.question-meta {
		display: flex;
		align-items: center;
		justify-content: space-between;
		flex-wrap: wrap;
		gap: 0.5rem;
		margin-top: 1.5rem;
		color: var(--ink-muted);
		font-size: 0.68rem;
		font-weight: 800;
	}
	.round-clock {
		display: grid;
		width: clamp(8rem, 35vw, 11rem);
		height: clamp(8rem, 35vw, 11rem);
		place-content: center;
		margin: 1.4rem auto 1rem;
		border: 4px solid #e5d4ad;
		border-radius: 2rem;
		background: #fffaf0;
		color: var(--navy);
		text-align: center;
		box-shadow: 0 0.5rem 1.4rem #142a4310;
		transition:
			border-color 200ms ease,
			background-color 200ms ease,
			color 200ms ease,
			transform 200ms ease;
	}
	.round-clock strong {
		font-size: clamp(3.2rem, 12vw, 5rem);
		line-height: 1;
		font-variant-numeric: tabular-nums;
	}
	.round-clock span {
		margin-top: 0.2rem;
		color: var(--ink-muted);
		font-size: 0.78rem;
		font-weight: 750;
	}
	.clock-warning {
		border-color: #df9c48;
		background: #fff4e2;
		color: #9a5c13;
	}
	.clock-low {
		border-color: #bd6752;
		background: #fff0ec;
		color: #9a3f2d;
		animation: timer-pulse 750ms ease-in-out infinite alternate;
	}
	@keyframes timer-pulse {
		to {
			transform: scale(1.035);
			box-shadow: 0 0 1.5rem #bd67524d;
		}
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
	.clock-low + .clock-track span {
		background: #bd6752;
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
	@media (prefers-reduced-motion: reduce) {
		.clock-low,
		.waiting-orbit span,
		.waiting-orbit b,
		.waiting-dots span,
		.reveal-sparkle {
			animation: none;
		}
	}
</style>
