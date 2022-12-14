//
//  McLocalManager.m
//  McSoftware
//
//  Created by developer on 10/17/12.
//  Copyright (c) 2012 Magican Software Ltd. All rights reserved.
//

#import "McLocalSoftManager.h"
#import "McApplicationScanner.h"
#import "McPluginScanner.h"
#import "McInputMethodScanner.h"
#import "QMSafeMutableArray.h"
#import "NSTimer+Extension.h"

@interface McLocalSoftManager ()
{
    NSInteger scannerType;
    NSArray *typeArray;
    NSDictionary *scannerInfo;
    NSDictionary *resultsInfo;
    NSDictionary *lockInfo;
    
    QMSafeMutableArray *monitorIDs;
    NSTimer *monitorTimer;
}
@end

@implementation McLocalSoftManager

NSString*  McLocalSoftManagerChangedNotification = @"McLocalSoftManagerChangedNotification";
NSString*  McLocalSoftManagerListKey = @"McLocalSoftManagerListKey";
NSString*  McLocalSoftManagerUpdateListKey = @"McLocalSoftManagerUpdateListKey";
NSString*  McLocalSoftManagerFlagKey = @"McLocalSoftManagerFlagKey";
NSString*  McLocalSoftManagerFinishKey = @"McLocalSoftManagerFinishKey";

+ (id)sharedManager
{
    static id instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (id)init
{
    self = [super init];
    if (self)
    {
        typeArray = @[@(kMcLocalFlagApplication),
                      @(kMcLocalFlagInternet),
                      @(kMcLocalFlagWidget),
                      @(kMcLocalFlagScreenSaver),
                      @(kMcLocalFlagPreferencePane),
                      @(kMcLocalFlagInputMethod),
                      @(kMcLocalFlagSpotlight),
                      @(kMcLocalFlagQuickLook),
                      @(kMcLocalFlagDictionary)];
        
        scannerInfo = @{@(kMcLocalFlagApplication):[McApplicationScanner scanner],
                        @(kMcLocalFlagInternet):[McInternetScanner scanner],
                        @(kMcLocalFlagWidget):[McWidgetScanner scanner],
                        @(kMcLocalFlagScreenSaver):[McScreensaverScanner scanner],
                        @(kMcLocalFlagPreferencePane):[McPreferencePaneScanner scanner],
                        @(kMcLocalFlagInputMethod):[McInputMethodScanner scanner],
                        @(kMcLocalFlagSpotlight):[McSpotlightScanner scanner],
                        @(kMcLocalFlagQuickLook):[McQuickLookScanner scanner],
                        @(kMcLocalFlagDictionary):[McDictionaryScanner scanner]};
        
        resultsInfo = [[NSMutableDictionary alloc] initWithCapacity:typeArray.count];
        lockInfo = [[NSMutableDictionary alloc] initWithCapacity:typeArray.count];
        for (id type in typeArray)
        {
            [(NSMutableDictionary*)resultsInfo setObject:[NSMutableArray array] forKey:type];
            [(NSMutableDictionary*)lockInfo setObject:[[NSLock alloc] init] forKey:type];
        }
        
        [self refreshWithFlag:kMcLocalFlagAll];
    }
    return self;
}

//??????bundleID????????????
- (McLocalSoft *)softWithBundleID:(NSString *)bundleID
{
    if (bundleID.length == 0)
        return nil;
    
    McLocalSoft *software = nil;
    for (id typeObj in typeArray)
    {
        NSLock *lock = [lockInfo objectForKey:typeObj];
        NSMutableArray *resultArray = [resultsInfo objectForKey:typeObj];
        [lock lock];
        for (McLocalSoft *one in resultArray)
        {
            if ([one.bundleID isEqualToString:bundleID])
            {
                //???????????????????????????
                if (!software)
                {
                    software = one;
                }
                else if ([software.version compare:one.version options:NSNumericSearch] == NSOrderedAscending)
                {
                    software = one;
                }
            }
        }
        [lock unlock];
    }
    
    return software;
}

//?????????bunldeID?????????
- (void)monitorBundleID:(NSString *)bundleID
{
    if (bundleID.length == 0)
        return;
    
    if (!monitorIDs)
    {
        monitorIDs = [[QMSafeMutableArray alloc] initWithObjects:bundleID, nil];
    }
    else
    {
        if (![monitorIDs containsObject:bundleID])
            [monitorIDs addObject:bundleID];
        else
            return;
    }
    
    if (!monitorTimer)
    {
        monitorTimer = [NSTimer timerWithTimeInterval:5.0 repeats:YES handler:^{
            
            if (monitorIDs.count == 0)
            {
                [monitorTimer invalidate];
                monitorTimer = nil;
            }
            
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                
                [monitorIDs lock];
                for (int idx=(int)monitorIDs.count - 1; idx>=0; idx--)
                {
                    NSString *monitorBundleID = [monitorIDs objectAtIndex:idx];
                    NSString *appFilePath = [[NSWorkspace sharedWorkspace] absolutePathForAppBundleWithIdentifier:monitorBundleID];
                    if (!appFilePath)
                        continue;
                    
                    NSArray *matchSofts = [self submitSoftWithBundlePaths:@[appFilePath]];
                    if (matchSofts.count > 0)
                    {
                        [monitorIDs removeObjectAtIndex:idx];
                    }
                }
                [monitorIDs unlock];
            });
        }];
        [[NSRunLoop currentRunLoop] addTimer:monitorTimer forMode:NSRunLoopCommonModes];
    }
}

