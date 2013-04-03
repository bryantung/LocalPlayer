//
//  LPAudioHost.m
//  LocalPlayer
//
//  Created by Bryan Tung on 4/2/13.
//  Copyright (c) 2013 positivegrid. All rights reserved.
//

#import "LPAudioHost.h"

void halfGainEqualizer(SInt16 *rawSample, int length)
{
    while (*rawSample) {
        *rawSample -= *rawSample*0.5;
        rawSample++;
    }
}

static OSStatus inputRenderCallback (
     void                           *inRefCon,      // A pointer to a struct containing the complete audio data
                                                    //    to play, as well as state information such as the
                                                    //    first sample to play on this invocation of the callback.
     AudioUnitRenderActionFlags     *ioActionFlags, // Unused here. When generating audio, use ioActionFlags to indicate silence
                                                    //    between sounds; for silence, also memset the ioData buffers to 0.
     const AudioTimeStamp           *inTimeStamp,   // Unused here.
     UInt32                         inBusNumber,    // The mixer unit input bus that is requesting some new
                                                    //    frames of audio data to play.
     UInt32                         inNumberFrames, // The number of frames of audio to provide to the buffer(s)
                                                    //    pointed to by the ioData parameter.
     AudioBufferList                *ioData         // On output, the audio data to play. The callback's primary
                                                    //    responsibility is to fill the buffer(s) in the
                                                    //    AudioBufferList.
) {
    
    LPAudioHost *THIS = (__bridge LPAudioHost *)inRefCon;
    
    SInt16 *outSample = (SInt16 *)ioData->mBuffers[0].mData;
    
    memset(outSample, 0, inNumberFrames*sizeof(SInt16)*2);
    if (THIS.isPlaying && THIS.bufferIsReady) {
        int32_t availableBytes;
        SInt16 *bufferTail = TPCircularBufferTail(&THIS->circularBuffer, &availableBytes);
        if (THIS.halfGain) halfGainEqualizer(bufferTail, inNumberFrames);
        memcpy(outSample, bufferTail, MIN(availableBytes, inNumberFrames*sizeof(SInt16)*2));
        TPCircularBufferConsume(&THIS->circularBuffer, MIN(availableBytes, inNumberFrames*sizeof(SInt16)*2));
        THIS.currentSampleNum += MIN(availableBytes/(sizeof(SInt16)*2), inNumberFrames);
        
        if (availableBytes<= inNumberFrames*sizeof(SInt16)*2) {
            THIS.bufferIsReady = NO;
            THIS.playing = NO;
            THIS.currentSampleNum = 0;
            
            if ([[AVAudioSession sharedInstance] respondsToSelector:@selector(callForNextMediaItem)]) {
                [[AVAudioSession sharedInstance] performSelector:@selector(callForNextMediaItem)];
            }
        }
    }
    
    return noErr;
}

#pragma mark -
#pragma mark Audio route change listener callback

