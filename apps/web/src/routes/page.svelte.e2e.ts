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
	await page.getByRole('link', { name: /i have a game code/i }).click();
	await expect(page).toHaveURL(/\/join$/);
	await expect(page.locator('.route-loading')).toHaveCount(0);
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
	await expect(page.getByRole('link', { name: 'Edit quest', exact: true })).toHaveAttribute(
		'href',
		'/host/activities/quest-id?edit=true'
	);
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

test('opens published quest editing without play-mode setup and supports deleting and importing questions', async ({
	page
}) => {
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			json: {
				data: { id: 'educator-id', email: 'educator@example.test', name: 'Educator' }
			}
		})
	);
	await page.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await page.route('**/api/v1/activities/quest-id', (route) =>
		route.fulfill({
			json: {
				data: {
					id: 'quest-id',
					title: 'A published quest',
					description: '',
					status: 'published',
					question_count: 1,
					share_code: 'ABC123',
					version: 1,
					total_plays: 0,
					updated_at: '2026-10-16T12:00:00Z',
					published_at: '2026-10-16T12:00:00Z',
					shuffle_questions: false,
					speed_scoring: true,
					questions: [
						{
							id: '10101010-1010-4101-8101-101010101001',
							position: 1,
							question_type: 'single_choice',
							prompt: 'Original question',
							options: [
								{ id: '10101010-1010-4101-8101-101010101101', text: 'Original answer' },
								{ id: '10101010-1010-4101-8101-101010101102', text: 'Another answer' }
							],
							correct_option_id: '10101010-1010-4101-8101-101010101101',
							correct_option_ids: ['10101010-1010-4101-8101-101010101101'],
							points: 100,
							time_limit_seconds: 30
						}
					]
				}
			}
		})
	);
	await page.route('**/api/v1/activities/quest-id/revisions', async (route) => {
		const payload = route.request().postDataJSON() as {
			revision: { title: string; expected_version: number; questions: Array<{ prompt: string }> };
		};
		expect(payload.revision.title).toBe('Updated quest title');
		expect(payload.revision.expected_version).toBe(1);
		expect(payload.revision.questions).toHaveLength(1);
		expect(payload.revision.questions[0]?.prompt).toBe('Imported question');
		await route.fulfill({
			status: 201,
			json: {
				data: {
					activity_id: 'quest-id',
					title: 'Updated quest title',
					version: 2,
					share_code: 'NEW123',
					play_path: '/play/NEW123'
				}
			}
		});
	});

	await page.goto('/host/activities/quest-id?edit=true');
	await expect(page.getByRole('heading', { name: 'Edit your questions' })).toBeVisible();
	await expect(page.getByText('Participant-paced', { exact: true })).toHaveCount(0);
	await expect(page.getByText('Instructor-paced live', { exact: true })).toHaveCount(0);
	await expect(page.getByRole('link', { name: 'Download the CSV template' })).toBeVisible();
	await expect(
		page.getByRole('link', { name: 'Download NIA example questions (40)' })
	).toBeVisible();
	await page.getByRole('button', { name: 'Delete question 1' }).click();
	await expect(page.getByText('No questions yet')).toBeVisible();
	await page.getByLabel('Quest title').fill('Updated quest title');
	await page.getByRole('button', { name: '+ Add a question' }).click();
	await expect(page.getByLabel('Points')).toHaveValue('1');
	await expect(page.getByRole('textbox', { name: 'Answer choice 4' })).toBeVisible();
	await page.getByRole('button', { name: 'Delete question 1' }).click();
	await page.locator('#revision-question-import').setInputFiles({
		name: 'questions.csv',
		mimeType: 'text/csv',
		buffer: Buffer.from(
			'question,option_a,option_b,correct_answer,points,time_limit_seconds\n"Imported question","First answer","Second answer","A",100,30'
		)
	});
	await expect(page.locator('.prompt-input')).toHaveValue('Imported question');
	await page.getByRole('button', { name: 'Update quest' }).click();
	await expect(page).toHaveURL(/\/dashboard\/quests\/quest-id$/);
});

