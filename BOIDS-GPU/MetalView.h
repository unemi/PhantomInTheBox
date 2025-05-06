//
//  MetalView.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

typedef struct {
	float depth, scale, contrast;
	float agentSize, agentOpacity, shadowOpacity, fogDensity;
} ViewParams;
typedef enum { ShapePaperPlane, ShapeBlob, ShapePoints } ShapeType;
#define N_VPARAMS (sizeof(ViewParams)/sizeof(float))

@interface MyMTKView : MTKView
@end

@interface MetalView : NSObject
<MTKViewDelegate, NSMenuItemValidation, NSWindowDelegate>
@property IBOutlet MyMTKView *view;
- (BOOL)isRunning;
- (void)revisePopSize:(NSInteger)newSize;
- (void)reviseSightDistance;
- (IBAction)fullScreen:(_Nullable id)sender;
- (IBAction)playPause:(_Nullable id)sender;
@end

extern CGFloat FPS;
extern simd_float3 WallRGB, AgntRGB, FogRGB;
extern BOOL Colorful;
extern ViewParams ViewPrms, DfltViewPrms;
extern ShapeType shapeType;
extern NSString * _Nonnull ViewPrmLbls[];

NS_ASSUME_NONNULL_END
