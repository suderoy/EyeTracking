//
//  pupilDetect.cpp
//  FaceDetectionPOC
//
//  Created by Sudeshna Roy on 14/03/13.
//  Copyright (c) 2013 iCapps. All rights reserved.
//

#include "pupilDetect.h"

int detect2(cv::Mat src, cv::Point &Pupil, cv::Mat faceROIColor )
{
	if (src.empty())
		return -1;
    
	// Invert the source image and convert to grayscale
	cv::Mat gray;
	cv::cvtColor(~src, gray, CV_BGR2GRAY);
    
	// Convert to binary image by thresholding it
	cv::threshold(gray, gray, 150, 255, cv::THRESH_BINARY);
    
	// Find all contours
	std::vector<std::vector<cv::Point> > contours;
	cv::findContours(gray.clone(), contours, CV_RETR_EXTERNAL, CV_CHAIN_APPROX_NONE);
	
	/// Draw contours
    cv::Mat drawing = cv::Mat::zeros( gray.size(), CV_8UC3 );
//    for( int i = 0; i< contours.size(); i++ )
//    {
//        cv::Scalar color = Scalar( rng.uniform(0, 255), rng.uniform(0,255), rng.uniform(0,255) );
//        drawContours( drawing, contours, i, color, 2, 8, CV_RETR_EXTERNAL, 0, cv::Point() );
//    }
    
    
	// Fill holes in each contour
	cv::drawContours(gray, contours, -1, CV_RGB(255,255,255), -1);
    
	for (int i = 0; i < contours.size(); i++)
	{
		double area = cv::contourArea(contours[i]);
		cv::Rect rect = cv::boundingRect(contours[i]);
		int radius = rect.width/2;
		
		// If contour is big enough and has round shape
		// Then it is the pupil
		if (area >= 30 &&
		    std::abs(1 - ((double)rect.width / (double)rect.height)) <= 0.2 &&
            std::abs(1 - (area / (CV_PI * pow(radius, 2)))) <= 0.2)
		{
			cv::circle(src, cv::Point(rect.x + radius, rect.y + radius), 1, CV_RGB(255,0,0), 2);
			Pupil.x=rect.x + radius;
			Pupil.y=rect.y+radius;
			break;
		}
	}
    
	return 0;
}
