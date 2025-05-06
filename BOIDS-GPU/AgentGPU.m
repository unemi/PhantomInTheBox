//
//  AgentGPU.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

#import "AgentGPU.h"
#import "AgentCPU.h"
#import "AppDelegate.h"
#import "CommPanel.h"
#import "../CommHeaders/PointInfo.h"

static id<MTLComputePipelineState> movePSO;
id<MTLCommandQueue> commandQueue;
id<MTLBuffer> popDrawBuf, cellBuf, idxsBuf, idxsDrawBuf;
id<MTLBuffer> popSimBuf[2], taskBf[2], pointsBuf[2], ptCellBuf[2];	// for double buffering
id<MTLBuffer> colBuf, colDrawBuf;
NSInteger taskBfIdx, NewPopSize;

typedef struct { simd_short3 i; float d; } NearCellIdxs;
static NearCellIdxs *nearCellIdxs = NULL;
static id<MTLBuffer> ffCellBuf;
static SInt16 *ffCells, *tgtCells, *prcCells;

#define NEW_BUF(s) [device newBufferWithLength:s options:MTLResourceStorageModeShared]
void alloc_pop_mem(id<MTLDevice> device) {
	for (NSInteger i = 0; i < 2; i ++) {
		taskBf[i] = NEW_BUF(sizeof(Task) * NewPopSize);
		popSimBuf[i] = NEW_BUF(sizeof(Agent) * NewPopSize);
		PopSim[i] = popSimBuf[i].contents;
	}
	popDrawBuf = NEW_BUF(sizeof(Agent) * NewPopSize);
	idxsBuf = NEW_BUF(sizeof(UInt32) * NewPopSize);
	idxsDrawBuf = NEW_BUF(sizeof(UInt32) * NewPopSize);
	colBuf = NEW_BUF(sizeof(simd_float4) * NewPopSize);
	colDrawBuf = NEW_BUF(sizeof(simd_float4) * NewPopSize);
	TaskQueue = taskBf[0].contents;
	TasQWork = taskBf[1].contents;
	PopDraw = popDrawBuf.contents;
	Idxs = idxsBuf.contents;
	IdxsDraw = idxsDrawBuf.contents;
	if (pop_mem_init(NewPopSize))
		alloc_cell_mem(device);
	PopSize = NewPopSize;
	pop_reset();
}
void alloc_cell_mem(id<MTLDevice> device) {
	cellBuf = NEW_BUF(sizeof(Cell) * N_CELLS);
	for (NSInteger i = 0; i < 2; i ++)
		ptCellBuf[i] = NEW_BUF(sizeof(PtCell) * N_CELLS);
	if (ptCellBuf[1] == nil) err_msg(@"Couldn't allocate Metal buffer.", YES);
	Cells = cellBuf.contents;
	PtCells = ptCellBuf[0].contents;
	PtCelWk = ptCellBuf[1].contents;
	memset(PtCells, 0, sizeof(PtCell) * N_CELLS);
}
#define N_PT_CELLS (N_DCELLSX * N_DCELLSY * N_DCELLSZ)
void alloc_points_mem(id<MTLDevice> device) {
	for (NSInteger i = 0; i < 2; i ++)
		pointsBuf[i] = NEW_BUF(sizeof(simd_float3) * NPOINTS);
	ffCellBuf = NEW_BUF(sizeof(SInt16) * N_PT_CELLS);
	Points = pointsBuf[0].contents;
	PointsWk = pointsBuf[1].contents;
	ffCells = ffCellBuf.contents;
	NSInteger ncSz = (N_DCELLSX * 2 - 1) * (N_DCELLSY * 2 - 1) * (N_DCELLSZ * 2 - 1);
	nearCellIdxs = malloc(sizeof(NearCellIdxs) * ncSz);
	simd_short3 xyz;
	NSInteger i = 0;
	for (xyz.z = 1-N_DCELLSZ; xyz.z < N_DCELLSZ; xyz.z ++)
	for (xyz.y = 1-N_DCELLSY; xyz.y < N_DCELLSY; xyz.y ++)
	for (xyz.x = 1-N_DCELLSX; xyz.x < N_DCELLSX; xyz.x ++, i ++) {
		nearCellIdxs[i].i = xyz;
		nearCellIdxs[i].d = simd_length(simd_float(xyz)) + drand48() * 1e-8;
	}
	for (NSInteger i = 0; i < ncSz - 1; i ++) {
		NSInteger j = (lrand48() % (ncSz - i)) + i;
		if (j != i) {
			NearCellIdxs tmp = nearCellIdxs[i];
			nearCellIdxs[i] = nearCellIdxs[j];
			nearCellIdxs[j] = tmp;
		}
	}
	qsort_b(nearCellIdxs, ncSz, sizeof(NearCellIdxs),
		^(const void *a, const void *b) {
			float c = ((NearCellIdxs *)a)->d, d = ((NearCellIdxs *)b)->d;
			return (c < d)? -1 : (c > d)? 1 : 0;
		});
	tgtCells = malloc(sizeof(SInt16) * N_PT_CELLS * 2);
	prcCells = tgtCells + N_PT_CELLS;
}
id<MTLDevice> setup_GPU(MTKView *view) {
	NSArray<id<MTLDevice>> *devs = MTLCopyAllDevices();
	if (devs == nil || devs.count == 0)
		err_msg(@"No GPU found.", YES);
	id<MTLDevice> device = view? view.preferredDevice : devs[0];
	@try {
		NSError *error;
		id<MTLLibrary> dfltLib = device.newDefaultLibrary;
		movePSO = [device newComputePipelineStateWithFunction:
			[dfltLib newFunctionWithName:@"moveAgent"] error:&error];
		if (movePSO == nil) @throw error;
		commandQueue = device.newCommandQueue;
	} @catch (NSObject *obj) { err_msg(obj, YES); }
	return device;
}
static inline int ptCell_index(simd_short3 vIdx) {
	return (vIdx.z * N_DCELLSY + vIdx.y) * N_DCELLSX + vIdx.x;
}
static inline simd_short3 ptCell_index_v(UInt32 sIdx) {
	return (simd_short3){sIdx % N_DCELLSX,
		(sIdx / N_DCELLSX) % N_DCELLSY,
		sIdx / (N_DCELLSY * N_DCELLSX) };
}
static void organize_near_pt_map(void) {
	memset(ffCells, -1, sizeof(SInt16) * N_PT_CELLS);
	SInt32 ncSz = (N_DCELLSX * 2 - 1) * (N_DCELLSY * 2 - 1) * (N_DCELLSZ * 2 - 1);
	simd_short3 maxIdx = {N_DCELLSX - 1, N_DCELLSY - 1, N_DCELLSZ - 1};
	SInt32 nTgt = 0, nPrc;
	for (UInt32 i = 0; i < N_PT_CELLS; i ++) {
		simd_short3 iV = ptCell_index_v(i) * CellUnit, xyz;
		BOOL cont = YES;
		for (xyz.z = 0; xyz.z < CellUnit && cont; xyz.z ++)
		for (xyz.y = 0; xyz.y < CellUnit && cont; xyz.y ++)
		for (xyz.x = 0; xyz.x < CellUnit; xyz.x ++) {
			simd_short3 vv = iV + xyz;
			UInt32 k = cell_index((simd_int3){vv.x, vv.y, vv.z});
			if (PtCells[k].n > 0) { ffCells[i] = i; cont = NO; break; }
		}
		if (cont) tgtCells[nTgt ++] = i;
	}
	for (SInt32 i = 0; i < ncSz && nTgt > 0; i ++) {
		simd_short3 dIdx = nearCellIdxs[i].i;
		nPrc = 0;
		for (SInt32 j = 0; j < nTgt; j ++) {
			SInt32 tgtIdx = tgtCells[j];
			simd_short3 v = ptCell_index_v(tgtIdx) + dIdx;
			if (simd_any(v < 0) || simd_any(v > maxIdx)) continue;
			SInt32 srcIdx = ptCell_index(v);
			if (ffCells[srcIdx] < 0) continue;
			ffCells[tgtIdx] = ffCells[srcIdx];
			prcCells[nPrc ++] = tgtIdx;
		}
		if (nPrc > 0) for (NSInteger j = 0, tx = 0, px = 0; j < nTgt; j ++) {
			if (px >= nPrc || tgtCells[j] != prcCells[px])
				tgtCells[tx ++] = tgtCells[j];
			else px ++;
		}
		nTgt -= nPrc;
	}
}
void pop_step3(float deltaTime) {	// millisecond
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	cmdBuf.label = @"MyCommand";
	id<MTLComputeCommandEncoder> cce = cmdBuf.computeCommandEncoder;
	if (theTracker != nil && theTracker.lastStepOfFrame > 0
		&& Step - theTracker.lastStepOfFrame > 30) {
		theTracker.lastStepOfFrame = nPoints = 0;
		memset(PtCells, 0, sizeof(PtCell) * N_CELLS);
	}
	struct {
		simd_int3 cellDim;
		float cellSize, deltaTime;
		UInt32 cellUnit, nPoints, maxNInCell;
	} ptParams = {
		.cellDim = {N_DCELLSX, N_DCELLSY, N_DCELLSZ},
		.cellSize = CellSize,
		.deltaTime = deltaTime,
		.cellUnit = CellUnit,
		.nPoints = (UInt32)(nPoints),
		.maxNInCell = (UInt32)(PopSize * 20 / N_CELLS)
	};
	if (nPoints > 0) organize_near_pt_map();
	memset(colBuf.contents, 0, sizeof(simd_float4) * PopSize);
	[cce setComputePipelineState:movePSO];
	NSInteger idx = 0;
	[cce setBuffer:popSimBuf[popBfIdx] offset:0 atIndex:idx ++];
	[cce setBuffer:popSimBuf[1 - popBfIdx] offset:0 atIndex:idx ++];
	[cce setBuffer:colBuf offset:0 atIndex:idx ++];
	[cce setBuffer:cellBuf offset:0 atIndex:idx ++];
	[cce setBuffer:idxsBuf offset:0 atIndex:idx ++];
	[cce setBuffer:taskBf[taskBfIdx] offset:0 atIndex:idx ++];
	[cce setBuffer:pointsBuf[ptBfIdx] offset:0 atIndex:idx ++];
	[cce setBuffer:ptCellBuf[ptBfIdx] offset:0 atIndex:idx ++];
	[cce setBuffer:ffCellBuf offset:0 atIndex:idx ++];
	[cce setBytes:&ptParams length:sizeof(ptParams) atIndex:idx ++];
	[cce setBytes:&PrmsSim length:sizeof(Params) atIndex:idx ++];
	NSUInteger threadGrpSz = movePSO.maxTotalThreadsPerThreadgroup;
	if (threadGrpSz > PopSize) threadGrpSz = PopSize;
	[cce dispatchThreads:MTLSizeMake(PopSize, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
	[cce endEncoding];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
}
