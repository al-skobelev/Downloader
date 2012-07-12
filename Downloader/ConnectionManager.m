/****************************************************************************
 * ConnectionManager.m                                                      *
 * Created by Alexander Skobelev                                            *
 *                                                                          *
 ****************************************************************************/
#import "CommonUtils.h"
#import "ConnectionManager.h"
#import "Reachability.h"

#include <arpa/inet.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <sys/socket.h>
#include <sys/types.h>

#define IFACE_WIFI "en0"
#define IFACE_WWAN "pdp_ip0"


#define DFNLOG(FMT$, ARGS$...) fprintf (stderr, "%s\n", [STRF(FMT$, ##ARGS$) UTF8String])
// #define DFNLOG(FMT$, ARGS$...) NSLog (@"%s -- " FMT$, __PRETTY_FUNCTION__, ##ARGS$)

// NSString* get_active_iface_addr ();
// NSString* get_iface_addr (const char* iface);



//============================================================================
@implementation ConnectionRequest 

@synthesize request           = _request;
@synthesize data              = _data;
@synthesize datapath          = _datapath;
@synthesize completionHandler = _completionHandler;
@synthesize userInfo          = _userInfo;
@synthesize updateHandler     = _updateHandler;

//----------------------------------------------------------------------------
- (NSString*) description
{
    NSString* descr = STRF(@"%@ = {\n  URL = <%@>", [super description], [_request URL]);
    
    descr = ((_datapath) ? STRF (@"%@ datapath = %@\n}", descr, _datapath)
             : STR_ADD (descr, @"\n}"));
    
    return descr;
}
@end


//============================================================================
@interface ConnectionInfo : NSObject

@property (strong, nonatomic) ConnectionRequest* request;
@property (strong, nonatomic) NSURLConnection*   connection;

@property (copy, nonatomic)   NSString* downloadPath;
@property (assign, nonatomic) size_t    contentLength;
@property (assign, nonatomic) size_t    downloadedLength;

@property (strong, nonatomic) NSTimer*      retryTimer;
@property (assign, nonatomic) int           retryCount;
@property (strong, nonatomic) Reachability* reachability;
@property (assign, nonatomic) NetworkStatus networkStatus;

@property (strong, nonatomic) NSMutableData* buffer;

- (BOOL) setupConnectionWithRequest: (ConnectionRequest*) creq
                           delegate: (id) delegate;


@end

//============================================================================
@implementation ConnectionInfo

@synthesize request      = _request;
@synthesize connection   = _connection;

@synthesize downloadPath     = _downloadPath;
@synthesize contentLength    = _contentLength;
@synthesize downloadedLength = _downloadedLength;

@synthesize retryTimer = _retryTimer;
@synthesize retryCount = _retryCount;

@synthesize reachability = _reachability;
@synthesize networkStatus = _networkStatus;

@synthesize buffer = _buffer;

#define BUFFER_LIMIT 200000

//----------------------------------------------------------------------------
- (BOOL) flushFileBuffer: (BOOL) force
{
    BOOL ret = NO;
    if (self.buffer.length > (force ? 0 : BUFFER_LIMIT))
    {
        FILE* file = fopen (STR_FSREP (self.downloadPath), "a");
        if (file) 
        {
            if (self.buffer.length == fwrite (self.buffer.bytes, 1, self.buffer.length, file))
            {
                DFNLOG(@"Writing %d bytes into file '%@'", self.buffer.length, self.request.datapath);
                ret = YES;
            }
            else 
            {
                DFNLOG(@"ERROR while writing data in file '%@'", self.request.datapath);
                ret = NO;
            }
            fclose (file);
        }
        [self.buffer setLength: 0];
    }
    return ret;
}

