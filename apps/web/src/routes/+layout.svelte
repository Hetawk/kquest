<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import { getCurrentUser, signOut } from '#lib/features/activities/api.js';
	import '../app.css';
	import '@fontsource-variable/dm-sans';
	import '@fontsource-variable/manrope';
	import favicon from '#lib/assets/favicon.svg';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();
	let currentUser = $state<Awaited<ReturnType<typeof getCurrentUser>>>(null);
	let authError = $state('');
	let authNotice = $state('');

	onMount(() => {
		const status = new URLSearchParams(window.location.search).get('auth');
		authNotice =
			status === 'signed_in'
				? 'You are signed in.'
				: status === 'account_conflict'
					? 'That email is already linked to another sign-in. Contact support to connect accounts.'
					: status === 'account_suspended'
						? 'This account is not currently active.'
						: status === 'google_sign_in_failed'
							? 'Google sign-in did not complete. Please try again.'
							: '';

		void getCurrentUser()
			.then((user) => {
				currentUser = user;
			})
			.catch((error: unknown) => {
				authError =
					error instanceof Error
						? error.message
						: 'Authentication services are temporarily unavailable.';
			});
	});

	async function handleSignOut() {
		authError = '';
		try {
			await signOut();
			currentUser = null;
			authNotice = 'You have signed out.';
		} catch (error) {
			authError = error instanceof Error ? error.message : 'Could not safely end this session.';
		}
	}
</script>

<svelte:head>
	<link rel="icon" href={favicon} />
	<meta
		name="description"
		content="Create joyful learning quests, play together, and turn practice into progress."
	/>
</svelte:head>

<header class="site-header">
	<div class="header-inner page-shell">
		<a class="brand" href={resolve('/')} aria-label="KINGDOM Quest home">
			<span class="brand-mark" aria-hidden="true">K</span>
			<span class="brand-name">KINGDOM<span>QUEST</span></span>
		</a>

		<nav class="main-nav" aria-label="Main navigation">
			<a href={resolve('/create')}>Create</a>
			<a href={resolve('/join')}>Join a game</a>
		</nav>

		{#if currentUser}
			<div class="account-actions">
				<span class="account-name">{currentUser.name}</span>
				<button class="header-cta" type="button" onclick={handleSignOut}>Sign out</button>
			</div>
		{:else}
			<a class="header-cta" href={resolve('/auth')}>Sign in</a>
		{/if}
	</div>
</header>

{#if authNotice || authError}
	<div
		class:auth-error={authError}
		class="auth-status page-shell"
		role={authError ? 'alert' : 'status'}
	>
		{authError || authNotice}
	</div>
{/if}

{@render children()}

<style>
	.site-header {
		position: relative;
		z-index: 5;
		border-bottom: 1px solid rgb(233 229 220 / 75%);
		background: rgb(253 251 247 / 91%);
		backdrop-filter: blur(16px);
	}

	.header-inner {
		display: flex;
		min-height: 5rem;
		align-items: center;
		justify-content: space-between;
		gap: 2rem;
	}

	.brand {
		display: inline-flex;
		align-items: center;
		gap: 0.7rem;
		color: var(--ink);
		text-decoration: none;
	}

	.brand-mark {
		display: grid;
		width: 2.4rem;
		height: 2.4rem;
		place-items: center;
		border-radius: 0.75rem;
		background: var(--navy);
		color: #f7e7c8;
		font-family: Manrope, sans-serif;
		font-size: 1.2rem;
		font-weight: 800;
	}

	.brand-name {
		display: flex;
		flex-direction: column;
		font-family: Manrope, sans-serif;
		font-size: 0.73rem;
		font-weight: 800;
		letter-spacing: 0.09em;
		line-height: 1.3;
	}

	.brand-name span {
		color: var(--gold-deep);
		font-size: 0.6rem;
		letter-spacing: 0.23em;
	}

	.main-nav {
		display: flex;
		align-items: center;
		gap: 2rem;
		margin-left: auto;
	}

	.main-nav a {
		color: var(--ink-soft);
		font-size: 0.86rem;
		font-weight: 600;
		text-decoration: none;
		transition: color 150ms ease;
	}

	.main-nav a:hover {
		color: var(--navy);
	}

	.header-cta {
		padding: 0.72rem 0.95rem;
		border: 1px solid var(--line);
		border-radius: 0.7rem;
		background: white;
		color: var(--navy);
		font-size: 0.82rem;
		font-weight: 700;
		text-decoration: none;
		transition:
			border-color 150ms ease,
			transform 150ms ease;
		cursor: pointer;
	}

	.header-cta:disabled {
		cursor: wait;
		opacity: 0.65;
	}

	.account-actions {
		display: flex;
		align-items: center;
		gap: 0.75rem;
	}

	.account-name {
		color: var(--ink-soft);
		font-size: 0.82rem;
		font-weight: 600;
	}

	.auth-status {
		padding-top: 0.7rem;
		color: var(--navy);
		font-size: 0.85rem;
	}

	.auth-error {
		color: #a32727;
	}

	.header-cta:hover {
		transform: translateY(-1px);
		border-color: #d2c4a8;
	}

	@media (max-width: 560px) {
		.header-inner {
			min-height: 4.35rem;
			gap: 0.75rem;
		}

		.main-nav {
			gap: 1rem;
		}

		.main-nav a {
			font-size: 0.75rem;
		}

		.header-cta {
			padding: 0.62rem 0.72rem;
			font-size: 0.72rem;
		}

		.account-name {
			display: none;
		}
	}
</style>
