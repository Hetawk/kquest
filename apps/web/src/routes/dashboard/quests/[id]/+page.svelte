<script lang="ts">
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import {
		getCreatorActivity,
		getCurrentUser,
		publishActivity,
		reviseActivity
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
	let quickEditingQuestionId = $state<string | null>(null);
	let quickPoints = $state(1);
	let quickSpeedBonusPoints = $state(100);
	let quickTimeLimitSeconds = $state(30);
	const totalLiveTimerSeconds = $derived(
		activity?.questions.reduce((sum, question) => sum + (question.time_limit_seconds || 30), 0) ?? 0
	);

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

	function formatDuration(totalSeconds: number) {
		const minutes = Math.floor(totalSeconds / 60);
		const seconds = totalSeconds % 60;
		if (minutes === 0) return `${seconds} sec`;
		return seconds === 0 ? `${minutes} min` : `${minutes} min ${seconds} sec`;
	}

	function beginQuickEdit(question: CreatorActivityDetail['questions'][number]) {
		quickEditingQuestionId = question.id;
		quickPoints = question.points;
		quickSpeedBonusPoints = question.speed_bonus_points ?? question.points;
		quickTimeLimitSeconds = question.time_limit_seconds || 30;
	}

	async function saveQuestionRevision(questions: CreatorActivityDetail['questions']) {
		if (!activity) throw new Error('This quest is no longer available.');
		const publication = await reviseActivity(activity.id, {
			title: activity.title,
			expected_version: activity.version ?? 1,
			shuffle_questions: activity.shuffle_questions,
			speed_scoring: activity.speed_scoring,
			questions
		});
		const updatedAt = new Date().toISOString();
		activity = {
			...activity,
			title: publication.title,
			version: publication.version,
			share_code: publication.share_code,
			updated_at: updatedAt,
			published_at: updatedAt,
			questions
		};
		return publication;
	}

	async function saveQuickSettings(questionId: string) {
		if (!activity || busy || activity.status !== 'published') return;
		if (
			!Number.isInteger(quickPoints) ||
			quickPoints < 1 ||
			quickPoints > 1000 ||
			!Number.isInteger(quickSpeedBonusPoints) ||
			quickSpeedBonusPoints < 0 ||
			quickSpeedBonusPoints > 100_000 ||
			!Number.isInteger(quickTimeLimitSeconds) ||
			quickTimeLimitSeconds < 5 ||
			quickTimeLimitSeconds > 300
		) {
			error = 'Points must be 1–1,000, speed bonus 0–100,000, and live timer 5–300 seconds.';
			return;
		}

		busy = true;
		error = '';
		notice = '';
		try {
			const questions = activity.questions.map((question) =>
				question.id === questionId
					? {
							...question,
							points: quickPoints,
							speed_bonus_points: quickSpeedBonusPoints,
							time_limit_seconds: quickTimeLimitSeconds
						}
					: question
			);
			const publication = await saveQuestionRevision(questions);
			quickEditingQuestionId = null;
			notice = `Question settings saved as version ${publication.version}. New game code: ${publication.share_code}. Previous versions remain unchanged.`;
		} catch (cause) {
			error =
				cause instanceof Error ? cause.message : 'These question settings could not be saved.';
		} finally {
			busy = false;
		}
	}

	async function setAllQuestionsToOnePoint() {
		if (!activity || busy || activity.status !== 'published') return;
		if (activity.questions.every((question) => question.points === 1)) return;
		busy = true;
		error = '';
		notice = '';
		try {
			const questions = activity.questions.map((question) => ({ ...question, points: 1 }));
			const publication = await saveQuestionRevision(questions);
			quickEditingQuestionId = null;
			notice = `All questions now have 1 base point in version ${publication.version}. Speed-bonus caps remain unchanged; previous versions remain available on their original code.`;
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Question points could not be updated.';
		} finally {
			busy = false;
		}
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
					<span>
						<strong>Up to {formatDuration(totalLiveTimerSeconds)}</strong> live timer allowance
					</span>
					<span><strong>Participant-paced</strong> no question countdown</span>
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
					<!-- eslint-disable svelte/no-navigation-without-resolve -->
					<a
						class="button button-outline"
						href={resolve('/host/activities/[id]', { id: activity.id }) + '?edit=true'}
					>
						Edit quest
					</a>
					<!-- eslint-enable svelte/no-navigation-without-resolve -->
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
						<p class="duration-hint">
							The live timer allowance is a maximum; hosts can advance sooner. Participant-paced
							sessions have no question countdown, and completed sessions record their actual
							duration.
						</p>
					</div>
					<div class="section-heading-actions">
						{#if activity.status === 'published' && activity.questions.some((question) => question.points !== 1)}
							<button
								class="quick-edit-button"
								type="button"
								onclick={setAllQuestionsToOnePoint}
								disabled={busy}
							>
								Set all questions to 1 point
							</button>
						{/if}
						<!-- eslint-disable svelte/no-navigation-without-resolve -->
						<a
							class="text-link"
							href={resolve('/host/activities/[id]', { id: activity.id }) + '?edit=true'}
						>
							Review and edit questions before starting <span aria-hidden="true">↗</span>
						</a>
						<!-- eslint-enable svelte/no-navigation-without-resolve -->
					</div>
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
										<span>{question.time_limit_seconds || 30}s live</span>
										<span>{question.points} pts</span>
										{#if activity.speed_scoring && question.time_limit_seconds > 0}
											<span
												>Up to +{question.speed_bonus_points ?? question.points} speed bonus</span
											>
										{/if}
									</div>
								</div>
								{#if activity.status === 'published'}
									{#if quickEditingQuestionId === question.id}
										<form
											class="quick-settings"
											onsubmit={(event) => {
												event.preventDefault();
												void saveQuickSettings(question.id);
											}}
										>
											<label>
												<span>Points</span>
												<input
													type="number"
													min="1"
													max="1000"
													step="1"
													bind:value={quickPoints}
													disabled={busy}
												/>
											</label>
											<label>
												<span>Max speed bonus</span>
												<input
													type="number"
													min="5"
													max="100000"
													step="1"
													bind:value={quickSpeedBonusPoints}
													disabled={busy}
												/>
											</label>
											<label>
												<span>Time limit</span>
												<input
													type="number"
													min="0"
													max="300"
													step="1"
													bind:value={quickTimeLimitSeconds}
													aria-label="Time limit"
													disabled={busy}
												/>
												<small>5–300 seconds in instructor-paced live play</small>
											</label>
											<div class="quick-settings-actions">
												<button
													class="button button-outline"
													type="button"
													onclick={() => (quickEditingQuestionId = null)}
													disabled={busy}
												>
													Cancel
												</button>
												<button class="button button-primary" type="submit" disabled={busy}>
													{busy ? 'Saving…' : 'Save question settings'}
												</button>
											</div>
										</form>
									{:else}
										<button
											class="quick-edit-button"
											type="button"
											onclick={() => beginQuickEdit(question)}
											disabled={busy}
										>
											Edit points and timing
										</button>
									{/if}
								{/if}
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

	.duration-hint {
		margin: 0.55rem 0 0;
		color: var(--ink-muted);
		font-size: 0.76rem;
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

	.section-heading-actions {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: flex-end;
		gap: 0.8rem;
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

	.quick-edit-button {
		margin-top: 0.8rem;
		padding: 0;
		border: 0;
		background: transparent;
		color: var(--navy);
		font: inherit;
		font-size: 0.76rem;
		font-weight: 750;
		cursor: pointer;
	}

	.quick-edit-button:disabled {
		cursor: wait;
		opacity: 0.55;
	}

	.quick-settings {
		display: flex;
		flex-wrap: wrap;
		align-items: end;
		gap: 0.75rem;
		margin-top: 0.9rem;
		padding: 1rem;
		border: 1px solid #e7e2d8;
		border-radius: 0.8rem;
		background: #faf9f6;
	}

	.quick-settings label {
		display: grid;
		min-width: 9rem;
		gap: 0.35rem;
		color: var(--ink-soft);
		font-size: 0.72rem;
		font-weight: 700;
	}

	.quick-settings input {
		width: 100%;
		min-height: 2.5rem;
		padding: 0.5rem 0.65rem;
		border: 1px solid var(--line);
		border-radius: 0.55rem;
		background: white;
		color: var(--ink);
		font: inherit;
		font-size: 0.84rem;
	}

	.quick-settings-actions {
		display: flex;
		gap: 0.45rem;
		margin-left: auto;
	}

	.quick-settings-actions .button {
		min-height: 2.5rem;
		padding: 0.55rem 0.75rem;
		font-size: 0.74rem;
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

		.section-heading-actions {
			align-items: flex-start;
			flex-direction: column;
		}

		.question-badges {
			justify-content: flex-start;
		}

		.answer-preview {
			grid-template-columns: 1fr;
		}

		.quick-settings-actions {
			width: 100%;
			margin-left: 0;
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
