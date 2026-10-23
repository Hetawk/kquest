<script lang="ts">
	import {
		LEARNER_CHARACTERS,
		getLearnerCharacter,
		type LearnerCharacterId
	} from '../characters.js';
	import CharacterAvatar from './CharacterAvatar.svelte';

	let {
		selectedId,
		disabled = false,
		onSelect
	}: {
		selectedId: string;
		disabled?: boolean;
		onSelect: (id: LearnerCharacterId) => void;
	} = $props();

	const selectedCharacter = $derived(getLearnerCharacter(selectedId));
</script>

<fieldset class="character-picker" {disabled}>
	<legend>
		<span>Choose your character</span>
		<span class="selected-name">Selected: {selectedCharacter.name}</span>
	</legend>
	<div class="character-options">
		{#each LEARNER_CHARACTERS as character (character.id)}
			<button
				class="character-option"
				class:selected={selectedId === character.id}
				type="button"
				aria-label="Choose {character.name}"
				aria-pressed={selectedId === character.id}
				title={character.name}
				onclick={() => onSelect(character.id)}
			>
				<CharacterAvatar avatarId={character.id} />
				<span>{character.name}</span>
			</button>
		{/each}
	</div>
</fieldset>

<style>
	.character-picker {
		min-width: 0;
		margin: 1rem 0;
		padding: 0;
		border: 0;
	}

	.character-picker legend {
		display: flex;
		width: 100%;
		align-items: baseline;
		justify-content: space-between;
		gap: 0.5rem;
		margin-bottom: 0.55rem;
		color: var(--navy);
		font-size: 0.78rem;
		font-weight: 800;
	}

	.selected-name {
		color: var(--ink-muted);
		font-size: 0.68rem;
		font-weight: 600;
	}

	.character-options {
		display: grid;
		grid-template-columns: repeat(6, minmax(0, 1fr));
		gap: 0.45rem;
	}

	.character-option {
		display: grid;
		min-width: 0;
		justify-items: center;
		gap: 0.25rem;
		padding: 0.45rem 0.2rem;
		border: 1px solid var(--line);
		border-radius: 0.75rem;
		background: white;
		color: var(--ink-soft);
		font: inherit;
		font-size: 0.62rem;
		font-weight: 700;
		cursor: pointer;
		transition:
			transform 150ms ease,
			border-color 150ms ease,
			background-color 150ms ease;
	}

	.character-option:hover:not(:disabled) {
		transform: translateY(-2px);
		border-color: #c8a061;
		background: #fffaf0;
	}

	.character-option.selected {
		border-color: var(--navy);
		background: #f1f3f9;
		color: var(--navy);
		box-shadow: 0 0 0 2px rgb(24 46 95 / 9%);
	}

	.character-option:disabled {
		cursor: not-allowed;
		opacity: 0.65;
	}

	@media (max-width: 420px) {
		.character-options {
			grid-template-columns: repeat(4, minmax(0, 1fr));
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.character-option {
			transition: none;
		}
	}
</style>
