//
//  MyShader.metal
//  BOIDS_Analysis1
//
//  Created by Tatsuo Unemi on 2024/11/24.
//

#include "ShaderHeader.metal"

float2 map3D_to_2D(float3 p, float3 size, float2 camPose) {
	return (p.xy - size.xy / 2.) / size.xy * 2.
		* camPose.x / (camPose.x + p.z) * camPose.y;
}
// for background and single color plane
typedef struct {
	float4 position [[position]];
	float3 p;
} VertexOut;

// for paper plane
kernel void makeShape(constant Agent *pop, constant float *agntSz,
	device float3 *shapes, device float3 *shadows, uint index [[thread_position_in_grid]]) {
	Agent a = pop[index];
	float2 t = normalize(a.v.xz), p = normalize(float2(length(a.v.xz), a.v.y));
	float3x3 mx = {{t.x*p.x,-t.x*p.y,-t.y}, {p.y,p.x,0}, {t.y*p.x,-t.y*p.y,t.x}};
	const float3 sh[] = {{2,0,0},{-1,0,-1},{-1,0,1}, {2,0,0},{-1,0,0},{-1,-1,0}};
	for (int i = 0; i < 3; i ++)
		shapes[index * 6 + i] = shadows[index * 3 + i] = a.p + sh[i] * *agntSz * mx;
	for (int i = 3; i < 6; i ++)
		shapes[index * 6 + i] = a.p + sh[i] * *agntSz * mx;
}
vertex VertexOut vertexShape(uint vertexID [[vertex_id]],
	constant float3 *size, constant float2 *camPose, constant float3 *vertices) {
	VertexOut out;
	float3 v = vertices[vertexID];
	out.position = float4(map3D_to_2D(v, *size, *camPose), 0., 1.);
	out.p = v / *size;
	return out;
}
fragment float4 fragmentShape(constant float4 *col,
	VertexOut in [[stage_in]]) {
	float a = in.p.z * col[1].a;
	return float4(col[0].rgb * (1. - a) + col[1].rgb * a, 1.);
}
// colorful paper plane
float3 hsb2rgb0(float3 hsb) {
	float c = (2. * hsb.y + 1.) * hsb.z;
	if (hsb.x < 1./3.) {
		float a = hsb.x * 3.;
		return float3((1. - a) * c, a * c, 0.);
	} else if (hsb.x < 2./3.) {
		float a = (hsb.x - 1./3.) * 3.;
		return float3(0., (1. - a) * c, a * c);
	} else {
		float a = (hsb.x - 2./3.) * 3.;
		return float3(a * c, 0., (1. - a) * c);
	}
}
float3 hsb2rgb(float3 hsb) {
	if (hsb.z < 1./3.) return hsb2rgb0(hsb);
	else if (hsb.z < 2./3.) {
		float3 rgb = hsb2rgb0(float3(hsb.xy, 1./3.));
		float3 cmy = 1. - hsb2rgb0(float3(fmod(hsb.x + .5, 1.), hsb.y, 1./3.));
		float a = hsb.z * 3. - 1.;
		return rgb * (1. - a) + cmy * a;
	} else return 1. - hsb2rgb0(float3(fmod(hsb.x + .5, 1.), hsb.y, 1. - hsb.z));
}
typedef struct {
	float4 position [[position]];
	float3 p, v;
	uint aIdx;
} VertexOutColorFul;
vertex VertexOutColorFul vertexColorful(uint vertexID [[vertex_id]],
	constant float3 *size, constant float2 *camPose, constant float3 *vertices,
	constant Agent *pop, constant uint *idxs, constant long *popSz) {
	VertexOutColorFul out;
	uint aIdx = out.aIdx = idxs[*popSz - 1 - vertexID / 6], vIdx = vertexID % 6;
	float3 v = vertices[aIdx * 6 + vIdx];
	out.position = float4(map3D_to_2D(v, *size, *camPose), 0., 1.);
	out.p = v / *size;
	v = pop[aIdx].v;
	float len = length(v);
	v = normalize(v);
	out.v = float3((atan2(v.z, v.x) / M_PI_F + 1.) / 2., len * 3., (v.y + 1.) / 2.);
	return out;
}
fragment float4 fragmentColorful(constant float4 *col, constant float4 *ptCol,
	VertexOutColorFul in [[stage_in]]) {
	float a = in.p.z * col[1].a;
	bool2 ph = col[0].yz < .5;
	float2 sbMin = select(1. - (1. - col[0].yz) * 2., 0., ph),
		sbMax = select(1., col[0].yz * 2., ph);
	float3 vCol = hsb2rgb(float3(fmod(col[0].x + in.v.x, 1.),
		in.v.yz * (sbMax - sbMin) + sbMin));
	float4 ptc = ptCol[in.aIdx];
//	vCol += (ptc.rgb - vCol) * min(1., ptc.a * 10.);
	if (ptc.a > 0.) vCol = ptc.rgb;
	return float4(vCol * (1. - a) + col[1].rgb * a, col[0].a);
}
// shadow of paper plane
typedef struct {
	float4 position [[position]];
	float y;
} VertexOutShadow;
vertex VertexOutShadow vertexShadow(uint vertexID [[vertex_id]],
	constant float3 *size, constant float2 *camPose, constant float3 *vertices) {
	VertexOutShadow out;
	float3 v = vertices[vertexID];
	out.y = v.y / size->y;
	v.y = 0.;
	out.position = float4(map3D_to_2D(v, *size, *camPose), 0., 1.);
    return out;
}
fragment float4 fragmentShadow(constant float *opacity,
	VertexOutShadow in [[stage_in]]) {
    return float4(0., 0., 0., (1. - in.y) * .8 * *opacity);
}

