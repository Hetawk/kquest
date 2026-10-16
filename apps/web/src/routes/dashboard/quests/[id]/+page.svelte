<script lang="ts">
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import {
		getCreatorActivity,
		getCurrentUser,
		publishActivity
	} from '#lib/features/activities/api.js';
	import type { CreatorActivityDetail } from '#lib/features/activities/api.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	let activity = $state<CreatorActivityDetail | null>(null);
	let tab = $state<'questions' | 'overview'>('questions');
	let loading = $state(true);
	let busy = $state(false);
	let error = $state('');
	let notice = $state('');

	onMount(() => {
		void loadActivity();
	});

	async function loadActivity() {
		error = '';
		try {
			const user = await getCurrentUser();
			if (!user) {
				window.location.replace(
					`${resolve('/auth')}?next=${encodeURIComponent(window.location.pathname)}`
				);
				return;
			}
			activity = await getCreatorActivity(data.activityId);
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'This quest could not be opened.';
		} finally {
			loading = false;
		}
	}

	async function copyText(value: string, success: string) {
		error = '';
		notice = '';
		try {
			await navigator.clipboard.writeText(value);
			notice = success;
		} catch {
			error = 'Copying is unavailable here. Select the text and copy it instead.';
		}
	}

	async function publishDraft() {
		if (!activity || busy) return;
		busy = true;
		error = '';
		try {
			await publishActivity(activity.id);
			await loadActivity();
			notice = 'Your quest is published and ready to share.';
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'This quest could not be published.';
		} finally {
			busy = false;
		}
	}

	async function openLiveRoom() {
		if (!activity || busy || !activity.share_code) return;
		await goto(resolve('/host/activities/[id]', { id: activity.id }));
	}

	async function copyAndEdit() {
		if (!activity) return;

		const target = new URL(resolve('/create'), window.location.origin);
		target.searchParams.set('copy', activity.id);
		// resolve() handles route parameters, so add the encoded search parameter afterward.
		// eslint-disable-next-line svelte/no-navigation-without-resolve
		await goto(target);
	}

	function isCorrectOption(question: CreatorActivityDetail['questions'][number], optionId: string) {
		return question.question_type === 'multiple_select'
			? question.correct_option_ids.includes(optionId)
			: question.correct_option_id === optionId;
	}

	function formatDate(value: string | null) {
		return value
			? new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value))
			: 'Not published yet';
	}
</script>

