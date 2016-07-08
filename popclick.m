#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <lauxlib.h>

#define get_listener_arg(L, idx) *((Listener**)luaL_checkudata(L, idx, "thume.popclick.listener"))

@interface Listener : NSObject
- (Listener*)initWithPlugin:(NSString*)plugin;
- (void)close;
@end

@implementation Listener

- (Listener*)initWithPlugin:(NSString*)plugin {
  self = [super init];
  if (self) {
    // stuff
  }
  return self;
}

- (void)close {
  // stuff
}
@end

static int listener_gc(lua_State* L) {
  Listener* listener = get_listener_arg(L, 1);
  [listener close];
  [listener release];
  return 0;
}

static int listener_close(lua_State* L) {
  Listener* listener = get_listener_arg(L, 1);
  [listener close];
  return 0;
}

static int listener_eq(lua_State* L) {
  Listener* listenA = get_listener_arg(L, 1);
  Listener* listenB = get_listener_arg(L, 2);
  lua_pushboolean(L, listenA == listenB);
  return 1;
}

void new_listener(lua_State* L, Listener* listener) {
  Listener** listenptr = lua_newuserdata(L, sizeof(Listener**));
  *listenptr = [listener retain];

  luaL_getmetatable(L, "thume.hints.listener");
  lua_setmetatable(L, -2);
}

static int popclick_test(lua_State* L) {
  [[NSSound soundNamed:@"Hero"] play];
  return 0;
}

static int listener_new(lua_State* L) {
  CGFloat x = luaL_checknumber(L, 1);
  NSString* plugin = [NSString stringWithUTF8String: luaL_tolstring(L, 2, NULL)];

  Listener *win = [[Listener alloc] initWithPlugin: plugin];
  new_listener(L, win);
  return 1;
}

static const luaL_Reg popclicklib[] = {
  {"test", popclick_test},
  {"__new", listener_new},
  {"__close", listener_close},

  {} // necessary sentinel
};

int luaopen_thume_popclick_internal(lua_State* L) {
  luaL_newlib(L, popclicklib);

  if (luaL_newmetatable(L, "thume.hints.listener")) {
    lua_pushvalue(L, -2);
    lua_setfield(L, -2, "__index");

    lua_pushcfunction(L, listener_gc);
    lua_setfield(L, -2, "__gc");

    lua_pushcfunction(L, listener_eq);
    lua_setfield(L, -2, "__eq");
  }
  lua_pop(L, 1);
  return 1;
}
