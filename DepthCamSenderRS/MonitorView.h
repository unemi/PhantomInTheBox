//
//  MonitorView.h
//  RealSenseTEST
//
//  Created by Tatsuo Unemi on 2025/02/05.
//  Copyright © 2025 Tatsuo Unemi. All rights reserved.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface MonitorView : NSView
- (void)fetchFrameRGB:(UInt32 (^)(int))getRGB;
- (void)fetchFrameImage:(float (^)(int))filter;
- (void)setPointsData:(NSData *)data;
@end

NS_ASSUME_NONNULL_END
