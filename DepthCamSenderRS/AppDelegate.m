//
//  AppDelegate.m
//  DepthCaptureRS
//
//  Created by Tatsuo Unemi on 2025/02/08.
//

#import "AppDelegate.h"
#import "MyRealSense.h"
#import "UDPSender.h"
#import "CalcPoints.h"
#import <sys/time.h>
#import <sys/sysctl.h>

static Parameters defaultParams = {
	.monitorType = MonitorNone,
	.senderOn = NO,
	.IPV4Address = "127.0.0.1",
	.portNumber = 9003,
	.maxDepth = 1000,
	.numPtMax = NPOINTS, .numPtMin = 100,
	.density = 2.5,
	.mirrorOn = NO,
	.geom = {0., 0., 0., 0.}	// xyz offset & exp of scale
};
Parameters params;

static NSString *keyMonitorType = @"monitorType",
	*keySenderOn = @"senderOn", *keyMirrorOn = @"mirrorOn",
	*keyIPv4Address = @"IPv4Address", *keyPortNumber = @"portNumber",
	*keyMaxDepth = @"maxDepth", *keyRGBOffset = @"RGBOffset",
	*keyDensity = @"density", *keyGeometry = @"geometry",
	*keyNumPtMax = @"numberOfPointsMax", *keyNumPtMin = @"numberOfPointsMin";

dispatch_group_t DispatchGrp;
dispatch_queue_t DispatchQue;
NSInteger nCores;

