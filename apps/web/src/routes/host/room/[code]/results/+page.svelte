<script lang="ts">
	import { onMount } from 'svelte';
	import { resolve } from '$app/paths';
	import CharacterAvatar from '#lib/features/activities/components/CharacterAvatar.svelte';
	import { fetchGameRoomReport } from '#lib/features/activities/api.js';
	import { buildGameRoomResultsCsv } from '#lib/features/activities/resultsCsv.js';
	import type { GameRoomReport } from '#lib/features/activities/types.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	const roomCode = $derived(data.code.toUpperCase());
	let report = $state<GameRoomReport | null>(null);
	let loading = $state(true);
	let error = $state('');

	onMount(() => {
		let disposed = false;
		void fetchGameRoomReport(roomCode)
			.then((result) => {
				if (!disposed) report = result;
			})
			.catch((cause: unknown) => {
				if (!disposed) {
					error = cause instanceof Error ? cause.message : 'Detailed results could not be loaded.';
				}
			})
			.finally(() => {
				if (!disposed) loading = false;
			});
		return () => {
			disposed = true;
		};
	});

	function formatDuration(milliseconds: number | null) {
		if (milliseconds === null) return 'No response';
		return `${(milliseconds / 1000).toFixed(1)} sec`;
	}

	function downloadCsv() {
		if (!report) return;
		const csv = buildGameRoomResultsCsv(report);
		const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
		const link = document.createElement('a');
		link.href = url;
		link.download = `kquest-${roomCode.toLowerCase()}-results.csv`;
		document.body.append(link);
		link.click();
		link.remove();
		window.setTimeout(() => URL.revokeObjectURL(url), 1000);
	}
</script>

