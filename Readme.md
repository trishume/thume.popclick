# PopClick Lua Module

This is a lua module for using my [PopClick](https://github.com/trishume/PopClick) mouth noise recognizers.
The intention is for this to allow you to connect mouth noises to computer actions with [HammerSpoon](http://www.hammerspoon.org/).

The recognizers from [PopClick](https://github.com/trishume/PopClick) are super low latency, low CPU, and high accuracy. They are intentionally well suited for computer control purposes.
This module includes a recognizer for "ssssss" sounds which is an easy to make sound that can be made for varying amounts of time, but has the downside of being an english syllable so having false positives while speaking. It also includes a recognizer for lip popping which is a bit harder of a sound to make and can't be done continuously, but it almost never gives false positives.

See [my dotfiles](https://github.com/trishume/dotfiles/blob/master/hammerspoon/hammerspoon.symlink/init.lua) for how I use this module with hammerspoon to emit scroll events while I make a subtle "sssss" sound.

This repo contains a one-file version of the two most important recognizers extracted from my [PopClick](https://github.com/trishume/PopClick) VAMP plugins.
It uses OSXs Accelerate/vDSP FFT functions to compute FFTs, every other bit of code is portable so if you replace this with another FFT the detector class should work on any OS.
The way the microphone is read and some of the detection logic is also in Objective-C so you'd also have to rewrite that, but it shouldn't be hard to make it work with a cross-platform audio library.

# The Noises and You

I've tried to tune the detectors so that they work for most people and most microphones. For best results use a highly directional headset microphone so that it doesn't pick up other people and background
noises around you, and put the boom off to the side of your mouth so you aren't directly breathing on it.

The two mouth noises (and their corresponding event numbers) are:

## "sssssssssss"
The "sssss" noise/syllable is easy to make and can be made continuously. The detector emits an event `1` when you start saying "sss" and a `2` after you stop.
It's good to hook up to variable-length actions like clicking/dragging and scrolling. It can detect very quiet noises so even just barely saying "ssss" under your
breath should trigger it without annoying anybody else around you too much. It works with most "sss" syllables but I find sharper is better, in crispness that is, loudness doesn't matter much.
It has a very low false negative rate, but often has false positives. It will obviously trigger in english speech since "s" is a common syllable, but with some microphones breathing in certain ways
will trigger it as well. Personally I use this to scroll down, it allows me to read long articles and books lying down with my laptop without awkward hand positioning to scroll with the trackpad.

## lip popping
Popping your lips is harder to do reliably and can't be done for variable lengths of time. The detector calls your callback with the number `3` when it detects one.
This detector has an almost zero false positive rate in my experience and a very low false negative rate (when you manage to make the sound).
Personally I use this to scroll up by a large increment in case I scroll down too far with "sss", and when my RSS reader is focused it moves to the next article.
The only false positives I've ever had with this detector are various rare throat clearing noises that make a pop sound very much like a lip pop.
