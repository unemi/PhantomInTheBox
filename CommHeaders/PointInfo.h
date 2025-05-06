//
//  PointInfo.h
//  BOIDS-GPU & DepthCaptureRS
//
//  Created by Tatsuo Unemi on 2025/02/14.
//

@import simd;

//#define DEBUGx
#ifdef DEBUGx
#define MyComment(fmt,...) printf(fmt,##__VA_ARGS__)
#else
#define MyComment(fmt,...)
#endif
#define NPOINTS 5000
#define MAX_PKT_SIZE (16*1024)
#define COM_HELLO 0xffffffff
#define COM_END_OF_FRAME 0xfffffffe
#define PKT_HEAD_SZ (sizeof(PointInfoPacket)-sizeof(PointsInCell))
#define CEL_HEAD_SZ (sizeof(PointsInCell)-sizeof(simd_float3))

typedef union {
	simd_float3 p;
	struct { float p[3]; UInt32 rgb; } c;
} PointInfo;
typedef struct {
	UInt32 celIdx;	// cell's index
	UInt32 n;	// the number of points
	PointInfo pts[1];	// point positions
} PointsInCell;
typedef struct {
	UInt32 timestamp; // frame's timestamp
	UInt32 ID;	// spec ID
	UInt16 pktNum, nPics;
	PointsInCell pic[1];
} PointInfoPacket;

typedef struct {
	UInt32 ID;	// spec ID
	UInt16 x, y, z;		// cell division
	UInt16 np;			// number of points
	float cellSize;
} RequestFromSv;
