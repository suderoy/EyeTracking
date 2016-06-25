//
//  ViewController.m
//  EyeTracking
//
//  Created by Sudeshna Roy on 16/03/13.
//  Copyright (c) 2013 __MyCompanyName__. All rights reserved.
//
//  Modified from Jeroen Trappers on 30/04/12.
//  Copyright (c) 2012 iCapps. All rights reserved.
//
//cpp header for pupil detection
#include "constants.h"
#include "findEyeCenter.h"
#include "findEyeCorner.h"

#include <string>
#include <cstring>
#include <queue>

#import "ViewController.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>
#import <AssertMacros.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "UIImage+OpenCV.h"

#import "EyeLocation.h"

#define THRESHOLD 13
#define FACTORX 0.75
#define FACTORY 1

#define NORMALIZE_EYE_FRAME 1000

#define N 4
#define M 2
#define GAZE_VARIATION_THRESHOLD 6300

float xMeanPrevLeft, yMeanPrevLeft;
float xMeanPrevRight, yMeanPrevRight;

static CGFloat DegreesToRadians(CGFloat degrees) {return degrees * M_PI / 180;};
int count = 0;

int c = 0;

NSMutableArray *locationQueue;


@interface ViewController (){
    
    CGPoint leftEyePointWas;
    CGPoint rightEyePointWas;
    
    CGPoint leftEyePupilWas;
    CGPoint rightEyePupilWas;
    
    CGRect leftRect;
    CGRect rightRect;
    
    float depth;
    float distBetweenEyesWas;
    
    CGPoint lookingAt;
}

@property (nonatomic) BOOL isUsingFrontFacingCamera;
@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic, strong) CIDetector *faceDetector;


- (void)setupAVCapture;
- (void)teardownAVCapture;
- (void)drawFaces:(NSArray *)features 
      forVideoBox:(CGRect)videoBox 
      orientation:(UIDeviceOrientation)orientation ofImage:(UIImage *)img;
- (void)findGazeLocationLeftPupil:(CGPoint)leftPupil rightPupil:(CGPoint)rightPupil leftEye:(CGPoint)le rightEye:(CGPoint)re;

@end

@implementation ViewController

@synthesize videoDataOutput = _videoDataOutput;
@synthesize videoDataOutputQueue = _videoDataOutputQueue;

@synthesize previewView = _previewView;
@synthesize previewLayer = _previewLayer;

@synthesize faceDetector = _faceDetector;

@synthesize isUsingFrontFacingCamera = _isUsingFrontFacingCamera;

-(UIImage*) rotate:(UIImage*) src andOrientation:(UIImageOrientation)orientation
{
    UIGraphicsBeginImageContext(src.size);
    
    CGContextRef context=(UIGraphicsGetCurrentContext());
    
    if (orientation == UIImageOrientationRight) {
        CGContextRotateCTM (context, 90/180*M_PI) ;
    } else if (orientation == UIImageOrientationLeft) {
        CGContextRotateCTM (context, -90/180*M_PI);
    } else if (orientation == UIImageOrientationDown) {
        // NOTHING
    } else if (orientation == UIImageOrientationUp) {
        CGContextRotateCTM (context, 90/180*M_PI);
    }
    
    [src drawAtPoint:CGPointMake(0, 0)];
    UIImage *img=UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
    
}

- (void)setupAVCapture
{
	NSError *error = nil;
	
	AVCaptureSession *session = [[AVCaptureSession alloc] init];
	if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone || [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad){
	    //[session setSessionPreset:AVCaptureSessionPreset640x480];
        [session setSessionPreset:AVCaptureSessionPreset640x480];
	} else {
	    [session setSessionPreset:AVCaptureSessionPresetPhoto];
	}
    
    // Select a video device, make an input
	AVCaptureDevice *device;
	
    AVCaptureDevicePosition desiredPosition = AVCaptureDevicePositionFront;
	
    // find the front facing camera
	for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo]) {
		if ([d position] == desiredPosition) {
			device = d;
            self.isUsingFrontFacingCamera = YES;
			break;
		}
	}
    // fall back to the default camera.
    if( nil == device )
    {
        self.isUsingFrontFacingCamera = NO;
        device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    }
    
    // get the input device
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    
	if( !error ) {
        
        // add the input to the session
        if ( [session canAddInput:deviceInput] ){
            [session addInput:deviceInput];
        }
        
        
        // Make a video data output
        self.videoDataOutput = [[AVCaptureVideoDataOutput alloc] init];
        
        // we want BGRA, both CoreGraphics and OpenGL work well with 'BGRA'
        NSDictionary *rgbOutputSettings = [NSDictionary dictionaryWithObject:
                                           [NSNumber numberWithInt:kCMPixelFormat_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
        [self.videoDataOutput setVideoSettings:rgbOutputSettings];
        //[self.videoDataOutput setMinFrameDuration:CMTimeMake(6, 1)];
        [self.videoDataOutput setAlwaysDiscardsLateVideoFrames:YES]; // discard if the data output queue is blocked
        
        // create a serial dispatch queue used for the sample buffer delegate
        // a serial dispatch queue must be used to guarantee that video frames will be delivered in order
        // see the header doc for setSampleBufferDelegate:queue: for more information
        self.videoDataOutputQueue = dispatch_queue_create("VideoDataOutputQueue", DISPATCH_QUEUE_SERIAL);
        [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
        
        if ( [session canAddOutput:self.videoDataOutput] ){
            [session addOutput:self.videoDataOutput];
        }
        
        // get the output for doing face detection.
        [[self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo] setEnabled:YES]; 

        self.previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:session];
        self.previewLayer.backgroundColor = [[UIColor blackColor] CGColor];
        self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        
        CALayer *rootLayer = [self.previewView layer];
        [rootLayer setMasksToBounds:YES];
        [self.previewLayer setFrame:[rootLayer bounds]];
        [rootLayer addSublayer:self.previewLayer];
        [session startRunning];
        rgbOutputSettings = nil;
    }
	session = nil;
	if (error) {
		UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:
                            [NSString stringWithFormat:@"Failed with error %d", (int)[error code]]
                                               message:[error localizedDescription]
										      delegate:nil 
								     cancelButtonTitle:@"Dismiss" 
								     otherButtonTitles:nil];
		[alertView show];
		[self teardownAVCapture];
	}
}