//----------------------------------------------------------------------------
- (BOOL) setupConnectionWithRequest: (ConnectionRequest*) creq
                           delegate: (id) delegate
{
    self.downloadPath = nil;
    self.downloadedLength = 0;
    self.contentLength = 0;
    self.buffer = [NSMutableData dataWithCapacity: (BUFFER_LIMIT | 0xFFFF) + 1];

    if (self.connection) {
        [self.connection cancel];
        self.connection = nil;
    }

    if (self.retryTimer) {
        [self.retryTimer invalidate];
        self.retryTimer = nil;
    }

    if (creq.datapath) 
    {
        unlink ([creq.datapath fileSystemRepresentation]);
        
        self.downloadPath = STR_ADDEXT (creq.datapath, @"partial");

        NSFileManager* fm = [NSFileManager defaultManager];
        
        if ([fm fileExistsAtPath: self.downloadPath])
        {
            NSError* err;
            NSDictionary* attrs = [fm attributesOfItemAtPath: self.downloadPath
                                                       error: &err];
            if (attrs) 
            {
                self.downloadedLength = attrs.fileSize;
            
                if (self.downloadedLength)
                {
                    NSMutableURLRequest* req = [creq.request mutableCopy];
                    
                    id val = STRF(@"bytes=%d-", self.downloadedLength);
                    [req setValue: val forHTTPHeaderField: @"Range"];
                    creq.request = req;
                }
            }
            else {
                unlink ([self.downloadPath fileSystemRepresentation]);
            }
        }
    }
    else if (creq.data.length)
    {
        self.downloadedLength = creq.data.length;
    }
    
    self.connection = [NSURLConnection connectionWithRequest: creq.request
                                                    delegate: delegate];
    if (self.connection) 
    {
        self.request = creq;

        self.reachability = [Reachability reachabilityForLocalWiFi];
        self.networkStatus = [self.reachability currentReachabilityStatus];
        [self.reachability startNotifier];
        
        return YES;
    }

    return NO;
}

//----------------------------------------------------------------------------
- (void) cancel
{
    [self flushFileBuffer: YES];
    if (self.connection) {
        [self.connection cancel];
        self.connection = nil;
    }
    
    if (self.retryTimer) {
        [self.retryTimer invalidate];
        self.retryTimer = nil;
    }
}


@end


//============================================================================
@interface ConnectionManager ()
{
    NSMutableSet*   _active;
    NSMutableArray* _waited;
    unsigned        _waitQueueLimit;
    NSTimeInterval  _requestDelay;

    UIBackgroundTaskIdentifier _backgroundTaskId;
}

@property (nonatomic, retain) NSDate* lastRequestDate;

- (void) startBackgroundTask;
- (void) stopBackgroundTask;

@end


//============================================================================
@implementation ConnectionManager

@synthesize limit = _limit;
@synthesize waitQueueLimit = _waitQueueLimit;

@synthesize lastRequestDate = _lastRequestDate;

//----------------------------------------------------------------------------
+ (NSString*) errorDomain
{
    STATIC (_s_domain, STRF(@"%@.%@", app_bundle_identifier(), CONNECTION_MANAGER_ERROR_SUBDOMAIN));
    return _s_domain;
}

//----------------------------------------------------------------------------
+ (NSError*) errorWithCode: (int) code
      localizedDescription: (NSString*) descr
{
    id info = (descr.length 
               ? [NSDictionary dictionaryWithObject: descr
                                             forKey: NSLocalizedDescriptionKey]
               : nil);
    
    NSError* err = [NSError errorWithDomain: [self errorDomain]
                                       code: code
                                   userInfo: info];
    return err;
}

//----------------------------------------------------------------------------
- initWithLimit: (unsigned) limit
 waitQueueLimit: (unsigned) waitQueueLimit
   requestDelay: (NSTimeInterval) delay
{
    if ((self = [super init])) {
        _limit = limit;
        _waitQueueLimit = waitQueueLimit;
        _requestDelay = delay;

        _active = [NSMutableSet new];
        _waited = [NSMutableArray new];

        _backgroundTaskId = UIBackgroundTaskInvalid;

        ADD_OBSERVER (kReachabilityChangedNotification, self, onReachabilityNtf:);
        ADD_OBSERVER (UIApplicationDidEnterBackgroundNotification, self, onEnterBackgroundNtf:);
        ADD_OBSERVER (UIApplicationWillEnterForegroundNotification, self, onExitBackgroundNtf:);
    }
    return self;
}

//----------------------------------------------------------------------------
- init
{
    return [self initWithLimit: 10000
                waitQueueLimit: 10000
                  requestDelay: 0];
}

