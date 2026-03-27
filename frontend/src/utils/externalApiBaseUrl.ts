const trimTrailingSlash = (value: string): string => value.replace(/\/+$/, '')

interface ResolveExternalApiBaseUrlOptions {
  isDev?: boolean
  devProxyTarget?: string
  fallbackOrigin?: string
}

export function resolveExternalApiBaseUrl(
  configuredBaseUrl?: string | null,
  options: ResolveExternalApiBaseUrlOptions = {}
): string {
  const configured = configuredBaseUrl?.trim()
  if (configured) {
    return trimTrailingSlash(configured)
  }

  const isDev = options.isDev ?? import.meta.env.DEV
  if (isDev) {
    const devProxyTarget =
      options.devProxyTarget?.trim() || import.meta.env.VITE_DEV_PROXY_TARGET?.trim() || 'http://localhost:8080'
    return trimTrailingSlash(devProxyTarget)
  }

  const fallbackOrigin =
    options.fallbackOrigin?.trim() ||
    (typeof window !== 'undefined' ? window.location.origin : '').trim()

  return fallbackOrigin ? trimTrailingSlash(fallbackOrigin) : ''
}
