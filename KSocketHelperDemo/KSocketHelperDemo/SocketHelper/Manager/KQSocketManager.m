//
//  KQSocketManager.m
//  IOSTestKitDemo
//  封包格式：数据包长度（int4字节）+消息id（int4字节）+data数据（json格式String）
//  数据包长度=消息id长度+data数据长度
//  Created by 王博 on 2018/8/1.
//  Copyright © 2018年 k. All rights reserved.
//

#import "KQSocketManager.h"
#import "GCDAsyncSocket.h"

#ifdef DEBUG
# define KLog(fmt, ...) NSLog((@"\n[文件名:%s]\n" "[函数名:%s]\n" "[行号:%d] \n" fmt "\n==============================================================================="), __FILE__, __FUNCTION__, __LINE__, ##__VA_ARGS__);
#else
# define KLog(...);
#endif

#define DEFAULT_CONNECT_TIME_OUT                20

#define DEFAULT_RECONNECT_MAX_COUNT                 10

@interface KQSocketManager()<GCDAsyncSocketDelegate>
//接收服务器发过来的的data 本地缓存Data
@property (nonatomic, strong) NSMutableData *receiveData;
//Socket
@property (nonatomic, strong) GCDAsyncSocket *clientSocket;

@property (nonatomic, copy) NSString *socketHost;

@property (nonatomic, assign) int socketPort;

@property (nonatomic, assign) NSInteger currentReconnectCount;
@end

@implementation KQSocketManager

static KQSocketManager *socketManager = nil;
static dispatch_once_t onceToken;
+(instancetype)getInstance
{
    
    dispatch_once(&onceToken, ^{
        if (!socketManager) {
            socketManager = [[KQSocketManager alloc] init];
        }
    });
    return socketManager;
}
+(void)destoryInstance
{
    onceToken = 0;
    socketManager = nil;
}
#pragma mark =================Public Method===================
-(void) connectSever:(NSString*)host port:(int) port
{
    self.socketHost = host;
    self.socketPort = port;
    if(!self.clientSocket.isConnected)
    {
//        [self.clientSocket connectToHost:host onPort:port error:nil];
        NSError *error = nil;
        BOOL connectFlag =  [self.clientSocket connectToHost:host onPort:port withTimeout:self.connectTimeOut error:&error];
        if(connectFlag)
        {
            KLog(@"socket connectHost成功 host:%@  port:%d",host,port);
        }
        else
        {
            KLog(@"socket connectHost失败 error = %@",error);
        }
        
    }
}
-(void)closeServer
{
    [self.clientSocket disconnect];
}
-(void) writeData:(KQSocketModel*) model
{
    
    //msgtype 转成大端
    int msgTypeForBig = ntohl(model.msgType);
    
    //判断json是否为空，如过不为空以json为准
    if(model.msgBodyJson != nil && ![model.msgBodyJson isEqualToString:@""])
    {
        model.msgBodyData = [model.msgBodyJson dataUsingEncoding:NSUTF8StringEncoding];
    }
    
    
    //计算数据总长度，并转成大端
    int totalLen = (int)model.msgBodyData.length + sizeof(model.msgType);
    int totalLenForBig = ntohl(totalLen);
    
    //发送总长度
    NSData *totalLendata = [NSData dataWithBytes: &totalLenForBig length: sizeof(totalLenForBig)];
    [self.clientSocket writeData:totalLendata withTimeout:- 1 tag:0];
    //发送msgType
    NSData *msgTypeData = [NSData dataWithBytes:&msgTypeForBig length:sizeof(msgTypeForBig)];
    [self.clientSocket writeData:msgTypeData withTimeout:- 1 tag:0];
    //发送Data
    [self.clientSocket writeData:model.msgBodyData withTimeout:- 1 tag:0];
    KLog(@"socket 发送数据 msgtype:%d bodyJson:%@ bodyData lenght:%ld",model.msgType,model.msgBodyJson,model.msgBodyData.length);
}

-(BOOL) isConnected
{
    return self.clientSocket.isConnected;
}

