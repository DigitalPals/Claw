import { describe, it, expect } from 'vitest'
import { loadQmlLib } from './helpers/qml-loader.js'

const P = loadQmlLib('claw/lib/protocol.js')

// ---------------------------------------------------------------------------
// channelFromSessionKey
// ---------------------------------------------------------------------------
describe('channelFromSessionKey', () => {
  it('extracts channel from agent:id:channel:extra format', () => {
    expect(P.channelFromSessionKey('agent:main:slack:channel:123')).toBe('slack')
  })

  it('extracts channel from agent:id:channel format', () => {
    expect(P.channelFromSessionKey('agent:main:main')).toBe('main')
  })

  it('extracts channel for different agent ids', () => {
    expect(P.channelFromSessionKey('agent:bot:webchat')).toBe('webchat')
  })

  it('falls back to second part for non-agent keys', () => {
    expect(P.channelFromSessionKey('foo:bar')).toBe('bar')
  })

  it('returns empty string for empty input', () => {
    expect(P.channelFromSessionKey('')).toBe('')
  })

  it('returns empty string for null', () => {
    expect(P.channelFromSessionKey(null)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(P.channelFromSessionKey(undefined)).toBe('')
  })

  it('returns empty string for single part with no colon', () => {
    expect(P.channelFromSessionKey('onlyonepart')).toBe('')
  })

  it('still returns third part for 5+ part agent keys', () => {
    expect(P.channelFromSessionKey('agent:x:discord:guild:chan:extra')).toBe('discord')
  })
})

// ---------------------------------------------------------------------------
// extractTextFromContent
// ---------------------------------------------------------------------------
describe('extractTextFromContent', () => {
  it('returns string content as-is', () => {
    expect(P.extractTextFromContent('hello world')).toBe('hello world')
  })

  it('returns empty string for null', () => {
    expect(P.extractTextFromContent(null)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(P.extractTextFromContent(undefined)).toBe('')
  })

  it('joins text blocks with newline', () => {
    const content = [
      { type: 'text', text: 'line one' },
      { type: 'text', text: 'line two' },
    ]
    expect(P.extractTextFromContent(content)).toBe('line one\nline two')
  })

  it('skips non-text blocks in mixed array', () => {
    const content = [
      { type: 'text', text: 'hello' },
      { type: 'image', source: { data: 'abc' } },
      { type: 'text', text: 'world' },
    ]
    expect(P.extractTextFromContent(content)).toBe('hello\nworld')
  })

  it('returns empty string for empty array', () => {
    expect(P.extractTextFromContent([])).toBe('')
  })

  it('returns empty string for number input', () => {
    expect(P.extractTextFromContent(42)).toBe('')
  })

  it('returns empty string for plain object input', () => {
    expect(P.extractTextFromContent({ type: 'text', text: 'hi' })).toBe('')
  })
})

// ---------------------------------------------------------------------------
// extractContentBlocksJson
// ---------------------------------------------------------------------------
describe('extractContentBlocksJson', () => {
  it('returns empty string when all blocks are text', () => {
    const blocks = [
      { type: 'text', text: 'a' },
      { type: 'text', text: 'b' },
    ]
    expect(P.extractContentBlocksJson(blocks)).toBe('')
  })

  it('returns JSON string when an image block is present', () => {
    const blocks = [
      { type: 'image', source: { data: 'abc' } },
    ]
    const result = P.extractContentBlocksJson(blocks)
    expect(result).toBe(JSON.stringify(blocks))
  })

  it('returns JSON string for mixed text and non-text blocks', () => {
    const blocks = [
      { type: 'text', text: 'hello' },
      { type: 'image', source: { data: 'xyz' } },
    ]
    const result = P.extractContentBlocksJson(blocks)
    expect(result).toBe(JSON.stringify(blocks))
  })

  it('returns empty string for a single text block', () => {
    const blocks = [{ type: 'text', text: 'only text' }]
    expect(P.extractContentBlocksJson(blocks)).toBe('')
  })

  it('returns empty string for an empty array', () => {
    expect(P.extractContentBlocksJson([])).toBe('')
  })
})

// ---------------------------------------------------------------------------
// truncateForToast
// ---------------------------------------------------------------------------
describe('truncateForToast', () => {
  it('returns short text unchanged', () => {
    expect(P.truncateForToast('hello', 100)).toBe('hello')
  })

  it('truncates long text with ellipsis character', () => {
    const result = P.truncateForToast('abcdefghij', 5)
    // maxLen 5 → substring(0,4) + \u2026
    expect(result).toBe('abcd\u2026')
    expect(result.length).toBe(5)
  })

  it('returns first non-empty line of multi-line input', () => {
    expect(P.truncateForToast('first line\nsecond line', 100)).toBe('first line')
  })

  it('skips leading blank lines', () => {
    expect(P.truncateForToast('\n\n  \nreal content\nmore', 100)).toBe('real content')
  })

  it('normalizes CRLF line endings', () => {
    expect(P.truncateForToast('line one\r\nline two', 100)).toBe('line one')
  })

  it('normalizes bare CR line endings', () => {
    expect(P.truncateForToast('first\rsecond', 100)).toBe('first')
  })

  it('returns empty string for null', () => {
    expect(P.truncateForToast(null, 50)).toBe('')
  })

  it('returns empty string for undefined', () => {
    expect(P.truncateForToast(undefined, 50)).toBe('')
  })
})

// ---------------------------------------------------------------------------
// ensureInstanceId
// ---------------------------------------------------------------------------
describe('ensureInstanceId', () => {
  it('returns existing ID as-is when truthy', () => {
    expect(P.ensureInstanceId('my-existing-id')).toBe('my-existing-id')
  })

  it('generates a new ID when given empty string', () => {
    const id = P.ensureInstanceId('')
    expect(id).toBeTruthy()
    expect(id.length).toBeGreaterThan(0)
  })

  it('generates a UUID v4-like string matching 8-4-4-4-12 hex pattern', () => {
    const id = P.ensureInstanceId('')
    const uuidRe = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    expect(id).toMatch(uuidRe)
  })

  it('generates unique IDs on successive calls', () => {
    const a = P.ensureInstanceId('')
    const b = P.ensureInstanceId('')
    expect(a).not.toBe(b)
  })
})

// ---------------------------------------------------------------------------
// markSessionUnread
// ---------------------------------------------------------------------------
describe('markSessionUnread', () => {
  it('adds a new session key to unread map', () => {
    const result = P.markSessionUnread({}, 'agent:main:slack:ch1')
    expect(result['agent:main:slack:ch1']).toBe(true)
  })

  it('returns same object reference when session is already unread', () => {
    const existing = { 'agent:main:slack:ch1': true }
    const result = P.markSessionUnread(existing, 'agent:main:slack:ch1')
    expect(result).toBe(existing)
  })

  it('returns same object reference when sessionKey is empty', () => {
    const existing = { a: true }
    expect(P.markSessionUnread(existing, '')).toBe(existing)
  })

  it('accumulates multiple sessions', () => {
    let unread = {}
    unread = P.markSessionUnread(unread, 'agent:main:slack:ch1')
    unread = P.markSessionUnread(unread, 'agent:main:slack:ch2')
    expect(Object.keys(unread)).toHaveLength(2)
    expect(unread['agent:main:slack:ch1']).toBe(true)
    expect(unread['agent:main:slack:ch2']).toBe(true)
  })

  it('preserves existing keys when adding a new one', () => {
    const existing = { 'agent:main:main:s1': true }
    const result = P.markSessionUnread(existing, 'agent:main:slack:s2')
    expect(result['agent:main:main:s1']).toBe(true)
    expect(result['agent:main:slack:s2']).toBe(true)
  })
})

// ---------------------------------------------------------------------------
// clearSessionUnread
// ---------------------------------------------------------------------------
describe('clearSessionUnread', () => {
  it('removes a session from the unread map', () => {
    const unread = { 'agent:main:slack:ch1': true, 'agent:main:main:s1': true }
    const result = P.clearSessionUnread(unread, 'agent:main:slack:ch1')
    expect(result['agent:main:slack:ch1']).toBeUndefined()
    expect(result['agent:main:main:s1']).toBe(true)
  })

  it('returns same object reference when session is not in map', () => {
    const existing = { a: true }
    const result = P.clearSessionUnread(existing, 'nonexistent')
    expect(result).toBe(existing)
  })

  it('returns same object reference when sessionKey is empty', () => {
    const existing = { a: true }
    expect(P.clearSessionUnread(existing, '')).toBe(existing)
  })

  it('preserves other keys after removal', () => {
    const unread = { x: true, y: true, z: true }
    const result = P.clearSessionUnread(unread, 'y')
    expect(Object.keys(result).sort()).toEqual(['x', 'z'])
  })
})

// ---------------------------------------------------------------------------
// clearChannelSessions
// ---------------------------------------------------------------------------
describe('clearChannelSessions', () => {
  it('removes all sessions matching the channel', () => {
    const unread = {
      'agent:main:slack:ch1': true,
      'agent:main:slack:ch2': true,
      'agent:main:main:s1': true,
    }
    const result = P.clearChannelSessions(unread, 'slack')
    expect(result['agent:main:slack:ch1']).toBeUndefined()
    expect(result['agent:main:slack:ch2']).toBeUndefined()
    expect(result['agent:main:main:s1']).toBe(true)
  })

  it('returns same object reference when no sessions match', () => {
    const existing = { 'agent:main:main:s1': true }
    const result = P.clearChannelSessions(existing, 'slack')
    expect(result).toBe(existing)
  })

  it('returns same object reference when channelId is empty', () => {
    const existing = { 'agent:main:slack:ch1': true }
    expect(P.clearChannelSessions(existing, '')).toBe(existing)
  })

  it('only removes sessions for the matching channel', () => {
    const unread = {
      'agent:main:slack:ch1': true,
      'agent:main:webchat:s1': true,
      'agent:main:slack:ch2': true,
      'agent:main:main:s1': true,
    }
    const result = P.clearChannelSessions(unread, 'slack')
    expect(Object.keys(result).sort()).toEqual([
      'agent:main:main:s1',
      'agent:main:webchat:s1',
    ])
  })
})

// ---------------------------------------------------------------------------
// filterSessionsForChannel
// ---------------------------------------------------------------------------
describe('filterSessionsForChannel', () => {
  it('filters sessions by explicit channel field', () => {
    const sessions = [
      { key: 'agent:main:slack:ch1', channel: 'slack' },
      { key: 'agent:main:main:s1', channel: 'main' },
      { key: 'agent:main:slack:ch2', channel: 'slack' },
    ]
    const result = P.filterSessionsForChannel(sessions, 'slack')
    expect(result).toHaveLength(2)
    expect(result[0].key).toBe('agent:main:slack:ch1')
    expect(result[1].key).toBe('agent:main:slack:ch2')
  })

  it('falls back to parsing key when channel field is missing', () => {
    const sessions = [
      { key: 'agent:main:slack:ch1' },
      { key: 'agent:main:main:s1' },
    ]
    const result = P.filterSessionsForChannel(sessions, 'slack')
    expect(result).toHaveLength(1)
    expect(result[0].key).toBe('agent:main:slack:ch1')
  })

  it('returns empty array when no sessions match', () => {
    const sessions = [
      { key: 'agent:main:main:s1', channel: 'main' },
    ]
    expect(P.filterSessionsForChannel(sessions, 'slack')).toEqual([])
  })

  it('returns all sessions when all match', () => {
    const sessions = [
      { key: 'a:b:webchat:1', channel: 'webchat' },
      { key: 'a:b:webchat:2', channel: 'webchat' },
    ]
    expect(P.filterSessionsForChannel(sessions, 'webchat')).toHaveLength(2)
  })

  it('returns empty array for empty input array', () => {
    expect(P.filterSessionsForChannel([], 'slack')).toEqual([])
  })
})
