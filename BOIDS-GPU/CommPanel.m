//
//  CommPanel.m
//  Learning is Life
//
//  Created by Tatsuo Unemi on 2023/01/30.
//

#import "CommPanel.h"
#import "AppDelegate.h"
#import "AgentCPU.h"
#import "MetalView.h"
#import "../CommHeaders/PointInfo.h"

Tracker *theTracker = nil;
PtCell *PtCells, *PtCelWk;
simd_float3 *Points, *PointsWk;
NSInteger ptBfIdx = 0, nPoints = 0;
static simd_int3 partitions = {N_DCELLSX, N_DCELLSY, N_DCELLSZ};
static int prttDiv[3][7] = {{1, 2, 4, 8, 16, 0}, {1, 3, 9, 0}, {1, 2, 3, 4, 6, 12, 0}};
static Sender *theSender = nil;
static Comm *theComm = nil;
static NSString *keyCommEnabled = @"commEnabled",
	*keyDstAddress = @"dstAddress", *keyDstPort = @"dstPort",
	*keyRcvPort = @"rcvPort", *keyPktPerSec = @"dstPktPerSec",
	*keyPartitions = @"partitions";
static void comm_setup_defaults(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSString *str; NSNumber *num;
	if ((str = [ud objectForKey:keyDstAddress]) != nil)
		if (str.length > 6) theComm.destinationAddress = str;
	if ((num = [ud objectForKey:keyDstPort]) != nil)
		theComm.destinationPort = num.intValue;
}
static BOOL start_communication(in_port_t rcvPort, float pktPerSec) {
	if (theComm == nil) {
		theComm = Comm.new;
		comm_setup_defaults();
	}
	if (theTracker == nil) theTracker = Tracker.new;
	if (![theComm startReceiverWithPort:rcvPort delegate:theTracker]) return NO;
	if (theSender == nil) theSender = Sender.new;
	theSender.packetPerSec = pktPerSec;
	return YES;
}
void check_initial_communication(void) {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSNumber *num;
	if ((num = [ud objectForKey:keyCommEnabled]) == nil) return;
	if (!num.boolValue) return;
	num = [ud objectForKey:keyRcvPort];
	in_port_t rcvPort = (num != nil)? num.intValue : RCV_PORT;
	num = [ud objectForKey:keyPktPerSec];
	float pps = (num != nil)? num.floatValue : DST_PKT_PER_SEC;
	NSArray<NSNumber *> *arr = [ud objectForKey:keyPartitions];
	if (arr != nil && arr.count == 3)
		partitions = (simd_int3){arr[0].intValue, arr[1].intValue, arr[2].intValue};
	start_communication(rcvPort, pps);
}
BOOL communication_is_running(void) {
	return (theComm != nil && theComm.valid);
}
typedef struct {
	unsigned long prevTime;
	CGFloat pps, bps;
} TraficMeasure;
static void measure_trafic(TraficMeasure *tm, ssize_t nBytes) {
	unsigned long t = current_time_us(), interval = t - tm->prevTime;
	CGFloat a = fmin(1., interval / 1e6);
	tm->pps += (1e6 / interval - tm->pps) * a;
	tm->bps += (nBytes * 1e6 / interval - tm->bps) * a;
	tm->prevTime = t;
}
@implementation CommPanel {
	IBOutlet NSButton *cboxCommEnabled, *btnDelUsrDflt;
	IBOutlet NSTextField *txtMyAddr, *txtMyBcAdr,
		*prttXdgt, *prttYdgt, *prttZdgt, *prttTotalDgt,
		*txtDstAddr, *txtDstPort, *txtSndInfo, *txtRcvPort, *txtRcvInfo,
		*dgtPktPerSec, *dgtSndPPS, *dgtSndBPS, *dgtRcvPPS, *dgtRcvBPS;
	IBOutlet NSStepper *prttXStp, *prttYStp, *prttZStp;
	NSArray<NSTextField *> *prttDgts;
	TraficMeasure sndTM, rcvTM;
	BOOL handlersReady;
}
- (NSString *)windowNibName { return @"CommPanel"; }
static NSString *bytes_number(CGFloat b) {
	CGFloat exp = (b <= 1.)? 0. : fmin(floor(log10(b) / 3.), 5.);
	NSString *unit = @[@"",@"k",@"M",@"G",@"T",@"P"][(int)exp];
	b /= pow(1e3, exp);
	return [NSString stringWithFormat:
		(b < 10.)? @"%.3f%@" : (b < 100.)? @"%.2f%@" : @"%.1f%@", b, unit];
}
- (NSString *)commInfoString:(ssize_t)nBytes
	propo:(NSString *)propo addr:(NSString *)addr {
	static NSDateFormatter *dtFmt = nil;
	if (dtFmt == nil) {
		dtFmt = NSDateFormatter.new;
		dtFmt.dateFormat = @"HH:mm:ss.SSS";
	}
	return [NSString stringWithFormat:@"%@ %6ld bytes %@ %@.",
		[dtFmt stringFromDate:NSDate.now], nBytes, propo, addr];
}
- (void)setupStatHandlers {
	if (handlersReady || theComm == nil) return;
	[theComm setStatHandlersSnd:^(ssize_t nBytes) {
		measure_trafic(&self->sndTM, nBytes);
		NSString *bpsStr = bytes_number(self->sndTM.bps), *info =
			[self commInfoString:nBytes propo:@"to" addr:theComm.destinationAddress];
		in_main_thread(^{
			self->dgtSndPPS.doubleValue = self->sndTM.pps;
			self->dgtSndBPS.stringValue = bpsStr;
			self->txtSndInfo.stringValue = info;
		});
	} rcv:^(ssize_t nBytes) {
		measure_trafic(&self->rcvTM, nBytes);
		NSString *bpsStr = bytes_number(self->rcvTM.bps), *info =
			[self commInfoString:nBytes propo:@"from" addr:theComm.senderAddress];
		in_main_thread(^{
			self->dgtRcvPPS.doubleValue = self->rcvTM.pps;
			self->dgtRcvBPS.stringValue = bpsStr;
			self->txtRcvInfo.stringValue = info;
		});
	}];
	handlersReady = YES;
}
- (void)adjustControls {
	BOOL enabled = (theComm != nil && theComm.valid);
    cboxCommEnabled.state = enabled;
    if (enabled) {
		txtMyAddr.stringValue = theComm.myAddress;
		txtMyBcAdr.stringValue = theComm.myBroadcastAddress;
	} else txtMyAddr.stringValue = txtMyBcAdr.stringValue = @"";
	if (theComm != nil) {
		txtDstAddr.stringValue = theComm.destinationAddress;
		txtDstPort.intValue = theComm.destinationPort;
		txtRcvPort.intValue = theComm.receiverPort;
	}
	NSArray<NSStepper *> *stps = @[prttXStp, prttYStp, prttZStp];
	for (NSInteger i = 0; i < 3; i ++) {
		NSInteger stpValue;
		for (stpValue = 0; prttDiv[i][stpValue] > 0; stpValue ++)
			if (partitions[i] <= prttDiv[i][stpValue]) break;
		if (prttDiv[i][stpValue] == 0) stpValue --;
		stps[i].integerValue = stpValue;
		partitions[i] = (int)(prttDgts[i].integerValue = prttDiv[i][stpValue]);
	}
	prttTotalDgt.integerValue = partitions.x * partitions.y * partitions.z;
	dgtSndPPS.doubleValue = dgtRcvPPS.doubleValue = 0.;
	dgtSndBPS.stringValue = dgtRcvBPS.stringValue = bytes_number(0);
}
- (void)windowDidLoad {
    [super windowDidLoad];
    prttDgts = @[prttXdgt, prttYdgt, prttZdgt];
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	NSString *str = [ud objectForKey:keyDstAddress]; 
	NSNumber *num;
    if (theComm == nil) {
		txtDstAddr.stringValue = (str != nil)? str : @"127.0.0.1";
		txtDstPort.intValue = ((num = [ud objectForKey:keyDstPort]) != nil)?
			num.intValue : OSC_PORT;
		txtRcvPort.intValue = ((num = [ud objectForKey:keyRcvPort]) != nil)?
			num.intValue : RCV_PORT;
	} else {
		for (NSControl *c in @[txtRcvPort, txtDstPort, txtDstAddr,
			prttXStp, prttYStp, prttZStp]) c.enabled = NO;
		[self setupStatHandlers];
	}
	dgtPktPerSec.floatValue = ((num = [ud objectForKey:keyPktPerSec]) != nil)?
		num.floatValue : DST_PKT_PER_SEC;
	NSArray<NSNumber *> *arr = [ud objectForKey:keyPartitions];
	if (arr != nil && arr.count == 3)
		partitions = (simd_int3){arr[0].intValue, arr[1].intValue, arr[2].intValue};
	[self adjustControls];
    btnDelUsrDflt.enabled = (str != nil);
}
- (IBAction)switchEnabled:(NSButton *)cbox {
	if (cbox.state) {
		if (theComm == nil) {
			theComm = Comm.new;
			comm_setup_defaults();
			theComm.destinationAddress = txtDstAddr.stringValue;
			theComm.destinationPort = txtDstPort.intValue;
			theComm.receiverPort = txtRcvPort.intValue;
		}
		start_communication(txtRcvPort.intValue, dgtPktPerSec.floatValue);
		[self setupStatHandlers];
	} else {
		if (theSender != nil) [theSender invalidate];
		[theComm invalidate];
		theComm = nil;
		handlersReady = NO;
	}
	for (NSControl *c in @[txtRcvPort, txtDstPort, txtDstAddr,
		dgtPktPerSec, prttXStp, prttYStp, prttZStp]) c.enabled = !cbox.state;
	[self adjustControls];
}
- (IBAction)switchCommEnabled:(id)sender {	// for menu item
    cboxCommEnabled.state = !cboxCommEnabled.state;
	[self switchEnabled:cboxCommEnabled];
}
- (IBAction)stepPartitions:(NSStepper *)stp {
	NSInteger idx = stp.tag, value = stp.integerValue;
	partitions[idx] = (int)(prttDgts[idx].integerValue = prttDiv[idx][value]);
	prttTotalDgt.integerValue = partitions.x * partitions.y * partitions.z;
}
- (IBAction)saveAsDefaults:(id)sender {
	NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
	[ud setBool:cboxCommEnabled.state forKey:keyCommEnabled];
	[ud setObject:txtDstAddr.stringValue forKey:keyDstAddress];
	[ud setInteger:txtDstPort.intValue forKey:keyDstPort];
	[ud setInteger:txtRcvPort.intValue forKey:keyRcvPort];
	[ud setFloat:dgtPktPerSec.floatValue forKey:keyPktPerSec];
	[ud setObject:@[@(partitions.x), @(partitions.y), @(partitions.z)]
		forKey:keyPartitions];
	btnDelUsrDflt.enabled = YES;
}
- (IBAction)deleteDefaults:(id)sender {
	NSAlert *alt = NSAlert.new;
	alt.alertStyle = NSAlertStyleWarning;
	alt.messageText = @"Default settings of the communication are going to removed.";
	alt.informativeText = @"You cannot undo this operation.";
	[alt addButtonWithTitle:@"OK"];
	[alt addButtonWithTitle:@"Cancel"];
	[alt beginSheetModalForWindow:self.window completionHandler:
		^(NSModalResponse returnCode) {
			if (returnCode != NSAlertFirstButtonReturn) return;
			NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
			for (NSString *key in @[keyCommEnabled, keyDstAddress,
				keyDstPort, keyRcvPort, keyPktPerSec, keyPartitions])
				[ud removeObjectForKey:key];
			self->btnDelUsrDflt.enabled = NO;
	}];
}
//
- (void)windowDidBecomeMain:(NSNotification *)notification {
	[self setupStatHandlers];
}
- (void)windowWillClose:(NSNotification *)notification {
	[theComm setStatHandlersSnd:nil rcv:nil];
	handlersReady = NO;
}
//
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = menuItem.action;
	if (action == @selector(switchCommEnabled:))
		menuItem.title = cboxCommEnabled.state? @"Disable" : @"Enable";
	else if (action == @selector(deleteDefaults:))
		return btnDelUsrDflt.enabled;
	return YES;
}
@end

