/****************************************************************************
 * CommonUtils.h                                                            *
 * Created by Alexander Skobelev                                            *
 *                                                                          *
 ****************************************************************************/

#import <Foundation/Foundation.h>

#define NELEMS(ARR$)   (sizeof(ARR$)/sizeof(ARR$[0]))
#define IS_NULL(OBJ$) ({id obj$ = (OBJ$); BOOL ret$ = ((!obj$ || (obj$ == NSNULL)) ? YES : NO); ret$;})

#define EQL(OBJ1$, OBJ2$)     [(OBJ1$) isEqual: (OBJ2$)]
#define STR_EQL(STR1$, STR2$) [(STR1$) isEqualToString: (STR2$)]

#define IS_KIND(OBJ$, CLASS$) [(OBJ$) isKindOfClass: [CLASS$ class]]
#define HAS_METHOD(OBJ$, MTD$) [(OBJ$) respondsToSelector: @selector(MTD$)]
#define ENSURE_TYPE(TYPE$, OBJ$) ((TYPE$*)({ id obj$ = (OBJ$); if (! IS_KIND(obj$, TYPE$)) obj$ = nil; obj$; }))

#define STATIC_VAR(VAR$, NULLVAL$, INITFORM$)                       \
    static typeof(INITFORM$) VAR$ = (typeof(INITFORM$))(NULLVAL$);  \
    if (VAR$ == (typeof(INITFORM$))(NULLVAL$)) VAR$ = (INITFORM$);                         


#define STATIC(VAR$, INITFORM$)        STATIC_VAR(VAR$, 0, (INITFORM$))
#define STATIC_RETAIN(VAR$, INITFORM$) STATIC(VAR$, (INITFORM$))
#define STATIC_OF_KIND(VAR$, CLASS$)   STATIC(VAR$, (CLASS$ *)[CLASS$ new]))

#define CLAMP(X$, LOW$, HIGH$)                       \
    ({                                               \
        __typeof__(X$)    x$=(X$);                   \
        __typeof__(LOW$)  l$=(LOW$);                 \
        __typeof__(HIGH$) h$=(HIGH$);                \
        (x$ <= l$) ? l$ : ((x$ >= h$) ? h$ : x$);    \
    }) 

#define BOUNDED(X$, LOW$, HIGH$)                   \
    ({                                             \
        __typeof__(X$)    x$=(X$);                 \
        __typeof__(LOW$)  l$=(LOW$);               \
        __typeof__(HIGH$) h$=(HIGH$);              \
        ((x$ >= l$) && (x$ <= h$));                \
    }) 


//============================================================================
// NSNUMBER MACROS 
//
#define NSDOUBLE(VAL$)   [NSNumber numberWithDouble:           (VAL$)]
#define NSFLOAT(VAL$)    [NSNumber numberWithFloat:            (VAL$)]
#define NSINT(VAL$)      [NSNumber numberWithInt:              (VAL$)]
#define NSUINT(VAL$)     [NSNumber numberWithUnsignedInt:      (VAL$)]
#define NSLONG(VAL$)     [NSNumber numberWithLong:             (VAL$)]
#define NSULONG(VAL$)    [NSNumber numberWithUnsignedLong:     (VAL$)]
#define NSLLONG(VAL$)    [NSNumber numberWithLongLong:         (VAL$)]
#define NSULLONG(VAL$)   [NSNumber numberWithUnsignedLongLong: (VAL$)]
#define NSBOOL(VAL$)     [NSNumber numberWithBool:             (VAL$)]

#define NSPOINTER(VAL$)  [NSValue valueWithPointer: (const void*)(VAL$)]
#define NSRANGE(VAL$)    [NSValue valueWithRange: (NSRange)(VAL$)]
#define NSSIZE(VAL$)     [NSValue valueWithSize:  (NSSize)(VAL$)]
#define NSPOINT(VAL$)    [NSValue valueWithPoint: (NSPoint)(VAL$)]
#define NSRECT(VAL$)     [NSValue valueWithRect:  (NSRect)(VAL$)]