//----------------------------------------------------------------------------
- (void) dealloc
{
    [self cancelAllRequests];
    REMOVE_OBSERVER (kReachabilityChangedNotification, self);
    REMOVE_OBSERVER (UIApplicationDidEnterBackgroundNotification,  self);
    REMOVE_OBSERVER (UIApplicationWillEnterForegroundNotification, self);
}

//----------------------------------------------------------------------------
- (void) onReachabilityNtf: (NSNotification*) ntf
{
    Reachability* reachability = [ntf object];

    if (ReachableViaWiFi == [reachability currentReachabilityStatus])
    {
        ConnectionInfo* cinfo = [[_active objectsPassingTest: ^(ConnectionInfo* cinfo, BOOL* stop) {
            return (BOOL)((cinfo.reachability == reachability) ? (*stop = YES) : NO); 
        }] anyObject];
        
        if (cinfo && (cinfo.networkStatus != ReachableViaWiFi))
        {
            if (! [self retryConnectionInfo: cinfo])
            {
                [self cancelConnection: cinfo];
            }
        }
    }
}

//----------------------------------------------------------------------------
- (void) onEnterBackgroundNtf: (NSNotification*) ntf
{
    if (_active.count) {
        [self startBackgroundTask];
    }
}

//----------------------------------------------------------------------------
- (void) onExitBackgroundNtf: (NSNotification*) ntf
{
    [self stopBackgroundTask];
}

//----------------------------------------------------------------------------
- (ConnectionInfo*) activeConnectionInfoByRequest: (ConnectionRequest*) req
{
    return [[_active objectsPassingTest: ^(ConnectionInfo* cinfo, BOOL* stop) {
        return (BOOL)((cinfo.request == req) ? (*stop = YES) : NO); 
    }] anyObject];
}

//----------------------------------------------------------------------------
- (ConnectionInfo*) activeConnectionInfoByConnection: (NSURLConnection*) connection
{
    return [[_active objectsPassingTest: ^(ConnectionInfo* cinfo, BOOL* stop) {
        return (BOOL)((cinfo.connection == connection) ? (*stop = YES) : NO); 
    }] anyObject];
}

//----------------------------------------------------------------------------
- (BOOL) isActiveRequest: (ConnectionRequest*) req
{
    return (nil != [self activeConnectionInfoByRequest: req]);
}

//----------------------------------------------------------------------------
- (NSArray*) requestsPassingTest: (BOOL (^)(ConnectionRequest* req, BOOL *stop)) predicate
{
    NSMutableArray* arr = 
        [NSMutableArray arrayWithArray: 
                            [[[_active valueForKey: @"request"]
                                 objectsPassingTest: predicate] allObjects]];
    
    [_waited enumerateObjectsUsingBlock: 
                 ^(ConnectionRequest* req, NSUInteger idx, BOOL *stop)
                 {
                     if (predicate (req, stop)) {
                         [arr addObject: req];
                     }
                 }];

    return arr;
}


//----------------------------------------------------------------------------
- (int) activateRequest: (ConnectionRequest*) creq
{
    DFNLOG(@"ACTIVATE: %@", creq);

    if (!_limit || (_active.count < _limit))
    {
        NSDate* now = [NSDate date];
        if (_lastRequestDate
            && ([now timeIntervalSinceDate: _lastRequestDate] < _requestDelay))
        {
            DFNLOG(@" -- return CONNECTION_MANAGER_ERROR_CODE_SHOULD_DELAY");
            return CONNECTION_MANAGER_ERROR_CODE_SHOULD_DELAY;
        }
        else
        {
            ConnectionInfo* cinfo = [ConnectionInfo new];
            if ([cinfo setupConnectionWithRequest: creq
                                         delegate: self])
            {
                self.lastRequestDate = [NSDate date];
                [_active addObject: cinfo];
                return 0;
            }

            return CONNECTION_MANAGER_ERROR_CODE_NSURLCONNECTION_CREATE;
        }
    }
    return CONNECTION_MANAGER_ERROR_CODE_ACTIVE_LIMIT_EXCEEDED;
}

//----------------------------------------------------------------------------
- (NSTimeInterval) delayForNextRequest
{
    NSTimeInterval delay = 0;
    if (_lastRequestDate) delay = (_requestDelay - [[NSDate date] timeIntervalSinceDate: _lastRequestDate]);
    return (delay > 0 ? delay + 0.001 : 0);
}

