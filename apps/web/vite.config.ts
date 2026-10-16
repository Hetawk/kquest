import { defineConfig } from 'vitest/config';
import adapter from '@sveltejs/adapter-node';
import { sveltekit } from '@sveltejs/kit/vite';

const apiTarget = process.env.KQUEST_API_URL ?? 'http://127.0.0.1:3000';
const apiProxy = {
	'/api': {
		target: apiTarget,
		changeOrigin: true
	}
};

export default defineConfig({
	// Keep API requests same-origin in the browser; Rails remains the system of record.
	server: { proxy: apiProxy },
	preview: { proxy: apiProxy },
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			adapter: adapter()
		})
	],
	test: {
		expect: { requireAssertions: true },
		projects: [
			{
				extends: './vite.config.ts',
				test: {
					name: 'server',
					environment: 'node',
					include: ['src/**/*.{test,spec}.{js,ts}'],
					exclude: ['src/**/*.svelte.{test,spec}.{js,ts}']
				}
			}
		]
	}
});