static NSDictionary *dict_from_params(Parameters *prm) {
	return @{keyMonitorType:@(prm->monitorType),
		keySenderOn:@(prm->senderOn), keyMirrorOn:@(prm->mirrorOn),
		keyIPv4Address:[NSString stringWithUTF8String:prm->IPV4Address],
		keyPortNumber:@(prm->portNumber), keyMaxDepth:@(prm->maxDepth),
		keyRGBOffset:@(prm->rgbOffset), keyDensity:@(prm->density),
		keyNumPtMax:@(prm->numPtMax), keyNumPtMin:@(prm->numPtMin),
		keyGeometry:@[@(prm->geom.x), @(prm->geom.y), @(prm->geom.z), @(prm->geom.w)]};
}
static void dict_to_params(Parameters *prm, NSDictionary *dict) {
	NSNumber *num;
	if ((num = dict[keyMonitorType])) prm->monitorType = num.intValue;
	if ((num = dict[keySenderOn])) prm->senderOn = num.boolValue;
	if ((num = dict[keyPortNumber])) prm->portNumber = num.intValue;
	if ((num = dict[keyMaxDepth])) prm->maxDepth = num.integerValue;
	if ((num = dict[keyRGBOffset])) prm->rgbOffset = num.doubleValue;
	NSString *str;
	if ((str = dict[keyIPv4Address]))
		memcpy(prm->IPV4Address, str.UTF8String, str.length + 1);
	if ((num = dict[keyNumPtMax])) prm->numPtMax = num.integerValue;
	if ((num = dict[keyNumPtMin])) prm->numPtMin = num.integerValue;
	if ((num = dict[keyDensity])) prm->density = num.doubleValue;
	if ((num = dict[keyMirrorOn])) prm->mirrorOn = num.boolValue;
	NSArray<NSNumber *> *arr;
	if ((arr = dict[keyGeometry]) && arr.count >= 4) prm->geom =
		(simd_float4){arr[0].floatValue, arr[1].floatValue, arr[2].floatValue, arr[3].floatValue};
}
unsigned long current_time_us(void) {
	static long startTime = -1;
	struct timeval tv;
	gettimeofday(&tv, NULL);
	if (startTime < 0) startTime = tv.tv_sec;
	return (tv.tv_sec - startTime) * 1000000L + tv.tv_usec;
}
void in_main_thread(void (^block)(void)) {
	if ([NSThread isMainThread]) block();
	else dispatch_async(dispatch_get_main_queue(), block);
}
static void show_alert(NSObject *object, short err, BOOL fatal) {
	in_main_thread( ^{
		NSAlert *alt;
		if ([object isKindOfClass:NSError.class])
			alt = [NSAlert alertWithError:(NSError *)object];
		else {
			NSString *str = [object isKindOfClass:NSString.class]?
				(NSString *)object : object.description;
			if (err != noErr)
				str = [NSString stringWithFormat:@"%@\nerror code = %d", str, err];
			alt = NSAlert.new;
			alt.alertStyle = fatal? NSAlertStyleCritical : NSAlertStyleWarning;
			alt.messageText = [NSString stringWithFormat:@"%@ in %@",
				fatal? @"Error" : @"Warning",
				[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleName"]];
			alt.informativeText = str;
		}
		NSLog(@"%@\n%@",alt.messageText,alt.informativeText);
		[alt runModal];
		if (fatal) [NSApp terminate:nil];
	} );
}
void err_msg(NSObject *object, BOOL fatal) {
	show_alert(object, 0, fatal);
}
void unix_error_msg(NSString *msg, BOOL fatal) {
	show_alert([NSString stringWithFormat:@"%@: %s.", msg, strerror(errno)], errno, fatal);
}
int indexRGB2Depth(int colIdx) {
	CGFloat offset = params.mirrorOn? -params.rgbOffset : params.rgbOffset;
	simd_int2 dXY = simd_int((((simd_float2){
		(float)(colIdx % WIDTH) / WIDTH, (float)(colIdx / WIDTH) / HEIGHT }
		- .5) / COL_SCR_SIZE_RATIO + .5 - (simd_float2){ offset, 0. })
		* (simd_float2){ WIDTH, HEIGHT });
	return simd_any(dXY < 0 || dXY >= (simd_int2){ WIDTH, HEIGHT })?
		-1 : dXY.y * WIDTH + dXY.x;
}
int indexDepth2RGB(int dptIdx) {
	CGFloat offset = params.mirrorOn? -params.rgbOffset : params.rgbOffset;
	simd_int2 cXY = simd_int((((simd_float2){
		(float)(dptIdx % WIDTH) / WIDTH, (float)(dptIdx / WIDTH) / HEIGHT }
		- .5 + (simd_float2){ offset, 0. }) * COL_SCR_SIZE_RATIO + .5)
		* (simd_float2){ WIDTH, HEIGHT });
	return simd_any(cXY < 0 || cXY >= (simd_int2){ WIDTH, HEIGHT })?
		-1 : cXY.y * WIDTH + cXY.x;
}
RequestFromSv req = {.ID = 0xffffffff, 0}, newReq = {
	.ID = 0,
	.x = 32, .y = 18, .z = 24, .np = NPOINTS,
	.cellSize = 29.6
};

@interface AppDelegate () {
	IBOutlet NSPopUpButton *monitorPopUp;
	IBOutlet NSButton *senderCBox, *mirrorCBox, *resetBtn;
	IBOutlet NSTextField *ipTxt, *portDgt, *maxDepthDgt,
		*numPtMaxDgt, *numPtMinDgt, *densityDgt,
		*ppfDgt, *fpsDgt;
	IBOutlet NSSlider *maxDepthSld, *rgbOffsetSld,
		*xSld, *ySld, *zSld, *scaleSld;
	NSUndoManager *undoManager;
	unsigned long frmTimestamp;
	CGFloat fps;
}
@property (strong) IBOutlet NSWindow *window;
@property (readonly) NSConditionLock *lock;
@property (readonly) CalcPoints *calcPoints;
@end

@implementation AppDelegate
- (void)RSLoop {
	BOOL running = YES;
	rs_start();
	while (running) @autoreleasepool {
		if (params.senderOn || params.monitorType)
			running = rs_step();
		else running = NO;
	}
	rs_stop();
}
- (void)showFPSandPPF:(NSInteger)npt {
	ppfDgt.integerValue = npt;
	fpsDgt.doubleValue = fps;
}
- (void)senderLoop {
	unsigned long tm1 = current_time_us();
	while (params.senderOn) {
		[_lock lockWhenCondition:YES];
		sender_step(_pointsData);
		NSInteger npt = (_pointsData == nil)? 0 : _pointsData.length / sizeof(PointInfo);
		[_lock unlockWithCondition:NO];
		unsigned long tm2 = current_time_us();
		fps += (1e6 / (tm2 - tm1) - fps) * .05; tm1 = tm2;
		in_main_thread(^{ [self showFPSandPPF:npt]; });
	}
	sender_close();
	fps = 0.;
	in_main_thread(^{ [self showFPSandPPF:0]; });
}
- (void)startRSThread {
	[NSThread detachNewThreadSelector:@selector(RSLoop) toTarget:self withObject:nil];
}
- (void)startSenderThread {
	sender_open(params.IPV4Address, params.portNumber);
	[NSThread detachNewThreadWithBlock:^{
		if (say_hello(&params.senderOn))
			while (params.senderOn) read_spec();
	}];
	[NSThread detachNewThreadSelector:@selector(senderLoop) toTarget:self withObject:nil];
}
- (void)applicationWillFinishLaunching:(NSNotification *)notification {
	_lock = NSConditionLock.new;
	_calcPoints = CalcPoints.new;
	params = defaultParams;
	dict_to_params(&params, NSUserDefaults.standardUserDefaults.dictionaryRepresentation);
	DispatchGrp = dispatch_group_create();
	DispatchQue = dispatch_queue_create("MyQueue", DISPATCH_QUEUE_CONCURRENT);
	size_t len = sizeof(SInt32);
	SInt32 nCpus = 0;
	sysctlbyname("hw.perflevel0.physicalcpu", &nCpus, &len, NULL, 0);
	nCores = (nCpus > 0)? nCpus : NSProcessInfo.processInfo.processorCount;
}
static void depthDataCB(AppDelegate *dlgt, uint16 *depthData, uint32 *colorData) {
	static BOOL wasNoPoints = YES;
	dlgt.pointsData = [dlgt.calcPoints calcPointsFromDepth:depthData color:colorData];
	BOOL isNoPoints = (dlgt.pointsData == nil);
	if (params.senderOn && !(isNoPoints && wasNoPoints)) {
		[dlgt.lock lock];
		[dlgt.lock unlockWithCondition:YES];
	}
	switch (params.monitorType) {
		case MonitorNone: break;
		case MonitorDepth:
		[dlgt.monitorView fetchFrameImage:^(int idx) {
			uint16 z = depthData[idx];
			return (z > params.maxDepth)? 0.f : (float)z / params.maxDepth; } ];
		break;
		case MonitorDensity: {
			float *densityMap = (float *)dlgt.calcPoints.densityMapData.bytes;
			[dlgt.monitorView fetchFrameImage:^(int idx) { return densityMap[idx]; } ];
		} break;
		case MonitorPoints: if (!(isNoPoints && wasNoPoints))
			[dlgt.monitorView setPointsData:dlgt.pointsData];
		break;
		case MonitorRGB:
		[dlgt.monitorView fetchFrameRGB:^(int idx) {
			int dptIdx = indexRGB2Depth(idx);
			return (dptIdx < 0 || depthData[dptIdx] > params.maxDepth
				|| depthData[dptIdx] == 0)?
				((colorData[idx] & 0xfcfcfcfc) >> 2) : colorData[idx];
		}];
	}
	wasNoPoints = isNoPoints;
}
- (void)adjustMaxNumPts:(NSInteger)numPts {
	((NSNumberFormatter *)(numPtMaxDgt.formatter)).maximum =
	((NSNumberFormatter *)(numPtMinDgt.formatter)).maximum = @(numPts);
	if (numPtMaxDgt.integerValue > numPts) numPtMaxDgt.integerValue = numPts;
	if (numPtMinDgt.integerValue > numPts) numPtMinDgt.integerValue = numPts;
}
- (void)adjustControls {
	[monitorPopUp selectItemAtIndex:params.monitorType];
	maxDepthDgt.integerValue = maxDepthSld.integerValue = params.maxDepth;
	rgbOffsetSld.doubleValue = params.rgbOffset;
	rgbOffsetSld.enabled = params.monitorType == MonitorRGB;
	senderCBox.state = params.senderOn? NSControlStateValueOn : NSControlStateValueOff;
	ipTxt.stringValue = [NSString stringWithUTF8String:params.IPV4Address];
	portDgt.integerValue = params.portNumber;
	ipTxt.enabled = portDgt.enabled = !params.senderOn;
	numPtMaxDgt.integerValue = params.numPtMax;
	numPtMinDgt.integerValue = params.numPtMin;
	densityDgt.doubleValue = params.density;
	mirrorCBox.state = params.mirrorOn? NSControlStateValueOn : NSControlStateValueOff;
	xSld.doubleValue = params.geom.x;
	ySld.doubleValue = params.geom.y;
	zSld.doubleValue = params.geom.z;
	scaleSld.doubleValue = params.geom.w;
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
	[self adjustMaxNumPts:NPOINTS];
	[self adjustControls];
	ppfDgt.integerValue = 0;
	fpsDgt.doubleValue = 0.;
//
	rs_initialize(self, depthDataCB);
	if (params.senderOn || params.monitorType) [self startRSThread];
	if (params.senderOn) [self startSenderThread];
}
- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (params.senderOn) sender_close();
	rs_close();
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSDictionary *dict = dict_from_params(&params);
	for (NSString *key in dict) [ud setObject:dict[key] forKey:key];
}
- (IBAction)chooseMonitorType:(NSObject *)sender {
	NSInteger typeID;
	if ([sender isKindOfClass:NSMenuItem.class]) {
		typeID = ((NSMenuItem *)sender).tag;
		[monitorPopUp selectItemAtIndex:typeID];
	} else typeID = monitorPopUp.indexOfSelectedItem;
	MonitorType newType = (MonitorType)typeID;
	if (newType == params.monitorType) return;
	if (params.monitorType == MonitorNone && !params.senderOn) [self startRSThread];
	params.monitorType = newType;
	rgbOffsetSld.enabled = newType == MonitorRGB;
}
- (IBAction)switchSender:(NSObject *)sender {
	if ([sender isKindOfClass:NSMenuItem.class])
		senderCBox.state = !senderCBox.state;
	BOOL newState = senderCBox.state == NSControlStateValueOn;
	if (newState == params.senderOn) return;
	ipTxt.enabled = portDgt.enabled = resetBtn.enabled = !(params.senderOn = newState);
	if (newState) {
		[self startSenderThread];
		if (!params.monitorType) [self startRSThread];
	} else {
		[_lock lock];
		_pointsData = nil;
		[_lock unlockWithCondition:YES];
	}
}
- (void)registarUndoForInteger:(NSInteger)orgValue control:(NSControl *)sender
	name:(NSString *)actionName {
	[undoManager registerUndoWithTarget:sender handler:^(NSControl *cntrl) {
		cntrl.integerValue = orgValue;
		[cntrl sendAction:cntrl.action to:cntrl.target];
	}];
	if (!undoManager.undoing && !undoManager.redoing)
		undoManager.actionName = actionName;
}
- (IBAction)changeMaxDepth:(NSControl *)sender {
	uint16 newValue = sender.intValue, orgValue = params.maxDepth;
	if (newValue == orgValue) return;
	if (sender != maxDepthSld) maxDepthSld.integerValue = newValue;
	if (sender != maxDepthDgt) maxDepthDgt.integerValue = newValue;
	params.maxDepth = newValue;
	[self registarUndoForInteger:orgValue control:sender name:@"Max Depth"];
}
- (IBAction)changeRGBOffset:(id)sender {
	CGFloat newValue = rgbOffsetSld.doubleValue, orgValue = params.rgbOffset;
	if (params.mirrorOn) newValue = - newValue;
	if (newValue == orgValue) return;
	if (params.mirrorOn) orgValue = - orgValue;
	params.rgbOffset = newValue;
	[undoManager registerUndoWithTarget:rgbOffsetSld handler:^(NSControl *cntrl) {
		cntrl.doubleValue = orgValue;
		[cntrl sendAction:cntrl.action to:cntrl.target];
	}];
	if (!undoManager.undoing && !undoManager.redoing)
		undoManager.actionName = @"RGB offset";
}
- (IBAction)changeIPV4Address:(id)sender {
	const char *newStr = ipTxt.stringValue.UTF8String;
	if (strcmp(newStr, params.IPV4Address) == 0) return;
	NSString *orgStr = [NSString stringWithUTF8String:params.IPV4Address];
	strncpy(params.IPV4Address, newStr, sizeof(params.IPV4Address));
	[undoManager registerUndoWithTarget:ipTxt handler:^(NSTextField *txt) {
		txt.stringValue = orgStr;
		[txt sendAction:txt.action to:txt.target];
	}];
	if (!undoManager.undoing && !undoManager.redoing)
		undoManager.actionName = @"IPv4 Address";
}
- (IBAction)changePortNumber:(id)sender {
	uint16 newValue = portDgt.intValue, orgValue = params.portNumber;
	if (newValue == orgValue) return;
	params.portNumber = newValue;
	[self registarUndoForInteger:orgValue control:portDgt name:@"Port Number"];
}
- (IBAction)changeNumPtMax:(id)sender {
	NSInteger newValue = numPtMaxDgt.integerValue, orgValue = params.numPtMax;
	if (newValue == orgValue) return;
	params.numPtMax = newValue;
	[self registarUndoForInteger:orgValue control:numPtMaxDgt name:@"Max points"];
}
- (IBAction)changeNumPtMin:(id)sender {
	NSInteger newValue = numPtMinDgt.integerValue, orgValue = params.numPtMin;
	if (newValue == orgValue) return;
	params.numPtMin = newValue;
	[self registarUndoForInteger:orgValue control:numPtMinDgt name:@"Min points"];
}
- (IBAction)changeDensity:(NSControl *)sender {
	CGFloat newValue = params.density, orgValue = params.density;
	newValue = densityDgt.doubleValue;
	if (newValue == orgValue) return;
	params.density = newValue;
	[undoManager registerUndoWithTarget:densityDgt handler:^(NSControl *cntrl) {
		cntrl.doubleValue = orgValue;
		[cntrl sendAction:cntrl.action to:cntrl.target];
	}];
	if (!undoManager.undoing && !undoManager.redoing)
		undoManager.actionName = @"Density";
}
- (IBAction)switchMirror:(NSObject *)sender {
	if ([sender isKindOfClass:NSMenuItem.class])
		mirrorCBox.state = !mirrorCBox.state;
	BOOL orgValue = params.mirrorOn, newValue = mirrorCBox.state == NSControlStateValueOn;
	if (orgValue == newValue) return;
	params.mirrorOn = newValue;
	[undoManager registerUndoWithTarget:mirrorCBox handler:^(NSButton *btn) {
		btn.state = orgValue? NSControlStateValueOn : NSControlStateValueOff;
		[btn sendAction:btn.action to:btn.target];
	}];
	if (!undoManager.undoing && !undoManager.redoing)
		undoManager.actionName = @"Mirror";
}
- (IBAction)changeGeometry:(NSSlider *)sender {
	NSInteger tag = sender.tag;
	float orgValue = params.geom[tag], newValue = sender.doubleValue;
	if (orgValue == newValue) return;
	params.geom[tag] = newValue;
	[undoManager registerUndoWithTarget:sender handler:^(NSControl *cntrl) {
		cntrl.doubleValue = orgValue;
		[cntrl sendAction:cntrl.action to:cntrl.target];
	}];
	if (!undoManager.undoing && !undoManager.redoing) undoManager.actionName =
		@[@"X Offset", @"Y Offset", @"Z Offset", @"Scale"][tag];
}
- (void)setParamsFromDict:(NSDictionary *)newDict {
	NSDictionary *orgDict = dict_from_params(&params);
	dict_to_params(&params, newDict);
	[self adjustControls];
	[undoManager registerUndoWithTarget:self handler:^(id target) {
		[self setParamsFromDict:orgDict];
	}];
}
- (IBAction)reset:(id)sender {
	if (memcmp(&params, &defaultParams, sizeof(params)) == 0) return;
	[self setParamsFromDict:dict_from_params(&defaultParams)];
	undoManager.actionName = @"Reset";
}
//
- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)window {
	if (!undoManager) undoManager = NSUndoManager.new;
	return undoManager;
}
- (void)windowWillClose:(NSNotification *)notification {
	[NSTimer scheduledTimerWithTimeInterval:.1
		target:NSApp selector:@selector(terminate:) userInfo:nil repeats:NO];
}
//
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL act = menuItem.action;
	if (act == @selector(chooseMonitorType:)) {
		if (menuItem.parentItem != nil)
			menuItem.state = menuItem.tag == params.monitorType;
	} else if (act == @selector(switchSender:))
		menuItem.state = senderCBox.state;
	else if (act == @selector(switchMirror:))
		menuItem.state = mirrorCBox.state;
	return YES;
}
@end
