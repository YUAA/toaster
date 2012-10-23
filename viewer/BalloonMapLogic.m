//
//  BalloonMapDelegate.m
//  viewer
//
//  Created by Sam Anklesaria on 11/23/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "BalloonMapLogic.h"
#include <math.h>
#import "cAkpParser.h"
#import "ASIFormDataRequest.h"


#define MAX_BALLOON_POINT_HISTORY 30
#define MAX_CELL_TRIANGULATION_HISTORY 30
#define MAX_CHASE_HISTORY 1
#define MAX_CELL_TOWER_HISTORY 30

#define BALLOON_POINT_KEY @"balloon"
#define BALLOON_POINT_CELL_KEY @"balloon_cell"
#define CHASE_KEY @"chase"
#define TOWER_KEY @"tower"

#define USER_LOCATION_UPDATE_FREQUENCY 2

@implementation BalloonMapLogic
@synthesize okToUpdate;

- (id) initWithPrefs: (Prefs *)p map: (MKMapView *) m {
    if (self = [self init]) {
        prefs = [p retain];
        map = [m retain];
        [map setDelegate: self];
        map.showsUserLocation = YES;

        dataPointHistory = [[NSMutableDictionary alloc] init];
        
        [self updateView];
        [self postUserLocation];
        
    }
    return self;
}

- (void) dealloc {
    [dataPointHistory release];
    [currentPoint release];
    [map release];
    [prefs release];
    [super dealloc];
}

/*
- (void) mapView: (MKMapView *)map didUpdateUserLocation: (MKUserLocation *)userLocation {
    [self updateView];
}
 */


double GPSToHMS(double coord) {
    
    double sign = 0;
    sign = coord < 0 ? -1.0 : 1.0;
    coord = coord<0?coord*-1:coord;
    
    double hour = 0;
    double minutes = 0;
    double seconds = 0;
    
    hour = floor(coord);
    minutes = (coord-hour)*60;
    //seconds = (coord-hour-minutes/60)*3600;
    
    double result = hour + minutes/100;
    return sign*result;
}

/*
double GPSToHMS(double coord) {
    int sign = 0;
    
    int hour = 0;
    int minutes = 0;
    int seconds = 0;
    sign = coord < 0 ? -1 : 1;
    
    hour = floor(coord);
    minutes = floor((coord-hour)*60);
    seconds = floor((coord-hour-minutes/60)*3600);
    
    double result = hour + minutes/100 + seconds/10000;
    return result;
}*/


- (void)postUserLocation {
    NSLog(@"Posting User Location");
    char latstr[20];
    char lonstr[20];
    CLLocationCoordinate2D coord = map.userLocation.location.coordinate;
    if (coord.latitude && coord.longitude) {
        
        double lat = GPSToHMS(coord.latitude);
        double lon = GPSToHMS(coord.longitude);
        
        sprintf(latstr,"%+.8f",lat);
        sprintf(lonstr,"%+.8f",lon);
        int latlen = strlen(latstr);
        int lonlen = strlen(lonstr);
        
        char *lats = calloc((latlen + 7), sizeof(char));
        char *lons = calloc((lonlen + 7), sizeof(char));
        
        sendTagCellShield(lats, "LA", latstr);
        sendTagCellShield(lons,"LO", lonstr);
        NSURL *myLocUrl = [NSURL URLWithString: [NSString stringWithFormat: @"http://yaleaerospace.com/scripts/store.php"]];
        ASIFormDataRequest *locReq = [ASIFormDataRequest requestWithURL:myLocUrl];
        [locReq setPostValue: prefs.deviceName forKey:@"uid"];
        [locReq setPostValue: @"berkeley" forKey: @"password"];
        [locReq setPostValue: [prefs deviceName] forKey:@"devname"];
        [locReq setPostValue: [NSString stringWithFormat: @"%s%s", lats, lons] forKey: @"data"];
        [locReq setDelegate:self];
        [locReq startAsynchronous];
        
        free(lats);
        free(lons);
    } else {
        // No location yet - check again in 5 seconds
        NSLog(@"No User Location Yet - Will try again shortly");
        [NSTimer scheduledTimerWithTimeInterval:USER_LOCATION_UPDATE_FREQUENCY target:self selector:@selector(postUserLocation) userInfo:nil repeats:NO];
    }
}

