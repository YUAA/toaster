//
//  BalloonMapDelegate.h
//  viewer
//
//  Created by Sam Anklesaria on 11/23/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <MapKit/MapKit.h>
#import "DataPoint.h"
#import "Prefs.h"
#import "FlightData.h"
#import "ASIHTTPRequest.h"

@interface BalloonMapLogic : NSObject <MKMapViewDelegate> {
    Prefs *prefs;
    DataPoint *currentPoint;
    MKPinAnnotationView *currentBalloonPin;
    
    NSMutableDictionary *dataPointHistory;
    
    
    MKMapView *map;
    MKCoordinateRegion currentRegion;
    BOOL okToUpdate;
}

- (id) initWithPrefs: (Prefs *)p map: (MKMapView *) m;
- (void)updateLocation:(CLLocationCoordinate2D)location forIdentifier:(NSString *)ID;
- (CLLocationCoordinate2D)midpointFrom:(CLLocationCoordinate2D)loca to: (CLLocationCoordinate2D)locb;
- (MKCoordinateSpan)distanceFrom:(CLLocationCoordinate2D)loca to: (CLLocationCoordinate2D)locb;
- (double)spanSize: (MKCoordinateSpan)rect;
- (void) updateView;
- (void)updateLocWithID:(NSString *)ID;
- (void) doUpdate;
- (void)postUserLocation;
@property BOOL okToUpdate;

@end

double myabs(double a);
