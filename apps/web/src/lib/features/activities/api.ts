import type {
	PlayActivity,
	PlayLeaderboard,
	ResolvedJoinCode,
	GameRoom,
	JoinedGameRoom,
	PlaySession,
	PlaySessionProgress,
	PublishedActivity,
	QuestionDraft
} from './types';

type ApiEnvelope<T> = { data: T };
type ApiErrorEnvelope = { error?: { message?: string } };
type UserProfile = { id: string; email: string; name: string };
type UploadedCover = {
	id: string;
	public_url: string;
	content_type: string;
	file_size: number;
};

export class ApiRequestError extends Error {
	constructor(
		message: string,
		readonly status: number
	) {
		super(message);
		this.name = 'ApiRequestError';
	}
}

let csrfToken: string | null = null;
let csrfTokenRequest: Promise<string> | null = null;

export async function getCsrfToken(): Promise<string> {
	if (csrfToken) return csrfToken;
	if (!csrfTokenRequest) {
		csrfTokenRequest = fetch('/api/v1/auth/csrf', {
			headers: { Accept: 'application/json' },
			credentials: 'same-origin'
		})
			.then(async (response) => {
				const payload = (await response.json()) as ApiEnvelope<{ token: string }>;
				if (!response.ok || !payload.data?.token) {
					throw new ApiRequestError('Could not prepare a secure sign-in request.', response.status);
				}
				csrfToken = payload.data.token;
				return csrfToken;
			})
			.finally(() => {
				csrfTokenRequest = null;
			});
	}
	return csrfTokenRequest;
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
	let response: Response;
	const method = init?.method?.toUpperCase() ?? 'GET';
	const headers = new Headers(init?.headers);

	try {
		if (!['GET', 'HEAD', 'OPTIONS'].includes(method)) {
			headers.set('X-CSRF-Token', await getCsrfToken());
		}
		headers.set('Accept', 'application/json');
		if (init?.body && !(init.body instanceof FormData)) {
			headers.set('Content-Type', 'application/json');
		}

		response = await fetch(path, {
			...init,
			credentials: 'same-origin',
			headers
		});
	} catch (cause) {
		if (cause instanceof ApiRequestError) throw cause;
		throw new Error(
			'Could not reach the KINGDOM Quest API. Check that the API server is running.',
			{
				cause
			}
		);
	}

	if (response.status === 204) return undefined as T;

	const payload = (await response.json().catch(() => null)) as
		ApiEnvelope<T> | ApiErrorEnvelope | null;

	if (!response.ok) {
		const apiMessage = payload && 'error' in payload ? payload.error?.message : undefined;
		throw new ApiRequestError(
			apiMessage ?? `The request could not be completed (${response.status}).`,
			response.status
		);
	}

	if (!payload || !('data' in payload)) {
		throw new Error('The server returned an unexpected response.');
	}

	return payload.data;
}

export async function getCurrentUser(): Promise<UserProfile | null> {
	try {
		return await request<UserProfile>('/api/v1/me');
	} catch (error) {
		if (error instanceof ApiRequestError && error.status === 401) return null;
		throw error;
	}
}

export function signOut() {
	csrfToken = null;
	return request<void>('/api/v1/auth/session', { method: 'DELETE' });
}

export function uploadCoverImage(file: File) {
	const body = new FormData();
	body.append('file', file);
	return request<UploadedCover>('/api/v1/assets/upload', { method: 'POST', body });
}

