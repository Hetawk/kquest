<script lang="ts">
	import { resolve } from '$app/paths';
	import '../app.css';
	import '@fontsource-variable/dm-sans';
	import '@fontsource-variable/manrope';
	import favicon from '#lib/assets/favicon.svg';
	import type { LayoutProps } from './$types';

	let { children }: LayoutProps = $props();
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

		<a class="header-cta" href={resolve('/create')}
			>Start creating <span aria-hidden="true">↗</span></a
		>
	</div>
</header>

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
	}

	.header-cta:hover {
		transform: translateY(-1px);
		border-color: #d2c4a8;
	}

	.header-cta span {
		margin-left: 0.3rem;
		color: var(--gold-deep);
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
			display: none;
		}
	}
</style>
