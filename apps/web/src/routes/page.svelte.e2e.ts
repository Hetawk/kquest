import { expect, test } from '@playwright/test';

test('has expected h1', async ({ page }) => {
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			status: 401,
			json: { error: { code: 'authentication_required', message: 'Sign in to continue.' } }
		})
	);
	await page.goto('/');
	await expect(
		page.getByRole('heading', { level: 1, name: /make learning feel like an adventure/i })
	).toBeVisible();
	await expect(page.getByRole('link', { name: /create your first quest/i })).toBeVisible();
	await expect(page.getByRole('link', { name: /i have a game code/i })).toHaveAttribute(
		'href',
		'/join'
	);
});

test('helps learners recover from an incomplete game code', async ({ page }) => {
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			json: {
				data: { id: 'educator-id', email: 'educator@example.test', name: 'Educator' }
			}
		})
	);
	await page.goto('/join');
	await expect(page.getByRole('button', { name: 'Sign out' })).toBeVisible();
	await page.getByLabel(/6-character game code/i).fill('ABCDE');
	await page.getByRole('button', { name: /find my game/i }).click();
	await expect(page.locator('.join-form [role="alert"]')).toContainText(/6 letters or numbers/i);
	await expect(page).toHaveURL(/\/join$/);
});

test('opens the verification-code form when an unverified account signs in', async ({ page }) => {
	await page.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			status: 401,
			json: { error: { code: 'authentication_required', message: 'Sign in to continue.' } }
		})
	);
	await page.route('**/api/v1/auth/email/login', (route) =>
		route.fulfill({
			status: 403,
			json: {
				error: {
					code: 'email_unverified',
					message: 'Verify your email address before signing in.'
				}
			}
		})
	);
	await page.route('**/api/v1/auth/email/resend-verification', (route) =>
		route.fulfill({
			json: { data: { message: 'If the address needs verification, a code is on its way.' } }
		})
	);

	await page.goto('/auth');
	await page.getByLabel('Email address').fill('educator@example.test');
	await page.getByLabel('Password', { exact: true }).fill('a-secure-password');
	await page.getByRole('button', { name: 'Sign in', exact: true }).click();

	await expect(page.getByRole('heading', { name: 'Check your email.' })).toBeVisible();
	await expect(page.getByLabel('Email code')).toBeVisible();
	await expect(page.getByText(/code is on its way/i)).toBeVisible();
	await expect(page.getByRole('button', { name: 'Verify email' })).toBeVisible();
});

test('lets a signed-out user request a code and enter it explicitly', async ({ page }) => {
	await page.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			status: 401,
			json: { error: { code: 'authentication_required', message: 'Sign in to continue.' } }
		})
	);
	await page.route('**/api/v1/auth/email/resend-verification', (route) =>
		route.fulfill({
			json: { data: { message: 'If the address needs verification, a code is on its way.' } }
		})
	);

	await page.goto('/auth');
	await page.getByRole('button', { name: 'Need to verify your email?' }).click();
	await page.getByLabel('Email address').fill('educator@example.test');
	await page.getByRole('button', { name: 'Send verification code' }).click();

	await expect(page.getByLabel('Email code')).toBeVisible();
	await expect(page.getByRole('button', { name: 'Verify email' })).toBeVisible();
});

test('supports accessible manual question reordering', async ({ page }) => {
	await page.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			json: { data: { id: 'educator-id', email: 'educator@example.test', name: 'Educator' } }
		})
	);

	await page.goto('/create');
	await page.getByPlaceholder('e.g. The Great Solar System Sprint').fill('A reordered quest');
	await page.locator('.prompt-input').first().fill('First question');
	await page.getByRole('button', { name: /add a question/i }).click();
	await page.locator('.prompt-input').first().fill('Second question');
	await page.getByRole('button', { name: 'Move question 2 up' }).click();

	await expect(page.locator('.prompt-input').nth(0)).toHaveValue('Second question');
	await expect(page.getByRole('button', { name: /01.*Second question/ })).toBeVisible();
	await page.getByRole('button', { name: /First question/ }).click();
	await expect(page.locator('.prompt-input').first()).toHaveValue('First question');
	await page.getByLabel('Question type').selectOption('multiple_select');
	await page.getByLabel('Mark option 2 as correct').check();
	await expect(page.getByLabel('Mark option 2 as correct')).toBeChecked();
});

test('opens an owner quest workspace with question answers and overview tabs', async ({ page }) => {
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			json: {
				data: { id: 'educator-id', email: 'educator@example.test', name: 'Educator' }
			}
		})
	);
	await page.route('**/api/v1/activities/quest-id', (route) =>
		route.fulfill({
			json: {
				data: {
					id: 'quest-id',
					title: 'A published quest',
					description: 'A focused practice set.',
					status: 'published',
					question_count: 1,
					share_code: 'ABC123',
					version: 1,
					total_plays: 4,
					updated_at: '2026-10-16T12:00:00Z',
					published_at: '2026-10-16T12:00:00Z',
					shuffle_questions: false,
					speed_scoring: true,
					questions: [
						{
							id: 'question-id',
							position: 1,
							question_type: 'multiple_select',
							prompt: 'Select both correct answers.',
							options: [
								{ id: 'option-a', text: 'First correct answer' },
								{ id: 'option-b', text: 'Not correct' },
								{ id: 'option-c', text: 'Second correct answer' }
							],
							correct_option_id: 'option-a',
							correct_option_ids: ['option-a', 'option-c'],
							points: 100,
							time_limit_seconds: 30
						}
					]
				}
			}
		})
	);

	await page.goto('/dashboard/quests/quest-id');
	await expect(page.getByRole('heading', { name: 'A published quest' })).toBeVisible();
	await expect(page.getByText('First correct answer')).toBeVisible();
	await expect(page.getByText('Multiple select')).toBeVisible();
	await expect(page.getByText('Correct answer').first()).toBeVisible();
	await page.getByRole('tab', { name: 'Overview' }).click();
	await expect(page.getByText('Educator order')).toBeVisible();
	await page.getByRole('button', { name: 'Copy and edit' }).click();
	await expect(page).toHaveURL(/\/create\?copy=quest-id$/);
	await expect(page.getByPlaceholder('e.g. The Great Solar System Sprint')).toHaveValue(
		'Copy of A published quest'
	);
	await expect(page.locator('.prompt-input')).toHaveValue('Select both correct answers.');
});

