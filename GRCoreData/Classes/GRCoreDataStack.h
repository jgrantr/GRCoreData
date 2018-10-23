//
//  GRCoreDataStack.h
//  GRCoreData
//
//  Created by Grant Robinson on 9/30/16.
//  Copyright © 2016 Grant Robinson. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>

@class AnyPromise;

typedef void (^GRManagedObjectSaveCompletion)(void);

@interface NSManagedObjectContext (GRExtensions)

- (NSError *) saveWithCompletionHandler:(GRManagedObjectSaveCompletion)completion;

/** then's nothing when the save is completed */
- (AnyPromise *) promiseSave;

@property (nonatomic, copy) GRManagedObjectSaveCompletion saveCompletion;

@end

typedef void (^CoreDataBlock)(NSManagedObjectContext *context);
typedef id (^CoreDataBlockWithValue)(NSManagedObjectContext *context);

@interface GRCoreDataStack : NSObject
{
@protected
	NSManagedObjectModel *model;
	NSPersistentStoreCoordinator *coordinator;
}

+ (instancetype) shared;
+ (void) removeShared;

@property (nonatomic, strong) NSManagedObjectModel *model;
@property (nonatomic, strong) NSManagedObjectContext *masterContext;
@property (nonatomic, strong) NSManagedObjectContext *mainContext;
@property (nonatomic, strong) NSPersistentStoreCoordinator *coordinator;

- (NSFetchRequest *) fetchRequestFromTemplateWithName:(NSString *)name substitutionVariables:(NSDictionary *)variables;

- (NSManagedObjectContext *) childBackgroundContext;
- (NSManagedObjectContext *) scratchContext;
- (void) returnScratchContext:(NSManagedObjectContext *)scratchContext;
- (NSManagedObjectContext *) throwawayContext;

- (void) performBlock:(CoreDataBlock)block completion:(void (^)(void))completionBlock;
/** then's nothing when completed */
- (AnyPromise *) promiseBlock:(CoreDataBlockWithValue)block;

- (void) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *context, id lastObject))afterEach completion:(void (^)(NSMutableSet *updatedObjects))completionBlock;
/** Then's a list of updated objects when completed */
- (AnyPromise *) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *context, id lastObject))afterEach;

- (void) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass completion:(void (^)(NSMutableSet *updatedObjects))completionBlock;
/** Then's a list of updated objects when completed */
- (AnyPromise *) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass;

- (void) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *context, id lastObject))afterEach completion:(void (^)(NSMutableSet *updatedObjects))completionBlock existingObjects:(NSDictionary *)existingObjects;
/** Then's a list of updated objects when completed */
- (AnyPromise *) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *context, id lastObject))afterEach existingObjects:(NSDictionary *)existingObjects;



- (void) deleteAndRecreateStore;

// override in subclasses to support inserting a set of default data when a store is created
- (void) insertDefaultData;
// override in subclasses to change the default location where to keep the store
- (NSURL *)applicationDocumentsDirectory;
// must override in subclasses to point to the store for the application
- (NSURL *) storeUrl;
// must override in subclasses to point to the model for the application
- (NSURL *) modelURL;
// override in subclasses to the change the type of persistent store to use
- (NSString *) persistentStoreType;

@end
