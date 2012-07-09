/****************************************************************************
 * ConnectionManager.m                                                      *
 * Created by Alexander Skobelev                                            *
 *                                                                          *
 ****************************************************************************/
#import "CommonUtils.h"
#import "ConnectionManager.h"

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
    
    descr = ((_datapath) ? STRF (@"%@ datapath = %@\n}", _datapath)
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
@property (assign, nonatomic) BOOL      serverAcceptsRanges;

@property (strong, nonatomic) NSTimer* retryTimer;
@property (assign, nonatomic) int      retryCount;
@end

@implementation ConnectionInfo

@synthesize request      = _request;
@synthesize connection   = _connection;

@synthesize downloadPath     = _downloadPath;
@synthesize contentLength    = _contentLength;
@synthesize downloadedLength = _downloadedLength;

@synthesize serverAcceptsRanges = _serverAcceptsRanges;
@synthesize retryTimer = _retryTimer;
@synthesize retryCount = _retryCount;
@end


//============================================================================
@interface ConnectionManager ()
{
    NSMutableSet*   _active;
    NSMutableArray* _waited;
    unsigned        _waitQueueLimit;
    NSTimeInterval  _requestDelay;
}

@property (nonatomic, retain) NSDate* lastRequestDate;

//- (int) maybeReactivateConnection: (ConnectionInfo*) cinfo;
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

        //ADD_OBSERVER (kReachabilityChangedNotification, self, onReachabilityNtf:);
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
}

//----------------------------------------------------------------------------
- (ConnectionInfo*) activeConnectionInfoByRequest: (ConnectionRequest*) req
{
    NSSet* set = 
        [_active objectsPassingTest: 
                     ^(ConnectionInfo* cinfo, BOOL* stop) 
                     {
                         return (BOOL)((cinfo.request == req) ? (*stop = YES) : NO); 
                     }];
    
    return [set anyObject];
}

//----------------------------------------------------------------------------
- (ConnectionInfo*) activeConnectionInfoByConnection: (NSURLConnection*) connection
{
    NSSet* set = 
        [_active objectsPassingTest: 
                     ^(ConnectionInfo* cinfo, BOOL* stop) 
                     {
                         return (BOOL)((cinfo.connection == connection) ? (*stop = YES) : NO); 
                     }];
    
    return [set anyObject];
}

