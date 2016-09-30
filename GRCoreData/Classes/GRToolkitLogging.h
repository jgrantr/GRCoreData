//
//  GRToolkitLogging.h
//  GRToolkit
//
//  Created by Grant Robinson on 4/23/15.
//  Copyright (c) 2015 Grant Robinson. All rights reserved.
//

#ifndef GRToolkit_GRToolkitLogging_h
#define GRToolkit_GRToolkitLogging_h

#import "DDLog.h"

#ifdef PRODUCTION
static int ddLogLevel = LOG_LEVEL_INFO;
#else
static int ddLogLevel = LOG_LEVEL_INFO;
#endif

#endif
