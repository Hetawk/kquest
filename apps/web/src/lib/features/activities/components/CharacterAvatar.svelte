<script lang="ts">
	import { getLearnerCharacter } from '../characters.js';

	let {
		avatarId,
		size = 'medium'
	}: { avatarId?: string | null; size?: 'small' | 'medium' | 'large' } = $props();

	const character = $derived(getLearnerCharacter(avatarId));
</script>

<span
	class="character-avatar"
	class:small={size === 'small'}
	class:large={size === 'large'}
	style:--character-color={character.color}
	aria-hidden="true"
>
	{character.emoji}
</span>

<style>
	.character-avatar {
		display: grid;
		width: 2.65rem;
		height: 2.65rem;
		flex: 0 0 auto;
		place-items: center;
		border: 1px solid rgb(24 46 95 / 8%);
		border-radius: 50%;
		background: var(--character-color);
		font-size: 1.45rem;
		line-height: 1;
	}

	.character-avatar.small {
		width: 2rem;
		height: 2rem;
		font-size: 1.1rem;
	}

	.character-avatar.large {
		width: 3.5rem;
		height: 3.5rem;
		font-size: 2rem;
	}
</style>
