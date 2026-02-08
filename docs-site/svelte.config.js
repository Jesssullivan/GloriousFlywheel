import adapter from '@sveltejs/adapter-static';
import { vitePreprocess } from '@sveltejs/vite-plugin-svelte';
import { mdsvex } from 'mdsvex';
import mdsvexConfig from './mdsvex.config.js';

/** @type {import('@sveltejs/kit').Config} */
const config = {
	preprocess: [
		mdsvex(mdsvexConfig),
		vitePreprocess()
	],

	extensions: ['.svelte', '.svelte.md', '.md', '.svx'],

	kit: {
		adapter: adapter({
			pages: 'build',
			assets: 'build',
			fallback: '404.html',
			precompress: false,
			strict: false
		}),
		paths: {
			base: process.env.DOCS_BASE_PATH || ''
		},
		prerender: {
			handleHttpError: 'warn',
			handleMissingId: 'warn'
		}
	},

	vitePlugin: {
		dynamicCompileOptions({ filename }) {
			if (filename.endsWith('.md') || filename.endsWith('.svx')) {
				return { runes: undefined };
			}
			return { runes: true };
		}
	}
};

export default config;
