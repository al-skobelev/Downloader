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

NSString* get_active_iface_addr ();
NSString* get_iface_addr (const char* iface);

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
@property (strong, nonatomic) Reachability*      reachability;

@property (copy, nonatomic)   NSString* downloadPath;
@property (assign, nonatomic) size_t    contentLength;
@property (assign, nonatomic) size_t    downloadedLength;
@property (assign, nonatomic) BOOL      serverAcceptsRanges;
@property (assign, nonatomic) NetworkStatus reachabilityStatus;;
@property (copy, nonatomic)   NSString* ifaddr;

@end

@implementation ConnectionInfo

@synthesize request      = _request;
@synthesize connection   = _connection;
@synthesize reachability = _reachability;

@synthesize downloadPath     = _downloadPath;
@synthesize contentLength    = _contentLength;
@synthesize downloadedLength = _downloadedLength;

@synthesize serverAcceptsRanges = _serverAcceptsRanges;
@synthesize reachabilityStatus  = _reachabilityStatus;
@synthesize ifaddr = _ifaddr;
@end


//============================================================================
@interface ConnectionManager ()
{
    NSMutableSet*   _active;
    NSMutableSet*   _unreachable;
    NSMutableArray* _waited;
    unsigned       _waitQueueLimit;
    NSTimeInterval _requestDelay;
}

@property (nonatomic, retain) NSDate* lastRequestDate;

- (int) maybeReactivateConnection: (ConnectionInfo*) cinfo;
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
        _unreachable = [NSMutableSet new];
        _waited = [NSMutableArray new];

        ADD_OBSERVER (kReachabilityChangedNotification, self, onReachabilityNtf:);
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
            NSString* host = creq.request.URL.host;

            cinfo.reachability = [Reachability reachabilityWithHostName: host];
            cinfo.reachabilityStatus = [cinfo.reachability currentReachabilityStatus];
            cinfo.ifaddr = get_active_iface_addr();

            [cinfo.reachability startNotifier];

            if (NotReachable == cinfo.reachabilityStatus)
            {
                cinfo.request = creq;
                [_unreachable addObject: cinfo];

                DFNLOG(@" -- ADDED TO UNREACHABLE -- return 0");
                return 0;
            }

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
    return (delay > 0 ? delay : 0);
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
            NSTimeInterval delay = [self delayForNextRequest] + 0.001;
            PERFORM_W_DELAY (self, activateWaitedRequests, nil, delay);
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

    NSTimeInterval delay = [self delayForNextRequest] + 0.001;
    
    PERFORM_W_DELAY (self, activateWaitedRequests, nil, delay);
    return YES;
}

//----------------------------------------------------------------------------
- (void) cancelRequest: (ConnectionRequest*) creq
{
    if (! creq) return;

    NSInteger i = [_waited indexOfObject: creq];
    
    if (i != NSNotFound) {
        [_waited removeObjectAtIndex: i];
    }
    else
    {
        ConnectionInfo* cinfo = [self activeConnectionInfoByRequest: creq];
        if (cinfo) {
            [cinfo.connection cancel];
            [_active removeObject: cinfo];
        }
    }
}

//----------------------------------------------------------------------------
- (void) cancelAllRequests
{
    [_waited removeAllObjects];
    
    for (ConnectionInfo* cinfo in _active) [cinfo.connection cancel];

    [_active removeAllObjects];
    [_unreachable removeAllObjects];
}

//----------------------------------------------------------------------------
// - (void) stopAllRequests
// {
//     [_waited removeAllObjects];
    
//     for (ConnectionInfo* cinfo in _active) [cinfo.connection cancel];
//     [_active removeAllObjects];
// }


// NSURLConnection delegate's methods
//----------------------------------------------------------------------------
// - (void) connection: (NSURLConnection*) connection 
//          decideDestinationWithSuggestedFilename: (NSString *) filepath
// {
//     Cons* cons = [self activeConnectionInfoByConnection: connection];

//     if (! cons) return;

//     ConnectionRequest* creq = CONS_REQ(cons);
//     NSString* filename = [filepath lastPathComponent];
//     NSString* path = self.defaultDownloadPath;

//     if (creq) { 
//         if (! [creq.filename isAbsolutePath]) 
//         {
//             path = STR_ADDPATH(path, creq.filename);
//         } else {
//             path = [NSString stringWithString: creq.filename];
//         }
//     }

