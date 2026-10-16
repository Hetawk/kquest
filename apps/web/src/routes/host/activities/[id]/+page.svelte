<script lang="ts">
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import questionTemplateUrl from '#lib/assets/question-import-template.csv?url';
	import niaQuestionsUrl from '../../../../../docs/questions.csv?url';
	import QuestionEditor from '#lib/features/activities/components/QuestionEditor.svelte';
	import { importQuestionFile } from '#lib/features/activities/importQuestions.js';
	import {
		createGameRoom,
		getCreatorActivity,
		getCurrentUser,
		reviseActivity
	} from '#lib/features/activities/api.js';
	import type { CreatorActivityDetail } from '#lib/features/activities/api.js';
	import type { QuestionDraft } from '#lib/features/activities/types.js';
	import type { PageProps } from './$types';

	type EditableQuestion = QuestionDraft & { id: string };

	let { data }: PageProps = $props();
	let activity = $state<CreatorActivityDetail | null>(null);
	let activityTitle = $state('');
	let questions = $state<EditableQuestion[]>([]);
	let originalQuestions = $state('');
	let originalTitle = $state('');
	let mode = $state<'host_paced' | 'self_paced'>('host_paced');
	let step = $state<'mode' | 'questions' | 'settings'>('mode');
	let loading = $state(true);
	let starting = $state(false);
	let saving = $state(false);
	let importing = $state(false);
	let bulkTimeLimit = $state('30');
	let error = $state('');
	let notice = $state('');
	let draggedQuestionId = $state('');
	let hasChanges = $derived(
		originalTitle !== activityTitle || originalQuestions !== JSON.stringify(questions)
	);

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
				activityTitle = activity.title;
				originalTitle = activityTitle;
				if (data.editMode) step = 'questions';
				questions = activity.questions.map((question) => ({
					...question,
					time_limit_seconds: question.time_limit_seconds || 30,
					options: question.options.map((option) => ({ ...option })),
					correct_option_ids:
						question.correct_option_ids.length > 0
							? [...question.correct_option_ids]
							: [question.correct_option_id]
				}));
				originalQuestions = JSON.stringify(questions);
				bulkTimeLimit = String(questions[0]?.time_limit_seconds ?? 30);
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

	function moveQuestion(index: number, direction: -1 | 1) {
		const target = index + direction;
		if (target < 0 || target >= questions.length) return;
		const reordered = [...questions];
		[reordered[index], reordered[target]] = [reordered[target], reordered[index]];
		questions = reordered;
	}

	function moveQuestionTo(questionId: string, destination: number) {
		const source = questions.findIndex((question) => question.id === questionId);
		if (source < 0 || destination < 0 || destination >= questions.length || source === destination)
			return;

		const reordered = [...questions];
		const [moved] = reordered.splice(source, 1);
		if (!moved) return;
		reordered.splice(destination, 0, moved);
		questions = reordered;
		notice = `Question moved to position ${destination + 1}.`;
	}

	function startQuestionDrag(event: DragEvent, questionId: string) {
		draggedQuestionId = questionId;
		if (event.dataTransfer) {
			event.dataTransfer.effectAllowed = 'move';
			event.dataTransfer.setData('text/plain', questionId);
		}
	}

	function dragOverQuestion(event: DragEvent, questionId: string, destination: number) {
		event.preventDefault();
		if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
		const draggedId = draggedQuestionId || event.dataTransfer?.getData('text/plain') || '';
		if (draggedId && draggedId !== questionId) moveQuestionTo(draggedId, destination);
	}

	function finishQuestionDrag(event: DragEvent) {
		event.preventDefault();
		draggedQuestionId = '';
	}

	function jumpToQuestion(questionId: string) {
		const container = document.getElementById('session-question-list');
		const target = document.getElementById(`session-question-${questionId}`);
		if (!container || !target) return;

		const top = target.getBoundingClientRect().top - container.getBoundingClientRect().top;
		container.scrollTo({
			top: container.scrollTop + top,
			behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth'
		});
	}

	function formatDuration(seconds: number) {
		const minutes = Math.floor(seconds / 60);
		const remainder = seconds % 60;
		return minutes ? `${minutes}m ${remainder}s` : `${remainder}s`;
	}

	function updateQuestion(index: number, updated: QuestionDraft) {
		questions = questions.map((question, currentIndex) =>
			currentIndex === index ? { ...updated, id: question.id } : question
		);
	}

	function removeQuestion(index: number) {
		questions = questions.filter((_, currentIndex) => currentIndex !== index);
	}

	function addQuestion() {
		const options = Array.from({ length: 4 }, () => ({ id: crypto.randomUUID(), text: '' }));
		questions = [
			...questions,
			{
				id: crypto.randomUUID(),
				question_type: 'single_choice',
				prompt: '',
				options,
				correct_option_id: options[0].id,
				correct_option_ids: [options[0].id],
				points: 1,
				speed_bonus_points: 100,
				time_limit_seconds: 30
			}
		];
	}

	function applyBulkTimeLimit() {
		const rawTimeLimit = String(bulkTimeLimit).trim();
		const timeLimit = Number(rawTimeLimit);
		if (rawTimeLimit === '' || !Number.isInteger(timeLimit) || timeLimit < 5 || timeLimit > 300) {
			error = 'Enter a live question timer from 5 to 300 seconds.';
			return;
		}
		error = '';
		questions = questions.map((question) => ({
			...question,
			time_limit_seconds: timeLimit
		}));
	}

	async function handleQuestionsImported(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		error = '';
		notice = '';
		importing = true;
		try {
			const imported = await importQuestionFile(file);
			if (questions.length + imported.length > 100) {
				throw new Error('A quest can contain up to 100 questions.');
			}
			questions = [
				...questions,
				...imported.map((question) => ({ ...question, id: crypto.randomUUID() }))
			];
			notice = `Imported ${imported.length} questions. Review and edit them before saving.`;
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'The question file could not be imported.';
		} finally {
			importing = false;
			input.value = '';
		}
	}

	async function persistRevision() {
		if (!activity || !hasChanges) return;
		if (questions.length === 0) {
			throw new Error('Add at least one question before saving this quest.');
		}
		if (!activityTitle.trim() || activityTitle.trim().length > 120) {
			throw new Error('Enter a quest title between 1 and 120 characters.');
		}
		const savedAt = new Date().toISOString();
		const updatedQuestions = questions.map((question, index) => ({
			...question,
			position: index + 1
		}));
		const publication = await reviseActivity(activity.id, {
			title: activityTitle.trim(),
			expected_version: activity.version ?? 1,
			shuffle_questions: activity.shuffle_questions,
			speed_scoring: activity.speed_scoring,
			questions: updatedQuestions
		});
		activity = {
			...activity,
			title: publication.title,
			share_code: publication.share_code,
			version: publication.version,
			question_count: updatedQuestions.length,
			published_at: savedAt,
			updated_at: savedAt,
			questions: updatedQuestions
		};
		questions = updatedQuestions;
		activityTitle = publication.title;
		originalTitle = activityTitle;
		originalQuestions = JSON.stringify(questions);
		notice = `Version ${publication.version} saved. Your new join code is ${publication.share_code}; previous versions remain available on their original links.`;
	}

	async function saveRevision() {
		if (!hasChanges || saving || starting) return;
		saving = true;
		error = '';
		notice = '';
		try {
			await persistRevision();
			if (data.editMode) {
				await goto(resolve('/dashboard/quests/[id]', { id: data.activityId }));
			}
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your quest revision could not be saved.';
		} finally {
			saving = false;
		}
	}

	async function startSession() {
		if (!activity?.share_code || starting) return;
		starting = true;
		error = '';
		notice = '';
		try {
			if (hasChanges) await persistRevision();
			if (questions.length === 0) {
				throw new Error('Add at least one question before starting this session.');
			}
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
			? `${data.editMode ? 'Edit' : 'Start'} ${activityTitle || activity.title} — KINGDOM Quest`
			: data.editMode
				? 'Edit quest — KINGDOM Quest'
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
				<p class="eyebrow">{data.editMode ? 'EDIT QUEST' : 'START A SESSION'}</p>
				<h1>{activityTitle || activity.title}</h1>
				<p>
					{data.editMode
						? 'Update questions, answers, and timing for the next version.'
						: 'Choose how your learners will experience this quest.'}
				</p>
			</div>
			{#if !data.editMode}
				<div class="step-count">
					<span>{step === 'mode' ? '01' : step === 'questions' ? '02' : '03'}</span> / 03
				</div>
			{/if}
		</div>
		{#if !data.editMode}
			<div class="step-track" aria-hidden="true">
				<span class:half={step === 'questions'} class:complete={step === 'settings'}></span>
			</div>
		{/if}
		{#if !data.editMode && step === 'mode'}
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
					<button class="button button-primary" type="button" onclick={() => (step = 'questions')}>
						Continue <span aria-hidden="true">→</span>
					</button>
				</div>
			</section>
		{:else if step === 'questions'}
			<section class="setup-card question-review" aria-labelledby="questions-heading">
				<p class="eyebrow">
					{data.editMode ? 'EDIT QUEST' : 'QUEST CONTENT'} · {questions.length} QUESTIONS
				</p>
				<h2 id="questions-heading">
					{data.editMode ? 'Edit your questions' : 'Review and refine your questions'}
				</h2>
				<p class="section-copy">
					{data.editMode
						? 'Reorder, add, remove, and edit questions or import them from a spreadsheet. Your changes will create a new quest version.'
						: 'Review every question before starting. Participant-paced play has no question countdown; instructor-paced play uses the live timers shown here.'}
				</p>
				{#if data.editMode}
					<label class="title-field" for="quest-title">
						<span>Quest title</span>
						<input
							id="quest-title"
							type="text"
							maxlength="120"
							bind:value={activityTitle}
							required
						/>
					</label>
					<div class="import-panel">
						<div>
							<strong>Import questions from a file</strong>
							<p>
								Upload a CSV or Excel workbook (.xlsx), then review the imported questions here.
							</p>
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
							<a href={questionTemplateUrl} download>Download the CSV template</a>
							<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
							<a href={niaQuestionsUrl} download>Download NIA example questions (40)</a>
						</div>
						<label class="button button-outline import-button" for="revision-question-import">
							{importing ? 'Reading file…' : 'Import CSV / XLSX'}
						</label>
						<input
							id="revision-question-import"
							class="visually-hidden"
							type="file"
							accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
							onchange={handleQuestionsImported}
							disabled={importing || saving || starting}
						/>
					</div>
					<div class="bulk-timing">
						<div>
							<strong>Set time for every question</strong>
							<p>
								Apply one live timer to the whole quest. Participant-paced play remains untimed.
							</p>
						</div>
						<label>
							<span class="visually-hidden">Live timer for every question in seconds</span>
							<input
								class="bulk-time-input"
								type="number"
								min="5"
								max="300"
								step="1"
								bind:value={bulkTimeLimit}
								aria-label="Live timer for every question in seconds"
							/>
							<span>seconds</span>
						</label>
						<button class="button button-outline" type="button" onclick={applyBulkTimeLimit}>
							Update all
						</button>
					</div>
				{:else}
					<div class="review-summary">
						<div>
							<strong>Instructor-paced live timers</strong>
							<span>
								{formatDuration(
									questions.reduce((total, question) => total + question.time_limit_seconds, 0)
								)}
								maximum shared countdown time
							</span>
						</div>
						<div>
							<strong>Participant-paced</strong>
							<span>No question countdown; each learner progresses independently.</span>
						</div>
					</div>
					{#if !data.editMode}
						<div class="step-actions review-top-actions">
							<button class="button button-outline" type="button" onclick={() => (step = 'mode')}
								>← Back</button
							>
							<button
								class="button button-primary"
								type="button"
								onclick={() => (step = 'settings')}
							>
								Continue to settings <span aria-hidden="true">→</span>
							</button>
						</div>
					{/if}
				{/if}
				<nav class="question-jump-nav" aria-label="Jump to a question">
					{#each questions as question, index (question.id)}
						<button
							type="button"
							aria-label="Go to question {index + 1}"
							onclick={() => jumpToQuestion(question.id)}
						>
							{index + 1}
						</button>
					{/each}
				</nav>
				<div
					class="question-list"
					class:read-only-list={!data.editMode}
					id="session-question-list"
					aria-label={data.editMode ? 'Editable quest questions' : 'Read-only question review'}
				>
					{#each questions as question, index (question.id)}
						<div id={`session-question-${question.id}`} class="question-list-item">
							{#if data.editMode}
								<QuestionEditor
									{question}
									{index}
									onUpdate={(updated) => updateQuestion(index, updated)}
									onRemove={() => removeQuestion(index)}
									onMoveUp={() => moveQuestion(index, -1)}
									onMoveDown={() => moveQuestion(index, 1)}
									onDragStart={(event) => startQuestionDrag(event, question.id)}
									onDragOver={(event) => dragOverQuestion(event, question.id, index)}
									onDrop={finishQuestionDrag}
									onDragEnd={() => (draggedQuestionId = '')}
									canMoveUp={index > 0}
									canMoveDown={index < questions.length - 1}
									canRemove={true}
								/>
							{:else}
								<article class="question-review-card">
									<div class="review-question-heading">
										<span>QUESTION {String(index + 1).padStart(2, '0')}</span>
										<strong
											>{question.points} pts · {question.time_limit_seconds}s live timer</strong
										>
									</div>
									<h3>{question.prompt}</h3>
									<ul>
										{#each question.options as option, optionIndex (option.id)}
											<li class:correct={question.correct_option_ids.includes(option.id)}>
												<span>{String.fromCharCode(65 + optionIndex)}. {option.text}</span>
												{#if question.correct_option_ids.includes(option.id)}
													<strong>Correct answer</strong>
												{/if}
											</li>
										{/each}
									</ul>
								</article>
							{/if}
						</div>
					{/each}
					{#if questions.length === 0}
						<div class="empty-questions">
							<strong>No questions yet</strong>
							<p>Add a question or import a CSV/XLSX file to continue.</p>
						</div>
					{/if}
				</div>
				{#if data.editMode}
					<button
						class="button button-outline add-question"
						type="button"
						onclick={addQuestion}
						disabled={questions.length >= 100 || importing || saving || starting}
					>
						+ Add a question
					</button>
					<p class="revision-note">
						Saving creates a new quest version. Existing learners and previously shared links keep
						the version they already use.
					</p>
				{/if}
				{#if error}<p class="error-message" role="alert">{error}</p>{/if}
				{#if notice}<p class="success-message" role="status">{notice}</p>{/if}
				<div class="step-actions">
					{#if data.editMode}
						<a
							class="button button-outline"
							href={resolve('/dashboard/quests/[id]', { id: activity.id })}>Cancel</a
						>
					{:else}
						<button class="button button-outline" type="button" onclick={() => (step = 'mode')}
							>← Back</button
						>
					{/if}
					{#if data.editMode}
						<button
							class="button button-outline"
							type="button"
							onclick={saveRevision}
							disabled={!hasChanges || saving || starting || importing}
						>
							{saving ? 'Saving…' : 'Update quest'}
						</button>
					{:else}
						<button class="button button-primary" type="button" onclick={() => (step = 'settings')}>
							Continue <span aria-hidden="true">→</span>
						</button>
					{/if}
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
									>A shared countdown uses each question’s live timer; you control group
									progression.</small
								></span
							>
							<b>Timed</b>
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
									>No question countdown; learners work at their own pace.</small
								></span
							>
							<b>No countdown</b>
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
				{#if notice}<p class="success-message" role="status">{notice}</p>{/if}
				<div class="step-actions">
					<button class="button button-outline" type="button" onclick={() => (step = 'questions')}
						>← Review questions</button
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
		width: 33.333%;
		height: 100%;
		background: var(--gold-deep);
		transition: width 180ms ease;
	}
	.step-track span.half {
		width: 66.666%;
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
	.title-field {
		display: grid;
		max-width: 38rem;
		gap: 0.45rem;
		margin: 1.3rem 0;
		color: var(--ink);
		font-size: 0.82rem;
		font-weight: 700;
	}
	.title-field input {
		width: 100%;
		padding: 0.75rem 0.85rem;
		border: 1px solid var(--line);
		border-radius: 0.7rem;
		background: var(--paper);
		color: var(--ink);
		font: inherit;
	}
	.title-field input:focus {
		border-color: var(--gold-deep);
		background: white;
		box-shadow: 0 0 0 3px rgb(200 160 97 / 17%);
		outline: none;
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
	.import-panel {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		margin: 1.1rem 0;
		padding: 1rem;
		border: 1px solid #e6decd;
		border-radius: 0.8rem;
		background: #fcfaf5;
	}
	.import-panel strong {
		display: block;
		color: var(--navy);
		font-size: 0.82rem;
	}
	.import-panel p {
		margin: 0.25rem 0;
		color: var(--ink-muted);
		font-size: 0.74rem;
		line-height: 1.5;
	}
	.import-panel a {
		display: inline-block;
		margin-right: 0.8rem;
		color: var(--navy);
		font-size: 0.72rem;
		font-weight: 700;
	}
	.import-button {
		flex: 0 0 auto;
		cursor: pointer;
	}
	.bulk-timing {
		display: flex;
		align-items: center;
		gap: 0.8rem;
		margin: 1.4rem 0;
		padding: 1rem;
		border: 1px solid var(--line);
		border-radius: 0.9rem;
		background: #fbfaf8;
	}
	.bulk-timing > div {
		flex: 1;
	}
	.bulk-timing strong {
		color: var(--navy);
		font-size: 0.85rem;
	}
	.bulk-timing p {
		margin: 0.25rem 0 0;
		color: var(--ink-muted);
		font-size: 0.75rem;
		line-height: 1.5;
	}
	.bulk-timing label {
		display: flex;
		align-items: center;
		gap: 0.4rem;
		color: var(--ink-muted);
		font-size: 0.75rem;
	}
	.bulk-time-input {
		width: 5rem;
		min-height: 2.6rem;
		padding: 0.4rem;
		border: 1px solid var(--line);
		border-radius: 0.55rem;
		color: var(--ink);
		font: inherit;
	}
	.question-list {
		display: grid;
		max-height: min(62vh, 50rem);
		overflow-y: auto;
		gap: 1rem;
		overscroll-behavior: contain;
		padding: 0.25rem 0.25rem 0.25rem 0;
		scroll-behavior: smooth;
	}
	.question-list.read-only-list {
		gap: 0.75rem;
	}
	.question-list-item {
		scroll-margin-block: 0.5rem;
	}
	.question-jump-nav {
		position: sticky;
		z-index: 2;
		top: 0;
		display: flex;
		flex-wrap: wrap;
		gap: 0.35rem;
		max-height: 5.8rem;
		overflow: auto;
		margin: 1rem 0 0.7rem;
		padding: 0.5rem;
		border: 1px solid var(--line);
		border-radius: 0.7rem;
		background: rgb(255 255 255 / 96%);
		box-shadow: 0 4px 12px rgb(31 28 24 / 5%);
	}
	.question-jump-nav button {
		min-width: 2rem;
		min-height: 2rem;
		padding: 0.25rem;
		border: 1px solid var(--line);
		border-radius: 0.45rem;
		background: white;
		color: var(--navy);
		font: inherit;
		font-size: 0.72rem;
		font-weight: 750;
		cursor: pointer;
	}
	.question-jump-nav button:hover,
	.question-jump-nav button:focus-visible {
		border-color: var(--gold-deep);
		background: #fffaf0;
	}
	.review-summary {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 0.75rem;
		margin: 1rem 0;
	}
	.review-summary > div {
		display: grid;
		gap: 0.3rem;
		padding: 0.9rem;
		border: 1px solid var(--line);
		border-radius: 0.75rem;
		background: #fbfaf8;
	}
	.review-summary strong,
	.review-question-heading strong {
		color: var(--navy);
		font-size: 0.78rem;
	}
	.review-summary span {
		color: var(--ink-muted);
		font-size: 0.72rem;
		line-height: 1.5;
	}
	.review-top-actions {
		justify-content: flex-end;
		margin-block: 1rem;
	}
	.question-review-card {
		padding: clamp(1rem, 2.5vw, 1.4rem);
		border: 1px solid var(--line);
		border-radius: 0.9rem;
		background: #fff;
	}
	.review-question-heading {
		display: flex;
		justify-content: space-between;
		gap: 0.75rem;
		color: var(--ink-muted);
		font-size: 0.66rem;
		font-weight: 800;
	}
	.review-question-heading > span {
		letter-spacing: 0.1em;
	}
	.question-review-card h3 {
		margin: 0.7rem 0;
		color: var(--navy);
		font-size: 1rem;
		line-height: 1.4;
	}
	.question-review-card ul {
		display: grid;
		gap: 0.35rem;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.question-review-card li {
		display: flex;
		justify-content: space-between;
		gap: 0.75rem;
		padding: 0.55rem 0.65rem;
		border: 1px solid #ece9e2;
		border-radius: 0.5rem;
		color: var(--ink);
		font-size: 0.77rem;
	}
	.question-review-card li.correct {
		border-color: #b9d8c5;
		background: #f3faf5;
	}
	.question-review-card li strong {
		flex: 0 0 auto;
		color: #226644;
		font-size: 0.67rem;
	}
	.review-top-actions .button {
		min-width: 10rem;
	}
	.empty-questions {
		padding: 1.2rem;
		border: 1px dashed var(--line);
		border-radius: 0.8rem;
		color: var(--navy);
	}
	.empty-questions p {
		margin: 0.3rem 0 0;
		color: var(--ink-muted);
		font-size: 0.8rem;
	}
	.add-question {
		width: 100%;
		margin-top: 1rem;
	}
	.revision-note {
		margin: 1rem 0 0;
		padding: 0.8rem 1rem;
		border-radius: 0.65rem;
		background: #f5f0e5;
		color: var(--ink-muted);
		font-size: 0.76rem;
		line-height: 1.55;
	}
	.success-message {
		margin: 1rem 0 0;
		color: #226644;
		font-size: 0.8rem;
		line-height: 1.5;
	}
	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		padding: 0;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		border: 0;
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
		.bulk-timing {
			align-items: stretch;
			flex-direction: column;
		}
		.import-panel {
			align-items: flex-start;
			flex-direction: column;
		}
		.mode-card {
			min-height: auto;
		}
		.review-summary {
			grid-template-columns: 1fr;
		}
		.review-top-actions .button {
			min-width: 0;
		}
		.review-question-heading {
			align-items: flex-start;
			flex-direction: column;
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
