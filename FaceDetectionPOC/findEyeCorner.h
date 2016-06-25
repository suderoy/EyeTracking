#ifndef EYE_CORNER_H
#define EYE_CORNER_H



#define kEyeLeft true
#define kEyeRight false

void createCornerKernels();
void releaseCornerKernels();
cv::Point findEyeCorner(cv::Mat region,bool left);
cv::Point2f findSubpixelEyeCorner(cv::Mat region, bool left);

#endif