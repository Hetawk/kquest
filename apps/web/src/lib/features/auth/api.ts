import { request } from '#lib/features/activities/api.js';

export type AuthUser = { id: string; email: string; name: string };

export function registerWithEmail(input: {
	email: string;
	name: string;
	password: string;
	password_confirmation: string;
}) {
	return request<{ verification_required: boolean; email: string }>('/api/v1/auth/email/register', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}

export function signInWithEmail(input: { email: string; password: string }) {
	return request<AuthUser>('/api/v1/auth/email/login', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}

export function verifyEmailAddress(input: { email: string; code: string }) {
	return request<AuthUser>('/api/v1/auth/email/verify', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}

export function resendEmailVerification(input: { email: string }) {
	return request<{ message: string }>('/api/v1/auth/email/resend-verification', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}

export function requestPasswordReset(input: { email: string }) {
	return request<{ message: string }>('/api/v1/auth/password/forgot', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}

export function resetPassword(input: {
	email: string;
	code: string;
	password: string;
	password_confirmation: string;
}) {
	return request<AuthUser>('/api/v1/auth/password/reset', {
		method: 'POST',
		body: JSON.stringify(input)
	});
}
