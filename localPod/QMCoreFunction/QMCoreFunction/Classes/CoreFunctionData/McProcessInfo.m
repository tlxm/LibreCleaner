//
//  McProcessInfo.m
//  ProcessInfo
//
//  Created by developer on 11-3-23.
//  Copyright 2011 Magican Software Ltd. All rights reserved.
//

#import "McProcessInfo.h"

@implementation McProcessInfo

//int acquireTaskportRight() 
//{
//    OSStatus stat;
//    AuthorizationItem taskport_item[] = {{"system.privilege.taskport"}};
//    AuthorizationRights rights = {1, taskport_item}, *out_rights = NULL;
//    AuthorizationRef author;
//    
//    AuthorizationFlags auth_flags =  kAuthorizationFlagExtendRights |  kAuthorizationFlagPreAuthorize | kAuthorizationFlagInteractionAllowed | ( 1 << 5); 
//    
//    stat = AuthorizationCreate (NULL, kAuthorizationEmptyEnvironment,auth_flags,&author);
//    
//    if (stat != errAuthorizationSuccess) {
//        return 0;
//    }
//    
//    stat = AuthorizationCopyRights ( author,  &rights,  kAuthorizationEmptyEnvironment, auth_flags,&out_rights);
//    
//    if (stat != errAuthorizationSuccess) {
//        NSLog(@"AuthorizationCopyRights fail: %x", stat);
//        return 1;
//    }
//    return 0;
//}

- (id)init
{
    if(self = [super init])
    {
        //acquireTaskportRight();
        previousProcArray = nil;
    }
    return self;
}

- (void)sortProcess:(NSMutableArray *) array 
          orderEnum:(ProcessOrderEnum) orderEnum 
              isAsc:(BOOL) isAsc
{
    [array sortUsingComparator:^(id obj1, id obj2)
     {
         McProcessInfoData * processData1 = (McProcessInfoData *)obj1;
         McProcessInfoData * processData2 = (McProcessInfoData *)obj2;
         
         NSComparisonResult comparisonResult = 0;
         
         switch (orderEnum)
         {
             case Pid:
                 if (processData1.pid < processData2.pid)
                     comparisonResult = NSOrderedAscending;
                 else if (processData1.pid > processData2.pid)
                     comparisonResult = NSOrderedDescending;
                 else
                     comparisonResult = NSOrderedSame;                                          
                 break;
             case ProcessName:
                 comparisonResult = [processData1.pName localizedStandardCompare:processData2.pName];
                 break;
             case Cpu:
                 if (processData1.cpuUsage < processData2.cpuUsage)
                     comparisonResult = NSOrderedAscending;
                 else if (processData1.cpuUsage > processData2.cpuUsage)
                     comparisonResult = NSOrderedDescending;
                 else
                     comparisonResult = NSOrderedSame;  
                 break;
             case Thread:
                 if (processData1.threadCount < processData2.threadCount)
                     comparisonResult = NSOrderedAscending;
                 else if (processData1.threadCount > processData2.threadCount)
                     comparisonResult = NSOrderedDescending;
                 else
                     comparisonResult = NSOrderedSame;  
                 break;
             case Memory:
                 if (processData1.resident_size < processData2.resident_size)
                     comparisonResult = NSOrderedAscending;
                 else if (processData1.resident_size > processData2.resident_size)
                     comparisonResult = NSOrderedDescending;
                 else
                     comparisonResult = NSOrderedSame;  
                 break;
             case User:
                 comparisonResult = [processData1.pUserName localizedStandardCompare:processData2.pUserName];
                 break;
             case Kind:
             {
                 int pflag1 = 0;
                 int pflag2 = 0;
                 if (processData1.pflag & MCPROC_LP64)
                     pflag1 = 1;
                 if (processData2.pflag & MCPROC_LP64)
                     pflag2 = 1;
                 
                 if (pflag1 < pflag2)
                     comparisonResult = NSOrderedAscending;
                 else if (pflag1 > pflag2)
                     comparisonResult = NSOrderedDescending;
                 else
                     comparisonResult = NSOrderedSame;
                 break;
             }
             case CpuTime:
             {
                 uint64_t cpuTime1 = processData1.cpuTime;
                 uint64_t cpuTime2 = processData2.cpuTime;
                 if (cpuTime1 < cpuTime2)
                     comparisonResult = NSOrderedAscending;
                 else if (cpuTime1 > cpuTime2)
                     comparisonResult = NSOrderedDescending;
                 else
                     comparisonResult = NSOrderedSame;   
                 break;
             }
         }
         if (!isAsc)
         {
             if (comparisonResult == NSOrderedAscending)
                 comparisonResult = NSOrderedDescending;
             else if (comparisonResult == NSOrderedDescending)
                 comparisonResult = NSOrderedAscending;
         }
         
         return (NSComparisonResult)comparisonResult;
     }];
}

