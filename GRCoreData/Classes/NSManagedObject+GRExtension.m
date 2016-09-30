//
//  NSManagedObject+GRExtension.m
//
//  Created by Grant Robinson on 12/8/12.
//  Copyright (c) 2012 Grant Robinson. All rights reserved.
//

#import "NSManagedObject+GRExtension.h"
#import "GRCoreDataStack.h"
#import "LoadableCategory.h"

#import "GRToolkitLogging.h"

@interface NSDictionary (GRCJson)

- (id) grc_objectForKeyOrNil:(id)key;

@end

@implementation NSDictionary (GRCJson)

- (id) grc_objectForKeyOrNil:(id)key {
	id object = [self objectForKey:key];
	if (object == [NSNull null]) {
		return nil;
	}
	return object;
}

@end


MAKE_CATEGORIES_LOADABLE(NSManageObject_GRExtension);

@interface NSAttributeDescription (GRExtension)

- (BOOL) includeInJSON;
- (BOOL) ignoreIfMissing;

@end

@implementation NSAttributeDescription (GRExtension)

- (BOOL) includeInJSON {
	NSString *include = [self.userInfo objectForKey:@"includeInJson"];
	if (include) {
		return include.boolValue;
	}
	return YES;
}

- (BOOL) ignoreIfMissing {
	NSString *ignore = [self.userInfo objectForKey:@"ignoreIfMissing"];
	if (ignore) {
		return ignore.boolValue;
	}
	return NO;
}

@end

static NSMutableDictionary *objectCache = nil;
dispatch_queue_t _cacheQueue;
static NSRegularExpression *regex = nil;
static NSDateFormatter *fromFormatShort;
static NSDateFormatter *fromFormatLong;


typedef void (^Promise)(void);

id getCachedObject(id<NSCopying>key) {
	__block id result = nil;
	dispatch_sync(_cacheQueue, ^{
		result = [objectCache objectForKey:key];
	});
	return result;
}

void setCachedObject(id<NSCopying>key, id value) {
	dispatch_sync(_cacheQueue, ^{
		if (value) {
			[objectCache setObject:value forKey:key];
		}
		else {
			[objectCache removeObjectForKey:key];
		}
	});
}

@implementation NSManagedObject (GRExtension)

+ (NSDate *) grc_dateFromISO8601String:(NSString *)dateStr error:(NSError *__autoreleasing *)_error {
	if (dateStr == nil) {
		return nil;
	}
	__block NSDate *date = nil;
	dispatch_sync(_cacheQueue, ^{
		NSString *str = [regex stringByReplacingMatchesInString:dateStr options:0 range:NSMakeRange(0, dateStr.length) withTemplate:@"$1$2"];
		NSDateFormatter *formatter = fromFormatShort;
		NSError *error = nil;
		if ([formatter getObjectValue:&date forString:str range:nil error:&error]) {
			return;
		}
		else {
			// fix-up the date
			formatter = fromFormatLong;
			if ([formatter getObjectValue:&date forString:str range:nil error:&error]) {
				return;
			}
			else {
				if (_error) {
					*_error = error;
				}
			}
		}
	});
	return date;

}

+ (void) load {
	_cacheQueue = dispatch_queue_create("com.meinc.NSManagedObjectCache", NULL);
	objectCache = [[NSMutableDictionary alloc] initWithCapacity:100];
}

+ (dispatch_queue_t) dispatchQueue {
	return _cacheQueue;
}

+ (void) clearCache {
	dispatch_sync(_cacheQueue, ^{
		objectCache = nil;
		objectCache = [NSMutableDictionary dictionaryWithCapacity:100];
	});
}

+ (id) insertInManagedObjectContext:(NSManagedObjectContext *)moc_ {
	NSManagedObject *obj = [NSEntityDescription insertNewObjectForEntityForName:[self entityName] inManagedObjectContext:moc_];
//	NSError *error = nil;
//	BOOL success = [moc_ obtainPermanentIDsForObjects:[NSArray arrayWithObject:obj] error:&error];
//	if (!success || error) {
//		NSLog(@"unable to obtain permanent ID for object %@: %@", obj, error);
//	}
	return obj;
}

