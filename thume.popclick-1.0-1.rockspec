-- `package` is the require-path.
--
--    Note: this must match the filename also.
package = "thume.popclick"

-- `version` has two parts, your module's version (0.1) and the
--    rockspec's version (1) in case you change metadata without
--    changing the module's source code.
--
--    Note: the version must match the version in the filename.
version = "1.0-1"

-- General metadata:

local url = "github.com/trishume/thume.popclick"
local desc = "A lua binding for PopClick to detect mouth noises on OSX with HammerSpoon/Mjolnir."

source = {url = "git://" .. url}
description = {
  summary = desc,
  detailed = desc,
  homepage = "https://" .. url,
  license = "MIT",
}

-- Dependencies:

supported_platforms = {"macosx"}
dependencies = {
  "lua >= 5.2",
}

-- Build rules:

build = {
  type = "builtin",
  modules = {
    -- This is the top-level module:
    ["thume.popclick"] = "popclick.lua",

    -- If you have an internal C or Objective-C submodule, include it here:
    ["thume.popclick.internal"] = "popclick.m",

    -- Note: the key on the left side is the require-path; the value
    --       on the right is the filename relative to the current dir.
  },
}
