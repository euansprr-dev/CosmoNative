// cosmo-cloud-agent/src/swipes/progress.ts
// Live per-swipe progress for the clients' progress bars. In-memory on
// purpose: progress is ephemeral UI state, not data — polling clients fall
// back to status-based estimates when the worker restarts mid-swipe.
//
// Checkpoint fractions mirror where wall-clock time actually goes for a
// typical reel (Apify run ~40%, media+transcription ~40%, analysis ~15%).

export interface SwipeProgress {
  stage: string;      // extracting | transcribing | analyzing | complete
  progress: number;   // 0..1, monotonically non-decreasing per swipe
  updatedAt: number;  // epoch ms
}

const progressMap = new Map<string, SwipeProgress>();
const TTL_MS = 15 * 60_000;

export function setProgress(uuid: string, stage: string, progress: number): void {
  const existing = progressMap.get(uuid);
  const clamped = Math.min(Math.max(progress, 0), 1);
  progressMap.set(uuid, {
    stage,
    // Never move backwards — a bar that retreats reads as a failure.
    progress: existing ? Math.max(existing.progress, clamped) : clamped,
    updatedAt: Date.now(),
  });
  if (progressMap.size > 200) pruneStale();
}

export function getProgress(uuid: string): SwipeProgress | null {
  const entry = progressMap.get(uuid);
  if (!entry) return null;
  if (Date.now() - entry.updatedAt > TTL_MS) {
    progressMap.delete(uuid);
    return null;
  }
  return entry;
}

export function clearProgress(uuid: string): void {
  progressMap.delete(uuid);
}

function pruneStale(): void {
  const cutoff = Date.now() - TTL_MS;
  for (const [uuid, entry] of progressMap) {
    if (entry.updatedAt < cutoff) progressMap.delete(uuid);
  }
}