static NSMutableArray *pack_process_info(McProcessInfo *object, ProcessInfo_t *proc, int real_count) {
    NSMutableArray *processInfoArray = [[NSMutableArray alloc] init];
    for(int i = 0; i < real_count; i++)
    {
        McProcessInfoData * processData = [[McProcessInfoData alloc] init];
        // get data from ProcessInfo_t
        processData.pid = proc[i].pid;
        processData.ppid = proc[i].ppid;
        processData.uid = proc[i].uid;
        processData.pflag = proc[i].p_flag;
        
        processData.resident_size = proc[i].resident_size;
        processData.virtual_size = proc[i].virtual_size;
        processData.threadCount = proc[i].threadCount;
        
        processData.cpuTime = proc[i].cpu_time;
        processData.currentTime = proc[i].current_time;
        
        processData.pUserName = [NSString stringWithCString:proc[i].pUserName
                                                   encoding:NSUTF8StringEncoding];
        processData.pExecutePath = [NSString stringWithCString:proc[i].pExecutePath
                                                      encoding:NSUTF8StringEncoding];
        // get executable file name
        processData.pName = [processData.pExecutePath lastPathComponent];
        
        if ([processData.pName length] != 0)
        {
            /*
             BOOL loadImage = NO;
             for (McProcessInfoData * _processData in previousProcArray)
             {
             if (_processData.pid == processData.pid && _processData.iconImage)
             {
             processData.iconImage = _processData.iconImage;
             loadImage = YES;
             break;
             }
             }
             if (!loadImage)
             [self performSelectorOnMainThread:@selector(getProcessIcon:) withObject:processData waitUntilDone:NO];
             */
            // calculate cpu usage
            [object calcCpuUsage:processData];
            
            object->cpuTotal += [processData cpuUsage];
            object->memoryTotal += [processData resident_size];
            
            [processInfoArray addObject:processData];
        }
    }
    
    // remember last process array for calc cpu usage
    object->previousProcArray = processInfoArray;
    
    return processInfoArray;
}

