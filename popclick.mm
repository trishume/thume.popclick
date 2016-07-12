#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

extern "C" {
#import <lauxlib.h>
}

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>

#include "detectors.h"

#define NUM_BUFFERS 1
static const int kSampleRate = 44100;
static const int kPopInstantOutput = 7;
static const int kTssDownOutput = 3;
static const int kTssUpOutput = 4;
static const int kScrollOnOutput = 3;
static const int kScrollOffOutput = 4;

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
  Detectors *detectors;
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
    detectors = new Detectors();
    detectors->initialise();
  }
  return self;
}

- (void)dealloc {
  delete detectors;
  [super dealloc];
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
      AudioQueueAllocateBuffer(recordState.queue, detectors->getPreferredBlockSize()*sizeof(float), &recordState.buffers[i]);
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
  NSAssert(sampleCount == detectors->getPreferredBlockSize(), @"Incorrect buffer size");

  int result = detectors->process(samples);
  if((result & 1) == 1) {
    [self mainThreadCallback: 1]; // Tss on
  }
  if((result & 2) == 2) {
    [self mainThreadCallback: 2]; // Tss off
  }
  if((result & 4) == 4) {
    [self mainThreadCallback: 3]; // Pop
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

/// thume.popclick.listener:stop() -> self
/// Method
/// Stops the listener from recording and analyzing microphone input.
///
/// Parameters:
///  * None
///
/// Returns:
///  * The `thume.popclick.listener` object
static int listener_stop(lua_State* L) {
  Listener* listener = get_listener_arg(L, 1);
  [listener stopRecording];
  lua_settop(L,1);
  return 1;
}

/// thume.popclick.listener:start() -> self
/// Method
/// Starts listening to the microphone and passing the audio to the recognizer.
///
/// Parameters:
///  * None
///
/// Returns:
///  * The `thume.popclick.listener` object
static int listener_start(lua_State* L) {
  Listener* listener = get_listener_arg(L, 1);
  [listener startRecording];
  lua_settop(L,1);
  return 1;
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

/// thume.popclick.new(fn) -> listener
/// Method
/// Creates a new listener for mouth noise recognition
///
/// Parameters:
///  * A function that is called when a mouth noise is recognized. It should accept a single parameter which will be a number representing the event type.
///
/// Returns:
///  * A `thume.popclick.listener` object
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
  {"new", listener_new},
  {"stop", listener_stop},
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
