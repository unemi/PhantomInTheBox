//
//  Statistics.m
//  BOIDS GPU
//
//  Created by Tatsuo Unemi on 2024/12/21.
//

#import "Statistics.h"
#import "AgentCPU.h"
#import "AppDelegate.h"
@import UniformTypeIdentifiers;

typedef enum { StatHopkins, StatCellPopDist } StatType;
StatType statType = StatHopkins;

static float nearest_d(simd_float3 p, float nDist, simd_int3 v) {
	int cIdx = cell_index(v);
	for (NSInteger i = 0; i < Cells[cIdx].n; i ++) {
		int aIdx = Idxs[Cells[cIdx].start + i];
		float d = simd_distance(p, PopSim[popBfIdx][aIdx].p);
		if (nDist > d) nDist = d;
	}
	return nDist;
}
static inline int n_index1(int x) { return (x < 0)? 0 : x; }
static inline int n_index2(int x, int k)
	{ return (x > MAX_CELL_IDX[k])? MAX_CELL_IDX[k] : x; }
static float nearest_dist(simd_float3 p, NSInteger idx) {
	simd_int3 v = simd_int(p / CellSize);
	int cIdx = cell_index(v);
	float nDist = 1e10;
	for (NSInteger i = 0; i < Cells[cIdx].n; i ++) {
		int aIdx = Idxs[Cells[cIdx].start + i];
		if (aIdx == idx) continue;
		float d = simd_distance(p, PopSim[popBfIdx][aIdx].p);
		if (nDist > d) nDist = d;
	}
	for (int i = 1; nDist >= 1e10 && i < N_CELLS_X; i ++) {
		simd_int3 b1 = v - i, b2 = v + i;
		for (int j = 0; j < 3; j ++) {
			if (b1[j] >= 0) {
				simd_int3 vv = b1;
				for (int k = n_index1(b1[(j+1)%3]+j/2);
					k <= n_index2(b2[(j+1)%3]-j/2, (j+1)%3); k ++) {
					vv[(j+1)%3] = k;
					for (int l = n_index1(b1[(j+2)%3]+(j+1)/2);
						l <= n_index2(b2[(j+2)%3]-(j+1)/2, (j+2)%3); l ++) {
						vv[(j+2)%3] = l;
						nDist = nearest_d(p, nDist, vv);
					}
				}
			}
			if (b2[j] <= MAX_CELL_IDX[j]) {
				simd_int3 vv = b2;
				for (int k = n_index1(b1[(j+1)%3]+j/2);
					k <= n_index2(b2[(j+1)%3]-j/2, (j+1)%3); k ++) {
					vv[(j+1)%3] = k;
					for (int l = n_index1(b1[(j+2)%3]+(j+1)/2);
						l <= n_index2(b2[(j+2)%3]-(j+1)/2, (j+2)%3); l ++) {
						vv[(j+2)%3] = l;
						nDist = nearest_d(p, nDist, vv);
					}
				}
			}
		}
	}
	return (nDist >= 1e10)? 0. : nDist;
}
static float hopkins(void) {
	NSInteger M = 200;
	if (PopSize / 100 < M) M = PopSize / 100;
	CGFloat u = 0., w = 0.;
//	for (NSInteger i = 0; i < M; i ++) {
//		w += nearest_dist(
//			(simd_float3){drand48(), drand48(), drand48()} * WS, -1);
//		NSInteger idx = i * PopSize / M + (lrand48() % M);
//		u += nearest_dist(PopSim[idx].p, idx);
//	}
	NSInteger nm = M / nCores;
	CGFloat *uu = malloc(sizeof(CGFloat) * nCores * 2), *ww = uu + nCores;
	memset(uu, 0, sizeof(CGFloat) * nCores * 2);
	void (^add_uw)(NSInteger, NSInteger, NSInteger) =
	^(NSInteger j, NSInteger from, NSInteger to){
		for (NSInteger i = from; i < to; i ++) {
			ww[j] += nearest_dist(
				(simd_float3){drand48(), drand48(), drand48()} * WS, -1);
			NSInteger idx = i * PopSize / M + (lrand48() % M);
			uu[j] += nearest_dist(PopSim[popBfIdx][idx].p, idx);
		}
	};
	for (NSInteger j = 0; j < nCores - 1; j ++)
		dispatch_group_async(DispatchGrp, DispatchQue,
			^{ add_uw(j, j * nm, (j + 1) * nm); });
	add_uw(nCores - 1, (nCores - 1) * nm, M);
	dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	for (NSInteger i = 0; i < nCores; i ++) { u += uu[i]; w += ww[i]; }
	free(uu);
	return u / (u + w);
}
static void cell_pop_dist(NSInteger *cnt) {
	for (NSInteger i = 0; i < N_CELLS; i ++)
		cnt[i] = Cells[i].n;
	qsort_b(cnt, N_CELLS, sizeof(NSInteger), ^(const void *a, const void *b) {
		NSInteger x = *((NSInteger *)a), y = *((NSInteger *)b);
		return (x < y)? 1 : (x > y)? -1 : 0;
	});
}
#define XOFFSET 30
#define YOFFSET 20
#define MAX_N_POINTS 512

