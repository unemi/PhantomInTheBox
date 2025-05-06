//
//  MyRealSense.m
//  RealSenseTEST
//
//  Created by Tatsuo Unemi on 2020/08/17.
//  Copyright © 2020 Tatsuo Unemi. All rights reserved.
//

#import "MyRealSense.h"
#import "AppDelegate.h"
#include <librealsense2/rs.h>
#include <librealsense2/h/rs_pipeline.h>
#include <librealsense2/h/rs_frame.h>
#define FPS 30
#define STREAM_INDEX 0

static rs2_context *ctx = NULL;
static rs2_device_list *device_list = NULL;
static rs2_pipeline *pipeline = NULL;
static rs2_device *dev = NULL;
static rs2_config *config = NULL;
static rs2_pipeline_profile* pipeline_profile = NULL;
static rs2_frame* frames = NULL;
static int num_of_frames = 0, index_of_frame = 0;
static uint16 *depthData = NULL;
static uint32 *colorData = NULL;
static id delegateObject;
static void (*procedure)(id, uint16 *, uint32 *);

static NSException *exception(NSString *reasonStr) {
	return [NSException exceptionWithName:@"RealSence Exception"
		reason:reasonStr userInfo:nil];
}
static void check_error(rs2_error *e) {
	if (e) @throw exception([NSString stringWithFormat:@"rs_error in %s(%s): %s",
		rs2_get_failed_function(e), rs2_get_failed_args(e), rs2_get_error_message(e)]);
}
BOOL rs_initialize(id delegate, void (*proc)(id, uint16 *, uint32 *)) {
	delegateObject = delegate;
	procedure = proc;
	@try {
		rs2_error *e = 0;
		ctx = rs2_create_context(RS2_API_VERSION, &e);
		check_error(e);
		device_list = rs2_query_devices(ctx, &e);
		check_error(e);
		int dev_count = rs2_get_device_count(device_list, &e);
		check_error(e);
		if (dev_count == 0) @throw exception(@"Could not find a RealSense device.");
		dev = rs2_create_device(device_list, 0, &e);
		check_error(e);
		pipeline = rs2_create_pipeline(ctx, &e);
		check_error(e);
		config = rs2_create_config(&e);
		check_error(e);
		rs2_config_enable_stream(config, RS2_STREAM_DEPTH,
			STREAM_INDEX, WIDTH, HEIGHT, RS2_FORMAT_Z16, FPS, &e);
		check_error(e);
		rs2_config_enable_stream(config, RS2_STREAM_COLOR,
			STREAM_INDEX, WIDTH, HEIGHT, RS2_FORMAT_RGBA8, FPS, &e);
		check_error(e);
		return YES;
	} @catch (NSException *exc) { err_msg(exc, YES); return NO; }
}
BOOL rs_start(void) {
	if (depthData == NULL) {
		depthData = malloc(WIDTH * HEIGHT * 2);
		colorData = malloc(WIDTH * HEIGHT * 4);
	}
	@try {
		rs2_error *e = 0;
		pipeline_profile = rs2_pipeline_start_with_config(pipeline, config, &e);
		check_error(e);
		return YES;
	} @catch (NSException *exc) { err_msg(exc, YES); return NO; }
}
BOOL rs_step(void) {
	BOOL fetchedDepth = NO, fetchedColor = NO, result = YES;
	rs2_error *e = NULL;
	@try {
		while (!(fetchedDepth && fetchedColor)) {
			if (num_of_frames <= 0) {
				frames = rs2_pipeline_wait_for_frames(pipeline, RS2_DEFAULT_TIMEOUT, &e);
				check_error(e);
				num_of_frames = rs2_embedded_frames_count(frames, &e);
				check_error(e);
				index_of_frame = 0;
			}
			for (; index_of_frame < num_of_frames && !(fetchedDepth && fetchedColor); index_of_frame ++) {
				rs2_frame* frame = rs2_extract_frame(frames, index_of_frame, &e);
				check_error(e);
				if (rs2_is_frame_extendable_to(frame, RS2_EXTENSION_DEPTH_FRAME, &e)) {
					const void *buf = rs2_get_frame_data(frame, &e);
					check_error(e);
					if (params.mirrorOn) for (int i = 0; i < HEIGHT; i ++) {
						const uint16 *src = (const uint16 *)buf + i * WIDTH;
						uint16 *dst = depthData + i * WIDTH;
						for (int j = 0; j < WIDTH; j ++) dst[WIDTH - 1 - j] = src[j];
					} else memcpy(depthData, buf, WIDTH * HEIGHT * 2);
					fetchedDepth = YES;
				} else if (rs2_is_frame_extendable_to(frame, RS2_EXTENSION_VIDEO_FRAME, &e)) {
					const void *buf = rs2_get_frame_data(frame, &e);
					check_error(e);
					if (params.mirrorOn) for (int i = 0; i < HEIGHT; i ++) {
						const uint32 *src = (const uint32 *)buf + i * WIDTH;
						uint32 *dst = colorData + i * WIDTH;
						for (int j = 0; j < WIDTH; j ++) dst[WIDTH - 1 - j] = src[j];
					} else memcpy(colorData, buf, WIDTH * HEIGHT * 4);
					fetchedColor = YES;
				}
				rs2_release_frame(frame);
			}
			rs2_release_frame(frames);
			if (index_of_frame >= num_of_frames) num_of_frames = 0;
		}
		procedure(delegateObject, depthData, colorData);
	} @catch (NSException *exc) { err_msg(exc, YES); result = NO; }
	return result;
}
void rs_stop(void) {
	rs2_error *e = NULL;
    rs2_pipeline_stop(pipeline, &e);
    check_error(e);
	if (depthData != NULL) {
		free(depthData); depthData = NULL;
		free(colorData); colorData = NULL;
	}
}
void rs_close(void) {
	rs2_delete_config(config);
	rs2_delete_pipeline(pipeline);
	rs2_delete_pipeline_profile(pipeline_profile);
	rs2_delete_device(dev);
	rs2_delete_device_list(device_list);
	rs2_delete_context(ctx);
}
