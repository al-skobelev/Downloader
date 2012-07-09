/**************************************************************************** 
 * AppDelegate.h                                                            * 
 * Created by Alexander Skobelev                                            * 
 *                                                                          * 
 ****************************************************************************/
#import <UIKit/UIKit.h>
#import "ConnectionManager.h"

#define APPD ((AppDelegate*)[UIApplication sharedApplication].delegate)

//============================================================================
@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (strong, nonatomic) UIWindow*          window;
@property (readonly)          NSURL*             fileURL;
@property (readonly)          ConnectionManager* connectionManager;
@property (readonly)          NSString*          downloadPath;

- (BOOL) startDownload: (NSString*) file
     completionHandler: (void (^)(NSError* err)) completionHandler
         updateHandler: (void (^)(size_t downloaded, size_t expected)) updateHandler;

- (void) stopDownload;
- (void) resetDownload;

@end

/* EOF */
