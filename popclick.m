#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <lauxlib.h>

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioQueue.h>
#import <AudioToolbox/AudioFile.h>

#define NUM_BUFFERS 1

#define get_listener_arg(L, idx) *((Listener**)luaL_checkudata(L, idx, "thume.popclick.listener"))

typedef struct
{
  AudioStreamBasicDescription dataFormat;
  AudioQueueRef               queue;
  AudioQueueBufferRef         buffers[NUM_BUFFERS];
  AudioFileID                 audioFile;
  UInt64                      currentPacket;
  bool                        recording;
}RecordState;

void AudioInputCallback(void * inUserData,  // Custom audio metadata
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs);

@interface Listener : NSObject {
  RecordState recordState;
}

- (Listener*)initWithPlugin:(NSString*)plugin outputNumber: (NSUInteger)output;
- (void)setupAudioFormat:(AudioStreamBasicDescription*)format;
- (void)startRecording;
- (void)stopRecording;
- (void)feedSamplesToEngine:(UInt32)audioDataBytesCapacity audioData:(void *)audioData;
- (RecordState*)recordState;

@end

void AudioInputCallback(void * inUserData,  // Custom audio metadata
                        AudioQueueRef inAQ,
                        AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp * inStartTime,
                        UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription * inPacketDescs) {

  Listener *rec = (Listener *) inUserData;
  RecordState * recordState = [rec recordState];
  if(!recordState->recording) return;
  recordState->currentPacket += 1;

  AudioQueueEnqueueBuffer(recordState->queue, inBuffer, 0, NULL);
  [rec feedSamplesToEngine:inBuffer->mAudioDataBytesCapacity audioData:inBuffer->mAudioData];
}

@implementation Listener

- (Listener*)initWithPlugin:(NSString*)plugin outputNumber: (NSUInteger)output {
  self = [super init];
  if (self) {
    // stuff
  }
  return self;
}

- (RecordState*)recordState {
  return &recordState;
}

- (void)setupAudioFormat:(AudioStreamBasicDescription*)format {
    format->mSampleRate = 16000.0;

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

  recordState.currentPacket = 0;

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
      AudioQueueAllocateBuffer(recordState.queue, 256, &recordState.buffers[i]);
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

- (void)feedSamplesToEngine:(UInt32)audioDataBytesCapacity audioData:(void *)audioData {
  int sampleCount = audioDataBytesCapacity / sizeof(float);
  float *samples = (float*)audioData;

  //Do something with the samples
  for ( int i = 0; i < sampleCount; i++) {
    //Do something with samples[i]
  }
}
@end

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
  NSString* plugin = [NSString stringWithUTF8String: luaL_tolstring(L, 1, NULL)];
  CGFloat outputNumF = luaL_checknumber(L, 2);
  NSUInteger outputNum = (NSUInteger)(outputNumF);

  Listener *win = [[Listener alloc] initWithPlugin: plugin outputNumber: outputNum];
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