+ (NSString *) entityName {
	return NSStringFromClass(self);
}

+ (NSEntityDescription *) entityInManagedObjectContext:(NSManagedObjectContext *)moc_ {
	return [NSEntityDescription entityForName:[self entityName] inManagedObjectContext:moc_];
}


+ (id<NSCopying>) cacheKeyFromValues:(NSDictionary *)values inContext:(NSManagedObjectContext *)context {
	NSEntityDescription *entity = [self entityInManagedObjectContext:context];
	NSString *key = [entity.userInfo objectForKey:@"jsonUniqueKey"];
	id uniqueId = [values grc_objectForKeyOrNil:key];
	if (uniqueId) {
		return [self cacheKeyFromId:uniqueId];
	}
	return nil;
}

+ (id<NSCopying>) cacheKeyFromId:(id)uniqueId {
	return [NSString stringWithFormat:@"%@_%@", [self entityName], [uniqueId description]];
}

+ (id) objectByUniqueId:(NSDictionary *)values inContext:(NSManagedObjectContext *)context {
	NSEntityDescription *entity = [self entityInManagedObjectContext:context];
	NSString *key = [entity.userInfo objectForKey:@"jsonUniqueKey"];
	id uniqueId = [self uniqueIdValue:values forKey:key];
	if (uniqueId) {
		return [self objectWithUniqueId:uniqueId inContext:context];
	}
	else {
		DDLogInfo(@"no value found for key '%@' in dictionary %@", key, values);
	}
	return nil;
}

+ (id) objectWithUniqueId:(id)uniqueId inContext:(NSManagedObjectContext *)context {
	if (uniqueId == nil) {
		DDLogError(@"cannot retrieve object for entity %@: uniqueId is nil", [self entityName]);
		//		NSAssert(uniqueId != nil, @"attempting to retrieve a %@ with a nil uniqueId", [self entityName]);
		return nil;
	}
	id<NSCopying> key = [self cacheKeyFromId:uniqueId];
	id (^fetchObject)() = ^id {
		NSEntityDescription *entity = [self entityInManagedObjectContext:context];
		NSString *jsonKey = [entity.userInfo objectForKey:@"jsonUniqueKey"];
		//		NSLog(@"uniqueId %@ for key %@", uniqueId, jsonKey);
		NSFetchRequest *request = [entity.managedObjectModel fetchRequestFromTemplateWithName:[NSString stringWithFormat:@"%@ById", [self entityName]] substitutionVariables:@{jsonKey: uniqueId}];
		request.shouldRefreshRefetchedObjects = YES;
		request.includesPendingChanges = YES;
		NSError *error = nil;
		NSArray *results = [context executeFetchRequest:request error:&error];
		if (results.count > 0) {
			NSManagedObject *obj = [results objectAtIndex:0];
			setCachedObject(key, obj.objectID);
			return obj;
		}
		return nil;
	};
	NSManagedObjectID *objectId = getCachedObject(key);
	if (objectId) {
		NSManagedObject *obj = [context existingObjectWithID:objectId error:nil];
		if (obj) {
			return obj;
		}
		else {
			DDLogError(@"we are hosed, we have an objectID (%@) cached for key %@, but no object", objectId, key);
			setCachedObject(key, nil);
			return fetchObject();
		}
	}
	else {
		return fetchObject();
	}
	return nil;
	
}

+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context saveWhenDone:(BOOL)saveWhenDone {
	return [self loadObjectsFromArray:objects intoContext:context afterEach:nil saveWhenDone:saveWhenDone];
}

+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context afterEach:(void (^)(NSManagedObjectContext *, id))afterEach {
	return [self loadObjectsFromArray:objects intoContext:context afterEach:afterEach saveWhenDone:YES];
}

+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context afterEach:(void (^)(NSManagedObjectContext *, id))afterEach saveWhenDone:(BOOL)saveWhenDone
{
	return [self loadObjectsFromArray:objects intoContext:context afterEach:afterEach saveWhenDone:saveWhenDone objectsById:nil];
}