//----------------------------------------------------------------------------
- (BOOL) isActiveRequest: (ConnectionRequest*) req
{
    if ([self activeConnectionInfoByRequest: req]) {
        return YES;
    }
    return NO;
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
- (ConnectionInfo*) connectionInfoWithRequest: (ConnectionRequest*) creq
{
    ConnectionInfo* cinfo = [ConnectionInfo new];
    //NSString* host = creq.request.URL.host;
    
    if (creq.datapath) 
    {
        unlink ([creq.datapath fileSystemRepresentation]);
        
        cinfo.downloadPath = STR_ADDEXT (creq.datapath, @"partial");
        NSFileManager* fm = [NSFileManager defaultManager];
        
        if ([fm fileExistsAtPath: cinfo.downloadPath])
        {
            NSError* err;
            NSDictionary* attrs = [fm attributesOfItemAtPath: cinfo.downloadPath
                                                       error: &err];
            if (attrs) {
                cinfo.downloadedLength = attrs.fileSize;
            }
            else {
                unlink ([cinfo.downloadPath fileSystemRepresentation]);
            }
            
            if (cinfo.downloadedLength)
            {
                NSMutableURLRequest* req = [creq.request mutableCopy];
                
                id val = STRF(@"bytes=%d-", cinfo.downloadedLength);
                [req setValue: val forHTTPHeaderField: @"Range"];
                creq.request = req;
            }
        }
    }
    else if (creq.data.length)
    {
        cinfo.downloadedLength += creq.data.length;
    }
    
    NSURLConnection* connection;
    connection = [NSURLConnection connectionWithRequest: creq.request
                                               delegate: self];
    if (connection) 
    {
        cinfo.request = creq;
        cinfo.connection = connection;
        
        //self.lastRequestDate = now;
    }

    return cinfo;
}

//----------------------------------------------------------------------------
- (BOOL) canActivateConnection
{
    if (!_limit || (_active.count < _limit))
    {
        NSDate* now = [NSDate date];
        if (!_lastRequestDate
            || ([now timeIntervalSinceDate: _lastRequestDate] > _requestDelay))
        {
            return YES;
        }
    }
    return NO;
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
            //NSString* host = creq.request.URL.host;

            if (creq.datapath) 
            {
                unlink ([creq.datapath fileSystemRepresentation]);
                
                cinfo.downloadPath = STR_ADDEXT (creq.datapath, @"partial");
                NSFileManager* fm = [NSFileManager defaultManager];
                
                if ([fm fileExistsAtPath: cinfo.downloadPath])
                {
                    NSError* err;
                    NSDictionary* attrs = [fm attributesOfItemAtPath: cinfo.downloadPath
                                                               error: &err];
                    if (attrs) {
                        cinfo.downloadedLength = attrs.fileSize;
                    }
                    else {
                        unlink ([cinfo.downloadPath fileSystemRepresentation]);
                    }
                    
                    if (cinfo.downloadedLength)
                    {
                        NSMutableURLRequest* req = [creq.request mutableCopy];
                   
                        id val = STRF(@"bytes=%d-", cinfo.downloadedLength);
                        [req setValue: val forHTTPHeaderField: @"Range"];
                        creq.request = req;
                    }
                }
            }
            
            NSURLConnection* connection;
            connection = [NSURLConnection connectionWithRequest: creq.request
                                                       delegate: self];
            if (connection) 
            {
                cinfo.request = creq;
                cinfo.connection = connection;

                self.lastRequestDate = now;

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
    [_waited addObject: creq];

    [self activateWaitedRequests];
    return YES;
}


//----------------------------------------------------------------------------
- (void) cancelConnection: (ConnectionInfo*) cinfo
{
    if (cinfo) 
    {
        [cinfo.connection cancel];
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
    
    for (ConnectionInfo* cinfo in _active) [cinfo.connection cancel];

    [_active removeAllObjects];
}

//----------------------------------------------------------------------------
- (void) onRetryConnectionTimer: (NSTimer*) timer
{
    ConnectionInfo* cinfo = 
        [[_active objectsPassingTest: ^(ConnectionInfo* obj, BOOL *stop) {
                    return (BOOL)((obj.retryTimer == timer) ? (*stop = YES) : NO); }]
            
            anyObject];

    if (!cinfo) return;

    [cinfo.retryTimer invalidate];
    cinfo.retryTimer = nil;
    cinfo.connection = [NSURLConnection 
                           connectionWithRequest: cinfo.request.request
                                        delegate: self];
    self.lastRequestDate = [NSDate date];
    DFNLOG(@"RETRY REQUEST %@", cinfo.request.request.URL);
}

//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection
 didReceiveResponse: (NSURLResponse*) response
{
    int http_status = [(NSHTTPURLResponse*)response statusCode];

    ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
    ConnectionRequest* creq = cinfo.request;

    if (! cinfo) return;

    if (http_status >= 400)
    {
        NSError* err = 
            [ConnectionManager errorWithCode: CONNECTION_MANAGER_ERROR_CODE_HTTP_ERROR
                        localizedDescription: STRLF(@"Server returned error: %d", http_status)];
        
        if (creq.completionHandler) creq.completionHandler (cinfo.request, err);
        [self cancelConnection: cinfo];
    }


    cinfo.retryCount = 0;
    cinfo.serverAcceptsRanges = ([[[(NSHTTPURLResponse*)response allHeaderFields]
                                      objectForKey: @"Accept-Ranges"] 
                                     rangeOfString: @"bytes"].length > 0);


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
}


//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection 
     didReceiveData: (NSData*) data
{
    if (data.length)
    {
        ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
        ConnectionRequest* creq = cinfo.request;

        if (cinfo.downloadPath) 
        {
            FILE* file = fopen (STR_FSREP (cinfo.downloadPath), "a");
            if (file) 
            {
                if (data.length != fwrite (data.bytes, 1, data.length, file))
                {
                    DFNLOG(@"ERROR while writing data in file '%@'", creq.datapath);
                }
                fclose (file);
            }
        }
        else
        {
            if (! creq.data) creq.data = [NSMutableData data];
            [creq.data appendData: data];
        }

        cinfo.downloadedLength += data.length;
        if (creq.updateHandler) creq.updateHandler (creq, cinfo.downloadedLength, cinfo.contentLength);
    }
}

//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection 
 didFinishWithError: (NSError*) err
{
    ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
    ConnectionRequest* creq = cinfo.request;

    DFNLOG (@"Connection FINISHED: %@\nERROR: %@\n", creq.request.URL, err);
            
    if ([_active containsObject: cinfo])
    {
        if (err)
        {
            static NSTimeInterval _s_interval[] = { 1.0, 2.0, 3.0 };
            cinfo.connection = nil;
                
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

// //----------------------------------------------------------------------------
// NSString* get_active_iface_addr ()
// {
//     return get_iface_addr (nil);
// }

// //----------------------------------------------------------------------------
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
