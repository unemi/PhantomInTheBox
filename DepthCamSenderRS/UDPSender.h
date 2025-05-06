//
//  UDPSender.h
//  DepthCaptureRS
//
//  Created by Tatsuo Unemi on 2025/02/08.
//

#import <Foundation/Foundation.h>

extern void sender_open(const char *ip4addr, UInt16 portNumber);
extern BOOL say_hello(BOOL *senderOn);
extern void sender_step(NSData *dataToBeSent);
extern void sender_close(void);
extern BOOL read_spec(void);
