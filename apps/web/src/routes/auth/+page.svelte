<script lang="ts">
	import { onMount } from 'svelte';
	import { getCsrfToken, getCurrentUser } from '#lib/features/activities/api.js';
	import {
		registerWithEmail,
		signInWithEmail,
		verifyEmailAddress,
		resendEmailVerification,
		requestPasswordReset,
		resetPassword
	} from '#lib/features/auth/api.js';

	type AuthMode = 'sign_in' | 'sign_up' | 'verify_email' | 'forgot_password' | 'reset_password';

	let mode = $state<AuthMode>('sign_in');
	let email = $state('');
	let name = $state('');
	let password = $state('');
	let passwordConfirmation = $state('');
	let code = $state('');
	let busy = $state(false);
	let checkingSession = $state(true);
	let csrfToken = $state('');
	let error = $state('');
	let notice = $state('');
	let nextPath = $state('/');

	const isEmailMode = $derived(mode === 'sign_in' || mode === 'sign_up');

	onMount(() => {
		const requestedPath = new URLSearchParams(window.location.search).get('next');
		if (requestedPath?.startsWith('/')) {
			const destination = new URL(requestedPath, window.location.origin);
			if (destination.origin === window.location.origin) {
				nextPath = `${destination.pathname}${destination.search}${destination.hash}`;
			}
		}

		void Promise.all([getCurrentUser(), getCsrfToken()])
			.then(([user, token]) => {
				csrfToken = token;
				if (user) window.location.assign(nextPath);
			})
			.catch((cause: unknown) => {
				error =
					cause instanceof Error ? cause.message : 'Authentication is temporarily unavailable.';
			})
			.finally(() => {
				checkingSession = false;
			});
	});

	function setMode(nextMode: AuthMode) {
		mode = nextMode;
		error = '';
		notice = '';
		code = '';
		password = '';
		passwordConfirmation = '';
	}

	async function handleSubmit(event: SubmitEvent) {
		event.preventDefault();
		if (busy) return;

		error = '';
		notice = '';
		busy = true;
		try {
			if (mode === 'sign_in') {
				await signInWithEmail({ email, password });
				window.location.assign(nextPath);
			} else if (mode === 'sign_up') {
				const result = await registerWithEmail({
					email,
					name,
					password,
					password_confirmation: passwordConfirmation
				});
				email = result.email;
				setMode('verify_email');
				notice = 'We sent a six-digit verification code to your email.';
			} else if (mode === 'verify_email') {
				await verifyEmailAddress({ email, code });
				window.location.assign(nextPath);
			} else if (mode === 'forgot_password') {
				const result = await requestPasswordReset({ email });
				setMode('reset_password');
				notice = result.message;
			} else {
				await resetPassword({
					email,
					code,
					password,
					password_confirmation: passwordConfirmation
				});
				window.location.assign(nextPath);
			}
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'We could not complete that request.';
		} finally {
			busy = false;
		}
	}

	async function handleResendCode() {
		if (busy) return;
		busy = true;
		error = '';
		notice = '';
		try {
			const result = await resendEmailVerification({ email });
			notice = result.message;
		} catch (cause) {
			error = cause instanceof Error ? cause.message : 'We could not send another code.';
		} finally {
			busy = false;
		}
	}
</script>

