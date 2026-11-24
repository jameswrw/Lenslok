# Live Lenslok Decoder for iPhone

This app decodes a Lenslok scrambled image revealing the two character code required to start your protected app. Simply, hold your phone so the scrambled region is inside the marked detection zone. For historical authenticity you may need to adjust the positioning of the phone and squint a bit to read the letters.

The decoding table is taken from Simon Owen's [Lenskey](https://github.com/simonowen/lenskey/), which is a Windows app that does much the same thing, except it captures a region of the screen rather than processes live video. There was much vibe coding involved in this - especially in LenslokDecoder.swift which is where pretty much everything happens - so kudos to AI for that.

Here's a screenshot of a successful decoding if the OK calibration pattern for a 3D game of some renown where you can wander around a whole universe, and not just a single city, whilst possibly taking liberties with the law. I hear this kind of thing is all the rage these days.
<img width="1311" height="603" alt="Lenslok-OK" src="https://github.com/user-attachments/assets/828f2de7-d9bf-4101-958e-7f954078cbde" />