// clean up capture setup
- (void)teardownAVCapture
{
	self.videoDataOutput = nil;
	if (self.videoDataOutputQueue) {
        //uncomment this for iOS version below 6.0
		//dispatch_release(self.videoDataOutputQueue);
    }
	[self.previewLayer removeFromSuperlayer];
	self.previewLayer = nil;
}


// utility routine to display error aleart if takePicture fails
- (void)displayErrorOnMainQueue:(NSError *)error withMessage:(NSString *)message
{
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		UIAlertView *alertView = [[UIAlertView alloc] 
                initWithTitle:[NSString stringWithFormat:@"%@ (%d)", message, (int)[error code]]
                      message:[error localizedDescription]
				     delegate:nil 
		    cancelButtonTitle:@"Dismiss" 
		    otherButtonTitles:nil];
        [alertView show];
	});
}


// find where the video box is positioned within the preview layer based on the video size and gravity
+ (CGRect)videoPreviewBoxForGravity:(NSString *)gravity 
                          frameSize:(CGSize)frameSize 
                       apertureSize:(CGSize)apertureSize
{
    CGFloat apertureRatio = apertureSize.height / apertureSize.width;
    CGFloat viewRatio = frameSize.width / frameSize.height;
    
    CGSize size = CGSizeZero;
    if ([gravity isEqualToString:AVLayerVideoGravityResizeAspectFill]) {
        if (viewRatio > apertureRatio) {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        } else {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResizeAspect]) {
        if (viewRatio > apertureRatio) {
            size.width = apertureSize.height * (frameSize.height / apertureSize.width);
            size.height = frameSize.height;
        } else {
            size.width = frameSize.width;
            size.height = apertureSize.width * (frameSize.width / apertureSize.height);
        }
    } else if ([gravity isEqualToString:AVLayerVideoGravityResize]) {
        size.width = frameSize.width;
        size.height = frameSize.height;
    }
	
	CGRect videoBox;
	videoBox.size = size;
	if (size.width < frameSize.width)
		videoBox.origin.x = (frameSize.width - size.width) / 2;
	else
		videoBox.origin.x = (size.width - frameSize.width) / 2;
	
	if ( size.height < frameSize.height )
		videoBox.origin.y = (frameSize.height - size.height) / 2;
	else
		videoBox.origin.y = (size.height - frameSize.height) / 2;
    
	return videoBox;
}

