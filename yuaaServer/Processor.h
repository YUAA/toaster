//
//  Processor.h
//  viewer
//
//  Created by Sam Anklesaria on 2/24/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>
// import "Parser.h"
#import "Prefs.h"
#import "ASIHTTPRequest.h"
#import "ASIFormDataRequest.h"
#import "StatPoint.h"
#import "FlightData.h"
#import "cAkpParser.h"

@protocol ProcessorDelegate
@optional
-(void)receivedTag:(NSString *)theData withValue:(double)val;
-(void)receivedPicture;
-(void)receivedLocationForId:(NSString *)ID;
-(void)serverStatus:(bool) isUp;
-(void)gettingTags: (bool)b;
@end

char* formattedString(char* format, ...);

@interface Processor : NSObject {
    id delegate;
    
    int netBusy;
    BOOL cellNew;
    BOOL threadAvailable;
    char cachedString[1024];
    int cacheStringIndex;
    //TagParseData tpData;
    
    int bayCounter;
    Prefs *prefs;
    
    NSURL *myUrl;
    NSURL *storeUrl;
    
    int mcc;
    int mnc;
    int lac;
    int cid;
    
    NSThread *parsingThread;
    NSMutableDictionary *parserDictionary;
    
    BOOL gotTags;
    
    NSDate *lastUpdate;
}

@property (nonatomic, assign) NSThread *parsingThread;

- (void)updateFromWeb:(NSString *)responseString;
- (void)updateFromSerialWithData:(NSData *)data;


- (void)addLocationToCache;
//- (void)updateData: (char) c fromSerial: (int) fromSerial withId:(NSString *)ID;
//-(void)updateData:(TagParseData)tpData fromSerial:(int)fromSerial withId:(NSString *)ID;
-(void)newTag:(char *)tag withData:(char*)data length:(int)tagDataLength fromSerial:(int)fromSerial withId:(NSString *)ID;
-(void)parseData:(NSString *)data fromDevice:(NSString *)deviceName fromSerial:(int)s;

//- (void)posterThread;
- (id)initWithPrefs: (Prefs *)p;
- (NSData *)lastData;

@property (retain) id delegate;

@end
