#import "CommonUtils.h"

//----------------------------------------------------------------------------
id info_for_key (NSString* key)
{
    return info_for_key_in_bundle (key, [NSBundle mainBundle]);
}

//----------------------------------------------------------------------------
id info_for_key_in_bundle (NSString* key, NSBundle* bundle)
{
    id val = [[bundle localizedInfoDictionary] 
                 objectForKey: key];

    if (! val) {
        val = [[bundle infoDictionary] 
                 objectForKey: key];
    }

    return val;
}


//----------------------------------------------------------------------------
NSString* app_name()
{
    STATIC_RETAIN (_s_name, info_for_key (@"CFBundleName"));
    return _s_name;
}

//----------------------------------------------------------------------------
NSString* app_bundle_identifier ()
{
    STATIC_RETAIN (_s_name, info_for_key (@"CFBundleIdentifier"));
    return _s_name;
}

//----------------------------------------------------------------------------
NSString* user_app_support_path()
{
    STATIC_RETAIN (_s_path, 
                   [(NSSearchPathForDirectoriesInDomains (NSApplicationSupportDirectory,
                                                          NSUserDomainMask,
                                                          YES)) 
                       objectAtIndex: 0]);
    return _s_path;
}

//----------------------------------------------------------------------------
NSString* user_documents_path()
{
    STATIC_RETAIN (_s_path, 
                   [(NSSearchPathForDirectoriesInDomains (NSDocumentDirectory,
                                                          NSUserDomainMask,
                                                          YES)) 
                       objectAtIndex: 0]);
    return _s_path;
}