test('shows the created quest ID separately from its learner game code', async ({ page }) => {
	const questId = '0199d6a6-3eb2-7b6e-9d74-d4cb14be9812';
	await page.context().grantPermissions(['clipboard-read', 'clipboard-write']);
	await page.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			json: {
				data: { id: 'educator-id', email: 'educator@example.test', name: 'Educator' }
			}
		})
	);
	await page.route('**/api/v1/activities', async (route) => {
		expect(route.request().method()).toBe('POST');
		const payload = route.request().postDataJSON() as {
			activity: {
				title: string;
				questions: Array<{
					prompt: string;
					options: Array<{ id: string; text: string }>;
					correct_option_id: string;
				}>;
			};
		};
		expect(payload.activity.title).toBe('NIA 2026 Bible Trivia Review');
		expect(payload.activity.questions[0]?.prompt).toBe('When did NIA 2026 take place?');
		expect(payload.activity.questions[0]?.correct_option_id).toBe(
			payload.activity.questions[0]?.options[1]?.id
		);
		await route.fulfill({
			status: 201,
			json: { data: { id: questId, title: 'NIA 2026 Bible Trivia Review' } }
		});
	});
	await page.route(`**/api/v1/activities/${questId}/publications`, (route) =>
		route.fulfill({
			status: 201,
			json: {
				data: {
					activity_id: questId,
					title: 'NIA 2026 Bible Trivia Review',
					version: 1,
					share_code: 'VQFAXD',
					play_path: '/play/VQFAXD'
				}
			}
		})
	);

	await page.goto('/create');
	const downloadPromise = page.waitForEvent('download');
	await page.getByRole('link', { name: 'Download NIA 2026 questions (40)' }).click();
	expect((await downloadPromise).suggestedFilename()).toBe('questions.csv');
	await page
		.getByPlaceholder('e.g. The Great Solar System Sprint')
		.fill('NIA 2026 Bible Trivia Review');
	await page.locator('.prompt-input').fill('When did NIA 2026 take place?');
	await page.getByLabel('Answer choice 1').fill('Friday 3rd and Saturday 4th October');
	await page.getByLabel('Answer choice 2').fill('Tuesday 6th and Wednesday 7th October 2026');
	await page.getByLabel('Answer choice 3').fill('Monday 5th October only');
	await page.getByLabel('Answer choice 4').fill('Saturday 10th and Sunday 11th October');
	await page.getByLabel('Mark option 2 as correct').check();
	const invalidFields = await page.locator('form').evaluate((form: HTMLFormElement) =>
		Array.from(form.querySelectorAll<HTMLElement>(':invalid')).map((field) => ({
			label: field.getAttribute('aria-label') ?? field.id ?? field.getAttribute('placeholder'),
			type: (field as HTMLInputElement).type,
			value: (field as HTMLInputElement).value,
			message: (field as HTMLInputElement).validationMessage
		}))
	);
	expect(invalidFields).toEqual([]);
	const createRequest = page.waitForRequest(
		(request) => request.url().endsWith('/api/v1/activities') && request.method() === 'POST'
	);
	await page.getByRole('button', { name: 'Publish quest' }).click();
	await createRequest;

	await expect(page.getByRole('heading', { name: 'NIA 2026 Bible Trivia Review' })).toBeVisible();
	await expect(page.getByLabel('Game code')).toHaveText('VQFAXD');
	await expect(page.getByText(questId)).toBeVisible();
	await page.getByRole('button', { name: 'Copy direct join link' }).click();
	await expect(page.getByRole('button', { name: 'Join link copied!' })).toBeVisible();
	await expect(page.evaluate(() => navigator.clipboard.readText())).resolves.toBe(
		'http://127.0.0.1:5173/join?code=VQFAXD'
	);
	await page.getByRole('button', { name: 'Copy quest ID' }).click();
	await expect(page.getByRole('button', { name: 'Copied!' })).toBeVisible();
	await expect(page.evaluate(() => navigator.clipboard.readText())).resolves.toBe(questId);
});