test('opens session setup and creates a live lobby with a join QR code and participant roster', async ({
	page
}) => {
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			json: {
				data: { id: 'educator-id', email: 'educator@example.test', name: 'Educator' }
			}
		})
	);
	await page.route('**/api/v1/activities/quest-id', (route) =>
		route.fulfill({
			json: {
				data: {
					id: 'quest-id',
					title: 'A live-ready quest',
					description: '',
					status: 'published',
					question_count: 1,
					share_code: 'ABCD23',
					version: 1,
					total_plays: 0,
					updated_at: '2026-10-16T12:00:00Z',
					published_at: '2026-10-16T12:00:00Z',
					shuffle_questions: false,
					speed_scoring: true,
					questions: [{ time_limit_seconds: 30 }]
				}
			}
		})
	);
	await page.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await page.route('**/api/v1/activities/quest-id/game_rooms', (route) =>
		route.fulfill({
			status: 201,
			json: {
				data: {
					room_code: 'KQST23',
					title: 'A live-ready quest',
					status: 'waiting',
					question_index: 0,
					question_count: 1,
					current_question: null,
					question_started_at: null,
					time_remaining_seconds: 0,
					server_time: '2026-10-16T12:00:00Z',
					participant_count: 2,
					answered_count: 0,
					participants: [
						{ learner_name: 'Ada', completed: false, answered: false },
						{ learner_name: 'Grace', completed: false, answered: false }
					],
					participant: null,
					standings: [],
					podium: [],
					standings_final: false
				}
			}
		})
	);
	await page.route('**/api/v1/game_rooms/KQST23', (route) =>
		route.fulfill({
			json: {
				data: {
					room_code: 'KQST23',
					title: 'A live-ready quest',
					status: 'waiting',
					question_index: 0,
					question_count: 1,
					current_question: null,
					question_started_at: null,
					time_remaining_seconds: 0,
					server_time: '2026-10-16T12:00:00Z',
					participant_count: 2,
					answered_count: 0,
					participants: [
						{ learner_name: 'Ada', completed: false, answered: false },
						{ learner_name: 'Grace', completed: false, answered: false }
					],
					participant: null,
					standings: [],
					podium: [],
					standings_final: false
				}
			}
		})
	);

	await page.goto('/host/activities/quest-id');
	await expect(page.getByRole('heading', { name: 'How should the group play?' })).toBeVisible();
	await expect(page.getByText('Instructor-paced live', { exact: true })).toBeVisible();
	await page.getByRole('button', { name: 'Continue' }).click();
	await expect(
		page.getByRole('heading', { name: 'Ready to bring everyone together?' })
	).toBeVisible();
	await page.getByRole('button', { name: 'Start now' }).click();

	await expect(page.getByRole('heading', { name: 'A live-ready quest' })).toBeVisible();
	await expect(page.getByText('KQST23', { exact: true })).toBeVisible();
	await expect(page.getByRole('img', { name: 'QR code to join game KQST23' })).toBeVisible();
	await expect(page.getByRole('link', { name: /\/join\?code=KQST23/ })).toHaveAttribute(
		'href',
		/\/join\?code=KQST23/
	);
	await expect(page.getByText('Ada')).toBeVisible();
	await expect(page.getByText('Grace')).toBeVisible();
	await expect(page.getByText('✦').first()).toBeVisible();
});

test('resolves a QR invite from the stable join URL to the room display-name form', async ({
	page
}) => {
	await page.route('**/api/v1/join/KQST23', (route) =>
		route.fulfill({ json: { data: { kind: 'live_room', path: '/room/KQST23' } } })
	);
	await page.route('**/api/v1/game_rooms/KQST23', (route) =>
		route.fulfill({
			json: {
				data: {
					room_code: 'KQST23',
					title: 'Phone join test',
					status: 'waiting',
					question_index: 0,
					question_count: 1,
					current_question: null,
					question_started_at: null,
					time_remaining_seconds: 0,
					server_time: '2026-10-16T12:00:00Z',
					participant_count: 0,
					answered_count: 0,
					participants: [],
					participant: null,
					standings: [],
					podium: [],
					standings_final: false
				}
			}
		})
	);

	await page.goto('/join?code=KQST23');
	await expect(page).toHaveURL(/\/room\/KQST23$/);
	await expect(page.getByRole('heading', { name: 'Phone join test' })).toBeVisible();
	await expect(page.getByLabel('Your display name')).toBeVisible();
});
