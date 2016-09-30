//
//  NSManagedObject+GRExtension.h
//
//  Created by Grant Robinson on 12/8/12.
//  Copyright (c) 2012 Grant Robinson. All rights reserved.
//

#import <CoreData/CoreData.h>

@interface NSManagedObject (GRExtension)

+ (dispatch_queue_t) dispatchQueue;
+ (void) clearCache;

+ (id)insertInManagedObjectContext:(NSManagedObjectContext*)moc_;
+ (NSString*)entityName;
+ (NSEntityDescription*)entityInManagedObjectContext:(NSManagedObjectContext*)moc_;
+ (id<NSCopying>) cacheKeyFromValues:(NSDictionary *)values inContext:(NSManagedObjectContext *)context;
+ (id<NSCopying>) cacheKeyFromId:(id)uniqueId;
+ (id) objectByUniqueId:(NSDictionary *)values inContext:(NSManagedObjectContext *)context;
+ (id) objectWithUniqueId:(id)uniqueId inContext:(NSManagedObjectContext *)context;
+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context;
+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context saveWhenDone:(BOOL)saveWhenDone;
+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context afterEach:(void (^)(NSManagedObjectContext *context, id lastObject))afterEach;
+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context afterEach:(void (^)(NSManagedObjectContext *context, id lastObject))afterEach saveWhenDone:(BOOL)saveWhenDone;
+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context afterEach:(void (^)(NSManagedObjectContext *context, id lastObject))afterEach saveWhenDone:(BOOL)saveWhenDone objectsById:(NSDictionary *)objectsById;

+ (id) fetchObject:(NSFetchRequest *)request inContext:(NSManagedObjectContext *)context;
+ (NSArray *) fetchObjects:(NSFetchRequest *)request inContext:(NSManagedObjectContext *)context;

+ (NSString *) uniqueIdKey;
+ (id) uniqueIdValue:(NSDictionary *)dict forKey:(id<NSCopying>)key;
+ (void) setCachedObject:(id)value forKey:(id<NSCopying>)key;

- (void) assignValues:(NSDictionary *)values;
- (void)assignRelationships:(NSDictionary *)relationships andPromises:(NSMutableArray *)promises;

- (NSMutableDictionary *)toJSONDict;
- (id)JSONValueForRelationship:(NSRelationshipDescription *)relationship;

@end