+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context afterEach:(void (^)(NSManagedObjectContext *, id))afterEach saveWhenDone:(BOOL)saveWhenDone objectsById:(NSDictionary *)_objectsById
{
	NSMutableArray *promises = [[NSMutableArray alloc] initWithCapacity:objects.count];
	NSMutableSet *updatedObjects = [NSMutableSet setWithCapacity:objects.count];
	NSEntityDescription *entity = [self entityInManagedObjectContext:context];
	NSString *jsonKey = [entity.userInfo objectForKey:@"jsonUniqueKey"];
	NSMutableDictionary *objectsById = [_objectsById mutableCopy];
	for (NSDictionary *objectDict in objects) {
		NSManagedObject *managedObject = nil;
		id uniqueId = [self uniqueIdValue:objectDict forKey:jsonKey];
		if (uniqueId) {
			if (objectsById) {
				managedObject = objectsById[uniqueId];
			}
			else {
				managedObject = [self objectWithUniqueId:uniqueId inContext:context];
			}
		}
		else {
			DDLogInfo(@"no value found for key '%@' in dictionary %@", jsonKey, objectDict);
		}
		if (!managedObject) {
			// Create one.
			managedObject = [self insertInManagedObjectContext:context];
			NSError *error = nil;
			BOOL success = [context obtainPermanentIDsForObjects:[NSArray arrayWithObject:managedObject] error:&error];
			if (!success || error) {
				DDLogError(@"unable to obtain permanent ID for object %@: %@", managedObject, error);
			}
			objectsById[uniqueId] = managedObject;
		}
		// Sync the remote values with the managed object.
		[managedObject assignValues:objectDict];
		[managedObject assignRelationships:objectDict andPromises:promises];
		[updatedObjects addObject:managedObject.objectID];
		if (afterEach) {
			afterEach(context, managedObject);
		}
	}
	// Fulfill promises to connect delayed relationships.
	if ([promises count] > 0) {
		for (Promise promise in promises) {
			promise();
		}
	}
	if (saveWhenDone) {
		if (updatedObjects.count > 0) {
			NSError *error = [context saveWithCompletionHandler:nil];
			if (error) {
				DDLogError(@"error saving nested contexts: %@", error);
				[context rollback];
			}
		}
	}
	
	return updatedObjects;
}

+ (NSMutableSet *) loadObjectsFromArray:(NSArray *)objects intoContext:(NSManagedObjectContext *)context {
	return [self loadObjectsFromArray:objects intoContext:context afterEach:nil saveWhenDone:YES];
}

+ (id) fetchObject:(NSFetchRequest *)request inContext:(NSManagedObjectContext *)context {
	NSError *error = nil;
	NSArray *results = [context executeFetchRequest:request error:&error];
	if (error) {
		DDLogError(@"error performing fetch %@: %@", request, error);
	}
	if (results.count > 0) {
		return [results objectAtIndex:0];
	}
	return nil;
}

+ (NSArray *) fetchObjects:(NSFetchRequest *)request inContext:(NSManagedObjectContext *)context {
	NSError *error = nil;
	NSArray *results = [context executeFetchRequest:request error:&error];
	if (error) {
		DDLogError(@"error performing fetch %@: %@", request, error);
	}
	return results;
}

+ (NSString *) uniqueIdKey {
	return nil;
}

+ (id) uniqueIdValue:(NSDictionary *)dict forKey:(id<NSCopying>)key {
	return [dict grc_objectForKeyOrNil:key];
}

+ (void) setCachedObject:(id)value forKey:(id<NSCopying>)key {
	setCachedObject(key, value);
}

