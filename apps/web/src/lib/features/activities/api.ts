import type { AttemptResult, PlayActivity, PublishedActivity, QuestionDraft } from './types';

type ApiEnvelope<T> = { data: T };
type ApiErrorEnvelope = { error?: { message?: string } };

async function request<T>(path: string, init?: RequestInit): Promise<T> {
	let response: Response;

	try {
		response = await fetch(path, {
			...init,
			headers: {
				Accept: 'application/json',
				...(init?.body ? { 'Content-Type': 'application/json' } : {}),
				...init?.headers
			}
		});
	} catch {
		throw new Error('Could not reach the KINGDOM Quest API. Check that the API server is running.');
	}

	const payload = (await response.json().catch(() => null)) as
		ApiEnvelope<T> | ApiErrorEnvelope | null;

	if (!response.ok) {
		throw new Error(
			(payload && 'error' in payload && payload.error?.message) ||
				`The request could not be completed (${response.status}).`
		);
	}

	if (!payload || !('data' in payload)) {
		throw new Error('The server returned an unexpected response.');
	}

	return payload.data;
}

export function createActivity(input: {
	title: string;
	description: string;
	questions: QuestionDraft[];
}) {
	return request<{ id: string; title: string }>('/api/v1/activities', {
		method: 'POST',
		body: JSON.stringify({ activity: input })
	});
}

export function publishActivity(activityId: string) {
	return request<PublishedActivity>(`/api/v1/activities/${activityId}/publications`, {
		method: 'POST',
		body: JSON.stringify({})
	});
}

export function fetchActivity(shareCode: string) {
	return request<PlayActivity>(`/api/v1/play/${encodeURIComponent(shareCode)}`);
}

export function submitAttempt(input: {
	shareCode: string;
	learnerName: string;
	responses: { question_id: string; option_id: string }[];
	idempotencyKey: string;
}) {
	return request<AttemptResult>(`/api/v1/play/${encodeURIComponent(input.shareCode)}/attempts`, {
		method: 'POST',
		headers: { 'Idempotency-Key': input.idempotencyKey },
		body: JSON.stringify({
			attempt: { learner_name: input.learnerName, responses: input.responses }
		})
	});
}