// Audio session callback function for responding to audio route changes. If playing back audio and
//   the user unplugs a headset or headphones, or removes the device from a dock connector for hardware
//   that supports audio playback, this callback detects that and stops playback.
//
// Refer to AudioSessionPropertyListener in Audio Session Services Reference.
void audioRouteChangeListenerCallback (
                                       void                      *inUserData,
                                       AudioSessionPropertyID    inPropertyID,
                                       UInt32                    inPropertyValueSize,
                                       const void                *inPropertyValue
                                       ) {
    
    // Ensure that this callback was invoked because of an audio route change
    if (inPropertyID != kAudioSessionProperty_AudioRouteChange) return;
    
    // This callback, being outside the implementation block, needs a reference to the MixerHostAudio
    //   object, which it receives in the inUserData parameter. You provide this reference when
    //   registering this callback (see the call to AudioSessionAddPropertyListener).
    LPAudioHost *audioObject = (__bridge LPAudioHost *) inUserData;
    
    // if application sound is not playing, there's nothing to do, so return.
    if (NO == audioObject.isPlaying) {
        
        NSLog (@"Audio route change while application audio is stopped.");
        return;
        
    } else {
        
        // Determine the specific type of audio route change that occurred.
        CFDictionaryRef routeChangeDictionary = inPropertyValue;
        
        CFNumberRef routeChangeReasonRef =
        CFDictionaryGetValue (
                              routeChangeDictionary,
                              CFSTR (kAudioSession_AudioRouteChangeKey_Reason)
                              );
        
        SInt32 routeChangeReason;
        
        CFNumberGetValue (
                          routeChangeReasonRef,
                          kCFNumberSInt32Type,
                          &routeChangeReason
                          );
        
        // "Old device unavailable" indicates that a headset or headphones were unplugged, or that
        //    the device was removed from a dock connector that supports audio output. In such a case,
        //    pause or stop audio (as advised by the iOS Human Interface Guidelines).
        if (routeChangeReason == kAudioSessionRouteChangeReason_OldDeviceUnavailable) {
            
            NSLog (@"Audio output device was removed; stopping audio playback.");
            NSString *MixerHostAudioObjectPlaybackStateDidChangeNotification = @"MixerHostAudioObjectPlaybackStateDidChangeNotification";
            [[NSNotificationCenter defaultCenter] postNotificationName: MixerHostAudioObjectPlaybackStateDidChangeNotification object: audioObject];
            
        } else {
            
            NSLog (@"A route change occurred that does not require stopping application audio.");
        }
    }
}

@implementation LPAudioHost

- (id) init {
    
    self = [super init];
    
    if (!self) return nil;
    
    self.interruptedDuringPlayback = NO;
    
    [self setupAudioSession];
    [self setupSInt16StereoStreamFormat];
    [self setupStereoStreamFormat];
    [self setupMonoStreamFormat];
    [self configureAndInitializeAudioProcessingGraph];
    
    _iTunesOperationQueue = [[NSOperationQueue alloc] init];
//    _halfGain = YES;
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"eqChange"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note){
                                                      _halfGain = !_halfGain;
                                                  }
     ];
    
    return self;
}

- (void) loadNextBufferWithURL:(NSURL *)nextAssetURL_
{
    [self stopAUGraph];
    [self loadBuffer:nextAssetURL_];
    [self startAUGraph];
}

- (void) reloadBufferWithTimeRange:(CMTimeRange)timeRange
{
    //TODO: slider value to seek play time
}

