import rehypeSlug from 'rehype-slug';
import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import { escapeSvelte } from 'mdsvex';
import { createHighlighter } from 'shiki';
import {
  transformerNotationDiff,
  transformerNotationHighlight,
  transformerNotationWordHighlight,
  transformerNotationFocus,
  transformerMetaHighlight
} from '@shikijs/transformers';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const shikiHighlighter = await createHighlighter({
  themes: ['github-light', 'github-dark-default'],
  langs: [
    'javascript', 'typescript', 'svelte', 'html', 'css', 'json', 'yaml', 'markdown',
    'bash', 'shell', 'python', 'rust', 'go', 'java', 'c', 'cpp', 'sql', 'graphql',
    'dockerfile', 'nginx', 'toml', 'xml', 'diff', 'hcl', 'nix', 'ini',
    'plaintext', 'text'
  ]
});

/**
 * Custom Shiki highlighter for MDsveX.
 * Mermaid code blocks are encoded as base64 data attributes for client-side rendering.
 */
function highlightCode(code, lang, meta) {
  if (lang === 'mermaid') {
    const encoded = Buffer.from(code.trim()).toString('base64');
    const id = `mermaid-${Math.random().toString(36).substr(2, 9)}`;
    return `<div class="mermaid-diagram my-6 not-prose" data-mermaid-code="${encoded}" data-mermaid-id="${id}"></div>`;
  }

  const language = lang || 'text';

  try {
    const html = shikiHighlighter.codeToHtml(code, {
      lang: language,
      themes: {
        light: 'github-light',
        dark: 'github-dark-default'
      },
      defaultColor: false,
      transformers: [
        transformerNotationDiff(),
        transformerNotationHighlight(),
        transformerNotationWordHighlight(),
        transformerNotationFocus(),
        transformerMetaHighlight()
      ]
    });

    const escaped = escapeSvelte(html);
    return `{@html \`${escaped}\`}`;
  } catch (error) {
    console.warn(`[mdsvex] Shiki highlighting failed for lang="${language}":`, error.message);
    const escaped = escapeSvelte(code);
    return `<pre><code class="language-${language}">${escaped}</code></pre>`;
  }
}

/** @type {import('mdsvex').MdsvexOptions} */
const config = {
  extensions: ['.svelte.md', '.md', '.svx'],

  layout: join(__dirname, 'src/lib/components/MdsvexLayout.svelte'),

  rehypePlugins: [
    rehypeSlug,
    [rehypeAutolinkHeadings, {
      behavior: 'wrap',
      properties: {
        className: ['heading-link']
      }
    }],
  ],

  highlight: {
    highlighter: highlightCode
  }
};

export default config;
