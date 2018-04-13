#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "GRCoreData.h"
#import "GRCoreDataStack.h"
#import "NSManagedObject+GRExtension.h"

FOUNDATION_EXPORT double GRCoreDataVersionNumber;
FOUNDATION_EXPORT const unsigned char GRCoreDataVersionString[];

