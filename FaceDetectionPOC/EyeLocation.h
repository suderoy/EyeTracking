//
//  EyeLocation.h
//  EyeTracking
//
//  Created by Sudeshna Roy on 16/03/13.
//  Copyright (c) 2013 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface EyeLocation : NSObject{

    int lpx;
    int lpy;
    
    int rpx;
    int rpy;
}
@property int lpx;
@property int lpy;

@property int rpx;
@property int rpy;

@end