@implementation Tracker {
	NSLock *lock;
	UInt32 tmstamp, reqID;
	NSInteger nPtCells, ptIdx;
	unsigned long nPktTime;
}
- (instancetype)init {
	if (!(self = [super init])) return nil;
	lock = NSLock.new;
	return self;
}
- (void)lock { [lock lock]; }
- (void)unlock { [lock unlock]; }
- (void)stepTracking {}
// Comm Delegate
//#define COM_MONITOR
#ifdef COM_MONITOR
static void monitor_req(RequestFromSv *req) {
	printf("Received HELLO, reply request ID:%d, %dx%dx%d, %dpts, celSz:%.1f\n",
		req->ID, req->x,req->y,req->z, req->np, req->cellSize);
}
static void monitor_eof(void) {
	printf("EOF %ld points.\n", nPoints);
}
static void monitor_points(PointInfoPacket *buf, ssize_t length) {
	printf("Received Points, TMS:%d, ID:%d, Pkt#%d, %d cells\n",
		buf->timestamp, buf->ID, buf->pktNum, buf->nPics);
	PointsInCell *pic = buf->pic;
	for (NSInteger len = PKT_HEAD_SZ; len < length; ) {
		printf("CelIdx:%d, n:%d, ", pic->celIdx, pic->n);
		if (pic->celIdx >= N_CELLS || pic->n == 0) {
			printf("Error?\n"); break;
		}
		len += CEL_HEAD_SZ + sizeof(simd_float3) * pic->n;
		for (NSInteger i = 0; i < 3 && i < pic->n; i ++) {
			PointInfo pInfo = pic->pts[i];
			printf("(%.1f,%.1f,%.1f:%08X),", pInfo.p.x, pInfo.p.y, pInfo.p.z, pInfo.c.rgb);
		}
		printf((pic->n > 3)? "...\n" : "\n");
		pic = (PointsInCell *)(pic->pts + pic->n);
	}
}
#else
static void monitor_req(RequestFromSv *req) {}
static void monitor_eof(void) {}
static void monitor_points(PointInfoPacket *buf, ssize_t length) {}
#endif
- (void)sendRequest {
	RequestFromSv req = {.ID = (reqID = current_time_us() & 0x7fffffff),
		.x = N_CELLS_X, .y = N_CELLS_Y, .z = N_CELLS_Z,
		.np = NPOINTS, .cellSize = CellSize};
	[theComm sendbackRequestInfo:&req];
	monitor_req(&req);
}
- (void)receive:(PointInfoPacket *)buf length:(ssize_t)length {
	switch (buf->timestamp) {
		case COM_HELLO:
		[self sendRequest];
		break;
		case COM_END_OF_FRAME:
		[lock lock];
		ptBfIdx = 1 - ptBfIdx;
		PtCell *pc = PtCells; PtCells = PtCelWk; PtCelWk = pc;
		simd_float3 *pt = Points; Points = PointsWk; PointsWk = pt;
		nPoints = ptIdx;
		_lastStepOfFrame = Step;
		if (shapeType == ShapePoints) in_main_thread(^{
			((AppDelegate *)NSApp.delegate).metalView.view.needsDisplay = YES; });
		[lock unlock];
		monitor_eof();
		break;
		default:
		monitor_points(buf, length);
		if (reqID != buf->ID) {
			if (nPktTime == 0) nPktTime = current_time_us();
			else if (current_time_us() - nPktTime > 500000L) [self sendRequest];
			break;
		}
		nPktTime = 0;
		if (tmstamp != buf->timestamp) {
			memset(PtCelWk, 0, sizeof(PtCell) * N_CELLS);
			ptIdx = 0;
			tmstamp = buf->timestamp;
		}
		PointsInCell *pic = buf->pic;
		for (NSInteger i = 0; i < buf->nPics; i ++) {
//if (pic->celIdx >= N_CELLS)
//	NSLog(@"PT: %d is out of bounds, shold be less than %d", pic->celIdx, N_CELLS);
			PtCell *pc = PtCelWk + pic->celIdx;
			if (pc->n == 0) { pc->start = (UInt32)ptIdx; pc->n = pic->n; }
			else pc->n += pic->n;
			memcpy(PointsWk + ptIdx, pic->pts, sizeof(simd_float3) * pic->n);
			ptIdx += pic->n;
			pic = (PointsInCell *)(pic->pts + pic->n);
		}
	}
}
@end

