<script lang="ts">
	import { resolve } from '$app/paths';
	import { onMount } from 'svelte';
	import {
		getCurrentUser,
		listCreatorActivities,
		publishActivity
	} from '#lib/features/activities/api.js';
	import type { CreatorActivity } from '#lib/features/activities/api.js';

	type ActivityFilter = 'all' | 'published' | 'draft';

	let user = $state<Awaited<ReturnType<typeof getCurrentUser>>>(null);
	let activities = $state<CreatorActivity[]>([]);
	let summary = $state({ total: 0, published: 0, plays: 0 });
	let filter = $state<ActivityFilter>('all');
	let search = $state('');
	let loading = $state(true);
	let busyActivityId = $state('');
	let error = $state('');
	let notice = $state('');
	const filters: { value: ActivityFilter; label: string }[] = [
		{ value: 'all', label: 'All quests' },
		{ value: 'published', label: 'Published' },
		{ value: 'draft', label: 'Drafts' }
	];

	const visibleActivities = $derived(
		activities.filter((activity) => {
			const matchesFilter = filter === 'all' || activity.status === filter;
			const query = search.trim().toLowerCase();
			return matchesFilter && (!query || activity.title.toLowerCase().includes(query));
		})
	);

	onMount(() => {
		void loadDashboard();
	});

	async function loadDashboard() {
		error = '';
		try {
			user = await getCurrentUser();
			if (!user) {
				window.location.replace(`${resolve('/auth')}?next=%2Fdashboard`);
				return;
			}
			const result = await listCreatorActivities();
			activities = result.activities;
			summary = result.summary;
		} catch (cause) {
			error =
				cause instanceof Error
					? cause.message
					: 'Your learning studio could not be loaded. Please try again.';
		} finally {
			loading = false;
		}
	}

	async function copyShareCode(activity: CreatorActivity) {
		if (!activity.share_code) return;
		error = '';
		notice = '';
		try {
			await navigator.clipboard.writeText(activity.share_code);
			notice = `Game code ${activity.share_code} copied.`;
		} catch {
			error = 'Copying is unavailable here. Select the game code to copy it.';
		}
	}

	async function copyJoinLink(activity: CreatorActivity) {
		if (!activity.share_code) return;
		error = '';
		notice = '';
		try {
			const url = new URL(resolve('/join'), window.location.origin);
			url.searchParams.set('code', activity.share_code);
			await navigator.clipboard.writeText(url.toString());
			notice = `Join link for ${activity.title} copied.`;
		} catch {
			error = 'Copying is unavailable here. Share the game code instead.';
		}
	}

	async function publishDraft(activity: CreatorActivity) {
		if (busyActivityId) return;
		busyActivityId = activity.id;
		error = '';
		notice = '';
		try {
			const publication = await publishActivity(activity.id);
			await loadDashboard();
			notice = `${activity.title} is published. Share code: ${publication.share_code}`;
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'The quest could not be published.';
		} finally {
			busyActivityId = '';
		}
	}

	async function openLiveRoom(activity: CreatorActivity) {
		if (!activity.share_code || busyActivityId) return;
		window.location.assign(resolve('/host/activities/[id]', { id: activity.id }));
	}

	function formatDate(value: string) {
		return new Intl.DateTimeFormat(undefined, { dateStyle: 'medium' }).format(new Date(value));
	}
</script>

