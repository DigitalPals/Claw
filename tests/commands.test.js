import { describe, it, expect } from 'vitest'
import { loadQmlLib } from './helpers/qml-loader.js'

const C = loadQmlLib('claw/lib/commands.js')

// ---------------------------------------------------------------------------
// commandShouldOpen
// ---------------------------------------------------------------------------
describe('commandShouldOpen', () => {
  it('returns true for a bare slash "/"', () => {
    expect(C.commandShouldOpen('/')).toBe(true)
  })

  it('returns true for a partial command "/h"', () => {
    expect(C.commandShouldOpen('/h')).toBe(true)
  })

  it('returns true for a full command "/help"', () => {
    expect(C.commandShouldOpen('/help')).toBe(true)
  })

  it('returns false when the command contains a space "/help "', () => {
    expect(C.commandShouldOpen('/help ')).toBe(false)
  })

  it('returns false when the command contains a tab "/help\\t"', () => {
    expect(C.commandShouldOpen('/help\t')).toBe(false)
  })

  it('returns false when the command contains a newline "/help\\n"', () => {
    expect(C.commandShouldOpen('/help\n')).toBe(false)
  })

  it('returns false for an empty string', () => {
    expect(C.commandShouldOpen('')).toBe(false)
  })

  it('returns false for null', () => {
    expect(C.commandShouldOpen(null)).toBe(false)
  })

  it('returns false for undefined', () => {
    expect(C.commandShouldOpen(undefined)).toBe(false)
  })

  it('returns false for text without a leading slash', () => {
    expect(C.commandShouldOpen('hello')).toBe(false)
  })

  it('returns false when a space precedes the slash', () => {
    expect(C.commandShouldOpen(' /help')).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// sessionDisplayName
// ---------------------------------------------------------------------------
describe('sessionDisplayName', () => {
  it('extracts the tail after the third colon for agent keys with 4+ parts', () => {
    expect(C.sessionDisplayName('agent:main:slack:channel:c0ae9n9jkkp'))
      .toBe('channel:c0ae9n9jkkp')
  })

  it('returns the third part for a 3-part agent key', () => {
    expect(C.sessionDisplayName('agent:main:main')).toBe('main')
  })

  it('returns the third part for another 3-part agent key', () => {
    expect(C.sessionDisplayName('agent:bot:webchat')).toBe('webchat')
  })

  it('extracts multi-segment tail for agent keys with colons in the suffix', () => {
    expect(C.sessionDisplayName('agent:main:slack:user:john'))
      .toBe('user:john')
  })

  it('returns tail from index 2 for non-agent 3-part keys', () => {
    expect(C.sessionDisplayName('foo:bar:baz')).toBe('baz')
  })

  it('returns the second part for a 2-part key', () => {
    expect(C.sessionDisplayName('foo:bar')).toBe('bar')
  })

  it('returns the key as-is for a single segment', () => {
    expect(C.sessionDisplayName('single')).toBe('single')
  })

  it('returns an empty string for an empty string input', () => {
    expect(C.sessionDisplayName('')).toBe('')
  })

  it('returns null when given null (falls through to return sessionKey)', () => {
    expect(C.sessionDisplayName(null)).toBe(null)
  })

  it('returns undefined when given undefined (falls through to return sessionKey)', () => {
    expect(C.sessionDisplayName(undefined)).toBe(undefined)
  })
})

// ---------------------------------------------------------------------------
// channelLabel
// ---------------------------------------------------------------------------
describe('channelLabel', () => {
  it('returns the label when the channel is found in meta', () => {
    const meta = [{ id: 'ch1', label: 'General' }]
    expect(C.channelLabel('ch1', meta)).toBe('General')
  })

  it('returns the channelId when the channel exists in meta but has no label', () => {
    const meta = [{ id: 'ch1' }]
    expect(C.channelLabel('ch1', meta)).toBe('ch1')
  })

  it('returns the channelId when the channel is not found in meta', () => {
    const meta = [{ id: 'ch2', label: 'Other' }]
    expect(C.channelLabel('ch1', meta)).toBe('ch1')
  })

  it('returns the channelId when the meta array is empty', () => {
    expect(C.channelLabel('ch1', [])).toBe('ch1')
  })

  it('returns the correct label when multiple channels are present', () => {
    const meta = [
      { id: 'ch1', label: 'General' },
      { id: 'ch2', label: 'Random' },
      { id: 'ch3', label: 'Support' },
    ]
    expect(C.channelLabel('ch2', meta)).toBe('Random')
  })
})

// ---------------------------------------------------------------------------
// channelHasUnread
// ---------------------------------------------------------------------------
describe('channelHasUnread', () => {
  const mockChannelFn = (key) => {
    const parts = key.split(':')
    return parts.length >= 3 && parts[0] === 'agent' ? parts[2] : ''
  }

  it('returns true when an unread session belongs to the channel', () => {
    const unread = { 'agent:main:slack:channel:c1': true }
    expect(C.channelHasUnread('slack', unread, mockChannelFn)).toBe(true)
  })

  it('returns false when there are no unread sessions', () => {
    expect(C.channelHasUnread('slack', {}, mockChannelFn)).toBe(false)
  })

  it('returns false when unread sessions belong to a different channel', () => {
    const unread = { 'agent:main:discord:dm:x': true }
    expect(C.channelHasUnread('slack', unread, mockChannelFn)).toBe(false)
  })

  it('returns true when at least one of multiple unreads matches', () => {
    const unread = {
      'agent:main:discord:dm:x': true,
      'agent:main:slack:channel:c1': true,
    }
    expect(C.channelHasUnread('slack', unread, mockChannelFn)).toBe(true)
  })

  it('returns false for an empty unread map (no keys to iterate)', () => {
    expect(C.channelHasUnread('slack', {}, mockChannelFn)).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// breadcrumbText
// ---------------------------------------------------------------------------
describe('breadcrumbText', () => {
  const meta = [
    { id: 'ch1', label: 'General' },
    { id: 'ch2', label: 'Random' },
  ]

  it('returns "OpenClaw Chat" for the channels view', () => {
    expect(C.breadcrumbText('channels', 'ch1', '', meta)).toBe('OpenClaw Chat')
  })

  it('returns the channel label for the sessions view', () => {
    expect(C.breadcrumbText('sessions', 'ch1', '', meta)).toBe('General')
  })

  it('returns "channelLabel > sessionName" for the chat view', () => {
    expect(C.breadcrumbText('chat', 'ch2', 'agent:main:main', meta))
      .toBe('Random \u203A main')
  })

  it('returns "OpenClaw Chat" for an unknown viewMode', () => {
    expect(C.breadcrumbText('unknown', 'ch1', '', meta)).toBe('OpenClaw Chat')
  })

  it('uses channelMeta to look up the label in the breadcrumb', () => {
    const customMeta = [{ id: 'x', label: 'My Channel' }]
    expect(C.breadcrumbText('chat', 'x', 'agent:main:slack:user:john', customMeta))
      .toBe('My Channel \u203A user:john')
  })
})
