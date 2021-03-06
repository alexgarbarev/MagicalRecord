//
//  NSManagedObjectContext+MagicalSaves.m
//  Magical Record
//
//  Created by Saul Mora on 3/9/12.
//  Copyright (c) 2012 Magical Panda Software LLC. All rights reserved.
//

#import "NSManagedObjectContext+MagicalSaves.h"
#import "MagicalRecord+ErrorHandling.h"
#import "NSManagedObjectContext+MagicalRecord.h"
#import "MagicalRecord.h"

@implementation NSManagedObjectContext (MagicalSaves)

- (void)MR_saveOnlySelfWithCompletion:(MRSaveCompletionHandler)completion;
{
    [self MR_saveWithOptions:0 completion:completion];
}

- (void)MR_saveOnlySelfAndWait;
{
    [self MR_saveWithOptions:MRSaveSynchronously completion:nil];
}

- (void) MR_saveToPersistentStoreWithCompletion:(MRSaveCompletionHandler)completion;
{
    [self MR_saveWithOptions:MRSaveParentContexts completion:completion];
}

- (void) MR_saveToPersistentStoreAndWait;
{
    [self MR_saveWithOptions:MRSaveParentContexts | MRSaveSynchronously completion:nil];
}

- (void)MR_saveOnlySelfOnQueue:(dispatch_queue_t)queue withCompletion:(MRSaveCompletionHandler)completion;
{
    [self MR_saveWithOptions:0 onQueue:queue completion:completion];
}

- (void)MR_saveOnlySelfAndWaitOnQueue:(dispatch_queue_t)queue;
{
    [self MR_saveWithOptions:MRSaveSynchronously onQueue:queue completion:nil];
}

- (void) MR_saveToPersistentStoreOnQueue:(dispatch_queue_t)queue withCompletion:(MRSaveCompletionHandler)completion;
{
    [self MR_saveWithOptions:MRSaveParentContexts onQueue:queue completion:completion];
}

- (void) MR_saveToPersistentStoreAndWaitOnQueue:(dispatch_queue_t)queue;
{
    [self MR_saveWithOptions:MRSaveParentContexts | MRSaveSynchronously onQueue:queue completion:nil];
}

- (void)MR_saveWithOptions:(MRSaveContextOptions)mask onQueue:(dispatch_queue_t) queue completion:(MRSaveCompletionHandler)completion{
    
    
    dispatch_group_t group = dispatch_group_create();
    
    [self MR_saveWithOptions:mask onGroup:group andQueue:queue completion:completion];
    
    /* Freeze caller thread while saving tasks running */
    if ((mask & MRSaveSynchronously) == MRSaveSynchronously){
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
    }
    
}

- (void)MR_saveWithOptions:(MRSaveContextOptions)mask onGroup:(dispatch_group_t) group andQueue:(dispatch_queue_t) queue completion:(MRSaveCompletionHandler)completion
{
    BOOL syncSave             = ((mask & MRSaveSynchronously) == MRSaveSynchronously);
    BOOL saveParentContexts   = ((mask & MRSaveParentContexts) == MRSaveParentContexts);
    BOOL saveOnSpecifiedQueue = queue && group;
    if (![self hasChanges]) {
        MRLog(@"NO CHANGES IN ** %@ ** CONTEXT - NOT SAVING", [self MR_workingName]);
        
        if (completion)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(NO, nil);
            });
        }
        
        return;
    }
    
    MRLog(@"→ Saving %@", [self MR_description]);
    MRLog(@"→ Save Parents? %@", @(saveParentContexts));
    MRLog(@"→ Save on specified queue? %@", @(saveOnSpecifiedQueue));
    MRLog(@"→ Save Synchronously? %@", @(!saveOnSpecifiedQueue & syncSave));
    
    
    id saveBlock = ^{
        NSError *error = nil;
        BOOL     saved = NO;
        
        @try
        {
            saved = [self save:&error];
        }
        @catch(NSException *exception)
        {
            MRLog(@"Unable to perform save: %@", (id)[exception userInfo] ? : (id)[exception reason]);
        }
        
        @finally
        {
            if (!saved) {
                [MagicalRecord handleErrors:error];
                
                if (completion) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        completion(saved, error);
                    });
                }
            } else {
                // If we're the default context, save to disk too (the user expects it to persist)
                if (self == [[self class] MR_defaultContext]) {
                    [[[self class] MR_rootSavingContext] MR_saveWithOptions:MRSaveSynchronously onGroup:group andQueue:queue completion:completion];
                }
                // If we're saving parent contexts, do so
                else if ((YES == saveParentContexts) && [self parentContext]) {
                    [[self parentContext] MR_saveWithOptions:MRSaveSynchronously | MRSaveParentContexts onGroup:group andQueue:queue completion:completion];
                }
                // If we are not the default context (And therefore need to save the root context, do the completion action if one was specified
                else {
                    MRLog(@"→ Finished saving: %@", [self MR_description]);
                    
                    if (completion) {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            completion(saved, error);
                        });
                    }
                }
            }
        }
    };
    
    /* If queue and group specified - use new async logic */
    if (saveOnSpecifiedQueue){
        /* Perform async saving on specified queue and group*/
        dispatch_group_async(group, queue, ^{
            [self performBlockAndWait:saveBlock];
        });
    }else{
        /* Save with old logic, which can block main thread  */
        if (YES == syncSave) {
            [self performBlockAndWait:saveBlock];
        } else {
            [self performBlock:saveBlock];
        }
    }
    
}

- (void)MR_saveWithOptions:(MRSaveContextOptions)mask completion:(MRSaveCompletionHandler)completion;
{
    [self MR_saveWithOptions:mask onGroup:nil andQueue:nil completion:completion];
}

#pragma mark - Deprecated methods
// These methods will be removed in MagicalRecord 3.0

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

- (void)MR_save;
{
    [self MR_saveToPersistentStoreAndWait];
}

- (void)MR_saveWithErrorCallback:(void (^)(NSError *error))errorCallback;
{
    [self MR_saveWithOptions:MRSaveSynchronously|MRSaveParentContexts completion:^(BOOL success, NSError *error) {
        if (!success) {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveInBackgroundCompletion:(void (^)(void))completion;
{
    [self MR_saveOnlySelfWithCompletion:^(BOOL success, NSError *error) {
        if (success) {
            if (completion) {
                completion();
            }
        }
    }];
}

- (void)MR_saveInBackgroundErrorHandler:(void (^)(NSError *error))errorCallback;
{
    [self MR_saveOnlySelfWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveInBackgroundErrorHandler:(void (^)(NSError *error))errorCallback completion:(void (^)(void))completion;
{
    [self MR_saveOnlySelfWithCompletion:^(BOOL success, NSError *error) {
        if (success) {
            if (completion) {
                completion();
            }
        } else {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveNestedContexts;
{
    [self MR_saveToPersistentStoreWithCompletion:nil];
}

- (void)MR_saveNestedContextsErrorHandler:(void (^)(NSError *error))errorCallback;
{
    [self MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        if (!success) {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

- (void)MR_saveNestedContextsErrorHandler:(void (^)(NSError *error))errorCallback completion:(void (^)(void))completion;
{
    [self MR_saveToPersistentStoreWithCompletion:^(BOOL success, NSError *error) {
        if (success) {
            if (completion) {
                completion();
            }
        } else {
            if (errorCallback) {
                errorCallback(error);
            }
        }
    }];
}

#pragma clang diagnostic pop // ignored "-Wdeprecated-implementations"

@end
