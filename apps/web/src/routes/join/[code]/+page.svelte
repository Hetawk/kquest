<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { resolveJoinCode } from '#lib/features/activities/api.js';
	import type { PageProps } from './$types';

	let { data }: PageProps = $props();
	let error = $state('');

	onMount(() => {
		let cancelled = false;
		void resolveJoinCode(data.code)
			.then((destination) => {
				if (!cancelled) {
					return goto(
						destination.kind === 'live_room'
							? resolve('/room/[code]', { code: data.code })
							: resolve('/play/[code]', { code: data.code })
					);
				}
			})
			.catch((cause: unknown) => {
				error = cause instanceof Error ? cause.message : 'We couldn’t find that game link.';
			});
		return () => {
			cancelled = true;
		};
	});
</script>

<svelte:head>
	<title>Opening your game — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="page-shell route-state">
	<section class="route-card" aria-live="polite">
		<p class="eyebrow">Your adventure is waiting</p>
		<h1>{error ? 'We couldn’t open this game.' : 'Finding your game…'}</h1>
		{#if error}
			<p>{error}</p>
			<a class="button button-primary" href={resolve('/join')}>Enter a game code</a>
		{:else}
			<div class="loader" aria-hidden="true"></div>
		{/if}
	</section>
</main>

<style>
	.route-state {
		display: grid;
		min-height: 70vh;
		place-items: center;
	}
	.route-card {
		width: min(100%, 34rem);
		padding: 2rem;
		border: 1px solid var(--line);
		border-radius: 1.2rem;
		background: white;
		text-align: center;
		box-shadow: var(--shadow-card);
	}
	.route-card h1 {
		color: var(--navy);
		font-family: Manrope, sans-serif;
		font-size: clamp(1.5rem, 5vw, 2.5rem);
	}
	.route-card p:not(.eyebrow) {
		color: var(--ink-muted);
	}
	.loader {
		width: 2rem;
		height: 2rem;
		margin: 1.4rem auto 0;
		border: 2px solid #e8e0d0;
		border-top-color: var(--gold-deep);
		border-radius: 50%;
		animation: spin 800ms linear infinite;
	}
</style>
