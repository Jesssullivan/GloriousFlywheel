#!/usr/bin/env node

/**
 * Generates llms.txt from docs/ content at build time.
 * Output: static/llms.txt (served at /llms.txt on each Pages site)
 *
 * Follows the llms.txt specification: plain text context file for LLMs
 * containing project description, structure, and documentation content.
 */

import { readdir, readFile, stat, writeFile, mkdir } from 'fs/promises';
import { join, relative, basename, dirname } from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const DOCS_DIR = join(__dirname, '..', '..', 'docs');
const OUTPUT = join(__dirname, '..', 'static', 'llms.txt');

function stripFrontmatter(content) {
	const match = content.match(/^---\n[\s\S]*?\n---\n([\s\S]*)$/);
	return match ? match[1].trim() : content.trim();
}

async function collectFiles(dir, base) {
	const results = [];
	let entries;
	try {
		entries = await readdir(dir);
	} catch {
		return results;
	}

	for (const entry of entries.sort()) {
		const fullPath = join(dir, entry);
		const s = await stat(fullPath);

		if (s.isDirectory()) {
			results.push(...(await collectFiles(fullPath, base)));
		} else if (entry.endsWith('.md')) {
			const rel = relative(base, fullPath);
			const content = await readFile(fullPath, 'utf-8');
			results.push({ path: rel, content: stripFrontmatter(content) });
		}
	}
	return results;
}

async function main() {
	const files = await collectFiles(DOCS_DIR, DOCS_DIR);

	// Read README for the header
	let readme = '';
	try {
		readme = await readFile(join(DOCS_DIR, '..', 'README.md'), 'utf-8');
	} catch {
		// no readme
	}

	const sections = [];

	sections.push('# attic-iac');
	sections.push('');
	sections.push('> Source: https://github.com/Jesssullivan/attic-iac');
	sections.push('> Docs: https://jesssullivan.github.io/attic-iac/');
	sections.push('> License: Zlib');
	sections.push('');

	if (readme) {
		sections.push(stripFrontmatter(readme));
		sections.push('');
		sections.push('---');
		sections.push('');
	}

	sections.push('# Full Documentation');
	sections.push('');

	for (const file of files) {
		sections.push(`## docs/${file.path}`);
		sections.push('');
		sections.push(file.content);
		sections.push('');
		sections.push('---');
		sections.push('');
	}

	const output = sections.join('\n');

	await mkdir(dirname(OUTPUT), { recursive: true });
	await writeFile(OUTPUT, output, 'utf-8');

	const kb = (Buffer.byteLength(output, 'utf-8') / 1024).toFixed(1);
	console.log(`Generated ${OUTPUT} (${files.length} docs, ${kb} KB)`);
}

main().catch((err) => {
	console.error('Failed to generate llms.txt:', err);
	process.exit(1);
});