export function createActivity(input: {
	title: string;
	description: string;
	questions: QuestionDraft[];
	cover_image_asset_id?: string;
	shuffle_questions: boolean;
	speed_scoring: boolean;
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

export function fetchLeaderboard(shareCode: string) {
	return request<PlayLeaderboard>(`/api/v1/play/${encodeURIComponent(shareCode)}/leaderboard`);
}

export function resolveJoinCode(code: string) {
	return request<ResolvedJoinCode>(`/api/v1/join/${encodeURIComponent(code)}`);
}

export function createGameRoom(activityId: string) {
	return request<GameRoom>(`/api/v1/activities/${encodeURIComponent(activityId)}/game_rooms`, {
		method: 'POST',
		body: JSON.stringify({})
	});
}

export function fetchGameRoom(roomCode: string, sessionId?: string) {
	const query = sessionId ? `?session_id=${encodeURIComponent(sessionId)}` : '';
	return request<GameRoom>(`/api/v1/game_rooms/${encodeURIComponent(roomCode)}${query}`);
}

export function joinGameRoom(input: {
	roomCode: string;
	learnerName: string;
	idempotencyKey: string;
}) {
	return request<JoinedGameRoom>(
		`/api/v1/game_rooms/${encodeURIComponent(input.roomCode)}/participants`,
		{
			method: 'POST',
			headers: { 'Idempotency-Key': input.idempotencyKey },
			body: JSON.stringify({ participant: { learner_name: input.learnerName } })
		}
	);
}

export function renameGameRoomParticipant(input: {
	roomCode: string;
	sessionId: string;
	learnerName: string;
}) {
	return request<{ learner_name: string }>(
		`/api/v1/game_rooms/${encodeURIComponent(input.roomCode)}/participants/${encodeURIComponent(input.sessionId)}`,
		{
			method: 'PATCH',
			body: JSON.stringify({ participant: { learner_name: input.learnerName } })
		}
	);
}

export function startGameRoom(roomCode: string) {
	return request<GameRoom>(`/api/v1/game_rooms/${encodeURIComponent(roomCode)}/start`, {
		method: 'POST',
		body: JSON.stringify({})
	});
}

export function advanceGameRoom(roomCode: string) {
	return request<GameRoom>(`/api/v1/game_rooms/${encodeURIComponent(roomCode)}/advance`, {
		method: 'POST',
		body: JSON.stringify({})
	});
}

export function answerGameRoomQuestion(input: {
	roomCode: string;
	sessionId: string;
	questionId: string;
	optionId: string | null;
	idempotencyKey: string;
}) {
	return request<{
		complete: false;
		is_correct: boolean;
		timed_out: boolean;
		points_awarded: number;
		speed_bonus: number;
		question_index: number;
	}>(
		`/api/v1/game_rooms/${encodeURIComponent(input.roomCode)}/participants/${encodeURIComponent(input.sessionId)}/answers`,
		{
			method: 'POST',
			headers: { 'Idempotency-Key': input.idempotencyKey },
			body: JSON.stringify({ answer: { question_id: input.questionId, option_id: input.optionId } })
		}
	);
}

export function renamePlaySession(input: {
	shareCode: string;
	sessionId: string;
	learnerName: string;
}) {
	return request<{ learner_name: string }>(
		`/api/v1/play/${encodeURIComponent(input.shareCode)}/sessions/${encodeURIComponent(input.sessionId)}`,
		{
			method: 'PATCH',
			body: JSON.stringify({ play_session: { learner_name: input.learnerName } })
		}
	);
}

export function startPlaySession(input: {
	shareCode: string;
	learnerName: string;
	idempotencyKey: string;
}) {
	return request<PlaySession>(`/api/v1/play/${encodeURIComponent(input.shareCode)}/sessions`, {
		method: 'POST',
		headers: { 'Idempotency-Key': input.idempotencyKey },
		body: JSON.stringify({
			play_session: { learner_name: input.learnerName }
		})
	});
}

export function answerPlayQuestion(input: {
	shareCode: string;
	sessionId: string;
	questionId: string;
	optionId: string | null;
	idempotencyKey: string;
}) {
	return request<PlaySessionProgress>(
		`/api/v1/play/${encodeURIComponent(input.shareCode)}/sessions/${encodeURIComponent(input.sessionId)}/answers`,
		{
			method: 'POST',
			headers: { 'Idempotency-Key': input.idempotencyKey },
			body: JSON.stringify({
				answer: { question_id: input.questionId, option_id: input.optionId }
			})
		}
	);
}
