import { afterEach, describe, expect, it, vi } from 'vitest';
import { fetchActivity, submitAttempt } from './api';

afterEach(() => vi.unstubAllGlobals());

describe('learning journey API client', () => {
	it('normalizes and encodes a learner game code in requests', async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			new Response(
				JSON.stringify({
					data: {
						id: 'version-id',
						title: 'A quest',
						share_code: 'ABCD23456789',
						questions: []
					}
				}),
				{ status: 200, headers: { 'Content-Type': 'application/json' } }
			)
		);
		vi.stubGlobal('fetch', fetchMock);

		await fetchActivity('ABCD23456789');

		expect(fetchMock).toHaveBeenCalledWith(
			'/api/v1/play/ABCD23456789',
			expect.objectContaining({
				headers: { Accept: 'application/json' }
			})
		);
	});

	it('sends answers and an idempotency key for retry-safe submissions', async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			new Response(JSON.stringify({ data: { id: 'attempt-id' } }), {
				status: 201,
				headers: { 'Content-Type': 'application/json' }
			})
		);
		vi.stubGlobal('fetch', fetchMock);

		await submitAttempt({
			shareCode: 'ABCD23456789',
			learnerName: 'Jordan',
			responses: [{ question_id: 'question-id', option_id: 'option-id' }],
			idempotencyKey: '00000000-0000-4000-8000-000000000001'
		});

		expect(fetchMock).toHaveBeenCalledWith(
			'/api/v1/play/ABCD23456789/attempts',
			expect.objectContaining({
				method: 'POST',
				headers: {
					Accept: 'application/json',
					'Content-Type': 'application/json',
					'Idempotency-Key': '00000000-0000-4000-8000-000000000001'
				},
				body: JSON.stringify({
					attempt: {
						learner_name: 'Jordan',
						responses: [{ question_id: 'question-id', option_id: 'option-id' }]
					}
				})
			})
		);
	});

	it('surfaces structured API errors for the learner', async () => {
		vi.stubGlobal(
			'fetch',
			vi.fn().mockResolvedValue(
				new Response(JSON.stringify({ error: { message: 'That game code has expired.' } }), {
					status: 404,
					headers: { 'Content-Type': 'application/json' }
				})
			)
		);

		await expect(fetchActivity('AAAAAAAAAAAA')).rejects.toThrow('That game code has expired.');
	});
});