test('opens session setup and creates a live lobby with a join QR code and participant roster', async ({
	page
}) => {
	let revisionCount = 0;
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
					questions: [
						{
							id: '10101010-1010-4101-8101-101010101001',
							position: 1,
							question_type: 'single_choice',
							prompt: 'Alpha question',
							options: [
								{ id: '10101010-1010-4101-8101-101010101101', text: 'Alpha answer' },
								{ id: '10101010-1010-4101-8101-101010101102', text: 'Beta answer' },
								{ id: '10101010-1010-4101-8101-101010101103', text: 'Gamma answer' }
							],
							correct_option_id: '10101010-1010-4101-8101-101010101101',
							correct_option_ids: ['10101010-1010-4101-8101-101010101101'],
							points: 100,
							time_limit_seconds: 30
						},
						{
							id: '10101010-1010-4101-8101-101010101002',
							position: 2,
							question_type: 'single_choice',
							prompt: 'Bravo question',
							options: [
								{ id: '10101010-1010-4101-8101-101010101201', text: 'First choice' },
								{ id: '10101010-1010-4101-8101-101010101202', text: 'Second choice' },
								{ id: '10101010-1010-4101-8101-101010101203', text: 'Third choice' }
							],
							correct_option_id: '10101010-1010-4101-8101-101010101201',
							correct_option_ids: ['10101010-1010-4101-8101-101010101201'],
							points: 100,
							time_limit_seconds: 30
						}
					]
				}
			}
		})
	);
	await page.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await page.route('**/api/v1/activities/quest-id/revisions', async (route) => {
		const payload = route.request().postDataJSON() as {
			revision: {
				expected_version: number;
				questions: Array<{
					id: string;
					prompt: string;
					correct_option_id: string;
					time_limit_seconds: number;
				}>;
			};
		};
		expect(payload.revision.expected_version).toBe(revisionCount + 1);
		if (revisionCount === 0) {
			expect(payload.revision.questions.map((question) => question.prompt)).toEqual([
				'Updated Bravo question',
				'Alpha question'
			]);
			expect(payload.revision.questions[0]?.correct_option_id).toBe(
				'10101010-1010-4101-8101-101010101202'
			);
			expect(payload.revision.questions.map((question) => question.time_limit_seconds)).toEqual([
				60, 45
			]);
		} else {
			expect(payload.revision.questions[1]?.prompt).toBe('Auto-saved before launch');
		}
		revisionCount += 1;
		await route.fulfill({
			status: 201,
			json: {
				data: {
					activity_id: 'quest-id',
					title: 'A live-ready quest',
					version: revisionCount + 1,
					share_code: revisionCount === 1 ? 'NEWA23' : 'NEXT23',
					play_path: revisionCount === 1 ? '/play/NEWA23' : '/play/NEXT23'
				}
			}
		});
	});
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
		page.getByRole('heading', { name: 'Review and refine your questions' })
	).toBeVisible();
	await expect(page.locator('.prompt-input')).toHaveCount(2);
	await page.getByLabel('Time limit for every question in seconds').fill('45');
	await page.getByRole('button', { name: 'Update all' }).click();
	await expect(page.getByLabel('Time limit (seconds)').nth(1)).toHaveValue('45');
	await page.getByRole('button', { name: 'Move question 2 up' }).click();
	await page.locator('.prompt-input').first().fill('Updated Bravo question');
	await page.getByLabel('Time limit (seconds)').first().fill('60');
	await page.getByLabel('Mark option 2 as correct').first().check();
	await page.getByRole('button', { name: 'Update quest' }).click();
	await expect(page.getByRole('status')).toContainText(/Version 2 saved/);
	expect(revisionCount).toBe(1);
	await page.locator('.prompt-input').nth(1).fill('Auto-saved before launch');
	await page.getByRole('button', { name: 'Continue' }).click();
	await expect(
		page.getByRole('heading', { name: 'Ready to bring everyone together?' })
	).toBeVisible();
	await page.getByRole('button', { name: 'Start now' }).click();
	await expect.poll(() => revisionCount).toBe(2);

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
	await page.route('**/api/v1/me', (route) =>
		route.fulfill({
			status: 401,
			json: { error: { code: 'authentication_required', message: 'Sign in to continue.' } }
		})
	);
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

