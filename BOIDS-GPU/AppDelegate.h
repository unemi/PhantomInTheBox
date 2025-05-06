//
//  AppDelegate.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/14.
//

#import <Cocoa/Cocoa.h>
#import "CommPanel.h"
#import "Statistics.h"
//#define SAVE_IMAGES
//#define MAKE_CSV
// for 30fps 2min movie
//#define FRMCNT_START 30
//#define FRMCNT_END (FRMCNT_START+30*60*2)
// for frame images
//#define FRMCNT_START 300
//#define FRMCNT_END (FRMCNT_START+30*20)

typedef struct { CGFloat red, green, blue; } MyRGB;

@interface PanelController : NSWindowController
<NSWindowDelegate, NSMenuItemValidation>
- (NSApplicationTerminateReply)appTerminate;
- (void)resetCamera;
- (void)camDepthModified;
- (void)camScaleModified;
- (void)setValuesFromDict:(NSDictionary *)dict;
@end

@class MetalView;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property IBOutlet MetalView *metalView;
@property (readonly) PanelController *pnlCntl;
@property (readonly) CommPanel *pnlComm;
@end

extern NSString *FullScreenName;
extern void in_main_thread(void (^block)(void));
extern void err_msg(NSObject *object, BOOL fatal);
extern void unix_error_msg(NSString *msg, BOOL fatal);
extern void load_defaults(void);
