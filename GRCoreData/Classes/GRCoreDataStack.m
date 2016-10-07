//
//  GRCoreDataStack.m
//  GRCoreData
//
//  Created by Grant Robinson on 9/30/16.
//  Copyright © 2016 Grant Robinson. All rights reserved.
//

#import "GRCoreDataStack.h"
#import "NSManagedObject+GRExtension.h"
#import "DDLog.h"
#import <objc/runtime.h>
#import <PromiseKit/PromiseKit.h>

#import "MyLogging.h"


static char keySaveCompletionHandler;

dispatch_queue_t contextSaveQueue;

static GRCoreDataStack *_helper = nil;

static NSMutableDictionary *blockSaveDict;

@implementation NSManagedObjectContext (GRExtensions)

- (GRManagedObjectSaveCompletion) saveCompletion {
	return objc_getAssociatedObject(self, &keySaveCompletionHandler);
}

- (void) setSaveCompletion:(GRManagedObjectSaveCompletion)saveCompletion {
	objc_setAssociatedObject(self, &keySaveCompletionHandler, saveCompletion, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSError *) saveWithCompletionHandler:(GRManagedObjectSaveCompletion)completion {
	if (completion) {
		self.saveCompletion = completion;
	}
	GRManagedObjectSaveCompletion localCompletion = self.saveCompletion;
	__block NSError *error = nil;
	__block BOOL saved = NO;
	[self performBlockAndWait:^{
		[self obtainPermanentIDsForObjects:self.insertedObjects.allObjects error:&error];
		if (error) {
			DDLogError(@"could not obtain permanent IDs: %@", error);
		}
		saved = [self save:&error];
		if (localCompletion) {
			NSNumber *key = @([localCompletion hash]);
			if ([blockSaveDict objectForKey:key]) {
				DDLogInfo(@"marking block %@ as having saved", key);
				blockSaveDict[key] = @(YES);
			}
		}
		self.saveCompletion = nil;
	}];
	if (!saved || error) {
		return error;
	}
	return nil;
}

- (AnyPromise *) promiseSave {
	return [AnyPromise promiseWithResolverBlock:^(PMKResolver  _Nonnull resolve) {
		NSError *error = [self saveWithCompletionHandler:nil];
		resolve(error);
	}];
}

@end

@interface GRCoreDataStack()
{
	NSManagedObjectContext *backgroundContext;
	NSManagedObjectContext *mainContext;
	NSMutableSet *scratchContexts;
	NSManagedObjectContext *excludeTemp;
	GRManagedObjectSaveCompletion saveTemp;
}

@property (nonatomic, strong) NSManagedObjectContext *backgroundContext;

@end

@implementation GRCoreDataStack

+ (DDLogLevel) ddLogLevel {
	return ddLogLevel;
}

+ (void) ddSetLogLevel:(DDLogLevel)logLevel {
	ddLogLevel = logLevel;
}

@synthesize masterContext, mainContext, model, coordinator, backgroundContext;

+ (void) load {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		contextSaveQueue = dispatch_queue_create("net.mr-r.GRToolkit.ContextSaveQueue", NULL);
		blockSaveDict = [[NSMutableDictionary alloc] initWithCapacity:5];
	});
}

+ (GRCoreDataStack *) shared {
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		dispatch_sync(contextSaveQueue, ^{
			_helper = [[self alloc] init];
		});
	});
	return _helper;
}

+ (void) removeShared {
	_helper = nil;
}

- (id) init {
	self = [super init];
	if (self) {
		scratchContexts = [NSMutableSet setWithCapacity:1];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:nil];
	}
	return self;
}

- (void) dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void) saveMasterMergingChildrenExcludingContext:(NSManagedObjectContext *)exclude completion:(GRManagedObjectSaveCompletion)saveCompletion {
	[masterContext performBlock:^{
		if ([NSThread isMainThread]) {
			DDLogWarn(@"^^^^^^^^^^^^^^^^ masterContext save is happening on main thread");
		}
		NSError *error = nil;
		excludeTemp = exclude;
		saveTemp = saveCompletion;
		BOOL saved = [masterContext save:&error];
		if (!saved || error) {
			DDLogError(@"could not save master context: %@", error);
			[masterContext rollback];
		}
		excludeTemp = nil;
		saveTemp = nil;
	}];
}

