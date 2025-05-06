//
//  MetalView.m
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

#import "MetalView.h"
#import "AgentCPU.h"
#import "AgentGPU.h"
#import "AppDelegate.h"
#define LOG_STEPS 200
//#define MEASURE_TIME
#ifdef MEASURE_TIME
#import <sys/sysctl.h>
#define REC_TIME(v) unsigned long v = current_time_us();
#else
#define REC_TIME(v)
#endif

CGFloat FPS = 10.;
simd_float3 WallRGB = {0,0,0}, AgntRGB = {1,1,1}, FogRGB = {.5,.5,.5};
BOOL Colorful = YES;
ViewParams DfltViewPrms = {
	.depth = 0., .scale = 0., .contrast = 0.,
	.agentSize = 0., .agentOpacity = .5,
	.shadowOpacity = .75, .fogDensity = .5}, ViewPrms;
ShapeType shapeType = ShapePaperPlane;
NSString * _Nonnull ViewPrmLbls[] = {
	@"Depth", @"Scale", @"Contrast",
	@"AgentSize", @"AgentOpacity", @"ShadowOpacity", @"FogDensity" };
typedef id<MTLComputeCommandEncoder> CCE;
typedef id<MTLRenderCommandEncoder> RCE;

@implementation MetalView {
	IBOutlet NSMenu *menu;
	IBOutlet NSToolbarItem *playItem, *fullScrItem;
	IBOutlet NSTextField *fpsDgt;
	id<MTLComputePipelineState> shapePSO, squarePSO, pointsPSO;
	id<MTLRenderPipelineState> drawPSO, colorfulPSO, shadowPSO, blobPSO, ptDrawPSO;
	id<MTLBuffer> vxBuf, shadowBuf, idxBuf;
	NSInteger vxBufSize, idxBufSize;
	NSRect viewportRect;
	NSLock *drawLock;
	NSTimer *fpsTimer;
	NSToolbar *toolbar;
#ifdef MEASURE_TIME
	CGFloat TM1, TM2, TM3, TMI, TMG;
#endif
	unsigned long PrevTimeSim, PrevTimeDraw;
	NSTimeInterval refreshSec;
	BOOL running, shouldRestart, sightDistChanged;
#ifdef SAVE_IMAGES
	NSMutableArray<NSData *> *frames;
	NSConditionLock *frmQLock;
#endif
}
- (BOOL)isRunning { return running; }
- (void)switchFpsTimer:(BOOL)on {
	if (on) {
		if (fpsTimer == nil) fpsTimer =
			[NSTimer scheduledTimerWithTimeInterval:.2 repeats:YES block:
			^(NSTimer * _Nonnull timer) { self->fpsDgt.doubleValue = FPS; }];
	} else if (fpsTimer != nil) {
		[fpsTimer invalidate];
		fpsTimer = nil;
	}
}
- (void)getScreenRefreshTime {
	refreshSec = _view.window.screen.displayUpdateGranularity;
}
- (void)allocCellMem {
	if (check_cell_unit(PopSize))
		alloc_cell_mem(_view.device);
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
	[self switchFpsTimer:[change[NSKeyValueChangeNewKey] boolValue] && !_view.paused];
}
static id<MTLComputePipelineState> make_comp_func(id<MTLDevice> device,
	id<MTLLibrary> dfltLib, NSString *name) {
	NSError *error;
	id<MTLComputePipelineState> pso = [device newComputePipelineStateWithFunction:
		[dfltLib newFunctionWithName:name] error:&error];
	if (pso == nil) @throw error;
	return pso;
}
static id<MTLRenderPipelineState> make_render_func(id<MTLDevice> device,
	id<MTLLibrary> dfltLib, MTLRenderPipelineDescriptor *pplnStDesc,
	NSString *vxName, NSString *frName) {
	NSError *error;
	pplnStDesc.vertexFunction = [dfltLib newFunctionWithName:vxName];
	pplnStDesc.fragmentFunction = [dfltLib newFunctionWithName:frName];
	id<MTLRenderPipelineState> pso =
		[device newRenderPipelineStateWithDescriptor:pplnStDesc error:&error];
	if (pso == nil) @throw error;
	return pso;
}
#define MK_COMP_FN(name) make_comp_func(device, dfltLib, name)
#define MK_REND_FN(vx, fr) make_render_func(device, dfltLib, pplnStDesc, vx, fr)
- (void)awakeFromNib {
	memcpy(&ViewPrms, &DfltViewPrms, sizeof(ViewPrms));
	[(toolbar = _view.window.toolbar) addObserver:self forKeyPath:@"visible"
		options:NSKeyValueObservingOptionNew context:NULL];
	[self getScreenRefreshTime];
	@try {
		pop_init();
		load_defaults();
#ifdef SAVE_IMAGES
		_view.framebufferOnly = NO;
#endif
		id<MTLDevice> device = _view.device = setup_GPU(_view);
		NSUInteger smplCnt = 1;
		while ([device supportsTextureSampleCount:smplCnt << 1]) smplCnt <<= 1;
		_view.sampleCount = smplCnt;
		[self mtkView:_view drawableSizeWillChange:_view.drawableSize];
		_view.menu = menu;
		_view.delegate = self;
		id<MTLLibrary> dfltLib = device.newDefaultLibrary;
		shapePSO = MK_COMP_FN(@"makeShape");
		squarePSO = MK_COMP_FN(@"makeSquare");
		pointsPSO = MK_COMP_FN(@"makePointShape");
		MTLRenderPipelineDescriptor *pplnStDesc = MTLRenderPipelineDescriptor.new;
		pplnStDesc.label = @"Simple Pipeline";
		pplnStDesc.rasterSampleCount = _view.sampleCount;
		MTLRenderPipelineColorAttachmentDescriptor *colAttDesc = pplnStDesc.colorAttachments[0];
		colAttDesc.pixelFormat = _view.colorPixelFormat;
		colAttDesc.blendingEnabled = YES;
		colAttDesc.rgbBlendOperation = MTLBlendOperationAdd;
		colAttDesc.sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
		colAttDesc.destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
		drawPSO = MK_REND_FN(@"vertexShape", @"fragmentShape");
		colorfulPSO = MK_REND_FN(@"vertexColorful", @"fragmentColorful");
		shadowPSO = MK_REND_FN(@"vertexShadow", @"fragmentShadow");
		blobPSO = MK_REND_FN(@"vertexBlob", @"fragmentBlob");
		ptDrawPSO = MK_REND_FN(@"vertexPoint", @"fragmentPoint");
		drawLock = NSLock.new;
		alloc_pop_mem(_view.device);
		alloc_points_mem(_view.device);
		_view.paused = YES;
		_view.enableSetNeedsDisplay = YES;
	} @catch (NSObject *obj) { err_msg(obj, YES); }
}
- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
	viewportRect.origin = NSZeroPoint;
	viewportRect.size = size;
	CGSize cSz = {size.width * 9, size.height * 16};
	if (cSz.width > cSz.height) {
		CGFloat newWidth = viewportRect.size.width = cSz.height / 9.;
		viewportRect.origin.x = (size.width - newWidth) / 2.;
	} else if (cSz.width < cSz.height) {
		CGFloat newHeight = viewportRect.size.height = cSz.width / 16.;
		viewportRect.origin.y = (size.height - newHeight) / 2.;
	}
	view.needsDisplay = YES;
}
- (void)detachComputeThread {
	[NSThread detachNewThreadSelector:@selector(compute:) toTarget:self withObject:nil];
}
- (void)computeBOIDS:(unsigned long)now {
	if (NewPopSize != PopSize) alloc_pop_mem(_view.device);
	else if (sightDistChanged) [self allocCellMem];
	if (shouldRestart) pop_reset();
	shouldRestart = sightDistChanged = NO;
#ifdef SAVE_IMAGES
	float deltaTime = 1000./30.;
#else
	CGFloat interval = (now - PrevTimeSim) / 1e6;
	float deltaTime = fmin(interval, 1./20.) * 1000.;
#endif
	PrevTimeSim = now;
	Step ++;
#ifdef MEASURE_TIME
	TMI += (deltaTime - TMI) * 0.05;
	if (Step == 1) {
		static char name[128] = {0};
		if (name[0] == '\0') {
			size_t len = sizeof(name);
			sysctlbyname("hw.model", name, &len, NULL, 0);
		}
		printf("\"%s\",\"%s\",\"%s\",%ld,%ld,%d\n", name,
			NSProcessInfo.processInfo.operatingSystemVersionString.UTF8String,
			_view.device.name.UTF8String, nCores, PopSize, N_CELLS);
	} else if (Step % LOG_STEPS == 0)
		printf("%ld,%.3f,%.3f,%.3f,%.3f,%.3f\n",
			Step, TM1, TM2, TM3, TMG, TMI);
#endif
	REC_TIME(tm1)
	pop_step1();
	REC_TIME(tm2)
	[theTracker lock];
	if (pop_step2()) {
		taskBfIdx = 1 - taskBfIdx;
		TaskQueue = taskBf[taskBfIdx].contents;
		TasQWork = taskBf[1 - taskBfIdx].contents;
	}
	REC_TIME(tm3)
	pop_step3(deltaTime);
	popBfIdx = 1 - popBfIdx;
	[theTracker unlock];
	[drawLock lock];
	memcpy(PopDraw, PopSim[popBfIdx], sizeof(Agent) * PopSize);
	memcpy(IdxsDraw, Idxs, sizeof(UInt32) * PopSize);
	memcpy(colDrawBuf.contents, colBuf.contents, sizeof(simd_float4) * PopSize);
	[drawLock unlock];
	in_main_thread( ^{ self.view.needsDisplay = YES; });
#ifdef MEASURE_TIME
	unsigned long tmE = current_time_us();
	TM1 += ((tm2 - tm1) / 1000. - TM1) * 0.05;
	TM2 += ((tm3 - tm2) / 1000. - TM2) * 0.05;
	TM3 += ((tmE - tm3) / 1000. - TM3) * 0.05;
#endif
}
- (void)compute:(id)dummy {
	NSThread.currentThread.name = @"compute";
	while (running) {
		unsigned long now = current_time_us();
		if (shapeType != ShapePoints)
			[self computeBOIDS:now];
		unsigned long tmE = current_time_us();
//#define REC_COMPTIME
#ifdef REC_COMPTIME
#define N_TRIALS 20
#define STEP_FROM 600
#define STEP_TO 800
static NSInteger pszCnt = 0, trlCnt = 0, svrCnt = 0;
static CGFloat sumTM = 0.;
static FILE *fd;
if (Step == 1) {
	float sd = (svrCnt - 2) * .5;
	NSInteger psz = (pszCnt + 1) * 100000;
	in_main_thread(^{
		NSMutableDictionary *dict = NSMutableDictionary.new;
		if (PrmsUI.sightDist != sd) dict[@"Sight Distance"] = @(sd);
		if (psz != PopSize) dict[@"PopSize"] = @(psz);
		if (dict.count > 0)
			[((AppDelegate *)NSApp.delegate).pnlCntl setValuesFromDict:dict];
	});
} else if (Step > STEP_FROM) {
	sumTM += tmE - now;
	if (Step == STEP_TO) {
		if ((++ trlCnt) >= N_TRIALS) {
			if (pszCnt == 0) {
				char fname[64];
				sprintf(fname, "CompTM_%d.dat", (int)(PrmsSim.sightDist * 1000));
				fd = fopen(fname, "w");
			}
			fprintf(fd, "%ld %.4f C=%d,Wx=%.4f,Cx=%.4f,Rs=%.6f\n",
				PopSize/100000, sumTM / 1000. / (STEP_TO - STEP_FROM) / N_TRIALS,
				CellUnit, WS.x, WS.x/N_CELLS_X, PrmsSim.sightDist);
			fflush(fd);
			trlCnt = 0;
			sumTM = 0.;
			if ((++ pszCnt) >= 10) {
				fclose(fd); pszCnt = 0;
				svrCnt ++;
			}
		}
		in_main_thread(^{
			if (svrCnt < 5) [self restart:nil];
			else [self playPause:nil];
		});
	}
}
#endif
		long timeLeft = refreshSec * .95e6 - (tmE - now);
		if (timeLeft > 100) usleep((unsigned int)timeLeft);
		else usleep(100);
	}
}
static simd_float3 rgb2hsb0(simd_float3 rgb, float sum) {
	float minc = simd_reduce_min(rgb), maxc = simd_reduce_max(rgb);
	simd_float3 hsb = {0., maxc - minc, sum / 3.};
	simd_float3 p = rgb - minc;
	if (p.b == 0.) hsb.x = p.g / (p.r + p.g) / 3.;
	else if (p.r == 0.) hsb.x = (p.b / (p.g + p.b) + 1.) / 3.;
	else hsb.x = (p.r / (p.b + p.r) + 2.) / 3.;
	return hsb;
}
static simd_float3 rgb2hsb(simd_float3 rgb) {
	float sum = simd_reduce_add(rgb);
	simd_float3 hsb = 0.;
	if (sum == 0.) hsb = (simd_float3){0.,0.,0.};	// black
	else if (sum == 3.) hsb = (simd_float3){1.,1.,1.}; // white
	else if (sum < 1.) hsb = rgb2hsb0(rgb, sum);
	else if (sum > 2.) hsb = 1. - rgb2hsb0(1. - rgb, 3. - sum);
	else {
		simd_float3 c1 = rgb2hsb0(rgb / sum, 1.),
			c2 = 1. - rgb2hsb0((1. - rgb) / (3. - sum), 1.);
		hsb = c1 * (2. - sum) + c2 * (sum - 1.);
	}
	return hsb;
}
- (void)drawScene:(MTKView *)view commandBuffer:(id<MTLCommandBuffer>)cmdBuf {
	MTLRenderPassDescriptor *rndrPasDesc = view.currentRenderPassDescriptor;
	if(rndrPasDesc == nil) return;
	RCE rce = [cmdBuf renderCommandEncoderWithDescriptor:rndrPasDesc];
	rce.label = @"MyRenderEncoder";
	[rce setViewport:(MTLViewport){viewportRect.origin.x, viewportRect.origin.y,
		viewportRect.size.width, viewportRect.size.height, 0., 1. }];
	static UInt16 cornersIdx[5][4] = // Floor, Left, Right, Cieling, and Back
		{{0, 1, 4, 5}, {0, 2, 4, 6}, {1, 3, 5, 7}, {2, 3, 6, 7}, {4, 5, 6, 7}};
	static float surfaceDim[5] = {0., .5, .5, 1., .75};
	simd_float2 camP = {WS.z * pow(10., ViewPrms.depth), pow(10., ViewPrms.scale)};
	[rce setRenderPipelineState:drawPSO];
	NSInteger idx = 0;
	[rce setVertexBytes:&WS length:sizeof(WS) atIndex:idx ++];
	[rce setVertexBytes:&camP length:sizeof(camP) atIndex:idx ++];
	for (NSInteger i = 0; i < 5; i ++) {
		simd_float3 corners[4];
		simd_float4 col[2] = {{0,0,0,1},{.5,.5,.5,1.}};
		for (NSInteger j = 0; j < 4; j ++) {
			UInt16 k = cornersIdx[i][j];
			corners[j] = WS * (simd_float3){k % 2, (k / 2) % 2, k / 4};
		}
		col[0].rgb = WallRGB * .5 + ((ViewPrms.contrast > 0.)?
			surfaceDim[i] * ViewPrms.contrast :
			(1. - surfaceDim[i]) * - ViewPrms.contrast) * (1. - WallRGB * .5);
		col[1] = simd_make_float4(FogRGB, ViewPrms.fogDensity);
		[rce setVertexBytes:corners length:sizeof(corners) atIndex:idx];
		[rce setFragmentBytes:col length:sizeof(col) atIndex:0];
		[rce drawPrimitives:MTLPrimitiveTypeTriangleStrip
			vertexStart:0 vertexCount:4];
	}
	if (ViewPrms.shadowOpacity > 0.) {
		float opacity = ViewPrms.agentOpacity * ViewPrms.shadowOpacity;
		[rce setFragmentBytes:&opacity length:sizeof(opacity) atIndex:0];
		[rce setRenderPipelineState:shadowPSO];
		switch (shapeType) {
			case ShapePaperPlane:
			[rce setVertexBuffer:shadowBuf offset:0 atIndex:idx];
			[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
				vertexCount:vxBufSize / 2];
			break;
			case ShapeBlob: break;
			case ShapePoints:
			[rce setVertexBuffer:vxBuf offset:0 atIndex:idx];
			[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
				vertexCount:nPoints * 3];
		}}
	if (shapeType != ShapePoints || nPoints > 0) {
		[rce setVertexBuffer:vxBuf offset:0 atIndex:idx];
		simd_float4 col[2] = {
			simd_make_float4(AgntRGB, ViewPrms.agentOpacity),
			simd_make_float4(FogRGB, ViewPrms.fogDensity) };
		[rce setFragmentBytes:col length:sizeof(col) atIndex:0];
		switch (shapeType) {
			case ShapePaperPlane: if (Colorful) {
				[rce setRenderPipelineState:colorfulPSO];
				[rce setVertexBuffer:popDrawBuf offset:0 atIndex:idx + 1];
				[rce setVertexBuffer:idxsDrawBuf offset:0 atIndex:idx + 2];
				[rce setVertexBytes:&PopSize length:sizeof(NSInteger) atIndex:idx + 3];
				col[0].rgb = rgb2hsb(col[0].rgb);
				[rce setFragmentBytes:col length:sizeof(col) atIndex:0];
				[rce setFragmentBuffer:colDrawBuf offset:0 atIndex:1];
			} else [rce setRenderPipelineState:drawPSO];
			[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
				vertexCount:vxBufSize];
			break;
			case ShapeBlob:
			[rce setRenderPipelineState:blobPSO];
			simd_float2 scrSize = {viewportRect.size.width, viewportRect.size.height};
			[rce setFragmentBytes:&scrSize length:sizeof(scrSize) atIndex:1];
			[rce drawIndexedPrimitives:MTLPrimitiveTypeTriangleStrip
				indexCount:idxBufSize indexType:MTLIndexTypeUInt32
				indexBuffer:idxBuf indexBufferOffset:0];
			break;
			case ShapePoints:
			[rce setRenderPipelineState:ptDrawPSO];
			[rce setVertexBuffer:pointsBuf[ptBfIdx] offset:0 atIndex:idx + 1];
			[rce setFragmentBytes:&col[1] length:sizeof(simd_float4) atIndex:0];
			[rce drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0
				vertexCount:nPoints * 3];
		}
	}
	[rce endEncoding];
}
#ifdef SAVE_IMAGES
- (void)frameOut:(id)dummy {
	FILE *frmOut = fopen("frames", "w");
	if (frmOut == NULL) {
		unix_error_msg(@"Could not open frames file.", YES);
		return;
	}
	NSBeep();
	for (;;) {
		[frmQLock lockWhenCondition:1];
		NSMutableArray<NSData *> *que = frames;
		frames = NSMutableArray.new;
		[frmQLock unlockWithCondition:0];
		if (que.count == 0) break;
		for (NSData *data in que)
			fwrite(data.bytes, 1, data.length, frmOut);
	}
	fclose(frmOut);
	NSBeep();
}
- (void)saveImage:(MTKView *)view {
	if (Step < FRMCNT_START || Step >= FRMCNT_END) return;
#ifdef MAKE_CSV
	extern void write_vecfld_CSV(void);
	if (Step % 30 == 0) write_vecfld_CSV();
#endif
	if (Step % 30 == 0) {
		NSInteger sec = (Step - FRMCNT_START) / 30;
		printf("%ld:%ld\n", sec / 60, sec % 60);
	}
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	id<MTLTexture> tex = view.currentDrawable.texture;
	NSAssert(tex, @"Failed to get texture from MTKView.");
	NSUInteger texW = tex.width, texH = tex.height;
	id<MTLBuffer> buf = [tex.device newBufferWithLength:texW * texH * 4
		options:MTLResourceStorageModeShared];
	NSAssert(buf, @"Failed to create buffer for %ld bytes.", texW * texH * 4);
	id<MTLBlitCommandEncoder> blitEnc = cmdBuf.blitCommandEncoder;
	[blitEnc copyFromTexture:tex sourceSlice:0 sourceLevel:0
		sourceOrigin:(MTLOrigin){0, 0, 0} sourceSize:(MTLSize){texW, texH, 1}
		toBuffer:buf destinationOffset:0
		destinationBytesPerRow:texW * 4 destinationBytesPerImage:texW * texH * 4];
	[blitEnc endEncoding];
	[cmdBuf commit];
	if (frames == nil) {
		frames = NSMutableArray.new;
		frmQLock = NSConditionLock.new;
		[NSThread detachNewThreadSelector:@selector(frameOut:) toTarget:self withObject:nil];
	}
	[cmdBuf waitUntilCompleted];
	[frmQLock lock];
	[frames addObject:[NSData dataWithBytes:buf.contents length:texW * texH * 4]];
	[frmQLock unlockWithCondition:1];
	if (Step == FRMCNT_END) [NSThread detachNewThreadWithBlock:^{
		[self->frmQLock lockWhenCondition:0];
		[self->frmQLock unlockWithCondition:1];
	}];
}
#endif
- (void)drawInMTKView:(MTKView *)view {
	id<MTLCommandBuffer> cmdBuf = commandQueue.commandBuffer;
	CCE cce = cmdBuf.computeCommandEncoder;
	NSArray<id<MTLComputePipelineState>> *psos = @[shapePSO, squarePSO, pointsPSO];
	NSArray<id<MTLBuffer>> *pToDraw = @[popDrawBuf, popDrawBuf, pointsBuf[ptBfIdx]];
	NSInteger vxSzs[] = {6, 4, 3}, idxSzs[] = {0, 5, 0}, pSize[] = {PopSize, PopSize, NPOINTS};
	NSInteger vxSz = pSize[shapeType] * vxSzs[shapeType],
		idxSz = pSize[shapeType] * idxSzs[shapeType];
	if (vxBufSize != vxSz) {
		vxBuf = [view.device newBufferWithLength:sizeof(simd_float3) * vxSz
			options:MTLResourceStorageModePrivate];
		shadowBuf = (shapeType != ShapePaperPlane || ViewPrms.shadowOpacity == 0.)? nil :
			[view.device newBufferWithLength:sizeof(simd_float3) * 3 * PopSize
				options:MTLResourceStorageModePrivate];
		vxBufSize = vxSz;
	}
	if (shapeType == ShapePaperPlane && ViewPrms.shadowOpacity > 0. && shadowBuf == nil)
		shadowBuf = [view.device newBufferWithLength:sizeof(simd_float3) * 3 * PopSize
			options:MTLResourceStorageModePrivate];
	if (idxBufSize != idxSz) {
		if (idxSz == 0) idxBuf = nil;
		else idxBuf = [view.device newBufferWithLength:sizeof(UInt32) * idxSz
			options:MTLResourceStorageModeShared];
		idxBufSize = idxSz;
		if (shapeType == ShapeBlob) {
			UInt32 *idxP = idxBuf.contents;
			for (UInt32 i = 0; i < PopSize; i ++) {
				for (UInt32 j = 0; j < 4; j ++) idxP[i * 5 + j] = i * 4 + j;
				idxP[i * 5 + 4] = (UInt32)(-1);
	}}}
	if (running) [drawLock lock];
	[cce setComputePipelineState:psos[shapeType]];
	NSInteger idx = 0;
	REC_TIME(tm1);
	float agntSz = pow(5., ViewPrms.agentSize);
	[cce setBuffer:pToDraw[shapeType] offset:0 atIndex:idx ++];
	[cce setBytes:&agntSz length:sizeof(agntSz) atIndex:idx ++];
	[cce setBuffer:vxBuf offset:0 atIndex:idx ++];
	if (shapeType == ShapePaperPlane) [cce setBuffer:shadowBuf offset:0 atIndex:idx ++];
	NSUInteger threadGrpSz = shapePSO.maxTotalThreadsPerThreadgroup;
	if (threadGrpSz > PopSize) threadGrpSz = PopSize;
	[cce dispatchThreads:MTLSizeMake(PopSize, 1, 1)
		threadsPerThreadgroup:MTLSizeMake(threadGrpSz, 1, 1)];
	[cce endEncoding];
	REC_TIME(tm2);
	REC_TIME(tm3);
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];

	cmdBuf = commandQueue.commandBuffer;
	[self drawScene:view commandBuffer:cmdBuf];
	[cmdBuf presentDrawable:view.currentDrawable];
	[cmdBuf commit];
	[cmdBuf waitUntilCompleted];
