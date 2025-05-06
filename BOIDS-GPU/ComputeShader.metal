//
//  ComputeShader.metal
//  BOIDS GPU
//
//  Created by Tatsuo Unemi on 2024/12/08.
//

#include "ShaderHeader.metal"
#define MaxElev (M_PI_F/6.)
#define MinDist 1e-3

kernel void moveAgent(constant Agent *popOrg, device Agent *popNew, device float4 *colors,
	constant Cell *cells, constant uint *idxs, constant Task *tasks,
	constant PointInfo *points, constant PtCell *ptCells, constant short *ffCells,
	constant PointParams *ptPrm, constant Params *params,
	uint index [[thread_position_in_grid]]) {

	Task tsk = tasks[index];
	uint aIdx = tsk.idx, nPt = 0;
	Agent a = popOrg[aIdx];
	float3 WS = (float3)(ptPrm->cellDim * ptPrm->cellUnit) * ptPrm->cellSize,
		cc = 0., cp = 0., colp = 0., aa = 0.;
	float sumDI = 0., sumDP = 0., dt = ptPrm->deltaTime;
// repulsion forces against walls
	float3 ff = params->avoid * 8. *
		(pow(max(MinDist, a.p), -2.) - pow(max(MinDist, WS - a.p), -2.));
// check neighbors
	float3 nav = normalize(a.v);
	for (uint i = 0; i < tsk.n; i ++) {
		// effects with other agents
		Cell c = cells[tsk.cIdxs[i]];
		for (uint j = 0; j < c.n && j < ptPrm->maxNInCell; j ++) {
			uint bIdx = idxs[c.start + j];
			if (bIdx == aIdx) continue;
			Agent b = popOrg[bIdx];
			float3 dv = a.p - b.p;
			float d = length(dv);
			if (d > params->sightD) continue;
			float3 ndv = normalize(dv);
			if (distance(nav, ndv) < 2. - params->sightA) continue;
			if (d < MinDist) d = MinDist;
			ff += ndv * params->avoid / (d * d);
			cc += b.p / d;
			aa += b.v / d;
			sumDI += 1. / d;
		}
		// effects with points (attractants)
		PtCell pc = ptCells[tsk.cIdxs[i]];
		for (uint j = 0; j < pc.n; j ++) {
			PointInfo ptInfo = points[pc.start + j];
			float3 dv = ptInfo.p - a.p;
			float d = length(dv);
			if (d > params->sightD) continue;
			float3 ndv = normalize(dv);
			if (distance(nav, ndv) < 2. - params->sightA) continue;
			if (d < MinDist) d = MinDist;
			cp += ptInfo.p / d;
			colp += float3(ptInfo.c.r, ptInfo.c.g, ptInfo.c.b) / d / 255.;
			nPt ++;
			sumDP += 1. / d;
		}
	}
	colors[aIdx] = (sumDP > 0.)? float4(colp / sumDP, sumDP / nPt) : 0.;
	ff += (sumDP > 0.)? (cp / sumDP - a.p) * params->attract * 7.5e-4 :
		(sumDI > 0.)? (cc / sumDI - a.p) * params->cohide : 0.;
	if (sumDI > 0. && sumDP == 0.) ff += aa / sumDI * params->align;
// long distance effects with points via force field
	if (sumDP == 0. && ptPrm->nPoints > 0) {
		int3 dm = ptPrm->cellDim, cIdx = clamp(int3(a.p / WS * float3(dm)), 0, dm - 1);
		int ffCIdx = (cIdx.z * dm.y + cIdx.y) * dm.x + cIdx.x, fIdx = ffCells[ffCIdx],
			cu = ptPrm->cellUnit;
		int3 pdm = dm * cu,
			pxv = int3(fIdx % dm.x, (fIdx / dm.x) % dm.y, fIdx / (dm.y * dm.x)) * cu;
		float coef;
		if (ffCIdx == fIdx) coef = 1e-5;
		else {
			int fdf = (aIdx + index) % (cu * cu * cu);
			pxv += int3(fdf % cu, (fdf / cu) % cu, fdf / (cu * cu));
			coef = 1e-3;
		}
		PtCell pc = ptCells[(pxv.z * pdm.y + pxv.y) * pdm.x + pxv.x];
		float3 npv = (pc.n > 0)? points[pc.start + aIdx % pc.n].p :
			(float3(pxv) + .5) * ptPrm->cellSize;
		npv = normalize(npv - a.p);
		if (distance(nav, npv) > 2. - params->sightA)
			ff += npv * params->attract * coef;
	}
// modify the velocity
	float3 newV = (a.v + ff / params->mass * dt) * pow(1. - params->fric, dt);
	float v = length(newV);
	float tilt = atan2(newV.y, length(newV.xz));
	if (abs(tilt) > MaxElev) {
		newV.xz *= cos(MaxElev) / cos(tilt);
		tilt = (tilt > 0.)? MaxElev : -MaxElev;
		newV.y = v * tilt;
	}
	float maxV = params->maxV;// * (1. - tilt * .5);
	if (sumDP > 0.) maxV *= .8;
	if (v > maxV) newV *= maxV / v;
	else if (v < MinDist) newV = float3(params->minV)
		* select(float3(1.), float3(-1.), a.p > WS / 2.);
	else if (v < params->minV) newV *= params->minV / v;
	a.p += (a.v + newV) / 2. * dt;	// move
// check wall boundaries
	newV *= select(float3(-1.), float3(1.), a.p > 0. && a.p < WS);
	a.p = select(- a.p, select(WS * 2. - a.p, a.p, a.p < WS), a.p > 0.);
//
	a.v = newV;
	int3 rndS = {10000, 8888, 7777};
	a.p = select(a.p, (float3(int3(aIdx) % rndS) / float3(rndS) * .8 + .1) * WS, any(isnan(a.p)));
	a.v = select(a.v, normalize(float3(int3(aIdx) % rndS) / float3(rndS)) * .001, any(isnan(a.v)));
	popNew[aIdx] = a;
}
