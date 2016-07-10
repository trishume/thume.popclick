# PopClick Lua Module

This is a lua module for using my [PopClick](https://github.com/trishume/PopClick) VAMP plugins.
The intention is for this to allow you to connect mouth noises to computer actions with [HammerSpoon](http://www.hammerspoon.org/).

See [my dotfiles](https://github.com/trishume/dotfiles/blob/master/hammerspoon/hammerspoon.symlink/init.lua) for how I use this module with hammerspoon to emit scroll events while I make a subtle "sssss" sound.

It currently just uses the VAMP host SDK to load and use the PopClick VAMP plugin, so you'll need to install both the SDK and the plugins before this module will work.
