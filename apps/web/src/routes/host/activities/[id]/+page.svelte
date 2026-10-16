<script lang="ts">
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import {
		createGameRoom,
		getCreatorActivity,
		getCurrentUser
	} from '#lib/features/activities/api.js';
	import type { CreatorActivityDetail } from '#lib/features/activities/api.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	let activity = $state<CreatorActivityDetail | null>(null);
	let mode = $state<'host_paced' | 'self_paced'>('host_paced');
	let step = $state<'mode' | 'settings'>('mode');
	let loading = $state(true);
	let starting = $state(false);
	let error = $state('');

	onMount(() => {
		void (async () => {
			try {
				const user = await getCurrentUser();
				if (!user) {
					window.location.replace(
						`${resolve('/auth')}?next=${encodeURIComponent(window.location.pathname)}`
					);
					return;
				}
				activity = await getCreatorActivity(data.activityId);
				if (!activity.share_code) {
					error = 'Publish this quest before starting a session.';
				}
			} catch (cause) {
				error = cause instanceof Error ? cause.message : 'This quest could not be prepared.';
			} finally {
				loading = false;
			}
		})();
	});

	async function startSession() {
		if (!activity?.share_code || starting) return;
		starting = true;
		error = '';
		try {
			if (mode === 'host_paced') {
				const room = await createGameRoom(activity.id);
				await goto(resolve('/host/room/[code]', { code: room.room_code }));
			} else {
				const joinUrl = new URL(resolve('/join'), window.location.origin);
				joinUrl.searchParams.set('code', activity.share_code);
				// eslint-disable-next-line svelte/no-navigation-without-resolve
				await goto(joinUrl);
			}
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'This session could not be started.';
		} finally {
			starting = false;
		}
	}
</script>

