/****************************************************************************
 * MainVC.m                                                                 *
 * Created by Alexander Skobelev                                            *
 *                                                                          *
 ****************************************************************************/

#import "MainVC.h"
#import "AppDelegate.h"
#import "CommonUtils.h"

//============================================================================
@implementation MainVC

@synthesize filenameField = _filenameField;
@synthesize stopBtn       = _stopBtn;
@synthesize startBtn      = _startBtn;
@synthesize resetBtn      = _resetBtn;
@synthesize progressView  = _progressView;
@synthesize activityIndicator = _activityIndicator;
@synthesize countLabel = _countLabel;


//----------------------------------------------------------------------------
- (BOOL) shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation) interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

//----------------------------------------------------------------------------
- (void) showPlainAlertWithTitle: (NSString*) title
                         message: (NSString*) msg
{
    UIAlertView* alert = [[UIAlertView alloc]
                             initWithTitle: title 
                                   message: msg 
                                  delegate: nil
                         cancelButtonTitle: LSTR(@"Close") 
                         otherButtonTitles: nil];
    [alert show];
}

//----------------------------------------------------------------------------
- (void) updateUI: (BOOL) downloading
{
    self.resetBtn.enabled = ! downloading;
    self.startBtn.enabled = ! downloading;
    self.stopBtn.enabled  = downloading;

    self.progressView.hidden = ! downloading;
    //self.countLabel.hidden = ! downloading;

    if (downloading) {
        if (! self.activityIndicator.isAnimating) {
            [self.activityIndicator startAnimating];
        }
    }
    else if (self.activityIndicator.isAnimating) {
        [self.activityIndicator stopAnimating];
    }
    
}

//----------------------------------------------------------------------------
- (void) viewWillAppear: (BOOL) animated
{
    [super viewWillAppear: animated];
    [self updateUI: NO];

    self.progressView.progress = 0;
    self.filenameField.text = [[APPD.fileURL path] lastPathComponent];
    self.countLabel.text = @"";
}


//----------------------------------------------------------------------------
- (void) downloadFinishedWithError: (NSError*) error
{
    [self updateUI: NO];

    if (error)
    {
        [self showPlainAlertWithTitle: @"Download Error"
                              message: [error localizedDescription]];
    }
    else {
        self.progressView.progress = 1.0;
    }
}

//----------------------------------------------------------------------------
- (void) updateDownloaded: (size_t) downloaded
                 expected: (size_t) expected
{
    if (expected > 0)
    {
        self.countLabel.text = STRF (@"%d/%d", downloaded, expected);
        self.progressView.progress = (float) downloaded / expected;
    }
    else {
        self.countLabel.text = STRF (@"%d", downloaded);
        self.progressView.progress = 0;
    }
}

//----------------------------------------------------------------------------
- (IBAction)onStartBtn 
{
    if ([APPD startDownloadWithCompletionHandler: (^(NSError* err) { [self downloadFinishedWithError: err]; })
                                   updateHandler: (^(size_t downloaded, size_t expected) 
                                                   { [self updateDownloaded: downloaded expected: expected]; })])
    {
        [self updateUI: YES];
    }
}

//----------------------------------------------------------------------------
- (IBAction)onStopBtn 
{
    [self updateUI: NO];
    [APPD stopDownload];
}

//----------------------------------------------------------------------------
- (IBAction) onResetBtn 
{
    [self updateUI: NO];
    [APPD resetDownload];
}

- (void)viewDidUnload {
    [self setActivityIndicator:nil];
    [self setCountLabel:nil];
    [super viewDidUnload];
}
@end

/* EOF */
