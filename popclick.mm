#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

extern "C" {
#import <lauxlib.h>
}

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>

#include <vamp-hostsdk/PluginHostAdapter.h>
#include <vamp-hostsdk/PluginInputDomainAdapter.h>
#include <vamp-hostsdk/PluginLoader.h>


using Vamp::Plugin;
using Vamp::PluginHostAdapter;
using Vamp::RealTime;
using Vamp::HostExt::PluginLoader;
using Vamp::HostExt::PluginWrapper;
using Vamp::HostExt::PluginInputDomainAdapter;

#define NUM_BUFFERS 1
static const int kSampleRate = 44100;
static const int kPopInstantOutput = 7;
static const int kTssDownOutput = 3;
static const int kTssUpOutput = 4;
static const int kScrollOnOutput = 3;
static const int kScrollOffOutput = 4;
static const int kBufferSize = 512;

#define get_listener_arg(L, idx) *((Listener**)luaL_checkudata(L, idx, "thume.popclick.listener"))

typedef struct
{
  AudioStreamBasicDescription dataFormat;
  AudioQueueRef               queue;
  AudioQueueBufferRef         buffers[NUM_BUFFERS];
  AudioFileID                 audioFile;
  UInt64                      currentFrame;
  bool                        recording;
}RecordState;

@interface Listener : NSObject {
  RecordState recordState;
  _VampHost::Vamp::Plugin *popPlugin;
  _VampHost::Vamp::Plugin *tssPlugin;
}

- (Listener*)initPlugins;
- (void)setupAudioFormat:(AudioStreamBasicDescription*)format;
- (void)startRecording;
- (void)stopRecording;
- (void)feedSamplesToEngine:(UInt32)audioDataBytesCapacity audioData:(void *)audioData;
- (RecordState*)recordState;
- (void)runCallbackWithEvent: (NSNumber*)evNumber;
- (void)mainThreadCallback: (NSUInteger)evNumber;

@property lua_State* L;
@property int fn;
@end

extern "C"
void AudioInputCallback(void * inUserData,  // Custom audio metadata
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs) {

  Listener *rec = (Listener *) inUserData;
  RecordState * recordState = [rec recordState];
  if(!recordState->recording) return;

  AudioQueueEnqueueBuffer(recordState->queue, inBuffer, 0, NULL);
  [rec feedSamplesToEngine:inBuffer->mAudioDataBytesCapacity audioData:inBuffer->mAudioData];
}

@implementation Listener

- (Listener*)initPlugins {
  self = [super init];
  if (self) {
    recordState.recording = false;

    PluginLoader *loader = PluginLoader::getInstance();
    PluginLoader::PluginKey popKey = loader->composePluginKey("popclick", "popdetector");
    popPlugin = loader->loadPlugin(popKey, kSampleRate, PluginLoader::ADAPT_ALL);
    PluginLoader::PluginKey tssKey = loader->composePluginKey("popclick", "tssdetector");
    tssPlugin = loader->loadPlugin(tssKey, kSampleRate, PluginLoader::ADAPT_ALL);

    if (!popPlugin->initialise(1, kBufferSize, kBufferSize)) {
      NSLog(@"ERROR: Plugin pop initialise failed.");
    }
    if (!tssPlugin->initialise(1, kBufferSize, kBufferSize)) {
      NSLog(@"ERROR: Plugin tss initialise failed.");
    }
  }
  return self;
}

- (RecordState*)recordState {
  return &recordState;
}

- (void)setupAudioFormat:(AudioStreamBasicDescription*)format {
    format->mSampleRate = kSampleRate;

    format->mFormatID = kAudioFormatLinearPCM;
    format->mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    format->mFramesPerPacket  = 1;
    format->mChannelsPerFrame = 1;
    format->mBytesPerFrame    = sizeof(float);
    format->mBytesPerPacket   = sizeof(float);
    format->mBitsPerChannel   = sizeof(float) * 8;
}

