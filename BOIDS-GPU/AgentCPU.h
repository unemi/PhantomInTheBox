//
//  AgentCPU.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

#import <Foundation/Foundation.h>
@import simd;

NS_ASSUME_NONNULL_BEGIN

#define N_DCELLSX 16
#define N_DCELLSY 9
#define N_DCELLSZ 12
#define N_CELLS_X (CellUnit*N_DCELLSX)
#define N_CELLS_Y (CellUnit*N_DCELLSY)
#define N_CELLS_Z (CellUnit*N_DCELLSZ)
#define N_CELLS (N_CELLS_X*N_CELLS_Y*N_CELLS_Z)
#define MAX_CELL_IDX (simd_int3){N_CELLS_X-1,N_CELLS_Y-1,N_CELLS_Z-1}

typedef struct { simd_float3 p, v; } Agent;
typedef struct { UInt32 start, n; } Cell;
typedef struct { UInt32 idx, nc, n, cIdxs[8]; } Task;
typedef struct {
	float avoid, cohide, align, attract, sightDist, sightAngle,
		mass, maxV, minV, fric;
} Params;
#define SIGHT_DIST_IDX 3
#define N_PARAMS (sizeof(Params)/sizeof(float))

extern NSLock *CellLock;
extern NSInteger PopSize, Step;
extern int CellUnit;
extern float CellSize;
extern simd_float3 WS;
extern Params PrmsUI, PrmsSim;
extern NSString *_Nonnull PrmLabels[];
extern NSInteger popBfIdx;
extern Agent *_Nonnull PopSim[2], *PopDraw;
extern Cell *Cells;
extern Task *TaskQueue, *TasQWork;
extern UInt32 *Idxs, *IdxsDraw;
extern NSInteger nCores;
extern dispatch_group_t DispatchGrp;
extern dispatch_queue_t DispatchQue;
extern unsigned long current_time_us(void);
extern void pop_reset(void);
extern BOOL check_cell_unit(NSInteger popSize);
extern BOOL pop_mem_init(NSInteger popSize);
extern void pop_init(void);
extern void set_sim_params(void);
extern UInt32 cell_index(simd_int3 idxV);
extern simd_int3 cell_index_v(UInt32 idx);
extern BOOL merge_sort(void *srcData, void *workData, NSInteger n,
	NSInteger eSz, int (^compare)(const void *, const void *));
extern void pop_step1(void);
extern BOOL pop_step2(void);

NS_ASSUME_NONNULL_END
