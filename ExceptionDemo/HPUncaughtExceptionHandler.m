//
//  HPUncaughtExceptionHandler.m
//  AppTest
//
//  Created by ZP on 2021/7/14.
//

#import "HPUncaughtExceptionHandler.h"
#import <UIKit/UIKit.h>

#include <libkern/OSAtomic.h>
#include <execinfo.h>
#include <stdatomic.h>

//异常名称key
NSString * const HPUncaughtExceptionHandlerSignalExceptionName = @"HPUncaughtExceptionHandlerSignalExceptionName";
//异常原因key
NSString * const HPUncaughtExceptionHandlerSignalExceptionReason = @"HPUncaughtExceptionHandlerSignalExceptionReason";
//bt精简过的
NSString * const HPUncaughtExceptionHandlerAddressesKey = @"HPUncaughtExceptionHandlerAddressesKey";
//异常文件key
NSString * const HPUncaughtExceptionHandlerFileKey = @"HPUncaughtExceptionHandlerFileKey";
//异常符号
NSString * const HPUncaughtExceptionHandlerCallStackSymbolsKey = @"HPUncaughtExceptionHandlerCallStackSymbolsKey";
//signal异常标识
NSString * const HPUncaughtExceptionHandlerSignalKey = @"HPUncaughtExceptionHandlerSignalKey";


atomic_int      HPUncaughtExceptionCount = 0;
const int32_t   HPUncaughtExceptionMaximum = 8;
const NSInteger HPUncaughtExceptionHandlerSkipAddressCount = 4;
const NSInteger HPUncaughtExceptionHandlerReportAddressCount = 5;

NSString *getAppInfo(void);

//保存原先的handler
NSUncaughtExceptionHandler *originalUncaughtExceptionHandler = NULL;
//保存原先abrt的handler
void (*originalAbrtSignalHandler)(int, struct __siginfo *, void *);

@interface HPUncaughtExceptionHandler()

+ (NSArray *)backtrace;

- (void)handleUncaughtSignalException:(NSException *)exception;

@end


// exception 调用时机来自 _objc_terminate
void HPExceptionHandlers(NSException *exception) {
    NSLog(@"%s",__func__);
    
    int32_t exceptionCount = atomic_fetch_add_explicit(&HPUncaughtExceptionCount,1,memory_order_relaxed);
    if (exceptionCount > HPUncaughtExceptionMaximum) {
        return;
    }
    // 获取堆栈信息
    NSArray *callStack = [HPUncaughtExceptionHandler backtrace];
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithDictionary:[exception userInfo]];
    [userInfo setObject:exception.name forKey:HPUncaughtExceptionHandlerSignalExceptionName];
    [userInfo setObject:exception.reason forKey:HPUncaughtExceptionHandlerSignalExceptionReason];
    [userInfo setObject:callStack forKey:HPUncaughtExceptionHandlerAddressesKey];
    [userInfo setObject:exception.callStackSymbols forKey:HPUncaughtExceptionHandlerCallStackSymbolsKey];
    [userInfo setObject:@"HPUncaughtException" forKey:HPUncaughtExceptionHandlerFileKey];
    
    [[[HPUncaughtExceptionHandler alloc] init]
     performSelectorOnMainThread:@selector(handleUncaughtSignalException:)
     withObject:
     [NSException
      exceptionWithName:[exception name]
      reason:[exception reason]
      userInfo:userInfo]
     waitUntilDone:YES];
    //处理完自己的调用之前的。
    if (originalUncaughtExceptionHandler) {
        originalUncaughtExceptionHandler(exception);
    }
}

// signal处理方法
void HPSignalHandler(int signal) {
    int32_t exceptionCount = atomic_fetch_add_explicit(&HPUncaughtExceptionCount,1,memory_order_relaxed);
    if (exceptionCount > HPUncaughtExceptionCount) {
        return;
    }
    
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionaryWithObject:[NSNumber numberWithInt:signal] forKey:HPUncaughtExceptionHandlerSignalKey];
    NSArray *callStack = [HPUncaughtExceptionHandler backtrace];
    [userInfo setObject:callStack forKey:HPUncaughtExceptionHandlerAddressesKey];
    [userInfo setObject:@"HPSignalCrash" forKey:HPUncaughtExceptionHandlerFileKey];
    [userInfo setObject:callStack forKey:HPUncaughtExceptionHandlerCallStackSymbolsKey];

    [[[HPUncaughtExceptionHandler alloc] init]
     performSelectorOnMainThread:@selector(handleUncaughtSignalException:) withObject:
     [NSException
      exceptionWithName:HPUncaughtExceptionHandlerSignalExceptionName
      reason:[NSString stringWithFormat:NSLocalizedString(@"Signal %d was raised.\n %@", nil),signal, getAppInfo()]
      userInfo:userInfo]
     waitUntilDone:YES];
}

static void HPAbrtSignalHandler(int signal, siginfo_t* info, void* context) {
    HPSignalHandler(signal);
    //调用之前注册的handler
    if (signal == SIGABRT && originalAbrtSignalHandler) {
        originalAbrtSignalHandler(signal, info, context);
    }
}