//?????????bundleID???????????????
- (void)removeSoftWithBundleID:(NSString *)bundleID
{
    if (bundleID.length == 0)
        return;
    
    //?????????BundleID?????????
    [monitorIDs removeObject:bundleID];
    
    for (id typeObj in typeArray)
    {
        BOOL listChanged = NO;
        NSLock *lock = [lockInfo objectForKey:typeObj];
        NSMutableArray *resultArray = [resultsInfo objectForKey:typeObj];
        [lock lock];
        for (NSInteger idx=[resultArray count]-1; idx>=0; idx--)
        {
            McLocalSoft *one = [resultArray objectAtIndex:idx];
            if ([one.bundleID isEqualToString:bundleID])
            {
                [resultArray removeObjectAtIndex:idx];
                listChanged = YES;
            }
        }
        [lock unlock];
        
        //???????????????????????????
        if (listChanged)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self postChangedNotification:[typeObj integerValue] updates:nil];
            });
        }
    }
}

- (NSArray *)submitSoftWithBundlePaths:(NSArray *)pathArray
{
    NSMutableArray *resultSofts = [[NSMutableArray alloc] init];
    for (NSString *bundlePath in pathArray)
    {
        if (![[NSFileManager defaultManager] fileExistsAtPath:bundlePath])
            continue;
        
        //???????????????????????????????????????????????????????????????
        id targetType = nil;
        if ([bundlePath hasPrefix:@"/Applications"])
        {
            targetType = @(kMcLocalFlagApplication);
        }else
        {
            for (id typeObj in typeArray)
            {
                McScanner *scanner = [scannerInfo objectForKey:typeObj];
                if (![scanner fileVaild:bundlePath])
                    continue;
                
                NSArray *scanPaths = [scanner scanPaths];
                for (NSString *filePath in scanPaths)
                {
                    if ([bundlePath hasPrefix:filePath])
                    {
                        targetType = typeObj;
                        break;
                    }
                }
                if (targetType)
                    break;
            }
            
            //????????????????????????,?????????
            if (!targetType)
                continue;
        }
        
        //???????????????
        McLocalSoft *localSoft = [McLocalSoft softWithPath:bundlePath];
        localSoft.type = [targetType integerValue];
        if (!localSoft)
            continue;
        
        NSLock *lock = [lockInfo objectForKey:targetType];
        NSMutableArray *resultArray = [resultsInfo objectForKey:targetType];
        
        [lock lock];
        //??????????????????????????????(????????????)
        McLocalSoft *currentSoft = nil;
        for (McLocalSoft *oneSoft in resultArray)
        {
            if ([oneSoft.bundleID isEqualToString:localSoft.bundleID])
            {
                if (!currentSoft || [currentSoft compareVersion:oneSoft] == NSOrderedAscending)
                {
                    currentSoft = oneSoft;
                }
            }
        }
        
        //?????????????????????????????????
        if (!currentSoft)
        {
            [resultArray addObject:localSoft];
        }
        else if ([currentSoft compareVersion:localSoft] == NSOrderedAscending)
        {
            NSUInteger idx = [resultArray indexOfObject:currentSoft];
            [resultArray replaceObjectAtIndex:idx withObject:localSoft];
        }
        else
        {
            [lock unlock];
            continue;
        }
        [lock unlock];
        
        //???????????????????????????
        dispatch_async(dispatch_get_main_queue(), ^{
            [self postChangedNotification:[targetType intValue] updates:@[localSoft]];
        });
        
        //????????????
        [resultSofts addObject:localSoft];
    }
    
    //?????????????????????????????????
    if ([resultSofts count] > 0)
    {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self postChangedNotification:kMcLocalFlagAll updates:nil];
        });
    }
    
    return resultSofts;
}