// for blob
kernel void makeSquare(constant Agent *pop, constant float *agntSz,
	device float3 *shapes, uint index [[thread_position_in_grid]]) {
	const float3 sh[] = {{-1,-1,0},{-1,1,0},{1,-1,0},{1,1,0}};
	float3 p = pop[index].p;
	for (int i = 0; i < 4; i ++)
		shapes[index * 4 + i] = p + sh[i] * 2. * *agntSz;
}
typedef struct {
	float4 position [[position]];
	float2 center;
	float radius;
} VertexOutBlob;
vertex VertexOutBlob vertexBlob(uint vertexID [[vertex_id]],
	constant float3 *size, constant float2 *camPose, constant float3 *vertices) {
	VertexOutBlob out;
	out.position = float4(map3D_to_2D(vertices[vertexID], *size, *camPose), 0., 1.);
	uint ix = (vertexID / 4) * 4;
	float2 p1 = map3D_to_2D(vertices[ix], *size, *camPose);
	float2 p2 = map3D_to_2D(vertices[ix + 3], *size, *camPose);
	out.center = (p1 + p2) / 2.;
	out.radius = (p2.x - p1.x) / 2.;
    return out;
}
fragment float4 fragmentBlob(constant float4 *col, constant float2 *vSize,
	VertexOutBlob in [[stage_in]]) {
	float2 vp = in.position.xy / *vSize * 2. - 1.;
	vp.y *= -1.;
	return float4(col->rgb, col->a *
		(1. - length((vp - in.center) * float2(1., 9./16.)) / in.radius));
}

// for points
kernel void makePointShape(constant float3 *points, constant float *agntSz,
	device float3 *shapes, uint index [[thread_position_in_grid]]) {
	const float3 sh[] = {{-1,-1,-.5},{1,-1,-.5},{0,1.5,.5}};
	float3 p = points[index];
	for (int i = 0; i < 3; i ++)
		shapes[index * 3 + i] = p + sh[i] * 2. * *agntSz;
}
typedef struct {
	float4 position [[position]];
	float z;
	float3 rgb;
} VertexOutPoint;
vertex VertexOutPoint vertexPoint(uint vertexID [[vertex_id]],
	constant float3 *size, constant float2 *camPose, constant float3 *vertices,
	constant PointInfo *ptInfo) {
	VertexOutPoint out;
	float3 v = vertices[vertexID];
	out.position = float4(map3D_to_2D(v, *size, *camPose), 0., 1.);
	out.z = v.z / size->z;
	PointInfo pt = ptInfo[vertexID / 3];
	out.rgb = float3(pt.c.r, pt.c.g, pt.c.b) / 255.;
	return out;
}
fragment float4 fragmentPoint(constant float4 *fog,
	VertexOutPoint in [[stage_in]]) {
	float a = in.z * fog->a;
	return float4(in.rgb * (1. - a) + fog->rgb * a, 1.);
}