<svelte:head>
	<title
		>{activity
			? `Start ${activity.title} — KINGDOM Quest`
			: 'Start a session — KINGDOM Quest'}</title
	>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell setup-page">
	<a
		class="back-link"
		href={activity ? resolve('/dashboard/quests/[id]', { id: activity.id }) : resolve('/dashboard')}
	>
		← Back to quest
	</a>
	{#if loading}
		<section class="setup-card loading" role="status" aria-label="Loading session setup">
			<span class="loading-mark"></span><span class="loading-line"></span><span
				class="loading-line short"
			></span>
		</section>
	{:else if !activity}
		<section class="setup-card">
			<p class="eyebrow">Session setup</p>
			<h1>We couldn’t prepare this quest.</h1>
			<p>{error}</p>
			<a class="button button-primary" href={resolve('/dashboard')}>Back to your studio</a>
		</section>
	{:else}
		<div class="setup-heading">
			<div>
				<p class="eyebrow">START A SESSION</p>
				<h1>{activity.title}</h1>
				<p>Choose how your learners will experience this quest.</p>
			</div>
			<div class="step-count"><span>{step === 'mode' ? '01' : '02'}</span> / 02</div>
		</div>
		<div class="step-track" aria-hidden="true">
			<span class:complete={step === 'settings'}></span>
		</div>
		{#if step === 'mode'}
			<section class="setup-card" aria-labelledby="mode-heading">
				<p class="eyebrow">PLAY STYLE</p>
				<h2 id="mode-heading">How should the group play?</h2>
				<p class="section-copy">You can change this choice before the session begins.</p>
				<div class="mode-grid">
					<label class="mode-card" class:selected={mode === 'self_paced'}>
						<input type="radio" name="session-mode" value="self_paced" bind:group={mode} />
						<span class="mode-icon" aria-hidden="true">↗</span>
						<strong>Participant-paced</strong>
						<span>Learners join individually and move through the questions at their own pace.</span
						>
						<small>Use the quest join code; no live room or shared question timer.</small>
					</label>
					<label class="mode-card" class:selected={mode === 'host_paced'}>
						<input type="radio" name="session-mode" value="host_paced" bind:group={mode} />
						<span class="mode-icon" aria-hidden="true">✦</span>
						<strong>Instructor-paced live</strong>
						<span
							>Welcome learners in a shared lobby, then start and advance each round together.</span
						>
						<small>See who has joined and monitor answers as the group plays.</small>
					</label>
				</div>
				{#if error}<p class="error-message" role="alert">{error}</p>{/if}
				<div class="step-actions">
					<button class="button button-primary" type="button" onclick={() => (step = 'settings')}>
						Continue <span aria-hidden="true">→</span>
					</button>
				</div>
			</section>
		{:else}
			<section class="setup-card" aria-labelledby="settings-heading">
				<p class="eyebrow">SESSION SETTINGS</p>
				<h2 id="settings-heading">Ready to bring everyone together?</h2>
				<p class="section-copy">
					{mode === 'host_paced'
						? 'Your live room will open in a waiting lobby. Share the code, link, or QR code, then start when your learners have joined.'
						: 'Learners will enter the published quest from the join page and complete it independently.'}
				</p>
				<div class="settings-list">
					{#if mode === 'host_paced'}
						<div class="setting-row">
							<span class="setting-icon" aria-hidden="true">◉</span>
							<span
								><strong>Guest access</strong><small
									>Learners can join with a name; no account is required.</small
								></span
							>
							<b>On</b>
						</div>
						<div class="setting-row">
							<span class="setting-icon" aria-hidden="true">◷</span>
							<span
								><strong>Question timing</strong><small
									>Uses the time limits already set for this published quest.</small
								></span
							>
							<b
								>{activity.questions.some((question) => question.time_limit_seconds > 0)
									? 'As set'
									: 'Untimed'}</b
							>
						</div>
						<div class="setting-row">
							<span class="setting-icon" aria-hidden="true">↗</span>
							<span
								><strong>Progression</strong><small
									>You decide when everyone moves to the next question.</small
								></span
							>
							<b>Host-led</b>
						</div>
					{:else}
						<div class="setting-row">
							<span class="setting-icon" aria-hidden="true">◉</span>
							<span
								><strong>Guest access</strong><small
									>Learners can enter a display name and play without signing in.</small
								></span
							>
							<b>On</b>
						</div>
						<div class="setting-row">
							<span class="setting-icon" aria-hidden="true">◷</span>
							<span
								><strong>Question timing</strong><small
									>Uses the time limits already set for this published quest.</small
								></span
							>
							<b
								>{activity.questions.some((question) => question.time_limit_seconds > 0)
									? 'As set'
									: 'Untimed'}</b
							>
						</div>
						<div class="setting-row">
							<span class="setting-icon" aria-hidden="true">◎</span>
							<span
								><strong>Progression</strong><small
									>Each learner completes the quest independently.</small
								></span
							>
							<b>Individual</b>
						</div>
					{/if}
				</div>
				<p class="no-cap-note">
					No plan-based participant limit. Technical safeguards keep sessions reliable.
				</p>
				{#if error}<p class="error-message" role="alert">{error}</p>{/if}
				<div class="step-actions">
					<button class="button button-outline" type="button" onclick={() => (step = 'mode')}
						>← Back</button
					>
					<button
						class="button button-primary"
						type="button"
						onclick={startSession}
						disabled={starting || !activity.share_code}
					>
						{starting ? 'Preparing…' : 'Start now'} <span aria-hidden="true">↗</span>
					</button>
				</div>
			</section>
		{/if}
	{/if}
</main>

<style>
	.setup-page {
		min-height: calc(100vh - 5rem);
		padding-block: 1.5rem 5rem;
	}
	.back-link {
		display: inline-block;
		margin-bottom: 1.5rem;
		color: var(--ink-muted);
		font-size: 0.82rem;
		font-weight: 650;
		text-decoration: none;
	}
	.setup-heading {
		display: flex;
		justify-content: space-between;
		align-items: end;
		gap: 1rem;
		margin: 0 auto 1.3rem;
		max-width: 58rem;
	}
	.eyebrow {
		margin: 0 0 0.5rem;
		color: var(--gold-deep);
		font-size: 0.67rem;
		font-weight: 850;
		letter-spacing: 0.15em;
	}
	h1,
	h2,
	p {
		margin-top: 0;
	}
	.setup-heading h1 {
		margin-bottom: 0.35rem;
		color: var(--navy);
		font:
			800 clamp(1.7rem, 4vw, 2.5rem)/1.1 Manrope,
			sans-serif;
		letter-spacing: -0.05em;
	}
	.setup-heading p,
	.section-copy {
		color: var(--ink-muted);
		font-size: 0.88rem;
		line-height: 1.65;
	}
	.step-count {
		color: var(--ink-muted);
		font-size: 0.78rem;
		font-weight: 750;
	}
	.step-count span {
		color: var(--navy);
		font-size: 1.25rem;
	}
	.step-track {
		max-width: 58rem;
		height: 0.3rem;
		margin: 0 auto 1rem;
		overflow: hidden;
		border-radius: 99px;
		background: #e8e4dc;
	}
	.step-track span {
		display: block;
		width: 50%;
		height: 100%;
		background: var(--gold-deep);
		transition: width 180ms ease;
	}
	.step-track span.complete {
		width: 100%;
	}
	.setup-card {
		max-width: 58rem;
		margin: 0 auto;
		padding: clamp(1.2rem, 4vw, 2.2rem);
		border: 1px solid var(--line);
		border-radius: 1.2rem;
		background: white;
		box-shadow: var(--shadow-card);
	}
	.setup-card h2 {
		margin-bottom: 0.4rem;
		color: var(--navy);
		font:
			750 clamp(1.25rem, 3vw, 1.75rem)/1.2 Manrope,
			sans-serif;
	}
	.mode-grid {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 1rem;
		margin-top: 1.5rem;
	}
	.mode-card {
		position: relative;
		display: grid;
		min-height: 14rem;
		align-content: start;
		gap: 0.65rem;
		padding: 1.2rem;
		border: 1px solid var(--line);
		border-radius: 1rem;
		cursor: pointer;
	}
	.mode-card.selected {
		border-color: var(--navy);
		background: #f7f8fb;
		box-shadow: 0 0 0 2px rgb(24 46 95 / 9%);
	}
	.mode-card input {
		position: absolute;
		top: 1rem;
		right: 1rem;
		width: 1.1rem;
		height: 1.1rem;
		accent-color: var(--navy);
	}
	.mode-icon,
	.setting-icon {
		display: grid;
		width: 2.5rem;
		height: 2.5rem;
		place-items: center;
		border-radius: 0.75rem;
		background: #f5f0e5;
		color: var(--gold-deep);
		font-size: 1.2rem;
		font-weight: 800;
	}
	.mode-card strong {
		color: var(--navy);
		font-size: 1rem;
	}
	.mode-card > span:not(.mode-icon) {
		color: var(--ink-muted);
		font-size: 0.82rem;
		line-height: 1.6;
	}
	.mode-card small {
		color: var(--ink-soft);
		font-size: 0.72rem;
		line-height: 1.5;
	}
	.step-actions {
		display: flex;
		justify-content: flex-end;
		gap: 0.7rem;
		margin-top: 1.5rem;
	}
	.settings-list {
		margin-top: 1.2rem;
		border-top: 1px solid var(--line);
	}
	.setting-row {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) auto;
		align-items: center;
		gap: 0.9rem;
		padding: 1rem 0;
		border-bottom: 1px solid var(--line);
	}
	.setting-icon {
		width: 2.2rem;
		height: 2.2rem;
		color: var(--navy);
		background: #f0f2f7;
	}
	.setting-row strong,
	.setting-row small {
		display: block;
	}
	.setting-row strong {
		color: var(--ink);
		font-size: 0.85rem;
	}
	.setting-row small {
		margin-top: 0.2rem;
		color: var(--ink-muted);
		font-size: 0.73rem;
		line-height: 1.5;
	}
	.setting-row b {
		color: var(--navy);
		font-size: 0.75rem;
	}
	.no-cap-note {
		margin: 1rem 0 0;
		color: var(--ink-muted);
		font-size: 0.72rem;
	}
	.error-message {
		margin: 1rem 0 0;
		color: #9d2e22;
		font-size: 0.8rem;
	}
	.loading {
		display: grid;
		gap: 0.8rem;
	}
	.loading-mark,
	.loading-line {
		display: block;
		height: 0.8rem;
		border-radius: 99px;
		background: #f0eee9;
	}
	.loading-mark {
		width: 30%;
		height: 1.5rem;
	}
	.loading-line {
		width: 85%;
	}
	.loading-line.short {
		width: 60%;
	}
	@media (max-width: 600px) {
		.setup-heading {
			align-items: start;
		}
		.mode-grid {
			grid-template-columns: 1fr;
		}
		.mode-card {
			min-height: auto;
		}
		.setting-row {
			grid-template-columns: auto minmax(0, 1fr);
		}
		.setting-row b {
			grid-column: 2;
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.step-track span {
			transition: none;
		}
	}
</style>