@implementation Sender {
	NSTimer *timer;
	MetalView *metalView;
}
#define NDCELLS (N_DCELLSX*N_DCELLSY*N_DCELLSZ)
#define OSC_COM_SIZE 20
#define OSC_N_ARGS 10
#define OSC_PKT_SIZE (OSC_COM_SIZE+OSC_N_ARGS*4)
typedef union {
	char c[OSC_PKT_SIZE];
	UInt32 i[OSC_PKT_SIZE/4];
} OSCPacket;
static OSCPacket *packets = NULL;
static void make_OSC_packets(void) {
	static char addr[] = "/cell\0\0\0,iiiiffffff\0";
	static int nPktsM = 0;
	int nPkts = partitions.x * partitions.y * partitions.z;
	if (nPkts != nPktsM) {
		packets = realloc(packets, sizeof(OSCPacket) * nPkts);
		for (NSInteger i = 0; i < nPkts; i ++)
			memcpy(packets[i].c, addr, OSC_COM_SIZE);
		nPktsM = nPkts;
	}
	simd_int3 celSpan = (simd_int3){N_DCELLSX, N_DCELLSY, N_DCELLSZ}
		/ partitions * CellUnit;
	SInt32 maxN = 200 / (celSpan.x * celSpan.y * celSpan.z);
	if (maxN < 10) maxN = 10;
	Agent *popSim = PopSim[popBfIdx];
	void (^block)(int, int) = ^(int start, int end) {
		union { simd_float3 v; UInt32 i[4]; } q;
		for (int i = start; i < end; i ++) {
			simd_int3 ixyz = {i % partitions.x,
				(i / partitions.x) % partitions.y, i / (partitions.x * partitions.y)}, jxyz;
			simd_float3 sumV = 0., sum2V = 0.;
			UInt32 nAg = 0, nn = 0;
			for (jxyz.z = 0; jxyz.z < celSpan.z; jxyz.z ++)
			for (jxyz.y = 0; jxyz.y < celSpan.y; jxyz.y ++)
			for (jxyz.x = 0; jxyz.x < celSpan.x; jxyz.x ++) {
				Cell cel = Cells[cell_index(ixyz * celSpan + jxyz)];
				SInt32 n = (cel.n < maxN)? cel.n : maxN;
				for (SInt32 i = 0; i < n; i ++) {
					simd_float3 v = popSim[Idxs[cel.start + i]].v;
					sumV += v;
					sum2V += v * v;
				}
				nn += n;
				nAg += cel.n;
			}
			UInt32 *b = packets[i].i, idx = OSC_COM_SIZE/4;
			b[idx ++] = EndianU32_NtoB(ixyz.x);
			b[idx ++] = EndianU32_NtoB(ixyz.y);
			b[idx ++] = EndianU32_NtoB(ixyz.z);
			b[idx ++] = EndianU32_NtoB(nAg);
			if (nn == 0) memset(&b[idx], 0, 6*4);
			else {
				q.v = sumV / nn / PrmsSim.maxV;
				for (int i = 0; i < 3; i ++)
					b[idx ++] = EndianU32_NtoB(q.i[i]);
				q.v = sqrt(fmax(0., sum2V - sumV * sumV / nn) / nn) / PrmsSim.maxV;
				for (int i = 0; i < 3; i ++)
					b[idx ++] = EndianU32_NtoB(q.i[i]);
			}
		}
	};
	if (nPkts >= nCores) {
		int nCels = (int)((nPkts + nCores - 1) / nCores);
		[CellLock lock];
		for (int i = 0; i < nCores - 1; i ++)
			dispatch_group_async(DispatchGrp, DispatchQue, ^{
				block(i * nCels, (i + 1) * nCels); });
		block((int)(nCores - 1) * nCels, nPkts);
		dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	} else if (nPkts > 1) {
		for (int i = 0; i < nPkts - 1; i ++)
			dispatch_group_async(DispatchGrp, DispatchQue, ^{
				block(i, i + 1); });
		block(nPkts - 1, nPkts);
		dispatch_group_wait(DispatchGrp, DISPATCH_TIME_FOREVER);
	} else block(0, 1);
//	block(0, NDCELLS);
	[CellLock unlock];
}
void write_vecfld_CSV(void) {
#ifdef MAKE_CSV
	static FILE *csvOut = NULL;
	if (csvOut == NULL) {
		csvOut = fopen("OSC00.csv", "w");
		if (csvOut == NULL) {
			unix_error_msg(@"Could not open OSC00.csv.", YES);
			return;
		}
	}
	NSInteger nPkts = partitions.x * partitions.y * partitions.z;
#ifdef SAVE_IMAGES
	make_OSC_packets();
#endif
	for (NSInteger i = 0; i < nPkts; i ++) {
		UInt32 b[10], *s = packets[i].i + OSC_COM_SIZE/4;
		for (NSInteger j = 0; j < 10; j ++) b[j] = EndianU32_BtoN(s[j]);
		float *f = (float *)(b + 4);
		fprintf(csvOut, "/cell,%d,%d,%d,%d,%.5f,%.5f,%.5f,%.5f,%.5f,%.5f\r\n",
			b[0], b[1], b[2], b[3], f[0], f[1], f[2], f[3], f[4], f[5]);
	}
	fflush(csvOut);
#endif
}
- (void)sendVectorFieldInfo:(id)arg {
	NSInteger nPkts = partitions.x * partitions.y * partitions.z;
	make_OSC_packets();
	for (NSInteger i = 0; i < nPkts; i ++)
		[theComm send:packets[i].c length:sizeof(OSCPacket)];
#ifndef SAVE_IMAGES
	write_vecfld_CSV();
#endif
}
- (void)invalidate {
	if (timer != nil && timer.valid) {
		[timer invalidate]; timer = nil;
	}
}
- (void)setPacketPerSec:(float)pktPerSec {
	if (pktPerSec == 0.) { [self invalidate]; return; }
	if (timer != nil && timer.valid) {
		CGFloat orgIntvl = timer.timeInterval, newIntvl = 1. / pktPerSec;
		if (fabs(orgIntvl - newIntvl) < 1e-6) return;
		[self invalidate];
	}
#ifndef SAVE_IMAGES
	if (theComm != nil && theComm.valid)
		timer = [NSTimer scheduledTimerWithTimeInterval:1. / pktPerSec
			repeats:YES block:^(NSTimer * _Nonnull tmr) {
			if (theComm == nil || !theComm.valid) [self invalidate];
			else if (((AppDelegate *)NSApp.delegate).metalView.isRunning)
				[NSThread detachNewThreadSelector:
					@selector(sendVectorFieldInfo:) toTarget:self withObject:nil];
		}];
#endif
}
@end

@implementation MyTextField
- (void)setEnabled:(BOOL)value {
	super.enabled = value;
	if (!value) self.textColor = NSColor.textColor;
}
@end