- (void)startRecording {
  if(recordState.recording) return;
  [self setupAudioFormat:&recordState.dataFormat];

  recordState.currentFrame = 0;

  OSStatus status;
  status = AudioQueueNewInput(&recordState.dataFormat,
                              AudioInputCallback,
                              self,
                              CFRunLoopGetCurrent(),
                              kCFRunLoopCommonModes,
                              0,
                              &recordState.queue);

  if (status == 0) {

    for (int i = 0; i < NUM_BUFFERS; i++) {
      AudioQueueAllocateBuffer(recordState.queue, kBufferSize*sizeof(float), &recordState.buffers[i]);
      AudioQueueEnqueueBuffer(recordState.queue, recordState.buffers[i], 0, nil);
    }

    recordState.recording = true;

    status = AudioQueueStart(recordState.queue, NULL);
  } else {
    NSLog(@"Error: Couldn't open audio queue.");
  }
}

- (void)stopRecording {
  if(!recordState.recording) return;
  recordState.recording = false;

  AudioQueueStop(recordState.queue, true);

  for (int i = 0; i < NUM_BUFFERS; i++) {
  AudioQueueFreeBuffer(recordState.queue, recordState.buffers[i]);
  }

  AudioQueueDispose(recordState.queue, true);
  AudioFileClose(recordState.audioFile);
}
- (void)mainThreadCallback: (NSUInteger)evNumber {
    [self performSelectorOnMainThread:@selector(runCallbackWithEvent:)
      withObject:[NSNumber numberWithInt: evNumber] waitUntilDone:NO];
}

- (void)feedSamplesToEngine:(UInt32)audioDataBytesCapacity audioData:(void *)audioData {
  int sampleCount = audioDataBytesCapacity / sizeof(float);
  float *samples = (float*)audioData;
  NSAssert(sampleCount == kBufferSize, @"Incorrect buffer size");
  RealTime rt = RealTime::frame2RealTime(recordState.currentFrame, kSampleRate);

  Plugin::FeatureSet tssFeatures = tssPlugin->process(&samples, rt);
  if(!tssFeatures[kTssDownOutput].empty()) {
    [self mainThreadCallback: 1];
  }
  if(!tssFeatures[kTssUpOutput].empty()) {
    [self mainThreadCallback: 2];
  }
  Plugin::FeatureSet popFeatures = popPlugin->process(&samples, rt);
  if(!popFeatures[kPopInstantOutput].empty()) {
    [self mainThreadCallback: 3];
  }

  recordState.currentFrame += sampleCount;
}

- (void)runCallbackWithEvent: (NSNumber*)evNumber {
  lua_State* L = self.L;
  lua_rawgeti(L, LUA_REGISTRYINDEX, self.fn);
  lua_pushinteger(L, [evNumber intValue]);
  lua_call(L, 1, 0);
}
@end

extern "C" {
static int listener_gc(lua_State* L) {
  Listener* listener = get_listener_arg(L, 1);
  [listener stopRecording];
  [listener release];
  return 0;
}

static int listener_close(lua_State* L) {
  Listener* listener = get_listener_arg(L, 1);
  [listener stopRecording];
  return 0;
}

static int listener_start(lua_State* L) {
  Listener* listener = get_listener_arg(L, 1);
  [listener startRecording];
  return 0;
}

static int listener_eq(lua_State* L) {
  Listener* listenA = get_listener_arg(L, 1);
  Listener* listenB = get_listener_arg(L, 2);
  lua_pushboolean(L, listenA == listenB);
  return 1;
}

void new_listener(lua_State* L, Listener* listener) {
  Listener** listenptr = (Listener**)lua_newuserdata(L, sizeof(Listener**));
  *listenptr = [listener retain];

  luaL_getmetatable(L, "thume.popclick.listener");
  lua_setmetatable(L, -2);
}

static int popclick_test(lua_State* L) {
  [[NSSound soundNamed:@"Hero"] play];
  return 0;
}

static int listener_new(lua_State* L) {
  luaL_checktype(L, 1, LUA_TFUNCTION);
  int fn = luaL_ref(L, LUA_REGISTRYINDEX);

  Listener *listener = [[Listener alloc] initPlugins];
  listener.fn = fn;
  listener.L = L;
  new_listener(L, listener);
  return 1;
}

static const luaL_Reg popclicklib[] = {
  {"test", popclick_test},
  {"new", listener_new},
  {"stop", listener_close},
  {"start", listener_start},

  {} // necessary sentinel
};

int luaopen_thume_popclick_internal(lua_State* L) {
  luaL_newlib(L, popclicklib);

  if (luaL_newmetatable(L, "thume.popclick.listener")) {
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
}
