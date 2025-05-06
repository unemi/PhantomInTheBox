//
//  MyRealSense.h
//  RealSenseTEST
//
//  Created by Tatsuo Unemi on 2020/08/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

extern BOOL rs_initialize(id delegate, void (*proc)(id, uint16 *, uint32 *));
extern BOOL rs_start(void);
extern BOOL rs_step(void);
extern void rs_stop(void);
extern void rs_close(void);

NS_ASSUME_NONNULL_END