// called asynchronously as the capture output is capturing sample buffers, this method asks the face detector
// to detect features and for each draw the green border in a layer and set appropriate orientation
- (void)drawFaces:(NSArray *)features 
      forVideoBox:(CGRect)clearAperture 
      orientation:(UIDeviceOrientation)orientation ofImage:(UIImage *)img
{
	NSArray *sublayers = [NSArray arrayWithArray:[self.previewLayer sublayers]];
	NSInteger sublayersCount = [sublayers count], currentSublayer = 0;
	NSInteger featuresCount = [features count], currentFeature = 0;
	
	[CATransaction begin];
	[CATransaction setValue:(id)kCFBooleanTrue forKey:kCATransactionDisableActions];

    
	// hide all the face layers
	for ( CALayer *layer in sublayers ) {
		if ( [[layer name] isEqualToString:@"FaceLayer"] )
			[layer setHidden:YES];
        
        if ( [[layer name] isEqualToString:@"LeftEyeLayer"] )
			[layer setHidden:YES];
        
        if ( [[layer name] isEqualToString:@"RightEyeLayer"] )
			[layer setHidden:YES];
        
        if ( [[layer name] isEqualToString:@"LeftPupilLayer"] )
			[layer setHidden:YES];
        
        if ( [[layer name] isEqualToString:@"RightPupilLayer"] )
			[layer setHidden:YES];
	}
	
	if ( featuresCount == 0 ) {
		[CATransaction commit];
		return; // early bail.
	}
    
	CGSize parentFrameSize = [self.previewView frame].size;
	NSString *gravity = [self.previewLayer videoGravity];
	BOOL isMirrored = [self.previewLayer isMirrored];
	CGRect previewBox = [ViewController videoPreviewBoxForGravity:gravity 
                                                        frameSize:parentFrameSize 
                                                     apertureSize:clearAperture.size];
    
	for ( CIFaceFeature *ff in features ) {
		// find the correct position for the square layer within the previewLayer
		// the feature box originates in the bottom left of the video frame.
		// (Bottom right if mirroring is turned on)
		CGRect faceRect = [ff bounds];
        CGPoint leftEyePoint, rightEyePoint;
        
        //float originalFaceWidth = faceRect.size.width;
		// flip preview width and height
		CGFloat temp = faceRect.size.width;
		faceRect.size.width = faceRect.size.height;
		faceRect.size.height = temp;
        
        float originalFaceWidth = faceRect.size.width;
        
		temp = faceRect.origin.x;
		faceRect.origin.x = faceRect.origin.y;
		faceRect.origin.y = temp;
		// scale coordinates so they fit in the preview box, which may be scaled
		CGFloat widthScaleBy = previewBox.size.width / clearAperture.size.height;
		CGFloat heightScaleBy = previewBox.size.height / clearAperture.size.width;
		faceRect.size.width *= widthScaleBy;
		faceRect.size.height *= heightScaleBy;
		faceRect.origin.x *= widthScaleBy;
		faceRect.origin.y *= heightScaleBy;
        
        float faceWidth = faceRect.size.width;
        CGImageRef cgImg = img.CGImage;
        
        //get the pupil locaion
        cv::Point leftPupil = cv::Point(0,0);
        cv::Point rightPupil = cv::Point(0,0);
        
        cv::Rect rect;
        
        //get eye positions
        if(ff.hasLeftEyePosition)
        {
            leftEyePoint =ff.leftEyePosition;
            
            if(cgImg){
                
                //calculate eye size
                float y = img.size.height - leftEyePoint.y;
                rect = cv::Rect(y - originalFaceWidth*0.12, leftEyePoint.x-originalFaceWidth*0.12, originalFaceWidth*0.24, originalFaceWidth*0.24);
                
                //get the eye cut out from face
                CGImageRef cgim = CGImageCreateWithImageInRect(cgImg, CGRectMake(leftEyePoint.x-originalFaceWidth*0.12, y - originalFaceWidth*0.12, originalFaceWidth*0.24, originalFaceWidth*0.24));
                UIImage *leftEyeim = [UIImage imageWithCGImage:cgim];
                [self.LeftEyeView performSelectorOnMainThread:@selector(setImage:) withObject:leftEyeim waitUntilDone:YES];
                
                
                cv::Mat leftEyeMat = [leftEyeim CVGrayscaleMat];
                CGImageRelease(cgim);
                leftEyeim = nil;
                
//                NSString *str = [NSString stringWithFormat:@"Documents/LeftEye%d.BMP", c];
//                NSString  *jpgPath = [NSHomeDirectory() stringByAppendingPathComponent:str];
//                
//                const char* cPath = [jpgPath cStringUsingEncoding:NSMacOSRomanStringEncoding];
//                
//                const std::string newPaths = (const std::string)cPath;
//                
//                //Save as Bitmap to Documents-Directory
//                cv::imwrite(newPaths, leftEyeMat);

//                c++;
                
                //Now find eye pupil
                findEyeCenter(leftEyeMat,rect, leftPupil);
                leftEyeMat.release();
                
//                //get rid of eyebrow
//                if(leftPupil.y < originalFaceWidth*0.03)
//                    leftPupil = cv::Point(leftEyePupilWas.x, leftEyePupilWas.y);
            
                //NSLog(@"\n\n left pupil %d, %d \n", leftPupil.x, leftPupil.y);
                // get corner regions
                cv::Rect leftCornerRegion = rect;
                leftCornerRegion.width -= leftPupil.x;
                leftCornerRegion.x += leftPupil.x;
                leftCornerRegion.height /= 2;
                leftCornerRegion.y += leftCornerRegion.height / 2;

               
                //note here pupil has been found on rotated eye but the rect has not been not rotated yet
            }
            //leftPupil = cv::Point(faceWidth*0.12, faceWidth*0.12);
            
            //Now get the position right
            //NSLog(@"Left eye without scale %@",NSStringFromCGPoint(leftEyePoint));
            temp = leftEyePoint.x;
            leftEyePoint.x = leftEyePoint.y;
            leftEyePoint.y = temp;
            leftEyePoint.x *= widthScaleBy;
            leftEyePoint.y *= heightScaleBy;
            
            //pupils r already rotated, just scale them
//            leftPupil.x *= widthScaleBy;
//            leftPupil.y *= heightScaleBy;
        }
        
        
        if(ff.hasRightEyePosition)
        {
            rightEyePoint =ff.rightEyePosition;
            
            if(cgImg){
                float y = img.size.height - rightEyePoint.y;
                //get pupil-----------------------
                //keep these two rect in sync
                rect = cv::Rect(y - originalFaceWidth*0.12, rightEyePoint.x-originalFaceWidth*0.12, originalFaceWidth*0.24, originalFaceWidth*0.24);
                
                CGImageRef cgim = CGImageCreateWithImageInRect(cgImg, CGRectMake(rightEyePoint.x-originalFaceWidth*0.12, y - originalFaceWidth*0.12, originalFaceWidth*0.24, originalFaceWidth*0.24));
                
                UIImage *rightEyeim = [UIImage imageWithCGImage:cgim];
                [self.RightEyeView performSelectorOnMainThread:@selector(setImage:) withObject:rightEyeim waitUntilDone:YES];
                
//                NSString *str = [NSString stringWithFormat:@"Documents/RightEye%d.jpg", count];
//                NSString  *jpgPath = [NSHomeDirectory() stringByAppendingPathComponent:str];
//                
//                // Write a UIImage to JPEG with minimum compression (best quality)
//                // The value 'image' must be a UIImage object
//                // The value '1.0' represents image compression quality as value from 0.0 to 1.0
//                [UIImageJPEGRepresentation(rightEyeim, 1.0) writeToFile:jpgPath atomically:YES];
                
                cv::Mat rightEyeMat = [rightEyeim CVGrayscaleMat];
                CGImageRelease(cgim);
                rightEyeim = nil;
                
//                NSString *str = [NSString stringWithFormat:@"Documents/RightEye%d.BMP", c];
//                NSString  *jpgPath = [NSHomeDirectory() stringByAppendingPathComponent:str];
//
//                const char* cPath = [jpgPath cStringUsingEncoding:NSMacOSRomanStringEncoding];
//                
//                const std::string newPaths = (const std::string)cPath;
//                
//                //Save as Bitmap to Documents-Directory
//                cv::imwrite(newPaths, rightEyeMat);
//                c++;
                
                findEyeCenter(rightEyeMat,rect,rightPupil);
                rightEyeMat.release();

//                //get rid of eyebrow
//                if(rightPupil.y < originalFaceWidth*0.03)
//                    rightPupil = cv::Point(rightEyePupilWas.x, rightEyePupilWas.y);
                
                //NSLog(@"\n\n right pupil %d, %d\n", rightPupil.x, rightPupil.y);
                cv::Rect rightCornerRegion(rect);
                rightCornerRegion.width = rightPupil.x;
                rightCornerRegion.x += rightPupil.x;					//LINE ADDED -- DEBUG PENDING
                rightCornerRegion.height /= 2;
                rightCornerRegion.y += rightCornerRegion.height / 2;
                
            }
            //rightPupil = cv::Point(faceWidth*0.12, faceWidth*0.12);
            
            //Now get the position right
            //NSLog(@"Right eye without scale %@",NSStringFromCGPoint(rightEyePoint));
            temp = rightEyePoint.x;
            rightEyePoint.x = rightEyePoint.y;
            rightEyePoint.y = temp;
            rightEyePoint.x *= widthScaleBy;
            rightEyePoint.y *= heightScaleBy;
            
            //pupils r already rotated, just scale them
//            rightPupil.x *= widthScaleBy;
//            rightPupil.y *= heightScaleBy;
        }
        
        //scale- normalization
        cv::Point leftPupilNormalized = cv::Point(leftPupil.x*NORMALIZE_EYE_FRAME/rect.width, leftPupil.y*NORMALIZE_EYE_FRAME/rect.height);
        cv::Point rightPupilNormalized = cv::Point(rightPupil.x*NORMALIZE_EYE_FRAME/rect.width, rightPupil.y*NORMALIZE_EYE_FRAME/rect.height);
        
        //translation
//        if(leftEyePointWas.x == 0 || leftEyePointWas.y == 0)
//            leftEyePointWas = leftEyePoint;
//        leftPupilNormalized.x +=(leftEyePoint.x - leftEyePointWas.x);
//        leftPupilNormalized.y +=(leftEyePoint.y - leftEyePointWas.y);
//        
//        if(rightEyePointWas.x == 0 || rightEyePointWas.y == 0)
//            rightEyePointWas = rightEyePoint;
//        rightPupilNormalized.x +=(rightEyePoint.x - rightEyePointWas.x);
//        rightPupilNormalized.y +=(rightEyePoint.y - rightEyePointWas.y);
        
        
        if (leftPupilNormalized.x < NORMALIZE_EYE_FRAME*0.1 || leftPupilNormalized.x > NORMALIZE_EYE_FRAME*0.9 ||
            rightPupilNormalized.x < NORMALIZE_EYE_FRAME*0.1 || rightPupilNormalized.x > NORMALIZE_EYE_FRAME*0.9  ||
            leftPupilNormalized.y < NORMALIZE_EYE_FRAME*0.1 || leftPupilNormalized.y > NORMALIZE_EYE_FRAME*0.9 ||
            rightPupilNormalized.y < NORMALIZE_EYE_FRAME*0.1 || rightPupilNormalized.y > NORMALIZE_EYE_FRAME*0.9) {
            
            leftPupilNormalized = cv::Point(leftEyePupilWas.x, leftEyePupilWas.y);
            rightPupilNormalized = cv::Point(rightEyePupilWas.x, rightEyePupilWas.y);
            
            
            
            NSLog(@"\nIGnored\n");
        }
        
        NSLog(@"\n\n leftPupilNormalized pupil %d, %d\n", leftPupilNormalized.x, leftPupilNormalized.y);
        
        NSLog(@"\n\n rightPupilNormalized pupil %d, %d\n", rightPupilNormalized.x, rightPupilNormalized.y);
        
        if(self.look.hidden == NO){
            CGPoint lp = CGPointMake(leftPupilNormalized.x, leftPupilNormalized.y);
            CGPoint rp = CGPointMake(rightPupilNormalized.x, rightPupilNormalized.y);
            
            [self findGazeLocationLeftPupil:lp rightPupil:rp leftEye:leftEyePoint rightEye:rightEyePoint];

        }
        leftEyePupilWas = CGPointMake(leftPupilNormalized.x, leftPupilNormalized.y);
        rightEyePupilWas = CGPointMake(rightPupilNormalized.x, rightPupilNormalized.y);
        
        leftEyePointWas = leftEyePoint;
        rightEyePointWas = rightEyePoint;
        
        //DO NOT Bother
        //The rest of the part is just for the sake of displaying on te big screen dude
		if ( isMirrored ){
            
			faceRect = CGRectOffset(faceRect, previewBox.origin.x + previewBox.size.width - faceRect.size.width - (faceRect.origin.x * 2), previewBox.origin.y);
            
            leftEyePoint.x +=previewBox.origin.x + previewBox.size.width - (leftEyePoint.x * 2);
            leftEyePoint.y += previewBox.origin.y;
            
            rightEyePoint.x +=previewBox.origin.x + previewBox.size.width - (rightEyePoint.x * 2);
            rightEyePoint.y += previewBox.origin.y;

        }
		else{
			faceRect = CGRectOffset(faceRect, previewBox.origin.x, previewBox.origin.y);
            
            leftEyePoint.x += previewBox.origin.x;
            leftEyePoint.y += previewBox.origin.y;
            
            rightEyePoint.x += previewBox.origin.x;
            rightEyePoint.y += previewBox.origin.y;
            
        }
//		NSLog(@"Left eye %@",NSStringFromCGPoint(leftEyePoint));
//        NSLog(@"Right eye %@",NSStringFromCGPoint(rightEyePoint));
//        NSLog(@"\n\n left pupil %d, %d \n\n right pupil %d, %d\n\n", leftPupil.x, leftPupil.y, rightPupil.x, rightPupil.y);

        
		CALayer *featureLayer = nil;
        CALayer *leftEyeLayer = nil;
        CALayer *rightEyeLayer = nil;
        CALayer *leftPupilLayer = nil;
        CALayer *rightPupilLayer = nil;
		
		// re-use an existing layer if possible
		while ( !featureLayer && (currentSublayer < sublayersCount) ) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"FaceLayer"] ) {
				featureLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
        
        while ( !leftEyeLayer && (currentSublayer < sublayersCount) ) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"LeftEyeLayer"] ) {
				leftEyeLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
        
        while ( !rightEyeLayer && (currentSublayer < sublayersCount) ) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"RightEyeLayer"] ) {
				rightEyeLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
        
        while ( !leftPupilLayer && (currentSublayer < sublayersCount) ) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"LeftPupilLayer"] ) {
				leftPupilLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
        
        while ( !rightPupilLayer && (currentSublayer < sublayersCount) ) {
			CALayer *currentLayer = [sublayers objectAtIndex:currentSublayer++];
			if ( [[currentLayer name] isEqualToString:@"RightPupilLayer"] ) {
				rightPupilLayer = currentLayer;
				[currentLayer setHidden:NO];
			}
		}
		
		// create a new one if necessary
		if ( !featureLayer ) {
			featureLayer = [[CALayer alloc]init];
			//featureLayer.contents = (id)self.borderImage.CGImage;
            // add a border around the newly created UIView
            featureLayer.borderWidth = 1;
            featureLayer.borderColor = [[UIColor redColor] CGColor];
			[featureLayer setName:@"FaceLayer"];
			[self.previewLayer addSublayer:featureLayer];
			featureLayer = nil;
		}
		[featureLayer setFrame:faceRect];
        
        // create a new one if necessary
		if ( !leftEyeLayer ) {
			leftEyeLayer = [[CALayer alloc]init];
			
            // add a border around the newly created UIView
            leftEyeLayer.borderWidth = 1;
            leftEyeLayer.borderColor = [[UIColor redColor] CGColor];
			[leftEyeLayer setName:@"LeftEyeLayer"];
			[self.previewLayer addSublayer:leftEyeLayer];
			leftEyeLayer = nil;
		}
        leftRect = CGRectMake(leftEyePoint.x-faceWidth*0.12, leftEyePoint.y-faceWidth*0.12, faceWidth*0.24, faceWidth*0.24);
		[leftEyeLayer setFrame:leftRect];
        
        
        leftPupil.x += leftRect.origin.x;
        leftPupil.y += leftRect.origin.y;
        
        // create a new one if necessary
		if ( !rightEyeLayer ) {
			rightEyeLayer = [[CALayer alloc]init];
			
            // add a border around the newly created UIView
            rightEyeLayer.borderWidth = 1;
            rightEyeLayer.borderColor = [[UIColor redColor] CGColor];
			[rightEyeLayer setName:@"RightEyeLayer"];
			[self.previewLayer addSublayer:rightEyeLayer];
			rightEyeLayer = nil;
		}
        rightRect = CGRectMake(rightEyePoint.x-faceWidth*0.12, rightEyePoint.y-faceWidth*0.12, faceWidth*0.24, faceWidth*0.24);
        [rightEyeLayer setFrame:rightRect];
        
        rightPupil.x += rightRect.origin.x;
        rightPupil.y += rightRect.origin.y;

        if(ff.hasLeftEyePosition)
        {
            
            if ( !leftPupilLayer ) {
                leftPupilLayer = [[CALayer alloc]init];
                
                // add a border around the newly created UIView
                leftPupilLayer.borderWidth = 4;
                leftPupilLayer.borderColor = [[UIColor redColor] CGColor];
                leftPupilLayer.cornerRadius = 2;
                [leftPupilLayer setName:@"LeftPupilLayer"];
                [self.previewLayer addSublayer:leftPupilLayer];
                leftPupilLayer = nil;
            }
            [leftPupilLayer setFrame:CGRectMake(leftPupil.x-4, leftPupil.y-4, 8, 8)];
        }
        if(ff.hasRightEyePosition)
        {
            
            if ( !rightPupilLayer ) {
                rightPupilLayer = [[CALayer alloc]init];
                
                // add a border around the newly created UIView
                rightPupilLayer.borderWidth = 4;
                rightPupilLayer.borderColor = [[UIColor redColor] CGColor];
                rightPupilLayer.cornerRadius = 2;
                [rightPupilLayer setName:@"RightPupilLayer"];
                [self.previewLayer addSublayer:rightPupilLayer];
                rightPupilLayer = nil;
            }
            [rightPupilLayer setFrame:CGRectMake(rightPupil.x-4, rightPupil.y-4, 8, 8)];
        }
                
		switch (orientation) {
			case UIDeviceOrientationPortrait:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(0.))];
				break;
			case UIDeviceOrientationPortraitUpsideDown:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(180.))];
				break;
			case UIDeviceOrientationLandscapeLeft:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(90.))];
				break;
			case UIDeviceOrientationLandscapeRight:
				[featureLayer setAffineTransform:CGAffineTransformMakeRotation(DegreesToRadians(-90.))];
				break;
			case UIDeviceOrientationFaceUp:
			case UIDeviceOrientationFaceDown:
			default:
				break; // leave the layer in its last known orientation
		}
		currentFeature++;
        
	}
	
	[CATransaction commit];
}

