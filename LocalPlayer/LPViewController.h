//
//  LPViewController.h
//  LocalPlayer
//
//  Created by Bryan Tung on 4/2/13.
//  Copyright (c) 2013 positivegrid. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import "LPAudioHost.h"

@interface LPViewController : UIViewController<MPMediaPickerControllerDelegate,UITableViewDelegate,UITableViewDataSource>

@property (nonatomic)   MPMediaItemCollection *loadedMediaCollection;
@property               NSInteger             currentMediaItemIndex;

@property (weak, nonatomic) IBOutlet UIImageView *albumArtView;
@property (weak, nonatomic) IBOutlet UILabel *songTitle;
@property (weak, nonatomic) IBOutlet UILabel *songArtist;
@property (weak, nonatomic) IBOutlet UILabel *songAlbum;
@property (weak, nonatomic) IBOutlet UILabel *songDuration;

@property (weak, nonatomic) IBOutlet UIButton *addSongsButton;
@property (weak, nonatomic) IBOutlet UIButton *selectLocationButton;
@property (weak, nonatomic) IBOutlet UITextField *locationNameText;
@property (weak, nonatomic) IBOutlet UIButton *locationDoneButton;
@property (weak, nonatomic) IBOutlet UITableView *playlistTable;

@property (weak, nonatomic) IBOutlet UISlider *timingSlider;
@property (weak, nonatomic) IBOutlet UIButton *playButton;
@property (weak, nonatomic) IBOutlet UIButton *nextButton;
@property (weak, nonatomic) IBOutlet UIButton *prevButton;
@property (weak, nonatomic) IBOutlet UIButton *eqButton;

@property                   LPAudioHost *AudioHost;

- (IBAction)addSongs:(UIButton *)sender;
- (IBAction)doneNamingLocation:(UIButton *)sender;
- (IBAction)playButtonPressed:(UIButton *)sender;
- (IBAction)nextButtonPressed:(UIButton *)sender;
- (IBAction)prevButtonPressed:(UIButton *)sender;
- (IBAction)sliderSeekToProgress:(UISlider *)sender;

@end
