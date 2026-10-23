<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import QRCode from 'qrcode';
	import Podium from '#lib/features/activities/components/Podium.svelte';
	import SoundControl from '#lib/features/audio/SoundControl.svelte';
	import { advanceGameRoom, fetchGameRoom, startGameRoom } from '#lib/features/activities/api.js';
	import type { GameRoom } from '#lib/features/activities/types.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	let room = $state<GameRoom | null>(null);
	let loading = $state(true);
	let busy = $state(false);
	let error = $state('');
	let notice = $state('');
	let copied = $state<'code' | 'link' | ''>('');
	let qrDataUrl = $state('');
	let hostPage = $state<HTMLElement | null>(null);
	let isFullscreen = $state(false);
	let soundEnabled = $state(true);
	let audioVolume = $state(1);
	let soundNeedsGesture = $state(false);
	let audioUnavailable = $state(false);
	let waitingAudio: import('#lib/features/audio/WaitingRoomAudio.js').WaitingRoomAudio | null =
		null;
	let liveAudio: import('#lib/features/audio/GameAudio.js').GameAudio | null = null;
	let remaining = $state(0);
	let deadlineAt = 0;
	let lastAudioQuestionIndex = -1;
	let lastAudioPhase: GameRoom['round_phase'] | null = null;
	let lastTickSecond = -1;
	let lastUrgencySecond = -1;
	let roundStartRanks = $state<Record<string, number>>({});
	const roomCode = $derived(data.code.toUpperCase());
	const questionNumbers = $derived(
		room ? Array.from({ length: room.question_count }, (_, index) => index) : []
	);
	const joinLink = $derived(
		typeof window === 'undefined' ? '' : createJoinLink(window.location.origin, roomCode)
	);
	const avatarIcons = ['✦', '☼', '◆', '✧', '◈', '✺', '✳', '◇'];

	function createJoinLink(origin: string, code: string) {
		const url = new URL(resolve('/join'), origin);
		url.searchParams.set('code', code);
		return url.toString();
	}

	onMount(() => {
		let disposed = false;
		let refreshing = false;
		const updateFullscreenState = () => {
			isFullscreen = document.fullscreenElement === hostPage;
		};
		document.addEventListener('fullscreenchange', updateFullscreenState);

		const refresh = async () => {
			if (refreshing || document.visibilityState === 'hidden') return;
			refreshing = true;
			const requestStartedAt = performance.now();
			try {
				const updated = await fetchGameRoom(roomCode);
				if (!disposed) {
					updateRoom(updated, requestStartedAt);
					error = '';
				}
			} catch (cause) {
				if (!disposed) {
					error = cause instanceof Error ? cause.message : 'Could not refresh the live room.';
				}
			} finally {
				refreshing = false;
				if (!disposed) loading = false;
			}
		};

		void refresh();
		const timer = window.setInterval(() => void refresh(), 1800);
		void import('#lib/features/audio/WaitingRoomAudio.js')
			.then(({ WaitingRoomAudio }) => {
				if (disposed) return;
				waitingAudio = new WaitingRoomAudio(
					() => (audioUnavailable = true),
					() => (soundNeedsGesture = true),
					() => (soundNeedsGesture = false)
				);
				waitingAudio.setVolume(audioVolume);
				if (room?.status === 'waiting') waitingAudio.start();
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
				room?.status !== 'active' ||
				room.round_phase !== 'question' ||
				!room.current_question?.time_limit_seconds
			)
				return;
			remaining = Math.max(0, (deadlineAt - performance.now()) / 1000);
		}, 150);
		return () => {
			disposed = true;
			window.clearInterval(timer);
			window.clearInterval(clock);
			document.removeEventListener('fullscreenchange', updateFullscreenState);
			waitingAudio?.dispose();
			waitingAudio = null;
			liveAudio?.dispose();
			liveAudio = null;
		};
	});

	$effect(() => {
		const currentRoom = room;
		if (currentRoom?.status === 'waiting') {
			waitingAudio?.start();
			liveAudio?.stopAmbient();
			return;
		}
		waitingAudio?.stop();
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

	$effect(() => {
		const link = joinLink;
		if (!link) return;

		let current = true;
		void QRCode.toDataURL(link, {
			errorCorrectionLevel: 'M',
			margin: 1,
			width: 256,
			color: { dark: '#182E5F', light: '#FFFFFF' }
		})
			.then((dataUrl) => {
				if (current) qrDataUrl = dataUrl;
			})
			.catch((cause: unknown) => {
				if (current) {
					error =
						cause instanceof Error ? cause.message : 'The join QR code could not be generated.';
				}
			});

		return () => {
			current = false;
		};
	});

	async function start() {
		if (busy || !room || room.status !== 'waiting' || room.participant_count === 0) return;
		busy = true;
		error = '';
		try {
			const requestStartedAt = performance.now();
			updateRoom(await startGameRoom(roomCode), requestStartedAt);
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'The live game could not be started.';
		} finally {
			busy = false;
		}
	}

	async function advance() {
		if (busy || !room || room.status !== 'active') return;
		busy = true;
		error = '';
		try {
			const requestStartedAt = performance.now();
			updateRoom(await advanceGameRoom(roomCode), requestStartedAt);
		} catch (cause) {
			error =
				cause instanceof Error
					? cause.message
					: 'The group could not advance to the next question.';
		} finally {
			busy = false;
		}
	}

	async function selectQuestion(questionIndex: number) {
		if (
			busy ||
			!room ||
			room.status !== 'active' ||
			(questionIndex === room.question_index && room.round_phase === 'question')
		)
			return;
		busy = true;
		error = '';
		try {
			const requestStartedAt = performance.now();
			updateRoom(await advanceGameRoom(roomCode, questionIndex), requestStartedAt);
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'The selected question could not be opened.';
		} finally {
			busy = false;
		}
	}

	async function copyValue(kind: 'code' | 'link') {
		error = '';
		notice = '';
		try {
			await navigator.clipboard.writeText(kind === 'code' ? roomCode : joinLink);
			copied = kind;
			notice = kind === 'code' ? 'Game code copied.' : 'Join link copied.';
			window.setTimeout(() => (copied = ''), 1800);
		} catch {
			error = `Copying the ${kind === 'code' ? 'code' : 'link'} is unavailable. You can still select and copy it.`;
		}
	}

	async function shareLink() {
		try {
			if (navigator.share) {
				await navigator.share({
					title: `Join ${room?.title ?? 'my KINGDOM Quest game'}`,
					text: `Join my live game with code ${roomCode}.`,
					url: joinLink
				});
			} else {
				await copyValue('link');
			}
		} catch (cause) {
			if (cause instanceof Error && cause.name !== 'AbortError') {
				error = 'The share sheet could not be opened. Copy the join link instead.';
			}
		}
	}

	function participantIcon(index: number) {
		return avatarIcons[index % avatarIcons.length];
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

	async function toggleFullscreen() {
		try {
			if (document.fullscreenElement === hostPage) {
				await document.exitFullscreen();
			} else if (hostPage?.requestFullscreen) {
				await hostPage.requestFullscreen();
			} else {
				throw new Error('Full screen is not supported by this browser.');
			}
		} catch (cause) {
			error =
				cause instanceof Error
					? cause.message
					: 'Full screen could not be enabled. Check your browser permissions and try again.';
		}
	}

	function formatDuration(seconds: number) {
		const minutes = Math.floor(seconds / 60);
		const remainder = seconds % 60;
		return minutes ? `${minutes}m ${remainder}s` : `${remainder}s`;
	}

	function updateRoom(updated: GameRoom, requestStartedAt: number) {
		const previousRoom = room;
		if (previousRoom?.status !== 'completed' && updated.status === 'completed') {
			liveAudio?.playCompletionCue();
			liveAudio?.playPodiumReveal();
		}
		if (
			previousRoom?.status === 'active' &&
			previousRoom.round_phase !== 'answer' &&
			updated.round_phase === 'answer'
		) {
			liveAudio?.playAnswerCue(true);
		}
		if (
			updated.status === 'active' &&
			(!previousRoom ||
				previousRoom.status === 'waiting' ||
				previousRoom.question_index !== updated.question_index)
		) {
			const reference =
				previousRoom?.status === 'active' ? previousRoom.standings : updated.standings;
			roundStartRanks = Object.fromEntries(
				reference.map((entry) => [leaderboardKey(entry), entry.rank])
			);
		}

		room = updated;
		const adjusted = Math.max(
			0,
			updated.time_remaining_seconds - (performance.now() - requestStartedAt) / 1000
		);
		remaining = updated.status === 'active' ? adjusted : 0;
		deadlineAt = performance.now() + adjusted * 1000;
	}

	function leaderboardKey(entry: GameRoom['standings'][number]) {
		return entry.participant_key ?? `name:${entry.learner_name.trim().toLocaleLowerCase()}`;
	}

	function rankMovement(entry: GameRoom['standings'][number]) {
		const previousRank = roundStartRanks[leaderboardKey(entry)];
		return previousRank === undefined ? 0 : previousRank - entry.rank;
	}

	function isCorrectOption(optionId: string) {
		const question = room?.current_question;
		if (!question) return false;
		return question.question_type === 'multiple_select'
			? (question.correct_option_ids?.includes(optionId) ?? false)
			: question.correct_option_id === optionId;
	}
</script>

<svelte:head>
	<title>{room ? `${room.title} — Host room` : 'Host live room'} — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="host-page" class:fullscreen-lobby={room?.status === 'waiting'} bind:this={hostPage}>
	{#if loading && !room}
		<section class="host-shell loading-shell" role="status" aria-label="Opening the live room">
			<span></span><span></span><span></span>
		</section>
	{:else if !room}
		<section class="host-shell error-shell">
			<p class="eyebrow">LIVE SESSION</p>
			<h1>We can’t open this room.</h1>
			<p>{error}</p>
			<a class="button button-primary" href={resolve('/dashboard')}>Back to your studio</a>
		</section>
	{:else}
		<header class="session-header">
			<a class="back-link" href={resolve('/dashboard')}>← Studio</a>
			<div class="session-heading">
				<div>
					<p class="eyebrow">INSTRUCTOR-PACED LIVE SESSION</p>
					<h1>{room.title}</h1>
				</div>
				<div class="session-tools">
					<SoundControl
						enabled={soundEnabled}
						volume={audioVolume}
						unavailable={audioUnavailable}
						needsGesture={soundNeedsGesture}
						onToggle={toggleWaitingSound}
						onVolumeChange={changeVolume}
					/>
					{#if room.started_at && room.duration_seconds !== null}
						<span class="session-duration" aria-live="off">
							Elapsed {formatDuration(room.duration_seconds)}
						</span>
					{/if}
					<button
						class="fullscreen-button"
						type="button"
						aria-pressed={isFullscreen}
						onclick={toggleFullscreen}
					>
						{isFullscreen ? 'Exit full screen' : 'Full screen'}
					</button>
					<span
						class:active={room.status === 'active'}
						class:completed={room.status === 'completed'}
						class="session-status"
					>
						<span></span>
						{room.status === 'waiting'
							? 'Waiting for learners'
							: room.status === 'active'
								? 'Live now'
								: 'Session complete'}
					</span>
				</div>
			</div>
		</header>

		{#if error}<p class="host-alert" role="alert">{error}</p>{/if}
		{#if notice}<p class="host-notice" role="status">{notice}</p>{/if}

		<div class="host-layout">
			<section class="host-main" aria-label="Live session controls">
				{#if room.status === 'waiting'}
					<div class="invite-card">
						<div class="invite-content">
							<p class="eyebrow">INVITE YOUR LEARNERS</p>
							<h2>Scan to join, or enter the game code</h2>
							<p>
								On a phone or computer, open the join page and enter this code. Scanning the QR code
								fills it in for them.
							</p>
							<div class="join-code-panel">
								<div>
									<span class="share-label">GAME CODE</span>
									<strong class="share-code">{room.room_code}</strong>
								</div>
								<button
									class="copy-icon-button"
									type="button"
									aria-label="Copy game code"
									onclick={() => copyValue('code')}
								>
									{copied === 'code' ? '✓' : '▢'}
								</button>
							</div>
							<div class="join-link-panel">
								<div class="join-link-copy">
									<span class="share-label">JOIN LINK</span>
									<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
									<a href={resolve('/join') + '?code=' + encodeURIComponent(roomCode)}>{joinLink}</a
									>
									<small
										>Or visit {new URL(resolve('/join'), joinLink).origin}{resolve('/join')} and enter
										the code above.</small
									>
								</div>
								<button
									class="button button-outline"
									type="button"
									onclick={() => copyValue('link')}
								>
									{copied === 'link' ? 'Copied!' : 'Copy link'}
								</button>
							</div>
							<button class="share-button" type="button" onclick={shareLink}>
								<span aria-hidden="true">↗</span> Share invite
							</button>
						</div>
						<div class="qr-panel">
							{#if qrDataUrl}
								<img src={qrDataUrl} alt={`QR code to join game ${room.room_code}`} />
							{:else}
								<div class="qr-placeholder" role="status" aria-label="Preparing join QR code"></div>
							{/if}
							<strong>Scan to join</strong>
							<span>Opens the Kquest join page</span>
						</div>
					</div>
					<div class="host-action-card">
						<div>
							<p class="eyebrow">WHEN EVERYONE IS READY</p>
							<h2>Start the live game</h2>
							<p>You’ll present the same question to everyone and choose when to move on.</p>
						</div>
						<button
							class="button button-primary"
							type="button"
							onclick={start}
							disabled={busy || room.participant_count === 0}
						>
							{busy ? 'Starting…' : 'Start now'} <span aria-hidden="true">→</span>
						</button>
					</div>
				{:else if room.status === 'active' && room.current_question && room.round_phase === 'leaderboard'}
					<section class="round-review-card" aria-labelledby="round-leaderboard-title">
						<div class="review-heading">
							<p class="eyebrow">ROUND {room.question_index + 1} COMPLETE</p>
							<div class="review-tools">
								<label class="question-picker">
									<span>Question</span>
									<select
										value={room.question_index}
										aria-label="Select a live question"
										disabled={busy}
										onchange={(event) => void selectQuestion(Number(event.currentTarget.value))}
									>
										{#each questionNumbers as questionIndex (questionIndex)}
											<option value={questionIndex}>{questionIndex + 1}</option>
										{/each}
									</select>
									<span>of {room.question_count}</span>
								</label>
							</div>
						</div>
						<div class="review-hero">
							<div class="review-orbit" aria-hidden="true"><span></span><b>✦</b></div>
							<h2 id="round-leaderboard-title">Leaderboard</h2>
							<p>
								{room.answered_count} of {room.participant_count} learners answered. Take a moment to
								celebrate their scores before revealing the answer.
							</p>
						</div>
						<ol class="review-standings" aria-label="Round leaderboard">
							{#each room.standings as entry (entry.rank)}
								{@const movement = rankMovement(entry)}
								<li class:review-leader={entry.rank === 1}>
									<span class="review-rank">#{entry.rank}</span>
									<span class="review-player">
										<strong>{entry.learner_name}</strong>
										<small>{entry.score} points</small>
									</span>
									<span
										class="leaderboard-movement"
										class:moved-up={movement > 0}
										class:moved-down={movement < 0}
									>
										{movement > 0
											? `↑ ${movement}`
											: movement < 0
												? `↓ ${Math.abs(movement)}`
												: '—'}
									</span>
								</li>
							{/each}
						</ol>
						<button
							class="button button-primary advance-button"
							type="button"
							onclick={advance}
							disabled={busy}
						>
							{busy ? 'Loading answer…' : 'Reveal the correct answer'}
							<span aria-hidden="true">→</span>
						</button>
					</section>
				{:else if room.status === 'active' && room.current_question && room.round_phase === 'answer'}
					<section class="question-card answer-review-card" aria-labelledby="answer-review-title">
						<div class="question-topline">
							<label class="question-picker">
								<span>Question</span>
								<select
									value={room.question_index}
									aria-label="Select a live question"
									disabled={busy}
									onchange={(event) => void selectQuestion(Number(event.currentTarget.value))}
								>
									{#each questionNumbers as questionIndex (questionIndex)}
										<option value={questionIndex}>{questionIndex + 1}</option>
									{/each}
								</select>
								<span>of {room.question_count}</span>
							</label>
						</div>
						<p class="eyebrow answer-review-eyebrow">ANSWER REVEAL</p>
						<h2 id="answer-review-title">{room.current_question.prompt}</h2>
						<div class="answer-options answer-reveal-options">
							{#each room.current_question.options as option, index (option.id)}
								<div class:correct-answer={isCorrectOption(option.id)}>
									<span>{String.fromCharCode(65 + index)}</span>
									<strong>{option.text}</strong>
									{#if isCorrectOption(option.id)}<b>Correct answer</b>{/if}
								</div>
							{/each}
						</div>
						<button
							class="button button-primary advance-button"
							type="button"
							onclick={advance}
							disabled={busy}
						>
							{busy
								? 'Moving on…'
								: room.question_index + 1 === room.question_count
									? 'End game and show winners'
									: 'Next question'}
							<span aria-hidden="true">→</span>
						</button>
						<p class="helper-note">
							Answer choices are now locked. You can revisit any question from the selector.
						</p>
					</section>
				{:else if room.status === 'active' && room.current_question}
					<div class="question-card">
						<div class="question-topline">
							<label class="question-picker">
								<span>Question</span>
								<select
									value={room.question_index}
									aria-label="Select a live question"
									disabled={busy}
									onchange={(event) => void selectQuestion(Number(event.currentTarget.value))}
								>
									{#each questionNumbers as questionIndex (questionIndex)}
										<option value={questionIndex}>{questionIndex + 1}</option>
									{/each}
								</select>
								<span>of {room.question_count}</span>
							</label>
							<div
								class="round-answer-count"
								aria-label="{room.answered_count} of {room.participant_count} learners answered"
							>
								<strong>{room.answered_count}<span> / {room.participant_count}</span></strong>
								<small>answered this round</small>
							</div>
						</div>
						<h2>{room.current_question.prompt}</h2>
						<div
							class="shared-timer"
							class:timer-warning={remaining <= 10}
							class:timer-urgent={remaining <= 5}
							role="timer"
							aria-live="off"
							aria-label="{Math.ceil(
								remaining
							)} seconds remaining on question {room.question_index + 1}"
						>
							<strong>{Math.ceil(remaining)}</strong>
							<span>
								<b>seconds left</b>
								<small
									>{remaining <= 10 ? 'Final seconds — choose now' : 'Shared round timer'}</small
								>
							</span>
						</div>
						<div class="answer-options">
							{#each room.current_question.options as option, index (option.id)}
								<div><span>{String.fromCharCode(65 + index)}</span>{option.text}</div>
							{/each}
						</div>
						<button
							class="button button-primary advance-button"
							type="button"
							onclick={advance}
							disabled={busy}
						>
							{busy ? 'Closing round…' : 'Close round and view leaderboard'}
							<span aria-hidden="true">→</span>
						</button>
						<p class="helper-note">
							Answers pause while you review. Reveal the correct answer before moving on; submitted
							answers can never be changed.
						</p>
					</div>
				{:else}
					<div class="results-card">
						<p class="eyebrow">LIVE SESSION COMPLETE</p>
						<h2>Well played, everyone.</h2>
						<Podium
							entries={room.podium}
							finalized={room.standings_final}
							participantCount={room.participant_count}
						/>
						<div class="standings">
							<h3>Final standings</h3>
							{#each room.standings as entry (entry.rank)}
								<div class="standing-row">
									<span>#{entry.rank}</span><strong>{entry.learner_name}</strong><b
										>{entry.score} pts</b
									>
								</div>
							{/each}
						</div>
					</div>
				{/if}
			</section>

			<aside class="participants-panel" aria-labelledby="participants-heading">
				<div class="participants-heading">
					<div>
						<p class="eyebrow">{room.status === 'waiting' ? 'YOUR ROOM' : 'LIVE STANDINGS'}</p>
						<h2 id="participants-heading">
							{room.status === 'waiting' ? 'Learners' : 'Leaderboard'}
						</h2>
					</div>
					<span class="participant-count">{room.participant_count}</span>
				</div>
				<p class="participants-caption">
					{room.status === 'waiting'
						? 'Names appear here as people join.'
						: room.status === 'active'
							? 'Scores update as answers arrive. Arrows compare this round with where learners started.'
							: 'Final scores for everyone who played.'}
				</p>
				{#if room.status === 'waiting' && room.participants.length}
					<ul class="participant-list" aria-live="polite" aria-relevant="additions text">
						{#each room.participants as participant, index (`${participant.learner_name}-${index}`)}
							<li>
								<span class="avatar" aria-hidden="true">{participantIcon(index)}</span>
								<strong>{participant.learner_name}</strong>
							</li>
						{/each}
					</ul>
				{:else if room.status === 'waiting'}
					<div class="empty-participants">
						<span class="empty-people" aria-hidden="true">◎</span>
						<strong>No one has joined yet</strong>
						<span>Share the link, code, or QR code to welcome your learners.</span>
					</div>
				{/if}
				{#if room.status !== 'waiting' && room.standings.length}
					<ol class="leaderboard-list" aria-label="Current learner standings">
						{#each room.standings as entry (entry.rank)}
							{@const movement = rankMovement(entry)}
							<li class:leader={entry.rank === 1}>
								<span class="leaderboard-rank">#{entry.rank}</span>
								<span class="leaderboard-player">
									<strong>{entry.learner_name}</strong>
									<small>{entry.score} pts</small>
								</span>
								<span
									class="leaderboard-movement"
									class:moved-up={movement > 0}
									class:moved-down={movement < 0}
									aria-label={movement > 0
										? `Moved up ${movement} places`
										: movement < 0
											? `Moved down ${Math.abs(movement)} places`
											: 'No change in position'}
								>
									{movement > 0 ? `↑ ${movement}` : movement < 0 ? `↓ ${Math.abs(movement)}` : '—'}
								</span>
							</li>
						{/each}
					</ol>
				{:else if room.status !== 'waiting'}
					<div class="empty-participants">
						<strong>No standings yet</strong>
						<span>Scores will appear here as learners answer.</span>
					</div>
				{/if}
				{#if room.status === 'waiting'}
					<div class="room-capacity-note">
						Open guest access <span>·</span> No plan-based participant cap
					</div>
				{/if}
			</aside>
		</div>
	{/if}
</main>

<style>
	:global(body) {
		background: #f5f3ee;
	}
	.host-page {
		min-height: calc(100vh - 5rem);
		padding: 1.3rem clamp(1rem, 4vw, 3.5rem) 3rem;
	}
	.session-header,
	.host-layout,
	.host-alert,
	.host-notice {
		width: min(100%, 78rem);
		margin-inline: auto;
	}
	.back-link {
		display: inline-block;
		margin-bottom: 1rem;
		color: var(--ink-muted);
		font-size: 0.78rem;
		font-weight: 700;
		text-decoration: none;
	}
	.session-heading {
		display: flex;
		justify-content: space-between;
		align-items: end;
		gap: 1rem;
		padding-bottom: 1.2rem;
	}
	.session-tools {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: flex-end;
		gap: 0.55rem;
	}
	.session-duration {
		color: var(--ink-muted);
		font-size: 0.72rem;
		font-weight: 750;
	}
	.fullscreen-button {
		padding: 0.55rem 0.75rem;
		border: 1px solid var(--line);
		border-radius: 0.6rem;
		background: white;
		color: var(--navy);
		font: inherit;
		font-size: 0.7rem;
		font-weight: 750;
		cursor: pointer;
	}
	.fullscreen-button:disabled {
		cursor: not-allowed;
		opacity: 0.65;
	}
	.host-page:fullscreen {
		width: 100%;
		min-height: 100vh;
		overflow-y: auto;
		background: #f5f3ee;
	}
	.eyebrow {
		margin: 0 0 0.4rem;
		color: var(--gold-deep);
		font-size: 0.64rem;
		font-weight: 850;
		letter-spacing: 0.14em;
	}
	h1,
	h2,
	h3,
	p {
		margin-top: 0;
	}
	.session-heading h1 {
		margin-bottom: 0;
		color: var(--navy);
		font:
			800 clamp(1.55rem, 4vw, 2.35rem)/1.1 Manrope,
			sans-serif;
		letter-spacing: -0.05em;
	}
	.session-status {
		display: inline-flex;
		align-items: center;
		gap: 0.45rem;
		padding: 0.5rem 0.75rem;
		border-radius: 99px;
		background: #fff;
		color: var(--ink-muted);
		font-size: 0.72rem;
		font-weight: 750;
		white-space: nowrap;
	}
	.session-status > span {
		width: 0.5rem;
		height: 0.5rem;
		border-radius: 50%;
		background: #d1aa67;
	}
	.session-status.active > span {
		background: #238052;
		box-shadow: 0 0 0 3px #e1f1e7;
	}
	.session-status.completed > span {
		background: #516487;
	}
	.host-layout {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 19rem;
		align-items: start;
		gap: 1rem;
	}
	.host-main {
		display: grid;
		gap: 1rem;
		min-width: 0;
	}
	.invite-card,
	.host-action-card,
	.question-card,
	.results-card,
	.participants-panel,
	.host-shell {
		border: 1px solid var(--line);
		border-radius: 1.15rem;
		background: white;
		box-shadow: var(--shadow-card);
	}
	.invite-card {
		display: grid;
		grid-template-columns: minmax(0, 1fr) 13rem;
		gap: 1rem;
		padding: clamp(1rem, 3vw, 1.6rem);
	}
	.invite-content h2,
	.host-action-card h2,
	.question-card h2,
	.results-card h2 {
		margin-bottom: 0.5rem;
		color: var(--navy);
		font:
			750 clamp(1.1rem, 2.5vw, 1.55rem)/1.25 Manrope,
			sans-serif;
	}
	.invite-content > p:not(.eyebrow),
	.host-action-card p:not(.eyebrow) {
		max-width: 43rem;
		margin-bottom: 1.1rem;
		color: var(--ink-muted);
		font-size: 0.78rem;
		line-height: 1.6;
	}
	.join-code-panel {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.8rem;
		padding: 0.85rem 1rem;
		border-radius: 0.85rem;
		background: #f6f4ef;
	}
	.share-label {
		display: block;
		margin-bottom: 0.25rem;
		color: var(--ink-muted);
		font-size: 0.59rem;
		font-weight: 850;
		letter-spacing: 0.14em;
	}
	.share-code {
		color: var(--navy);
		font:
			850 clamp(1.9rem, 6vw, 2.8rem)/1 Manrope,
			sans-serif;
		letter-spacing: 0.2em;
	}
	.copy-icon-button {
		display: grid;
		width: 2.55rem;
		height: 2.55rem;
		place-items: center;
		border: 1px solid var(--line);
		border-radius: 0.65rem;
		background: white;
		color: var(--navy);
		font-size: 1.2rem;
		cursor: pointer;
	}
	.join-link-panel {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.7rem;
		margin-top: 0.7rem;
		padding: 0.85rem 1rem;
		border: 1px solid var(--line);
		border-radius: 0.85rem;
	}
	.join-link-copy {
		min-width: 0;
	}
	.join-link-copy a {
		display: block;
		overflow: hidden;
		color: var(--navy);
		font-size: 0.75rem;
		font-weight: 750;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.join-link-copy small {
		display: block;
		margin-top: 0.3rem;
		color: var(--ink-muted);
		font-size: 0.64rem;
		line-height: 1.4;
	}
	.join-link-panel .button {
		flex: 0 0 auto;
		padding: 0.62rem 0.8rem;
		font-size: 0.72rem;
	}
	.share-button {
		display: inline-flex;
		align-items: center;
		gap: 0.45rem;
		margin-top: 0.7rem;
		padding: 0.55rem 0.8rem;
		border: 0;
		border-radius: 0.7rem;
		background: transparent;
		color: var(--navy);
		font-size: 0.76rem;
		font-weight: 750;
		cursor: pointer;
	}
	.share-button:hover {
		background: #f0f2f7;
	}
	.qr-panel {
		display: flex;
		min-height: 12rem;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		padding: 0.8rem;
		border-radius: 0.9rem;
		background: #f6f4ef;
		text-align: center;
	}
	.qr-panel img,
	.qr-placeholder {
		width: min(100%, 10rem);
		aspect-ratio: 1;
		border: 0.35rem solid white;
		border-radius: 0.8rem;
		background: white;
	}
	.qr-panel strong {
		margin-top: 0.55rem;
		color: var(--navy);
		font-size: 0.76rem;
	}
	.qr-panel > span {
		margin-top: 0.2rem;
		color: var(--ink-muted);
		font-size: 0.64rem;
	}
	.qr-placeholder {
		animation: qr-pulse 1s ease-in-out infinite alternate;
	}
	.host-action-card {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		padding: 1.2rem 1.4rem;
	}
	.host-action-card h2 {
		margin-bottom: 0.3rem;
	}
	.host-action-card p:not(.eyebrow) {
		margin-bottom: 0;
	}
	.host-action-card .button {
		flex: 0 0 auto;
	}
	.participants-panel {
		position: sticky;
		top: 1rem;
		min-height: 25rem;
		padding: 1.2rem;
	}
	.participants-heading {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.5rem;
	}
	.participants-heading .eyebrow {
		margin-bottom: 0.25rem;
	}
	.participants-heading h2 {
		margin: 0;
		color: var(--navy);
		font:
			750 1.15rem Manrope,
			sans-serif;
	}
	.participant-count {
		display: grid;
		min-width: 2.1rem;
		height: 2.1rem;
		place-items: center;
		padding-inline: 0.45rem;
		border-radius: 99px;
		background: #f1eee7;
		color: var(--navy);
		font-size: 0.8rem;
		font-weight: 850;
	}
	.participants-caption {
		margin: 0.55rem 0 1rem;
		color: var(--ink-muted);
		font-size: 0.72rem;
		line-height: 1.5;
	}
	.participant-list {
		display: grid;
		gap: 0.25rem;
		max-height: min(58vh, 36rem);
		overflow: auto;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.participant-list li {
		display: flex;
		min-width: 0;
		align-items: center;
		gap: 0.65rem;
		padding: 0.65rem 0.2rem;
		border-top: 1px solid #eeece6;
	}
	.avatar {
		display: grid;
		width: 2.2rem;
		height: 2.2rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f1eadc;
		color: var(--navy);
		font-size: 0.95rem;
		font-weight: 850;
	}
	.participant-list li:nth-child(3n + 2) .avatar {
		background: #eaf0f6;
		color: #35567d;
	}
	.participant-list li:nth-child(3n) .avatar {
		background: #f6e9e7;
		color: #8e463a;
	}
	.participant-list li strong {
		overflow: hidden;
		color: var(--ink);
		font-size: 0.8rem;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.empty-participants {
		display: grid;
		justify-items: center;
		gap: 0.55rem;
		padding: 3.5rem 1rem 2rem;
		text-align: center;
	}
	.empty-people {
		display: grid;
		width: 3.3rem;
		height: 3.3rem;
		place-items: center;
		border-radius: 1.2rem;
		background: #f1f2f5;
		color: var(--navy);
		font-size: 1.8rem;
	}
	.empty-participants strong {
		color: var(--navy);
		font-size: 0.82rem;
	}
	.empty-participants > span:last-child {
		max-width: 13rem;
		color: var(--ink-muted);
		font-size: 0.69rem;
		line-height: 1.5;
	}
	.room-capacity-note {
		margin-top: 1.4rem;
		padding-top: 0.8rem;
		border-top: 1px solid var(--line);
		color: var(--ink-muted);
		font-size: 0.65rem;
		text-align: center;
	}
	.room-capacity-note span {
		padding-inline: 0.25rem;
		color: var(--gold-deep);
	}
	.round-review-card {
		display: grid;
		gap: 1.1rem;
		padding: clamp(1rem, 3vw, 1.6rem);
	}
	.review-heading,
	.review-tools {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 0.75rem;
	}
	.review-heading > .eyebrow {
		margin: 0;
	}
	.review-tools {
		flex-wrap: wrap;
		justify-content: flex-end;
	}
	.review-hero {
		display: grid;
		justify-items: center;
		padding: 0.5rem 0 0.2rem;
		text-align: center;
	}
	.review-orbit {
		position: relative;
		display: grid;
		width: 4.2rem;
		height: 4.2rem;
		place-items: center;
		margin-bottom: 0.7rem;
		border: 1px solid #e5d4ad;
		border-radius: 50%;
		background: radial-gradient(circle, #fffaf0 0 30%, #f7edd9 70%, #efe2c7);
		color: var(--gold-deep);
		font-size: 1.5rem;
		box-shadow: 0 0 0 0.55rem #d1a95814;
	}
	.review-orbit span {
		position: absolute;
		inset: 0.35rem;
		border: 1px solid #c79d574d;
		border-radius: 50%;
		animation: orbit-turn 8s linear infinite;
	}
	.review-orbit span::after {
		position: absolute;
		top: -0.16rem;
		left: 50%;
		width: 0.34rem;
		height: 0.34rem;
		border-radius: 50%;
		background: #c79d57;
		content: '';
	}
	@keyframes orbit-turn {
		to {
			transform: rotate(360deg);
		}
	}
	.review-hero h2 {
		margin: 0;
		color: var(--navy);
		font:
			800 clamp(1.5rem, 4vw, 2.2rem) Manrope,
			sans-serif;
		letter-spacing: -0.04em;
	}
	.review-hero p {
		max-width: 32rem;
		margin: 0.45rem 0 0;
		color: var(--ink-muted);
		font-size: 0.78rem;
		line-height: 1.55;
	}
	.review-standings {
		display: grid;
		gap: 0.45rem;
		max-height: min(45vh, 24rem);
		overflow: auto;
		margin: 0;
		padding: 0.15rem;
		list-style: none;
	}
	.review-standings li {
		display: flex;
		min-width: 0;
		align-items: center;
		gap: 0.75rem;
		padding: 0.7rem 0.8rem;
		border: 1px solid #eeece6;
		border-radius: 0.75rem;
		background: #fff;
	}
	.review-standings li.review-leader {
		border-color: #e5d4ad;
		background: #fffaf0;
	}
	.review-rank {
		display: grid;
		width: 2.1rem;
		height: 2.1rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f1eee7;
		color: var(--navy);
		font-size: 0.7rem;
		font-weight: 850;
	}
	.review-leader .review-rank {
		background: #f4e3b6;
	}
	.review-player {
		display: grid;
		min-width: 0;
		gap: 0.1rem;
	}
	.review-player strong {
		overflow: hidden;
		color: var(--ink);
		font-size: 0.8rem;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.review-player small {
		color: var(--ink-muted);
		font-size: 0.66rem;
	}
	.answer-review-card h2 {
		margin-block: 0.3rem 0.5rem;
	}
	.answer-review-eyebrow {
		margin: 1.2rem 0 0;
	}
	.answer-reveal-options div.correct-answer {
		border-color: #99c9a9;
		background: #edf7ef;
		color: #1f643c;
	}
	.answer-reveal-options div.correct-answer span {
		background: #d6ecdc;
		color: #1f643c;
	}
	.answer-reveal-options div.correct-answer b {
		margin-left: auto;
		color: #25744d;
		font-size: 0.64rem;
		white-space: nowrap;
	}
	.question-card,
	.results-card {
		padding: clamp(1rem, 3vw, 1.6rem);
	}
	.question-topline {
		display: flex;
		align-items: center;
		justify-content: space-between;
		flex-wrap: wrap;
		gap: 0.7rem;
		color: var(--ink-muted);
		font-size: 0.68rem;
		font-weight: 850;
	}
	.question-picker {
		display: inline-flex;
		align-items: center;
		gap: 0.45rem;
	}
	.question-picker select {
		min-width: 3rem;
		padding: 0.45rem 0.6rem;
		border: 1px solid var(--line);
		border-radius: 0.55rem;
		background: white;
		color: var(--navy);
		font: inherit;
		font-size: 0.8rem;
		font-weight: 850;
	}
	.round-answer-count {
		display: grid;
		gap: 0.1rem;
		padding: 0.4rem 0.7rem;
		border: 1px solid var(--line);
		border-radius: 0.65rem;
		background: #fffdf9;
		text-align: center;
	}
	.round-answer-count strong {
		color: var(--navy);
		font-size: 0.85rem;
	}
	.round-answer-count strong span {
		color: var(--ink-muted);
		font-weight: 650;
	}
	.round-answer-count small {
		color: var(--ink-muted);
		font-size: 0.58rem;
		font-weight: 700;
	}
	.question-card h2 {
		margin-block: 1.25rem 0.5rem;
		font-size: clamp(1.35rem, 3vw, 2rem);
	}
	.helper-note {
		color: var(--ink-muted);
		font-size: 0.76rem;
	}
	.shared-timer {
		display: flex;
		align-items: center;
		gap: 1rem;
		width: fit-content;
		margin-block: 1.2rem;
		padding: 0.8rem 1.2rem;
		border: 2px solid #e5d4ad;
		border-radius: 1.1rem;
		background: #fffaf0;
		color: var(--navy);
		transition:
			border-color 200ms ease,
			background-color 200ms ease,
			color 200ms ease;
	}
	.shared-timer > strong {
		min-width: 4.8rem;
		font:
			850 clamp(3rem, 8vw, 5rem)/0.95 Manrope,
			sans-serif;
		letter-spacing: -0.08em;
		text-align: center;
		font-variant-numeric: tabular-nums;
	}
	.shared-timer > span {
		display: grid;
		gap: 0.25rem;
	}
	.shared-timer b {
		font-size: 0.9rem;
	}
	.shared-timer small {
		color: var(--ink-muted);
		font-size: 0.7rem;
	}
	.shared-timer.timer-warning {
		border-color: #df9c48;
		background: #fff4e2;
		color: #9a5c13;
	}
	.shared-timer.timer-urgent {
		border-color: #bd6752;
		background: #fff0ec;
		color: #9a3f2d;
		animation: timer-pulse 750ms ease-in-out infinite alternate;
	}
	@keyframes timer-pulse {
		to {
			box-shadow: 0 0 0.9rem #bd67524d;
		}
	}
	.answer-options {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 0.55rem;
		margin-block: 1.2rem;
	}
	.answer-options div {
		display: flex;
		align-items: center;
		gap: 0.6rem;
		padding: 0.7rem;
		border: 1px solid var(--line);
		border-radius: 0.7rem;
		color: var(--ink);
		font-size: 0.78rem;
	}
	.answer-options div span {
		display: grid;
		width: 1.5rem;
		height: 1.5rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f2efe8;
		color: var(--navy);
		font-size: 0.66rem;
		font-weight: 850;
	}
	.advance-button {
		display: flex;
		width: 100%;
		justify-content: center;
		gap: 0.45rem;
	}
	.helper-note {
		margin: 0.7rem 0 0;
		font-size: 0.68rem;
		line-height: 1.5;
	}
	.standings {
		margin-top: 1rem;
	}
	.standings h3 {
		color: var(--navy);
		font-size: 0.95rem;
	}
	.standing-row {
		display: grid;
		grid-template-columns: 2rem 1fr auto;
		gap: 0.6rem;
		align-items: center;
		padding: 0.7rem 0;
		border-top: 1px solid var(--line);
		font-size: 0.78rem;
	}
	.standing-row span {
		color: var(--gold-deep);
		font-weight: 850;
	}
	.standing-row b {
		color: var(--navy);
	}
	.leaderboard-list {
		display: grid;
		gap: 0.45rem;
		max-height: min(66vh, 42rem);
		overflow: auto;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.leaderboard-list li {
		display: flex;
		min-width: 0;
		align-items: center;
		gap: 0.7rem;
		padding: 0.75rem;
		border: 1px solid #eeece6;
		border-radius: 0.75rem;
		background: #fff;
	}
	.leaderboard-list li.leader {
		border-color: #e5d4ad;
		background: #fffaf0;
	}
	.leaderboard-rank {
		display: grid;
		width: 2rem;
		height: 2rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f1eee7;
		color: var(--navy);
		font-size: 0.7rem;
		font-weight: 850;
	}
	.leaderboard-list li.leader .leaderboard-rank {
		background: #f4e3b6;
	}
	.leaderboard-player {
		display: grid;
		min-width: 0;
		gap: 0.15rem;
	}
	.leaderboard-player strong {
		overflow: hidden;
		color: var(--ink);
		font-size: 0.78rem;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.leaderboard-player small {
		color: var(--ink-muted);
		font-size: 0.66rem;
		font-weight: 700;
	}
	.leaderboard-movement {
		margin-left: auto;
		padding: 0.25rem 0.4rem;
		border-radius: 0.45rem;
		background: #f1f0ec;
		color: var(--ink-muted);
		font-size: 0.65rem;
		font-weight: 850;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.leaderboard-movement.moved-up {
		background: #e8f4ec;
		color: #25744d;
	}
	.leaderboard-movement.moved-down {
		background: #fff0ee;
		color: #9a3f2d;
	}
	.host-alert,
	.host-notice {
		margin-block: 0 1rem;
		padding: 0.8rem 1rem;
		border-radius: 0.7rem;
		font-size: 0.78rem;
	}
	.host-alert {
		background: #fff0ee;
		color: #8e3026;
	}
	.host-notice {
		background: #eaf5ed;
		color: #236143;
	}
	.host-shell {
		display: grid;
		width: min(100%, 44rem);
		gap: 0.8rem;
		margin: 3rem auto;
		padding: 2rem;
	}
	.host-shell h1 {
		margin: 0;
		color: var(--navy);
		font:
			800 2rem Manrope,
			sans-serif;
	}
	.host-shell p {
		color: var(--ink-muted);
	}
	.loading-shell span {
		height: 1rem;
		border-radius: 99px;
		background: #f0eee9;
	}
	.loading-shell span:first-child {
		width: 35%;
		height: 1.5rem;
	}
	.loading-shell span:last-child {
		width: 70%;
	}
	@keyframes qr-pulse {
		to {
			opacity: 0.5;
		}
	}
	@media (max-width: 850px) {
		.host-layout {
			grid-template-columns: minmax(0, 1fr) 16rem;
		}
		.invite-card {
			grid-template-columns: minmax(0, 1fr) 10rem;
		}
	}
	@media (max-width: 680px) {
		.host-layout {
			grid-template-columns: 1fr;
		}
		.participants-panel {
			position: static;
			min-height: 0;
			grid-row: 1;
		}
		.invite-card {
			grid-template-columns: 1fr;
		}
		.qr-panel {
			display: grid;
			min-height: 0;
			grid-template-columns: 5rem 1fr;
			justify-items: start;
			gap: 0.15rem 0.75rem;
			text-align: left;
		}
		.qr-panel img,
		.qr-placeholder {
			width: 5rem;
			grid-row: span 2;
		}
		.qr-panel strong {
			align-self: end;
			margin-top: 0;
		}
		.qr-panel > span {
			align-self: start;
		}
		.host-action-card {
			align-items: stretch;
			flex-direction: column;
		}
		.answer-options {
			grid-template-columns: 1fr;
		}
		.session-heading {
			align-items: start;
			flex-direction: column;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.shared-timer.timer-urgent {
			animation: none;
		}
		.qr-placeholder {
			animation: none;
		}
	}
	.host-page:fullscreen.fullscreen-lobby {
		box-sizing: border-box;
		min-height: 100vh;
		padding: clamp(1.5rem, 3vh, 3rem) clamp(1.5rem, 5vw, 5rem);
	}
	.host-page:fullscreen.fullscreen-lobby .session-header,
	.host-page:fullscreen.fullscreen-lobby .host-layout,
	.host-page:fullscreen.fullscreen-lobby .host-alert,
	.host-page:fullscreen.fullscreen-lobby .host-notice {
		width: min(100%, 112rem);
	}
	.host-page:fullscreen.fullscreen-lobby .session-heading {
		padding-bottom: clamp(1.5rem, 3vh, 2.5rem);
	}
	.host-page:fullscreen.fullscreen-lobby .session-heading h1 {
		font-size: clamp(2.25rem, 4vw, 4rem);
	}
	.host-page:fullscreen.fullscreen-lobby .eyebrow {
		font-size: clamp(0.72rem, 0.9vw, 0.9rem);
	}
	.host-page:fullscreen.fullscreen-lobby .session-tools {
		gap: 0.8rem;
	}
	.host-page:fullscreen.fullscreen-lobby .fullscreen-button,
	.host-page:fullscreen.fullscreen-lobby .session-status {
		padding: 0.75rem 1rem;
		font-size: 0.9rem;
	}
	.host-page:fullscreen.fullscreen-lobby .host-layout {
		grid-template-columns: minmax(0, 1.7fr) minmax(20rem, 0.9fr);
		align-items: stretch;
		gap: clamp(1.25rem, 2vw, 2rem);
		min-height: max(36rem, calc(100vh - 12rem));
	}
	.host-page:fullscreen.fullscreen-lobby .host-main {
		grid-template-rows: minmax(0, 1fr) auto;
		gap: clamp(1.25rem, 2vh, 2rem);
	}
	.host-page:fullscreen.fullscreen-lobby .invite-card {
		grid-template-columns: minmax(0, 1fr) minmax(16rem, 0.48fr);
		align-items: stretch;
		gap: clamp(1.25rem, 2vw, 2rem);
		padding: clamp(1.75rem, 3vw, 3rem);
	}
	.host-page:fullscreen.fullscreen-lobby .invite-content h2,
	.host-page:fullscreen.fullscreen-lobby .host-action-card h2 {
		font-size: clamp(1.65rem, 2.5vw, 2.4rem);
	}
	.host-page:fullscreen.fullscreen-lobby .invite-content > p:not(.eyebrow),
	.host-page:fullscreen.fullscreen-lobby .host-action-card p:not(.eyebrow) {
		max-width: 55rem;
		font-size: clamp(0.95rem, 1.1vw, 1.15rem);
	}
	.host-page:fullscreen.fullscreen-lobby .join-code-panel,
	.host-page:fullscreen.fullscreen-lobby .join-link-panel {
		padding: clamp(1rem, 1.5vw, 1.5rem);
	}
	.host-page:fullscreen.fullscreen-lobby .share-label {
		font-size: 0.75rem;
	}
	.host-page:fullscreen.fullscreen-lobby .share-code {
		font-size: clamp(2.75rem, 5vw, 4.5rem);
	}
	.host-page:fullscreen.fullscreen-lobby .copy-icon-button {
		width: 3.25rem;
		height: 3.25rem;
	}
	.host-page:fullscreen.fullscreen-lobby .join-link-copy a {
		font-size: clamp(0.9rem, 1.1vw, 1.1rem);
	}
	.host-page:fullscreen.fullscreen-lobby .join-link-copy small {
		font-size: 0.8rem;
	}
	.host-page:fullscreen.fullscreen-lobby .join-link-panel .button,
	.host-page:fullscreen.fullscreen-lobby .share-button {
		font-size: 0.9rem;
	}
	.host-page:fullscreen.fullscreen-lobby .qr-panel {
		min-height: 100%;
		padding: clamp(1rem, 2vw, 2rem);
	}
	.host-page:fullscreen.fullscreen-lobby .qr-panel img,
	.host-page:fullscreen.fullscreen-lobby .qr-placeholder {
		width: min(100%, 17rem);
	}
	.host-page:fullscreen.fullscreen-lobby .qr-panel strong {
		font-size: 1rem;
	}
	.host-page:fullscreen.fullscreen-lobby .qr-panel > span {
		font-size: 0.85rem;
	}
	.host-page:fullscreen.fullscreen-lobby .host-action-card {
		padding: clamp(1.5rem, 2.5vw, 2.5rem);
	}
	.host-page:fullscreen.fullscreen-lobby .host-action-card .button {
		padding: 1rem 1.5rem;
		font-size: 1rem;
	}
	.host-page:fullscreen.fullscreen-lobby .participants-panel {
		position: static;
		min-height: 100%;
		padding: clamp(1.5rem, 2.5vw, 2.5rem);
	}
	.host-page:fullscreen.fullscreen-lobby .participants-heading h2 {
		font-size: 1.6rem;
	}
	.host-page:fullscreen.fullscreen-lobby .participant-count {
		min-width: 2.75rem;
		height: 2.75rem;
		font-size: 1rem;
	}
	.host-page:fullscreen.fullscreen-lobby .participants-caption {
		font-size: 0.9rem;
	}
	.host-page:fullscreen.fullscreen-lobby .empty-participants {
		min-height: 20rem;
		align-content: center;
		gap: 0.9rem;
	}
	.host-page:fullscreen.fullscreen-lobby .empty-people {
		width: 4.5rem;
		height: 4.5rem;
		font-size: 2.25rem;
	}
	.host-page:fullscreen.fullscreen-lobby .empty-participants strong {
		font-size: 1.1rem;
	}
	.host-page:fullscreen.fullscreen-lobby .empty-participants > span:last-child {
		max-width: 20rem;
		font-size: 0.9rem;
	}
	.host-page:fullscreen.fullscreen-lobby .participant-list li {
		gap: 0.9rem;
		padding-block: 0.9rem;
	}
	.host-page:fullscreen.fullscreen-lobby .avatar {
		width: 2.75rem;
		height: 2.75rem;
		font-size: 1.1rem;
	}
	.host-page:fullscreen.fullscreen-lobby .participant-list li strong {
		font-size: 1rem;
	}
	.host-page:fullscreen.fullscreen-lobby .room-capacity-note {
		font-size: 0.8rem;
	}
	@media (max-width: 900px) {
		.host-page:fullscreen.fullscreen-lobby .host-layout {
			grid-template-columns: minmax(0, 1.4fr) minmax(16rem, 0.8fr);
		}
		.host-page:fullscreen.fullscreen-lobby .invite-card {
			grid-template-columns: minmax(0, 1fr) minmax(12rem, 0.45fr);
		}
	}
	@media (max-width: 680px) {
		.host-page:fullscreen.fullscreen-lobby .host-layout {
			grid-template-columns: 1fr;
		}
		.host-page:fullscreen.fullscreen-lobby .participants-panel {
			grid-row: auto;
			min-height: 20rem;
		}
		.host-page:fullscreen.fullscreen-lobby .invite-card {
			grid-template-columns: 1fr;
		}
		.host-page:fullscreen.fullscreen-lobby .qr-panel {
			min-height: 15rem;
		}
		.host-page:fullscreen.fullscreen-lobby .qr-panel img,
		.host-page:fullscreen.fullscreen-lobby .qr-placeholder {
			width: min(100%, 10rem);
		}
	}
</style>
