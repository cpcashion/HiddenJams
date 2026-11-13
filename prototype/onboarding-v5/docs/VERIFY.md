# VERIFY: live URL run

Command: `python3 shoot.py https://cpcashion.github.io/hiddenjams-onboarding-v4/v5/` (headless Chromium, 393x852 @2x). Run on Thu Nov 12 22:57:52 EST 2026

Notes: `overflowX` on screen 1 = the rotated "heard." highlight and starburst poking past the title box (visual check: title is 3 lines, nothing clipped). `collisions` = cover/text bounding-box intersections (empty = none). `dots_bottom` is y of the dots; Next box identical on every screen except 5 (connect buttons occupy that slot).

```json
{
 "flow_steps(expect 2,3,4,5,6,7,8,9,10)": [
  "2",
  "3",
  "4",
  "5",
  "6",
  "7",
  "8",
  "9",
  "10"
 ],
 "stored": "[\"ambient\",\"funk\",\"hip hop\"]",
 "pre_selected_after_reload": [
  "Funk",
  "Ambient",
  "Hip Hop"
 ],
 "swipe_left_from_1_goes_to": "2",
 "empty_path_ends_on": "11",
 "console_errors": "clean"
}
{
 "1": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [
   "display xl:Most musicnever getshear"
  ],
  "offscreen": []
 },
 "2": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "3": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "4": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "5": {
  "cta": {
   "l": 22,
   "t": 704,
   "r": 371,
   "b": 760
  },
  "label": "Continue with Spotify",
  "dots_bottom": 690,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "6": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "7": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "8": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "9": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Next",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "10": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Start digging",
  "dots_bottom": 756,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 },
 "11": {
  "cta": {
   "l": 22,
   "t": 770,
   "r": 371,
   "b": 826
  },
  "label": "Start digging",
  "dots_bottom": null,
  "collisions": [],
  "overflowX": [],
  "offscreen": []
 }
}
CTA boxes {1: (22, 371, 826), 2: (22, 371, 826), 3: (22, 371, 826), 4: (22, 371, 826), 5: (22, 371, 760), 6: (22, 371, 826), 7: (22, 371, 826), 8: (22, 371, 826), 9: (22, 371, 826), 10: (22, 371, 826), 11: (22, 371, 826)}
```