- (void) managedObjectContextDidSave:(NSNotification *)note {
	NSManagedObjectContext *object = note.object;
	GRManagedObjectSaveCompletion saveCompletion = object.saveCompletion;
	NSManagedObjectContext *localExclude = excludeTemp;
	GRManagedObjectSaveCompletion localSave = saveTemp;
	if ([scratchContexts containsObject:object]) {
		[self saveMasterMergingChildrenExcludingContext:nil completion:saveCompletion];
	}
	else if (object == backgroundContext) {
		[self saveMasterMergingChildrenExcludingContext:backgroundContext completion:saveCompletion];
	}
	else if (object == mainContext) {
		[self saveMasterMergingChildrenExcludingContext:mainContext completion:saveCompletion];
	}
	else if (object == masterContext) {
		if (localExclude != mainContext) {
			dispatch_async(dispatch_get_main_queue(), ^{
				[mainContext mergeChangesFromContextDidSaveNotification:note];
				if (localSave) {
					localSave();
				}
			});
		}
		if (localExclude != backgroundContext) {
			[backgroundContext performBlock:^{
				[backgroundContext mergeChangesFromContextDidSaveNotification:note];
				if (localSave) {
					dispatch_async(dispatch_get_main_queue(), ^{
						localSave();
					});
				}
			}];
		}
	}
}

- (id) doFetchAndReturnResult:(NSFetchRequest *)request context:(NSManagedObjectContext *)_context {
	NSError* error = nil;
	NSArray *results = [_context executeFetchRequest:request error:&error];
	if (error) {
		DDLogError(@"error doing fetch %@: %@", request, error);
	}
	if (results == nil) {
		//TODO handle the error
		return nil;
	}
	if ([results count] > 0) {
		return [results objectAtIndex:0];
	}
	return nil;
}

- (void) insertDefaultData {
	[self insertDefaultData:NO];
}

- (void) insertDefaultData:(BOOL)sendStoreDeletedNotification {
	
}

- (NSFetchRequest *) fetchRequestFromTemplateWithName:(NSString *)name substitutionVariables:(NSDictionary *)variables {
	NSFetchRequest *request = [model fetchRequestFromTemplateWithName:name substitutionVariables:variables];
	request.shouldRefreshRefetchedObjects = YES;
	return request;
}

- (NSURL *)applicationDocumentsDirectory {
	return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

- (NSURL *) storeUrl {
	return nil;
}

- (NSURL *) modelURL {
	return nil;
}

- (void) addPeristentStore {
	NSError *error = nil;
	NSURL *storeURL = [self storeUrl];
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
							 [NSNumber numberWithBool:YES],
							 NSMigratePersistentStoresAutomaticallyOption,
							 [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
	if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType
								   configuration:nil URL:storeURL options:options error:&error])
	{
		error = nil;
		[fileManager removeItemAtURL:storeURL error:&error];
		error = nil;
		if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType
									   configuration:nil URL:storeURL options:options error:&error])
		{
			/*
			 Replace this implementation with code to handle the error appropriately.
			 
			 abort() causes the application to generate a crash log and terminate.
			 You should not use this function in a shipping application, although it may be useful during development.
			 If it is not possible to recover from the error, display an alert panel that instructs the user to quit
			 the application by pressing the Home button.
			 
			 Typical reasons for an error here include:
			 * The persistent store is not accessible;
			 * The schema for the persistent store is incompatible with current managed object model.
			 Check the error message to determine what the actual problem was.
			 
			 
			 If the persistent store is not accessible, there is typically something wrong with the file path.
			 Often, a file URL is pointing into the application's resources directory instead of a writeable directory.
			 
			 If you encounter schema incompatibility errors during development, you can reduce their frequency by:
			 * Simply deleting the existing store:
			 [[NSFileManager defaultManager] removeItemAtURL:storeURL error:nil]
			 
			 * Performing automatic lightweight migration by passing the following dictionary as the options parameter:
			 [NSDictionary dictionaryWithObjectsAndKeys:
			 [NSNumber numberWithBool:YES],
			 NSMigratePersistentStoresAutomaticallyOption,
			 [NSNumber numberWithBool:YES], NSInferMappingModelAutomaticallyOption, nil];
			 
			 Lightweight migration will only work for a limited set of schema changes;
			 consult "Core Data Model Versioning and Data Migration Programming Guide" for details.
			 
			 */
			DDLogError(@"Unresolved error %@, %@", error, [error userInfo]);
			//			abort();
		}
	}
}