- (NSNumber *) exifOrientation: (UIDeviceOrientation) orientation
{
	int exifOrientation;
    /* kCGImagePropertyOrientation values
     The intended display orientation of the image. If present, this key is a CFNumber value with the same value as defined
     by the TIFF and EXIF specifications -- see enumeration of integer constants. 
     The value specified where the origin (0,0) of the image is located. If not present, a value of 1 is assumed.
     
     used when calling featuresInImage: options: The value for this key is an integer NSNumber from 1..8 as found in kCGImagePropertyOrientation.
     If present, the detection will be done based on that orientation but the coordinates in the returned features will still be based on those of the image. */
    
	enum {
		PHOTOS_EXIF_0ROW_TOP_0COL_LEFT			= 1, //   1  =  0th row is at the top, and 0th column is on the left (THE DEFAULT).
		PHOTOS_EXIF_0ROW_TOP_0COL_RIGHT			= 2, //   2  =  0th row is at the top, and 0th column is on the right.  
		PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT      = 3, //   3  =  0th row is at the bottom, and 0th column is on the right.  
		PHOTOS_EXIF_0ROW_BOTTOM_0COL_LEFT       = 4, //   4  =  0th row is at the bottom, and 0th column is on the left.  
		PHOTOS_EXIF_0ROW_LEFT_0COL_TOP          = 5, //   5  =  0th row is on the left, and 0th column is the top.  
		PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP         = 6, //   6  =  0th row is on the right, and 0th column is the top.  
		PHOTOS_EXIF_0ROW_RIGHT_0COL_BOTTOM      = 7, //   7  =  0th row is on the right, and 0th column is the bottom.  
		PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM       = 8  //   8  =  0th row is on the left, and 0th column is the bottom.  
	};
	
	switch (orientation) {
		case UIDeviceOrientationPortraitUpsideDown:  // Device oriented vertically, home button on the top
			exifOrientation = PHOTOS_EXIF_0ROW_LEFT_0COL_BOTTOM;
			break;
		case UIDeviceOrientationLandscapeLeft:       // Device oriented horizontally, home button on the right
			if (self.isUsingFrontFacingCamera)
				exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
			else
				exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
			break;
		case UIDeviceOrientationLandscapeRight:      // Device oriented horizontally, home button on the left
			if (self.isUsingFrontFacingCamera)
				exifOrientation = PHOTOS_EXIF_0ROW_TOP_0COL_LEFT;
			else
				exifOrientation = PHOTOS_EXIF_0ROW_BOTTOM_0COL_RIGHT;
			break;
		case UIDeviceOrientationPortrait:            // Device oriented vertically, home button on the bottom
		default:
			exifOrientation = PHOTOS_EXIF_0ROW_RIGHT_0COL_TOP;
			break;
	}
    return [NSNumber numberWithInt:exifOrientation];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    //if(count%3==0){
        count = 0;
	// get the image
	CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
	CFDictionaryRef attachments = CMCopyDictionaryOfAttachments(kCFAllocatorDefault, sampleBuffer, kCMAttachmentMode_ShouldPropagate);
	CIImage *ciImage = [[CIImage alloc] initWithCVPixelBuffer:pixelBuffer 
                                                      options:(__bridge NSDictionary *)attachments];
	if (attachments) {
		CFRelease(attachments);
    }
    
    // make sure your device orientation is not locked.
	UIDeviceOrientation curDeviceOrientation = [[UIDevice currentDevice] orientation];
    
	NSDictionary *imageOptions = nil;
    
	imageOptions = [NSDictionary dictionaryWithObject:[self exifOrientation:curDeviceOrientation] 
                                               forKey:CIDetectorImageOrientation];
    
	NSArray *features = [self.faceDetector featuresInImage:ciImage 
                                                   options:imageOptions];
    // get the clean aperture
    // the clean aperture is a rectangle that defines the portion of the encoded pixel dimensions
    // that represents image data valid for display.
	CMFormatDescriptionRef fdesc = CMSampleBufferGetFormatDescription(sampleBuffer);
	CGRect cleanAperture = CMVideoFormatDescriptionGetCleanAperture(fdesc, false /*originIsTopLeft == false*/);
    //CFRelease(fdesc);
    
    CIContext *context = [CIContext contextWithOptions:nil];
    CGImageRef cgImage = [context createCGImage:ciImage fromRect:[ciImage extent]];
    UIImage *im = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    
    [self.TestImageView performSelectorOnMainThread:@selector(setImage:) withObject:im waitUntilDone:YES];
        
        
    CGAffineTransform transform = CGAffineTransformMakeRotation(M_PI_2);
    self.TestImageView.transform = transform;
    imageOptions = nil;
    
	dispatch_async(dispatch_get_main_queue(), ^(void) {
		[self drawFaces:features 
            forVideoBox:cleanAperture 
            orientation:curDeviceOrientation ofImage:im];
	});
    
    features = nil;
    im = nil;
    //}
    count++;
}


