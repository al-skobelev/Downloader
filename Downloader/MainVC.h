//
//  ViewController.h
//  Downloader
//
//  Created by Alexander Skobelev on 05/07/2012.
//  Copyright (c) 2012 IZITEQ. All rights reserved.
//

#import <UIKit/UIKit.h>

//============================================================================
@interface MainVC : UIViewController

@property (weak, nonatomic) IBOutlet UITextField* filenameField;
@property (weak, nonatomic) IBOutlet UIBarButtonItem* stopBtn;
@property (weak, nonatomic) IBOutlet UIBarButtonItem* startBtn;
@property (weak, nonatomic) IBOutlet UIBarButtonItem* resetBtn;

@property (weak, nonatomic) IBOutlet UIProgressView* progressView;
@property (weak, nonatomic) IBOutlet UIActivityIndicatorView* activityIndicator;
@property (weak, nonatomic) IBOutlet UILabel* countLabel;

- (IBAction) onStartBtn;
- (IBAction) onStopBtn;
- (IBAction) onResetBtn;

@end