- (NSManagedObjectContext *) masterContext {
	if (masterContext != nil) {
		return masterContext;
	}
	NSPersistentStoreCoordinator *storeCoordinator = self.coordinator;
	if (storeCoordinator != nil) {
		self.masterContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
		[masterContext performBlockAndWait:^{
			[masterContext setStalenessInterval:0.0];
			[masterContext setPersistentStoreCoordinator:storeCoordinator];
			[masterContext setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
		}];
	}
	
	return masterContext;
}

- (NSManagedObjectContext *) mainContext {
	
	if (mainContext != nil) {
		return mainContext;
	}
	
	NSManagedObjectContext *master = self.masterContext;
	if (master != nil) {
		self.mainContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
		[mainContext performBlockAndWait:^{
			[mainContext setStalenessInterval:0.0];
			[mainContext setParentContext:master];
			[mainContext setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
		}];
	}
	return mainContext;
}

- (NSManagedObjectContext *) childBackgroundContext {
	if (backgroundContext == nil) {
		NSManagedObjectContext *master = self.masterContext;
		self.backgroundContext = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
		[backgroundContext performBlockAndWait:^{
			[backgroundContext setStalenessInterval:0.0];
			[backgroundContext setParentContext:master];
			[backgroundContext setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
		}];
	}
	return backgroundContext;
}

- (NSManagedObjectContext *) throwawayContext {
	NSManagedObjectContext *master = self.masterContext;
	NSManagedObjectContext *throwaway = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
	[throwaway performBlockAndWait:^{
		[throwaway setStalenessInterval:0.0f];
		[throwaway setParentContext:master];
		[throwaway setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
	}];
	return throwaway;
}

- (NSManagedObjectContext *) scratchContext {
	NSManagedObjectContext *master = self.masterContext;
	NSManagedObjectContext *scratch = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
	[scratch performBlockAndWait:^{
		[scratch setStalenessInterval:0.0];
		[scratch setParentContext:master];
		[scratch setMergePolicy:NSMergeByPropertyStoreTrumpMergePolicy];
	}];
	[scratchContexts addObject:scratch];
	return scratch;
}

- (void) returnScratchContext:(NSManagedObjectContext *)scratchContext {
	[scratchContexts removeObject:scratchContext];
}

- (void) performBlock:(CoreDataBlock)block completion:(void (^)())completionBlock {
	NSManagedObjectContext *childContext = [self childBackgroundContext];
	[childContext performBlock:^{
		childContext.saveCompletion = completionBlock;
		NSNumber *key = @([completionBlock hash]);
		if (completionBlock) {
			DDLogVerbose(@"completion block key is %@", key);
			blockSaveDict[key] = @(NO);
		}
		block(childContext);
		if (completionBlock) {
			if ([blockSaveDict[key] boolValue] == NO) {
				DDLogInfo(@"executing completion block %@ because the context wasn't saved", key);
				dispatch_async(dispatch_get_main_queue(), ^{
					completionBlock();
				});
			}
			[blockSaveDict removeObjectForKey:key];
		}
	}];
}

- (void) performBlock:(CoreDataBlockWithValue)block completionWithValue:(void (^)(id value))valueCompletion {
	NSManagedObjectContext *childContext = [self childBackgroundContext];
	[childContext performBlock:^{
		id value = block(childContext);
		dispatch_async(dispatch_get_main_queue(), ^{
			valueCompletion(value);
		});
	}];
}

- (AnyPromise *) promiseBlock:(CoreDataBlockWithValue)block {
	return [AnyPromise promiseWithResolverBlock:^(PMKResolver  _Nonnull resolve) {
		[self performBlock:block completionWithValue:^(id value) {
			resolve(value);
		}];
	}];
}

- (void) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *, id))afterEach completion:(void (^)(NSMutableSet *))completionBlock existingObjects:(NSDictionary *)existingObjects
{
	[self performBlock:^(NSManagedObjectContext *_context) {
		NSMutableSet *updatedObjects = [modelClass loadObjectsFromArray:values intoContext:_context afterEach:afterEach saveWhenDone:NO objectsById:existingObjects];
		NSError *error = [_context saveWithCompletionHandler:^{
			if (completionBlock) {
				completionBlock(updatedObjects);
			}
		}];
		if (error) {
			DDLogError(@"error saving loaded data: %@", error);
			[_context rollback];
		}
	} completion:nil];
	
}

- (AnyPromise *) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *, id))afterEach existingObjects:(NSDictionary *)existingObjects
{
	return [AnyPromise promiseWithResolverBlock:^(PMKResolver  _Nonnull resolve) {
		[self loadModelObjects:values usingClass:modelClass afterEach:afterEach completion:^(NSMutableSet *updatedObjects)
		{
			resolve(updatedObjects);
		} existingObjects:existingObjects];
	}];
}