//???????????????????????????????????????
- (NSArray *)softsWithFlag:(McLocalType)flag
{
    //??????????????????????????????
    if (flag == kMcLocalFlagAll)
    {
        NSMutableArray *totalArray = [[NSMutableArray alloc] init];
        for (id typeObj in typeArray)
        {
            NSLock *lock = [lockInfo objectForKey:typeObj];
            NSMutableArray *resultArray = [resultsInfo objectForKey:typeObj];
            [lock lock];
            [totalArray addObjectsFromArray:resultArray];
            [lock unlock];
        }
        return totalArray;
    }
    
    NSLock *lock = [lockInfo objectForKey:@(flag)];
    NSMutableArray *resultArray = [resultsInfo objectForKey:@(flag)];
    if (!resultArray)
        return nil;
    
    [lock lock];
    NSArray *lists = [[NSArray alloc] initWithArray:resultArray];
    [lock unlock];
    return lists;
}

//????????????????????????????????????????????????????????????
- (BOOL)loadingWithFlag:(McLocalType)flag
{
    return scannerType & flag;
}

//???????????????????????????,??????????????????Notification??????
- (void)refreshWithFlag:(McLocalType)flag
{
    if (flag != kMcLocalFlagAll && ![typeArray containsObject:@(flag)])
        return;
    
    //??????????????????
    scannerType |= flag;
    
    //??????????????????????????????
    if (flag == kMcLocalFlagAll)
    {
        //????????????
        [monitorTimer invalidate];
        monitorTimer = nil;
        [monitorIDs removeAllObjects];
        
        //????????????????????????
        for (id typeObj in typeArray)
            [self refreshWithFlag:[typeObj integerValue]];
        return;
    }
    
    //??????????????????????????????
    McScanner *scanner = [scannerInfo objectForKey:@(flag)];
    if (!scanner || [scanner scanning])
        return;
    
    //??????????????????
    NSLock *lock = [lockInfo objectForKey:@(flag)];
    NSMutableArray *resultArray = [resultsInfo objectForKey:@(flag)];
    [lock lock];
    [resultArray removeAllObjects];
    [lock unlock];
    
    //?????????????????????
    [scanner scanWithHandler:^(NSArray *updates, BOOL finished) {
        if (updates)
        {            
            [lock lock];
            [resultArray addObjectsFromArray:updates];
            [lock unlock];
        }
        
        if (finished)
            scannerType &= ~flag;
        
        [self postChangedNotification:flag updates:updates];
    }];
}

//????????????
- (void)postChangedNotification:(McLocalType)flag updates:(NSArray *)updates
{
    BOOL finish = ![self loadingWithFlag:flag];
    NSArray *lists = [self softsWithFlag:flag];
    
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    [info setObject:@(flag) forKey:McLocalSoftManagerFlagKey];
    [info setObject:@(finish) forKey:McLocalSoftManagerFinishKey];
    if (lists)
        [info setObject:lists forKey:McLocalSoftManagerListKey];
    if (updates)
        [info setObject:updates forKey:McLocalSoftManagerUpdateListKey];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:McLocalSoftManagerChangedNotification
                                                        object:self
                                                      userInfo:info];
    
    //????????????????????????????????????????????????????????????????????????????????????????????????
    if (scannerType == kMcLocalFlagAll)
    {
        scannerType = 0;
        [self postChangedNotification:kMcLocalFlagAll updates:nil];
    }
}

@end
