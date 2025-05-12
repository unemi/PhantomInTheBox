//
//  CommPanel.h
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/30.
//

@import Cocoa;
#import "Comm.h"

NS_ASSUME_NONNULL_BEGIN

typedef struct { UInt32 start, n; } PtCell;

@interface CommPanel : NSWindowController
	<NSWindowDelegate, NSMenuItemValidation>
@end

extern void check_initial_communication(void);
extern BOOL communication_is_running(void);
extern ssize_t send_packet(const char *buf, int length);
extern void write_vecfld_CSV(void);

@interface Tracker : NSObject <CommDelegate>
- (void)lock;
- (void)unlock;
- (void)stepTracking;
- (void)sendRequest;
@property NSInteger lastStepOfFrame;
@end

@interface Sender : NSObject
- (void)invalidate;
- (void)setPacketPerSec:(float)pktPerSec;
@end

extern Tracker *theTracker;
extern PtCell *PtCells, *PtCelWk;
extern simd_float3 *Points, *PointsWk;
extern NSInteger ptBfIdx, nPoints;

@interface MyTextField : NSTextField
@end

NS_ASSUME_NONNULL_END
