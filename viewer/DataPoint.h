//
//  DataPoint.h
//  Babelon iPhone
//
//  Created by Stephen Hall on 4/23/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>



typedef enum {
    
    kDataPointTypeBalloon = 0,
    kDataPointTypeBalloonCurrent,
    kDataPointTypeCellTower,
    kDataPointTypeCellTriangulation,
    kDataPointTypeChaseCar,
    
} DataPointType;

@interface DataPoint : NSObject <MKAnnotation> {
    CLLocationCoordinate2D coordinate; 
    NSString *creationDate;
    DataPointType type;
    
    NSString *ID;
    
}

@property (nonatomic, copy) NSString *ID;

@property (nonatomic, assign) DataPointType type;
@property (nonatomic, readonly) CLLocationCoordinate2D coordinate;
-(id)initWithCoordinate:(CLLocationCoordinate2D)c;
- (NSString *)subtitle;
- (NSString *)title;

@end
