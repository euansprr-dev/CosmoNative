// cosmo-cloud-agent/src/swipes/http.ts
// Small shared helpers for outbound HTTP in the swipe pipeline.

export function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Node's `fetch` reports every transport failure as a bare
 * `TypeError: fetch failed` and hides the real reason (ECONNRESET,
 * ENETUNREACH, certificate errors, an AggregateError per address…) in
 * `error.cause`. Six days of "carousel slide 0 mirror failed: fetch failed"
 * in the Railway log told us nothing — this digs the cause out so the next
 * outage is diagnosable from the log alone.
 */
export function describeFetchError(error: unknown): string {
  if (!(error instanceof Error)) return String(error);
  const parts: string[] = [];
  if (error.name === 'TimeoutError' || error.name === 'AbortError') {
    parts.push('timeout');
  } else {
    parts.push(error.message);
  }
  const cause = (error as Error & { cause?: unknown }).cause as
    | { code?: string; errno?: number; message?: string; errors?: Array<{ code?: string; address?: string }> }
    | undefined;
  if (cause) {
    if (cause.code) parts.push(cause.code);
    else if (cause.message) parts.push(cause.message);
    if (Array.isArray(cause.errors) && cause.errors.length > 0) {
      parts.push(cause.errors.map(e => `${e.code ?? '?'}@${e.address ?? '?'}`).join(','));
    }
  }
  return parts.join(' / ');
}

/** Hostname of a URL, or the raw string when it does not parse. */
export function hostOf(url: string): string {
  try {
    return new URL(url).hostname;
  } catch {
    return url;
  }
}