<svelte:head>
	<title>{report ? `Detailed results — ${report.title}` : 'Detailed results'} — KINGDOM Quest</title
	>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="results-page">
	<a class="back-link" href={resolve('/host/room/[code]', { code: roomCode })}>
		<span aria-hidden="true">←</span> Back to live room
	</a>

	{#if loading}
		<section class="state-card" role="status">Preparing your results report…</section>
	{:else if error}
		<section class="state-card error-card" role="alert">
			<p class="eyebrow">RESULTS REPORT</p>
			<h1>We couldn’t open these results.</h1>
			<p>{error}</p>
			<a class="back-link" href={resolve('/host/room/[code]', { code: roomCode })}>Return to room</a
			>
		</section>
	{:else if report}
		<header class="report-header">
			<div>
				<p class="eyebrow">GAME REPORT · {report.room_code}</p>
				<h1>{report.title}</h1>
				<p class="report-subtitle">
					A question-by-question record of every learner’s answers, accuracy, and points.
				</p>
			</div>
			<button class="download-button" type="button" onclick={downloadCsv}>
				<svg viewBox="0 0 20 20" aria-hidden="true" fill="none">
					<path d="M10 2.8v9.1m0 0 3.2-3.2M10 11.9 6.8 8.7M3.6 13.3v3h12.8v-3" />
				</svg>
				Download CSV
			</button>
		</header>

		<section class="summary-grid" aria-label="Game summary">
			<article class="summary-card">
				<span>Learners</span>
				<strong>{report.participant_count}</strong>
				<small>completed players</small>
			</article>
			<article class="summary-card">
				<span>Questions</span>
				<strong>{report.question_count}</strong>
				<small>in this game</small>
			</article>
			<article class="summary-card">
				<span>Average score</span>
				<strong>{report.average_score}<small> / {report.max_score}</small></strong>
				<small>points per learner</small>
			</article>
			<article class="summary-card">
				<span>Overall accuracy</span>
				<strong>{report.accuracy_percent}<small>%</small></strong>
				<small>of all learner answers correct</small>
			</article>
		</section>

		<section class="question-summary" aria-labelledby="question-summary-title">
			<div class="section-heading">
				<div>
					<p class="eyebrow">LEARNING SNAPSHOT</p>
					<h2 id="question-summary-title">How the group did</h2>
				</div>
				<span>Correct answers by question</span>
			</div>
			<div class="question-summary-list">
				{#each report.questions as question (question.id)}
					<article class="question-summary-row">
						<span class="question-number">{question.number}</span>
						<div class="question-summary-copy">
							<strong>{question.prompt}</strong>
							<small>Answer: {question.correct_answer || 'No correct answer listed'}</small>
						</div>
						<div class="accuracy">
							<strong>{question.accuracy_percent}%</strong>
							<span>
								{question.correct_count} correct · {question.missed_count} missed ·
								{question.timed_out_count} timed out
							</span>
						</div>
					</article>
				{/each}
			</div>
		</section>

		<section class="learner-results" aria-labelledby="learner-results-title">
			<div class="section-heading">
				<div>
					<p class="eyebrow">ANSWER REVIEW</p>
					<h2 id="learner-results-title">Every learner, every question</h2>
				</div>
				<span>Answers are grouped by question</span>
			</div>
			{#each report.questions as question (question.id)}
				<article class="question-report">
					<header class="question-report-heading">
						<span class="question-number">{question.number}</span>
						<div>
							<h3>{question.prompt}</h3>
							<p>
								Correct answer: <strong
									>{question.correct_answer || 'No correct answer listed'}</strong
								>
							</p>
						</div>
						<span class="question-score">{question.accuracy_percent}% correct</span>
					</header>
					<div class="answer-list">
						{#each report.participants as participant (participant.learner_name)}
							{@const answer = participant.questions.find(
								(result) => result.question_id === question.id
							)}
							{#if answer}
								<div class="answer-row">
									<CharacterAvatar avatarId={participant.avatar_id} size="small" />
									<div class="learner-cell">
										<strong>#{participant.rank} {participant.learner_name}</strong>
										<small>{participant.score} points total</small>
									</div>
									<div
										class="answer-cell"
										class:answer-correct={answer.is_correct}
										class:answer-incorrect={!answer.is_correct}
									>
										<strong>
											{answer.timed_out ? 'No answer' : answer.selected_answer || 'No answer'}
										</strong>
										<small
											>{answer.is_correct
												? 'Correct'
												: answer.timed_out
													? 'Timed out'
													: 'Incorrect'}</small
										>
									</div>
									<div class="answer-points">
										<strong>{answer.points_awarded} / {answer.points_possible}</strong>
										<small>{formatDuration(answer.response_time_ms)}</small>
									</div>
								</div>
							{/if}
						{/each}
					</div>
				</article>
			{/each}
		</section>
	{/if}
</main>

<style>
	:global(body) {
		background: #f5f3ee;
	}

	.results-page {
		width: min(100% - 2rem, 76rem);
		margin: 0 auto;
		padding: 1.5rem 0 4rem;
	}

	.back-link {
		display: inline-flex;
		align-items: center;
		gap: 0.4rem;
		margin-bottom: 1.5rem;
		color: #626a79;
		font-size: 0.78rem;
		font-weight: 750;
		text-decoration: none;
	}

	.back-link:hover {
		color: #182e5f;
	}

	.report-header {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 1.5rem;
		margin-bottom: 1.4rem;
	}

	.eyebrow {
		margin: 0 0 0.45rem;
		color: #a37636;
		font-size: 0.66rem;
		font-weight: 850;
		letter-spacing: 0.13em;
	}

	h1,
	h2,
	h3,
	p {
		margin-top: 0;
	}

	h1 {
		margin-bottom: 0.4rem;
		color: #182e5f;
		font:
			800 clamp(1.7rem, 4vw, 2.6rem)/1.1 Manrope,
			sans-serif;
		letter-spacing: -0.045em;
	}

	.report-subtitle {
		max-width: 42rem;
		margin-bottom: 0;
		color: #696d76;
		font-size: 0.88rem;
		line-height: 1.55;
	}

	.download-button {
		display: inline-flex;
		min-height: 2.8rem;
		flex: 0 0 auto;
		align-items: center;
		justify-content: center;
		gap: 0.55rem;
		padding: 0.7rem 0.95rem;
		border: 1px solid #182e5f;
		border-radius: 0.7rem;
		background: #182e5f;
		color: white;
		font: inherit;
		font-size: 0.78rem;
		font-weight: 800;
		cursor: pointer;
	}

	.download-button:hover {
		background: #233d76;
	}

	.download-button svg {
		width: 1.1rem;
		height: 1.1rem;
		stroke: currentColor;
		stroke-linecap: round;
		stroke-linejoin: round;
		stroke-width: 1.7;
	}

	.summary-grid {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: 0.8rem;
		margin-bottom: 1.2rem;
	}

	.summary-card,
	.question-summary,
	.question-report,
	.state-card {
		border: 1px solid #e8e3d9;
		border-radius: 1rem;
		background: #fff;
		box-shadow: 0 8px 30px rgb(37 39 46 / 4%);
	}

	.summary-card {
		display: grid;
		min-height: 7.5rem;
		align-content: center;
		gap: 0.35rem;
		padding: 1rem;
	}

	.summary-card > span,
	.summary-card > small {
		color: #777b83;
		font-size: 0.72rem;
		font-weight: 650;
	}

	.summary-card > strong {
		color: #182e5f;
		font-size: 1.65rem;
		font-weight: 850;
		line-height: 1;
	}

	.summary-card > strong small {
		color: #777b83;
		font-size: 0.85rem;
		font-weight: 700;
	}

	.question-summary,
	.learner-results {
		margin-top: 1.1rem;
	}

	.question-summary {
		padding: clamp(1rem, 3vw, 1.4rem);
	}

	.section-heading {
		display: flex;
		align-items: end;
		justify-content: space-between;
		gap: 1rem;
		margin-bottom: 0.9rem;
	}

	.section-heading .eyebrow {
		margin-bottom: 0.25rem;
	}

	.section-heading h2 {
		margin-bottom: 0;
		color: #182e5f;
		font-size: 1.12rem;
	}

	.section-heading > span {
		color: #777b83;
		font-size: 0.68rem;
		text-align: right;
	}

	.question-summary-list {
		display: grid;
	}

	.question-summary-row {
		display: grid;
		grid-template-columns: 2.1rem minmax(0, 1fr) auto;
		align-items: center;
		gap: 0.75rem;
		padding: 0.85rem 0;
		border-top: 1px solid #eeece6;
	}

	.question-number {
		display: grid;
		width: 1.85rem;
		height: 1.85rem;
		flex: 0 0 auto;
		place-items: center;
		border-radius: 50%;
		background: #f2efe8;
		color: #182e5f;
		font-size: 0.72rem;
		font-weight: 850;
	}

	.question-summary-copy,
	.accuracy {
		display: grid;
		gap: 0.25rem;
	}

	.question-summary-copy strong {
		color: #30343b;
		font-size: 0.8rem;
		line-height: 1.4;
	}

	.question-summary-copy small,
	.accuracy span {
		color: #777b83;
		font-size: 0.67rem;
	}

	.accuracy {
		justify-items: end;
		text-align: right;
	}

	.accuracy strong {
		color: #182e5f;
		font-size: 0.9rem;
	}

	.learner-results {
		display: grid;
		gap: 0.9rem;
	}

	.learner-results > .section-heading {
		margin-bottom: 0;
		padding: 0.3rem 0;
	}

	.question-report {
		overflow: hidden;
	}

	.question-report-heading {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 1rem 1.15rem;
		border-bottom: 1px solid #eeece6;
		background: #fffdf9;
	}

	.question-report-heading > div {
		min-width: 0;
		flex: 1;
	}

	.question-report-heading h3 {
		margin-bottom: 0.25rem;
		color: #182e5f;
		font-size: 0.9rem;
		line-height: 1.4;
	}

	.question-report-heading p {
		margin-bottom: 0;
		color: #777b83;
		font-size: 0.68rem;
		line-height: 1.4;
	}

	.question-report-heading p strong {
		color: #30343b;
	}

	.question-score {
		flex: 0 0 auto;
		padding: 0.35rem 0.55rem;
		border-radius: 99px;
		background: #e8f3eb;
		color: #276040;
		font-size: 0.67rem;
		font-weight: 800;
	}

	.answer-row {
		display: grid;
		grid-template-columns: 2rem minmax(8rem, 1fr) minmax(8rem, 1.4fr) auto;
		align-items: center;
		gap: 0.7rem;
		padding: 0.75rem 1.15rem;
		border-bottom: 1px solid #f0eee9;
	}

	.answer-row:last-child {
		border-bottom: 0;
	}

	.learner-cell,
	.answer-cell,
	.answer-points {
		display: grid;
		min-width: 0;
		gap: 0.2rem;
	}

	.learner-cell strong,
	.answer-cell strong,
	.answer-points strong {
		overflow-wrap: anywhere;
		color: #30343b;
		font-size: 0.73rem;
	}

	.learner-cell small,
	.answer-cell small,
	.answer-points small {
		color: #777b83;
		font-size: 0.65rem;
	}

	.answer-correct strong,
	.answer-correct small {
		color: #276040;
	}

	.answer-incorrect strong {
		color: #8b443e;
	}

	.answer-points {
		text-align: right;
		white-space: nowrap;
	}

	.state-card {
		padding: 2rem;
		color: #646a75;
	}

	.error-card h1 {
		font-size: 1.6rem;
	}

	@media (max-width: 760px) {
		.report-header {
			align-items: flex-start;
			flex-direction: column;
		}

		.summary-grid {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
	}

	@media (max-width: 520px) {
		.results-page {
			width: min(100% - 1.2rem, 76rem);
			padding-top: 1rem;
		}

		.question-report-heading {
			align-items: flex-start;
		}

		.question-score {
			font-size: 0.6rem;
		}

		.answer-row {
			grid-template-columns: 2rem minmax(0, 1fr) auto;
			gap: 0.55rem;
			padding-inline: 0.75rem;
		}

		.answer-cell {
			grid-column: 2 / -1;
			grid-row: 2;
			padding-bottom: 0.2rem;
		}

		.answer-points {
			grid-column: 3;
			grid-row: 1;
		}
	}
</style>