#pragma mark =================Private Method===================
-(void)parseMsgContentByLen:(int) msgContentLen
{
    
    //    NSRange range = NSMakeRange(0, 4 + msgContentLen);   //本次解析data的范围
    //    NSData *data = [self.receiveData subdataWithRange:range]; //本次解析的data
    
    //本次解析头部data的范围
    NSRange headerRange = NSMakeRange(0, 4);
    //移除头部
    [self.receiveData replaceBytesInRange:headerRange withBytes:NULL length:0];
    
    //本次解析msgType的范围
    NSRange msgTypeRange = NSMakeRange(0, 4);
    NSData *msgTypeData = [self.receiveData subdataWithRange:msgTypeRange];
    
    int msgTypeForBig ;
    [msgTypeData getBytes: &msgTypeForBig length: sizeof(msgTypeForBig)];
    int msgType = htonl(msgTypeForBig);
    //    KLog(@"socket 接受到数据 msgType = %d",msgType);
    
    //移除msgType
    [self.receiveData replaceBytesInRange:msgTypeRange withBytes:NULL length:0];
    
    //本次解析body范围
    NSRange bodyRange = NSMakeRange(0, msgContentLen-4);
    NSData *bodyData = [self.receiveData subdataWithRange:bodyRange];
    NSString *bodyJson = [[NSString alloc] initWithData:bodyData encoding:NSUTF8StringEncoding];
    
    KQSocketModel *model = [[KQSocketModel alloc] init];
    model.msgType = msgType;
    model.msgBodyData = bodyData;
    model.msgBodyJson = bodyJson;
    
    KLog(@"socket 接收到数据: msgTyep:%d bodyJson:%@  bodyData lenght:%ld",model.msgType,model.msgBodyJson,model.msgBodyData.length);
    if(self.delegate && [self.delegate respondsToSelector:@selector(kSocketDidReadData:)])
    {
        [self.delegate kSocketDidReadData:model];
    }
    
    
    //移除已经解析过的data
    [self.receiveData replaceBytesInRange:bodyRange withBytes:NULL length:0];
    ///本次解析完成，但是粘包的情况下，查看是否还够下一条消息
    
    if(self.receiveData.length > 4)
    {
        NSRange headerRange = NSMakeRange(0, 4);
        NSData *headerData = [self.receiveData subdataWithRange:headerRange];
        int msgContentLenForBig ;
        [headerData getBytes: &msgContentLenForBig length: sizeof(msgContentLenForBig)];
        int msgContentLen = htonl(msgContentLenForBig);
        
        if(msgContentLen + 4 > self.receiveData.length)
        {
            [self.clientSocket readDataWithTimeout:- 1 tag:0];
            return;
        }
        
        [self parseMsgContentByLen:msgContentLen];
    }
    else
    {
        [self.clientSocket readDataWithTimeout:- 1 tag:0];
    }
}
-(void)beginReConnectSocket
{
    if(self.currentReconnectCount < self.reconnectMaxCount)
    {
        KLog(@"准备开始第%ld次重连",self.currentReconnectCount+1);
        if(self.currentReconnectCount < self.reconnectMaxCount/3)
        {
            [self reConnectSocket];
        }
        else if(self.currentReconnectCount > self.reconnectMaxCount/3 && self.currentReconnectCount < self.reconnectMaxCount/3*2)
        {
            __weak typeof (self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf reConnectSocket];
            });
        }
        else
        {
            __weak typeof (self) weakSelf = self;
            NSInteger afterTime = self.currentReconnectCount;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(afterTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [weakSelf reConnectSocket];
            });
        }
        self.currentReconnectCount ++;
    }
    else
    {
        KLog(@"重连达到最大次数!!!");
        self.currentReconnectCount = 0;
        if(self.delegate && [self.delegate respondsToSelector:@selector(kSocketReconnectByMaxCount)])
        {
            [self.delegate kSocketReconnectByMaxCount];
        }
        
    }
}

-(void)reConnectSocket
{
    NSError *error = nil;
    BOOL connectFlag =  [self.clientSocket connectToHost:self.socketHost onPort:self.socketPort withTimeout:self.connectTimeOut error:&error];
    if(connectFlag)
    {
        KLog(@"socket connectHost成功");
    }
    else
    {
        KLog(@"socket connectHost失败 error = %@",error);
    }
}
#pragma mark =================GCDAsyncSocketDelegate===================
- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(nullable NSError *)err
{
    KLog(@"socket 连接失败:%p Error: %@", socket, err);
    [self beginReConnectSocket];
}
- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port
{
    KLog(@"socket 连接成功!!! socket:%p    host:%@  port:@%d  ",sock,host,port);
    [self.clientSocket readDataWithTimeout:- 1 tag:0];
    if(self.delegate && [self.delegate respondsToSelector:@selector(kSocketDidConnectSuccess)])
    {
        [self.delegate kSocketDidConnectSuccess];
    }
    
}
- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag
{
    [self.receiveData appendData:data];
    
    if(self.receiveData.length > 4)
    {
        NSRange headerRange = NSMakeRange(0, 4);
        NSData *headerData = [self.receiveData subdataWithRange:headerRange];
        int msgContentLenForBig ;
        [headerData getBytes: &msgContentLenForBig length: sizeof(msgContentLenForBig)];
        int msgContentLen = htonl(msgContentLenForBig);
        
        if(msgContentLen + 4 > self.receiveData.length)
        {
            [sock readDataWithTimeout:-1 tag:0];
            return;
        }
        
        [self parseMsgContentByLen:msgContentLen];
    }
    else
    {
        [self.clientSocket readDataWithTimeout:- 1 tag:0];
    }
}




#pragma mark =================Get===================
-(NSInteger)connectTimeOut
{
    if( _connectTimeOut == 0)
    {
        _connectTimeOut = DEFAULT_CONNECT_TIME_OUT;
    }
    return _connectTimeOut;
}
-(NSInteger)reconnectMaxCount
{
    if(_reconnectMaxCount == 0)
    {
        _reconnectMaxCount = DEFAULT_RECONNECT_MAX_COUNT;
    }
    return _reconnectMaxCount;
}
-(GCDAsyncSocket*)clientSocket
{
    if(_clientSocket == nil)
    {
        _clientSocket = [[GCDAsyncSocket alloc] initWithDelegate:self delegateQueue:dispatch_get_main_queue()];
    }
    return _clientSocket;
}
/** 存储服务器发过来的的data 本地缓存Data */
- (NSMutableData *)receiveData{
    if (_receiveData == nil){
        _receiveData = [[NSMutableData alloc] init];
    }
    return _receiveData;
}
@end