<svelte:head>
	<title>{mode === 'sign_up' ? 'Create your account' : 'Sign in'} — KINGDOM Quest</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<main class="auth-page page-shell">
	<section class="auth-card" aria-labelledby="auth-heading">
		<div class="auth-heading">
			<p class="eyebrow">Your learning studio</p>
			<h1 id="auth-heading">
				{#if mode === 'sign_up'}
					Create your account.
				{:else if mode === 'verify_email'}
					Check your email.
				{:else if mode === 'forgot_password'}
					Reset your password.
				{:else if mode === 'reset_password'}
					Choose a new password.
				{:else}
					Welcome back.
				{/if}
			</h1>
			<p class="auth-description">
				{#if mode === 'sign_up'}
					Join KINGDOM Quest and save the learning activities you create.
				{:else if mode === 'verify_email'}
					Enter the six-digit code we sent to <strong>{email}</strong>. It expires in 10 minutes.
				{:else if mode === 'forgot_password'}
					Enter your email and we’ll send a reset code if an email/password account exists.
				{:else if mode === 'reset_password'}
					Enter the code from your email and choose a new password.
				{:else}
					Sign in with email and password, or continue with Google.
				{/if}
			</p>
		</div>

		{#if isEmailMode}
			<div class="mode-switch" role="tablist" aria-label="Account access">
				<button
					type="button"
					role="tab"
					aria-selected={mode === 'sign_in'}
					class:active={mode === 'sign_in'}
					onclick={() => setMode('sign_in')}>Sign in</button
				>
				<button
					type="button"
					role="tab"
					aria-selected={mode === 'sign_up'}
					class:active={mode === 'sign_up'}
					onclick={() => setMode('sign_up')}>Create account</button
				>
			</div>
		{/if}

		{#if checkingSession}
			<p class="form-status" role="status">Checking your sign-in…</p>
		{:else}
			<form class="auth-form" onsubmit={handleSubmit}>
				{#if mode === 'sign_up'}
					<label>
						<span>Your name</span>
						<input
							bind:value={name}
							class="text-input"
							name="name"
							autocomplete="name"
							maxlength="160"
							required
						/>
					</label>
				{/if}

				{#if mode !== 'verify_email'}
					<label>
						<span>Email address</span>
						<input
							bind:value={email}
							class="text-input"
							type="email"
							name="email"
							autocomplete="email"
							maxlength="320"
							required
							disabled={mode === 'reset_password'}
						/>
					</label>
				{/if}

				{#if mode === 'verify_email' || mode === 'reset_password'}
					<label>
						<span>Email code</span>
						<input
							bind:value={code}
							class="text-input code-input"
							name="code"
							inputmode="numeric"
							autocomplete="one-time-code"
							pattern="[0-9]{6}"
							minlength="6"
							maxlength="6"
							required
						/>
					</label>
				{/if}

				{#if mode === 'sign_in' || mode === 'sign_up' || mode === 'reset_password'}
					<label>
						<span>{mode === 'reset_password' ? 'New password' : 'Password'}</span>
						<input
							bind:value={password}
							class="text-input"
							type="password"
							name="password"
							autocomplete={mode === 'sign_in' ? 'current-password' : 'new-password'}
							minlength="12"
							maxlength="72"
							required
						/>
						{#if mode !== 'sign_in'}
							<small>Use at least 12 characters; passwords are limited to 72 bytes.</small>
						{/if}
					</label>
				{/if}

				{#if mode === 'sign_up' || mode === 'reset_password'}
					<label>
						<span>Confirm password</span>
						<input
							bind:value={passwordConfirmation}
							class="text-input"
							type="password"
							name="password_confirmation"
							autocomplete="new-password"
							minlength="12"
							maxlength="72"
							required
						/>
					</label>
				{/if}

				{#if error}<p class="form-error" role="alert">{error}</p>{/if}
				{#if notice}<p class="form-notice" role="status">{notice}</p>{/if}

				<button class="button button-primary submit-button" type="submit" disabled={busy}>
					{#if busy}
						Please wait…
					{:else if mode === 'sign_in'}
						Sign in
					{:else if mode === 'sign_up'}
						Create account
					{:else if mode === 'verify_email'}
						Verify email
					{:else if mode === 'forgot_password'}
						Send reset code
					{:else}
						Update password
					{/if}
				</button>
			</form>

			{#if mode === 'sign_in'}
				<button class="text-action" type="button" onclick={() => setMode('forgot_password')}>
					Forgot your password?
				</button>
				<button class="text-action" type="button" onclick={handleResendCode} disabled={busy}>
					Need to verify your email?
				</button>
			{:else if mode === 'verify_email'}
				<button class="text-action" type="button" onclick={handleResendCode} disabled={busy}>
					Send another code
				</button>
			{:else if mode === 'reset_password'}
				<button class="text-action" type="button" onclick={() => setMode('forgot_password')}>
					Request a new reset code
				</button>
			{:else if mode === 'forgot_password'}
				<button class="text-action" type="button" onclick={() => setMode('sign_in')}>
					Return to sign in
				</button>
			{/if}

			<div class="divider"><span>or</span></div>

			<form class="google-form" action="/api/v1/auth/google_oauth2" method="post">
				<input type="hidden" name="authenticity_token" value={csrfToken} />
				<button
					class="button button-outline google-button"
					type="submit"
					disabled={!csrfToken || busy}
				>
					Continue with Google <span aria-hidden="true">↗</span>
				</button>
			</form>
		{/if}

		<p class="auth-footnote">
			By continuing, you agree to use KINGDOM Quest respectfully and keep your account secure.
		</p>
	</section>
</main>

<style>
	.auth-page {
		display: grid;
		min-height: min(48rem, calc(100vh - 5rem));
		place-items: center;
		padding-block: 3rem;
	}

	.auth-card {
		width: min(100%, 35rem);
		padding: clamp(1.5rem, 5vw, 3.25rem);
		border: 1px solid var(--line);
		border-radius: 1.4rem;
		background: var(--white);
		box-shadow: var(--shadow-card);
		animation: rise-in 420ms ease both;
	}

	.auth-heading {
		text-align: center;
	}

	.auth-heading .eyebrow {
		justify-content: center;
	}

	h1 {
		margin: 1rem 0 0.65rem;
		font-family: Manrope, 'DM Sans', sans-serif;
		font-size: clamp(1.8rem, 5vw, 2.4rem);
		font-weight: 800;
		letter-spacing: -0.065em;
		line-height: 1.12;
	}

	.auth-description {
		margin: 0 auto;
		color: var(--ink-soft);
		font-size: 0.96rem;
		line-height: 1.65;
	}

	.auth-description strong {
		color: var(--ink);
		overflow-wrap: anywhere;
	}

	.mode-switch {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 0.25rem;
		margin-top: 1.8rem;
		padding: 0.25rem;
		border-radius: 0.8rem;
		background: #f4f1eb;
	}

	.mode-switch button {
		min-height: 2.65rem;
		border: 0;
		border-radius: 0.6rem;
		background: transparent;
		color: var(--ink-soft);
		font: inherit;
		font-size: 0.86rem;
		font-weight: 700;
		cursor: pointer;
	}

	.mode-switch button.active {
		background: white;
		box-shadow: 0 1px 4px rgb(35 31 24 / 10%);
		color: var(--navy);
	}

	.auth-form {
		display: grid;
		gap: 1rem;
		margin-top: 1.6rem;
	}

	.auth-form label {
		display: grid;
		gap: 0.45rem;
		color: var(--ink);
		font-size: 0.82rem;
		font-weight: 700;
	}

	.auth-form .text-input {
		min-height: 3.1rem;
		padding: 0.75rem 0.85rem;
		font-size: 0.95rem;
	}

	.auth-form small {
		color: var(--ink-muted);
		font-size: 0.75rem;
		font-weight: 500;
	}

	.code-input {
		letter-spacing: 0.35em;
		text-align: center;
		font-size: 1.2rem !important;
		font-weight: 800 !important;
	}

	.submit-button,
	.google-button {
		width: 100%;
		min-height: 3.2rem;
	}

	.form-error,
	.form-notice,
	.form-status {
		margin: 0;
		padding: 0.8rem 0.9rem;
		border-radius: 0.7rem;
		font-size: 0.84rem;
		line-height: 1.5;
	}

	.form-error {
		border: 1px solid #f0cbc4;
		background: #fff4f1;
		color: #792b21;
	}

	.form-notice {
		border: 1px solid #cde6d9;
		background: #f1faf5;
		color: #24644b;
	}

	.form-status {
		margin-top: 1.5rem;
		background: #f7f5f0;
		color: var(--ink-soft);
		text-align: center;
	}

	.text-action {
		display: block;
		margin: 0.85rem auto 0;
		padding: 0.35rem;
		border: 0;
		background: transparent;
		color: var(--navy);
		font: inherit;
		font-size: 0.82rem;
		font-weight: 700;
		text-decoration: underline;
		text-underline-offset: 0.2em;
		cursor: pointer;
	}

	.text-action:disabled {
		cursor: wait;
		opacity: 0.6;
	}

	.divider {
		display: flex;
		align-items: center;
		gap: 0.8rem;
		margin: 1.3rem 0;
		color: var(--ink-muted);
		font-size: 0.76rem;
	}

	.divider::before,
	.divider::after {
		height: 1px;
		flex: 1;
		background: var(--line);
		content: '';
	}

	.google-form {
		margin: 0;
	}

	.auth-footnote {
		margin: 1.4rem 0 0;
		color: var(--ink-muted);
		font-size: 0.73rem;
		line-height: 1.55;
		text-align: center;
	}

	@keyframes rise-in {
		from {
			transform: translateY(10px);
			opacity: 0;
		}
		to {
			transform: translateY(0);
			opacity: 1;
		}
	}

	@media (prefers-reduced-motion: reduce) {
		.auth-card {
			animation: none;
		}
	}
</style>