- (void) assignValues:(NSDictionary *)values {
	for (NSPropertyDescription *property in self.entity) {
		if ([property isKindOfClass:[NSAttributeDescription class]] && ((NSAttributeDescription *)property).includeInJSON) {
			NSString *attribute = property.name;
			id key = [property.userInfo objectForKey:@"jsonKey"];
			id alternateKey = [property.userInfo objectForKey:@"alternateKey"];
			if (key == nil) {
				key = attribute;
			}
			id value = values[key];
			if (value == nil && alternateKey != nil) {
				value = values[alternateKey];
			}
			if (value) {
				NSAttributeType attributeType = [(NSAttributeDescription *)property attributeType];
				if ((attributeType == NSStringAttributeType) && ([value isKindOfClass:[NSNumber class]])) {
					value = [value stringValue];
				}
				else if ((attributeType == NSBooleanAttributeType) && ([value isKindOfClass:[NSString class]])) {
					value = @([value boolValue]);
				}
				else if (((attributeType == NSInteger16AttributeType) || (attributeType == NSInteger32AttributeType) || (attributeType == NSInteger64AttributeType) || (attributeType == NSBooleanAttributeType)) && ([value isKindOfClass:[NSString class]])) {
					value = @([value integerValue]);
				}
				else if ((attributeType == NSFloatAttributeType) && ([value isKindOfClass:[NSString class]])) {
					value = @([value doubleValue]);
				}
				else if (attributeType == NSDateAttributeType) {
					if (([value isKindOfClass:[NSString class]])) {
						NSError *error = nil;
						NSDate *date = [NSManagedObject grc_dateFromISO8601String:value error:&error];
						if (date) {
							value = date;
						}
						else if (error) {
							DDLogError(@"could not parse date for %@: %@", attribute, error);
							value = nil;
						}
						else {
							value = nil;
						}
					}
					else if ([value isKindOfClass:[NSNumber class]]) {
						value = [NSDate dateWithTimeIntervalSince1970:([(NSNumber *)value doubleValue]/1000)];
					}
				}
				if (value == [NSNull null]) {
					if (((NSAttributeDescription *)property).ignoreIfMissing == NO) {
						[self setValue:nil forKey:attribute];
					}
				}
				else {
					[self setValue:value forKey:attribute];
				}
			}
			else {
				//				NSLog(@"Encountered <null> value for key %@ while parsing JSON.", attribute);
			}
		}
	}
}

- (void) assignRelationships:(NSDictionary *)relationships andPromises:(NSMutableArray *)promises {
	// default does nothing
}

- (id) JSONValueForRelationship:(NSRelationshipDescription *)relationship {
    return nil;
}


- (NSMutableDictionary *) toJSONDict {
    NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithCapacity:self.entity.properties.count];
    for (NSPropertyDescription *property in self.entity) {
        NSString *attribute = property.name;
		NSDictionary *info = [property userInfo];
		BOOL includeInJson = YES;
		NSString *str = [info objectForKey:@"includeInJson"];
		if (str) {
			includeInJson = str.boolValue;
		}
        if ([property isKindOfClass:[NSAttributeDescription class]] && includeInJson == YES) {
            id value = [self valueForKey:attribute];
			id key = [property.userInfo objectForKey:@"jsonKey"];
			if (key == nil) {
				key = attribute;
			}
            if (value != nil && [value isKindOfClass:[NSNull class]] == NO) {
                NSAttributeType type = [(NSAttributeDescription *)property attributeType];
                switch (type) {
                    case NSInteger16AttributeType:
                    case NSInteger32AttributeType:
                    case NSInteger64AttributeType:
                    case NSDecimalAttributeType:
                    case NSDoubleAttributeType:
                    case NSFloatAttributeType:
                    case NSStringAttributeType:
                    case NSBooleanAttributeType:
                        [dict setObject:value forKey:key];
                        break;
                    case NSDateAttributeType:
                    {
						dict[key] = @((long long)[(NSDate *)value timeIntervalSince1970] * 1000);
                        break;
                    }
                    default:
                        DDLogInfo(@"ignoring attribute %@ which is of type %lu", attribute, (unsigned long)type);
                        break;
                }
            }
			else {
				[dict setObject:[NSNull null] forKey:key];
			}
        }
        else if ([property isKindOfClass:[NSRelationshipDescription class]]) {
            id value = [self JSONValueForRelationship:(NSRelationshipDescription *)property];
            if (value) {
                id key = [property.userInfo objectForKey:@"jsonKey"];
                if (key == nil) {
                    key = property.name;
                }
                [dict setObject:value forKey:key];
            }
        }
    }
    return dict;
}


@end
