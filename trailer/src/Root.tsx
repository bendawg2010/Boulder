import { Composition } from "remotion";
import { BoulderTrailer } from "./BoulderTrailer";

// 33 seconds @ 30fps = 990 frames, 1920x1080 landscape.
// (Bumped from 30s after inserting the new "click to inspect" scene.)
export const RemotionRoot: React.FC = () => {
  return (
    <Composition
      id="BoulderTrailer"
      component={BoulderTrailer}
      durationInFrames={990}
      fps={30}
      width={1920}
      height={1080}
    />
  );
};
