//
//  Comm.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/28.
//

@import Cocoa;
@import simd;
#import "../CommHeaders/PointInfo.h"

NS_ASSUME_NONNULL_BEGIN

#define OSC_PORT 5000
#define DST_PKT_PER_SEC 1
#define RCV_PORT 9003

@protocol CommDelegate
- (void)receive:(PointInfoPacket *)buf length:(ssize_t)length;
@end

@interface Comm : NSObject
@property (readonly) BOOL valid, rcvRunning;
@property (readonly) NSString *myAddress, *myBroadcastAddress, *senderAddress;
@property NSString *destinationAddress;
@property in_port_t destinationPort, receiverPort;
- (void)setStatHandlersSnd:(void (^ _Nullable)(ssize_t nBytes))sndHdl
	rcv:(void (^ _Nullable)(ssize_t nBytes))rcvHdl;
- (ssize_t)send:(const char *)buf length:(int)len;
- (BOOL)startReceiverWithPort:(UInt16)rcvPort delegate:(id<CommDelegate>)dlgt;
- (void)stopReceiver;
- (ssize_t)sendbackRequestInfo:(RequestFromSv *)req;
- (void)invalidate;
@end

NS_ASSUME_NONNULL_END
