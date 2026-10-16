<script lang="ts">
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import questionTemplateUrl from '#lib/assets/question-import-template.csv?url';
	import QuestionEditor from '#lib/features/activities/components/QuestionEditor.svelte';
	import { importQuestionFile } from '#lib/features/activities/importQuestions.js';
	import {
		createGameRoom,
		createActivity,
		getCurrentUser,
		publishActivity,
		uploadCoverImage
	} from '#lib/features/activities/api.js';
	import type { PublishedActivity, QuestionDraft } from '#lib/features/activities/types.js';

	const makeQuestion = (): QuestionDraft => {
		const firstOption = crypto.randomUUID();
		return {
			prompt: '',
			options: [
				{ id: firstOption, text: '' },
				{ id: crypto.randomUUID(), text: '' },
				{ id: crypto.randomUUID(), text: '' },
				{ id: crypto.randomUUID(), text: '' }
			],
			correct_option_id: firstOption,
			points: 100,
			time_limit_seconds: 30
		};
	};

	let title = $state('');
	let description = $state('');
	let questions = $state<QuestionDraft[]>([makeQuestion()]);
	let error = $state('');
	let saving = $state(false);
	let published = $state<PublishedActivity | null>(null);
	let copied = $state(false);
	let copiedLink = $state(false);
	let authChecking = $state(true);
	let signedIn = $state(false);
	let coverImage = $state<{ id: string; public_url: string } | null>(null);
	let coverUploading = $state(false);
	let importing = $state(false);
	let shuffleQuestions = $state(false);
	let speedScoring = $state(true);
	let gameMode = $state<'self_paced' | 'host_paced'>('self_paced');
	const maxQuestions = 100;

	onMount(() => {
		void getCurrentUser()
			.then((user) => {
				signedIn = user !== null;
			})
			.catch((cause: unknown) => {
				error = cause instanceof Error ? cause.message : 'Could not verify your sign-in.';
			})
			.finally(() => {
				authChecking = false;
			});
	});

	function updateQuestion(index: number, question: QuestionDraft) {
		questions[index] = question;
	}

	async function handleSubmit(event: SubmitEvent) {
		event.preventDefault();
		if (saving || coverUploading) return;

		error = '';
		saving = true;

		try {
			const activity = await createActivity({
				title,
				description,
				questions,
				shuffle_questions: shuffleQuestions,
				speed_scoring: speedScoring,
				...(coverImage ? { cover_image_asset_id: coverImage.id } : {})
			});
			published = await publishActivity(activity.id);
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'Your quest could not be published.';
		} finally {
			saving = false;
		}
	}

	async function handleQuestionsImported(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		error = '';
		importing = true;
		try {
			const imported = await importQuestionFile(file);
			if (questions.length + imported.length > maxQuestions) {
				throw new Error(`You can have up to ${maxQuestions} questions in a quest.`);
			}
			questions = [...questions, ...imported];
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'The question file could not be imported.';
		} finally {
			importing = false;
			input.value = '';
		}
	}

	async function startHostRoom() {
		if (!published || saving) return;
		saving = true;
		error = '';
		try {
			const room = await createGameRoom(published.activity_id);
			await goto(resolve('/host/room/[code]', { code: room.room_code }));
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'The live room could not be created.';
		} finally {
			saving = false;
		}
	}

	async function handleCoverSelected(event: Event) {
		const input = event.currentTarget as HTMLInputElement;
		const file = input.files?.[0];
		if (!file) return;

		error = '';
		if (!['image/jpeg', 'image/png', 'image/webp'].includes(file.type)) {
			error = 'Choose a PNG, JPEG, or WebP image.';
			input.value = '';
			return;
		}
		if (file.size > 5 * 1024 * 1024) {
			error = 'Cover images must be 5 MB or smaller.';
			input.value = '';
			return;
		}

		coverUploading = true;
		try {
			coverImage = await uploadCoverImage(file);
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'The cover image could not be uploaded.';
		} finally {
			coverUploading = false;
		}
	}

	async function copyCode() {
		if (!published) return;

		try {
			await navigator.clipboard.writeText(published.share_code);
			copied = true;
			window.setTimeout(() => (copied = false), 1800);
		} catch (cause) {
			error =
				cause instanceof Error
					? 'Copying is unavailable here. Select the code to copy it.'
					: 'The game code could not be copied.';
		}
	}

	async function copyJoinLink() {
		if (!published) return;
		try {
			await navigator.clipboard.writeText(`${window.location.origin}/join/${published.share_code}`);
			copiedLink = true;
			window.setTimeout(() => (copiedLink = false), 1800);
		} catch {
			error = 'Copying is unavailable here. Share the game code instead.';
		}
	}