typedef struct { CGFloat xMin, xMax, yMin, yMax; } XYRange;
Statistics *statistics = nil;
@interface Statistics () {
	NSMutableArray<NSValue *> *points;
	NSLock *pointsLock;
	XYRange range;
	NSInteger interval, nAccm;
	CGFloat vAccm;
	NSInteger *cellPopDist, nCells;
}
@property IBOutlet __weak NSView *view;
@end

@implementation Statistics
- (NSString *)windowNibName { return @"Statistics"; }
- (void)reset {
	[pointsLock lock];
	points = NSMutableArray.new;
	range.xMin = 1e10; range.xMax = -1e10;
	range.yMin = 0.; range.yMax = 0.5;
	interval = 1;
	nAccm = 0;
	vAccm = 0.;
	[pointsLock unlock];
}
- (void)step {
	CGFloat t = Step;
	float value = hopkins();
	vAccm = (vAccm * nAccm + value) / (nAccm + 1);
	[pointsLock lock];
	if ((++ nAccm) >= interval) {
		[points addObject:[NSValue valueWithPoint:(NSPoint){t, vAccm}]];
		if (range.xMin > t) range.xMin = t;
		if (range.xMax < t) range.xMax = t;
		if (range.yMin > value) range.yMin = value;
		if (range.yMax < value) range.yMax = value;
		nAccm = 0; vAccm = 0.;
		if (points.count >= MAX_N_POINTS) {
			NSMutableArray<NSValue *> *newPts = NSMutableArray.new;
			for (NSInteger i = 0; i < points.count; i += 2) {
				NSPoint p1 = points[i].pointValue, p2 = points[i + 1].pointValue;
				[newPts addObject:
					[NSValue valueWithPoint:(NSPoint){p2.x, (p1.y + p2.y) / 2.}]];
			}
			points = newPts;
			interval *= 2;
		}
	}

	if (nCells != N_CELLS)
		cellPopDist = realloc(cellPopDist, sizeof(NSInteger) * (nCells = N_CELLS));
	cell_pop_dist(cellPopDist);
	[pointsLock unlock];

	in_main_thread(^{ self.view.needsDisplay = YES; });
}
- (void)windowDidLoad {
    [super windowDidLoad];
    pointsLock = NSLock.new;
	[self reset];
}
static CGFloat scaled_x(CGFloat x, XYRange rng, NSRect bounds) {
	return (x - rng.xMin) * (bounds.size.width - XOFFSET) / (rng.xMax - rng.xMin)
		+ NSMinX(bounds) + XOFFSET;
}
static void draw_tics(NSBezierPath *path, XYRange rng, NSRect bounds) {
	CGFloat ticSpan = (rng.xMax - rng.xMin) / 5., ticExp = floor(log10(ticSpan)),
		ticMnts = ticSpan / pow(10., ticExp);
	ticSpan = ((ticMnts < 2.)? 1. : (ticMnts < 5.)? 2. : 5.) * pow(10., ticExp);
	NSDictionary *attr = @{NSFontAttributeName:[NSFont systemFontOfSize:YOFFSET/2.],
		NSForegroundColorAttributeName:NSColor.whiteColor};
	if (ticSpan > 1.) for (CGFloat ticX = ticSpan; ticX < rng.xMax; ticX += ticSpan)
		if (ticX > rng.xMin) {
			CGFloat x = scaled_x(ticX, rng, bounds);
			[path moveToPoint:(NSPoint){x, YOFFSET}];
			[path relativeLineToPoint:(NSPoint){0., -YOFFSET / 4.}];
			NSString *dgts = [NSString stringWithFormat:@"%.0f", ticX];
			[dgts drawAtPoint:(CGPoint){x - [dgts sizeWithAttributes:attr].width / 2.,
				YOFFSET / 5.} withAttributes:attr];
	}
}
- (void)drawPathIn:(NSRect)bounds {
	NSBezierPath *path = NSBezierPath.new;
	[path moveToPoint:(NSPoint){0, YOFFSET}];
	[path lineToPoint:(NSPoint){NSMaxX(bounds), YOFFSET}];
	[path moveToPoint:(NSPoint){XOFFSET, 0}];
	[path lineToPoint:(NSPoint){XOFFSET, NSMaxY(bounds)}];
	[pointsLock lock];
	switch (statType) {
		case StatHopkins:
		if (points.count > 1) {
			XYRange rng = range;
			draw_tics(path, rng, bounds);
			NSPoint (^xy)(NSValue *) = ^(NSValue *v) {
				NSPoint p = [v pointValue];
				return (NSPoint){scaled_x(p.x, rng, bounds),
					(p.y - rng.yMin) * (bounds.size.height - YOFFSET) / (rng.yMax - rng.yMin)
						+ NSMinY(bounds) + YOFFSET};
			};
			[path moveToPoint:xy(points[0])];
			for (NSInteger i = 1; i < points.count; i ++)
				[path lineToPoint:xy(points[i])];
		}
		break;
		case StatCellPopDist:
		draw_tics(path, (XYRange){.xMin = 0., .xMax = nCells}, bounds);
		if (cellPopDist != NULL) {
			[path moveToPoint:(NSPoint){XOFFSET, NSMaxY(bounds)}];
			CGFloat yRatio = (CGFloat)(NSMaxY(bounds) - YOFFSET) / cellPopDist[0],
				skip = (CGFloat)(NSMaxX(bounds) - XOFFSET) / (nCells - 1);
			for (NSInteger i = 1; i < nCells; i ++) [path lineToPoint:
				(NSPoint){i * skip + XOFFSET, cellPopDist[i] * yRatio + YOFFSET}];
		}
	}
	[pointsLock unlock];
	[NSColor.clearColor setFill];
	[NSColor.whiteColor setStroke];
	[path stroke];
}
- (void)windowWillClose:(NSNotification *)notification {
	statistics = nil;
}
- (IBAction)selectType:(NSButton *)btn {
	StatType newType = (StatType)btn.tag;
	if (newType == statType) return;
	if ((statType = newType) == StatHopkins) {
		[pointsLock lock];
		
		[pointsLock unlock];
	}
	self.view.needsDisplay = YES;
}
- (void)writeHopkinsStat:(NSOutputStream *)outStr {
	[outStr open];
	char buf[128];
	for (NSInteger i = 0; i < points.count; i ++) {
		NSPoint p = [points[i] pointValue];
		sprintf(buf, "%.0f,%.4f\r\n", p.x + 1, p.y);
		[outStr write:(const UInt8 *)buf maxLength:strlen(buf)];
	}
	[outStr close];
}
- (void)writeCSVCellPopDist:(NSOutputStream *)outStr {
	[outStr open];
	char buf[128];
	for (NSInteger i = 0; i < nCells; i ++) {
		sprintf(buf, "%ld,%ld\r\n", i + 1, cellPopDist[i]);
		[outStr write:(const UInt8 *)buf maxLength:strlen(buf)];
	}
	[outStr close];
}
- (IBAction)saveAsCSV:(id)sender {
	NSSavePanel *sp = NSSavePanel.new;
	sp.allowedContentTypes = @[UTTypeCommaSeparatedText];
	sp.message = @"Save current data into a CSV format file.";
	[sp beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
		if (result != NSModalResponseOK) return;
		NSOutputStream *outStr = [NSOutputStream outputStreamWithURL:sp.URL append:NO];
		if (!outStr) err_msg(@"", NO);
		else switch (statType) {
			case StatHopkins:[self writeHopkinsStat:outStr]; break;
			case StatCellPopDist:[self writeCSVCellPopDist:outStr];
		}
	}];
}
@end

@interface TrendView : NSView
@end

@implementation TrendView
- (void)drawRect:(NSRect)dirtyRect {
	[NSColor.blackColor setFill];
	[NSBezierPath fillRect:NSIntersectionRect(self.bounds, dirtyRect)];
	[statistics drawPathIn:self.bounds];
}
@end
