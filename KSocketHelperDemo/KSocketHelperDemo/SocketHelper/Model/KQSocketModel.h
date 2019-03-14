//
//  KQSocketModel.h
//  IOSTestKitDemo
//  
//  Created by 王博 on 2018/8/1.
//  Copyright © 2018年 k. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface KQSocketModel : NSObject

@property (nonatomic,assign) int totoleLen;
@property (nonatomic,assign) int msgType;
@property (nonatomic,copy) NSString *msgBodyJson;
@property (nonatomic,strong) NSData *msgBodyData;
@end

