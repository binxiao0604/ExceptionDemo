//
//  ViewController.m
//  ExceptionDemo
//
//  Created by ZP on 2021/7/14.
//

#import "ViewController.h"

@interface ViewController ()

@property (nonatomic, strong) NSMutableArray *dataArray;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.dataArray = [@[@1,@2,@3,@4] mutableCopy];
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    //exception错误
//    NSLog(@"%@",self.dataArray[4]);
    
    //signal 错误
    void *singal = malloc(1024);
    free(singal);
    free(singal);//SIGABRT的错误
}


@end
