/****************************************************************************
 * ConnectionManager.h                                                      *
 * Created by Alexander Skobelev                                            *
 *                                                                          *
 ****************************************************************************/
#import <UIKit/UIKit.h>
#import "ConnectionManager.h"

#define CONNECTION_MANAGER_ERROR_SUBDOMAIN @"ConnectionManager"

enum {
    CONNECTION_MANAGER_ERROR_CODE_NONE,
    CONNECTION_MANAGER_ERROR_CODE_NSURLCONNECTION_CREATE,
    CONNECTION_MANAGER_ERROR_CODE_CANCELLED,
    CONNECTION_MANAGER_ERROR_CODE_SHOULD_DELAY,
    CONNECTION_MANAGER_ERROR_CODE_ACTIVE_LIMIT_EXCEEDED,
    CONNECTION_MANAGER_ERROR_CODE_WAIT_LIMIT_EXCEEDED,
    CONNECTION_MANAGER_ERROR_CODE_HTTP_ERROR,
};


@class ConnectionRequest;

//============================================================================
@interface ConnectionRequest : NSObject

@property (nonatomic, retain) NSURLRequest* request;
@property (nonatomic, retain) NSMutableData* data;
@property (nonatomic, copy)   NSString* datapath;
@property (nonatomic, copy)   void (^completionHandler)(ConnectionRequest* req, NSError* err);
@property (nonatomic, copy)   void (^updateHandler)(ConnectionRequest* req, size_t downloaded, size_t expected);

@property (nonatomic, retain) id userInfo;

@end



//============================================================================
@interface ConnectionManager : NSObject

@property (assign) unsigned limit;
@property (assign) unsigned waitQueueLimit;


// + (ConnectionManager*) defaultManager;

- initWithLimit: (unsigned) limit
 waitQueueLimit: (unsigned) waitQueueLimit
   requestDelay: (NSTimeInterval) delay;

- (BOOL) isActiveRequest: (ConnectionRequest*) req;
- (NSArray*) requestsPassingTest: (BOOL (^)(ConnectionRequest* req, BOOL *stop)) predicate;

- (BOOL) addRequest: (ConnectionRequest*) request
              error: (NSError**) error;

- (void) cancelRequest: (ConnectionRequest*) request;
- (void) cancelAllRequests;

@end
