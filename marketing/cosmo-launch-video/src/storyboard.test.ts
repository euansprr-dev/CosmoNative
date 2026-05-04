import { describe, expect, it } from "vitest";
import {
  FPS,
  STORYBOARD,
  VIDEO_DURATION_FRAMES,
  getSceneById,
} from "./storyboard";

describe("Cosmo launch storyboard", () => {
  it("covers the requested launch narrative in a paced 75 second asset", () => {
    expect(FPS).toBe(30);
    expect(VIDEO_DURATION_FRAMES).toBe(2250);
    expect(STORYBOARD.map((scene) => scene.id)).toEqual([
      "hook",
      "capture",
      "thinkspace",
      "deep-dive",
      "command-center",
      "brain-map",
      "close",
    ]);
  });

  it("keeps every scene readable with explicit feature proof points", () => {
    for (const scene of STORYBOARD) {
      expect(scene.duration).toBeGreaterThanOrEqual(210);
      expect(scene.headline.length).toBeGreaterThan(0);
      expect(scene.proofPoints.length).toBeGreaterThanOrEqual(2);
    }

    expect(getSceneById("capture").proofPoints).toContain(
      "Telegram, links, voice notes, screenshots, and clips route themselves",
    );
    expect(getSceneById("thinkspace").proofPoints).toContain(
      "Clusters, tabs, and canvases keep context spatial instead of buried",
    );
    expect(getSceneById("deep-dive").proofPoints).toContain(
      "Inquiry sessions compound across days and map discoveries as you learn",
    );
    expect(getSceneById("command-center").proofPoints).toContain(
      "Tasks link to any atom in the database and carry live time tracking",
    );
  });

  it("has contiguous scene timing without gaps or overlaps", () => {
    let cursor = 0;

    for (const scene of STORYBOARD) {
      expect(scene.from).toBe(cursor);
      cursor += scene.duration;
    }

    expect(cursor).toBe(VIDEO_DURATION_FRAMES);
  });
});