-(NSMutableArray *)GetProcessInfo:(ORDER_TYPE) orderType
                            count:(int)count
                        isReverse:(Boolean)isReverse
                            block:(block_v_a)block_a
{
    cpuTotal = 0;
    memoryTotal = 0;
    
    if(block_a)
    {
        // ?????? 1: ProcessInfo_t *proc ?????????????????????, ???????????????.
        block_v_i_proc copyBlock = ^(int return_code, ProcessInfo_t *proc) {
            if (return_code <= 0 || proc == NULL)
            {
                block_a(nil);
            }
            NSMutableArray * processInfoArray = pack_process_info(self, proc, return_code);
            free(proc);
            block_a(processInfoArray);
            
        };
        _dm_get_process_info_aysnc(orderType, count, isReverse, copyBlock);
        
        // ??????2: ????????????, ??????????????????.?????????
//         __block ProcessInfo_t *proc = NULL;    //__block ??????, ??????__block ??????, ??????????????? oc ??????,?????? ???????????????.
//        block_v_i copyBlock = ^(int return_code) {
//            if (return_code <= 0 || proc == NULL)
//            {
//                block_a(nil);
//            }
//            NSMutableArray * processInfoArray = pack_process_info(self, proc, return_code);
//            free(proc);
//            block_a(processInfoArray);
//
//        };
//        _dm_get_process_info_aysnc(orderType, count, &proc, isReverse, copyBlock);

        // Block ??????, ??? Arc ???, block ???=????????????????????? copy ??????.
        // ????????? Block ??? StackBlock??????,????????????, copy ???????????????????????????. ?????????????????????(MallocBlock??????), ?????????????????????????????????__block????????????????????????????????????, ???__block ?????????????????????????????????,?????????????????????.
        
        // ????????????, _dm_get_process_info_aysnc?????????????????????????????????&proc, ??????__block ???????????????????????????, ?????? &proc?????????????????????. ???????????????????????????????????????. ???????????????*proc????????????, ?????????????????????proc????????????.
        
        
        //??????3:????????????, ?????????
//         __block ProcessInfo_t *proc = NULL;
//        _dm_get_process_info_aysnc(orderType, count, &proc, isReverse, (int return_code) {
//            if (return_code <= 0 || proc == NULL)
//            {
//                block_a(nil);
//            }
//            NSMutableArray * processInfoArray = pack_process_info(self, proc, return_code);
//            free(proc);
//            block_a(processInfoArray);
//
//        });
        // ???????????????,??????????????????. ??????&proc, ????????? __block proc ????????????,??????????????????.(???proc1)
        // ????????? block ????????????. Block?????? copy ??????. ????????? Block?????????__block proc ????????????????????????. Block??????proc ??????????????????.(?????? proc2)
        // ???proc ???????????????, ???????????? proc1?????????????????????. ???proc2?????????????????? Null. ?????? block ?????????????????????, proc2?????? Null.
        
        
        return nil;
    }else{
        
        __block ProcessInfo_t *proc = NULL;
        int real_count = _dm_get_process_info(orderType, count, isReverse, &proc);
        if (real_count <= 0 || proc == NULL)
        {
            return nil;
        }
        
        // fill info to array
        NSMutableArray * processInfoArray = pack_process_info(self, proc, real_count);
        free(proc);
        
        return processInfoArray;
        
    }
}

- (void)calcCpuUsage:(McProcessInfoData *)processData
{
    processData.cpuUsage = 0.0;
    if (previousProcArray == nil)
        return;
    
    for (McProcessInfoData *prevData in previousProcArray)
    {
        if (prevData.pid == processData.pid)
        {
            if (prevData.cpuTime < processData.cpuTime)
            {
                processData.cpuUsage = (float)(processData.cpuTime - prevData.cpuTime) / (float)(processData.currentTime - prevData.currentTime);
            }
            
            break;
        }
    }
}

/*
- (void)getProcessIcon:(McProcessInfoData *)processData
{   
    NSRange range = [processData.pExecutePath rangeOfString:@".app/"
                                                    options:NSBackwardsSearch];
    if (range.length == 0)
        return;
    
    NSString *appPath = [processData.pExecutePath substringToIndex:(range.location + range.length - 1)];
    NSBundle *bundle = [NSBundle bundleWithPath:appPath];
    if (bundle == nil)
        return;
    
    // make sure the executable file is the same
    //NSLog(@"%@", [bundle executablePath]);
    if (![[[bundle executablePath] lastPathComponent] isEqualToString:processData.pName])
        return;
    
    // icon
    //if ([bundle objectForInfoDictionaryKey:@"CFBundleIconFile"] != nil)

    processData.pExecutePath = appPath;
    NSImage *image = [[NSWorkspace sharedWorkspace] iconForFile:appPath];
    [image setSize:NSMakeSize(16, 16)];
    processData.iconImage = image;
    image = nil;
    
    // maybe we should change name to "Bundle name"
    NSString *bundleName = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    //NSLog(@"Bundle Name: %@", bundleName);
    if (bundleName != nil)
    {
        processData.pName = bundleName;
    }
}
 */

- (void)getTotalCPU:(float *)totalCPU totalMemory:(uint64 *)memory
{
    if (totalCPU) *totalCPU = cpuTotal;
    if (memory) *memory = memoryTotal;
}

@end
