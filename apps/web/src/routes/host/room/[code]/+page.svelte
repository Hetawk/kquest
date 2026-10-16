<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import QRCode from 'qrcode';
	import Podium from '#lib/features/activities/components/Podium.svelte';
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
	const roomCode = $derived(data.code.toUpperCase());
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

		const refresh = async () => {
			if (refreshing || document.visibilityState === 'hidden') return;
			refreshing = true;
			try {
				const updated = await fetchGameRoom(roomCode);
				if (!disposed) {
					room = updated;
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
		return () => {
			disposed = true;
			window.clearInterval(timer);
		};
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
			room = await startGameRoom(roomCode);
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
			room = await advanceGameRoom(roomCode);
		} catch (cause) {
			error =
				cause instanceof Error
					? cause.message
					: 'The group could not advance to the next question.';
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
</script>

<svelte:head>
	<title>{room ? `${room.title} — Host room` : 'Host live room'} — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="host-page">
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
				{:else if room.status === 'active' && room.current_question}
					<div class="question-card">
						<div class="question-topline">
							<span>QUESTION {room.question_index + 1} / {room.question_count}</span>
							<span>{room.answered_count} / {room.participant_count} answered</span>
						</div>
						<h2>{room.current_question.prompt}</h2>
						{#if room.current_question.time_limit_seconds > 0}
							<p class="timer-note">
								Shared timer: <strong>{Math.ceil(room.time_remaining_seconds)} seconds</strong> remaining
							</p>
						{:else}
							<p class="timer-note">This question is untimed.</p>
						{/if}
						<div
							class="answer-meter"
							role="progressbar"
							aria-label="Participants answered"
							aria-valuenow={room.answered_count}
							aria-valuemin="0"
							aria-valuemax={room.participant_count}
						>
							<span
								style={`width:${room.participant_count ? (room.answered_count / room.participant_count) * 100 : 0}%`}
							></span>
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
							{busy
								? 'Moving on…'
								: room.question_index + 1 === room.question_count
									? 'End game and show winners'
									: 'End round and advance'}
							<span aria-hidden="true">→</span>
						</button>
						<p class="helper-note">
							Unanswered learners receive zero when you advance. Wait for more answers or move the
							group forward.
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
						<p class="eyebrow">YOUR ROOM</p>
						<h2 id="participants-heading">Learners</h2>
					</div>
					<span class="participant-count">{room.participant_count}</span>
				</div>
				<p class="participants-caption">
					{room.status === 'waiting'
						? 'Names appear here as people join.'
						: room.status === 'active'
							? 'Live progress updates automatically.'
							: 'Thanks for playing together.'}
				</p>
				{#if room.participants.length}
					<ul class="participant-list" aria-live="polite" aria-relevant="additions text">
						{#each room.participants as participant, index (`${participant.learner_name}-${index}`)}
							<li>
								<span class="avatar" aria-hidden="true">{participantIcon(index)}</span>
								<strong>{participant.learner_name}</strong>
								{#if room.status === 'active'}
									<span
										class:answered={room.participants[index]?.answered}
										class="participant-state"
									>
										{room.participants[index]?.answered ? 'Answered' : 'Playing'}
									</span>
								{/if}
							</li>
						{/each}
					</ul>
				{:else}
					<div class="empty-participants">
						<span class="empty-people" aria-hidden="true">◎</span>
						<strong>No one has joined yet</strong>
						<span>Share the link, code, or QR code to welcome your learners.</span>
					</div>
				{/if}
				<div class="room-capacity-note">
					Open guest access <span>·</span> No plan-based participant cap
				</div>
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
	.participant-state {
		margin-left: auto;
		color: var(--ink-muted);
		font-size: 0.64rem;
	}
	.participant-state.answered {
		color: #25744d;
		font-weight: 800;
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
	.question-card,
	.results-card {
		padding: clamp(1rem, 3vw, 1.6rem);
	}
	.question-topline {
		display: flex;
		justify-content: space-between;
		gap: 0.5rem;
		color: var(--ink-muted);
		font-size: 0.68rem;
		font-weight: 850;
	}
	.question-card h2 {
		margin-block: 1.2rem 0.4rem;
		font-size: clamp(1.35rem, 3vw, 2rem);
	}
	.timer-note,
	.helper-note {
		color: var(--ink-muted);
		font-size: 0.76rem;
	}
	.timer-note strong {
		color: var(--navy);
	}
	.answer-meter {
		height: 0.55rem;
		overflow: hidden;
		margin: 1rem 0;
		border-radius: 99px;
		background: #eee9df;
	}
	.answer-meter span {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--gold-deep);
		transition: width 180ms ease;
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
		.answer-meter span {
			transition: none;
		}
		.qr-placeholder {
			animation: none;
		}
	}
</style>
