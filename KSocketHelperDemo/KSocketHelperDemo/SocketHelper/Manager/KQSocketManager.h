//
//  KQSocketManager.h
//  IOSTestKitDemo
//  封包格式：数据包长度（int4字节）+消息id（int4字节）+data数据（json格式String）
//  数据包长度=消息id长度+data数据长度
//  Created by 王博 on 2018/8/1.
//  Copyright © 2018年 k. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "KQSocketModel.h"

@protocol KQSocketManagerDelegate <NSObject>
/* sockt 重连达到最大次数，依然失败*/
-(void)kSocketReconnectByMaxCount;
/* sockt 连接成功*/
-(void)kSocketDidConnectSuccess;
/* sockt 返回解析好的数据
   备注：如果bodyData可以解析成Json则解析成Json
 */
-(void)kSocketDidReadData:(KQSocketModel*)model;
@end

@interface KQSocketManager : NSObject

+(instancetype)getInstance;
+(void)destoryInstance;

@property (nonatomic,weak) id<KQSocketManagerDelegate> delegate;
/* sockt 连接超时时间，默认20S*/
@property (nonatomic,assign) NSInteger connectTimeOut ;
/* sockt 最大重连次数，默认10次，
 备注：该次数为失败后连续次数，即连接成功后会重新计数
 重连分三个阶段，第一阶段，秒重连，第二阶段，延迟2秒重连，第三阶段，重连次数秒数后重连
 */
@property (nonatomic,assign) NSInteger reconnectMaxCount ;
/* sockt 是否正在连接*/
@property (nonatomic,assign,readonly) BOOL isConnected;


/* 连接socket*/
-(void) connectSever:(NSString*)host port:(int) port;
/* 关闭socket*/
-(void)closeServer;
/* sockt 发送数据
 备注：如果msgBodyJson属性有值，则以msgBodyJson属性为准
 */
-(void) writeData:(KQSocketModel*) model;



@end