</script>

<svelte:head>
	<title>Create a quest — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell create-page">
	{#if authChecking}
		<section class="published-card" aria-live="polite">
			<p class="eyebrow">Your learning studio</p>
			<h1>Checking your sign-in…</h1>
		</section>
	{:else if !signedIn}
		<section class="published-card" aria-labelledby="signin-title">
			<p class="eyebrow">Your learning studio</p>
			<h1 id="signin-title">Sign in to create a quest.</h1>
			<p class="published-copy">
				Create an account or sign in with email and password, or continue with Google.
			</p>
			<a
				class="button button-primary"
				href={resolve('/auth')}
				onclick={(event) => {
					event.preventDefault();
					window.location.assign(`${resolve('/auth')}?next=%2Fcreate`);
				}}
			>
				Sign in or create an account
			</a>
			{#if error}<p class="error-message" role="alert">{error}</p>{/if}
		</section>
	{:else if published}
		<section class="published-card" aria-labelledby="published-title">
			<div class="published-icon" aria-hidden="true">✦</div>
			<p class="eyebrow">Your quest is out in the world</p>
			<h1 id="published-title">{published.title}</h1>
			<p class="published-copy">
				Share this game code with your learners. Their answers will be checked and scored by the
				server.
			</p>
			<div class="share-code" aria-label="Game code">{published.share_code}</div>
			<div class="published-actions">
				<button class="button button-primary" type="button" onclick={copyCode}>
					{copied ? 'Copied!' : 'Copy game code'}
				</button>
				<button class="button button-outline" type="button" onclick={copyJoinLink}>
					{copiedLink ? 'Join link copied!' : 'Copy direct join link'}
				</button>
				<button
					class="button button-outline"
					type="button"
					onclick={() =>
						goto(
							published ? resolve('/play/[code]', { code: published.share_code }) : resolve('/')
						)}
				>
					Preview your quest <span aria-hidden="true">↗</span>
				</button>
			</div>
			{#if gameMode === 'host_paced'}
				<button
					class="button button-primary"
					type="button"
					onclick={startHostRoom}
					disabled={saving}
				>
					{saving ? 'Opening live room…' : 'Open host-controlled live room'}
					<span aria-hidden="true">↗</span>
				</button>
			{/if}
			{#if error}<p class="error-message" role="alert">{error}</p>{/if}
			<a class="back-link" href={resolve('/')}>Back to your studio</a>
		</section>
	{:else}
		<div class="create-intro">
			<a class="back-link" href={resolve('/')}>← Back to studio</a>
			<p class="eyebrow">The question studio</p>
			<h1 class="page-heading">Make a little<br />room for wonder.</h1>
			<p class="page-intro">
				Start with what you want your learners to discover. We’ll help turn it into a quest worth
				playing.
			</p>
		</div>

		<form class="builder" onsubmit={handleSubmit}>
			<section class="activity-details" aria-labelledby="details-heading">
				<div class="section-heading">
					<span class="step-marker">01</span>
					<div>
						<h2 id="details-heading">Give your quest a name</h2>
						<p>Make it memorable. You can share the story in the description.</p>
					</div>
				</div>

				<label class="field-label" for="activity-title">Quest title</label>
				<input
					id="activity-title"
					class="text-input"
					type="text"
					maxlength="120"
					placeholder="e.g. The Great Solar System Sprint"
					bind:value={title}
					required
				/>

				<label class="field-label description-label" for="activity-description">
					A little context <span>(optional)</span>
				</label>
				<textarea
					id="activity-description"
					class="text-input"
					rows="3"
					maxlength="500"
					placeholder="What will learners explore?"
					bind:value={description}></textarea>

				<label class="field-label description-label" for="cover-image">
					Quest cover <span>(optional)</span>
				</label>
				<p class="field-hint" id="cover-image-hint">
					Add a PNG, JPEG, or WebP image up to 5 MB. Cover images are publicly visible to anyone
					with a published quest.
				</p>
				<input
					id="cover-image"
					class="text-input"
					type="file"
					accept="image/png,image/jpeg,image/webp"
					aria-describedby="cover-image-hint"
					onchange={handleCoverSelected}
					disabled={coverUploading || saving}
				/>
				{#if coverUploading}
					<p class="field-hint" role="status">Uploading your cover image…</p>
				{:else if coverImage}
					<img class="cover-preview" src={coverImage.public_url} alt="Quest cover preview" />
					<button class="back-link" type="button" onclick={() => (coverImage = null)}>
						Remove cover
					</button>
				{/if}
			</section>

			<section class="questions-section" aria-labelledby="questions-heading">
				<div class="section-heading">
					<span class="step-marker">02</span>
					<div>
						<h2 id="questions-heading">Bring the questions</h2>
						<p>Add up to {maxQuestions} questions by hand or import and review a spreadsheet.</p>
					</div>
				</div>

				<div class="import-panel">
					<div>
						<strong>Bring questions from a file</strong>
						<p>
							CSV or Excel (.xlsx), up to 100 questions. Imported questions are added here for
							review before publishing.
						</p>
						<!-- eslint-disable-next-line svelte/no-navigation-without-resolve -->
						<a href={questionTemplateUrl} download>Download the CSV template</a>
					</div>
					<label class="button button-outline import-button" for="question-import">
						{importing ? 'Reading file…' : 'Import CSV / XLSX'}
					</label>
					<input
						id="question-import"
						class="visually-hidden"
						type="file"
						accept=".csv,.xlsx,text/csv,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
						onchange={handleQuestionsImported}
						disabled={importing || saving}
					/>
				</div>

				<div class="question-list">
					{#each questions as question, index (index)}
						<QuestionEditor
							{question}
							{index}
							onUpdate={(updated) => updateQuestion(index, updated)}
							onRemove={() => (questions = questions.filter((_, itemIndex) => itemIndex !== index))}
						/>
					{/each}
				</div>

				<button
					class="add-question"
					type="button"
					disabled={questions.length >= maxQuestions}
					onclick={() => (questions = [...questions, makeQuestion()])}
				>
					<span aria-hidden="true">+</span>
					Add another question
					<span class="question-count">{questions.length} / {maxQuestions}</span>
				</button>
			</section>

			<section class="play-settings" aria-labelledby="play-settings-heading">
				<div class="section-heading">
					<span class="step-marker">03</span>
					<div>
						<h2 id="play-settings-heading">Choose how your group plays</h2>
						<p>Both options share fair, server-verified scoring and rankings.</p>
					</div>
				</div>
				<div class="mode-options">
					<label class="mode-option" class:mode-selected={gameMode === 'self_paced'}>
						<input type="radio" name="game-mode" value="self_paced" bind:group={gameMode} />
						<span
							><strong>Participant-paced</strong><small
								>Everyone plays independently. The shared leaderboard stays provisional as players
								finish.</small
							></span
						>
					</label>
					<label class="mode-option" class:mode-selected={gameMode === 'host_paced'}>
						<input type="radio" name="game-mode" value="host_paced" bind:group={gameMode} />
						<span
							><strong>Host-paced live room</strong><small
								>Open a waiting room, share its link or code, then control when the group starts and
								advances.</small
							></span
						>
					</label>
				</div>
				<label class="setting-toggle">
					<input type="checkbox" bind:checked={shuffleQuestions} />
					<span
						><strong>Shuffle question order</strong><small
							>Question order is randomized once when you publish; answer choices remain attached to
							their question.</small
						></span
					>
				</label>
				<label class="setting-toggle">
					<input type="checkbox" bind:checked={speedScoring} />
					<span
						><strong>Reward quick correct answers</strong><small
							>Timed correct answers earn the base points plus up to a 100% bonus based on
							server-recorded time remaining. Incorrect and timed-out answers earn zero.</small
						></span
					>
				</label>
			</section>

			{#if error}<p class="error-message" role="alert">{error}</p>{/if}

			<div class="publish-row">
				<p><span aria-hidden="true">✦</span> You can play your quest as soon as it’s published.</p>
				<button class="button button-primary publish-button" type="submit" disabled={saving}>
					{saving ? 'Publishing your quest…' : 'Publish quest'}
					{#if !saving}<span aria-hidden="true">↗</span>{/if}
				</button>
			</div>
			<p class="prototype-note">
				Prototype note: your quest is saved to your account. Organization roles and classroom
				sharing are still in development.
			</p>
		</form>
	{/if}
</main>

<style>
	.create-page {
		padding-block: 2.4rem 5rem;
	}

	.create-intro {
		max-width: 44rem;
		margin-bottom: 2rem;
	}

	.back-link {
		display: inline-block;
		margin-bottom: 2rem;
		color: var(--ink-muted);
		font-size: 0.82rem;
		font-weight: 600;
		text-decoration: none;
	}

	.back-link:hover {
		color: var(--navy);
	}

	.create-intro .eyebrow {
		margin-top: 0.25rem;
	}

	.builder {
		display: grid;
		gap: 1.3rem;
	}

	.activity-details,
	.questions-section,
	.play-settings {
		padding: clamp(1.1rem, 3vw, 1.75rem);
		border: 1px solid var(--line);
		border-radius: var(--radius-lg);
		background: white;
		box-shadow: 0 8px 28px rgb(31 28 24 / 3%);
	}

	.import-panel {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		margin-bottom: 1.1rem;
		padding: 1rem;
		border: 1px solid #e6decd;
		border-radius: 0.8rem;
		background: #fcfaf5;
	}

	.import-panel strong,
	.setting-toggle strong,
	.mode-option strong {
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
		color: var(--navy);
		font-size: 0.72rem;
		font-weight: 700;
	}
	.import-button {
		flex: 0 0 auto;
		cursor: pointer;
	}
	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		clip-path: inset(50%);
	}

	.mode-options {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 0.8rem;
	}
	.mode-option,
	.setting-toggle {
		display: flex;
		align-items: flex-start;
		gap: 0.7rem;
		padding: 0.95rem;
		border: 1px solid var(--line);
		border-radius: 0.8rem;
		background: #fff;
		cursor: pointer;
	}
	.mode-selected {
		border-color: var(--gold-deep);
		background: #fffaf0;
		box-shadow: 0 0 0 2px rgb(200 160 97 / 12%);
	}
	.mode-option input,
	.setting-toggle input {
		flex: 0 0 auto;
		margin-top: 0.2rem;
		accent-color: var(--navy);
	}
	.mode-option small,
	.setting-toggle small {
		display: block;
		margin-top: 0.35rem;
		color: var(--ink-muted);
		font-size: 0.73rem;
		line-height: 1.5;
	}
	.setting-toggle {
		margin-top: 0.65rem;
	}

	.section-heading {
		display: flex;
		align-items: flex-start;
		gap: 0.85rem;
		margin-bottom: 1.4rem;
	}

	.step-marker {
		display: grid;
		width: 2rem;
		height: 2rem;
		flex: 0 0 2rem;
		place-items: center;
		border-radius: 50%;
		background: var(--navy);
		color: white;
		font-size: 0.68rem;
		font-weight: 800;
	}

	.section-heading h2 {
		margin: 0;
		font-family: Manrope, sans-serif;
		font-size: 1.1rem;
		font-weight: 800;
		letter-spacing: -0.04em;
	}

	.section-heading p {
		margin: 0.3rem 0 0;
		color: var(--ink-muted);
		font-size: 0.8rem;
		line-height: 1.5;
	}

	.activity-details > .text-input {
		padding: 0.85rem 1rem;
		font-size: 0.9rem;
	}

	.field-hint {
		margin: -0.45rem 0 0.7rem;
		color: var(--ink-muted);
		font-size: 0.76rem;
		line-height: 1.55;
	}

	.cover-preview {
		display: block;
		width: min(100%, 30rem);
		max-height: 16rem;
		margin-top: 0.75rem;
		border-radius: 0.8rem;
		object-fit: cover;
	}

	.activity-details textarea {
		resize: vertical;
	}

	.description-label {
		margin-top: 1.15rem;
	}

	.description-label span {
		color: var(--ink-muted);
		font-weight: 400;
	}

	.question-list {
		display: grid;
		gap: 1rem;
	}

	.add-question {
		display: flex;
		width: 100%;
		align-items: center;
		justify-content: center;
		gap: 0.55rem;
		margin-top: 1rem;
		padding: 0.85rem;
		border: 1px dashed #d4cbb9;
		border-radius: 0.8rem;
		background: #fffdf9;
		color: var(--navy);
		font-size: 0.82rem;
		font-weight: 700;
		cursor: pointer;
		transition:
			border-color 150ms ease,
			background 150ms ease;
	}

	.add-question:hover:not(:disabled) {
		border-color: var(--gold-deep);
		background: #fbf6ea;
	}

	.add-question:disabled {
		color: var(--ink-muted);
		cursor: not-allowed;
	}

	.add-question > span:first-child {
		font-size: 1.2rem;
	}

	.question-count {
		margin-left: 0.35rem;
		color: var(--ink-muted);
		font-size: 0.72rem;
		font-weight: 500;
	}

	.publish-row {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		padding-top: 0.4rem;
	}

	.publish-row p {
		margin: 0;
		color: var(--ink-muted);
		font-size: 0.78rem;
	}

	.publish-row p span {
		margin-right: 0.3rem;
		color: var(--gold-deep);
	}

	.publish-button {
		min-width: 10.8rem;
	}

	.prototype-note {
		max-width: 49rem;
		margin: 0;
		color: var(--ink-muted);
		font-size: 0.72rem;
		line-height: 1.6;
		text-align: right;
	}

	.published-card {
		display: flex;
		max-width: 43rem;
		flex-direction: column;
		align-items: center;
		margin: 3.5rem auto;
		padding: clamp(1.5rem, 7vw, 3rem);
		border: 1px solid var(--line);
		border-radius: 1.5rem;
		background: white;
		box-shadow: var(--shadow-card);
		text-align: center;
		animation: reveal 350ms ease both;
	}

	.published-icon {
		display: grid;
		width: 3.5rem;
		height: 3.5rem;
		place-items: center;
		margin-bottom: 1rem;
		border-radius: 1.1rem;
		background: #fbf0db;
		color: var(--gold-deep);
		font-size: 1.6rem;
	}

	.published-card .eyebrow {
		justify-content: center;
	}

	.published-card .eyebrow::after {
		width: 1.6rem;
		height: 1px;
		background: currentColor;
		content: '';
	}

	.published-card h1 {
		margin: 0.8rem 0 0;
		font-family: Manrope, sans-serif;
		font-size: clamp(1.8rem, 5vw, 2.5rem);
		font-weight: 800;
		letter-spacing: -0.06em;
	}

	.published-copy {
		max-width: 30rem;
		margin: 0.65rem 0 1.4rem;
		color: var(--ink-soft);
		font-size: 0.92rem;
		line-height: 1.7;
	}

	.share-code {
		padding: 1rem 1.5rem;
		border: 1px dashed #d5c29c;
		border-radius: 0.95rem;
		background: #fffaf0;
		color: var(--navy);
		font-family: Manrope, monospace;
		font-size: clamp(1.5rem, 7vw, 2.5rem);
		font-weight: 800;
		letter-spacing: 0.2em;
	}

	.published-actions {
		display: flex;
		flex-wrap: wrap;
		justify-content: center;
		gap: 0.7rem;
		margin-top: 1.4rem;
	}

	.published-card .back-link {
		margin: 1.2rem 0 0;
	}

	@keyframes reveal {
		from {
			transform: translateY(10px);
			opacity: 0;
		}
		to {
			transform: translateY(0);
			opacity: 1;
		}
	}

	@media (max-width: 600px) {
		.import-panel {
			align-items: flex-start;
			flex-direction: column;
		}
		.mode-options {
			grid-template-columns: 1fr;
		}
		.create-page {
			padding-top: 1.4rem;
		}

		.publish-row {
			align-items: stretch;
			flex-direction: column;
		}

		.publish-button {
			width: 100%;
		}

		.prototype-note {
			text-align: left;
		}
	}
</style>
