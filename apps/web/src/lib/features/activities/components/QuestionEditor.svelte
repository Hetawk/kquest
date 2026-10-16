<script lang="ts">
	import type { ChoiceOption, QuestionDraft } from '../types';

	let {
		question,
		index,
		onUpdate,
		onRemove,
		onMoveUp,
		onMoveDown,
		canMoveUp,
		canMoveDown,
		canRemove
	} = $props<{
		question: QuestionDraft;
		index: number;
		onUpdate: (question: QuestionDraft) => void;
		onRemove: () => void;
		onMoveUp: () => void;
		onMoveDown: () => void;
		canMoveUp: boolean;
		canMoveDown: boolean;
		canRemove: boolean;
	}>();

	function changeQuestionType(questionType: QuestionDraft['question_type']) {
		const correctOptionIds = question.correct_option_ids.length
			? question.correct_option_ids
			: [question.correct_option_id];
		onUpdate({
			...question,
			question_type: questionType,
			correct_option_id: correctOptionIds[0] ?? question.options[0].id,
			correct_option_ids: correctOptionIds
		});
	}

	function toggleCorrectOption(optionId: string, checked: boolean) {
		const correctOptionIds = checked
			? [...question.correct_option_ids, optionId]
			: question.correct_option_ids.filter((id: string) => id !== optionId);
		onUpdate({
			...question,
			correct_option_id: correctOptionIds[0] ?? question.correct_option_id,
			correct_option_ids: correctOptionIds
		});
	}

	function updateOption(optionIndex: number, text: string) {
		const options = question.options.map((option: ChoiceOption, currentIndex: number) =>
			currentIndex === optionIndex ? { ...option, text } : option
		);
		onUpdate({ ...question, options });
	}

	function addOption() {
		if (question.options.length >= 6) return;
		onUpdate({
			...question,
			options: [...question.options, { id: crypto.randomUUID(), text: '' }]
		});
	}

	function removeOption(optionId: string) {
		if (question.options.length <= 2) return;
		const options = question.options.filter((option: ChoiceOption) => option.id !== optionId);
		const correctOptionIds = question.correct_option_ids.filter((id: string) => id !== optionId);
		const remainingCorrectOptionIds =
			correctOptionIds.length > 0 ? correctOptionIds : [options[0].id];
		onUpdate({
			...question,
			options,
			correct_option_id:
				question.correct_option_id === optionId ? options[0].id : question.correct_option_id,
			correct_option_ids: remainingCorrectOptionIds
		});
	}
</script>

<fieldset class="question-editor">
	<legend class="question-legend">
		<span class="question-number">{String(index + 1).padStart(2, '0')}</span>
		<span>Question {index + 1}</span>
		<button
			class="icon-button order-button"
			type="button"
			aria-label="Move question {index + 1} up"
			disabled={!canMoveUp}
			onclick={onMoveUp}>↑</button
		>
		<button
			class="icon-button order-button"
			type="button"
			aria-label="Move question {index + 1} down"
			disabled={!canMoveDown}
			onclick={onMoveDown}>↓</button
		>
		<button
			class="icon-button remove-button"
			type="button"
			aria-label="Delete question {index + 1}"
			disabled={!canRemove}
			onclick={onRemove}
		>
			Delete
		</button>
	</legend>

	<label class="field-label question-type-label">
		Question type
		<select
			class="text-input question-type-select"
			value={question.question_type}
			onchange={(event) =>
				changeQuestionType(event.currentTarget.value as QuestionDraft['question_type'])}
		>
			<option value="single_choice">Single choice</option>
			<option value="multiple_select">Multiple select</option>
		</select>
	</label>

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
		<span class="field-hint">
			{question.question_type === 'multiple_select'
				? 'Select all correct answers'
				: 'Select the correct answer'}
		</span>
	</div>

	<div class="option-list">
		{#each question.options as option, optionIndex (option.id)}
			<div class="option-row">
				<label
					class="correct-choice"
					class:multiple-select={question.question_type === 'multiple_select'}
					aria-label="Mark option {optionIndex + 1} as correct"
				>
					{#if question.question_type === 'multiple_select'}
						<input
							type="checkbox"
							checked={question.correct_option_ids.includes(option.id)}
							onchange={(event) => toggleCorrectOption(option.id, event.currentTarget.checked)}
						/>
					{:else}
						<input
							type="radio"
							name="correct-answer-{index}"
							value={option.id}
							checked={question.correct_option_id === option.id}
							onchange={() =>
								onUpdate({
									...question,
									correct_option_id: option.id,
									correct_option_ids: [option.id]
								})}
						/>
					{/if}
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
				<button
					class="option-remove"
					type="button"
					aria-label="Remove answer choice {optionIndex + 1}"
					disabled={question.options.length <= 2}
					onclick={() => removeOption(option.id)}
				>
					×
				</button>
			</div>
		{/each}
	</div>
	<button
		class="button button-outline add-option"
		type="button"
		onclick={addOption}
		disabled={question.options.length >= 6}
	>
		+ Add answer choice
	</button>

	<div class="question-footer">
		<p class="field-hint">
			{question.question_type === 'multiple_select'
				? 'Scoring requires the exact set of correct answers.'
				: 'Select the correct answer.'}
		</p>
		<label class="points-label" for="points-{index}">
			<span>Points</span>
			<input
				id="points-{index}"
				class="points-input"
				type="number"
				min="1"
				max="1000"
				step="1"
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

	.remove-button:disabled {
		cursor: not-allowed;
		opacity: 0.4;
	}

	.order-button {
		display: grid;
		width: 2rem;
		height: 2rem;
		place-items: center;
		padding: 0;
		border: 1px solid var(--line);
		border-radius: 0.55rem;
		color: var(--navy);
	}

	.order-button:disabled {
		cursor: not-allowed;
		opacity: 0.35;
	}

	.field-label {
		display: block;
		margin-bottom: 0.55rem;
		color: var(--ink);
		font-size: 0.8rem;
		font-weight: 700;
	}

	.question-type-select {
		max-width: 17rem;
		padding: 0.65rem 0.8rem;
		font: inherit;
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

	.option-remove {
		display: grid;
		width: 2rem;
		height: 2rem;
		flex: 0 0 2rem;
		place-items: center;
		border: 1px solid var(--line);
		border-radius: 0.55rem;
		background: white;
		color: var(--ink-muted);
		font-size: 1.2rem;
		cursor: pointer;
	}

	.option-remove:disabled {
		cursor: not-allowed;
		opacity: 0.35;
	}

	.add-option {
		margin-top: 0.75rem;
		padding: 0.5rem 0.7rem;
		font-size: 0.78rem;
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

	.correct-choice.multiple-select .correct-indicator {
		border-radius: 0.3rem;
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