- (void) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *, id))afterEach completion:(void (^)(NSMutableSet *))completionBlock
{
	[self loadModelObjects:values usingClass:modelClass afterEach:afterEach completion:completionBlock existingObjects:nil];
}

- (AnyPromise *) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass afterEach:(void (^)(NSManagedObjectContext *, id))afterEach
{
	return [self loadModelObjects:values usingClass:modelClass afterEach:afterEach existingObjects:nil];
}

- (void) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass completion:(void (^)(NSMutableSet *))completionBlock {
	[self loadModelObjects:values usingClass:modelClass afterEach:nil completion:completionBlock];
}

- (AnyPromise *) loadModelObjects:(NSArray *)values usingClass:(Class)modelClass {
	return [self loadModelObjects:values usingClass:modelClass afterEach:nil existingObjects:nil];
}

- (NSManagedObjectModel *) model {
	if (model != nil) {
		return model;
	}
	NSURL *modelURL = [self modelURL];
	model = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
	return model;
	
}

- (NSPersistentStoreCoordinator *) coordinator {
	if (coordinator != nil) {
		return coordinator;
	}
	
	coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:self.model];
	[self addPeristentStore];
	
	return coordinator;
}

- (void) deleteAndRecreateStore {
	// remove objects from Core Data store
	// first, do the main context
	self.mainContext = nil;
	// next, do the background context on it's private queue
	[self.backgroundContext performBlockAndWait:^{
		[self.backgroundContext reset];
	}];
	self.backgroundContext = nil;
	[self.masterContext performBlockAndWait:^{
		[self.masterContext reset];
	}];
	self.masterContext = nil;
	// clear the cache once before removing our persistent store
	[NSManagedObject clearCache];
	// execute the rest of this asynchronously, to give other threads a chance to lock/unlock the persistent store coordinator
	dispatch_async(dispatch_get_main_queue(), ^{
		NSURL *storeUrl = self.storeUrl;
		NSString *filename = [storeUrl lastPathComponent];
		NSURL *baseURL = [storeUrl URLByDeletingLastPathComponent];
		NSError *error = nil;
		NSPersistentStore *store = [self.coordinator persistentStoreForURL:storeUrl];
		BOOL removed = [self.coordinator removePersistentStore:store error:&error];
		if (!removed || error) {
			DDLogError(@"could not remove persistent store '%@': %@", store, error);
		}
		NSArray *urlContents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:baseURL includingPropertiesForKeys:nil options:0 error:&error];
		for (NSURL *url in urlContents) {
			NSString *name = [url lastPathComponent];
			if ([name hasPrefix:filename]) {
				BOOL removed = [[NSFileManager defaultManager] removeItemAtURL:url error:&error];
				if (!removed || error) {
					DDLogError(@"could not remove item %@: %@", url, error);
				}
				else {
					DDLogInfo(@"removed CoreData item '%@'", url);
				}
			}
		}
		[NSFetchedResultsController deleteCacheWithName:nil];
		self.backgroundContext = nil;
		self.mainContext = nil;
		self.masterContext = nil;
		[NSManagedObject clearCache];
		[self addPeristentStore];
		[self insertDefaultData:YES];
	});
}

@end
