//
//  Statistics.h
//  BOIDS GPU
//
//  Created by Tatsuo Unemi on 2024/12/21.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface Statistics : NSWindowController <NSWindowDelegate>
- (void)reset;
- (void)step;
@end

extern Statistics *statistics;

NS_ASSUME_NONNULL_END
