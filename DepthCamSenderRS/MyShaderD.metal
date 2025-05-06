//
//  MyShaderD.metal
//  DepthCamSenderRS
//
//  Created by Tatsuo Unemi on 2025/02/10.
//

#include <metal_stdlib>
using namespace metal;
#define WIDTH 640
#define HEIGHT 480

kernel void calcGradient(constant ushort *z16, device float *result,
	uint index [[thread_position_in_grid]]) {
	int x = index % WIDTH, y = index / WIDTH;
	if (x == 0 || x == WIDTH-1 || y == 0 || y >= HEIGHT-1)
		{ result[index] = 0.; return; }
	float3 z[3] = {
		float3(z16[index - WIDTH - 1], z16[index - WIDTH], z16[index - WIDTH + 1]),
		float3(z16[index - 1], z16[index], z16[index + 1]),
		float3(z16[index + WIDTH - 1], z16[index + WIDTH], z16[index + WIDTH + 1]),
	};
	float g = length(float2(
		(z[0].z - z[0].x + z[2].z - z[2].x) + (z[1].z - z[1].x) * 3.,
		(z[2].z - z[0].z + z[2].x - z[0].x) + (z[2].y - z[0].y) * 3.));
	result[index] = (g > 1e3)? 0. : g * z[1].y;
}