test('adds a guest to the host roster as soon as they join the live room', async ({
	context,
	page
}) => {
	const participants: Array<{ learner_name: string; completed: boolean; answered: boolean }> = [];
	let sessionStarted = false;
	const room = () => {
		const activeQuestion = sessionStarted
			? {
					id: 'question-id',
					prompt: 'First live question',
					question_type: 'single_choice' as const,
					points: 100,
					speed_scoring: true,
					time_limit_seconds: 30,
					options: [
						{ id: 'option-a', text: 'Answer A' },
						{ id: 'option-b', text: 'Answer B' }
					]
				}
			: null;
		return {
			room_code: 'KQST23',
			title: 'Live roster test',
			status: sessionStarted ? ('active' as const) : ('waiting' as const),
			question_index: 0,
			question_count: 1,
			current_question: activeQuestion,
			question_started_at: sessionStarted ? '2026-10-16T12:00:00Z' : null,
			time_remaining_seconds: sessionStarted ? 30 : 0,
			server_time: '2026-10-16T12:00:00Z',
			participant_count: participants.length,
			answered_count: 0,
			participants: [...participants],
			participant: null,
			standings: [],
			podium: [],
			standings_final: false
		};
	};

	await context.route('**/api/v1/me', (route) =>
		route.fulfill({
			json: {
				data: { id: 'educator-id', email: 'educator@example.test', name: 'Educator' }
			}
		})
	);
	await context.route('**/api/v1/auth/csrf', (route) =>
		route.fulfill({ json: { data: { token: 'test-csrf-token' } } })
	);
	await context.route('**/api/v1/join/KQST23', (route) =>
		route.fulfill({ json: { data: { kind: 'live_room', path: '/room/KQST23' } } })
	);
	await context.route(/\/api\/v1\/game_rooms\/KQST23(?:\?.*)?$/, (route) =>
		route.fulfill({ json: { data: room() } })
	);
	await context.route('**/api/v1/game_rooms/KQST23/start', async (route) => {
		sessionStarted = true;
		await route.fulfill({ json: { data: room() } });
	});
	await context.route('**/api/v1/game_rooms/KQST23/participants', async (route) => {
		const body = route.request().postDataJSON() as { participant: { learner_name: string } };
		const participant = {
			learner_name: body.participant.learner_name,
			completed: false,
			answered: false
		};
		participants.push(participant);
		await route.fulfill({
			status: 201,
			json: {
				data: {
					session_id: 'participant-session-id',
					learner_name: participant.learner_name,
					room: {
						...room(),
						participant: { learner_name: participant.learner_name, answered: false }
					}
				}
			}
		});
	});

	await page.goto('/host/room/KQST23');
	await expect(page.getByText('No one has joined yet')).toBeVisible();

	const learnerPage = await context.newPage();
	await learnerPage.goto('/join?code=KQST23');
	await expect(learnerPage.getByLabel('Your display name')).toBeVisible();
	await learnerPage.getByLabel('Your display name').fill('Maya');
	await learnerPage.getByRole('button', { name: 'Join as a guest' }).click();
	await expect(learnerPage.getByText('Waiting room')).toBeVisible();
	await expect(page.getByText('Maya')).toBeVisible({ timeout: 5000 });
	await page.getByRole('button', { name: 'Start now' }).click();
	await expect(page.getByRole('heading', { name: 'First live question' })).toBeVisible();
	await expect(page.getByText('0 / 1 answered')).toBeVisible();
});
