//
//  LPViewController.m
//  LocalPlayer
//
//  Created by Bryan Tung on 4/2/13.
//  Copyright (c) 2013 positivegrid. All rights reserved.
//

#import "LPViewController.h"

@interface LPViewController ()

@end

@implementation LPViewController

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([object isEqual:_AudioHost]) {
        if ([keyPath isEqualToString:@"playing"]) {
            MPMediaItem *item = [[_loadedMediaCollection items] objectAtIndex:_currentMediaItemIndex];
            NSTimeInterval duration = [[item valueForProperty:MPMediaItemPropertyPlaybackDuration] doubleValue];
            UIImage *artwork = [[item valueForProperty:MPMediaItemPropertyArtwork] imageWithSize:_albumArtView.frame.size];
            if (artwork==nil) {
                artwork = [UIImage imageNamed:@"albumart.jpg"];
            }
            switch (_AudioHost.isPlaying) {
                case YES:
                    [_playButton setTitle:@"Pause" forState:UIControlStateNormal];
                    [_albumArtView setImage:artwork];
                    [_songTitle setText:[item valueForProperty:MPMediaItemPropertyTitle]];
                    [_songArtist setText:[item valueForProperty:MPMediaItemPropertyArtist]];
                    [_songAlbum setText:[item valueForProperty:MPMediaItemPropertyAlbumTitle]];
                    [_songDuration setText:[NSString stringWithFormat:@"%02d:%02d",(int)floorf(duration/60),(int)duration%60]];
                    break;
                    
                default:
                    [_playButton setTitle:@"Play" forState:UIControlStateNormal];
                    break;
            }
            [_playlistTable selectRowAtIndexPath:[NSIndexPath indexPathForRow:_currentMediaItemIndex inSection:0] animated:YES scrollPosition:UITableViewScrollPositionTop];
        }
    }
}

- (IBAction)addSongs:(UIButton *)sender
{
    MPMediaPickerController *songPicker = [[MPMediaPickerController alloc] initWithMediaTypes:MPMediaTypeMusic];
    [songPicker setAllowsPickingMultipleItems:YES];
    [songPicker setDelegate:self];
    [self presentViewController:songPicker animated:YES completion:^{}];
}

- (IBAction)doneNamingLocation:(UIButton *)sender {
    [_locationNameText resignFirstResponder];
    [_locationNameText setHidden:YES];
    [_locationDoneButton setHidden:YES];
    [_selectLocationButton setTitle:_locationNameText.text forState:UIControlStateNormal];
    _locationNameText.text = @"";
    [_selectLocationButton setHidden:NO];
    [_addSongsButton setHidden:NO];
}

- (IBAction)playButtonPressed:(UIButton *)sender
{
    _AudioHost.isPlaying? [_AudioHost stopAUGraph]:[_AudioHost startAUGraph];
}

- (IBAction)nextButtonPressed:(UIButton *)sender
{
    _currentMediaItemIndex = MIN([_loadedMediaCollection count]-1, _currentMediaItemIndex+1);
    [_AudioHost loadNextBufferWithURL:[[[_loadedMediaCollection items] objectAtIndex:_currentMediaItemIndex] valueForProperty:MPMediaItemPropertyAssetURL]];
}

- (IBAction)prevButtonPressed:(UIButton *)sender
{
    _currentMediaItemIndex = MAX(0, _currentMediaItemIndex-1);
    [_AudioHost loadNextBufferWithURL:[[[_loadedMediaCollection items] objectAtIndex:_currentMediaItemIndex] valueForProperty:MPMediaItemPropertyAssetURL]];
}

- (IBAction)sliderSeekToProgress:(UISlider *)sender
{
    
}

- (void)mediaPicker:(MPMediaPickerController *)mediaPicker didPickMediaItems:(MPMediaItemCollection *)mediaItemCollection
{
    [mediaPicker dismissViewControllerAnimated:YES completion:^{
        _loadedMediaCollection = [MPMediaItemCollection collectionWithItems:[mediaItemCollection items]];
        [_playlistTable reloadData];
        
        _currentMediaItemIndex = 0;
        [_AudioHost loadBuffer:[[[mediaItemCollection items] objectAtIndex:_currentMediaItemIndex] valueForProperty:MPMediaItemPropertyAssetURL]];
        
        [_selectLocationButton setHidden:YES];
        [_addSongsButton setHidden:YES];
        [_locationNameText setHidden:NO];
        [_locationDoneButton setHidden:NO];
        [_locationNameText becomeFirstResponder];
    }];
}

- (void)mediaPickerDidCancel:(MPMediaPickerController *)mediaPicker
{
    [mediaPicker dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_loadedMediaCollection count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *reuseSongRow = @"playlistRow";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:reuseSongRow];
    if (cell==nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseSongRow];
    }
    MPMediaItem *mediaItem = [[_loadedMediaCollection items] objectAtIndex:indexPath.row];
    cell.textLabel.text = (NSString *)[mediaItem valueForProperty:MPMediaItemPropertyTitle];
    cell.detailTextLabel.text = (NSString *)[mediaItem valueForProperty:MPMediaItemPropertyArtist];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if ([tableView isEqual:_playlistTable]) {
        _currentMediaItemIndex = indexPath.row;
        [_AudioHost loadNextBufferWithURL:[[[_loadedMediaCollection items] objectAtIndex:_currentMediaItemIndex] valueForProperty:MPMediaItemPropertyAssetURL]];
    }
}

- (void)updateTimingSlider
{
    [_timingSlider setValue:_AudioHost.currentSampleNum animated:YES];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _AudioHost = [[LPAudioHost alloc] init];
    [_AudioHost addObserver:self forKeyPath:@"playing" options:0 context:NULL];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"renewSliderLength"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note){
                                                      float length = [(NSNumber *)[note object] floatValue];
                                                      [_timingSlider setMaximumValue:length*_AudioHost.graphSampleRate];
                                                  }
     ];
    [NSTimer scheduledTimerWithTimeInterval:0.1 target:self selector:@selector(updateTimingSlider) userInfo:nil repeats:YES];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:@"playNextMediaItem"
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note){
                                                      if ([_loadedMediaCollection count]==(_currentMediaItemIndex+1)) {
                                                          [_AudioHost stopAUGraph];
                                                      } else {
                                                          _currentMediaItemIndex++;
                                                          [_AudioHost loadNextBufferWithURL:[[[_loadedMediaCollection items] objectAtIndex:_currentMediaItemIndex] valueForProperty:MPMediaItemPropertyAssetURL]];
                                                      }
                                                  }
     ];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


@end