//     if (path.length)
//     {        
//         BOOL pathIsDir = NO;
//         if ([[NSFileManager defaultManager] 
//                 fileExistsAtPath: path 
//                      isDirectory: &pathIsDir]
//             && pathIsDir)
//         {
//             path = [path stringByAppendingPathComponent: filename];
//         } 
//         else 
//         {
//             NSString* ext = [filename pathExtension];
//             if (([path pathExtension].length == 0)
//                  && (ext.length > 0))
//             {
//                 path = STR_ADDEXT (path, ext);
//             }
//         }    

//         [creq setFilename: path];
//         [connection setDestination: path allowOverwrite: YES];
//     }
// }

// - (NSURLRequest *)connection:(NSURLConnection *)connection willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)response;

//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection
 didReceiveResponse: (NSURLResponse*) response
{
    ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
    // ConnectionRequest* creq = cinfo.request;

    cinfo.serverAcceptsRanges = ([[[(NSHTTPURLResponse*)response allHeaderFields]
                                      objectForKey: @"Accept-Ranges"] 
                                     rangeOfString: @"bytes"].length > 0);
    if (cinfo.downloadedLength)
    {
        if ([(NSHTTPURLResponse*)response statusCode] != 206)
        {
            cinfo.downloadedLength = 0;
            unlink ([cinfo.downloadPath fileSystemRepresentation]);
        }
    }
    cinfo.contentLength = cinfo.downloadedLength + response.expectedContentLength;
}


// - (NSCachedURLResponse *)connection:(NSURLConnection *)connection willCacheResponse:(NSCachedURLResponse *)cachedResponse;