- (void)requestFinished:(ASIHTTPRequest *)request {
    // When the user location request finishes, post the location again
    [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(postUserLocation) userInfo:nil repeats:NO];
}


- (CLLocationCoordinate2D)midpointFrom:(CLLocationCoordinate2D)loca to: (CLLocationCoordinate2D)locb {
    CLLocationCoordinate2D midpoint;
    midpoint.latitude = (loca.latitude + locb.latitude) / 2;
    midpoint.longitude = (loca.longitude + locb.longitude) / 2;
    return midpoint;
}

double myabs(double a) {
    return a >0 ? a : -a;
}

- (MKCoordinateSpan)distanceFrom:(CLLocationCoordinate2D)loca to: (CLLocationCoordinate2D)locb {
    MKCoordinateSpan spanA;
    double f = myabs(loca.latitude - locb.latitude);
    double s = myabs(loca.longitude - locb.longitude);
    spanA.latitudeDelta = f;
    spanA.longitudeDelta = s;
    return spanA;
}

- (double)spanSize: (MKCoordinateSpan)rect {
    return rect.latitudeDelta * rect.longitudeDelta;
}

- (void)updateLocation:(CLLocationCoordinate2D)location forIdentifier:(NSString *)ID {
    //Create a new data point for the balloon
    DataPoint *newPoint = [[DataPoint alloc] initWithCoordinate:location];
    newPoint.ID = ID;
    
    
    //Choose the data type based on the ID
    
    int maxHistory = 0;
    NSString *historyType = nil;
    
    if ([ID isEqualToString:@"balloon"]) {
        if (currentPoint) {
            currentPoint.type = kDataPointTypeBalloon;
            [map removeAnnotation: currentPoint];
            [map addAnnotation: currentPoint];
        }
        newPoint.type = kDataPointTypeBalloonCurrent;
        currentPoint = newPoint;
        historyType = BALLOON_POINT_KEY;
        maxHistory = MAX_BALLOON_POINT_HISTORY;
        
        [self updateView];
    } else if ([ID isEqualToString:@"BalloonCell"]) {
        newPoint.type = kDataPointTypeCellTriangulation;
        historyType = BALLOON_POINT_CELL_KEY;
        maxHistory = MAX_CELL_TRIANGULATION_HISTORY;
    } else if ([ID isEqualToString:@"Tower"]) {
        newPoint.type = kDataPointTypeCellTower;
        historyType = TOWER_KEY;
        maxHistory = MAX_CELL_TOWER_HISTORY;
    } else {
        newPoint.type = kDataPointTypeChaseCar;
        historyType = CHASE_KEY;
        maxHistory = MAX_CHASE_HISTORY;
    }
    
    // Grab the history of balloon data points - depending on whether the points were for cell or from the GPS
    NSMutableArray *previousPoints = [dataPointHistory objectForKey:historyType];
    if (previousPoints == nil) {
        previousPoints = [[NSMutableArray alloc] init];
        [dataPointHistory setObject:previousPoints forKey:historyType];
    }
    
    if ([previousPoints count] >= maxHistory) {
        //Too many points - remove the last data point, and annotation from the map
        DataPoint *removePoint = [previousPoints objectAtIndex:0];
        [previousPoints removeObjectAtIndex:0];
        [map removeAnnotation:removePoint];
    }
    [previousPoints addObject:newPoint];
    [map addAnnotation:newPoint];
}

-(void) updateView {
    if ([prefs autoAdjust] == 0) {
        CLLocationCoordinate2D carloc = map.userLocation.location.coordinate;
        MKCoordinateSpan spanB;
        spanB.latitudeDelta=0.02;
        spanB.longitudeDelta=0.02;
        if (carloc.latitude && carloc.longitude) {
            if (currentPoint != nil) {
                CLLocationCoordinate2D center = [self midpointFrom:currentPoint.coordinate to:carloc];
                MKCoordinateSpan spanA = [self distanceFrom: currentPoint.coordinate to: carloc];
                currentRegion.span = ([self spanSize: spanB] > [self spanSize: spanA]) ? spanB : spanA;
                currentRegion.center=center;
            } else {
                currentRegion.center = carloc;
                currentRegion.span = spanB;
            }
        } else if (currentPoint != nil) {
            currentRegion.center = currentPoint.coordinate;
            currentRegion.span = spanB;
        } else {
            return;
        }
        [self performSelectorOnMainThread: @selector(doUpdate) withObject:nil waitUntilDone:YES];
    }
}

