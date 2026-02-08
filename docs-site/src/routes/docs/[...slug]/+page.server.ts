import { getDocPage, getNavigation } from '$lib/server/docs';
import { compile } from 'mdsvex';
import mdsvexConfig from '../../../../mdsvex.config.js';

export const prerender = true;

interface NavItem {
	slug: string;
	children?: NavItem[];
}

function collectLeafSlugs(items: NavItem[]): string[] {
	const slugs: string[] = [];
	for (const item of items) {
		if (item.children && item.children.length > 0) {
			slugs.push(...collectLeafSlugs(item.children));
		} else {
			slugs.push(item.slug);
		}
	}
	return slugs;
}

export async function entries() {
	const nav = await getNavigation();
	const slugs = collectLeafSlugs(nav);
	return slugs.map((slug) => ({ slug }));
}

export async function load({ params }) {
	const slug = params.slug;
	const page = await getDocPage(slug);

	if (!page) {
		return {
			title: 'Not Found',
			slug,
			html: '',
			error: true
		};
	}

	const compiled = await compile(page.content, {
		...mdsvexConfig,
		layout: undefined
	});

	return {
		title: page.title,
		slug,
		html: compiled?.code || page.content,
		error: false
	};
}