//----------------------------------------------------------------------------
- (void) connection: (NSURLConnection*) connection 
     didReceiveData: (NSData*) data
{
    if (data.length)
    {
        ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
        ConnectionRequest* creq = cinfo.request;

        if (cinfo.downloadPath) {
            FILE* file = fopen (STR_FSREP (cinfo.downloadPath), "a");
            if (file) {
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
- (void)  connection: (NSURLConnection*) connection 
  didFinishWithError: (NSError*) err
{
    @autoreleasepool
    {
        ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
        ConnectionRequest* creq = cinfo.request;

        DFNLOG (@"Connection FINISHED: %@\nERROR: %@\n", creq.request.URL, err);
        [cinfo.reachability stopNotifier];
            
        if ([_active containsObject: cinfo])
        {
            if (! err)
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
            else // if ((err.code == -1005) || (err.code == -1009)) // "The Internet connection appears to be offline."
            {
                if (0 == [self maybeReactivateConnection: cinfo])
                {
                    [self activateWaitedRequests];
                    return;
                }
                [connection cancel];
            }

            [_active removeObject: cinfo];
            if (creq) {
                if (creq.completionHandler) creq.completionHandler (creq, err);
            }
        }

        [self activateWaitedRequests];
    }
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

////----------------------------------------------------------------------------
//- (void)                   connection: (NSURLConnection*)connection 
//  didReceiveAuthenticationChallenge: (NSURLAuthenticationChallenge*) challenge
//{
//}
//
////----------------------------------------------------------------------------
//- (void)        connection: (NSURLConnection*) connection 
//  didReceiveDataOfLength: (unsigned) length
//{ }
//

//----------------------------------------------------------------------------
- (NSURLRequest*) connection: (NSURLConnection*) connection 
             willSendRequest: (NSURLRequest*) request 
            redirectResponse: (NSURLResponse*) redirectResponse
{
    ConnectionInfo* cinfo = [self activeConnectionInfoByConnection: connection];
    ConnectionRequest* creq = cinfo.request;
    
    if (! creq) {
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

//----------------------------------------------------------------------------
- (int) maybeReactivateConnection: (ConnectionInfo*) cinfo
{
    DFNLOG(@"MAY BE REACTIVATE: %@", cinfo);
    int res = -1;
    if (cinfo)
    {
        NetworkStatus rstatus = [cinfo.reachability currentReachabilityStatus];

        cinfo.reachabilityStatus = rstatus;

        BOOL active = [_active containsObject: cinfo];
        BOOL unreachable = [_unreachable containsObject: cinfo];
        BOOL reactivate = YES;

        NSString* ifaddr = get_active_iface_addr();
        if (active && (NotReachable != rstatus))
        {
            if (ifaddr && STR_EQL (cinfo.ifaddr, ifaddr))
            {
                DFNLOG(@"SAME IFADDR: WILL NOT REACTIVATE ACTIVE");
                return 0;
            }

        }
        if ((NotReachable == rstatus) && unreachable)
        {
            DFNLOG(@"NOT REACHABLE YET: WILL NOT REACTIVATE");
            return 0;
        }

        // if (NotReachable != rstatus)
        // {
        //     // don't reactivate downloads that can not be resumed?
        //     reactivate = !active || cinfo.serverAcceptsRanges;
        // }

        if (reactivate) 
        {
            DFNLOG(@"WILL REACTIVATE");

            if (active) 
            {
                DFNLOG(@"IT WAS ACTIVE: CANCEL IT");

                [_active removeObject: cinfo];
                [cinfo.connection cancel];
                cinfo.connection = nil;
            }
            else {
                [_unreachable removeObject: cinfo];
            }

            res = [self activateRequest: cinfo.request];

            if (res)
            {
                DFNLOG(@"FAILED TO REACTIVATE");

                if ((res == CONNECTION_MANAGER_ERROR_CODE_ACTIVE_LIMIT_EXCEEDED)
                    || (res == CONNECTION_MANAGER_ERROR_CODE_SHOULD_DELAY))
                {
                    if (_waited.count) [_waited insertObject: cinfo.request atIndex: 0];
                    else [_waited addObject: cinfo.request];
                    
                    res = 0;
                }
            }
        }
    }

    DFNLOG(@"MAY BE REACTIVATE RETURN %d", res);
    return res;
}

//----------------------------------------------------------------------------
- (void) onReachabilityNtf: (NSNotification*) ntf
{
    Reachability* reachability = ntf.object;

    BOOL active = YES;
    ConnectionInfo* cinfo = 
        [[_active objectsPassingTest: ^(ConnectionInfo* obj, BOOL *stop) {
            return (BOOL)((obj.reachability == reachability) ? (*stop = YES) : NO); }]

            anyObject];

    if (! cinfo) {
        cinfo = [[_unreachable objectsPassingTest: ^(ConnectionInfo* obj, BOOL *stop) {
                    return (BOOL)((obj.reachability == reachability) ? (*stop = YES) : NO); }]

                    anyObject];
        active = NO;
    }

    DFNLOG (@"REACHABILITY NTF FOR %@", cinfo.request);

    int res = [self maybeReactivateConnection: cinfo];
    if (res)
    {
        NSError* err = [ConnectionManager errorWithCode: res
                                   localizedDescription: LSTR(@"Failed to reactivate request.")];
        
        ConnectionRequest* creq = cinfo.request;
        if (creq.completionHandler) creq.completionHandler (creq, err);
    }
}

@end

//----------------------------------------------------------------------------
NSString* get_active_iface_addr ()
{
    return get_iface_addr (nil);
}

//----------------------------------------------------------------------------
NSString* get_iface_addr (const char* iface)
{
    NSString* nsaddr = nil;

    struct ifaddrs* interfaces = NULL;
    struct ifaddrs* temp_addr  = NULL;

    const char* addr = NULL;

    if (! getifaddrs (&interfaces))
    {
        temp_addr = interfaces;
        while(temp_addr != NULL)
        {
            if ((temp_addr->ifa_addr->sa_family == AF_INET)
                && ((temp_addr->ifa_flags & IFF_LOOPBACK) == 0)) // skip loopback
            {
                addr = inet_ntoa (((struct sockaddr_in *) temp_addr->ifa_addr)->sin_addr);

                if (addr)
                {
                    BOOL found = NO;
                    if (iface) {
                        found = (! strcmp (temp_addr->ifa_name, iface)); 
                    }
                    else {
                        iface = ((0 == strcmp (temp_addr->ifa_name, IFACE_WIFI)) ? IFACE_WIFI : // wifi on iphone
                                 (0 == strcmp (temp_addr->ifa_name, IFACE_WWAN)  ? IFACE_WWAN : // cellurar network on iphone
                                  NULL));

                        found = (NULL != iface);
                    }

                    if (found)
                    {
                        nsaddr = [NSString stringWithUTF8String: addr];
                        break;
                    }
                }

            }
            temp_addr = temp_addr->ifa_next;
        }
    }

    DFNLOG (@"IFACE NAME: %s IP: %s", iface ?: "UNKNOWN", addr ?: "???.???.???.???");

    freeifaddrs (interfaces);
    return nsaddr;
}

/* EOF */