- (void) loadBuffer:(NSURL *)assetURL_
{
    if (self.isPlaying) {
        [self stopAUGraph];
    }
    if (nil != _iPodAssetReader) {
        [_iTunesOperationQueue cancelAllOperations];
        
        TPCircularBufferCleanup(&circularBuffer);
        TPCircularBufferClear(&circularBuffer);
    }
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                    [NSNumber numberWithInt:kAudioFormatLinearPCM], AVFormatIDKey,
                                    [NSNumber numberWithFloat:44100.0], AVSampleRateKey,
                                    [NSNumber numberWithInt:16], AVLinearPCMBitDepthKey,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsNonInterleaved,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsFloatKey,
                                    [NSNumber numberWithBool:NO], AVLinearPCMIsBigEndianKey,
                                    nil];
    
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL_ options:nil];
    if (asset==nil) {
        NSLog(@"asset not defined");
        return;
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:@"renewSliderLength" object:[NSNumber numberWithFloat:CMTimeGetSeconds(asset.duration)]];
    
    NSError *error = nil;
    if (_iPodAssetReader) {
        [_iPodAssetReader cancelReading];
        _iPodAssetReader = nil;
    }
    _iPodAssetReader = [AVAssetReader assetReaderWithAsset:asset error:&error];
    if (error) {
        NSLog(@"error: %@",error);
        return;
    }
    
    AVAssetReaderOutput *readerOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:asset.tracks audioSettings:outputSettings];
    if (![_iPodAssetReader canAddOutput:readerOutput]) {
        NSLog(@"unable to add reader output");
        return;
    }
    [_iPodAssetReader addOutput:readerOutput];
    
    if (![_iPodAssetReader startReading]) {
        NSLog(@"unable to start reading");
        return;
    }
    
    _playingAssetURL = [NSURL URLWithString:[assetURL_ absoluteString]];
    
    AudioUnitSetParameter(_mixerUnit, kMultiChannelMixerParam_Enable, kAudioUnitScope_Input, 0, 1, 0);
    _currentSampleNum = 0;
    
    TPCircularBufferInit(&circularBuffer, 655360*sizeof(SInt16));
    __block NSBlockOperation *feediPodBufferOperation = [NSBlockOperation blockOperationWithBlock:^{
        while (![feediPodBufferOperation isCancelled]&&_iPodAssetReader.status!=AVAssetReaderStatusCompleted) {
            if (_iPodAssetReader.status==AVAssetReaderStatusReading) {
                if (((655360*sizeof(SInt16))-circularBuffer.fillCount)>=32768) {
                    CMSampleBufferRef nextBuffer = [readerOutput copyNextSampleBuffer];
                    if (nextBuffer) {
                        AudioBufferList abl;
                        CMBlockBufferRef blockBuffer;
                        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(nextBuffer, NULL, &abl, sizeof(abl), NULL, NULL, kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, &blockBuffer);
                        UInt64 size = CMSampleBufferGetTotalSampleSize(nextBuffer);
                        
                        int bytesCopied = TPCircularBufferProduceBytes(&circularBuffer, abl.mBuffers[0].mData, size);
                        
                        if (!_bufferIsReady && bytesCopied>0) {
                            _bufferIsReady = YES;
                        }
                        
                        CFRelease(nextBuffer);
                        CFRelease(blockBuffer);
                    }
                    else break;
                }
            }
        }
        NSLog(@"iPod buffer reading finished");
    }];
    [_iTunesOperationQueue addOperation:feediPodBufferOperation];
}

- (void)callForNextMediaItem
{
    [[NSNotificationCenter defaultCenter] postNotificationName:@"playNextMediaItem" object:nil];
}

- (void) setupAudioSession {
    
    AVAudioSession *mySession = [AVAudioSession sharedInstance];
    
    // Assign the Playback category to the audio session.
    NSError *audioSessionError = nil;
    [mySession setCategory: AVAudioSessionCategoryPlayback
                     error: &audioSessionError];
    
    if (audioSessionError != nil) {
        
        NSLog (@"Error setting audio session category.");
        return;
    }
    
    // Request the desired hardware sample rate.
    _graphSampleRate = 44100.0;    // Hertz
    
    [mySession setPreferredSampleRate: _graphSampleRate
                                error: &audioSessionError];
    
    if (audioSessionError != nil) {
        
        NSLog (@"Error setting preferred hardware sample rate.");
        return;
    }
    
    // Activate the audio session
    [mySession setActive: YES
                   error: &audioSessionError];
    
    if (audioSessionError != nil) {
        
        NSLog (@"Error activating audio session during initial setup.");
        return;
    }
    
    // Obtain the actual hardware sample rate and store it for later use in the audio processing graph.
    self.graphSampleRate = [mySession sampleRate];
    
    // Register the audio route change listener callback function with the audio session.
    AudioSessionAddPropertyListener (
                                     kAudioSessionProperty_AudioRouteChange,
                                     audioRouteChangeListenerCallback,
                                     (__bridge void *)(self)
                                     );
}