//----------------------------------------------------------------------------
- (void) activateWaitedRequests
{
    CANCEL_PERFORM (self, activateWaitedRequests, nil);

    // Commented this as it can prevent from retrying in background
    // if (! (_waited.count && _active.count))
    // {
    //     [self stopBackgroundTask];
    // }
 
    while (_waited.count && (!_limit || (_active.count < _limit)))
    {
        ConnectionRequest* req = [_waited objectAtIndex: 0];
        
        int ecode = [self activateRequest: req];
        if (ecode == CONNECTION_MANAGER_ERROR_CODE_SHOULD_DELAY)
        {
            PERFORM_W_DELAY (self, activateWaitedRequests, nil, [self delayForNextRequest]);
            return;
        }
        else if (ecode == CONNECTION_MANAGER_ERROR_CODE_ACTIVE_LIMIT_EXCEEDED)
        {
            return;
        }
        else if (ecode == CONNECTION_MANAGER_ERROR_CODE_NSURLCONNECTION_CREATE)
        {
            NSError* err = [ConnectionManager errorWithCode: ecode
                                       localizedDescription: LSTR(@"Failed to create NSURLConnection.")];

            if (req.completionHandler) req.completionHandler(req, err);
        }
        
        [_waited removeObjectAtIndex: 0];
    }
}

//----------------------------------------------------------------------------
- (void) stopBackgroundTask
{
    if (_backgroundTaskId != UIBackgroundTaskInvalid) 
    {
        [[UIApplication sharedApplication] endBackgroundTask: _backgroundTaskId];
        _backgroundTaskId = UIBackgroundTaskInvalid;
        DFNLOG(@"STOP BACKGROUND TASK");
    }
}

//----------------------------------------------------------------------------
- (void) startBackgroundTask
{
    if (_backgroundTaskId == UIBackgroundTaskInvalid) 
    {
        _backgroundTaskId = 
            [[UIApplication sharedApplication]
                beginBackgroundTaskWithExpirationHandler: ^{[self stopBackgroundTask];}];
        DFNLOG(@"START BACKGROUND TASK");
    }
}


//----------------------------------------------------------------------------
- (BOOL) addRequest: (ConnectionRequest*) creq
              error: (NSError**) err
{
    if (_waitQueueLimit && (_waited.count >= _waitQueueLimit)) 
    {
        *err = [ConnectionManager 
                  errorWithCode: CONNECTION_MANAGER_ERROR_CODE_WAIT_LIMIT_EXCEEDED
           localizedDescription: LSTR(@"The waiting connections queue overflow.")];
        return NO;
    }

    // [self startBackgroundTask];

    [_waited addObject: creq];

    [self activateWaitedRequests];
    return YES;
}


//----------------------------------------------------------------------------
- (void) cancelConnection: (ConnectionInfo*) cinfo
{
    if (cinfo) 
    {
        
        [cinfo cancel];
        [_active removeObject: cinfo];
        [self activateWaitedRequests];
    }
}

//----------------------------------------------------------------------------
- (void) cancelRequest: (ConnectionRequest*) creq
{
    if (! creq) return;

    NSInteger i = [_waited indexOfObject: creq];
    
    if (i != NSNotFound) {
        [_waited removeObjectAtIndex: i];
    }
    else {
        [self cancelConnection: 
                  [self activeConnectionInfoByRequest: creq]];
    }
}

//----------------------------------------------------------------------------
- (void) cancelAllRequests
{
    [_waited removeAllObjects];
    
    for (ConnectionInfo* cinfo in _active) [cinfo cancel];

    [_active removeAllObjects];
    [self stopBackgroundTask];
}

//----------------------------------------------------------------------------
- (BOOL) retryConnectionInfo: (ConnectionInfo*) cinfo
{
    if (!cinfo) return NO;

    if (cinfo.retryTimer) 
    {
        [cinfo.retryTimer invalidate];
        cinfo.retryTimer = nil;
    }

    if (cinfo.connection) {
        [cinfo.connection cancel];
        cinfo.connection = nil;
    }

    if ([cinfo setupConnectionWithRequest: cinfo.request
                                 delegate: self])
    {
        self.lastRequestDate = [NSDate date];

        DFNLOG(@"RETRY REQUEST %@ (%@)", cinfo.request.request.URL, [cinfo.request.request allHTTPHeaderFields]);
        return YES;
    }
    
    return NO;
}

