import { readdir, readFile, stat } from 'fs/promises';
import { join, relative, basename, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const DOCS_DIR = join(__dirname, '..', '..', '..', '..', '..', 'docs');

export interface NavItem {
	title: string;
	slug: string;
	order: number;
	children?: NavItem[];
}

export interface DocPage {
	content: string;
	slug: string;
	title: string;
}

function slugFromPath(filePath: string, base: string): string {
	const rel = relative(base, filePath);
	return rel
		.replace(/\.md$/, '')
		.replace(/\/index$/, '')
		.replace(/\/README$/i, '');
}

function titleFromFilename(filename: string): string {
	return basename(filename, '.md')
		.replace(/^README$/i, 'Overview')
		.replace(/^index$/, 'Overview')
		.replace(/-/g, ' ')
		.replace(/\b\w/g, (c) => c.toUpperCase());
}

function extractFrontmatter(content: string): { title?: string; order?: number; body: string } {
	const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
	if (!match) return { body: content };

	const frontmatter: Record<string, string> = {};
	for (const line of match[1].split('\n')) {
		const [key, ...vals] = line.split(':');
		if (key && vals.length) {
			frontmatter[key.trim()] = vals.join(':').trim();
		}
	}

	return {
		title: frontmatter.title,
		order: frontmatter.order ? parseInt(frontmatter.order) : undefined,
		body: match[2]
	};
}

async function walkDir(dir: string, base: string): Promise<NavItem[]> {
	const items: NavItem[] = [];

	let entries;
	try {
		entries = await readdir(dir);
	} catch {
		return items;
	}

	for (const entry of entries.sort()) {
		const fullPath = join(dir, entry);
		const s = await stat(fullPath);

		if (s.isDirectory()) {
			const children = await walkDir(fullPath, base);
			if (children.length > 0) {
				const indexFile = join(fullPath, 'index.md');
				const readmeFile = join(fullPath, 'README.md');
				let order = 50;

				try {
					const indexContent = await readFile(indexFile, 'utf-8');
					const fm = extractFrontmatter(indexContent);
					if (fm.order) order = fm.order;
				} catch {
					try {
						const readmeContent = await readFile(readmeFile, 'utf-8');
						const fm = extractFrontmatter(readmeContent);
						if (fm.order) order = fm.order;
					} catch {
						// no index or readme
					}
				}

				items.push({
					title: titleFromFilename(entry),
					slug: relative(base, fullPath),
					order,
					children
				});
			}
		} else if (entry.endsWith('.md') && entry !== 'index.md' && entry.toUpperCase() !== 'README.MD') {
			const content = await readFile(fullPath, 'utf-8');
			const fm = extractFrontmatter(content);
			items.push({
				title: fm.title || titleFromFilename(entry),
				slug: slugFromPath(fullPath, base),
				order: fm.order ?? 50
			});
		}
	}

	items.sort((a, b) => a.order - b.order || a.title.localeCompare(b.title));
	return items;
}

export async function getNavigation(): Promise<NavItem[]> {
	return walkDir(DOCS_DIR, DOCS_DIR);
}

export async function getDocPage(slug: string): Promise<DocPage | null> {
	const candidates = [
		join(DOCS_DIR, `${slug}.md`),
		join(DOCS_DIR, slug, 'index.md'),
		join(DOCS_DIR, slug, 'README.md')
	];

	for (const filePath of candidates) {
		try {
			const content = await readFile(filePath, 'utf-8');
			const fm = extractFrontmatter(content);
			return {
				content: fm.body,
				slug,
				title: fm.title || titleFromFilename(basename(filePath))
			};
		} catch {
			continue;
		}
	}

	return null;
}
