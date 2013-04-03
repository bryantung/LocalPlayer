//
//  LPLocationViewController.h
//  LocalPlayer
//
//  Created by Bryan Tung on 4/3/13.
//  Copyright (c) 2013 positivegrid. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface LPLocationViewController : UITableViewController<UITableViewDataSource,UITableViewDelegate>

@property (nonatomic)   NSArray *locList;

@end
