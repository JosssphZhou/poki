# The launch screen's pictures

The launch screen is the home page's light with "Poki" over it and the bear looking up from the bottom
edge. iOS draws it from `LaunchScreen.storyboard` before Poki runs, so the storyboard can hold only
pictures: no mesh gradient, no Geist and no shadow. When Poki's first frame is up, `LaunchCurtain`
lays the same storyboard over it and lets it go: the bear sinks, the word fades, and the picture of the
light fades into the light itself.

| File | What | Made by |
| --- | --- | --- |
| `LaunchBackdrop.png` | The home page's light at rest, light appearance, 402 by 874 points at one pixel a point | `scripts/make-launch-backdrop.sh`, which has a Debug build draw `HomeBackdrop` itself |
| `LaunchBackdropDark.png` | The same light in the dark appearance | The same script |
| `LaunchBear.png` | The bear cut out of the app icon, on a clear ground | The design's own cut-out |

`scripts/make-assets.sh` copies the two lights into the asset catalogue and draws the word (at 3x) and the
bear (at 2x) from these with `scripts/make-launch-art.swift`, once for each appearance: in dark the word
is a soft white and the bear has no blue shadow. The word's colours and weight are set once, at the top of
that script. The ground under the pictures is the `LaunchGround` colour, the home page's paper in light
and its blue-black in dark. After a change to the home page's light, run
`make-launch-backdrop.sh` again; `LaunchScreenTests` fails while a picture and the light differ.

iOS draws the launch screen on the iPhone itself before Poki runs, so every picture here stays small:
each one fits in a single 4 MiB piece of the asset catalogue, as the old launch screen's bear did.
The bear is drawn at 2x because its cut-out is 1024 pixels wide, fewer than a 3x picture would hold,
so 3x only made it the largest picture in the app. `LaunchScreenTests` fails if a picture outgrows this.

Every picture has a dark one, so in Dark Mode the launch screen is the dark home page's light with a
pale word, and the curtain lets it go into the dark home page as it does in light.

## License

`LaunchBear.png` is the Poki bear, Poki's own character and its main brand asset. It is not covered by the AGPL-3.0-only license that applies to Poki's code. You can build and run Poki with it unchanged; any other use, including new versions of the bear made from it, needs written permission. See [BRAND.md](../../../../BRAND.md).

Copyright (c) 2026 Joseph Zhou (周瑟夫). All rights reserved, to the extent the law protects these works.