//----------------------------------------------------------------------------
- (void) onRetryConnectionTimer: (NSTimer*) timer
{
    ConnectionInfo* cinfo = 
        [[_active objectsPassingTest: ^(ConnectionInfo* obj, BOOL *stop) {
                    return (BOOL)((obj.retryTimer == timer) ? (*stop = YES) : NO); }]
            
            anyObject];

    if (! [self retryConnectionInfo: cinfo])
    {
        [self cancelConnection: cinfo];
    }
}


//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection
 didReceiveResponse: (NSURLResponse*) response
{
    int http_status = [(NSHTTPURLResponse*)response statusCode];

    ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
    ConnectionRequest* creq = cinfo.request;

    if (! cinfo) return;

    if (http_status >= 300)
    {
        NSError* err = 
            [ConnectionManager errorWithCode: CONNECTION_MANAGER_ERROR_CODE_HTTP_ERROR
                        localizedDescription: STRLF(@"Server returned error: %d", http_status)];
        
        [cinfo.connection cancel];
        cinfo.connection = nil;
        [_active removeObject: cinfo];
       
        if (creq.completionHandler) creq.completionHandler (cinfo.request, err);
    }


    DFNLOG(@"CONNECTION %p GOT RESPONSE %d HEADERS: %@", connection, http_status, [(NSHTTPURLResponse*)response allHeaderFields]);
    DFNLOG(@"-- INITIAL REQUEST WAS: %@ (%@)", [connection originalRequest], [[connection originalRequest] allHTTPHeaderFields]);

    cinfo.retryCount = 0;
    cinfo.contentLength = response.expectedContentLength;

    if (http_status != 206)
    {
        if (cinfo.downloadedLength)
        {
            if (cinfo.downloadPath) 
            {
                cinfo.downloadedLength = 0;
                unlink ([cinfo.downloadPath fileSystemRepresentation]);
            }
            else if (creq.data.length)
            {
                creq.data = nil;
            }
        }
    }

    cinfo.contentLength += (cinfo.downloadPath ? cinfo.downloadedLength : creq.data.length);
    DFNLOG(@"DOWNLOADED LENGTH: %d, EXPECTED LENGTH: %d, CONTENT LENGTH: %d", (int)cinfo.downloadedLength, (int)response.expectedContentLength, (int)cinfo.contentLength);
}

//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection 
     didReceiveData: (NSData*) data
{
    if (data.length)
    {
        ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
        if (cinfo)
        {
            ConnectionRequest* creq = cinfo.request;

            if (cinfo.downloadPath) 
            {
                if (cinfo.buffer)
                {
                    [cinfo.buffer appendData: data];
                }
                
                [cinfo flushFileBuffer: NO];
            }
            else
            {
                if (! creq.data) creq.data = [NSMutableData data];
                [creq.data appendData: data];
            }

            cinfo.downloadedLength += data.length;
            //DFNLOG(@"CONNECTION %p GOT DATA OF LENGTH: %d, DOWNLOADED LENGTH %d, CONTENT LENGTH: %d", connection, data.length, cinfo.downloadedLength, cinfo.contentLength);
    
            if (creq.updateHandler) creq.updateHandler (creq, cinfo.downloadedLength, cinfo.contentLength);
        }
    }
}

//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection 
 didFinishWithError: (NSError*) err
{
    ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
    ConnectionRequest* creq = cinfo.request;

    DFNLOG (@"Connection %p FINISHED: %@\nERROR: %@\n", connection, creq.request.URL, err);

    if (cinfo)
    {
        [cinfo cancel];

        if (err)
        {
            static NSTimeInterval _s_interval[] = { 1.0, 2.0, 3.0 };
                
            if (cinfo.retryCount < NELEMS(_s_interval))
            {
                cinfo.retryTimer = 
                    [NSTimer scheduledTimerWithTimeInterval: _s_interval [cinfo.retryCount++]
                                                     target: self
                                                   selector: @selector(onRetryConnectionTimer:)
                                                   userInfo: nil
                                                    repeats: NO];
            }                    
        }
        else 
        {
            if (creq.datapath && cinfo.downloadPath)
            {
                unlink (STR_FSREP (creq.datapath));
                    
                NSFileManager* fm = [NSFileManager defaultManager];

                if (! [fm moveItemAtPath: cinfo.downloadPath
                                  toPath: creq.datapath
                                   error: &err])
                {
                    DFNLOG (@"ERROR: Failed to copy partial file to '%@'. %@", creq.datapath, [err localizedDescription]);
                }
            }
        }

        if (! cinfo.retryTimer) 
        {
            [_active removeObject: cinfo];
            if (creq) {
                if (creq.completionHandler) creq.completionHandler (creq, err);
            }
        }
    }
    [self activateWaitedRequests];
}