#define CGSIZE(VAL$)     [NSValue valueWithCGSize:  (CGSize)(VAL$)]
#define CGPOINT(VAL$)    [NSValue valueWithCGPoint: (CGPoint)(VAL$)]
#define CGRECT(VAL$)     [NSValue valueWithCGRect:  (CGRect)(VAL$)]


#define NSCOLOR(R$, G$, B$, A$) [NSColor colorWithCalibratedRed: (R$) green: (G$) blue: (B$) alpha: (A$)]
#define UICOLOR(R$, G$, B$, A$) [UIColor colorWithRed: (R$) green: (G$) blue: (B$) alpha: (A$)]

#define NSIMAGE(INAME$) [NSImage imageNamed: (INAME$)]
#define UIIMAGE(INAME$) [UIImage imageNamed: (INAME$)]


#define STR_CONCAT(STR$, REST$...)                                  \
    ({                                                              \
         id rest$[] = { nil, ##REST$, nil };                        \
         NSString* str$ = STR$;                                     \
         if (str$) {                                                \
             int i$ = 0;                                            \
             id next$;                                              \
             while ((next$ = rest$ [++i$])) {                       \
                 str$ = [str$ stringByAppendingString: next$];      \
             }                                                      \
         }                                                          \
         str$;                                                      \
    })

#define STR_TRIM(STR$)                                                  \
    ({                                                                  \
        NSString* str$ = (STR$);                                        \
        str$ = ((![str$ length]) ? @"" :                                \
                [str$ stringByTrimmingCharactersInSet:                  \
                          [NSCharacterSet whitespaceAndNewlineCharacterSet]]); \
        str$;                                                           \
    })

#define STR_ADD(STR$, ADDSTR$)         ((NSString*)[(STR$) stringByAppendingString: (ADDSTR$)])
#define STR_ADDPATH(STR$, PATH$)       ((NSString*)[(STR$) stringByAppendingPathComponent: (PATH$)])
#define STR_ADDEXT(STR$, PATHEXT$)     ((NSString*)[(STR$) stringByAppendingPathExtension: (PATHEXT$)])
#define STR_FSREP(STR$)                ((const char*)([(STR$) length] ? [(STR$) fileSystemRepresentation] : ""))

#define STRUTF8(STR$) ((NSString*)[NSString stringWithUTF8String: (const char*)(STR$)])
#define STRC(STR$)    ((NSString*)[NSString stringWithCString: (const char*)(STR$)])

#define STRF(FMT$, args$...) ((NSString*)[NSString stringWithFormat: FMT$ , ##args$])

#define LSTRTBD(KEY_, TABLE_, BUNDLE_, DEFVAL_)                         \
    ((NSString*)[(BUNDLE_) localizedStringForKey: (KEY_) value: (DEFVAL_) table: (TABLE_)])

#define LSTRTD(KEY_, TABLE_, DEFVAL_)                       \
    LSTRTBD (KEY_, TABLE_, [NSBundle mainBundle], DEFVAL_)


#define LSTR(STR$)            LSTRTD(STR$, nil, nil)
#define LSTRF(FMT$, args$...) LSTR([NSString stringWithFormat: FMT$ , ##args$])

#define STRLF(FMT$, args$...) ((NSString*)[NSString stringWithFormat: LSTR(FMT$), ##args$])


//============================================================================
// Notifications related stuff
//
// ENQUEUE_NOTIF_W_STYLE
// ENQUEUE_NOTIF
// POST_NOTIF
//
// ADD_OBSERVER_W_OBJ
// ADD_OBSERVER
//                                                        
// REMOVE_OBSERVER_W_OBJ
// REMOVE_OBSERVER
//                                                        
#define NOTIF(NAME$, OBJ$, INF$)                    \
    [NSNotification notificationWithName: (NAME$)   \
                                  object: (OBJ$)    \
                                userInfo: (INF$)]        

#define ENQUEUE_NOTIF_W_STYLE(NAME$, OBJ$, INF$, STYLE$)    \
    [[NSNotificationQueue defaultQueue]                     \
        enqueueNotification: NOTIF(NAME$, OBJ$, INF$)       \
               postingStyle: (STYLE$)]


#define ENQUEUE_NOTIF(NAME$, OBJ$, INF$)                        \
    ENQUEUE_NOTIF_W_STYLE(NAME$, OBJ$, INF$, NSPostWhenIdle)


#define POST_NOTIF(NAME$, OBJ$, INF$)           \
    [[NSNotificationCenter defaultCenter]       \
        postNotificationName: (NAME$)           \
                      object: (OBJ$)            \
                    userInfo: (INF$)]


#define ADD_DIST_OBSERVER_W_OBJ(NTFNAME$, OBSERV$, SEL$, OBJ$)          \
    {                                                                   \
        id nc$ = [NSDistributedNotificationCenter defaultCenter];       \
        id observ$ = (OBSERV$);                                         \
        id ntfname$ = (NTFNAME$);                                       \
        id obj$ = (OBJ$);                                               \
        [nc$ removeObserver: observ$ name: ntfname$ object: obj$];      \
        [nc$ addObserver: observ$                                       \
                selector: @selector(SEL$)                               \
                    name: ntfname$                                      \
                  object: obj$];                                        \
    }

#define ADD_OBSERVER_W_OBJ(NTFNAME$, OBSERV$, SEL$, OBJ$)               \
    {                                                                   \
        id nc$ = [NSNotificationCenter defaultCenter];                  \
        id observ$ = (OBSERV$);                                         \
        id ntfname$ = (NTFNAME$);                                       \
        id obj$ = (OBJ$);                                               \
        [nc$ removeObserver: observ$ name: ntfname$ object: obj$];      \
        [nc$ addObserver: observ$                                       \
                selector: @selector(SEL$)                               \
                    name: ntfname$                                      \
                  object: obj$];                                        \
    }

#define ADD_OBSERVER(NTFNAME$, OBSERV$, SEL$)           \
    ADD_OBSERVER_W_OBJ(NTFNAME$, OBSERV$, SEL$, nil)


#define REMOVE_OBSERVER_W_OBJ(NTFNAME$, OBSERV$, OBJ$)              \
    [[NSNotificationCenter defaultCenter]                           \
        removeObserver: OBSERV$ name: NTFNAME$ object: OBJ$];       \
    

#define REMOVE_OBSERVER(NTFNAME$, OBSERV$)          \
    REMOVE_OBSERVER_W_OBJ(NTFNAME$, OBSERV$, nil)               


//============================================================================
// PERFORM MACROS
//  CANCEL_PERFORM
//  PERFORM_W_DELAY
//  TRY_PERFORM_SEL
//  TRY_PERFORM_SEL_WOBJ

#define CANCEL_PERFORM(TARGET$, METHOD$, OBJ$)                          \
    [NSObject cancelPreviousPerformRequestsWithTarget: (TARGET$)        \
                                             selector: @selector(METHOD$) \
                                               object: (OBJ$)]

#define PERFORM_W_DELAY(TARGET$, METHOD$, OBJ$, DELAY$) \
    [(TARGET$) performSelector: @selector(METHOD$)      \
                    withObject: (OBJ$)                  \
                    afterDelay: (DELAY$)]                                               

#define PERFORM_ON_MAIN_THREAD(TARGET$, METHOD$, OBJ$, DO_WAIT$)    \
    [(TARGET$) performSelectorOnMainThread: @selector(METHOD$)      \
                                withObject: (OBJ$)                  \
                             waitUntilDone: (DO_WAIT$)]                                               



#ifdef __cplusplus
extern "C" {
#endif

id info_for_key (NSString* key);
id info_for_key_in_bundle (NSString* key, NSBundle* bundle);
NSString* app_name();
NSString* app_bundle_identifier();
NSString* user_app_support_path();
NSString* user_documents_path();

#ifdef __cplusplus
} //extern "C" {
#endif

/* EOF */