- (void) configureAndInitializeAudioProcessingGraph {
    
    NSLog (@"Configuring and then initializing audio processing graph");
    OSStatus result = noErr;
    
    //............................................................................
    // Create a new audio processing graph.
    result = NewAUGraph (&processingGraph);
    
    if (noErr != result) {[self printErrorMessage: @"NewAUGraph" withStatus: result]; return;}
    
    
    //............................................................................
    // Specify the audio unit component descriptions for the audio units to be
    //    added to the graph.
    
    // I/O unit
    AudioComponentDescription iOUnitDescription;
    iOUnitDescription.componentType          = kAudioUnitType_Output;
    iOUnitDescription.componentSubType       = kAudioUnitSubType_RemoteIO;
    iOUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    iOUnitDescription.componentFlags         = 0;
    iOUnitDescription.componentFlagsMask     = 0;
    
    // Multichannel mixer unit
    AudioComponentDescription MixerUnitDescription;
    MixerUnitDescription.componentType          = kAudioUnitType_Mixer;
    MixerUnitDescription.componentSubType       = kAudioUnitSubType_MultiChannelMixer;
    MixerUnitDescription.componentManufacturer  = kAudioUnitManufacturer_Apple;
    MixerUnitDescription.componentFlags         = 0;
    MixerUnitDescription.componentFlagsMask     = 0;
    
    
    //............................................................................
    // Add nodes to the audio processing graph.
    NSLog (@"Adding nodes to audio processing graph");
    
    AUNode   iONode;         // node for I/O unit
    AUNode   mixerNode;      // node for Multichannel Mixer unit
    
    // Add the nodes to the audio processing graph
    result =    AUGraphAddNode (
                                processingGraph,
                                &iOUnitDescription,
                                &iONode);
    
    if (noErr != result) {[self printErrorMessage: @"AUGraphNewNode failed for I/O unit" withStatus: result]; return;}
    
    
    result =    AUGraphAddNode (
                                processingGraph,
                                &MixerUnitDescription,
                                &mixerNode
                                );
    
    if (noErr != result) {[self printErrorMessage: @"AUGraphNewNode failed for Mixer unit" withStatus: result]; return;}
    
    
    //............................................................................
    // Open the audio processing graph
    
    // Following this call, the audio units are instantiated but not initialized
    //    (no resource allocation occurs and the audio units are not in a state to
    //    process audio).
    result = AUGraphOpen (processingGraph);
    
    if (noErr != result) {[self printErrorMessage: @"AUGraphOpen" withStatus: result]; return;}
    
    
    //............................................................................
    // Obtain the mixer unit instance from its corresponding node.
    
    result =    AUGraphNodeInfo (
                                 processingGraph,
                                 mixerNode,
                                 NULL,
                                 &_mixerUnit
                                 );
    
    if (noErr != result) {[self printErrorMessage: @"AUGraphNodeInfo" withStatus: result]; return;}
    
    
    //............................................................................
    // Multichannel Mixer unit Setup
    
    UInt32 busCount   = 2;    // bus count for mixer unit input
    
    NSLog (@"Setting mixer unit input bus count to: %lu", busCount);
    result = AudioUnitSetProperty (
                                   _mixerUnit,
                                   kAudioUnitProperty_ElementCount,
                                   kAudioUnitScope_Input,
                                   0,
                                   &busCount,
                                   sizeof (busCount)
                                   );
    
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit bus count)" withStatus: result]; return;}
    
    
    NSLog (@"Setting kAudioUnitProperty_MaximumFramesPerSlice for mixer unit global scope");
    // Increase the maximum frames per slice allows the mixer unit to accommodate the
    //    larger slice size used when the screen is locked.
    UInt32 maximumFramesPerSlice = 4096;
    
    result = AudioUnitSetProperty (
                                   _mixerUnit,
                                   kAudioUnitProperty_MaximumFramesPerSlice,
                                   kAudioUnitScope_Global,
                                   0,
                                   &maximumFramesPerSlice,
                                   sizeof (maximumFramesPerSlice)
                                   );
    
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit input stream format)" withStatus: result]; return;}
    
    
    // Setup the struture that contains the input render callback
    AURenderCallbackStruct inputCallbackStruct;
    inputCallbackStruct.inputProc        = &inputRenderCallback;
    inputCallbackStruct.inputProcRefCon  = (__bridge void *)(self);
    
    // Set a callback for the specified node's specified input
    result = AUGraphSetNodeInputCallback (
                                          processingGraph,
                                          mixerNode,
                                          0,
                                          &inputCallbackStruct
                                          );
    
    if (noErr != result) {[self printErrorMessage: @"AUGraphSetNodeInputCallback" withStatus: result]; return;}
    
    NSLog (@"Setting stereo stream format for mixer unit input bus");
    result = AudioUnitSetProperty (
                                   _mixerUnit,
                                   kAudioUnitProperty_StreamFormat,
                                   kAudioUnitScope_Input,
                                   0,
                                   &_SInt16StereoStreamFormat,
                                   sizeof (_SInt16StereoStreamFormat)
                                   );
    
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit guitar input bus stream format)" withStatus: result];return;}
    
    NSLog (@"Setting sample rate for mixer unit output scope");
    // Set the mixer unit's output sample rate format. This is the only aspect of the output stream
    //    format that must be explicitly set.
    result = AudioUnitSetProperty (
                                   _mixerUnit,
                                   kAudioUnitProperty_SampleRate,
                                   kAudioUnitScope_Output,
                                   0,
                                   &_graphSampleRate,
                                   sizeof (_graphSampleRate)
                                   );
    
    if (noErr != result) {[self printErrorMessage: @"AudioUnitSetProperty (set mixer unit output stream format)" withStatus: result]; return;}
    
    
    //............................................................................
    // Connect the nodes of the audio processing graph
    NSLog (@"Connecting the mixer output to the input of the I/O unit output element");
    
    result = AUGraphConnectNodeInput (
                                      processingGraph,
                                      mixerNode,         // source node
                                      0,                 // source node output bus number
                                      iONode,            // destination node
                                      0                  // desintation node input bus number
                                      );
    
    if (noErr != result) {[self printErrorMessage: @"AUGraphConnectNodeInput" withStatus: result]; return;}
    
    
    //............................................................................
    // Initialize audio processing graph
    
    // Diagnostic code
    // Call CAShow if you want to look at the state of the audio processing 
    //    graph.
    NSLog (@"Audio processing graph state immediately before initializing it:");
    CAShow (processingGraph);
    
    NSLog (@"Initializing the audio processing graph");
    // Initialize the audio processing graph, configure audio data stream formats for
    //    each input and output, and validate the connections between audio units.
    result = AUGraphInitialize (processingGraph);
    
    if (noErr != result) {[self printErrorMessage: @"AUGraphInitialize" withStatus: result]; return;}
}

