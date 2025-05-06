//
//  CalcPoints.m
//  DepthCamSenderRS
//
//  Created by Tatsuo Unemi on 2025/02/11.
//

#import "CalcPoints.h"
#import "AppDelegate.h"
#import "../CommHeaders/PointInfo.h"
@import simd;

typedef struct {
	uint16 maxDepth;
	NSInteger numPtMax, numPtMin;
	CGFloat density;
} PointParams;

static PointParams prms;

static double calc_density_map(uint16 *frameData, float *output) {
	double areaSize = 0.;
	static simd_float3 fltXe = {-1, 0, 1}, fltXc = {-3, 0, 3}, fltY = {1, 3, 1};
	memset(output, 0, WIDTH * sizeof(float));
	memset(output + WIDTH * (HEIGHT - 1), 0, WIDTH * sizeof(float));
//	float minF = 1e10, maxF = -1e10;
	for (int iy = 1; iy < HEIGHT-1; iy ++) {
		output[iy * WIDTH] = output[(iy + 1) * WIDTH - 1] = 0;
		for (int ix = 1; ix < WIDTH-1; ix ++) {
			int idx = iy * WIDTH + ix;
			simd_float3 z[3];
			BOOL cont = YES;
			for (int j = 0; j < 3 && cont; j ++)
			for (int i = 0; i < 3 && cont; i ++) {
				uint16 d = frameData[idx + (j - 1) * WIDTH + i - 1];
				if (d > prms.maxDepth || d == 0) { output[idx] = 0.; cont = NO; break; }
				z[j][i] = (float)d;
			}
			if (!cont) continue;
			float g = simd_length((simd_float2){
				simd_reduce_add((z[0] + z[2]) * fltXe + z[1] * fltXc),
				simd_reduce_add((z[0] - z[2]) * fltY)})
				/ 5. / (z[2][1] * .95 / WIDTH * 4);
			areaSize += output[idx] = sqrt(g * g + 1.) * z[1].y / (WIDTH / 2 * 95.);// * 6e-5;
//			if (minF > output[idx]) minF = output[idx];
//			if (maxF < output[idx]) maxF = output[idx];
		}
	}
//	static int cnt = 0;
//	if ((++ cnt) >= 60) { NSLog(@"Range=(%.2f, %2f)", minF, maxF); cnt = 0; }
	return areaSize;
}
typedef struct { float p; NSInteger idx; } Roulette;
static NSInteger toss_roulette(Roulette *roulette, NSInteger size) {
	float r = (float)drand48() * roulette[size - 1].p;
	NSInteger kBegin = 0, kEnd = size;
	while (kEnd - kBegin > 1) {
		NSInteger k = (kBegin + kEnd - 1) / 2;
		float p = roulette[k].p;
		if (r < p) kEnd = k + 1;
		else if (r > p) kBegin = k + 1;
		else kBegin = kEnd = k;
	}
	return roulette[kBegin].idx;
}
//#define TIME_MEASURE
#ifdef TIME_MEASURE
#define N_TMS 3
static unsigned long tm[N_TMS+1], tmAcc[N_TMS] = {0}, tmCnt = 0;
#endif
@implementation CalcPoints
- (instancetype)init {
	if (!(self = [super init])) return nil;
	_densityMapData = [NSMutableData dataWithLength:WIDTH * HEIGHT * sizeof(float)];
	return self;
}
- (NSMutableData *)calcPointsFromDepth:(uint16 *)frameData color:(uint32 *)colorData {
	float *densityMap = _densityMapData.mutableBytes;
	prms.maxDepth = params.maxDepth;
	prms.numPtMax = params.numPtMax;
	prms.numPtMin = params.numPtMin;
	prms.density = params.density;
#ifdef TIME_MEASURE
	int tmIdx = 0;
	tm[tmIdx ++] = current_time_us();
#endif
	double areaSize = calc_density_map(frameData, densityMap);
	NSInteger nPoints = prms.density * areaSize;
	if (nPoints < prms.numPtMin) return nil;
	if (nPoints > prms.numPtMax) nPoints = prms.numPtMax;

#ifdef TIME_MEASURE
	tm[tmIdx ++] = current_time_us();
#endif
	Roulette *roulette = malloc(WIDTH * HEIGHT * sizeof(Roulette));
	float accp = 0.;
	NSInteger nIdx = 0;
	for (int i = 0; i < WIDTH * HEIGHT; i ++) if (densityMap[i] > 0.)
		roulette[nIdx ++] = (Roulette){accp += densityMap[i], i};

#ifdef TIME_MEASURE
	tm[tmIdx ++] = current_time_us();
#endif
	NSMutableData *dstData = [NSMutableData dataWithLength:nPoints * sizeof(PointInfo)];
	PointInfo *dst = dstData.mutableBytes;
	for (NSInteger i = 0; i < nPoints; i ++) {
		NSInteger idx = toss_roulette(roulette, nIdx);
		simd_float2 pScr = simd_float((simd_long2){ idx % WIDTH, idx / WIDTH }
				- (simd_long2){ WIDTH / 2, HEIGHT / 2 }) / (float)(WIDTH / 2),
			p = pScr * (float)frameData[idx] * .95;
		dst[i].p = (simd_float3){ p.x, -p.y, frameData[idx] };
		int colIdx = indexDepth2RGB((int)idx);
		dst[i].c.rgb = (colIdx < 0)? 0 : colorData[colIdx];
	}
#ifdef TIME_MEASURE
	tm[tmIdx ++] = current_time_us();
	for (int i = 0; i < N_TMS; i ++) tmAcc[i] += tm[i+1] - tm[i];
	if ((++ tmCnt) >= 60) {
		unsigned long total = 0;
		for (int i = 0; i < N_TMS; i ++) {
			total += tmAcc[i] /= tmCnt;
			printf("%ld,", tmAcc[i]);
		}
		printf("%ld\n", total);
		tmCnt = 0;
		memset(tmAcc, 0, sizeof(tmAcc));
	}
#endif
	free(roulette);
	return dstData;
}
@end
