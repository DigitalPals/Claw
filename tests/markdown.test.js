import { describe, it, expect } from 'vitest'
import { loadQmlLib } from './helpers/qml-loader.js'

const M = loadQmlLib('claw/lib/markdown.js')

// ---------------------------------------------------------------------------
// escapeHtml
// ---------------------------------------------------------------------------
describe('escapeHtml', () => {
  it('returns empty string for null', () => {
    expect(M.escapeHtml(null)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(M.escapeHtml(undefined)).toBe('')
  })

  it('returns empty string for empty string', () => {
    expect(M.escapeHtml('')).toBe('')
  })

  it('leaves normal text unchanged', () => {
    expect(M.escapeHtml('hello world')).toBe('hello world')
  })

  it('escapes ampersand', () => {
    expect(M.escapeHtml('a & b')).toBe('a &amp; b')
  })

  it('escapes less-than', () => {
    expect(M.escapeHtml('a < b')).toBe('a &lt; b')
  })

  it('escapes greater-than', () => {
    expect(M.escapeHtml('a > b')).toBe('a &gt; b')
  })

  it('escapes double quote', () => {
    expect(M.escapeHtml('say "hi"')).toBe('say &quot;hi&quot;')
  })

  it('escapes single quote', () => {
    expect(M.escapeHtml("it's")).toBe('it&#39;s')
  })

  it('escapes multiple entities in one string', () => {
    expect(M.escapeHtml('<a href="x">&</a>')).toBe(
      '&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;'
    )
  })

  it('double-escapes already-escaped text', () => {
    expect(M.escapeHtml('&amp;')).toBe('&amp;amp;')
  })
})

// ---------------------------------------------------------------------------
// sanitizeUrlToken
// ---------------------------------------------------------------------------
describe('sanitizeUrlToken', () => {
  it('returns empty string for null', () => {
    expect(M.sanitizeUrlToken(null)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(M.sanitizeUrlToken(undefined)).toBe('')
  })

  it('returns empty string for empty string', () => {
    expect(M.sanitizeUrlToken('')).toBe('')
  })

  it('returns empty string for whitespace-only', () => {
    expect(M.sanitizeUrlToken('   ')).toBe('')
  })

  it('leaves a normal URL unchanged', () => {
    expect(M.sanitizeUrlToken('https://example.com/path')).toBe(
      'https://example.com/path'
    )
  })

  it('strips surrounding angle brackets', () => {
    expect(M.sanitizeUrlToken('<https://example.com/path>')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing closing paren', () => {
    expect(M.sanitizeUrlToken('https://example.com/path)')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing closing bracket', () => {
    expect(M.sanitizeUrlToken('https://example.com/path]')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing closing brace', () => {
    expect(M.sanitizeUrlToken('https://example.com/path}')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing period', () => {
    expect(M.sanitizeUrlToken('https://example.com/path.')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing comma', () => {
    expect(M.sanitizeUrlToken('https://example.com/path,')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing semicolon', () => {
    expect(M.sanitizeUrlToken('https://example.com/path;')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing colon', () => {
    expect(M.sanitizeUrlToken('https://example.com/path:')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing exclamation mark', () => {
    expect(M.sanitizeUrlToken('https://example.com/path!')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing question mark', () => {
    expect(M.sanitizeUrlToken('https://example.com/path?')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing asterisks (markdown emphasis)', () => {
    expect(M.sanitizeUrlToken('https://example.com/path**')).toBe(
      'https://example.com/path'
    )
  })

  it('strips trailing %2A (percent-encoded asterisk, case insensitive)', () => {
    expect(M.sanitizeUrlToken('https://example.com/path%2A%2a')).toBe(
      'https://example.com/path'
    )
  })

  it('drops trailing slash for host-only URL', () => {
    expect(M.sanitizeUrlToken('https://example.com/')).toBe(
      'https://example.com'
    )
  })

  it('keeps trailing slash for URL with path', () => {
    expect(M.sanitizeUrlToken('https://example.com/path/')).toBe(
      'https://example.com/path/'
    )
  })

  it('trims leading and trailing whitespace', () => {
    expect(M.sanitizeUrlToken('  https://example.com  ')).toBe(
      'https://example.com'
    )
  })

  it('handles combination: angle brackets + trailing emphasis + punctuation', () => {
    // Processing order: strip angles → strip slash (none) → strip stars → strip %2A → strip punct
    expect(M.sanitizeUrlToken('<https://example.com/path**.)>')).toBe(
      'https://example.com/path'
    )
  })

  it('strips multiple trailing punctuation characters', () => {
    expect(M.sanitizeUrlToken('https://example.com/path...')).toBe(
      'https://example.com/path'
    )
  })

  it('host-only http:// URL drops trailing slash', () => {
    expect(M.sanitizeUrlToken('http://example.com/')).toBe(
      'http://example.com'
    )
  })
})

// ---------------------------------------------------------------------------
// autoLinkBareUrlsInMarkdown
// ---------------------------------------------------------------------------
describe('autoLinkBareUrlsInMarkdown', () => {
  it('returns unchanged text with no URLs', () => {
    expect(M.autoLinkBareUrlsInMarkdown('hello world')).toBe('hello world')
  })

  it('wraps bare http:// URL in angle brackets', () => {
    expect(M.autoLinkBareUrlsInMarkdown('visit http://example.com now')).toBe(
      'visit <http://example.com> now'
    )
  })

  it('wraps bare https:// URL in angle brackets', () => {
    expect(M.autoLinkBareUrlsInMarkdown('visit https://example.com now')).toBe(
      'visit <https://example.com> now'
    )
  })

  it('does NOT wrap URL inside fenced code block', () => {
    const input = '```\nhttps://example.com\n```'
    expect(M.autoLinkBareUrlsInMarkdown(input)).toBe(input)
  })

  it('does NOT wrap URL inside inline code', () => {
    const input = 'run `https://example.com` here'
    expect(M.autoLinkBareUrlsInMarkdown(input)).toBe(input)
  })

  it('wraps multiple URLs', () => {
    const input = 'see https://a.com and https://b.com'
    expect(M.autoLinkBareUrlsInMarkdown(input)).toBe(
      'see <https://a.com> and <https://b.com>'
    )
  })

  it('handles URL with trailing punctuation (absorbed by sanitizeUrlToken)', () => {
    // The trailing-punct regex in autoLink uses double-escaped backslashes, so
    // it never splits trailing punctuation from the URL token.  Instead the
    // period is passed through to sanitizeUrlToken which strips it.
    expect(M.autoLinkBareUrlsInMarkdown('see https://example.com.')).toBe(
      'see <https://example.com>'
    )
  })

  it('handles mixed code block and URL outside', () => {
    const input = '```\ncode\n```\nhttps://example.com'
    expect(M.autoLinkBareUrlsInMarkdown(input)).toBe(
      '```\ncode\n```\n<https://example.com>'
    )
  })

  it('wraps URL inside markdown link parentheses (not markdown-aware)', () => {
    // autoLink is not markdown-aware for link syntax — it scans char-by-char
    // for http(s):// prefixes.  The URL inside the parens IS detected as bare.
    // The closing ")" is consumed as part of the URL token; sanitizeUrlToken
    // strips it.  Result: the original markdown link is broken.
    const input = '[click](https://example.com)'
    expect(M.autoLinkBareUrlsInMarkdown(input)).toBe(
      '[click](<https://example.com>'
    )
  })

  it('returns empty string for null input', () => {
    expect(M.autoLinkBareUrlsInMarkdown(null)).toBe('')
  })

  it('returns empty string for undefined input', () => {
    expect(M.autoLinkBareUrlsInMarkdown(undefined)).toBe('')
  })

  it('handles URL at end of string with no trailing space', () => {
    expect(M.autoLinkBareUrlsInMarkdown('go to https://example.com')).toBe(
      'go to <https://example.com>'
    )
  })
})

// ---------------------------------------------------------------------------
// renderPlainWithLinks
// ---------------------------------------------------------------------------
describe('renderPlainWithLinks', () => {
  it('escapes plain text', () => {
    expect(M.renderPlainWithLinks('hello <world>')).toBe(
      'hello &lt;world&gt;'
    )
  })

  it('turns a URL into a clickable <a> tag', () => {
    expect(M.renderPlainWithLinks('https://example.com')).toBe(
      '<a href="https://example.com">https://example.com</a>'
    )
  })

  it('handles URL in the middle of text', () => {
    expect(M.renderPlainWithLinks('go to https://example.com now')).toBe(
      'go to <a href="https://example.com">https://example.com</a> now'
    )
  })

  it('handles multiple URLs', () => {
    const result = M.renderPlainWithLinks('a https://a.com b https://b.com c')
    expect(result).toBe(
      'a <a href="https://a.com">https://a.com</a> b <a href="https://b.com">https://b.com</a> c'
    )
  })

  it('escapes HTML entities in surrounding text', () => {
    expect(M.renderPlainWithLinks('<b>bold</b> & https://x.com')).toBe(
      '&lt;b&gt;bold&lt;/b&gt; &amp; <a href="https://x.com">https://x.com</a>'
    )
  })

  it('returns empty string for null', () => {
    expect(M.renderPlainWithLinks(null)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(M.renderPlainWithLinks(undefined)).toBe('')
  })

  it('handles URL with trailing punctuation (absorbed by sanitizeUrlToken)', () => {
    // Same double-backslash regex issue as autoLink — the trailing period is NOT
    // split off as trailing text.  Instead the whole "https://example.com." goes
    // to sanitizeUrlToken which strips the period, so no trailing char appears.
    expect(M.renderPlainWithLinks('see https://example.com.')).toBe(
      'see <a href="https://example.com">https://example.com</a>'
    )
  })
})

// ---------------------------------------------------------------------------
// renderInlineNoCode
// ---------------------------------------------------------------------------
describe('renderInlineNoCode', () => {
  it('escapes plain text', () => {
    expect(M.renderInlineNoCode('hello <b>')).toBe('hello &lt;b&gt;')
  })

  it('renders [label](url) as an <a> tag', () => {
    expect(M.renderInlineNoCode('[click](https://example.com)')).toBe(
      '<a href="https://example.com">click</a>'
    )
  })

  it('renders bare URL as an <a> tag', () => {
    expect(M.renderInlineNoCode('visit https://example.com now')).toBe(
      'visit <a href="https://example.com">https://example.com</a> now'
    )
  })

  it('handles markdown link and bare URL in same string', () => {
    const input = '[a](https://a.com) and https://b.com'
    expect(M.renderInlineNoCode(input)).toBe(
      '<a href="https://a.com">a</a> and <a href="https://b.com">https://b.com</a>'
    )
  })

  it('falls through on broken markdown link (no closing paren)', () => {
    // No closing paren → [ is treated as literal text
    const input = '[label](https://example.com'
    // The [ is escaped, then "label" is escaped, then ]( is escaped,
    // then https://example.com is detected as bare URL
    expect(M.renderInlineNoCode(input)).toBe(
      '[label](<a href="https://example.com">https://example.com</a>'
    )
  })

  it('returns empty string for null', () => {
    expect(M.renderInlineNoCode(null)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(M.renderInlineNoCode(undefined)).toBe('')
  })

  it('escapes label HTML in markdown links', () => {
    expect(M.renderInlineNoCode('[<b>hi</b>](https://example.com)')).toBe(
      '<a href="https://example.com">&lt;b&gt;hi&lt;/b&gt;</a>'
    )
  })
})

// ---------------------------------------------------------------------------
// renderInlineBoldAndLinks
// ---------------------------------------------------------------------------
describe('renderInlineBoldAndLinks', () => {
  it('delegates plain text to renderInlineNoCode', () => {
    expect(M.renderInlineBoldAndLinks('hello <b>')).toBe('hello &lt;b&gt;')
  })

  it('renders **bold** as <b>bold</b>', () => {
    expect(M.renderInlineBoldAndLinks('**bold**')).toBe('<b>bold</b>')
  })

  it('renders multiple bold segments', () => {
    expect(M.renderInlineBoldAndLinks('**a** and **b**')).toBe(
      '<b>a</b> and <b>b</b>'
    )
  })

  it('treats unclosed ** as literal text', () => {
    // No closing ** → renderInlineNoCode("**trailing") which escapes it as-is
    // Actually: open = indexOf("**", 0) → 0. close = indexOf("**", 2) → -1.
    // So it does: out += renderInlineNoCode("") (empty from substring(0,0)) then
    // out += renderInlineNoCode("**trailing") and breaks.
    expect(M.renderInlineBoldAndLinks('**trailing')).toBe('**trailing')
  })

  it('renders bold with a link inside', () => {
    expect(
      M.renderInlineBoldAndLinks('**[click](https://example.com)**')
    ).toBe('<b><a href="https://example.com">click</a></b>')
  })

  it('renders bold with bare URL inside', () => {
    expect(M.renderInlineBoldAndLinks('**https://example.com**')).toBe(
      '<b><a href="https://example.com">https://example.com</a></b>'
    )
  })

  it('returns empty string for null', () => {
    expect(M.renderInlineBoldAndLinks(null)).toBe('')
  })

  it('handles text before, between, and after bold', () => {
    expect(M.renderInlineBoldAndLinks('a **b** c **d** e')).toBe(
      'a <b>b</b> c <b>d</b> e'
    )
  })
})

// ---------------------------------------------------------------------------
// renderInlineMarkdownLite
// ---------------------------------------------------------------------------
describe('renderInlineMarkdownLite', () => {
  it('renders plain text', () => {
    expect(M.renderInlineMarkdownLite('hello world')).toBe('hello world')
  })

  it('renders `code` as <tt>code</tt>', () => {
    expect(M.renderInlineMarkdownLite('run `code` now')).toBe(
      'run <tt>code</tt> now'
    )
  })

  it('renders **bold** as <b>bold</b>', () => {
    expect(M.renderInlineMarkdownLite('this is **bold** text')).toBe(
      'this is <b>bold</b> text'
    )
  })

  it('handles backslash escape for backtick', () => {
    // \` → literal ` in the raw string, then it is not treated as code delimiter
    expect(M.renderInlineMarkdownLite('use \\` for code')).toBe(
      'use ` for code'
    )
  })

  it('handles backslash escape for single asterisk', () => {
    // A single \* should produce a literal * in output (not trigger bold)
    // The JS string '\\*hello' sends the two chars \* to the function,
    // which escapes the * to a literal.
    expect(M.renderInlineMarkdownLite('\\*hello')).toBe('*hello')
  })

  it('does not prevent bold when backslash-star pairs reassemble **', () => {
    // JS string '\\*\\*not bold\\*\\*' is the 18-char sequence \*\*not bold\*\*
    // The backslash-escape pass strips each \* → *, yielding **not bold**
    // Then the bold renderer treats ** as bold delimiters.
    expect(M.renderInlineMarkdownLite('\\*\\*not bold\\*\\*')).toBe(
      '<b>not bold</b>'
    )
  })

  it('handles backslash escape for brackets', () => {
    expect(M.renderInlineMarkdownLite('\\[not a link\\]')).toBe(
      '[not a link]'
    )
  })

  it('renders code and bold in the same line', () => {
    expect(M.renderInlineMarkdownLite('`code` and **bold**')).toBe(
      '<tt>code</tt> and <b>bold</b>'
    )
  })

  it('treats unclosed backtick as literal with remaining text', () => {
    // When backtick is never closed: prepends ` to buf and renders via renderInlineBoldAndLinks
    expect(M.renderInlineMarkdownLite('open `never closed')).toBe(
      'open `never closed'
    )
  })

  it('renders mixed text, code, bold, and links', () => {
    const input = 'see `cmd` and **[link](https://x.com)** done'
    expect(M.renderInlineMarkdownLite(input)).toBe(
      'see <tt>cmd</tt> and <b><a href="https://x.com">link</a></b> done'
    )
  })

  it('escapes HTML inside code spans', () => {
    expect(M.renderInlineMarkdownLite('`<script>`')).toBe(
      '<tt>&lt;script&gt;</tt>'
    )
  })

  it('returns empty string for null', () => {
    expect(M.renderInlineMarkdownLite(null)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(M.renderInlineMarkdownLite(undefined)).toBe('')
  })
})

// ---------------------------------------------------------------------------
// splitHyphenListLine
// ---------------------------------------------------------------------------
describe('splitHyphenListLine', () => {
  it('returns single-element array for normal text', () => {
    expect(M.splitHyphenListLine('hello world')).toEqual(['hello world'])
  })

  it('returns single-element array when only one separator', () => {
    // Need at least 2 separators to split
    expect(M.splitHyphenListLine('A - B')).toEqual(['A - B'])
  })

  it('splits into 3 items with 2 separators', () => {
    expect(M.splitHyphenListLine('A - B - C')).toEqual([
      'A',
      '- B',
      '- C',
    ])
  })

  it('splits into 4 items with 3 separators', () => {
    expect(M.splitHyphenListLine('A - B - C - D')).toEqual([
      'A',
      '- B',
      '- C',
      '- D',
    ])
  })

  it('returns [""] for null', () => {
    expect(M.splitHyphenListLine(null)).toEqual([''])
  })

  it('returns [""] for undefined', () => {
    expect(M.splitHyphenListLine(undefined)).toEqual([''])
  })

  it('handles tab whitespace around dash', () => {
    expect(M.splitHyphenListLine('A\t-\tB\t-\tC')).toEqual([
      'A',
      '- B',
      '- C',
    ])
  })

  it('handles non-breaking space around dash', () => {
    expect(M.splitHyphenListLine('A\u00A0-\u00A0B\u00A0-\u00A0C')).toEqual([
      'A',
      '- B',
      '- C',
    ])
  })
})

// ---------------------------------------------------------------------------
// markdownLiteToHtml
// ---------------------------------------------------------------------------
describe('markdownLiteToHtml', () => {
  it('returns empty string for empty input', () => {
    expect(M.markdownLiteToHtml('')).toBe('')
  })

  it('returns empty string for null', () => {
    expect(M.markdownLiteToHtml(null)).toBe('')
  })

  it('renders a single line with inline markdown', () => {
    expect(M.markdownLiteToHtml('hello **bold**')).toBe('hello <b>bold</b>')
  })

  it('joins multiple lines with <br/>', () => {
    expect(M.markdownLiteToHtml('line1\nline2')).toBe('line1<br/>line2')
  })

  it('renders fenced code block as <pre><tt>', () => {
    const input = '```\ncode here\n```'
    expect(M.markdownLiteToHtml(input)).toBe('<pre><tt>code here</tt></pre>')
  })

  it('renders unclosed fence as code block at end', () => {
    const input = '```\ncode here'
    // inFence is still true at the end → flushFence is called
    expect(M.markdownLiteToHtml(input)).toBe('<pre><tt>code here</tt></pre>')
  })

  it('produces <br/> for blank lines', () => {
    const input = 'a\n\nb'
    // Line 0: "a" → "a"
    // Line 1: "" → "<br/>" (li > 0) but line is empty so no content
    // Line 2: "b" → "<br/>b"
    expect(M.markdownLiteToHtml(input)).toBe('a<br/><br/>b')
  })

  it('normalizes CRLF to LF', () => {
    expect(M.markdownLiteToHtml('a\r\nb')).toBe('a<br/>b')
  })

  it('normalizes lone CR to LF', () => {
    expect(M.markdownLiteToHtml('a\rb')).toBe('a<br/>b')
  })

  it('strips the language tag after opening fence', () => {
    const input = '```javascript\nconsole.log(1)\n```'
    // The line "```javascript" starts with ``` so it's treated as a fence opener
    expect(M.markdownLiteToHtml(input)).toBe(
      '<pre><tt>console.log(1)</tt></pre>'
    )
  })

  it('escapes HTML inside fenced code blocks', () => {
    const input = '```\n<script>alert(1)</script>\n```'
    expect(M.markdownLiteToHtml(input)).toBe(
      '<pre><tt>&lt;script&gt;alert(1)&lt;/script&gt;</tt></pre>'
    )
  })

  it('handles mixed text, code block, and text', () => {
    // Fence lines use `continue` so they don't emit <br/>.
    // Only lines after the code block that are non-fence get <br/> prefix.
    const input = 'before\n```\ncode\n```\nafter'
    expect(M.markdownLiteToHtml(input)).toBe(
      'before<pre><tt>code</tt></pre><br/>after'
    )
  })
})

// ---------------------------------------------------------------------------
// normalizeMarkdownForDisplay
// ---------------------------------------------------------------------------
describe('normalizeMarkdownForDisplay', () => {
  it('returns single newline for empty input', () => {
    // Empty string splits to [""], the loop runs once and appends "\n"
    expect(M.normalizeMarkdownForDisplay('')).toBe('\n')
  })

  it('returns single newline for null', () => {
    expect(M.normalizeMarkdownForDisplay(null)).toBe('\n')
  })

  it('preserves fenced code blocks verbatim', () => {
    const input = '```\ncode line\n```'
    expect(M.normalizeMarkdownForDisplay(input)).toBe('```\ncode line\n```')
  })

  it('expands inline bold headings with colons', () => {
    // **Title:** text → newline before **Title:** and newline after
    const input = 'intro **Title:** detail'
    const result = M.normalizeMarkdownForDisplay(input)
    expect(result).toContain('**Title:**')
    // The bold heading should be on its own line
    const lines = result.split('\n')
    const boldLine = lines.find((l) => l.trim() === '**Title:**')
    expect(boldLine).toBeDefined()
  })

  it('splits numbered list items onto separate lines', () => {
    const input = 'First item 1. Second item 2. Third item'
    const result = M.normalizeMarkdownForDisplay(input)
    expect(result).toContain('1. Second item')
    expect(result).toContain('2. Third item')
  })

  it('adds trailing double-space when forceHardLineBreaks is true', () => {
    const input = 'line one\nline two'
    const result = M.normalizeMarkdownForDisplay(input, true)
    // Each non-list line should get "  " appended before the newline
    expect(result).toContain('line one  \n')
    expect(result).toContain('line two  \n')
  })

  it('does NOT add trailing spaces to list-like lines with forceHardLineBreaks', () => {
    const input = '- item one\n- item two'
    const result = M.normalizeMarkdownForDisplay(input, true)
    // List lines should NOT get the trailing double-space
    expect(result).not.toContain('- item one  ')
    expect(result).not.toContain('- item two  ')
  })

  it('normalizes CRLF to LF', () => {
    const input = 'a\r\nb'
    const result = M.normalizeMarkdownForDisplay(input)
    expect(result).not.toContain('\r')
  })
})

// ---------------------------------------------------------------------------
// extractUrls
// ---------------------------------------------------------------------------
describe('extractUrls', () => {
  it('returns empty array when no URLs', () => {
    expect(M.extractUrls('hello world')).toEqual([])
  })

  it('extracts a single URL', () => {
    expect(M.extractUrls('visit https://example.com ok')).toEqual([
      'https://example.com',
    ])
  })

  it('extracts multiple URLs and deduplicates', () => {
    expect(
      M.extractUrls('https://a.com and https://b.com and https://a.com')
    ).toEqual(['https://a.com', 'https://b.com'])
  })

  it('cleans trailing punctuation from extracted URLs', () => {
    expect(M.extractUrls('see https://example.com.')).toEqual([
      'https://example.com',
    ])
  })

  it('returns empty array for null', () => {
    expect(M.extractUrls(null)).toEqual([])
  })

  it('returns empty array for undefined', () => {
    expect(M.extractUrls(undefined)).toEqual([])
  })
})

// ---------------------------------------------------------------------------
// renderInlineFormatting
// ---------------------------------------------------------------------------
describe('renderInlineFormatting', () => {
  it('renders *italic* as <i>italic</i>', () => {
    expect(M.renderInlineFormatting('*italic*')).toBe('<i>italic</i>')
  })

  it('renders _italic_ as <i>italic</i>', () => {
    expect(M.renderInlineFormatting('_italic_')).toBe('<i>italic</i>')
  })

  it('renders **bold** as <b>bold</b>', () => {
    expect(M.renderInlineFormatting('**bold**')).toBe('<b>bold</b>')
  })

  it('renders __bold__ as <b>bold</b>', () => {
    expect(M.renderInlineFormatting('__bold__')).toBe('<b>bold</b>')
  })

  it('renders ~~strikethrough~~ as <s>strikethrough</s>', () => {
    expect(M.renderInlineFormatting('~~strikethrough~~')).toBe('<s>strikethrough</s>')
  })

  it('renders ***bold italic*** as <b><i>bold italic</i></b>', () => {
    expect(M.renderInlineFormatting('***bold italic***')).toBe('<b><i>bold italic</i></b>')
  })

  it('renders ___bold italic___ as <b><i>bold italic</i></b>', () => {
    expect(M.renderInlineFormatting('___bold italic___')).toBe('<b><i>bold italic</i></b>')
  })

  it('handles bold with nested italic', () => {
    expect(M.renderInlineFormatting('**bold *nested* more**')).toBe(
      '<b>bold <i>nested</i> more</b>'
    )
  })

  it('handles mixed bold and italic', () => {
    expect(M.renderInlineFormatting('**bold** and *italic*')).toBe(
      '<b>bold</b> and <i>italic</i>'
    )
  })

  it('handles mixed bold and strikethrough', () => {
    expect(M.renderInlineFormatting('**bold** and ~~struck~~')).toBe(
      '<b>bold</b> and <s>struck</s>'
    )
  })

  it('treats unclosed * as literal text', () => {
    expect(M.renderInlineFormatting('*unclosed')).toBe('*unclosed')
  })

  it('treats unclosed ~~ as literal text', () => {
    expect(M.renderInlineFormatting('~~unclosed')).toBe('~~unclosed')
  })

  it('does not treat _ as italic inside words', () => {
    expect(M.renderInlineFormatting('some_var_name')).toBe('some_var_name')
  })

  it('does not treat __ as bold inside words', () => {
    expect(M.renderInlineFormatting('some__var__name')).toBe('some__var__name')
  })

  it('treats _ as italic at word boundaries', () => {
    expect(M.renderInlineFormatting('a _text_ b')).toBe('a <i>text</i> b')
  })

  it('returns empty string for null', () => {
    expect(M.renderInlineFormatting(null)).toBe('')
  })

  it('delegates plain text to renderInlineNoCode', () => {
    expect(M.renderInlineFormatting('hello <b>')).toBe('hello &lt;b&gt;')
  })

  it('renders bold with a link inside', () => {
    expect(M.renderInlineFormatting('**[click](https://example.com)**')).toBe(
      '<b><a href="https://example.com">click</a></b>'
    )
  })
})

// ---------------------------------------------------------------------------
// markdownLiteToHtml — block-level features
// ---------------------------------------------------------------------------
describe('markdownLiteToHtml block features', () => {
  it('renders # heading as <h1>', () => {
    expect(M.markdownLiteToHtml('# Title')).toBe('<h1>Title</h1>')
  })

  it('renders ## heading as <h2>', () => {
    expect(M.markdownLiteToHtml('## Subtitle')).toBe('<h2>Subtitle</h2>')
  })

  it('renders ### heading as <h3>', () => {
    expect(M.markdownLiteToHtml('### Section')).toBe('<h3>Section</h3>')
  })

  it('renders #### heading as <h4>', () => {
    expect(M.markdownLiteToHtml('#### Sub-section')).toBe('<h4>Sub-section</h4>')
  })

  it('renders heading with inline formatting', () => {
    expect(M.markdownLiteToHtml('# **Bold** title')).toBe('<h1><b>Bold</b> title</h1>')
  })

  it('renders unordered list with -', () => {
    expect(M.markdownLiteToHtml('- item 1\n- item 2')).toBe(
      '<ul><li>item 1</li><li>item 2</li></ul>'
    )
  })

  it('renders unordered list with *', () => {
    expect(M.markdownLiteToHtml('* item 1\n* item 2')).toBe(
      '<ul><li>item 1</li><li>item 2</li></ul>'
    )
  })

  it('renders ordered list', () => {
    expect(M.markdownLiteToHtml('1. first\n2. second\n3. third')).toBe(
      '<ol><li>first</li><li>second</li><li>third</li></ol>'
    )
  })

  it('renders blockquote as table with border', () => {
    const result = M.markdownLiteToHtml('> quoted text')
    expect(result).toContain('<table')
    expect(result).toContain('quoted text')
    expect(result).toContain('</table>')
  })

  it('renders multi-line blockquote', () => {
    const result = M.markdownLiteToHtml('> line 1\n> line 2')
    expect(result).toContain('line 1<br/>line 2')
    expect(result).toContain('</table>')
  })

  it('renders horizontal rule with ---', () => {
    expect(M.markdownLiteToHtml('---')).toBe('<hr/>')
  })

  it('renders horizontal rule with ***', () => {
    expect(M.markdownLiteToHtml('***')).toBe('<hr/>')
  })

  it('renders horizontal rule with ___', () => {
    expect(M.markdownLiteToHtml('___')).toBe('<hr/>')
  })

  it('closes list before heading', () => {
    expect(M.markdownLiteToHtml('- item\n# Heading')).toBe(
      '<ul><li>item</li></ul><h1>Heading</h1>'
    )
  })

  it('closes blockquote before list', () => {
    const result = M.markdownLiteToHtml('> quote\n- item')
    expect(result).toContain('quote')
    expect(result).toContain('</table>')
    expect(result).toContain('<ul><li>item</li></ul>')
  })

  it('blank line closes list', () => {
    expect(M.markdownLiteToHtml('- item\n\ntext')).toBe(
      '<ul><li>item</li></ul><br/>text'
    )
  })

  it('switches from ul to ol', () => {
    expect(M.markdownLiteToHtml('- bullet\n1. number')).toBe(
      '<ul><li>bullet</li></ul><ol><li>number</li></ol>'
    )
  })

  it('renders mixed heading, list, text', () => {
    const input = '# Title\n- item 1\n- item 2\nsome text'
    expect(M.markdownLiteToHtml(input)).toBe(
      '<h1>Title</h1><ul><li>item 1</li><li>item 2</li></ul><br/>some text'
    )
  })

  it('does not apply splitHyphenListLine to list items', () => {
    // "A - B - C" as a list item should remain intact
    expect(M.markdownLiteToHtml('- A - B - C')).toBe(
      '<ul><li>A - B - C</li></ul>'
    )
  })

  it('applies splitHyphenListLine to regular text', () => {
    // Regular text with hyphen separators is still split
    const result = M.markdownLiteToHtml('A - B - C')
    expect(result).toContain('- B')
    expect(result).toContain('- C')
  })

  it('renders nested unordered list', () => {
    const input = '- item 1\n- item 2\n    - nested a\n    - nested b\n- item 3'
    expect(M.markdownLiteToHtml(input)).toBe(
      '<ul><li>item 1</li><li>item 2</li><ul><li>nested a</li><li>nested b</li></ul><li>item 3</li></ul>'
    )
  })

  it('renders nested ordered list', () => {
    const input = '1. first\n2. second\n    1. sub-a\n    2. sub-b\n3. third'
    expect(M.markdownLiteToHtml(input)).toBe(
      '<ol><li>first</li><li>second</li><ol><li>sub-a</li><li>sub-b</li></ol><li>third</li></ol>'
    )
  })

  it('renders mixed nested list types', () => {
    const input = '- bullet\n    1. numbered\n    2. numbered'
    expect(M.markdownLiteToHtml(input)).toBe(
      '<ul><li>bullet</li><ol><li>numbered</li><li>numbered</li></ol></ul>'
    )
  })
})

// ---------------------------------------------------------------------------
// markdownLiteToHtml — styleOpts
// ---------------------------------------------------------------------------
describe('markdownLiteToHtml styleOpts', () => {
  const opts = {
    codeBg: '#112233',
    codeBlockBg: '#445566',
    blockquoteBorder: '#778899',
  }

  it('wraps inline <tt> with styled span', () => {
    const result = M.markdownLiteToHtml('use `code` here', opts)
    expect(result).toContain('<span style="background-color: #112233;"><tt>code</tt></span>')
  })

  it('styles <pre> blocks with codeBlockBg', () => {
    const result = M.markdownLiteToHtml('```\ncode\n```', opts)
    expect(result).toContain('background-color: #445566; padding: 8px;')
  })

  it('does not style <tt> inside <pre> with codeBg', () => {
    const result = M.markdownLiteToHtml('```\ncode\n```', opts)
    // The <tt> inside <pre> should NOT be wrapped with codeBg span
    expect(result).not.toContain('#112233')
  })

  it('styles blockquote with border color via table cell', () => {
    const result = M.markdownLiteToHtml('> quoted', opts)
    expect(result).toContain('background-color: #778899')
    expect(result).toContain('quoted')
  })

  it('works without styleOpts (backward compat)', () => {
    const result = M.markdownLiteToHtml('use `code` here')
    expect(result).toBe('use <tt>code</tt> here')
  })

  it('styles table borders', () => {
    const input = '| A | B |\n|---|---|\n| 1 | 2 |'
    const result = M.markdownLiteToHtml(input, opts)
    expect(result).toContain('<table')
    expect(result).toContain('<th')
    expect(result).toContain('<td')
  })
})

// ---------------------------------------------------------------------------
// markdownLiteToHtml — tables
// ---------------------------------------------------------------------------
describe('markdownLiteToHtml tables', () => {
  it('renders a basic table with header', () => {
    const input = '| Header 1 | Header 2 |\n|----------|----------|\n| Cell 1 | Cell 2 |'
    const result = M.markdownLiteToHtml(input)
    expect(result).toContain('<table')
    expect(result).toContain('<th')
    expect(result).toContain('Header 1')
    expect(result).toContain('<td')
    expect(result).toContain('Cell 1')
    expect(result).toContain('</table>')
  })

  it('renders table without header (no separator line)', () => {
    const input = '| A | B |\n| 1 | 2 |'
    const result = M.markdownLiteToHtml(input)
    expect(result).toContain('<td')
    expect(result).not.toContain('<th')
  })

  it('renders inline formatting in table cells', () => {
    const input = '| **bold** | *italic* |\n|---|---|\n| `code` | text |'
    const result = M.markdownLiteToHtml(input)
    expect(result).toContain('<b>bold</b>')
    expect(result).toContain('<i>italic</i>')
    expect(result).toContain('<tt>code</tt>')
  })

  it('closes table before other blocks', () => {
    const input = '| A | B |\n|---|---|\n| 1 | 2 |\n# Heading'
    const result = M.markdownLiteToHtml(input)
    expect(result).toContain('</table><h1>Heading</h1>')
  })

  it('renders multiple-row table', () => {
    const input = '| H1 | H2 |\n|---|---|\n| a | b |\n| c | d |'
    const result = M.markdownLiteToHtml(input)
    // 1 header row + 2 data rows = 3 <tr> tags
    const trCount = (result.match(/<tr>/g) || []).length
    expect(trCount).toBe(3)
  })
})

// ---------------------------------------------------------------------------
// syntaxHighlightCode
// ---------------------------------------------------------------------------
describe('syntaxHighlightCode', () => {
  const hlOpts = {
    keywordColor: '#00ff00',
    stringColor: '#ffff00',
    commentColor: '#888888',
  }

  it('returns escaped HTML when opts is null', () => {
    expect(M.syntaxHighlightCode('<b>', null)).toBe('&lt;b&gt;')
  })

  it('highlights keywords', () => {
    const result = M.syntaxHighlightCode('export FOO', hlOpts)
    expect(result).toContain('color: #00ff00')
    expect(result).toContain('export')
    expect(result).toContain('FOO')
  })

  it('highlights strings in double quotes', () => {
    const result = M.syntaxHighlightCode('x="hello"', hlOpts)
    expect(result).toContain('color: #ffff00')
    expect(result).toContain('&quot;hello&quot;')
  })

  it('highlights strings in single quotes', () => {
    const result = M.syntaxHighlightCode("x='hello'", hlOpts)
    expect(result).toContain('color: #ffff00')
    expect(result).toContain("&#39;hello&#39;")
  })

  it('highlights full-line comments with #', () => {
    const result = M.syntaxHighlightCode('# comment here', hlOpts)
    expect(result).toContain('color: #888888')
    expect(result).toContain('# comment here')
  })

  it('highlights full-line comments with //', () => {
    const result = M.syntaxHighlightCode('// comment here', hlOpts)
    expect(result).toContain('color: #888888')
  })

  it('does not color non-keywords', () => {
    const result = M.syntaxHighlightCode('myFunction()', hlOpts)
    expect(result).not.toContain('color:')
  })

  it('handles mixed keywords, strings, comments', () => {
    const result = M.syntaxHighlightCode('export KEY="value" # set key', hlOpts)
    expect(result).toContain('#00ff00')  // keyword
    expect(result).toContain('#ffff00')  // string
    expect(result).toContain('#888888')  // comment
  })

  it('handles multi-line code', () => {
    const result = M.syntaxHighlightCode('# header\nexport X="y"', hlOpts)
    expect(result).toContain('\n')
    expect(result).toContain('#888888')  // comment line
    expect(result).toContain('#00ff00')  // keyword line
  })
})
