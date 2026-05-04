import "./index.css";
import { Composition } from "remotion";
import { CosmoLaunchVideo } from "./Composition";
import { FPS, VIDEO_DURATION_FRAMES } from "./storyboard";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      <Composition
        id="CosmoLaunchVideo"
        component={CosmoLaunchVideo}
        durationInFrames={VIDEO_DURATION_FRAMES}
        fps={FPS}
        width={1920}
        height={1080}
      />
    </>
  );
};
