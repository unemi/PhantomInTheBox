//
//  MonitorView.m
//  RealSenseTEST
//
//  Created by Tatsuo Unemi on 2025/02/05.
//  Copyright © 2025 Tatsuo Unemi. All rights reserved.
//

#import "MonitorView.h"
#import "AppDelegate.h"
@import simd;

static uint32 scale2rgb(float s) {
	static struct {
		float rate, rgb[3];
	} sc[] = {
		{0., 0., 0., 1.},	// blue
		{.15, 0., 1., 1.},	// cyan
		{.35, 0., 1., 0.},	// green
		{.5, 1., 1., 0.},	// yellow
		{.8, 1., 0., 0.},	// red
		{1., 1., 1., 1.},	// white
	};
	if (s == 0.) return 0;
	s = fmin(1., s);
	int k = 0;
	for (int i = 0; i < 5; i ++)
		if (s < sc[i + 1].rate) { k = i; break; }
	float a = (s - sc[k].rate) / (sc[k + 1].rate - sc[k].rate);
	unsigned char rgb[3];
	for (int i = 0; i < 3; i ++)
		rgb[i] = (sc[k + 1].rgb[i] * a + sc[k].rgb[i] * (1. - a)) * 255;
	return rgb[0] | (rgb[1] << 8) | (rgb[2] << 16);
}
@implementation MonitorView {
	NSBitmapImageRep *imgRep;
	NSData *pointsData;
	NSLock *lock;
}
- (instancetype)initWithCoder:(NSCoder *)coder {
	if (!(self = [super initWithCoder:coder])) return nil;
	lock = NSLock.new;
	return self;
}
- (void)drawPoints {
	const PointInfo *pp = pointsData.bytes;
	NSInteger nPoints = pointsData.length / sizeof(PointInfo);
	float scl = self.bounds.size.width / 2.;
	float th = ((current_time_us() / 1000) % 10000) / 10000. * M_PI * 2.;
	float az = 0.;
	for (NSInteger i = 0; i < nPoints; i ++) az += pp[i].p.z;
	az /= nPoints;
	NSRect bounds = self.bounds;
	float ptSize = bounds.size.width / 256.;
	for (NSInteger i = 0; i < nPoints; i ++) {
		simd_float3 p = pp[i].p;
		p.z -= az;
		p = (simd_float3){p.x * cos(th) - p.z * sin(th), p.y, p.x * sin(th) + p.z * cos(th)};
		p.z += az;
		simd_float2 q = (p.xy / p.z / .95 + (simd_float2){1., (float)HEIGHT/WIDTH}) * scl - ptSize / 2.;
		NSPoint qp = {q.x, q.y};
		union { UInt32 rgb; unsigned char c[4]; } col = { .rgb = pp[i].c.rgb };
		if (NSPointInRect(qp, bounds)) {
			[[NSColor colorWithRed:col.c[0] / 255. green:col.c[1] / 255.
				blue:col.c[2] / 255. alpha:1.] setFill];
			[NSBezierPath fillRect:(NSRect){qp, ptSize, ptSize}];
		}
	}
}
- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
	[lock lock];
	if (imgRep) { [imgRep drawInRect:self.bounds]; imgRep = nil; }
	else {
		[NSColor.blackColor setFill];
		[NSBezierPath fillRect:NSIntersectionRect(dirtyRect, self.bounds)];
		if (pointsData) { [self drawPoints]; pointsData = nil; }
	}
	[lock unlock];
}
- (void)fetchFrameRGB:(UInt32 (^)(int))getRGB {
	[lock lock];
	imgRep = [NSBitmapImageRep.alloc
		initWithBitmapDataPlanes:NULL pixelsWide:WIDTH pixelsHigh:HEIGHT
		bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO
		colorSpaceName:NSCalibratedRGBColorSpace
		bytesPerRow:WIDTH*4 bitsPerPixel:32];
	uint32 *buffer = (UInt32 *)imgRep.bitmapData;
	for (int i = 0; i < WIDTH * HEIGHT; i ++) buffer[i] = getRGB(i);
	in_main_thread(^{ self.needsDisplay = YES; });
	[lock unlock];
}
- (void)fetchFrameImage:(float (^)(int))filter {
	[self fetchFrameRGB:^(int idx)
		{ return scale2rgb(filter(idx)); }];
}
- (void)setPointsData:(NSData *)data {
	[lock lock];
	pointsData = data;
	in_main_thread(^{ self.needsDisplay = YES; });
	[lock unlock];
}
@end