//----------------------------------------------------------------------------
- (void) connectionDidFinishLoading: (NSURLConnection*) connection 
{
    [self connection: connection didFinishWithError: nil];
}

//----------------------------------------------------------------------------
- (void)  connection: (NSURLConnection*) connection 
    didFailWithError: (NSError*) error
{
    [self connection: connection didFinishWithError: error];
}

//----------------------------------------------------------------------------
- (NSURLRequest*) connection: (NSURLConnection*) connection 
             willSendRequest: (NSURLRequest*) request 
            redirectResponse: (NSURLResponse*) redirectResponse
{
    ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
    ConnectionRequest* creq = cinfo.request;
    
    if (! cinfo) {
        [connection cancel];
        return nil;
    }
    
    if (request.URL) 
    {
        NSURLRequest* old_request = creq.request;
        NSMutableURLRequest* new_request = nil;
        
        NSDictionary* fields = [old_request allHTTPHeaderFields];
        if (fields) 
        {
            new_request = [NSMutableURLRequest 
                              requestWithURL: request.URL
                                 cachePolicy: [old_request cachePolicy]
                             timeoutInterval: [old_request timeoutInterval]];

            NSEnumerator* it = [fields keyEnumerator];
            id key;

            while ((key = [it nextObject])) {
                [new_request setValue: [fields objectForKey: key] 
                   forHTTPHeaderField: key];
            }
        }
        else {
            new_request = (id) request;
        }

        creq.request = new_request;
        return new_request;
    } 
    else {
        //NSLog (@"\n <*>Connection REDIRECT: NIL redirect\n");
    }

    return nil;
}

@end

//----------------------------------------------------------------------------
// NSString* get_active_iface_addr ()
// {
//     return get_iface_addr (nil);
// }

//----------------------------------------------------------------------------
// NSString* get_iface_addr (const char* iface)
// {
//     NSString* nsaddr = nil;

//     struct ifaddrs* interfaces = NULL;
//     struct ifaddrs* temp_addr  = NULL;

//     const char* addr = NULL;

//     if (! getifaddrs (&interfaces))
//     {
//         temp_addr = interfaces;
//         while(temp_addr != NULL)
//         {
//             if ((temp_addr->ifa_addr->sa_family == AF_INET)
//                 && ((temp_addr->ifa_flags & IFF_LOOPBACK) == 0)) // skip loopback
//             {
//                 addr = inet_ntoa (((struct sockaddr_in *) temp_addr->ifa_addr)->sin_addr);

//                 if (addr)
//                 {
//                     BOOL found = NO;
//                     if (iface) {
//                         found = (! strcmp (temp_addr->ifa_name, iface)); 
//                     }
//                     else {
//                         iface = ((0 == strcmp (temp_addr->ifa_name, IFACE_WIFI)) ? IFACE_WIFI : // wifi on iphone
//                                  (0 == strcmp (temp_addr->ifa_name, IFACE_WWAN)  ? IFACE_WWAN : // cellurar network on iphone
//                                   NULL));

//                         found = (NULL != iface);
//                     }

//                     if (found)
//                     {
//                         nsaddr = [NSString stringWithUTF8String: addr];
//                         break;
//                     }
//                 }

//             }
//             temp_addr = temp_addr->ifa_next;
//         }
//     }

//     DFNLOG (@"IFACE NAME: %s IP: %s", iface ?: "UNKNOWN", addr ?: "???.???.???.???");

//     freeifaddrs (interfaces);
//     return nsaddr;
// }

/* EOF */