<svelte:head>
	<title>Your learning studio — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="dashboard-shell page-shell">
	<aside class="studio-sidebar" aria-label="Studio navigation">
		<div class="sidebar-heading">
			<span class="sidebar-mark" aria-hidden="true">✦</span>
			<div><strong>Your studio</strong><small>Make room for wonder.</small></div>
		</div>
		<nav>
			<a class="sidebar-link active" href={resolve('/dashboard')} aria-current="page">
				<span aria-hidden="true">⌂</span> Overview
			</a>
			<a class="sidebar-link" href="#quests"><span aria-hidden="true">◈</span> My quests</a>
			<a class="sidebar-link" href={resolve('/create')}
				><span aria-hidden="true">＋</span> Create a quest</a
			>
			<a class="sidebar-link" href={resolve('/join')}
				><span aria-hidden="true">▷</span> Join a game</a
			>
		</nav>
		<div class="sidebar-note">
			<span aria-hidden="true">✧</span>
			<p>Your next great learning moment starts with one good question.</p>
			<a href={resolve('/create')}>Start creating <span aria-hidden="true">↗</span></a>
		</div>
	</aside>

	<section class="dashboard-content" aria-labelledby="dashboard-title">
		{#if loading}
			<section class="loading-workspace" role="status" aria-label="Loading your learning studio">
				<div class="loading-welcome">
					<div><span></span><span></span><span></span></div>
					<div class="loading-action"></div>
				</div>
				<div class="loading-summary">
					{#each [1, 2, 3] as item (item)}<div class="loading-summary-card"></div>{/each}
				</div>
				<div class="loading-library">
					<span></span><span></span><span></span>
				</div>
				<span class="visually-hidden">Opening your learning studio…</span>
			</section>
		{:else}
			<header class="dashboard-welcome">
				<div>
					<p class="eyebrow">Your learning studio</p>
					<h1 id="dashboard-title">Welcome back, {user?.name.split(' ')[0] ?? 'educator'}.</h1>
					<p>All your quests, ready for the next moment of discovery.</p>
				</div>
				<a class="button button-primary" href={resolve('/create')}>＋ Create a quest</a>
			</header>

			{#if error}<p class="dashboard-alert" role="alert">{error}</p>{/if}
			{#if notice}<p class="dashboard-notice" role="status">{notice}</p>{/if}

			<div class="summary-grid" aria-label="Studio summary">
				<article class="summary-card">
					<span class="summary-icon navy" aria-hidden="true">◈</span>
					<div><span>Quests created</span><strong>{summary.total}</strong></div>
				</article>
				<article class="summary-card">
					<span class="summary-icon gold" aria-hidden="true">✦</span>
					<div><span>Published quests</span><strong>{summary.published}</strong></div>
				</article>
				<article class="summary-card">
					<span class="summary-icon green" aria-hidden="true">▷</span>
					<div><span>Completed plays</span><strong>{summary.plays}</strong></div>
				</article>
			</div>

			<section id="quests" class="quest-library" aria-labelledby="quests-title">
				<div class="library-heading">
					<div>
						<p class="eyebrow">Your collection</p>
						<h2 id="quests-title">My quests</h2>
					</div>
					<span class="quest-count">
						{#if summary.total > activities.length}
							Latest {activities.length} of {summary.total} quests
						{:else}
							{summary.total} {summary.total === 1 ? 'quest' : 'quests'}
						{/if}
					</span>
				</div>

				<div class="library-controls">
					<label class="search-box">
						<span class="visually-hidden">Search your quests</span>
						<span aria-hidden="true">⌕</span>
						<input bind:value={search} type="search" placeholder="Search your quests" />
					</label>
					<div class="filter-tabs" aria-label="Filter quests">
						{#each filters as option (option.value)}
							<button
								type="button"
								class:chosen={filter === option.value}
								aria-pressed={filter === option.value}
								onclick={() => (filter = option.value)}
							>
								{option.label}
							</button>
						{/each}
					</div>
				</div>

				{#if visibleActivities.length}
					<div class="quest-list">
						{#each visibleActivities as activity (activity.id)}
							<article class="quest-card">
								<div class="quest-card-main">
									<div class="quest-card-heading">
										<h3>
											<a href={resolve('/dashboard/quests/[id]', { id: activity.id })}>
												{activity.title}
											</a>
										</h3>
										<span class:published={activity.status === 'published'} class="status-pill">
											{activity.status}
										</span>
									</div>
									<p class="quest-description">
										{activity.description || 'A learning adventure ready to take shape.'}
									</p>
									<div class="quest-meta">
										<span
											>{activity.question_count}
											{activity.question_count === 1 ? 'question' : 'questions'}</span
										>
										<span
											>{activity.total_plays} {activity.total_plays === 1 ? 'play' : 'plays'}</span
										>
										<span>Updated {formatDate(activity.updated_at)}</span>
									</div>
								</div>
								{#if activity.share_code}
									<div class="share-panel">
										<div>
											<span>Share code</span>
											<strong>{activity.share_code}</strong>
										</div>
										<button type="button" class="code-copy" onclick={() => copyShareCode(activity)}>
											Copy code
										</button>
									</div>
									<div class="quest-actions">
										<button type="button" class="text-link" onclick={() => copyJoinLink(activity)}>
											Copy join link <span aria-hidden="true">↗</span>
										</button>
										<a
											class="text-link"
											href={resolve('/play/[code]', { code: activity.share_code })}
										>
											Preview quest <span aria-hidden="true">↗</span>
										</a>
										<button
											type="button"
											class="text-link"
											disabled={busyActivityId === activity.id}
											onclick={() => openLiveRoom(activity)}
										>
											{busyActivityId === activity.id ? 'Opening room…' : 'Host live game'}
											<span aria-hidden="true">↗</span>
										</button>
									</div>
								{:else}
									<div class="draft-note">Publish this quest to get a share code.</div>
									<button
										type="button"
										class="text-link"
										disabled={busyActivityId === activity.id}
										onclick={() => publishDraft(activity)}
									>
										{busyActivityId === activity.id ? 'Publishing…' : 'Publish draft'}
										<span aria-hidden="true">↗</span>
									</button>
								{/if}
							</article>
						{/each}
					</div>
				{:else if activities.length}
					<div class="empty-state">
						<div class="empty-icon" aria-hidden="true">⌕</div>
						<h3>No quests match that view.</h3>
						<p>Try another search or choose a different filter.</p>
					</div>
				{:else}
					<div class="empty-state">
						<div class="empty-icon" aria-hidden="true">✧</div>
						<h3>Your first quest is waiting.</h3>
						<p>Bring your questions, set the pace, and share a six-character game code.</p>
						<a class="button button-primary" href={resolve('/create')}>Create your first quest</a>
					</div>
				{/if}
			</section>
		{/if}
	</section>
</main>

<style>
	.dashboard-shell {
		display: grid;
		grid-template-columns: 15.5rem minmax(0, 1fr);
		gap: clamp(1.5rem, 4vw, 3rem);
		padding-block: 2.5rem 5rem;
	}

	.studio-sidebar {
		position: sticky;
		top: 1.5rem;
		display: flex;
		height: max-content;
		min-height: 36rem;
		flex-direction: column;
		padding: 1.15rem;
		border: 1px solid var(--line);
		border-radius: 1.1rem;
		background: rgb(255 255 255 / 76%);
	}

	.sidebar-heading {
		display: flex;
		align-items: center;
		gap: 0.75rem;
		padding: 0.25rem 0.3rem 1.5rem;
		border-bottom: 1px solid var(--line);
	}

	.sidebar-mark,
	.summary-icon,
	.empty-icon {
		display: grid;
		flex: 0 0 auto;
		place-items: center;
	}

	.sidebar-mark {
		width: 2.35rem;
		height: 2.35rem;
		border-radius: 0.75rem;
		background: #fbf2e2;
		color: var(--gold-deep);
	}

	.sidebar-heading div {
		display: grid;
		gap: 0.2rem;
	}

	.sidebar-heading strong {
		font-family: Manrope, sans-serif;
		font-size: 0.9rem;
	}

	.sidebar-heading small {
		color: var(--ink-muted);
		font-size: 0.7rem;
	}

	.studio-sidebar nav {
		display: grid;
		gap: 0.35rem;
		padding-block: 1.2rem;
	}

	.sidebar-link {
		display: flex;
		min-height: 2.85rem;
		align-items: center;
		gap: 0.75rem;
		padding: 0.65rem 0.8rem;
		border-radius: 0.7rem;
		color: var(--ink-soft);
		font-size: 0.84rem;
		font-weight: 650;
		text-decoration: none;
	}

	.sidebar-link > span {
		width: 1.2rem;
		color: var(--gold-deep);
		font-size: 1.05rem;
		text-align: center;
	}

	.sidebar-link:hover,
	.sidebar-link.active {
		background: var(--navy-soft);
		color: var(--navy);
	}

	.sidebar-note {
		margin-top: auto;
		padding: 1rem;
		border: 1px solid #eee0c6;
		border-radius: 0.85rem;
		background: #fcf7ed;
		color: var(--gold-deep);
	}

	.sidebar-note p {
		margin: 0.6rem 0 0.85rem;
		color: var(--ink-soft);
		font-size: 0.78rem;
		line-height: 1.55;
	}

	.sidebar-note a {
		color: var(--navy);
		font-size: 0.76rem;
		font-weight: 750;
		text-decoration: none;
	}

	.dashboard-content {
		min-width: 0;
	}

	.dashboard-welcome {
		display: flex;
		align-items: flex-end;
		justify-content: space-between;
		gap: 1.25rem;
		padding: 0.7rem 0 1.8rem;
	}

	.dashboard-welcome .eyebrow,
	.library-heading .eyebrow {
		margin: 0;
	}

	.dashboard-welcome h1 {
		margin: 0.8rem 0 0.45rem;
		font-family: Manrope, sans-serif;
		font-size: clamp(1.8rem, 3.5vw, 2.65rem);
		font-weight: 800;
		letter-spacing: -0.065em;
		line-height: 1.12;
	}

	.dashboard-welcome > div > p:last-child {
		margin: 0;
		color: var(--ink-soft);
		font-size: 0.92rem;
	}

	.dashboard-welcome .button {
		flex: 0 0 auto;
	}

	.summary-grid {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 0.85rem;
	}

	.summary-card {
		display: flex;
		min-height: 7.25rem;
		align-items: center;
		gap: 0.85rem;
		padding: 1.1rem;
		border: 1px solid var(--line);
		border-radius: 0.95rem;
		background: white;
	}

	.summary-icon {
		width: 2.5rem;
		height: 2.5rem;
		border-radius: 0.75rem;
	}

	.summary-icon.navy {
		background: var(--navy-soft);
		color: var(--navy);
	}

	.summary-icon.gold {
		background: #fbf2e2;
		color: var(--gold-deep);
	}

	.summary-icon.green {
		background: #e9f4ee;
		color: var(--success);
	}

	.summary-card div {
		display: grid;
		gap: 0.35rem;
	}

	.summary-card div span {
		color: var(--ink-muted);
		font-size: 0.72rem;
	}

	.summary-card strong {
		font-family: Manrope, sans-serif;
		font-size: 1.55rem;
		line-height: 1;
	}

	.quest-library {
		margin-top: 2.35rem;
	}

	.library-heading {
		display: flex;
		align-items: end;
		justify-content: space-between;
		gap: 1rem;
	}

	.library-heading h2 {
		margin: 0.45rem 0 0;
		font-family: Manrope, sans-serif;
		font-size: 1.55rem;
		letter-spacing: -0.05em;
	}

	.quest-count {
		padding: 0.42rem 0.68rem;
		border-radius: 999px;
		background: #f1eee8;
		color: var(--ink-soft);
		font-size: 0.72rem;
		font-weight: 700;
	}

	.library-controls {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		margin-block: 1.15rem;
	}

	.search-box {
		display: flex;
		width: min(100%, 20rem);
		min-height: 2.7rem;
		align-items: center;
		gap: 0.6rem;
		padding-inline: 0.8rem;
		border: 1px solid var(--line);
		border-radius: 0.7rem;
		background: white;
		color: var(--ink-muted);
	}

	.search-box > span:not(.visually-hidden) {
		font-size: 1.3rem;
	}

	.search-box input {
		width: 100%;
		border: 0;
		outline: 0;
		background: transparent;
		color: var(--ink);
		font-size: 0.82rem;
	}

	.filter-tabs {
		display: flex;
		gap: 0.25rem;
		padding: 0.22rem;
		border-radius: 0.7rem;
		background: #f0ede7;
	}

	.filter-tabs button {
		min-height: 2.2rem;
		padding-inline: 0.7rem;
		border: 0;
		border-radius: 0.55rem;
		background: transparent;
		color: var(--ink-soft);
		font-size: 0.72rem;
		font-weight: 700;
		cursor: pointer;
	}

	.filter-tabs button.chosen {
		background: white;
		box-shadow: 0 1px 3px rgb(35 31 24 / 9%);
		color: var(--navy);
	}

	.quest-list {
		display: grid;
		gap: 0.8rem;
	}

	.quest-card {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		gap: 0.85rem 1rem;
		padding: 1.15rem;
		border: 1px solid var(--line);
		border-radius: 0.95rem;
		background: white;
		transition:
			transform 160ms ease,
			box-shadow 160ms ease;
	}

	.quest-card:hover {
		transform: translateY(-2px);
		box-shadow: 0 0.8rem 1.8rem rgb(35 31 24 / 6%);
	}

	.quest-card-main {
		min-width: 0;
	}

	.quest-card-heading {
		display: flex;
		align-items: center;
		gap: 0.65rem;
	}

	.quest-card-heading h3 {
		overflow: hidden;
		margin: 0;
		font-family: Manrope, sans-serif;
		font-size: 1rem;
		letter-spacing: -0.025em;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.quest-card-heading h3 a {
		color: inherit;
		text-decoration: none;
	}

	.quest-card-heading h3 a:hover {
		color: var(--gold-deep);
	}

	.status-pill {
		padding: 0.25rem 0.48rem;
		border-radius: 999px;
		background: #f0ede7;
		color: var(--ink-soft);
		font-size: 0.63rem;
		font-weight: 800;
		text-transform: capitalize;
	}

	.status-pill.published {
		background: #e9f4ee;
		color: var(--success);
	}

	.quest-description {
		overflow: hidden;
		margin: 0.42rem 0;
		color: var(--ink-soft);
		font-size: 0.78rem;
		text-overflow: ellipsis;
		white-space: nowrap;
	}

	.quest-meta {
		display: flex;
		flex-wrap: wrap;
		gap: 0.45rem 1rem;
		color: var(--ink-muted);
		font-size: 0.68rem;
	}

	.share-panel {
		display: flex;
		min-width: 9rem;
		align-items: center;
		justify-content: space-between;
		gap: 0.65rem;
		padding: 0.55rem 0.7rem;
		border: 1px solid #eee0c6;
		border-radius: 0.7rem;
		background: #fcf7ed;
	}

	.share-panel div {
		display: grid;
		gap: 0.18rem;
	}

	.share-panel div span {
		color: var(--ink-muted);
		font-size: 0.61rem;
	}

	.share-panel strong {
		font-size: 0.92rem;
		letter-spacing: 0.12em;
	}

	.code-copy {
		padding: 0.45rem;
		border: 0;
		border-radius: 0.45rem;
		background: white;
		color: var(--navy);
		font-size: 0.66rem;
		font-weight: 750;
		cursor: pointer;
	}

	.quest-actions {
		display: flex;
		grid-column: 1 / -1;
		justify-content: flex-end;
		gap: 1rem;
		padding-top: 0.15rem;
	}

	.text-link {
		padding: 0;
		border: 0;
		background: transparent;
		color: var(--navy);
		font-size: 0.72rem;
		font-weight: 750;
		text-decoration: none;
		cursor: pointer;
	}

	.text-link:disabled {
		cursor: wait;
		opacity: 0.6;
	}

	.draft-note {
		align-self: center;
		color: var(--ink-muted);
		font-size: 0.72rem;
	}

	.empty-state {
		display: grid;
		justify-items: center;
		padding: 3.5rem 1.5rem;
		border: 1px dashed #dcd4c7;
		border-radius: 1rem;
		background: rgb(255 255 255 / 56%);
		text-align: center;
	}

	.loading-workspace {
		display: grid;
		gap: 1rem;
	}

	.loading-welcome,
	.loading-summary-card,
	.loading-library {
		border: 1px solid var(--line);
		border-radius: 1rem;
		background: white;
	}

	.loading-welcome {
		display: flex;
		min-height: 10rem;
		align-items: center;
		justify-content: space-between;
		gap: 1rem;
		padding: 1.5rem;
	}

	.loading-welcome > div:first-child,
	.loading-library {
		display: grid;
		gap: 0.8rem;
	}

	.loading-welcome span,
	.loading-action,
	.loading-summary-card,
	.loading-library span {
		background: linear-gradient(100deg, #f2efe9 25%, #fbfaf7 45%, #f2efe9 65%);
		background-size: 220% 100%;
		animation: dashboard-skeleton 1.5s ease-in-out infinite;
	}

	.loading-welcome span {
		display: block;
		width: min(32rem, 60vw);
		height: 0.85rem;
		border-radius: 999px;
	}

	.loading-welcome span:first-child {
		width: min(12rem, 35vw);
		height: 0.55rem;
	}

	.loading-welcome span:last-child {
		width: min(22rem, 48vw);
		height: 0.65rem;
	}

	.loading-action {
		width: 8rem;
		height: 2.5rem;
		border-radius: 0.75rem;
	}

	.loading-summary {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 0.85rem;
	}

	.loading-summary-card {
		min-height: 6rem;
	}

	.loading-library {
		min-height: 15rem;
		padding: 1rem;
	}

	.loading-library span {
		height: 3.3rem;
		border-radius: 0.7rem;
	}

	@keyframes dashboard-skeleton {
		to {
			background-position: -220% 0;
		}
	}

	.empty-icon {
		width: 3rem;
		height: 3rem;
		border-radius: 1rem;
		background: #fbf2e2;
		color: var(--gold-deep);
		font-size: 1.25rem;
	}

	.empty-state h3 {
		margin: 1rem 0 0.4rem;
		font-family: Manrope, sans-serif;
		font-size: 1.1rem;
	}

	.empty-state p {
		max-width: 24rem;
		margin: 0 0 1.15rem;
		color: var(--ink-soft);
		font-size: 0.82rem;
		line-height: 1.6;
	}

	@media (max-width: 560px) {
		.loading-summary {
			grid-template-columns: 1fr;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.loading-welcome span,
		.loading-action,
		.loading-summary-card,
		.loading-library span {
			animation: none;
		}
	}

	.dashboard-alert,
	.dashboard-notice {
		padding: 0.8rem 1rem;
		border-radius: 0.75rem;
		font-size: 0.82rem;
	}

	.dashboard-alert {
		background: #fff4f1;
		color: #792b21;
	}

	.dashboard-notice {
		background: #e9f4ee;
		color: #23684e;
	}

	.visually-hidden {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip: rect(0, 0, 0, 0);
		white-space: nowrap;
		clip-path: inset(50%);
	}

	@media (max-width: 900px) {
		.dashboard-shell {
			grid-template-columns: 12.5rem minmax(0, 1fr);
			gap: 1.25rem;
		}

		.studio-sidebar {
			min-height: 31rem;
		}

		.summary-card {
			align-items: flex-start;
			flex-direction: column;
			gap: 0.65rem;
		}
	}

	@media (max-width: 680px) {
		.dashboard-shell {
			grid-template-columns: minmax(0, 1fr);
			gap: 1.2rem;
			padding-block: 1.25rem 3rem;
		}

		.studio-sidebar {
			position: static;
			min-height: 0;
			padding: 0.8rem;
		}

		.sidebar-heading,
		.sidebar-note {
			display: none;
		}

		.studio-sidebar nav {
			display: flex;
			overflow-x: auto;
			gap: 0.3rem;
			padding: 0;
		}

		.sidebar-link {
			min-height: 2.55rem;
			flex: 0 0 auto;
			gap: 0.4rem;
			padding-inline: 0.65rem;
			font-size: 0.73rem;
		}

		.dashboard-welcome {
			align-items: flex-start;
			flex-direction: column;
			padding-top: 0.2rem;
		}

		.summary-grid {
			grid-template-columns: repeat(3, minmax(0, 1fr));
			gap: 0.45rem;
		}

		.summary-card {
			min-height: 6.4rem;
			align-items: flex-start;
			padding: 0.75rem;
		}

		.summary-icon {
			width: 2rem;
			height: 2rem;
		}

		.summary-card div span {
			font-size: 0.62rem;
		}

		.summary-card strong {
			font-size: 1.25rem;
		}

		.library-controls {
			align-items: stretch;
			flex-direction: column;
		}

		.search-box {
			width: 100%;
		}

		.filter-tabs {
			width: max-content;
			max-width: 100%;
		}

		.quest-card {
			grid-template-columns: minmax(0, 1fr);
		}

		.share-panel {
			width: fit-content;
		}

		.quest-actions {
			justify-content: flex-start;
			flex-wrap: wrap;
		}
	}

	@media (max-width: 400px) {
		.summary-grid {
			grid-template-columns: 1fr;
		}

		.summary-card {
			min-height: 0;
			align-items: center;
			flex-direction: row;
		}
	}
</style>
