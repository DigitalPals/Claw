import { describe, it, expect } from 'vitest'
import { loadQmlLib } from './helpers/qml-loader.js'

const Ch = loadQmlLib('claw/lib/channels.js')

// ---------------------------------------------------------------------------
// resolveChannelIcon
// ---------------------------------------------------------------------------
describe('resolveChannelIcon', () => {
  it('returns terminal-2 for main channel', () => {
    expect(Ch.resolveChannelIcon('main')).toBe('terminal-2')
  })

  it('returns brand-slack for slack channel', () => {
    expect(Ch.resolveChannelIcon('slack')).toBe('brand-slack')
  })

  it('returns brand-discord for discord channel', () => {
    expect(Ch.resolveChannelIcon('discord')).toBe('brand-discord')
  })

  it('returns message-circle for unknown channel', () => {
    expect(Ch.resolveChannelIcon('unknown')).toBe('message-circle')
  })

  it('returns world for webchat', () => {
    expect(Ch.resolveChannelIcon('webchat')).toBe('world')
  })

  it('returns brand-twitter for x channel', () => {
    expect(Ch.resolveChannelIcon('x')).toBe('brand-twitter')
  })
})

// ---------------------------------------------------------------------------
// virtualChannelLabel
// ---------------------------------------------------------------------------
describe('virtualChannelLabel', () => {
  it('returns "Main (Direct)" for main', () => {
    expect(Ch.virtualChannelLabel('main')).toBe('Main (Direct)')
  })

  it('returns "Web Chat" for webchat', () => {
    expect(Ch.virtualChannelLabel('webchat')).toBe('Web Chat')
  })

  it('returns "Slack" for slack', () => {
    expect(Ch.virtualChannelLabel('slack')).toBe('Slack')
  })

  it('returns capitalized name for unknown channel type', () => {
    expect(Ch.virtualChannelLabel('custom')).toBe('Custom')
  })

  it('returns "X (Twitter)" for x', () => {
    expect(Ch.virtualChannelLabel('x')).toBe('X (Twitter)')
  })

  it('returns "Microsoft Teams" for teams', () => {
    expect(Ch.virtualChannelLabel('teams')).toBe('Microsoft Teams')
  })
})

// ---------------------------------------------------------------------------
// channelIconMap and channelLabelMap
// ---------------------------------------------------------------------------
describe('maps', () => {
  it('channelIconMap has entries for all channelLabelMap keys', () => {
    for (const key of Object.keys(Ch.channelLabelMap)) {
      expect(Ch.channelIconMap).toHaveProperty(key)
    }
  })

  it('channelIconMap has at least 20 entries', () => {
    expect(Object.keys(Ch.channelIconMap).length).toBeGreaterThanOrEqual(20)
  })
})
