//
//  LPAudioHost.h
//  LocalPlayer
//
//  Created by Bryan Tung on 4/2/13.
//  Copyright (c) 2013 positivegrid. All rights reserved.
//

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import "TPCircularBuffer+AudioBufferList.h"

@interface LPAudioHost : NSObject{
    AUGraph                         processingGraph;
    @public
    TPCircularBuffer                circularBuffer;
}

@property (readwrite)           AudioStreamBasicDescription stereoStreamFormat;
@property (readwrite)           AudioStreamBasicDescription monoStreamFormat;
@property (readwrite)           AudioStreamBasicDescription SInt16StereoStreamFormat;
@property (readwrite)           Float64                     graphSampleRate;
@property (getter = isPlaying)  BOOL                        playing;
@property                       BOOL                        bufferIsReady;
@property                       BOOL                        interruptedDuringPlayback;
@property                       AudioUnit                   mixerUnit;
@property                       UInt32                      currentSampleNum;
@property                       UInt32                      totalSampleNum;
@property                       AVAssetReader               *iPodAssetReader;
@property                       NSOperationQueue            *iTunesOperationQueue;
@property                       BOOL                        halfGain;
@property                       NSURL                       *playingAssetURL;

- (void)loadNextBufferWithURL:(NSURL *)nextAssetURL_;
- (void)loadBuffer:(NSURL *)assetURL_;
- (void)reloadBufferWithTimeRange:(CMTimeRange)timeRange;
- (void)callForNextMediaItem;
- (void)startAUGraph;
- (void)stopAUGraph;

@end
