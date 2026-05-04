import type { CSSProperties, ReactNode } from "react";
import {
  AbsoluteFill,
  Easing,
  interpolate,
  Sequence,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Audio } from "@remotion/media";
import { STORYBOARD, type StoryScene } from "./storyboard";

const ease = Easing.bezier(0.16, 1, 0.3, 1);

const clamp = {
  extrapolateLeft: "clamp",
  extrapolateRight: "clamp",
} as const;

const copyMaxWidth = 760;

const visualForScene = (scene: StoryScene): ReactNode => {
  switch (scene.id) {
    case "hook":
      return <HookVisual accent={scene.accent} />;
    case "capture":
      return <CaptureVisual accent={scene.accent} />;
    case "thinkspace":
      return <ThinkspaceVisual accent={scene.accent} />;
    case "deep-dive":
      return <DeepDiveVisual accent={scene.accent} />;
    case "command-center":
      return <CommandCenterVisual accent={scene.accent} />;
    case "brain-map":
      return <BrainMapVisual accent={scene.accent} />;
    case "close":
      return <CloseVisual accent={scene.accent} />;
  }
};

export const CosmoLaunchVideo = () => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  const audioVolume = (audioFrame: number) =>
    interpolate(
      audioFrame,
      [0, 40, durationInFrames - 90, durationInFrames],
      [0, 0.42, 0.42, 0],
      clamp,
    );

  return (
    <AbsoluteFill style={styles.stage}>
      <Audio src={staticFile("audio/cosmo-pulse.wav")} volume={audioVolume} />
      <AmbientField frame={frame} />
      <ProgressRail frame={frame} />
      {STORYBOARD.map((scene) => (
        <Sequence
          key={scene.id}
          from={scene.from}
          durationInFrames={scene.duration}
          premountFor={30}
        >
          <LaunchScene scene={scene}>{visualForScene(scene)}</LaunchScene>
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

const LaunchScene = ({
  scene,
  children,
}: {
  scene: StoryScene;
  children: ReactNode;
}) => {
  const frame = useCurrentFrame();
  const entrance = interpolate(frame, [0, 36], [0, 1], {
    ...clamp,
    easing: ease,
  });
  const exit = interpolate(
    frame,
    [scene.duration - 54, scene.duration],
    [1, 0],
    clamp,
  );
  const opacity = entrance * exit;
  const copyShift = interpolate(frame, [0, 42], [42, 0], {
    ...clamp,
    easing: ease,
  });

  return (
    <AbsoluteFill style={{ ...styles.scene, opacity }}>
      <div style={styles.copyColumn}>
        <div style={{ ...styles.eyebrow, color: scene.accent }}>
          {scene.eyebrow}
        </div>
        <h1
          style={{
            ...styles.headline,
            transform: `translateY(${copyShift}px)`,
          }}
        >
          {scene.headline}
        </h1>
        <p style={styles.subline}>{scene.subline}</p>
        <ProofList scene={scene} />
      </div>
      <div style={styles.visualColumn}>{children}</div>
    </AbsoluteFill>
  );
};

const ProofList = ({ scene }: { scene: StoryScene }) => {
  const frame = useCurrentFrame();

  return (
    <div style={styles.proofList}>
      {scene.proofPoints.map((point, index) => {
        const reveal = interpolate(
          frame,
          [38 + index * 20, 66 + index * 20],
          [0, 1],
          {
            ...clamp,
            easing: ease,
          },
        );

        return (
          <div
            key={point}
            style={{
              ...styles.proofItem,
              borderColor: `${scene.accent}66`,
              opacity: reveal,
              transform: `translateX(${interpolate(reveal, [0, 1], [-22, 0])}px)`,
            }}
          >
            <span
              style={{
                ...styles.proofDot,
                background: scene.accent,
              }}
            />
            <span>{point}</span>
          </div>
        );
      })}
    </div>
  );
};

const AmbientField = ({ frame }: { frame: number }) => {
  const drift = frame * 0.16;
  const pulse = interpolate(
    Math.sin(frame / 36),
    [-1, 1],
    [0.55, 0.95],
    clamp,
  );

  return (
    <AbsoluteFill style={styles.ambient}>
      <div
        style={{
          ...styles.grid,
          transform: `translate3d(${-drift % 52}px, ${-drift % 52}px, 0)`,
        }}
      />
      <div
        style={{
          ...styles.radialGlow,
          opacity: pulse,
        }}
      />
      {Array.from({ length: 26 }).map((_, index) => {
        const x = 7 + ((index * 37) % 88);
        const y = 8 + ((index * 53) % 84);
        const float = Math.sin(frame / 24 + index) * 7;

        return (
          <div
            key={index}
            style={{
              ...styles.star,
              left: `${x}%`,
              top: `${y}%`,
              opacity: 0.22 + ((index % 5) * 0.06),
              transform: `translateY(${float}px)`,
            }}
          />
        );
      })}
    </AbsoluteFill>
  );
};

const ProgressRail = ({ frame }: { frame: number }) => {
  const { durationInFrames } = useVideoConfig();
  const progress = interpolate(frame, [0, durationInFrames], [0, 100], clamp);
  const activeIndex = STORYBOARD.findIndex(
    (scene) => frame >= scene.from && frame < scene.from + scene.duration,
  );

  return (
    <div style={styles.progressShell}>
      <div style={styles.progressTrack}>
        <div style={{ ...styles.progressFill, width: `${progress}%` }} />
      </div>
      <div style={styles.progressLabels}>
        {STORYBOARD.map((scene, index) => (
          <span
            key={scene.id}
            style={{
              ...styles.progressLabel,
              color: index === activeIndex ? scene.accent : "rgba(244,246,240,0.5)",
            }}
          >
            {scene.id.replace("-", " ")}
          </span>
        ))}
      </div>
    </div>
  );
};

const HookVisual = ({ accent }: { accent: string }) => {
  const frame = useCurrentFrame();
  const graphReveal = interpolate(frame, [26, 106], [0, 1], {
    ...clamp,
    easing: ease,
  });
  const folderFade = interpolate(frame, [0, 78], [1, 0.2], clamp);
  const nodes = [
    ["Phone capture", 19, 26],
    ["Canvas", 67, 23],
    ["Inquiry", 78, 58],
    ["Tasks", 32, 74],
    ["Voice", 52, 10],
    ["Swipes", 12, 58],
  ] as const;

  return (
    <div style={styles.heroGraph}>
      <div style={{ ...styles.folderStack, opacity: folderFade }}>
        {["Ideas", "Tasks", "Research", "Links"].map((name, index) => (
          <div
            key={name}
            style={{
              ...styles.folderCard,
              transform: `translate(${index * 18}px, ${index * 26}px) rotate(${-3 + index}deg)`,
            }}
          >
            <span>{name}</span>
            <div style={styles.folderLine} />
            <div style={{ ...styles.folderLine, width: "61%" }} />
          </div>
        ))}
      </div>
      <div
        style={{
          ...styles.centralOrb,
          borderColor: `${accent}88`,
          boxShadow: `0 0 90px ${accent}55`,
          transform: `scale(${interpolate(graphReveal, [0, 1], [0.82, 1])})`,
        }}
      >
        <span>Cosmo</span>
      </div>
      {nodes.map(([label, x, y], index) => {
        const reveal = interpolate(
          graphReveal,
          [0.15 + index * 0.05, 0.72 + index * 0.03],
          [0, 1],
          clamp,
        );

        return (
          <div
            key={label}
            style={{
              ...styles.graphNode,
              left: `${x}%`,
              top: `${y}%`,
              borderColor: `${accent}88`,
              opacity: reveal,
              transform: `scale(${interpolate(reveal, [0, 1], [0.78, 1])})`,
            }}
          >
            {label}
          </div>
        );
      })}
      <GraphLine x1={50} y1={50} x2={19} y2={26} accent={accent} progress={graphReveal} />
      <GraphLine x1={50} y1={50} x2={67} y2={23} accent={accent} progress={graphReveal} />
      <GraphLine x1={50} y1={50} x2={78} y2={58} accent={accent} progress={graphReveal} />
      <GraphLine x1={50} y1={50} x2={32} y2={74} accent={accent} progress={graphReveal} />
      <GraphLine x1={50} y1={50} x2={12} y2={58} accent={accent} progress={graphReveal} />
      <GraphLine x1={50} y1={50} x2={52} y2={10} accent={accent} progress={graphReveal} />
    </div>
  );
};

const CaptureVisual = ({ accent }: { accent: string }) => {
  const frame = useCurrentFrame();
  const route = interpolate(frame, [48, 146], [0, 1], {
    ...clamp,
    easing: ease,
  });
  const messages = [
    "https://x.com/thread",
    "Voice: idea for launch angle",
    "Screenshot: pricing model",
    "Clip: retention teardown",
  ];
  const lanes = ["Inbox", "Canvas", "Research", "Task"];

  return (
    <div style={styles.captureLayout}>
      <div style={styles.phone}>
        <div style={styles.phoneNotch} />
        <div style={styles.telegramHeader}>Telegram to Cosmo</div>
        {messages.map((message, index) => {
          const reveal = interpolate(
            frame,
            [12 + index * 16, 46 + index * 16],
            [0, 1],
            {
              ...clamp,
              easing: ease,
            },
          );

          return (
            <div
              key={message}
              style={{
                ...styles.chatBubble,
                opacity: reveal,
                transform: `translateY(${interpolate(reveal, [0, 1], [18, 0])}px)`,
              }}
            >
              {message}
            </div>
          );
        })}
        <div style={{ ...styles.sendBar, borderColor: `${accent}55` }}>
          Send to Cosmo
        </div>
      </div>
      <div style={styles.routerPanel}>
        <div style={{ ...styles.routerCore, borderColor: `${accent}99` }}>
          Auto-router
        </div>
        <div style={styles.routeStack}>
          {lanes.map((lane, index) => {
            const laneReveal = interpolate(
              route,
              [index * 0.12, 0.55 + index * 0.1],
              [0, 1],
              clamp,
            );

            return (
              <div
                key={lane}
                style={{
                  ...styles.routeLane,
                  borderColor: `${accent}66`,
                  opacity: laneReveal,
                  transform: `translateX(${interpolate(laneReveal, [0, 1], [32, 0])}px)`,
                }}
              >
                <span style={{ ...styles.routePill, background: accent }} />
                {lane}
              </div>
            );
          })}
        </div>
      </div>
      {[0, 1, 2, 3].map((index) => (
        <MovingPacket
          key={index}
          accent={accent}
          progress={interpolate(frame, [62 + index * 18, 132 + index * 18], [0, 1], clamp)}
          y={26 + index * 14}
        />
      ))}
    </div>
  );
};

const ThinkspaceVisual = ({ accent }: { accent: string }) => {
  const frame = useCurrentFrame();
  const blocks = [
    ["Hook bank", 10, 20, "#70f7d4"],
    ["Audience pains", 38, 16, "#ffc766"],
    ["Pricing notes", 66, 22, "#ff7d9b"],
    ["Research clips", 18, 58, "#7cb7ff"],
    ["Launch tasks", 54, 62, "#c697ff"],
    ["Positioning", 78, 54, "#f4ff7a"],
  ] as const;
  const tabs = ["Canvas", "Board", "List", "Focus"];
  const activeTab = Math.min(3, Math.floor(frame / 78));

  return (
    <div style={styles.canvasPanel}>
      <div style={styles.tabBar}>
        {tabs.map((tab, index) => (
          <div
            key={tab}
            style={{
              ...styles.tab,
              background: activeTab === index ? `${accent}22` : "rgba(255,255,255,0.05)",
              borderColor: activeTab === index ? `${accent}aa` : "rgba(255,255,255,0.11)",
              color: activeTab === index ? "#ffffff" : "rgba(245,246,240,0.62)",
            }}
          >
            {tab}
          </div>
        ))}
      </div>
      <div style={styles.clusterCanvas}>
        <ClusterFrame
          accent="#70f7d4"
          label="Messaging cluster"
          x={5}
          y={12}
          width={44}
          height={44}
          reveal={interpolate(frame, [20, 78], [0, 1], clamp)}
        />
        <ClusterFrame
          accent="#ffc766"
          label="Launch execution"
          x={45}
          y={39}
          width={49}
          height={42}
          reveal={interpolate(frame, [60, 128], [0, 1], clamp)}
        />
        {blocks.map(([label, x, y, color], index) => {
          const reveal = interpolate(
            frame,
            [18 + index * 18, 74 + index * 18],
            [0, 1],
            {
              ...clamp,
              easing: ease,
            },
          );
          const float = Math.sin(frame / 18 + index) * 6;

          return (
            <div
              key={label}
              style={{
                ...styles.canvasBlock,
                left: `${x}%`,
                top: `${y}%`,
                borderColor: `${color}99`,
                opacity: reveal,
                transform: `translateY(${float}px) scale(${interpolate(reveal, [0, 1], [0.82, 1])})`,
              }}
            >
              <span style={{ ...styles.blockDot, background: color }} />
              {label}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const DeepDiveVisual = ({ accent }: { accent: string }) => {
  const frame = useCurrentFrame();
  const sessions = ["Session 01", "Session 02", "Session 03"];
  const inquiryItems = [
    "What makes knowledge stick?",
    "Evidence from cognitive maps",
    "Pattern: spatial recall beats lists",
    "Decision: canvas-first onboarding",
  ];

  return (
    <div style={styles.deepDivePanel}>
      <div style={styles.sessionRail}>
        {sessions.map((session, index) => {
          const active = frame > 42 + index * 78;

          return (
            <div
              key={session}
              style={{
                ...styles.sessionChip,
                borderColor: active ? `${accent}aa` : "rgba(255,255,255,0.13)",
                background: active ? `${accent}20` : "rgba(255,255,255,0.04)",
              }}
            >
              <span style={{ color: active ? accent : "rgba(255,255,255,0.45)" }}>
                {session}
              </span>
              <small>{active ? "mapped" : "queued"}</small>
            </div>
          );
        })}
      </div>
      <div style={styles.inquiryWindow}>
        <div style={styles.inquiryTitle}>Deep Dive: Learn retention systems</div>
        {inquiryItems.map((item, index) => {
          const reveal = interpolate(
            frame,
            [18 + index * 40, 58 + index * 40],
            [0, 1],
            {
              ...clamp,
              easing: ease,
            },
          );

          return (
            <div
              key={item}
              style={{
                ...styles.inquiryRow,
                opacity: reveal,
                transform: `translateY(${interpolate(reveal, [0, 1], [18, 0])}px)`,
              }}
            >
              <span style={{ ...styles.inquiryIcon, borderColor: accent }} />
              {item}
            </div>
          );
        })}
      </div>
      <div style={styles.mapPreview}>
        {["Question", "Source", "Claim", "Model", "Next session"].map((label, index) => {
          const reveal = interpolate(frame, [88 + index * 24, 148 + index * 24], [0, 1], clamp);
          const positions = [
            [44, 12],
            [18, 36],
            [67, 34],
            [40, 58],
            [72, 72],
          ];

          return (
            <div
              key={label}
              style={{
                ...styles.mapNode,
                left: `${positions[index][0]}%`,
                top: `${positions[index][1]}%`,
                borderColor: `${accent}88`,
                opacity: reveal,
              }}
            >
              {label}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const CommandCenterVisual = ({ accent }: { accent: string }) => {
  const frame = useCurrentFrame();
  const timerSeconds = Math.floor(interpolate(frame, [40, 260], [0, 28], clamp));
  const commandText = "Link task to launch canvas + start timer";
  const typedChars = Math.floor(interpolate(frame, [16, 104], [0, commandText.length], clamp));
  const links = ["TG capture", "Deep Dive", "Launch canvas", "Calendar"];

  return (
    <div style={styles.commandPanel}>
      <div style={{ ...styles.commandBar, borderColor: `${accent}88` }}>
        <span style={{ color: accent }}>⌘</span>
        {commandText.slice(0, typedChars)}
        <span style={styles.cursor}>|</span>
      </div>
      <div style={styles.commandBody}>
        <div style={styles.taskCard}>
          <div style={styles.taskHeader}>
            <span>Task</span>
            <strong>Write Cosmo launch narrative</strong>
          </div>
          <div style={styles.timer}>
            {`00:${timerSeconds.toString().padStart(2, "0")}`}
            <span style={styles.timerLabel}>tracked in context</span>
          </div>
          <div style={styles.linkGrid}>
            {links.map((link, index) => {
              const reveal = interpolate(frame, [70 + index * 18, 112 + index * 18], [0, 1], clamp);

              return (
                <div
                  key={link}
                  style={{
                    ...styles.linkChip,
                    borderColor: `${accent}66`,
                    opacity: reveal,
                  }}
                >
                  {link}
                </div>
              );
            })}
          </div>
        </div>
        <div style={styles.dbPanel}>
          {["atom: idea", "atom: clip", "atom: canvas", "atom: session"].map((atom, index) => (
            <div
              key={atom}
              style={{
                ...styles.dbRow,
                opacity: interpolate(frame, [96 + index * 18, 142 + index * 18], [0, 1], clamp),
              }}
            >
              <span style={{ background: index % 2 === 0 ? accent : "#70f7d4" }} />
              {atom}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};

const BrainMapVisual = ({ accent }: { accent: string }) => {
  const frame = useCurrentFrame();
  const reveal = interpolate(frame, [44, 142], [0, 1], {
    ...clamp,
    easing: ease,
  });
  const graphLabels = ["Voice", "Swipes", "Research", "Tasks", "Calendar", "Writing"];

  return (
    <div style={styles.comparePanel}>
      <div style={styles.fileSystem}>
        <div style={styles.compareTitle}>Old way</div>
        {["/notes", "/projects", "/screenshots", "/tasks"].map((folder, index) => (
          <div
            key={folder}
            style={{
              ...styles.fileRow,
              opacity: 0.78 - index * 0.12,
              transform: `translateX(${index * 14}px)`,
            }}
          >
            <span>▣</span>
            {folder}
          </div>
        ))}
      </div>
      <div style={styles.brainGraph}>
        <div style={styles.compareTitle}>Cosmo</div>
        <div
          style={{
            ...styles.brainCore,
            borderColor: `${accent}aa`,
            boxShadow: `0 0 74px ${accent}44`,
          }}
        >
          Brain map
        </div>
        {graphLabels.map((label, index) => {
          const angle = (Math.PI * 2 * index) / graphLabels.length - Math.PI / 2;
          const x = 50 + Math.cos(angle) * 34;
          const y = 51 + Math.sin(angle) * 32;
          const nodeReveal = interpolate(
            reveal,
            [index * 0.08, 0.72 + index * 0.04],
            [0, 1],
            clamp,
          );

          return (
            <div
              key={label}
              style={{
                ...styles.brainNode,
                left: `${x}%`,
                top: `${y}%`,
                borderColor: `${accent}77`,
                opacity: nodeReveal,
              }}
            >
              {label}
            </div>
          );
        })}
      </div>
    </div>
  );
};

const CloseVisual = ({ accent }: { accent: string }) => {
  const frame = useCurrentFrame();
  const ring = interpolate(frame, [0, 120], [0.72, 1], {
    ...clamp,
    easing: ease,
  });
  const capsules = ["Phone to graph", "Canvas to inquiry", "Task to timer", "Everything connected"];

  return (
    <div style={styles.closeVisual}>
      <div
        style={{
          ...styles.closeRing,
          borderColor: `${accent}77`,
          transform: `scale(${ring})`,
          boxShadow: `0 0 120px ${accent}35`,
        }}
      >
        <div style={styles.closeMark}>COSMO</div>
      </div>
      <div style={styles.closeCapsules}>
        {capsules.map((capsule, index) => (
          <div
            key={capsule}
            style={{
              ...styles.closeCapsule,
              borderColor: `${accent}66`,
              opacity: interpolate(frame, [54 + index * 22, 102 + index * 22], [0, 1], clamp),
            }}
          >
            {capsule}
          </div>
        ))}
      </div>
    </div>
  );
};

const GraphLine = ({
  x1,
  y1,
  x2,
  y2,
  accent,
  progress,
}: {
  x1: number;
  y1: number;
  x2: number;
  y2: number;
  accent: string;
  progress: number;
}) => {
  const width = Math.hypot(x2 - x1, y2 - y1);
  const angle = Math.atan2(y2 - y1, x2 - x1);

  return (
    <div
      style={{
        ...styles.graphLine,
        left: `${x1}%`,
        top: `${y1}%`,
        width: `${width * progress}%`,
        background: `linear-gradient(90deg, ${accent}, rgba(255,255,255,0))`,
        transform: `rotate(${angle}rad)`,
      }}
    />
  );
};

const MovingPacket = ({
  accent,
  progress,
  y,
}: {
  accent: string;
  progress: number;
  y: number;
}) => (
  <div
    style={{
      ...styles.packet,
      left: `${interpolate(progress, [0, 1], [35, 61])}%`,
      top: `${y}%`,
      opacity: interpolate(progress, [0, 0.15, 0.85, 1], [0, 1, 1, 0], clamp),
      background: accent,
    }}
  />
);

const ClusterFrame = ({
  accent,
  label,
  x,
  y,
  width,
  height,
  reveal,
}: {
  accent: string;
  label: string;
  x: number;
  y: number;
  width: number;
  height: number;
  reveal: number;
}) => (
  <div
    style={{
      ...styles.clusterFrame,
      left: `${x}%`,
      top: `${y}%`,
      width: `${width}%`,
      height: `${height}%`,
      borderColor: `${accent}66`,
      opacity: reveal,
    }}
  >
    <span style={{ color: accent }}>{label}</span>
  </div>
);

const styles: Record<string, CSSProperties> = {
  stage: {
    background: "#090a0a",
    color: "#f7f8f0",
    fontFamily:
      'Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "SF Pro Display", sans-serif',
    overflow: "hidden",
  },
  ambient: {
    opacity: 0.85,
  },
  grid: {
    position: "absolute",
    inset: "-10%",
    backgroundImage:
      "linear-gradient(rgba(255,255,255,0.035) 1px, transparent 1px), linear-gradient(90deg, rgba(255,255,255,0.035) 1px, transparent 1px)",
    backgroundSize: "52px 52px",
  },
  radialGlow: {
    position: "absolute",
    inset: "-20%",
    background:
      "radial-gradient(circle at 72% 40%, rgba(112,247,212,0.18), transparent 28%), radial-gradient(circle at 36% 68%, rgba(255,199,102,0.14), transparent 28%), radial-gradient(circle at 52% 14%, rgba(198,151,255,0.16), transparent 24%)",
  },
  star: {
    position: "absolute",
    width: 5,
    height: 5,
    borderRadius: 999,
    background: "#f7f8f0",
    boxShadow: "0 0 18px rgba(255,255,255,0.8)",
  },
  progressShell: {
    position: "absolute",
    top: 44,
    left: 80,
    right: 80,
    zIndex: 5,
  },
  progressTrack: {
    height: 3,
    background: "rgba(255,255,255,0.13)",
    overflow: "hidden",
  },
  progressFill: {
    height: "100%",
    background: "linear-gradient(90deg, #70f7d4, #ffc766, #ff7d9b, #f4ff7a)",
  },
  progressLabels: {
    display: "flex",
    justifyContent: "space-between",
    marginTop: 12,
    fontSize: 16,
    textTransform: "uppercase",
  },
  progressLabel: {
    fontWeight: 700,
  },
  scene: {
    display: "grid",
    gridTemplateColumns: "0.95fr 1.05fr",
    gap: 52,
    padding: "142px 80px 86px",
    alignItems: "center",
    zIndex: 2,
  },
  copyColumn: {
    maxWidth: copyMaxWidth,
  },
  eyebrow: {
    fontSize: 24,
    fontWeight: 800,
    textTransform: "uppercase",
    marginBottom: 28,
  },
  headline: {
    margin: 0,
    fontSize: 76,
    lineHeight: 0.94,
    maxWidth: copyMaxWidth,
  },
  subline: {
    margin: "34px 0 0",
    fontSize: 30,
    lineHeight: 1.22,
    color: "rgba(247,248,240,0.75)",
    maxWidth: 700,
  },
  proofList: {
    display: "flex",
    flexDirection: "column",
    gap: 14,
    marginTop: 40,
  },
  proofItem: {
    display: "flex",
    alignItems: "center",
    gap: 14,
    width: "fit-content",
    maxWidth: 710,
    padding: "14px 18px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(255,255,255,0.06)",
    color: "rgba(247,248,240,0.9)",
    fontSize: 22,
    lineHeight: 1.2,
  },
  proofDot: {
    flex: "0 0 auto",
    width: 10,
    height: 10,
    borderRadius: 999,
  },
  visualColumn: {
    position: "relative",
    height: 740,
  },
  heroGraph: {
    position: "absolute",
    inset: 0,
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.045)",
    overflow: "hidden",
  },
  folderStack: {
    position: "absolute",
    left: 52,
    top: 70,
    width: 330,
    height: 350,
  },
  folderCard: {
    position: "absolute",
    width: 290,
    height: 180,
    padding: 24,
    border: "1px solid rgba(255,255,255,0.16)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.06)",
    color: "rgba(255,255,255,0.55)",
    fontSize: 26,
    fontWeight: 800,
  },
  folderLine: {
    height: 9,
    width: "76%",
    marginTop: 28,
    background: "rgba(255,255,255,0.13)",
  },
  centralOrb: {
    position: "absolute",
    left: "39%",
    top: "39%",
    width: 190,
    height: 190,
    borderRadius: 999,
    border: "2px solid",
    display: "grid",
    placeItems: "center",
    background: "rgba(9,10,10,0.76)",
    fontSize: 34,
    fontWeight: 900,
  },
  graphNode: {
    position: "absolute",
    padding: "14px 18px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(9,10,10,0.82)",
    fontSize: 19,
    fontWeight: 800,
  },
  graphLine: {
    position: "absolute",
    height: 2,
    transformOrigin: "0 50%",
    opacity: 0.82,
  },
  captureLayout: {
    position: "absolute",
    inset: 0,
    display: "grid",
    gridTemplateColumns: "0.82fr 1fr",
    gap: 46,
    alignItems: "center",
  },
  phone: {
    height: 660,
    border: "2px solid rgba(255,255,255,0.18)",
    borderRadius: 46,
    background: "linear-gradient(180deg, rgba(255,255,255,0.1), rgba(255,255,255,0.035))",
    padding: "46px 26px 28px",
    boxShadow: "0 28px 80px rgba(0,0,0,0.35)",
  },
  phoneNotch: {
    width: 92,
    height: 12,
    borderRadius: 999,
    background: "rgba(255,255,255,0.22)",
    margin: "0 auto 28px",
  },
  telegramHeader: {
    fontSize: 24,
    fontWeight: 900,
    marginBottom: 28,
  },
  chatBubble: {
    padding: "18px 20px",
    marginBottom: 18,
    borderRadius: 8,
    background: "rgba(124,183,255,0.16)",
    border: "1px solid rgba(124,183,255,0.28)",
    color: "#eaf3ff",
    fontSize: 22,
  },
  sendBar: {
    marginTop: 26,
    padding: "16px 20px",
    border: "1px solid",
    borderRadius: 8,
    color: "#fff",
    fontSize: 20,
    fontWeight: 900,
    textAlign: "center",
  },
  routerPanel: {
    position: "relative",
    minHeight: 590,
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.045)",
    padding: 42,
  },
  routerCore: {
    width: 220,
    height: 220,
    borderRadius: 999,
    border: "2px solid",
    display: "grid",
    placeItems: "center",
    margin: "36px auto",
    fontSize: 28,
    fontWeight: 900,
  },
  routeStack: {
    display: "grid",
    gap: 18,
  },
  routeLane: {
    display: "flex",
    alignItems: "center",
    gap: 14,
    padding: "18px 22px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(9,10,10,0.45)",
    fontSize: 24,
    fontWeight: 800,
  },
  routePill: {
    width: 14,
    height: 14,
    borderRadius: 999,
  },
  packet: {
    position: "absolute",
    width: 16,
    height: 16,
    borderRadius: 999,
    boxShadow: "0 0 26px currentColor",
  },
  canvasPanel: {
    position: "absolute",
    inset: 0,
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.045)",
    padding: 28,
  },
  tabBar: {
    display: "grid",
    gridTemplateColumns: "repeat(4, 1fr)",
    gap: 12,
    marginBottom: 22,
  },
  tab: {
    padding: "14px 16px",
    border: "1px solid",
    borderRadius: 8,
    textAlign: "center",
    fontSize: 20,
    fontWeight: 900,
  },
  clusterCanvas: {
    position: "relative",
    height: 628,
    overflow: "hidden",
    borderRadius: 8,
    background:
      "linear-gradient(135deg, rgba(112,247,212,0.08), rgba(255,199,102,0.06), rgba(198,151,255,0.08))",
  },
  clusterFrame: {
    position: "absolute",
    border: "2px dashed",
    borderRadius: 8,
    padding: 14,
    fontSize: 18,
    fontWeight: 900,
  },
  canvasBlock: {
    position: "absolute",
    display: "flex",
    alignItems: "center",
    gap: 10,
    minWidth: 160,
    padding: "17px 18px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(9,10,10,0.74)",
    fontSize: 20,
    fontWeight: 800,
  },
  blockDot: {
    width: 12,
    height: 12,
    borderRadius: 999,
  },
  deepDivePanel: {
    position: "absolute",
    inset: 0,
    display: "grid",
    gridTemplateColumns: "190px 1fr",
    gridTemplateRows: "1fr 220px",
    gap: 18,
  },
  sessionRail: {
    display: "grid",
    gap: 18,
  },
  sessionChip: {
    border: "1px solid",
    borderRadius: 8,
    padding: 18,
    display: "flex",
    flexDirection: "column",
    justifyContent: "space-between",
    minHeight: 128,
    fontSize: 20,
    fontWeight: 900,
  },
  inquiryWindow: {
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.05)",
    padding: 28,
  },
  inquiryTitle: {
    fontSize: 26,
    fontWeight: 900,
    marginBottom: 26,
  },
  inquiryRow: {
    display: "flex",
    alignItems: "center",
    gap: 14,
    padding: "18px 0",
    borderBottom: "1px solid rgba(255,255,255,0.1)",
    fontSize: 24,
  },
  inquiryIcon: {
    width: 20,
    height: 20,
    borderRadius: 999,
    border: "2px solid",
  },
  mapPreview: {
    gridColumn: "1 / 3",
    position: "relative",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.045)",
  },
  mapNode: {
    position: "absolute",
    padding: "11px 14px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(9,10,10,0.78)",
    fontSize: 18,
    fontWeight: 800,
  },
  commandPanel: {
    position: "absolute",
    inset: 0,
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.045)",
    padding: 38,
  },
  commandBar: {
    display: "flex",
    alignItems: "center",
    gap: 16,
    minHeight: 76,
    padding: "0 24px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(9,10,10,0.78)",
    fontSize: 28,
    fontWeight: 850,
  },
  cursor: {
    color: "rgba(255,255,255,0.55)",
  },
  commandBody: {
    display: "grid",
    gridTemplateColumns: "1.08fr 0.92fr",
    gap: 28,
    marginTop: 32,
  },
  taskCard: {
    minHeight: 500,
    border: "1px solid rgba(255,255,255,0.13)",
    borderRadius: 8,
    padding: 28,
    background: "rgba(255,255,255,0.06)",
  },
  taskHeader: {
    display: "flex",
    flexDirection: "column",
    gap: 10,
    fontSize: 20,
    color: "rgba(255,255,255,0.58)",
  },
  timer: {
    marginTop: 42,
    display: "flex",
    flexDirection: "column",
    gap: 10,
    color: "#ffffff",
    fontSize: 82,
    fontWeight: 950,
  },
  timerLabel: {
    color: "rgba(255,255,255,0.62)",
    fontSize: 22,
    fontWeight: 850,
  },
  linkGrid: {
    display: "grid",
    gridTemplateColumns: "repeat(2, 1fr)",
    gap: 14,
    marginTop: 40,
  },
  linkChip: {
    padding: "15px 16px",
    border: "1px solid",
    borderRadius: 8,
    fontSize: 20,
    fontWeight: 850,
    background: "rgba(9,10,10,0.42)",
  },
  dbPanel: {
    display: "grid",
    gap: 15,
    alignContent: "center",
    border: "1px solid rgba(255,255,255,0.13)",
    borderRadius: 8,
    padding: 24,
  },
  dbRow: {
    display: "flex",
    alignItems: "center",
    gap: 14,
    padding: "16px 18px",
    borderRadius: 8,
    background: "rgba(255,255,255,0.06)",
    fontSize: 22,
    fontWeight: 800,
  },
  comparePanel: {
    position: "absolute",
    inset: 0,
    display: "grid",
    gridTemplateColumns: "0.8fr 1.2fr",
    gap: 24,
  },
  fileSystem: {
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    padding: 32,
    background: "rgba(255,255,255,0.035)",
  },
  compareTitle: {
    fontSize: 25,
    fontWeight: 950,
    marginBottom: 30,
    color: "rgba(255,255,255,0.68)",
  },
  fileRow: {
    display: "flex",
    alignItems: "center",
    gap: 16,
    padding: "18px 0",
    fontSize: 28,
    fontWeight: 850,
    color: "rgba(255,255,255,0.48)",
  },
  brainGraph: {
    position: "relative",
    border: "1px solid rgba(255,255,255,0.12)",
    borderRadius: 8,
    background: "rgba(255,255,255,0.05)",
    padding: 32,
  },
  brainCore: {
    position: "absolute",
    left: "38%",
    top: "39%",
    width: 210,
    height: 210,
    border: "2px solid",
    borderRadius: 999,
    display: "grid",
    placeItems: "center",
    fontSize: 27,
    fontWeight: 950,
    background: "rgba(9,10,10,0.82)",
  },
  brainNode: {
    position: "absolute",
    padding: "16px 18px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(9,10,10,0.78)",
    fontSize: 20,
    fontWeight: 850,
  },
  closeVisual: {
    position: "absolute",
    inset: 0,
    display: "grid",
    placeItems: "center",
  },
  closeRing: {
    width: 470,
    height: 470,
    borderRadius: 999,
    border: "2px solid",
    display: "grid",
    placeItems: "center",
    background: "rgba(255,255,255,0.04)",
  },
  closeMark: {
    fontSize: 72,
    fontWeight: 1000,
  },
  closeCapsules: {
    position: "absolute",
    bottom: 70,
    display: "grid",
    gridTemplateColumns: "repeat(4, max-content)",
    gap: 14,
  },
  closeCapsule: {
    padding: "16px 18px",
    border: "1px solid",
    borderRadius: 8,
    background: "rgba(9,10,10,0.62)",
    fontSize: 18,
    fontWeight: 900,
  },
};
