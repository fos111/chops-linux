// Markdown preview pipeline for the detail editor.
//
// Skill files are untrusted input (they can come from the registry or from a
// teammate), so the rendered HTML is always passed through DOMPurify before it is
// injected with `{@html}`. Fenced code blocks are highlighted by highlight.js inside
// the marked renderer, which keeps the preview a pure function of the editor buffer.

import DOMPurify from "dompurify";
import hljs from "highlight.js";
import { Marked, type Tokens } from "marked";

const marked = new Marked({
  gfm: true,
  breaks: false,
  renderer: {
    code({ text, lang }: Tokens.Code): string {
      const requested = (lang ?? "").trim().split(/\s+/)[0];
      const language = requested && hljs.getLanguage(requested) ? requested : null;
      const highlighted = language
        ? hljs.highlight(text, { language, ignoreIllegals: true }).value
        : hljs.highlightAuto(text).value;
      const languageClass = language
        ? ` language-${language.replace(/[^a-zA-Z0-9_-]/g, "")}`
        : "";
      return `<pre><code class="hljs${languageClass}">${highlighted}</code></pre>`;
    },
  },
});

/**
 * Removes a leading YAML frontmatter block so the preview shows the document body
 * (the textarea still edits the complete file).
 */
export function stripFrontmatter(markdown: string): string {
  const lines = markdown.split("\n");
  if (lines[0]?.trim() !== "---") return markdown;
  const end = lines.findIndex((line, index) => index > 0 && line.trim() === "---");
  if (end < 0) return markdown;
  return lines.slice(end + 1).join("\n").replace(/^\n+/, "");
}

/** Renders Markdown to sanitized HTML. Never returns executable markup. */
export function renderMarkdown(markdown: string): string {
  const html = marked.parse(stripFrontmatter(markdown)) as string;
  return DOMPurify.sanitize(html, {
    USE_PROFILES: { html: true },
    FORBID_TAGS: ["style", "iframe", "form", "input", "button"],
    FORBID_ATTR: ["style"],
  });
}