- (void) setupSInt16StereoStreamFormat {
    size_t bytesPerSample = sizeof(AudioSampleType);
    
    _SInt16StereoStreamFormat.mFormatID         = kAudioFormatLinearPCM;
    _SInt16StereoStreamFormat.mFormatFlags      = kAudioFormatFlagsCanonical;
    _SInt16StereoStreamFormat.mBytesPerPacket   = 2*bytesPerSample;
    _SInt16StereoStreamFormat.mFramesPerPacket  = 1;
    _SInt16StereoStreamFormat.mBytesPerFrame    = _SInt16StereoStreamFormat.mBytesPerPacket*_SInt16StereoStreamFormat.mFramesPerPacket;
    _SInt16StereoStreamFormat.mChannelsPerFrame = 2;
    _SInt16StereoStreamFormat.mBitsPerChannel   = 8*bytesPerSample;
    _SInt16StereoStreamFormat.mSampleRate       = _graphSampleRate;
    
    [self printASBD:_SInt16StereoStreamFormat];
}

- (void) setupStereoStreamFormat {
    
    // The AudioUnitSampleType data type is the recommended type for sample data in audio
    //    units. This obtains the byte size of the type for use in filling in the ASBD.
    size_t bytesPerSample = sizeof (AudioUnitSampleType);
    
    // Fill the application audio format struct's fields to define a linear PCM,
    //        stereo, noninterleaved stream at the hardware sample rate.
    _stereoStreamFormat.mFormatID          = kAudioFormatLinearPCM;
    _stereoStreamFormat.mFormatFlags       = kAudioFormatFlagsAudioUnitCanonical;
    _stereoStreamFormat.mBytesPerPacket    = bytesPerSample;
    _stereoStreamFormat.mFramesPerPacket   = 1;
    _stereoStreamFormat.mBytesPerFrame     = bytesPerSample;
    _stereoStreamFormat.mChannelsPerFrame  = 2;                    // 2 indicates stereo
    _stereoStreamFormat.mBitsPerChannel    = 8 * bytesPerSample;
    _stereoStreamFormat.mSampleRate        = _graphSampleRate;
    
    [self printASBD: _stereoStreamFormat];
}


