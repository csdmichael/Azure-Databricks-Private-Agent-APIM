import DOMPurify from 'dompurify';
import { marked } from 'marked';

/** Renders agent Markdown to HTML. Agent output is untrusted, so always sanitize. */
export function renderMarkdown(markdown: string): string {
  const html = marked.parse(markdown ?? '', { async: false, breaks: true, gfm: true }) as string;
  return DOMPurify.sanitize(html, { USE_PROFILES: { html: true } });
}

const BLOCK_TAGS = new Set(['P', 'DIV', 'LI', 'BLOCKQUOTE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6']);

/**
 * Converts the WYSIWYG editor's HTML into Markdown so the agent receives the
 * emphasis, lists and code spans the user actually typed.
 */
export function htmlToMarkdown(html: string): string {
  const root = new DOMParser().parseFromString(
    DOMPurify.sanitize(html ?? '', { USE_PROFILES: { html: true } }),
    'text/html',
  ).body;

  const walk = (node: Node, listPrefix?: () => string): string => {
    if (node.nodeType === Node.TEXT_NODE) {
      return node.textContent ?? '';
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return '';
    }

    const element = node as HTMLElement;
    const children = () =>
      Array.from(element.childNodes)
        .map((child) => walk(child, listPrefix))
        .join('');

    switch (element.tagName) {
      case 'BR':
        return '\n';
      case 'STRONG':
      case 'B':
        return `**${children()}**`;
      case 'EM':
      case 'I':
        return `*${children()}*`;
      case 'CODE':
        return `\`${children()}\``;
      case 'PRE':
        return `\n\`\`\`\n${children()}\n\`\`\`\n`;
      case 'A':
        return `[${children()}](${element.getAttribute('href') ?? ''})`;
      case 'UL':
      case 'OL': {
        let index = 0;
        const ordered = element.tagName === 'OL';
        return (
          '\n' +
          Array.from(element.children)
            .map((item) => {
              index += 1;
              const marker = ordered ? `${index}. ` : '- ';
              return marker + walk(item).trim();
            })
            .join('\n') +
          '\n'
        );
      }
      case 'BLOCKQUOTE':
        return `\n> ${children().trim()}\n`;
      default:
        return BLOCK_TAGS.has(element.tagName) ? `${children()}\n` : children();
    }
  };

  return Array.from(root.childNodes)
    .map((node) => walk(node))
    .join('')
    .replace(/\u00a0/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}
