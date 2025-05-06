//
//  UDPSender.m
//  DepthCaptureRS
//
//  Created by Tatsuo Unemi on 2025/02/08.
//

#import "UDPSender.h"
@import Darwin.POSIX.netinet.in;
@import simd;
#import "AppDelegate.h"
#import "../CommHeaders/PointInfo.h"

static int soc = -1;
static socklen_t pkt_size_max = 0;
static struct sockaddr_in name;
static BOOL didSendPoints = NO;

void sender_open(const char *ip4addr, UInt16 portNumber) {
	MyComment("sender_open start\n");
	soc = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP);
	if (soc < 0) { unix_error_msg(@"socket", YES); return; }
	socklen_t optLen = sizeof(socklen_t);
	if (getsockopt(soc, SOL_SOCKET, SO_SNDBUF, &pkt_size_max, &optLen))
		{ unix_error_msg(@"getsockopt", YES); return; }
	name.sin_len = sizeof(name);
	name.sin_family = AF_INET;
	inet_aton(ip4addr? ip4addr : "127.0.0.1", &name.sin_addr);
	name.sin_port = EndianU16_NtoB(portNumber);
	MyComment("sender_open end\n");
}
#define SIZE_UNIT 512
static BOOL send_packet(void *data, ssize_t size) {
	if (pkt_size_max < size) {
		if (size > 65507) {
			err_msg([NSString stringWithFormat:
				@"Too large size %ld of packet to send.", size],
				YES); return NO; }
		socklen_t newLen = (((socklen_t)size + SIZE_UNIT - 1) / SIZE_UNIT) * SIZE_UNIT;
		if (setsockopt(soc, SOL_SOCKET, SO_SNDBUF, &newLen, sizeof(newLen)))
			{ unix_error_msg(@"setsockopt", YES); return NO; }
		MyComment("Sender's buffer size %d -> %ld\n", pkt_size_max, size);
		pkt_size_max = newLen;
	}
	ssize_t sizeSent = sendto(soc, data, size,
		0, (struct sockaddr *)&name, sizeof(name));
	return size == sizeSent;
}
BOOL say_hello(BOOL *senderOn) {
	UInt32 com = COM_HELLO;
	struct timeval timeout = {.tv_sec = 2, .tv_usec = 0};
	@try {
		if (setsockopt(soc, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)))
			@throw @"set socket receiver timeout to 2 seconds.";
		for (BOOL trying = YES; trying; ) {
			if (!*senderOn) return NO;
			if (!send_packet(&com, sizeof(com))) @throw @"send hello";
			MyComment("Said Hello.\n");
			trying = !read_spec();
			if (trying && errno != EWOULDBLOCK && *senderOn) @throw @"read spec";
		}
		timeout = (struct timeval){0, 0};
		if (setsockopt(soc, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout)))
			@throw @"reset socket receiver timeout";
		in_main_thread(^{
			[(AppDelegate *)(NSApp.delegate) adjustMaxNumPts:newReq.np];
		});
		return YES;
	} @catch (NSString *msg) {
		sender_close(); unix_error_msg(msg, YES); return NO;
	}
}
void sender_step(NSMutableData *dataToBeSent) {
	typedef struct { UInt32 cIdx, pIdx; } CelPtIdx;
	static CelPtIdx *idxBuf = NULL;
	static PointInfo *ptBuf = NULL;
	static PointInfoPacket *packet = NULL;
	if (req.ID != newReq.ID) memcpy(&req, &newReq, sizeof(req));
	if (idxBuf == NULL) {
		idxBuf = malloc(sizeof(CelPtIdx) * NPOINTS);
		ptBuf = malloc(sizeof(PointInfo) * NPOINTS);
		packet = malloc(MAX_PKT_SIZE);
	}
	packet->timestamp = (UInt32)((current_time_us() / 1000) & 0x7fffffff);
	packet->ID = req.ID;
	PointInfo *points = dataToBeSent.mutableBytes;
	NSInteger nPoints = dataToBeSent.length / sizeof(PointInfo);
	NSInteger nPtToSend = 0;
	float scale = pow(5., params.geom.w);
	simd_float3 geom = params.geom.xyz,
		maxP = (simd_float3){req.x, req.y, req.z} * req.cellSize,
		offset = (geom + (simd_float3){1., 1., 0.}) / (simd_float3){2., 2., 1.} * maxP;
	maxP *= .9999;
	for (UInt32 i = 0; i < nPoints && nPtToSend < NPOINTS; i ++) {
		simd_float3 p = points[i].p * scale + offset;
		if (!simd_equal(p, simd_clamp(p, 0., maxP))) continue;
		ptBuf[i].p = p;
		ptBuf[i].c.rgb = points[i].c.rgb;
		simd_int3 v = simd_min(simd_int(p / req.cellSize),
			(simd_int3){req.x - 1, req.y - 1, req.z - 1});
		idxBuf[nPtToSend].pIdx = i;
		idxBuf[nPtToSend ++].cIdx = (v.z * req.y + v.y) * req.x + v.x;
	}
	@try {
		NSInteger pktLen = PKT_HEAD_SZ;
		packet->pktNum = 0;
		if (nPtToSend < params.numPtMin) {
			if (didSendPoints) {
				packet->nPics = 0;
				if (!send_packet(packet, pktLen))
					@throw @"Couldn't send an empty Cell info.";
				didSendPoints = NO;
			}
		} else {
			qsort_b(idxBuf, nPtToSend, sizeof(CelPtIdx), ^(const void *x, const void *y) {
				UInt32 a = ((CelPtIdx *)x)->cIdx, b = ((CelPtIdx *)y)->cIdx;
				return (a < b)? -1 : (a > b)? 1 : 0;
			});
			packet->nPics = 1;
			PointsInCell *pic = packet->pic;
			pic->celIdx = idxBuf[0].cIdx;
			pic->n = 0;
			pktLen += CEL_HEAD_SZ;
			for (NSInteger idx = 0;;) {
				pic->pts[pic->n ++] = ptBuf[idxBuf[idx ++].pIdx];
				pktLen += sizeof(PointInfo);
				if (idx >= nPtToSend) break;
				if (idxBuf[idx].cIdx != pic->celIdx) {
					if (pktLen > MAX_PKT_SIZE - sizeof(PointsInCell)) {
						if (!send_packet(packet, pktLen)) @throw @"Send points #1";
						pktLen = PKT_HEAD_SZ + CEL_HEAD_SZ;
						pic = packet->pic;
						packet->pktNum ++; packet->nPics = 1;
					} else {
						pktLen += CEL_HEAD_SZ;
						pic = (PointsInCell *)(pic->pts + pic->n);
						packet->nPics ++;
					}
					pic->celIdx = idxBuf[idx].cIdx;
					pic->n = 0;
				} else if (pktLen > MAX_PKT_SIZE - sizeof(PointInfo)) {
					if (!send_packet(packet, pktLen)) @throw @"Send points #2";
					pktLen = PKT_HEAD_SZ + CEL_HEAD_SZ;
					pic = packet->pic;
					packet->pktNum ++; packet->nPics = 1;
					pic->celIdx = idxBuf[idx].cIdx;
					pic->n = 0;
				}
			}
			if (pktLen > PKT_HEAD_SZ + CEL_HEAD_SZ)
				if (!send_packet(packet, pktLen)) @throw @"Send points #3";
			didSendPoints = YES;
		}
		UInt32 com = COM_END_OF_FRAME;
		if (!send_packet(&com, sizeof(com))) @throw @"Send EndOfFrame";
	} @catch (NSString *msg) {
		sender_close(); unix_error_msg(msg, YES);
	}
}
void sender_close(void) {
	if (soc >= 0) { close(soc); soc = -1; MyComment("sender's socket closed.\n"); }
}
BOOL read_spec(void) {
	struct sockaddr name_rcv;
	socklen_t len = sizeof(name_rcv);
	RequestFromSv reqBuf;
	ssize_t size = recvfrom(soc, &reqBuf, sizeof(reqBuf), 0, &name_rcv, &len);
	if (size == sizeof(reqBuf)) {
		memcpy(&newReq, &reqBuf, sizeof(reqBuf));
		MyComment("Got request. ID:%d, %dx%dx%d, %dpts, celSz:%.1f\n",
			reqBuf.ID, reqBuf.x,reqBuf.y,reqBuf.z, reqBuf.np, reqBuf.cellSize);
		return YES;
	} else return NO;
}
