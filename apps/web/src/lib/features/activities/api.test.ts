import { afterEach, describe, expect, it, vi } from 'vitest';
import { answerPlayQuestion, fetchActivity, startPlaySession } from './api';

function jsonResponse(body: unknown, status = 200) {
	return new Response(JSON.stringify(body), {
		status,
		headers: { 'Content-Type': 'application/json' }
	});
}

afterEach(() => vi.unstubAllGlobals());

describe('learning journey API client', () => {
	it('normalizes and encodes a learner game code in requests', async () => {
		const fetchMock = vi.fn().mockResolvedValue(
			jsonResponse({
				data: {
					id: 'version-id',
					title: 'A quest',
					share_code: 'ABCD23',
					cover_image_url: null,
					questions: []
				}
			})
		);
		vi.stubGlobal('fetch', fetchMock);

		await fetchActivity('ABCD23');

		expect(fetchMock).toHaveBeenCalledWith(
			'/api/v1/play/ABCD23',
			expect.objectContaining({
				credentials: 'same-origin',
				headers: expect.any(Headers)
			})
		);
		expect((fetchMock.mock.calls[0][1] as RequestInit).headers).toHaveProperty('get');
	});

	it('starts a play session with the learner name and an idempotency key', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(jsonResponse({ data: { token: 'csrf-token' } }))
			.mockResolvedValueOnce(
				jsonResponse(
					{
						data: {
							id: 'session-id',
							question_index: 0,
							time_limit_seconds: 30,
							time_remaining_seconds: 30,
							question_started_at: '2026-10-16T12:00:00Z',
							server_time: '2026-10-16T12:00:00Z'
						}
					},
					201
				)
			);
		vi.stubGlobal('fetch', fetchMock);

		await startPlaySession({
			shareCode: 'ABCD23',
			learnerName: 'Jordan',
			idempotencyKey: '00000000-0000-4000-8000-000000000001'
		});

		expect(fetchMock).toHaveBeenNthCalledWith(
			1,
			'/api/v1/auth/csrf',
			expect.objectContaining({ credentials: 'same-origin' })
		);
		const [path, init] = fetchMock.mock.calls.at(-1) as [string, RequestInit];
		expect(path).toBe('/api/v1/play/ABCD23/sessions');
		expect(init.method).toBe('POST');
		expect(init.credentials).toBe('same-origin');
		expect(init.body).toBe(
			JSON.stringify({
				play_session: { learner_name: 'Jordan' }
			})
		);
		const headers = init.headers as Headers;
		expect(headers.get('Accept')).toBe('application/json');
		expect(headers.get('Content-Type')).toBe('application/json');
		expect(headers.get('Idempotency-Key')).toBe('00000000-0000-4000-8000-000000000001');
		expect(headers.get('X-CSRF-Token')).toBe('csrf-token');
	});

	it('posts the current answer with a retry key and supports unanswered timeout responses', async () => {
		const fetchMock = vi
			.fn()
			.mockResolvedValueOnce(jsonResponse({ data: { token: 'csrf-token' } }))
			.mockResolvedValueOnce(
				jsonResponse({
					data: {
						complete: false,
						is_correct: false,
						timed_out: true,
						question_index: 1,
						time_limit_seconds: 0,
						question_started_at: '2026-10-16T12:00:00Z',
						server_time: '2026-10-16T12:00:00Z'
					}
				})
			);
		vi.stubGlobal('fetch', fetchMock);

		await answerPlayQuestion({
			shareCode: 'ABCD23',
			sessionId: 'session-id',
			questionId: 'question-id',
			optionId: null,
			idempotencyKey: '00000000-0000-4000-8000-000000000002'
		});

		const [path, init] = fetchMock.mock.calls.at(-1) as [string, RequestInit];
		expect(path).toBe('/api/v1/play/ABCD23/sessions/session-id/answers');
		expect(init.method).toBe('POST');
		expect(init.body).toBe(
			JSON.stringify({ answer: { question_id: 'question-id', option_id: null } })
		);
		expect((init.headers as Headers).get('Idempotency-Key')).toBe(
			'00000000-0000-4000-8000-000000000002'
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
