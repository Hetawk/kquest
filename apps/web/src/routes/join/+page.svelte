<script lang="ts">
	import { resolve } from '$app/paths';
	import { goto } from '$app/navigation';
	import { onMount } from 'svelte';
	import { resolveJoinCode } from '#lib/features/activities/api.js';

	let code = $state('');
	let error = $state('');
	let resolving = $state(false);

	onMount(() => {
		const sharedCode = new URLSearchParams(window.location.search).get('code');
		if (!sharedCode) return;

		code = sharedCode;
		void findGame(sharedCode);
	});

	function normalizedCode(value: string) {
		return value.toUpperCase().replace(/[^A-HJ-NP-Z2-9]/g, '');
	}

	async function submit(event: SubmitEvent) {
		event.preventDefault();
		await findGame(code);
	}

	async function findGame(value: string) {
		const normalized = normalizedCode(value);
		if (normalized.length !== 6) {
			error = 'A game code has 6 letters or numbers. Check with your teacher and try again.';
			return;
		}
		if (resolving) return;

		resolving = true;
		error = '';
		try {
			const destination = await resolveJoinCode(normalized);
			await goto(
				destination.kind === 'live_room'
					? resolve('/room/[code]', { code: normalized })
					: resolve('/play/[code]', { code: normalized })
			);
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'We couldn’t find that game code.';
		} finally {
			resolving = false;
		}
	}
</script>

<svelte:head>
	<title>Join a game — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell join-page">
	<a class="back-link" href={resolve('/')}>← Back to home</a>
	<section class="join-card" aria-labelledby="join-heading">
		<div class="join-mark" aria-hidden="true">↗</div>
		<p class="eyebrow">Your next adventure is waiting</p>
		<h1 id="join-heading" class="page-heading">You’re in the right place.</h1>
		<p class="page-intro">
			Enter a game code or open the link your host shared. You’ll choose a display name before
			joining.
		</p>

		<form class="join-form" onsubmit={submit}>
			<label class="field-label" for="join-code">6-character game code</label>
			<input
				id="join-code"
				class="code-input"
				type="text"
				autocomplete="off"
				autocapitalize="characters"
				spellcheck="false"
				maxlength="6"
				placeholder="e.g. AB3D7K"
				bind:value={code}
				oninput={() => (error = '')}
				required
			/>
			{#if error}<p class="error-message" role="alert">{error}</p>{/if}
			<button class="button button-primary join-button" type="submit" disabled={resolving}>
				{resolving ? 'Finding your game…' : 'Find my game'} <span aria-hidden="true">↗</span>
			</button>
		</form>
		<div class="join-choice">
			<strong>Choose how to join</strong>
			<p>
				Play as a guest with no account, or
				<a href={resolve('/auth')}>sign in to your account</a> if you prefer. Guest play is always available.
			</p>
		</div>
		<p class="join-footer">
			Direct links with a game code work too — no need to enter the code twice.
		</p>
	</section>
</main>

<style>
	.join-page {
		min-height: calc(100vh - 5rem);
		padding-block: 2rem 4rem;
	}

	.back-link {
		display: inline-block;
		margin-bottom: 1rem;
		color: var(--ink-muted);
		font-size: 0.82rem;
		font-weight: 600;
		text-decoration: none;
	}

	.back-link:hover {
		color: var(--navy);
	}

	.join-card {
		display: flex;
		max-width: 37rem;
		flex-direction: column;
		align-items: center;
		margin: 2rem auto;
		padding: clamp(1.7rem, 7vw, 3.25rem);
		border: 1px solid var(--line);
		border-radius: 1.5rem;
		background: radial-gradient(ellipse at 50% 0%, rgb(237 228 207 / 44%), transparent 48%), white;
		box-shadow: var(--shadow-card);
		text-align: center;
	}

	.join-mark {
		display: grid;
		width: 3.5rem;
		height: 3.5rem;
		place-items: center;
		margin-bottom: 1rem;
		border-radius: 1.1rem;
		background: var(--navy-soft);
		color: var(--navy);
		font-size: 1.55rem;
	}

	.join-card .eyebrow {
		justify-content: center;
	}

	.join-card .eyebrow::after {
		width: 1.6rem;
		height: 1px;
		background: currentColor;
		content: '';
	}

	.join-card .page-heading {
		font-size: clamp(1.9rem, 6vw, 2.8rem);
	}

	.join-card .page-intro {
		max-width: 27rem;
	}

	.join-form {
		display: grid;
		width: min(100%, 27rem);
		gap: 0.75rem;
		margin-top: 1.8rem;
		text-align: left;
	}

	.code-input {
		width: 100%;
		padding: 1rem;
		border: 1px solid var(--line);
		border-radius: 0.9rem;
		background: white;
		color: var(--navy);
		font-family: Manrope, monospace;
		font-size: 1.2rem;
		font-weight: 800;
		letter-spacing: 0.2em;
		text-align: center;
		text-transform: uppercase;
	}

	.code-input:focus {
		border-color: var(--gold-deep);
		box-shadow: 0 0 0 3px rgb(200 160 97 / 17%);
		outline: none;
	}

	.code-input::placeholder {
		color: #b0aaa0;
		letter-spacing: 0.12em;
	}

	.join-button {
		width: 100%;
		margin-top: 0.3rem;
	}

	.join-footer {
		margin: 1.3rem 0 0;
		color: var(--ink-muted);
		font-size: 0.75rem;
	}

	.join-choice {
		width: min(100%, 27rem);
		margin-top: 1.2rem;
		padding: 0.9rem 1rem;
		border: 1px solid var(--line);
		border-radius: 0.8rem;
		background: #fffdf9;
		text-align: left;
	}

	.join-choice strong {
		color: var(--navy);
		font-size: 0.78rem;
	}
	.join-choice p {
		margin: 0.3rem 0 0;
		color: var(--ink-muted);
		font-size: 0.74rem;
		line-height: 1.55;
	}
	.join-choice a {
		color: var(--navy);
		font-weight: 700;
	}
</style>
