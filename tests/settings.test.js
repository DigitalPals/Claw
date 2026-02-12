import { describe, it, expect } from 'vitest'
import { loadQmlLib } from './helpers/qml-loader.js'

const S = loadQmlLib('claw/lib/settings.js')

// ---------------------------------------------------------------------------
// pickSetting
// ---------------------------------------------------------------------------
describe('pickSetting', () => {
  it('returns pluginSettings value when present', () => {
    const api = { pluginSettings: { wsUrl: 'ws://custom:9999' } }
    expect(S.pickSetting(api, 'wsUrl', 'ws://default')).toBe('ws://custom:9999')
  })

  it('returns manifest defaultSettings value when pluginSettings lacks the key', () => {
    const api = {
      pluginSettings: {},
      manifest: { metadata: { defaultSettings: { wsUrl: 'ws://manifest' } } }
    }
    expect(S.pickSetting(api, 'wsUrl', 'ws://fallback')).toBe('ws://manifest')
  })

  it('returns fallback when both pluginSettings and manifest lack the key', () => {
    const api = { pluginSettings: {}, manifest: { metadata: { defaultSettings: {} } } }
    expect(S.pickSetting(api, 'wsUrl', 'ws://fallback')).toBe('ws://fallback')
  })

  it('returns fallback when pluginApi is null', () => {
    expect(S.pickSetting(null, 'wsUrl', 'ws://fallback')).toBe('ws://fallback')
  })

  it('returns fallback when pluginApi is undefined', () => {
    expect(S.pickSetting(undefined, 'token', 'default-token')).toBe('default-token')
  })

  it('prefers pluginSettings over manifest defaultSettings', () => {
    const api = {
      pluginSettings: { token: 'from-settings' },
      manifest: { metadata: { defaultSettings: { token: 'from-manifest' } } }
    }
    expect(S.pickSetting(api, 'token', 'fallback')).toBe('from-settings')
  })

  it('returns fallback when manifest has no metadata', () => {
    const api = { pluginSettings: {}, manifest: {} }
    expect(S.pickSetting(api, 'token', 'fb')).toBe('fb')
  })

  it('handles boolean values correctly (false is not undefined)', () => {
    const api = { pluginSettings: { autoReconnect: false } }
    expect(S.pickSetting(api, 'autoReconnect', true)).toBe(false)
  })
})

// ---------------------------------------------------------------------------
// loadEditableSettings
// ---------------------------------------------------------------------------
describe('loadEditableSettings', () => {
  it('returns all default values when pluginApi is null', () => {
    const result = S.loadEditableSettings(null)
    expect(result).toEqual({
      wsUrl: 'ws://127.0.0.1:18789',
      token: '',
      agentId: 'main',
      autoReconnect: true,
      notifyOnResponse: true,
      notifyOnlyWhenAppInactive: true
    })
  })

  it('reads values from pluginSettings', () => {
    const api = {
      pluginSettings: {
        wsUrl: 'ws://custom:1234',
        token: 'secret',
        agentId: 'bot',
        autoReconnect: false,
        notifyOnResponse: false,
        notifyOnlyWhenAppInactive: false
      }
    }
    const result = S.loadEditableSettings(api)
    expect(result).toEqual({
      wsUrl: 'ws://custom:1234',
      token: 'secret',
      agentId: 'bot',
      autoReconnect: false,
      notifyOnResponse: false,
      notifyOnlyWhenAppInactive: false
    })
  })

  it('coerces boolean settings to actual booleans', () => {
    const api = { pluginSettings: { autoReconnect: 1, notifyOnResponse: 0, notifyOnlyWhenAppInactive: '' } }
    const result = S.loadEditableSettings(api)
    expect(result.autoReconnect).toBe(true)
    expect(result.notifyOnResponse).toBe(false)
    expect(result.notifyOnlyWhenAppInactive).toBe(false)
  })
})