#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    self.look.hidden = YES;
    
    [[UIDevice currentDevice] beginGeneratingDeviceOrientationNotifications];
    
	[self setupAVCapture];
	NSDictionary *detectorOptions = [[NSDictionary alloc] initWithObjectsAndKeys:CIDetectorAccuracyLow, CIDetectorAccuracy, nil];
	self.faceDetector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:detectorOptions];
    detectorOptions = nil;
    
    locationQueue = [[NSMutableArray alloc] initWithCapacity:4];

}

- ( void )didReceiveMemoryWarning
{
    [ super didReceiveMemoryWarning ];
}
- (void)viewDidUnload
{
    [self setVisualView:nil];
    [self setLook:nil];
    [self setTestImageView:nil];
    [self setLeftEyeView:nil];
    [self setRightEyeView:nil];
    [self setCalibrateButton:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    // e.g. self.myOutlet = nil;
    [self teardownAVCapture];
	self.faceDetector = nil;
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // We support only Portrait.
	return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - IBActions

- (IBAction)Calibrate:(id)sender {
 
    self.calibrateButton.hidden = YES;
    self.calibrateButton.userInteractionEnabled = NO;
    lookingAt = CGPointMake(400, 500);
    self.look.hidden = NO;
    
    //all we are taking in square term, nopoint in doing square root when we are using it as a factor
    
    xMeanPrevLeft = leftEyePupilWas.x;
    yMeanPrevLeft = leftEyePupilWas.y;
    
    distBetweenEyesWas = (leftEyePointWas.x-rightEyePointWas.x)*(leftEyePointWas.x-rightEyePointWas.x) + (leftEyePointWas.y-rightEyePointWas.y)*(leftEyePointWas.y-rightEyePointWas.y);
    
    float depthLeft = (lookingAt.x - leftEyePointWas.x)*(lookingAt.x - leftEyePointWas.x)+(lookingAt.y - leftEyePointWas.y)*(lookingAt.y - leftEyePointWas.y);
    //ideally these should be equal. right?
    float depthright = (lookingAt.x - rightEyePointWas.x)*(lookingAt.x - rightEyePointWas.x)+(lookingAt.y - rightEyePointWas.y)*(lookingAt.y - rightEyePointWas.y);
    
    float avgD = (depthright+depthLeft)/2;
    
    depth = avgD - distBetweenEyesWas/2;
    
    

}

- (void)findGazeLocationLeftPupil:(CGPoint)leftPupil rightPupil:(CGPoint)rightPupil leftEye:(CGPoint)leftEye rightEye:(CGPoint)rightEye{

//    int n = 0;
//    float distX = 0;
    
    EyeLocation *el = [[EyeLocation alloc] init];
    el.lpx = leftPupil.x;
    el.lpy = leftPupil.y;
    el.rpx = rightPupil.x;
    el.rpy = rightPupil.y;
    [locationQueue addObject:el];
    
    
    //////////////////////////////////
    if ([locationQueue count]>=N) {
        
        float meanXLeft = 0;
        for (int i=0; i<N; i++){
            meanXLeft += [[locationQueue objectAtIndex:i] lpx];
        }
        meanXLeft = meanXLeft/N;
        
        float VarXLeft = 0;
        for(int i=0; i<N; i++){
            VarXLeft += (meanXLeft - [[locationQueue objectAtIndex:i] lpx])*(meanXLeft - [[locationQueue objectAtIndex:i] lpx]);
        }
        VarXLeft = VarXLeft/N;
        
        float meanYLeft = 0;
        for (int i=0; i<N; i++){
            meanYLeft += [[locationQueue objectAtIndex:i] lpy];
        }
        meanYLeft = meanYLeft/N;
        
        float VarYLeft = 0;
        for(int i=0; i<N; i++){
            VarYLeft += (meanYLeft - [[locationQueue objectAtIndex:i] lpy])*(meanYLeft - [[locationQueue objectAtIndex:i] lpy]);
        }
        VarYLeft = VarYLeft/N;
        
        float meanXRight = 0;
        for (int i=0; i<N; i++){
            meanXRight += [[locationQueue objectAtIndex:i] rpx];
        }
        meanXRight = meanXRight/N;
        
        float VarXRight = 0;
        for(int i=0; i<N; i++){
            VarXRight += (meanXRight - [[locationQueue objectAtIndex:i] rpx])*(meanXRight - [[locationQueue objectAtIndex:i] rpx]);
        }
        VarXRight = VarXRight/N;
        
        float meanYRight = 0;
        for (int i=0; i<N; i++){
            meanYRight += [[locationQueue objectAtIndex:i] rpy];
        }
        meanYRight = meanYRight/N;
        
        float VarYRight = 0;
        for(int i=0; i<N; i++){
            VarYRight += (meanYRight - [[locationQueue objectAtIndex:i] rpy])*(meanYRight - [[locationQueue objectAtIndex:i] rpy]);
        }
        VarYRight = VarYRight/N;
        
        float x, y;
        if (VarXLeft < GAZE_VARIATION_THRESHOLD && VarYLeft < GAZE_VARIATION_THRESHOLD && VarXRight < GAZE_VARIATION_THRESHOLD && VarYRight < GAZE_VARIATION_THRESHOLD){
            
            x = lookingAt.x+ (int)(FACTORX*((meanXLeft - xMeanPrevLeft) + (meanXRight - xMeanPrevRight))/2);
            y = lookingAt.y + (int)(FACTORY*((meanYLeft - yMeanPrevLeft) + (meanYRight - yMeanPrevRight))/2);
            
            self.look.center = CGPointMake(x, y);
            lookingAt.x = x;
            lookingAt.y = y;
            xMeanPrevLeft = meanXLeft;
            xMeanPrevRight = meanXRight;
            yMeanPrevLeft = meanYLeft;
            yMeanPrevRight = meanYRight;
        }
    NSRange theRange;
    
    theRange.location = 0;
    theRange.length = M;
    
    [locationQueue removeObjectsInRange:theRange];
    }



//    if ((leftPupil.x - leftEyePupilWas.x)<THRESHOLD) {
//        distX += (leftPupil.x - leftEyePupilWas.x);
//        n++;
//    }
//    if ((rightPupil.x - rightEyePupilWas.x)<THRESHOLD) {
//        distX += (rightPupil.x - rightEyePupilWas.x);
//        n++;
//    }
//    distX = n>0?distX/n:distX;
//    
//    n = 0;
//    float distY = 0;
//    if ((leftPupil.y - leftEyePupilWas.y)<THRESHOLD) {
//        distY += (leftPupil.y - leftEyePupilWas.y);
//        n++;
//    }
//    if ((rightPupil.y - rightEyePupilWas.y)<THRESHOLD) {
//        distY += (rightPupil.y - rightEyePupilWas.y);
//        n++;
//    }
//    distY = n>0?distY/n:distY;
//    
//    float x = self.look.center.x + FACTORX * distX;
//    float y = self.look.center.y + FACTORY * distY;
//    
//    self.look.center = CGPointMake(x, y);
    
}
@end
