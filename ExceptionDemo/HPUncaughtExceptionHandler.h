//
//  HPUncaughtExceptionHandler.h
//  AppTest
//
//  Created by ZP on 2021/7/14.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface HPUncaughtExceptionHandler : NSObject

+ (void)installUncaughtSignalExceptionHandler;

@end

NS_ASSUME_NONNULL_END
