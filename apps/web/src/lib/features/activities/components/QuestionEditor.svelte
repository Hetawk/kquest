<script lang="ts">
	import type { ChoiceOption, QuestionDraft } from '../types';

	let { question, index, onUpdate, onRemove } = $props<{
		question: QuestionDraft;
		index: number;
		onUpdate: (question: QuestionDraft) => void;
		onRemove: () => void;
	}>();

	function updateOption(optionIndex: number, text: string) {
		const options = question.options.map((option: ChoiceOption, currentIndex: number) =>
			currentIndex === optionIndex ? { ...option, text } : option
		);
		onUpdate({ ...question, options });
	}
</script>

<fieldset class="question-editor">
	<legend class="question-legend">
		<span class="question-number">{String(index + 1).padStart(2, '0')}</span>
		<span>Question {index + 1}</span>
		<button class="icon-button remove-button" type="button" onclick={onRemove}> Remove </button>
	</legend>

	<label class="field-label" for="prompt-{index}">Your question</label>
	<textarea
		id="prompt-{index}"
		class="text-input prompt-input"
		rows="2"
		maxlength="500"
		placeholder="What would you like learners to discover?"
		value={question.prompt}
		oninput={(event) => onUpdate({ ...question, prompt: event.currentTarget.value })}
		required></textarea>

	<div class="option-heading">
		<span class="field-label">Answer choices</span>
		<span class="field-hint">Select the correct answer</span>
	</div>

	<div class="option-list">
		{#each question.options as option, optionIndex (option.id)}
			<div class="option-row">
				<label class="correct-choice" aria-label="Mark option {optionIndex + 1} as correct">
					<input
						type="radio"
						name="correct-answer-{index}"
						value={option.id}
						checked={question.correct_option_id === option.id}
						onchange={() => onUpdate({ ...question, correct_option_id: option.id })}
					/>
					<span class="correct-indicator" aria-hidden="true"></span>
				</label>
				<input
					class="text-input option-input"
					type="text"
					maxlength="160"
					placeholder="Choice {optionIndex + 1}"
					value={option.text}
					oninput={(event) => updateOption(optionIndex, event.currentTarget.value)}
					aria-label="Answer choice {optionIndex + 1}"
					required
				/>
				<span class="option-letter" aria-hidden="true">{String.fromCharCode(65 + optionIndex)}</span
				>
			</div>
		{/each}
	</div>

	<div class="question-footer">
		<p class="field-hint">Tap the circle beside the right answer.</p>
		<label class="points-label" for="points-{index}">
			<span>Points</span>
			<input
				id="points-{index}"
				class="points-input"
				type="number"
				min="1"
				max="1000"
				step="25"
				value={question.points}
				onchange={(event) =>
					onUpdate({ ...question, points: Number.parseInt(event.currentTarget.value, 10) || 0 })}
				required
			/>
		</label>
	</div>

	<div class="timing-settings">
		<label class="timer-toggle">
			<input
				type="checkbox"
				checked={question.time_limit_seconds === 0}
				onchange={(event) =>
					onUpdate({
						...question,
						time_limit_seconds: event.currentTarget.checked ? 0 : 30
					})}
			/>
			<span>No time limit</span>
		</label>
		{#if question.time_limit_seconds > 0}
			<label class="points-label" for="time-limit-{index}">
				<span>Time limit (seconds)</span>
				<input
					id="time-limit-{index}"
					class="points-input"
					type="number"
					min="5"
					max="300"
					step="1"
					value={question.time_limit_seconds}
					oninput={(event) =>
						onUpdate({
							...question,
							time_limit_seconds: Number.parseInt(event.currentTarget.value, 10) || 0
						})}
					required
				/>
			</label>
		{/if}
		<p class="field-hint">Choose 5–300 seconds, or allow learners to work at their own pace.</p>
	</div>
</fieldset>

<style>
	.question-editor {
		min-width: 0;
		margin: 0;
		padding: 1.5rem;
		border: 1px solid var(--line);
		border-radius: var(--radius-lg);
		background: white;
		box-shadow: 0 8px 28px rgb(31 28 24 / 4%);
	}

	.question-legend {
		display: flex;
		width: 100%;
		align-items: center;
		gap: 0.75rem;
		margin-bottom: 1.3rem;
		font-size: 1rem;
		font-weight: 700;
	}

	.question-number {
		display: grid;
		width: 2rem;
		height: 2rem;
		place-items: center;
		border-radius: 50%;
		background: var(--navy-soft);
		color: var(--navy);
		font-size: 0.7rem;
		letter-spacing: 0.04em;
	}

	.remove-button {
		margin-left: auto;
		color: var(--ink-soft);
	}

	.field-label {
		display: block;
		margin-bottom: 0.55rem;
		color: var(--ink);
		font-size: 0.8rem;
		font-weight: 700;
	}

	.text-input {
		width: 100%;
		border: 1px solid var(--line);
		border-radius: 0.8rem;
		background: var(--paper);
		color: var(--ink);
		font: inherit;
		transition:
			border-color 160ms ease,
			box-shadow 160ms ease,
			background 160ms ease;
	}

	.text-input:focus {
		border-color: var(--gold-deep);
		background: white;
		box-shadow: 0 0 0 3px rgb(200 160 97 / 17%);
		outline: none;
	}

	.prompt-input {
		min-height: 5rem;
		padding: 0.85rem 1rem;
		resize: vertical;
	}

	.option-heading,
	.question-footer {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
	}

	.timing-settings {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		margin-top: 0.85rem;
	}

	.timer-toggle {
		display: flex;
		align-items: center;
		gap: 0.45rem;
		color: var(--ink-soft);
		font-size: 0.78rem;
		font-weight: 700;
	}

	.timer-toggle input {
		accent-color: var(--navy);
	}

	.option-heading {
		margin-top: 1.4rem;
	}

	.field-hint {
		margin: 0;
		color: var(--ink-muted);
		font-size: 0.76rem;
	}

	.option-list {
		display: grid;
		gap: 0.65rem;
	}

	.option-row {
		display: flex;
		min-width: 0;
		align-items: center;
		gap: 0.65rem;
	}

	.correct-choice {
		display: grid;
		width: 1.55rem;
		height: 1.55rem;
		flex: 0 0 1.55rem;
		place-items: center;
		cursor: pointer;
	}

	.correct-choice input {
		position: absolute;
		width: 1px;
		height: 1px;
		opacity: 0;
	}

	.correct-indicator {
		width: 1.1rem;
		height: 1.1rem;
		border: 1.5px solid #c7c2b8;
		border-radius: 50%;
		background: white;
		box-shadow: inset 0 0 0 3px white;
	}

	.correct-choice input:checked + .correct-indicator {
		border-color: var(--success);
		background: var(--success);
	}

	.correct-choice input:focus-visible + .correct-indicator {
		outline: 3px solid rgb(200 160 97 / 42%);
		outline-offset: 3px;
	}

	.option-input {
		min-width: 0;
		padding: 0.72rem 0.8rem;
		font-size: 0.9rem;
	}

	.option-letter {
		width: 1.3rem;
		flex: 0 0 1.3rem;
		color: var(--ink-muted);
		font-size: 0.74rem;
		font-weight: 700;
		text-align: center;
	}

	.question-footer {
		margin-top: 1.1rem;
		padding-top: 1rem;
		border-top: 1px solid var(--line);
	}

	.points-label {
		display: flex;
		align-items: center;
		gap: 0.5rem;
		color: var(--ink-soft);
		font-size: 0.78rem;
		font-weight: 700;
	}

	.points-input {
		width: 4.8rem;
		padding: 0.5rem;
		border: 1px solid var(--line);
		border-radius: 0.6rem;
		font: inherit;
	}

	@media (max-width: 540px) {
		.question-editor {
			padding: 1rem;
		}

		.option-heading {
			align-items: baseline;
		}

		.question-footer .field-hint {
			max-width: 12rem;
		}

		.timing-settings {
			align-items: flex-start;
			flex-direction: column;
		}
	}
</style>
