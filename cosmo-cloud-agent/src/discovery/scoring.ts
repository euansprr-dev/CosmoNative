import type { NormalizedDiscoveredPost, SocialOutlierGrade } from './types';

export interface ScorePostInput {
  post: NormalizedDiscoveredPost;
  creatorRecentReach: number[];
  now?: Date;
}

export interface ScorePostResult {
  outlierScore: number | null;
  outlierGrade: SocialOutlierGrade;
  velocityScore: number;
  rankingScore: number;
}

function median(values: number[]): number | null {
  const sorted = values.filter(value => value > 0 && Number.isFinite(value)).sort((a, b) => a - b);
  if (sorted.length === 0) return null;
  const middle = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 1) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

function gradeFor(score: number | null): SocialOutlierGrade {
  if (score === null) return 'insufficient_data';
  if (score >= 20) return 'S';
  if (score >= 10) return 'A';
  if (score >= 5) return 'B';
  return 'C';
}

function postReach(post: NormalizedDiscoveredPost): number {
  return post.view_count ?? post.like_count ?? post.comment_count ?? post.repost_count ?? 0;
}

function ageHours(post: NormalizedDiscoveredPost, now: Date): number {
  if (!post.posted_at) return 24 * 365;
  const posted = new Date(post.posted_at).getTime();
  if (!Number.isFinite(posted)) return 24 * 365;
  return Math.max(1, (now.getTime() - posted) / 3_600_000);
}

export function scorePost(input: ScorePostInput): ScorePostResult {
  const now = input.now ?? new Date();
  const reach = postReach(input.post);
  const baseline = input.creatorRecentReach.length >= 5 ? median(input.creatorRecentReach) : null;
  const outlierScore = baseline && baseline > 0 ? Number((reach / baseline).toFixed(2)) : null;
  const outlierGrade = gradeFor(outlierScore);
  const velocityScore = Number((reach / ageHours(input.post, now)).toFixed(2));
  const engagementBoost = input.post.engagement_rate ? 1 + Math.min(input.post.engagement_rate, 0.25) : 1;
  const outlierBoost = outlierScore ? Math.log2(outlierScore + 1) : 1;
  const freshnessDecay = 1 / Math.sqrt(ageHours(input.post, now) / 24);
  const rankingScore = Number((velocityScore * outlierBoost * engagementBoost * freshnessDecay).toFixed(2));

  return {
    outlierScore,
    outlierGrade,
    velocityScore,
    rankingScore,
  };
}

export function applyScore(
  post: NormalizedDiscoveredPost,
  score: ScorePostResult
): NormalizedDiscoveredPost {
  return {
    ...post,
    outlier_score: score.outlierScore,
    outlier_grade: score.outlierGrade,
    velocity_score: score.velocityScore,
    ranking_score: score.rankingScore,
  };
}
