<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import Podium from '#lib/features/activities/components/Podium.svelte';
	import { advanceGameRoom, fetchGameRoom, startGameRoom } from '#lib/features/activities/api.js';
	import type { GameRoom } from '#lib/features/activities/types.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	let room = $state<GameRoom | null>(null);
	let loading = $state(true);
	let busy = $state(false);
	let error = $state('');
	let copied = $state(false);
	const roomCode = $derived(data.code.toUpperCase());
	const joinLink = $derived(
		typeof window === 'undefined' ? '' : `${window.location.origin}/join/${roomCode}`
	);

	onMount(() => {
		let disposed = false;
		const refresh = async () => {
			try {
				const updated = await fetchGameRoom(roomCode);
				if (!disposed) {
					room = updated;
					error = '';
				}
			} catch (cause) {
				if (!disposed)
					error = cause instanceof Error ? cause.message : 'Could not refresh the live room.';
			} finally {
				if (!disposed) loading = false;
			}
		};
		void refresh();
		const timer = window.setInterval(() => void refresh(), 2000);
		return () => {
			disposed = true;
			window.clearInterval(timer);
		};
	});

	async function start() {
		if (busy) return;
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
		if (busy) return;
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

	async function copyLink() {
		try {
			await navigator.clipboard.writeText(joinLink);
			copied = true;
			window.setTimeout(() => (copied = false), 1600);
		} catch {
			error = 'Copying is unavailable here. Share the visible game code instead.';
		}
	}
</script>

<svelte:head>
	<title>{room ? `${room.title} — Host room` : 'Host live room'} — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell host-page">
	{#if loading && !room}
		<section class="host-card">
			<p class="eyebrow">Live room</p>
			<h1>Opening your room…</h1>
		</section>
	{:else if !room}
		<section class="host-card">
			<p class="eyebrow">Live room</p>
			<h1>We can’t open this room.</h1>
			<p>{error}</p>
			<a class="button button-primary" href={resolve('/')}>Back to KINGDOM Quest</a>
		</section>
	{:else}
		<section class="host-card">
			<p class="eyebrow">Host-controlled live room</p>
			<h1>{room.title}</h1>
			<p class="intro">
				Share this link or code. Players can join as guests and choose a display name before the
				game starts.
			</p>
			<div class="share-panel">
				<span class="share-label">GAME CODE</span>
				<strong class="share-code">{room.room_code}</strong>
				<button type="button" class="button button-outline" onclick={copyLink}
					>{copied ? 'Link copied!' : 'Copy join link'}</button
				>
				<code>{joinLink}</code>
			</div>

			<div class="room-status">
				<span class:live={room.status === 'active'} class="status-dot"></span>
				<strong
					>{room.status === 'waiting'
						? 'Waiting for players'
						: room.status === 'active'
							? 'Live game in progress'
							: 'Game complete'}</strong
				>
				<span
					>{room.participant_count}
					{room.participant_count === 1 ? 'player' : 'players'} joined</span
				>
			</div>

			{#if room.status === 'waiting'}
				<div class="participant-list">
					<h2>Players in the room</h2>
					{#if room.participants.length}
						<ul>
							{#each room.participants as participant, index (`${participant.learner_name}-${index}`)}<li
								>
									{participant.learner_name}
								</li>{/each}
						</ul>
					{:else}<p>Share your invite to welcome the first player.</p>{/if}
				</div>
				<button
					class="button button-primary room-action"
					type="button"
					onclick={start}
					disabled={busy || room.participant_count === 0}
				>
					{busy ? 'Starting…' : 'Start the live game'} <span aria-hidden="true">↗</span>
				</button>
				<p class="help-text">
					Starting synchronizes question one for everyone. You control when the group moves on.
				</p>
			{:else if room.status === 'active' && room.current_question}
				<div class="host-question">
					<div class="question-topline">
						<span>QUESTION {room.question_index + 1} / {room.question_count}</span><span
							>{room.answered_count} / {room.participant_count} answered</span
						>
					</div>
					<h2>{room.current_question.prompt}</h2>
					{#if room.current_question.time_limit_seconds > 0}<p>
							Shared round timer: {Math.ceil(room.time_remaining_seconds)} seconds remaining
						</p>{:else}<p>This question is untimed.</p>{/if}
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
					<button
						class="button button-primary room-action"
						type="button"
						onclick={advance}
						disabled={busy}
					>
						{busy
							? 'Moving on…'
							: room.question_index + 1 === room.question_count
								? 'End game and show winners'
								: 'End this round and advance'} <span aria-hidden="true">→</span>
					</button>
					<p class="help-text">
						Unanswered players receive zero for this round when you advance. You can wait for more
						answers or move the group forward.
					</p>
				</div>
			{:else}
				<Podium
					entries={room.podium}
					finalized={room.standings_final}
					participantCount={room.participant_count}
				/>
				<div class="full-standings">
					<h2>Final standings</h2>
					{#each room.standings as entry (entry.rank)}<div class="standing-row">
							<span>#{entry.rank}</span><strong>{entry.learner_name}</strong><b>{entry.score} pts</b
							>
						</div>{/each}
				</div>
				<a class="button button-outline room-action" href={resolve('/')}>Back to studio</a>
			{/if}
			{#if error}<p class="error-message" role="alert">{error}</p>{/if}
		</section>
	{/if}
</main>

<style>
	.host-page {
		min-height: 75vh;
		padding-block: 2rem 4rem;
	}
	.host-card {
		width: min(100%, 52rem);
		margin-inline: auto;
		padding: clamp(1.2rem, 4vw, 2.3rem);
		border: 1px solid var(--line);
		border-radius: 1.3rem;
		background: white;
		box-shadow: var(--shadow-card);
	}
	.host-card h1 {
		margin: 0.5rem 0;
		color: var(--navy);
		font-family: Manrope, sans-serif;
		font-size: clamp(1.8rem, 5vw, 3rem);
		letter-spacing: -0.06em;
	}
	.intro,
	.help-text {
		color: var(--ink-muted);
		font-size: 0.83rem;
		line-height: 1.6;
	}
	.share-panel {
		display: grid;
		justify-items: center;
		gap: 0.55rem;
		margin: 1.4rem 0;
		padding: 1.2rem;
		border: 1px solid #e9dfcc;
		border-radius: 1rem;
		background: #fcf8ef;
	}
	.share-label {
		color: var(--ink-muted);
		font-size: 0.65rem;
		font-weight: 800;
		letter-spacing: 0.15em;
	}
	.share-code {
		color: var(--navy);
		font-family: Manrope, sans-serif;
		font-size: clamp(1.5rem, 7vw, 2.5rem);
		font-weight: 900;
		letter-spacing: 0.18em;
	}
	.share-panel code {
		overflow-wrap: anywhere;
		color: var(--ink-muted);
		font-size: 0.7rem;
	}
	.room-status {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 0.5rem;
		margin: 1.4rem 0;
		padding: 0.9rem;
		border-radius: 0.8rem;
		background: #f5f3ed;
		font-size: 0.8rem;
	}
	.room-status > span:last-child {
		margin-left: auto;
		color: var(--ink-muted);
	}
	.status-dot {
		width: 0.55rem;
		height: 0.55rem;
		border-radius: 50%;
		background: #c0b7a6;
	}
	.status-dot.live {
		background: #268452;
		box-shadow: 0 0 0 4px #e0f1e7;
	}
	.participant-list,
	.host-question,
	.full-standings {
		margin-top: 1.4rem;
		padding: 1rem;
		border: 1px solid var(--line);
		border-radius: 0.9rem;
	}
	.participant-list h2,
	.host-question h2,
	.full-standings h2 {
		margin: 0 0 0.8rem;
		color: var(--navy);
		font-size: 1rem;
	}
	.participant-list ul {
		display: flex;
		flex-wrap: wrap;
		gap: 0.5rem;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.participant-list li {
		padding: 0.5rem 0.75rem;
		border-radius: 99px;
		background: #f4f0e6;
		font-size: 0.78rem;
		font-weight: 700;
	}
	.participant-list p,
	.host-question p {
		color: var(--ink-muted);
		font-size: 0.78rem;
	}
	.room-action {
		display: flex;
		width: 100%;
		justify-content: center;
		margin-top: 1rem;
	}
	.question-topline {
		display: flex;
		flex-wrap: wrap;
		justify-content: space-between;
		gap: 0.5rem;
		color: var(--ink-muted);
		font-size: 0.7rem;
		font-weight: 800;
	}
	.host-question h2 {
		margin-block: 1.3rem 0.4rem;
		font-size: clamp(1.3rem, 4vw, 2rem);
	}
	.answer-meter {
		height: 0.55rem;
		overflow: hidden;
		border-radius: 99px;
		background: #eee9df;
	}
	.answer-meter span {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--gold-deep);
		transition: width 200ms ease;
	}
	.standing-row {
		display: grid;
		grid-template-columns: 2.5rem 1fr auto;
		gap: 0.6rem;
		align-items: center;
		padding: 0.75rem 0;
		border-top: 1px solid var(--line);
		font-size: 0.82rem;
	}
	.standing-row span {
		color: var(--gold-deep);
		font-weight: 800;
	}
	.standing-row b {
		color: var(--navy);
	}
</style>
