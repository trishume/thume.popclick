# PopClick Lua Module

This is a lua module for using my [PopClick](https://github.com/trishume/PopClick) mouth noise recognizers.
The intention is for this to allow you to connect mouth noises to computer actions with [HammerSpoon](http://www.hammerspoon.org/).

The recognizers from [PopClick](https://github.com/trishume/PopClick) are super low latency, low CPU, and high accuracy. They are intentionally well suited for computer control purposes.
This module includes a recognizer for "ssssss" sounds which is an easy to make sound that can be made for varying amounts of time, but has the downside of being an english syllable so having false positives while speaking. It also includes a recognizer for lip popping which is a bit harder of a sound to make and can't be done continuously, but it almost never gives false positives.

See [my dotfiles](https://github.com/trishume/dotfiles/blob/master/hammerspoon/hammerspoon.symlink/init.lua) for how I use this module with hammerspoon to emit scroll events while I make a subtle "sssss" sound.

This repo contains a one-file version of the two most important recognizers extracted from my [PopClick](https://github.com/trishume/PopClick) VAMP plugins.
It uses OSXs Accelerate/vDSP FFT functions to compute FFTs, every other bit of code is portable so if you replace this with another FFT the detector class should work on any OS.
The way the microphone is read and some of the detection logic is also in Objective-C so you'd also have to rewrite that, but it shouldn't be hard to make it work with a cross-platform audio library.
