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
external_dependencies = {
  VAMP = {
    header = "vamp-hostsdk/vamp-hostsdk.h"
  }
}
build = {
  type = "make",
  build_variables = {
     CFLAGS="$(CFLAGS)",
     LIBFLAG="$(LIBFLAG)",
     LUA_LIBDIR="$(LUA_LIBDIR)",
     LUA_BINDIR="$(LUA_BINDIR)",
     LUA_INCDIR="$(LUA_INCDIR)",
     VAMP_LIBDIR="$(VAMP_LIBDIR)",
     VAMP_INCDIR="$(VAMP_INCDIR)",
     LUA="$(LUA)",
  },
  install_variables = {
     INST_PREFIX="$(PREFIX)",
     INST_BINDIR="$(BINDIR)",
     INST_LIBDIR="$(LIBDIR)",
     INST_LUADIR="$(LUADIR)",
     INST_CONFDIR="$(CONFDIR)",
  },
}
