export const FPS = 30;
export const VIDEO_DURATION_FRAMES = 2250;

export type SceneId =
  | "hook"
  | "capture"
  | "thinkspace"
  | "deep-dive"
  | "command-center"
  | "brain-map"
  | "close";

export type StoryScene = {
  id: SceneId;
  from: number;
  duration: number;
  eyebrow: string;
  headline: string;
  subline: string;
  proofPoints: string[];
  accent: string;
};

export const STORYBOARD: StoryScene[] = [
  {
    id: "hook",
    from: 0,
    duration: 240,
    eyebrow: "Cosmo launch film",
    headline: "Your knowledge app should not think in folders.",
    subline:
      "Cosmo is the first fully fledged knowledge management tool that maps to your brain.",
    proofPoints: [
      "Capture, learning, planning, and execution happen in one living system",
      "Ideas stay connected to the context that created them",
    ],
    accent: "#70f7d4",
  },
  {
    id: "capture",
    from: 240,
    duration: 330,
    eyebrow: "Capture from anywhere",
    headline: "Send anything from Telegram. Cosmo routes it automatically.",
    subline:
      "A clip, thought, link, screenshot, or voice note becomes structured knowledge before you get back to your desk.",
    proofPoints: [
      "Telegram, links, voice notes, screenshots, and clips route themselves",
      "Inbox lanes, canvases, tasks, and research atoms are chosen by context",
      "Your phone becomes a capture remote for the whole OS",
    ],
    accent: "#7cb7ff",
  },
  {
    id: "thinkspace",
    from: 570,
    duration: 360,
    eyebrow: "Canvas and Thinkspace",
    headline: "The canvas clusters itself around how you actually think.",
    subline:
      "Tabs, clusters, and spatial blocks turn messy inputs into a working mental map.",
    proofPoints: [
      "Clusters, tabs, and canvases keep context spatial instead of buried",
      "Switch between canvas, board, list, and focus tabs without losing the map",
      "Every block remains an object in the database, not a dead note",
    ],
    accent: "#ffc766",
  },
  {
    id: "deep-dive",
    from: 930,
    duration: 360,
    eyebrow: "Deep Dive mode",
    headline: "Learn anything through inquiry sessions that compound.",
    subline:
      "Each session adds questions, sources, claims, and decisions back to the canvas.",
    proofPoints: [
      "Inquiry sessions compound across days and map discoveries as you learn",
      "Follow-up sessions inherit the context instead of starting over",
      "The canvas grows from curiosity into a reusable knowledge model",
    ],
    accent: "#c697ff",
  },
  {
    id: "command-center",
    from: 1290,
    duration: 330,
    eyebrow: "Command Center",
    headline: "Turn knowledge into action without breaking context.",
    subline:
      "Tasks can link to anything in the database, carry their source context, and track the time you spend.",
    proofPoints: [
      "Tasks link to any atom in the database and carry live time tracking",
      "Command search reaches ideas, captures, research, canvases, and projects",
      "Execution keeps a trail back to the thought that started it",
    ],
    accent: "#ff7d9b",
  },
  {
    id: "brain-map",
    from: 1620,
    duration: 330,
    eyebrow: "Not another file system",
    headline: "Cosmo maps relationships, not folders.",
    subline:
      "The system understands clusters, sessions, tasks, projects, swipes, voice, and calendar context as one graph.",
    proofPoints: [
      "Local-first semantic search keeps every atom reachable",
      "Voice, calendar, swipes, writing, and research all share the same graph",
      "The more you use it, the more your workspace starts to mirror your mind",
    ],
    accent: "#62e5ff",
  },
  {
    id: "close",
    from: 1950,
    duration: 300,
    eyebrow: "Cosmo",
    headline: "A knowledge OS for brains. Not folders.",
    subline:
      "Capture everything. Learn deeply. Map the connections. Execute with context.",
    proofPoints: [
      "Phone to graph",
      "Canvas to inquiry",
      "Task to timer",
      "Everything connected",
    ],
    accent: "#f4ff7a",
  },
];

export const getSceneById = (id: SceneId): StoryScene => {
  const scene = STORYBOARD.find((candidate) => candidate.id === id);

  if (!scene) {
    throw new Error(`Missing Cosmo launch scene: ${id}`);
  }

  return scene;
};
