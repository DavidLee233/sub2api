import { describe, expect, it } from 'vitest'
import { resolveExternalApiBaseUrl } from '@/utils/externalApiBaseUrl'

describe('resolveExternalApiBaseUrl', () => {
  it('prefers configured public api base url', () => {
    expect(
      resolveExternalApiBaseUrl('http://127.0.0.1:8080/', {
        isDev: true,
        devProxyTarget: 'http://localhost:8080',
        fallbackOrigin: 'http://127.0.0.1:3000'
      })
    ).toBe('http://127.0.0.1:8080')
  })

  it('falls back to vite dev proxy target in dev mode', () => {
    expect(
      resolveExternalApiBaseUrl('', {
        isDev: true,
        devProxyTarget: 'http://127.0.0.1:8080/',
        fallbackOrigin: 'http://127.0.0.1:3000'
      })
    ).toBe('http://127.0.0.1:8080')
  })

  it('falls back to current origin outside dev mode', () => {
    expect(
      resolveExternalApiBaseUrl('', {
        isDev: false,
        fallbackOrigin: 'https://api.example.com/'
      })
    ).toBe('https://api.example.com')
  })
})
