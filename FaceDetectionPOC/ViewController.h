//
//  ViewController.h
//  EyeTracking
//
//  Created by Sudeshna Roy on 16/03/13.
//  Copyright (c) 2013 __MyCompanyName__. All rights reserved.
//
//  Modified from Jeroen Trappers on 30/04/12.
//  Copyright (c) 2012 iCapps. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

@interface ViewController : UIViewController 
    <UIGestureRecognizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate>

@property (nonatomic, weak) IBOutlet UIView *previewView;
@property (weak, nonatomic) IBOutlet UIView *visualView;
@property (weak, nonatomic) IBOutlet UIButton *calibrateButton;
@property (weak, nonatomic) IBOutlet UIImageView *RightEyeView;

@property (weak, nonatomic) IBOutlet UIImageView *TestImageView;
@property (weak, nonatomic) IBOutlet UIImageView *LeftEyeView;
@property (weak, nonatomic) IBOutlet UIButton *look;
- (IBAction)Calibrate:(id)sender;
@end