#ifdef SAVE_IMAGES
	[self saveImage:view];
#endif
	if (running) [drawLock unlock];
	unsigned long tm = current_time_us();
#ifdef MEASURE_TIME
	TMG += ((tm - tm3 + tm2 - tm1) / 1000. - TMG) * 0.05;
#endif
	FPS += (1e6 / (tm - PrevTimeDraw) - FPS) * fmax(0.005, 1. / (Step + 1));
	PrevTimeDraw = tm;
}
- (void)revisePopSize:(NSInteger)newSize {
	NewPopSize = newSize;
	if (!running) {
		alloc_pop_mem(_view.device);
		_view.needsDisplay = YES;
	}
}
- (void)reviseSightDistance {
	if (running) sightDistChanged = YES;
	else [self allocCellMem];
}
- (IBAction)fullScreen:(_Nullable id)sender {
	if (_view.inFullScreenMode) {
		[_view exitFullScreenModeWithOptions:nil];
		fullScrItem.image = [NSImage imageNamed:NSImageNameEnterFullScreenTemplate];
	} else {
		NSScreen *screen = NSScreen.screens.lastObject;
		if (FullScreenName != nil) for (NSScreen *scr in NSScreen.screens)
			if ([scr.localizedName isEqualToString:FullScreenName])
				{ screen = scr; break; }
		fullScrItem.image = [NSImage imageNamed:NSImageNameExitFullScreenTemplate];
		[_view enterFullScreenMode:screen withOptions:
			@{NSFullScreenModeAllScreens:@NO}];
	}
	[self getScreenRefreshTime];
}
- (IBAction)playPause:(_Nullable id)sender {
	if ((running = !running)) {
		playItem.image = [NSImage imageNamed:NSImageNameTouchBarPauseTemplate];
		playItem.label = @"Pause";
		if (toolbar.visible) [self switchFpsTimer:YES];
		[self detachComputeThread];
	} else {
		playItem.image = [NSImage imageNamed:NSImageNameTouchBarPlayTemplate];
		playItem.label = @"Play";
		[self switchFpsTimer:NO];
	}
}
- (IBAction)restart:(id)sender {
	if (running) shouldRestart = YES;
	else {
		pop_reset();
		_view.needsDisplay = YES;
	}
}
- (IBAction)resetCamera:(id)sender {
	if (((AppDelegate *)NSApp.delegate).pnlCntl != nil)
		[((AppDelegate *)NSApp.delegate).pnlCntl resetCamera];
	else ViewPrms.depth = ViewPrms.scale = 0.;
	_view.needsDisplay = YES;
}
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if (menuItem.action == @selector(playPause:)) {
		menuItem.title = _view.paused? @"Play" : @"Pause";
	} else if (menuItem.action == @selector(fullScreen:)) {
		menuItem.title = _view.inFullScreenMode? @"Exit Full Screen" : @"Enter Full Screen";
	} else if (menuItem.action == @selector(resetCamera:)) {
		return ViewPrms.depth != 0. || ViewPrms.scale != 0.;
	}
	return YES;
}
- (void)windowDidResize:(NSNotification *)notification {
// for recovery from the side effect of toolbar.
	static BOOL launched = NO;
	if (!launched) {
		launched = YES;
		NSRect frame = _view.window.frame;
		NSSize vSize = _view.frame.size;
		frame.size.width += 1280 - vSize.width;
		frame.size.height += 720 - vSize.height;
		[_view.window setFrame:frame display:NO];
	}
}
- (void)windowWillClose:(NSNotification *)notification {
	[NSApp terminate:nil];
}
- (void)windowDidChangeScreenProfile:(NSNotification *)notification {
	[self getScreenRefreshTime];
}
- (void)escKeyDown {
	if (_view.inFullScreenMode) [self fullScreen:nil];
}
@end

@implementation MyMTKView
- (void)scrollWheel:(NSEvent *)event {
	CGFloat delta = (event.modifierFlags & NSEventModifierFlagShift)?
		event.deltaX * .05 : event.deltaY * .005;
	if (event.modifierFlags & NSEventModifierFlagCommand) {
		ViewPrms.depth =  fmax(-1., fmin(1., ViewPrms.depth + delta));
		[((AppDelegate *)NSApp.delegate).pnlCntl camDepthModified];
	} else {
		ViewPrms.scale = fmax(-1., fmin(1., ViewPrms.scale - delta));
		[((AppDelegate *)NSApp.delegate).pnlCntl camScaleModified];
	}
	self.needsDisplay = YES;
}
- (void)keyDown:(NSEvent *)event {
	if (event.keyCode == 53) [(MetalView *)self.delegate escKeyDown];
}
@end
