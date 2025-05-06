//
//  AgentGPU.h
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/21.
//

@import MetalKit;

NS_ASSUME_NONNULL_BEGIN

extern id<MTLCommandQueue> commandQueue;
extern id<MTLBuffer> popDrawBuf, cellBuf, idxsBuf, idxsDrawBuf;
extern id<MTLBuffer> _Nonnull popSimBuf[2], taskBf[2], pointsBuf[2], ptCellBuf[2];
extern id<MTLBuffer> colBuf, colDrawBuf;
extern NSInteger taskBfIdx, NewPopSize;

extern void alloc_pop_mem(id<MTLDevice> device);
extern void alloc_cell_mem(id<MTLDevice> device);
extern void alloc_points_mem(id<MTLDevice> device);
extern id<MTLDevice> setup_GPU(MTKView *view);
extern void pop_step3(float deltaTime);

NS_ASSUME_NONNULL_END
