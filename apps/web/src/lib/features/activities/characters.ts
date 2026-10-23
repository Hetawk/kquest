export const LEARNER_CHARACTERS = [
	{ id: 'fox', name: 'Fox', emoji: '🦊', color: '#f7ead8' },
	{ id: 'panda', name: 'Panda', emoji: '🐼', color: '#e8edf2' },
	{ id: 'lion', name: 'Lion', emoji: '🦁', color: '#f5e8ca' },
	{ id: 'frog', name: 'Frog', emoji: '🐸', color: '#e2f0e3' },
	{ id: 'cat', name: 'Cat', emoji: '🐱', color: '#f4e6e4' },
	{ id: 'penguin', name: 'Penguin', emoji: '🐧', color: '#e4edf5' },
	{ id: 'tiger', name: 'Tiger', emoji: '🐯', color: '#f7e5d2' },
	{ id: 'rabbit', name: 'Rabbit', emoji: '🐰', color: '#f4e4ec' },
	{ id: 'owl', name: 'Owl', emoji: '🦉', color: '#eee6f5' },
	{ id: 'unicorn', name: 'Unicorn', emoji: '🦄', color: '#f4e5f2' },
	{ id: 'koala', name: 'Koala', emoji: '🐨', color: '#e8e9ed' },
	{ id: 'dragon', name: 'Dragon', emoji: '🐲', color: '#e3efe8' }
] as const;

export type LearnerCharacterId = (typeof LEARNER_CHARACTERS)[number]['id'];

export const DEFAULT_CHARACTER_ID: LearnerCharacterId = 'fox';

export function isLearnerCharacterId(value: unknown): value is LearnerCharacterId {
	return (
		typeof value === 'string' && LEARNER_CHARACTERS.some((character) => character.id === value)
	);
}

export function getLearnerCharacter(id?: string | null) {
	return LEARNER_CHARACTERS.find((character) => character.id === id) ?? LEARNER_CHARACTERS[0];
}
