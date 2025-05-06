//
//  AppDelegate.h
//  DepthCaptureRS
//
//  Created by Tatsuo Unemi on 2025/02/08.
//

#define WIDTH 640
#define HEIGHT 480

@import simd;
#import <Cocoa/Cocoa.h>
#import "../CommHeaders/PointInfo.h"
#import "MonitorView.h"
#define COL_SCR_SIZE_RATIO 1.38

typedef enum {
	MonitorNone, MonitorDepth, MonitorDensity, MonitorPoints,
	MonitorRGB
} MonitorType;

typedef struct {
	MonitorType monitorType;
	BOOL senderOn, mirrorOn;
	char IPV4Address[16];
	uint16 portNumber, maxDepth;
	NSInteger numPtMax, numPtMin;
	CGFloat rgbOffset, density;
	simd_float4 geom;
} Parameters;

extern Parameters params;

@interface AppDelegate : NSObject
<NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation>
@property IBOutlet MonitorView *monitorView;
@property NSMutableData *pointsData;
- (void)adjustMaxNumPts:(NSInteger)numPts;
@end

extern unsigned long current_time_us(void);
extern void in_main_thread(void (^block)(void));
extern void err_msg(NSObject *object, BOOL fatal);
extern void unix_error_msg(NSString *msg, BOOL fatal);
extern int indexRGB2Depth(int colIdx);
extern int indexDepth2RGB(int dptIdx);

extern RequestFromSv req, newReq;
extern dispatch_group_t DispatchGrp;
extern dispatch_queue_t DispatchQue;
extern NSInteger nCores;
