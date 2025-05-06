//
//  ShaderTyeps.metal
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/12/08.
//

#include <metal_stdlib>
using namespace metal;
typedef struct { float3 p, v; } Agent;
typedef struct { uint start, n; } Cell;
typedef struct { uint idx, nc, n, cIdxs[8]; } Task;
typedef struct {
	float avoid, cohide, align, attract,
		sightD, sightA,
		mass, maxV, minV, fric;
} Params;

typedef struct { uint start, n; } PtCell;

typedef struct {
	int3 cellDim;
	float cellSize, deltaTime;
	uint cellUnit, nPoints, maxNInCell;
} PointParams;

typedef union {
	float3 p;
	struct {
		float x, y, z;
		uchar r, g, b, a;	// little endian
	} c;
} PointInfo;