- (void) setupMonoStreamFormat {
    
    // The AudioUnitSampleType data type is the recommended type for sample data in audio
    //    units. This obtains the byte size of the type for use in filling in the ASBD.
    size_t bytesPerSample = sizeof (AudioUnitSampleType);
    
    // Fill the application audio format struct's fields to define a linear PCM,
    //        stereo, noninterleaved stream at the hardware sample rate.
    _monoStreamFormat.mFormatID          = kAudioFormatLinearPCM;
    _monoStreamFormat.mFormatFlags       = kAudioFormatFlagsAudioUnitCanonical;
    _monoStreamFormat.mBytesPerPacket    = bytesPerSample;
    _monoStreamFormat.mFramesPerPacket   = 1;
    _monoStreamFormat.mBytesPerFrame     = bytesPerSample;
    _monoStreamFormat.mChannelsPerFrame  = 1;                  // 1 indicates mono
    _monoStreamFormat.mBitsPerChannel    = 8 * bytesPerSample;
    _monoStreamFormat.mSampleRate        = _graphSampleRate;
    
    [self printASBD: _monoStreamFormat];
    
}

#pragma mark -
#pragma mark Playback control

// Start playback
- (void) startAUGraph {
    
    NSLog (@"Starting audio processing graph");
    OSStatus result = AUGraphStart (processingGraph);
    if (noErr != result) {[self printErrorMessage: @"AUGraphStart" withStatus: result]; return;}
    
    self.playing = YES;
}

// Stop playback
- (void) stopAUGraph {
    
    NSLog (@"Stopping audio processing graph");
    Boolean isRunning = false;
    OSStatus result = AUGraphIsRunning (processingGraph, &isRunning);
    if (noErr != result) {[self printErrorMessage: @"AUGraphIsRunning" withStatus: result]; return;}
    
    if (isRunning) {
        
        result = AUGraphStop (processingGraph);
        if (noErr != result) {[self printErrorMessage: @"AUGraphStop" withStatus: result]; return;}
        self.playing = NO;
    }
}

- (void) printASBD: (AudioStreamBasicDescription) asbd {
    
    char formatIDString[5];
    UInt32 formatID = CFSwapInt32HostToBig (asbd.mFormatID);
    bcopy (&formatID, formatIDString, 4);
    formatIDString[4] = '\0';
    
    NSLog (@"  Sample Rate:         %10.0f",  asbd.mSampleRate);
    NSLog (@"  Format ID:           %10s",    formatIDString);
    NSLog (@"  Format Flags:        %10lu",    asbd.mFormatFlags);
    NSLog (@"  Bytes per Packet:    %10lu",    asbd.mBytesPerPacket);
    NSLog (@"  Frames per Packet:   %10lu",    asbd.mFramesPerPacket);
    NSLog (@"  Bytes per Frame:     %10lu",    asbd.mBytesPerFrame);
    NSLog (@"  Channels per Frame:  %10lu",    asbd.mChannelsPerFrame);
    NSLog (@"  Bits per Channel:    %10lu",    asbd.mBitsPerChannel);
}


- (void) printErrorMessage: (NSString *) errorString withStatus: (OSStatus) result {
    
    
    char str[20];
	// see if it appears to be a 4-char-code
	*(UInt32 *)(str + 1) = CFSwapInt32HostToBig(result);
	if (isprint(str[1]) && isprint(str[2]) && isprint(str[3]) && isprint(str[4])) {
		str[0] = str[5] = '\'';
		str[6] = '\0';
	} else
		// no, format it as an integer
		sprintf(str, "%d", (int)result);
	   
    
    NSLog (
           @"*** %@ error: %s\n",
           errorString,
           str
           );
}

@end
