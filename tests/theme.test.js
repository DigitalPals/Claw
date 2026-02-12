import { describe, it, expect } from 'vitest'
import { loadQmlLib } from './helpers/qml-loader.js'

const T = loadQmlLib('claw/lib/theme.js')

// ---------------------------------------------------------------------------
// color constants
// ---------------------------------------------------------------------------
describe('color constants', () => {
  it('exports statusConnected as green', () => {
    expect(T.statusConnected).toBe('#4CAF50')
  })

  it('exports statusConnecting as orange', () => {
    expect(T.statusConnecting).toBe('#FFA726')
  })

  it('exports statusError as red', () => {
    expect(T.statusError).toBe('#F44336')
  })

  it('exports statusStreaming as light blue', () => {
    expect(T.statusStreaming).toBe('#4FC3F7')
  })

  it('exports primaryFallback as blue', () => {
    expect(T.primaryFallback).toBe('#2196F3')
  })
})

// ---------------------------------------------------------------------------
// connectionStatusColor
// ---------------------------------------------------------------------------
describe('connectionStatusColor', () => {
  const outline = '#808080'

  it('returns primary color when hasUnread is true and primary is defined', () => {
    expect(T.connectionStatusColor('connected', true, '#FF00FF', outline)).toBe('#FF00FF')
  })

  it('returns primaryFallback when hasUnread is true and primary is undefined', () => {
    expect(T.connectionStatusColor('connected', true, undefined, outline)).toBe('#2196F3')
  })

  it('returns statusConnected for connected state without unread', () => {
    expect(T.connectionStatusColor('connected', false, '#FF00FF', outline)).toBe('#4CAF50')
  })

  it('returns statusConnecting for connecting state', () => {
    expect(T.connectionStatusColor('connecting', false, '#FF00FF', outline)).toBe('#FFA726')
  })

  it('returns statusError for error state', () => {
    expect(T.connectionStatusColor('error', false, '#FF00FF', outline)).toBe('#F44336')
  })

  it('returns outline color for idle state', () => {
    expect(T.connectionStatusColor('idle', false, '#FF00FF', outline)).toBe(outline)
  })

  it('prioritizes hasUnread over connection state', () => {
    expect(T.connectionStatusColor('error', true, '#FF00FF', outline)).toBe('#FF00FF')
  })
})