//获取应用信息
NSString *getAppInfo() {
    NSString *appInfo = [NSString stringWithFormat:@"App : %@ %@(%@)\nDevice : %@\nOS Version : %@ %@\n",
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"],
                         [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"],
                         [UIDevice currentDevice].model,
                         [UIDevice currentDevice].systemName,
                         [UIDevice currentDevice].systemVersion];
    NSLog(@"Crash!!!! %@", appInfo);
    return appInfo;
}

@implementation HPUncaughtExceptionHandler

+ (void)installUncaughtSignalExceptionHandler {
    //可以通过 NSGetUncaughtExceptionHandler 先保存旧的，然后赋值自己新的。
    if (NSGetUncaughtExceptionHandler() != HPExceptionHandlers) {
        originalUncaughtExceptionHandler = NSGetUncaughtExceptionHandler();
    }
    //HPExceptionHandlers 赋值给 uncaught_handler()，最终_objc_terminate 调用 HPExceptionHandlers
    //NSSetUncaughtExceptionHandler 是 objc_setUncaughtExceptionHandler()的上层实现。
    NSSetUncaughtExceptionHandler(&HPExceptionHandlers);
    
    //信号量截断
//    [self registerSignalHandler];
    [self registerSigactionHandler];
}

//方式一：通过 signal 注册
+ (void)registerSignalHandler {
    signal(SIGHUP, HPSignalHandler);
    signal(SIGINT, HPSignalHandler);
    signal(SIGQUIT, HPSignalHandler);
    signal(SIGABRT, HPSignalHandler);
    signal(SIGILL, HPSignalHandler);
    signal(SIGSEGV, HPSignalHandler);
    signal(SIGFPE, HPSignalHandler);
    signal(SIGBUS, HPSignalHandler);
    signal(SIGPIPE, HPSignalHandler);
}

//方式二：通过 sigaction 注册
+ (void)registerSigactionHandler {
    struct sigaction old_action;
    sigaction(SIGABRT, NULL, &old_action);
    if (old_action.sa_flags & SA_SIGINFO) {
        if (old_action.sa_sigaction != HPAbrtSignalHandler) {
            //保存之前注册的handler
            originalAbrtSignalHandler = old_action.sa_sigaction;
        }
    }

    struct sigaction action;
    action.sa_sigaction = HPAbrtSignalHandler;
    action.sa_flags = SA_NODEFER | SA_SIGINFO;
    sigemptyset(&action.sa_mask);
    sigaction(SIGABRT, &action, 0);
}

+ (void)removeRegister:(NSException *)exception {
    NSSetUncaughtExceptionHandler(NULL);
    signal(SIGHUP, SIG_DFL);
    signal(SIGINT, SIG_DFL);
    signal(SIGQUIT, SIG_DFL);
    signal(SIGABRT, SIG_DFL);
    signal(SIGILL, SIG_DFL);
    signal(SIGSEGV, SIG_DFL);
    signal(SIGFPE, SIG_DFL);
    signal(SIGBUS, SIG_DFL);
    signal(SIGPIPE, SIG_DFL);
        
    NSLog(@"%@",[exception name]);
    //signal
    if ([[exception name] isEqual:HPUncaughtExceptionHandlerSignalExceptionName]) {
        kill(getpid(), [[[exception userInfo] objectForKey:HPUncaughtExceptionHandlerSignalKey] intValue]);
    } else {
    //exception
        [exception raise];
    }
}

- (void)handleUncaughtSignalException:(NSException *)exception {
    // 保存上传服务器
    NSDictionary *userinfo = [exception userInfo];
    [self saveCrash:exception file:[userinfo objectForKey:HPUncaughtExceptionHandlerFileKey]];
    //alert 提示相关操作
    //如果要做 UI 相关提示需要写runloop相关的代码
    //移除注册
    [HPUncaughtExceptionHandler removeRegister:exception];
}

//保存奔溃信息或者上传
- (void)saveCrash:(NSException *)exception file:(NSString *)file {
    NSArray *stackArray = [[exception userInfo] objectForKey:HPUncaughtExceptionHandlerCallStackSymbolsKey];// 异常的堆栈信息
    NSString *reason = [exception reason];// 出现异常的原因
    NSString *name = [exception name];// 异常名称
    // NSLog(@"crash: %@", exception);// 可以在console 中输出，以方便查看。
    NSString * filePath  = [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:file];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]){
        [[NSFileManager defaultManager] createDirectoryAtPath:filePath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSDate *dat = [NSDate dateWithTimeIntervalSinceNow:0];
    NSTimeInterval timeInterval = [dat timeIntervalSince1970];
    NSString *timeString = [NSString stringWithFormat:@"%f", timeInterval];
    NSString *savePath = [filePath stringByAppendingFormat:@"/error_%@.log",timeString];
    NSString *exceptionInfo = [NSString stringWithFormat:@"Exception reason：%@\nException name：%@\nException stack：%@",name, reason, stackArray];
    BOOL sucess = [exceptionInfo writeToFile:savePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSLog(@"save crash log sucess:%d, path:%@",sucess,savePath);
    //保存之后可以做上传相关操作。
}

//获取函数堆栈信息
+ (NSArray *)backtrace {
    void* callstack[128];
    int frames = backtrace(callstack, 128);//用于获取当前线程的函数调用堆栈，返回实际获取的指针个数
    char **strs = backtrace_symbols(callstack, frames);//从backtrace函数获取的信息转化为一个字符串数组
    int i;
    NSMutableArray *backtrace = [NSMutableArray arrayWithCapacity:frames];
    //过滤部分数据，从4~8取5个。
    for (i = HPUncaughtExceptionHandlerSkipAddressCount;
         i < HPUncaughtExceptionHandlerSkipAddressCount + HPUncaughtExceptionHandlerReportAddressCount;
         i++)
    {
        [backtrace addObject:[NSString stringWithUTF8String:strs[i]]];
    }
    free(strs);
    return backtrace;
}

@end

