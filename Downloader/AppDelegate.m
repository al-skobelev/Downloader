/****************************************************************************
 * AppDelegate.m                                                            *
 * Created by Alexander Skobelev                                            *
 *                                                                          *
 ****************************************************************************/

#import "AppDelegate.h"
#import "CommonUtils.h"

//============================================================================
@interface AppDelegate ()

@property (strong, nonatomic) ConnectionRequest* request;
@end

//============================================================================
@implementation AppDelegate 

@synthesize window = _window;
@synthesize request = _request;

//----------------------------------------------------------------------------
- (NSURL*) fileURL
{
    STATIC (_s_url, [NSURL URLWithString: @"https://s3-eu-west-1.amazonaws.com/izi-packages/d031fbd9-8942-4168-96ea-914a8a1d3f98.tar.gz"]);
    return _s_url;
}

//----------------------------------------------------------------------------
- (ConnectionManager*) connectionManager
{
    STATIC (_s_cmgr, [ConnectionManager new]); 
    return _s_cmgr;
}

//----------------------------------------------------------------------------
- (NSString*) downloadPath
{
    STATIC (_s_path, user_documents_path());
    return _s_path;
}

//----------------------------------------------------------------------------
- (BOOL) startDownloadWithCompletionHandler: (void (^)(NSError* err)) completionHandler
                              updateHandler: (void (^)(size_t downloaded, size_t expected)) updateHandler
{

    NSURLRequest* req = [NSURLRequest requestWithURL: self.fileURL];
    NSString* fname = [[self.fileURL path] lastPathComponent];
    NSString* datapath = STR_ADDPATH (self.downloadPath, fname);

    ConnectionRequest* creq = [ConnectionRequest new];
    creq.request = req;
    creq.datapath = datapath;

    if (completionHandler) {
        creq.completionHandler = ^(ConnectionRequest* req, NSError* err) {
            completionHandler (err);
        };
    }

    if (updateHandler) {
        creq.updateHandler = ^(ConnectionRequest* req, size_t downloaded, size_t expected) {
            updateHandler (downloaded, expected);
        };
    }

    
    if ([self.connectionManager addRequest: creq error: NULL])
    {
        self.request = creq;
        return YES;
    }
    return NO;
}

//----------------------------------------------------------------------------
- (void) stopDownload
{
    [self.connectionManager cancelRequest: self.request];
}

//----------------------------------------------------------------------------
- (void) resetDownload
{
    unlink (STR_FSREP ([self.fileURL path]));
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // Override point for customization after application launch.
    return YES;
}
							
- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
