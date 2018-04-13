//
//  MyLogging.h
//  Pods
//
//  Created by Grant Robinson on 10/6/16.
//
//

#ifndef MyLogging_h
#define MyLogging_h

#define LOG_LEVEL_DEF GRC_ddLogLevel
#define LOG_ASYNC_ENABLED YES

#import <CocoaLumberjack/CocoaLumberjack.h>

#undef LOG_LEVEL_DEF

#define LOG_LEVEL_DEF GRC_ddLogLevel

#endif /* MyLogging_h */