- (void) doUpdate {
    MKCoordinateRegion r = [map regionThatFits: currentRegion];
    [map setRegion: r animated:TRUE];
}

- (MKAnnotationView *)mapView:(MKMapView *)mV viewForAnnotation:(DataPoint *)annotation{
    static NSString *PinIdentifier = @"pinview";
    static NSString *TowerIdentifier = @"tower";
    static NSString *ChaseIdentifier = @"chase";
    
    
    if ([annotation isKindOfClass:[MKUserLocation class]]) {
        return nil;
    }
    
    
    MKAnnotationView *annotationView;
    
    // Choose an Annotation View for the map
    switch (annotation.type) {
        case kDataPointTypeBalloon:
        case kDataPointTypeBalloonCurrent:
        case kDataPointTypeCellTriangulation:
            annotationView = (MKPinAnnotationView *)[map dequeueReusableAnnotationViewWithIdentifier:PinIdentifier];
            [(MKPinAnnotationView *)annotationView setAnimatesDrop: NO];
            if (annotationView == nil) {
                annotationView = [[[MKPinAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:PinIdentifier] autorelease];
                annotationView.canShowCallout = YES;
                annotationView.calloutOffset = CGPointMake(-5, 5);
            } else {
                annotationView.annotation = annotation;
            }
            [(MKPinAnnotationView *)annotationView setPinColor:MKPinAnnotationColorRed];
        
            // In the case of the point being the CURRENT position, just switch the pin color to green
            if (annotation.type == kDataPointTypeBalloonCurrent) {
                [(MKPinAnnotationView *)annotationView setPinColor:MKPinAnnotationColorGreen];
                currentBalloonPin = (MKPinAnnotationView *)annotationView;
            }
            
            if (annotation.type == kDataPointTypeCellTriangulation) [(MKPinAnnotationView *)annotationView setPinColor:MKPinAnnotationColorPurple];
            
            break;
        case kDataPointTypeChaseCar:
            annotationView = [map dequeueReusableAnnotationViewWithIdentifier:ChaseIdentifier];
            if (annotationView == nil) {
                annotationView = [[[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:ChaseIdentifier] autorelease];
                annotationView.image  = [UIImage imageNamed:@"chase.png"];
                annotationView.canShowCallout = YES;
                annotationView.calloutOffset = CGPointMake(-5, 5);
            } else {
                annotationView.annotation = annotation;
            }
            break;
            
        case kDataPointTypeCellTower:
            annotationView = [map dequeueReusableAnnotationViewWithIdentifier:TowerIdentifier];
            if (annotationView == nil) {
                annotationView = [[[MKAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:TowerIdentifier] autorelease];
                annotationView.image  = [UIImage imageNamed:@"tower.png"];
                annotationView.canShowCallout = YES;
                annotationView.calloutOffset = CGPointMake(-5, 5);
            } else {
                annotationView.annotation = annotation;
            }
            break;
            
            
        default:
            break;
    }
    return annotationView;
}

- (void)mapView:(MKMapView *)mapView didAddAnnotationViews:(NSArray *)views {
    //Put the green point on top
    if (currentBalloonPin) [[currentBalloonPin superview] bringSubviewToFront:currentBalloonPin];
}


- (void)updateLocWithID:(NSString *)ID {
    // Update the Balloon Location
    FlightData *f = [FlightData instance];
    if (f.lat && f.lon) {
        
        //Switch to Google's Decimal GPS representation
        double latAbs = fabs(f.lat);
        double lat = (((latAbs - floor(latAbs)) * 100) / 60 + floor(latAbs)) * (f.lat>0?1.0:-1.0);
        
        
        
        double lonAbs = fabs(f.lon);
        double lon = (((lonAbs - floor(lonAbs)) * 100) / 60 + floor(lonAbs)) * (f.lon>0?1.0:-1.0);
        
        
        CLLocationCoordinate2D loc = {lat, lon};
        if (fabs(loc.latitude) <= 90 && fabs(loc.longitude) <= 180) {
            [self updateLocation:loc forIdentifier:ID];
        }
    }
}


@end
