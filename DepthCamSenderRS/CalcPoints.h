//
//  CalcPoints.h
//  DepthCamSenderRS
//
//  Created by Tatsuo Unemi on 2025/02/11.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CalcPoints : NSObject
@property NSMutableData *densityMapData;
- (NSMutableData *)calcPointsFromDepth:(uint16 *)frameData color:(uint32 *)colorData;
@end

NS_ASSUME_NONNULL_END