<svelte:head>
	<title>{activity ? `${activity.title} — Your studio` : 'Quest details — KINGDOM Quest'}</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell quest-detail-page">
	<a class="back-link" href={resolve('/dashboard')}>← Back to your studio</a>

	{#if loading}
		<section class="detail-loading" role="status" aria-label="Loading quest details">
			<div class="loading-mark" aria-hidden="true"></div>
			<div class="loading-copy">
				<span></span><span></span><span></span>
			</div>
		</section>
	{:else if !activity}
		<section class="detail-error">
			<p class="eyebrow">Your learning studio</p>
			<h1>We couldn’t open this quest.</h1>
			<p>{error}</p>
			<a class="button button-primary" href={resolve('/dashboard')}>Return to your quests</a>
		</section>
	{:else}
		<section class="quest-overview" aria-labelledby="quest-title">
			<div class="quest-overview-main">
				<p class="eyebrow">Quest workspace</p>
				<div class="title-line">
					<h1 id="quest-title">{activity.title}</h1>
					<span class:published={activity.status === 'published'} class="status-pill">
						{activity.status}
					</span>
				</div>
				<p class="quest-description">
					{activity.description || 'A learning adventure ready to take shape.'}
				</p>
				<div class="quest-stats">
					<span><strong>{activity.question_count}</strong> questions</span>
					<span><strong>{activity.total_plays}</strong> completed plays</span>
					<span>Published {formatDate(activity.published_at)}</span>
				</div>
			</div>
			<div class="overview-actions" aria-label="Quest actions">
				{#if activity.share_code}
					<a
						class="button button-outline"
						href={resolve('/play/[code]', { code: activity.share_code })}
					>
						Preview
					</a>
					<button
						class="button button-outline"
						type="button"
						onclick={() => {
							if (activity?.share_code) {
								void copyText(activity.share_code, `Game code ${activity.share_code} copied.`);
							}
						}}
					>
						Copy code
					</button>
					<button
						class="button button-primary"
						type="button"
						onclick={openLiveRoom}
						disabled={busy}
					>
						{busy ? 'Opening room…' : 'Start live session'}
					</button>
				{:else}
					<button
						class="button button-primary"
						type="button"
						onclick={publishDraft}
						disabled={busy}
					>
						{busy ? 'Publishing…' : 'Publish quest'}
					</button>
				{/if}
				<button class="button button-outline" type="button" onclick={copyAndEdit}>
					Copy and edit
				</button>
			</div>
		</section>

		{#if error}<p class="detail-alert" role="alert">{error}</p>{/if}
		{#if notice}<p class="detail-notice" role="status">{notice}</p>{/if}

		<div class="workspace-tabs" role="tablist" aria-label="Quest workspace sections">
			<button
				id="questions-tab"
				type="button"
				role="tab"
				aria-selected={tab === 'questions'}
				aria-controls="questions-panel"
				class:active={tab === 'questions'}
				onclick={() => (tab = 'questions')}
			>
				Questions <span>{activity.questions.length}</span>
			</button>
			<button
				id="overview-tab"
				type="button"
				role="tab"
				aria-selected={tab === 'overview'}
				aria-controls="overview-panel"
				class:active={tab === 'overview'}
				onclick={() => (tab = 'overview')}
			>
				Overview
			</button>
		</div>

		{#if tab === 'questions'}
			<div id="questions-panel" role="tabpanel" aria-labelledby="questions-tab">
				<div class="section-heading">
					<div>
						<p class="eyebrow">Question library</p>
						<h2>Inside this quest</h2>
					</div>
					<button class="text-link" type="button" onclick={copyAndEdit}>
						Edit questions in a copy <span aria-hidden="true">↗</span>
					</button>
				</div>
				{#if activity.questions.length}
					<div class="question-library">
						{#each activity.questions as question (question.id)}
							<article class="question-detail-card" id={`question-${question.id}`}>
								<div class="question-card-heading">
									<div>
										<span class="question-index"
											>QUESTION {String(question.position).padStart(2, '0')}</span
										>
										<h3>{question.prompt}</h3>
									</div>
									<div class="question-badges">
										<span
											>{question.question_type === 'multiple_select'
												? 'Multiple select'
												: 'Single choice'}</span
										>
										<span
											>{question.time_limit_seconds === 0
												? 'Untimed'
												: `${question.time_limit_seconds}s`}</span
										>
										<span>{question.points} pts</span>
									</div>
								</div>
								<ol
									class="answer-preview"
									aria-label={`Answer choices for question ${question.position}`}
								>
									{#each question.options as option, index (option.id)}
										<li class:correct={isCorrectOption(question, option.id)}>
											<span class="answer-letter">{String.fromCharCode(65 + index)}</span>
											<span>{option.text}</span>
											{#if isCorrectOption(question, option.id)}
												<strong class="correct-label">Correct answer</strong>
											{/if}
										</li>
									{/each}
								</ol>
							</article>
						{/each}
					</div>
				{:else}
					<div class="empty-questions">
						<h3>No questions have been added yet.</h3>
						<p>Create a copy to add the first question and publish a new version.</p>
					</div>
				{/if}
			</div>
		{:else}
			<div
				id="overview-panel"
				class="overview-panel"
				role="tabpanel"
				aria-labelledby="overview-tab"
			>
				<div class="overview-card">
					<p class="eyebrow">At a glance</p>
					<h2>How this quest is set up</h2>
					<dl>
						<div>
							<dt>Question order</dt>
							<dd>{activity.shuffle_questions ? 'Shuffled for each learner' : 'Educator order'}</dd>
						</div>
						<div>
							<dt>Scoring</dt>
							<dd>
								{activity.speed_scoring
									? 'Correctness with optional speed bonus'
									: 'Correctness only'}
							</dd>
						</div>
						<div>
							<dt>Publication</dt>
							<dd>{activity.version ? `Version ${activity.version}` : 'Draft — not published'}</dd>
						</div>
						<div>
							<dt>Last updated</dt>
							<dd>{formatDate(activity.updated_at)}</dd>
						</div>
					</dl>
				</div>
			</div>
		{/if}
	{/if}
</main>

<style>
	.quest-detail-page {
		min-height: calc(100vh - 5rem);
		padding-block: 2rem 5rem;
	}

	.back-link {
		display: inline-block;
		margin-bottom: 1rem;
		color: var(--ink-muted);
		font-size: 0.82rem;
		font-weight: 650;
		text-decoration: none;
	}

	.quest-overview,
	.detail-error,
	.detail-loading,
	.overview-card {
		border: 1px solid var(--line);
		border-radius: 1.2rem;
		background: white;
		box-shadow: var(--shadow-card);
	}

	.quest-overview {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 2rem;
		padding: clamp(1.25rem, 4vw, 2.5rem);
	}

	.quest-overview-main {
		min-width: 0;
	}

	.title-line,
	.quest-stats,
	.question-card-heading,
	.question-badges,
	.answer-preview li {
		display: flex;
		align-items: center;
	}

	.title-line {
		flex-wrap: wrap;
		gap: 0.75rem;
	}

	h1,
	h2,
	h3,
	p {
		margin-top: 0;
	}

	.title-line h1 {
		margin-bottom: 0.4rem;
		color: var(--navy);
		font-family: Manrope, sans-serif;
		font-size: clamp(1.7rem, 4vw, 2.7rem);
		letter-spacing: -0.055em;
	}

	.status-pill,
	.question-badges span {
		padding: 0.35rem 0.6rem;
		border-radius: 999px;
		background: #f0eee9;
		color: var(--ink-soft);
		font-size: 0.7rem;
		font-weight: 700;
		text-transform: capitalize;
	}

	.status-pill.published {
		background: #e7f4ed;
		color: #226644;
	}

	.quest-description {
		max-width: 50rem;
		margin: 0.8rem 0 1.1rem;
		color: var(--ink-muted);
		line-height: 1.6;
	}

	.quest-stats {
		flex-wrap: wrap;
		gap: 0.55rem 1.25rem;
		color: var(--ink-muted);
		font-size: 0.78rem;
	}

	.quest-stats strong {
		color: var(--navy);
	}

	.overview-actions {
		display: flex;
		max-width: 21rem;
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: 0.5rem;
	}

	.overview-actions .button {
		min-height: 2.6rem;
		padding: 0.65rem 0.8rem;
		font-size: 0.76rem;
	}

	.detail-alert,
	.detail-notice {
		margin: 1rem 0;
		padding: 0.85rem 1rem;
		border-radius: 0.7rem;
		font-size: 0.84rem;
	}

	.detail-alert {
		background: #fff0ef;
		color: #8e0e00;
	}

	.detail-notice {
		background: #eaf4ee;
		color: #226644;
	}

	.workspace-tabs {
		display: flex;
		gap: 0.4rem;
		margin-top: 1.3rem;
		border-bottom: 1px solid var(--line);
	}

	.workspace-tabs button {
		display: flex;
		align-items: center;
		gap: 0.45rem;
		padding: 0.85rem 1rem;
		border: 0;
		border-bottom: 3px solid transparent;
		background: transparent;
		color: var(--ink-muted);
		font: inherit;
		font-size: 0.86rem;
		font-weight: 700;
		cursor: pointer;
	}

	.workspace-tabs button.active {
		border-bottom-color: var(--gold-deep);
		color: var(--navy);
	}

	.workspace-tabs button span {
		display: grid;
		width: 1.35rem;
		height: 1.35rem;
		place-items: center;
		border-radius: 50%;
		background: var(--navy-soft);
		font-size: 0.68rem;
	}

	.section-heading {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 1rem;
		margin: 1.6rem 0 1rem;
	}

	.section-heading h2,
	.overview-card h2 {
		margin-bottom: 0;
		color: var(--navy);
		font-family: Manrope, sans-serif;
		font-size: 1.3rem;
		letter-spacing: -0.035em;
	}

	.section-heading .eyebrow,
	.overview-card .eyebrow {
		margin-bottom: 0.3rem;
	}

	.text-link {
		padding: 0;
		border: 0;
		background: transparent;
		color: var(--navy);
		font-size: 0.8rem;
		font-weight: 700;
		text-decoration: none;
		cursor: pointer;
	}

	.question-library {
		display: grid;
		gap: 0.85rem;
	}

	.question-detail-card {
		padding: 1.2rem clamp(1rem, 3vw, 1.7rem);
		border: 1px solid var(--line);
		border-radius: 1rem;
		background: white;
	}

	.question-card-heading {
		align-items: flex-start;
		justify-content: space-between;
		gap: 1rem;
	}

	.question-index {
		color: var(--gold-deep);
		font-size: 0.66rem;
		font-weight: 800;
		letter-spacing: 0.1em;
	}

	.question-card-heading h3 {
		margin: 0.35rem 0 0;
		color: var(--ink);
		font-size: 1rem;
		line-height: 1.5;
	}

	.question-badges {
		flex-wrap: wrap;
		justify-content: flex-end;
		gap: 0.35rem;
	}

	.question-badges span {
		white-space: nowrap;
		text-transform: none;
	}

	.answer-preview {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 0.45rem 1rem;
		margin: 1rem 0 0;
		padding: 0;
		list-style: none;
	}

	.answer-preview li {
		min-width: 0;
		gap: 0.65rem;
		padding: 0.65rem 0.75rem;
		border: 1px solid #f0eee9;
		border-radius: 0.65rem;
		color: var(--ink-soft);
		font-size: 0.8rem;
	}

	.answer-preview li.correct {
		border-color: #c5dfcf;
		background: #f1f8f3;
		color: #235b3a;
	}

	.answer-letter {
		display: grid;
		width: 1.55rem;
		height: 1.55rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f1efe9;
		font-size: 0.68rem;
		font-weight: 800;
	}

	.correct-label {
		margin-left: auto;
		color: #226644;
		font-size: 0.65rem;
		white-space: nowrap;
	}

	.overview-panel {
		padding-top: 1.25rem;
	}

	.overview-card {
		max-width: 54rem;
		padding: clamp(1.2rem, 3vw, 2rem);
	}

	.overview-card h2 {
		margin-bottom: 1.2rem;
	}

	dl {
		display: grid;
		gap: 0;
		margin: 0;
	}

	dl div {
		display: flex;
		justify-content: space-between;
		gap: 1rem;
		padding: 0.9rem 0;
		border-top: 1px solid var(--line);
		font-size: 0.84rem;
	}

	dt {
		color: var(--ink-muted);
	}

	dd {
		margin: 0;
		color: var(--ink);
		font-weight: 650;
		text-align: right;
	}

	.detail-error,
	.detail-loading {
		padding: 2rem;
	}

	.detail-error h1 {
		color: var(--navy);
	}

	.detail-loading {
		display: flex;
		min-height: 18rem;
		align-items: center;
		justify-content: center;
		gap: 1rem;
	}

	.loading-mark {
		width: 2.5rem;
		height: 2.5rem;
		border: 3px solid #eee7d8;
		border-top-color: var(--gold-deep);
		border-radius: 50%;
		animation: spin 900ms linear infinite;
	}

	.loading-copy {
		display: grid;
		width: min(45%, 20rem);
		gap: 0.55rem;
	}

	.loading-copy span {
		height: 0.7rem;
		border-radius: 999px;
		background: linear-gradient(90deg, #f1eee8 20%, #faf8f4 45%, #f1eee8 70%);
		background-size: 220% 100%;
		animation: shimmer 1.4s ease-in-out infinite;
	}

	.loading-copy span:nth-child(2) {
		width: 78%;
	}

	.loading-copy span:nth-child(3) {
		width: 54%;
	}

	.empty-questions {
		padding: 2rem;
		border: 1px dashed var(--line);
		border-radius: 1rem;
		color: var(--ink-muted);
	}

	.empty-questions h3 {
		color: var(--navy);
	}

	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}

	@keyframes shimmer {
		to {
			background-position: -220% 0;
		}
	}

	@media (max-width: 800px) {
		.quest-overview {
			flex-direction: column;
		}

		.overview-actions {
			max-width: none;
			justify-content: flex-start;
		}
	}

	@media (max-width: 580px) {
		.section-heading,
		.question-card-heading {
			align-items: flex-start;
			flex-direction: column;
		}

		.question-badges {
			justify-content: flex-start;
		}

		.answer-preview {
			grid-template-columns: 1fr;
		}

		.correct-label {
			font-size: 0.58rem;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.loading-mark,
		.loading-copy span {
			animation: none;
		}
	}
</style>
