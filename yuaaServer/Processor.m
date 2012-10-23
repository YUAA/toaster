//
//  Processor.m
//  viewer
//
//  Created by Sam Anklesaria on 2/24/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "Processor.h"

#define TAG_POST_DELAY 5

//Mallocs a formatted string based on printf
char* formattedString(char* format, ...)
{
    //printf("Formatting String");
    va_list args;
    va_start(args, format);
    //Include null byte in length
    int length = 1 + vsnprintf(NULL, 0, format, args);
    va_end(args);

    char* formatted = malloc(sizeof(char) * length);
    va_start(args, format);
    vsnprintf(formatted, length, format, args);
    va_end(args);
    
    return formatted;
}


@implementation Processor
@synthesize delegate, parsingThread;

- (NSData *) lastData {
    return [[[NSData alloc] initWithBytes: cachedString length: cacheStringIndex] autorelease];
}

- (id)initWithPrefs: (Prefs *)p
{
    self = [super init];
    if (self) {
        myUrl = [[NSURL URLWithString: @"http://yaleaerospace.com/scripts/downlink.php"] retain];
        storeUrl = [[NSURL URLWithString: @"http://yaleaerospace.com/scripts/store.php"] retain];
        prefs = [p retain];
        lastUpdate = [[NSDate date] retain];
        netBusy = 0;
        threadAvailable = 1;
        
        parserDictionary = [[NSMutableDictionary alloc] init];
        
        parsingThread = [[NSThread alloc] initWithTarget:self selector:@selector(runParseThread) object:nil];
        [parsingThread start];
        
        [self performSelector:@selector(postTags) onThread:parsingThread withObject:nil waitUntilDone:NO];


        
    }
    return self;
}
         
- (void) parserKeepAlive {
    NSLog(@"Keeping Parsing Thread Alive");
    [self performSelector:@selector(parserKeepAlive) withObject:nil afterDelay:60];
}

- (void)runParseThread
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    
    // Add selector to prevent CFRunLoopRunInMode from returning immediately
    [self performSelector:@selector(parserKeepAlive) withObject:nil afterDelay:60];
    BOOL done = NO;
    do
    {
        NSAutoreleasePool *tempPool = [[NSAutoreleasePool alloc] init];
        // Start the run loop but return after each source is handled.
        SInt32    result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 10, YES);
        // If a source explicitly stopped the run loop, or if there are no
        // sources or timers, go ahead and exit.
        if ((result == kCFRunLoopRunStopped) || (result == kCFRunLoopRunFinished))
            done = YES;
        
        [tempPool release];
    }
    while (!done);
    
     NSLog(@"Thread Done");
    
    [pool release];
}


- (void) updateFromWeb:(NSString *)responseString {
    NSLog(@"Updating From Web");
    // Parse the String from the Web into 1) Balloon 2) Triangulation [ 3) Cars 4) Towers ]
    
    NSArray *devices = [responseString componentsSeparatedByCharactersInSet: [NSCharacterSet newlineCharacterSet]];

    for (NSString *deviceString in devices) {
        
        NSRange deviceNameRange  = [deviceString rangeOfString:@","];
        if ([deviceString length] > deviceNameRange.location && deviceNameRange.location > 0) {
            NSString *deviceName = [deviceString substringToIndex:deviceNameRange.location];
            NSString *data =[deviceString substringFromIndex:deviceNameRange.location+1];
            [self parseData:data fromDevice:deviceName fromSerial:0];
            
        }
    }
}

-(void)updateFromSerialWithData:(NSData *)data {
    NSLog(@"Updating From Serial");
    //Create a data string to feed through the parser
    NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    [self parseData:s fromDevice:@"balloon" fromSerial:1];
    [s release];
}

-(void)parseData:(NSString *)data fromDevice:(NSString *)deviceName fromSerial:(int)s {
    
    TagParseData tpData;
    
    NSValue *parser = [parserDictionary objectForKey:@"devname"];
    if (!parser) {
        TagParseData newParser;
        NSValue *newValue = [NSValue valueWithBytes:&newParser objCType:@encode(TagParseData)];
        [parserDictionary setValue:newValue forKey:deviceName];
        parser = newValue;
    }
    [parser getValue:&tpData];
    
    for (int i=0;i<[data length];i++) {
        
        char c = [(NSString *)data characterAtIndex:i];
        
        if (parseTag(c, &tpData)) {
            //printf("Parsing Tag\n");
            [self newTag:tpData.tag withData:tpData.data length:tpData.dataLength fromSerial:s withId:deviceName];
            //Free up the results
            free(tpData.tag);
            tpData.tag = NULL;
            free(tpData.data);
            tpData.data = NULL;
        }
    }
}



//- (void) updateData: (char)c fromSerial:(int)fromSerial withId:(NSString *)ID {

//-(void)updateData:(TagParseData)tpData fromSerial:(int)fromSerial withId:(NSString *)ID {

-(void)newTag:(char *)tag withData:(char*)tagData length:(int)tagDataLength fromSerial:(int)fromSerial withId:(NSString *)ID {
    if (!gotTags) {
        if ([delegate respondsToSelector:@selector(gettingTags:)] && fromSerial) {
            [delegate gettingTags: YES];
            gotTags = YES;
        }
    }
    
    FlightData *flightData = [FlightData instance];
    
    /*
     //Store the last time we got an update
     [lastUpdate release];
     lastUpdate = [[NSDate date] retain];
     */
    
    // Not image, not LA, not LO
    if (fromSerial && cacheStringIndex + (tagDataLength + 6) < 1024 && strncmp(tag, "IM", 2) != 0 && strncmp(tag, "LA", 2) != 0 && strncmp(tag, "LO", 2) != 0) {
        //Update the Cache to send to the server
        NSLog(@"Updating with tag %2s", tag);
        // Calculate the tag...
        sendTagCellShield(cachedString + cacheStringIndex, tag, tagData);
        cacheStringIndex += tagDataLength + 6;
    }
     
    
    //Create Strings
    NSString *strTag = [[NSString alloc] initWithBytes: tag length: 2 encoding:NSASCIIStringEncoding];//ar mark
    
    // Handle Special Tags ////////
    // Image Tags
    /* Handle Images Here - temporarily disabled
     if ([strTag isEqualToString: @"IM"]) {
     flightData.lastImageTime = [NSDate date];
     
     int width = 80;
     int height = 60;
     Byte *rawImage = (Byte *)tpData.data;
     
     CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
     CGContextRef bitmapContext = CGBitmapContextCreate(
     rawImage,
     width,
     height,
     8,
     width,
     colorSpace,
     kCGImageAlphaNone);
     
     CFRelease(colorSpace);
     CGImageRef cgImage = CGBitmapContextCreateImage(bitmapContext);
     CFRelease(bitmapContext);
     id theValue;
     NSData *imageData;
     
     #if TARGET_OS_IPHONE || TARGET_IPHONE_SIMULATOR || TARGET_OS_EMBEDDED
     theValue = [UIImage imageWithCGImage: cgImage];
     imageData = UIImageJPEGRepresentation(theValue, 1);
     #else
     CFMutableDataRef mutableImageData = CFDataCreateMutable(NULL, 0);
     theValue = [[[NSImage alloc] initWithCGImage: cgImage size: NSZeroSize] autorelease];
     CGImageDestinationRef idst = CGImageDestinationCreateWithData(mutableImageData, kUTTypeJPEG, 1, NULL);
     CGImageDestinationAddImage(idst, cgImage, NULL);
     CGImageDestinationFinalize(idst);
     CFRelease(idst);
     imageData = [NSData dataWithData: (NSMutableData *)mutableImageData];
     CFRelease(mutableImageData);
     #endif
     CFRelease(cgImage);
     [flightData.pictures addObject: theValue];
     if ([delegate respondsToSelector: @selector(receivedPicture)])
     [delegate receivedPicture];
     
     ASIFormDataRequest *r = [ASIFormDataRequest requestWithURL:storeUrl];
     [r setPostValue: prefs.uuid forKey:@"uid"];
     [r setPostValue: @"berkeley" forKey: @"password"];
     [r setPostValue: @"balloon" forKey:@"devname"];
     [r setData:imageData withFileName:@"photo.jpg" andContentType:@"image/jpeg" forKey:@"photo"];
     [r setDelegate:self];
     [r startAsynchronous];
     [imageData release];
     return;
     }
     */
    
    NSString *strVal = [[NSString alloc] initWithBytes: tagData length: (NSUInteger)(tagDataLength) encoding:NSASCIIStringEncoding];//ar mark
    
    
    // Store Log Messages From the Balloon
    
    /*
     if ([strTag isEqualToString: @"MS"]) {
     [flightData.parseLogData addObject: @"Balloon message: "];
     [strVal enumerateLinesUsingBlock: ^(NSString *str, BOOL *stop) {
     [flightData.parseLogData addObject: str];
     }];
     return;
     }
     */
    
    ////////
    double floatVal = [strVal floatValue];
    
    //NSLog(@"String tag is %@", strTag);
    
    // Log the incoming Data
    //[flightData.parseLogData addObject: [NSString stringWithFormat: @"Updating tag %@ with value %@", strTag, strVal]];
    
    // Parse IMU Data
    if ([strTag isEqualToString: @"YA"]) {
        flightData.rotationZ = floatVal;
        flightData.lastIMUTime = [NSDate date];
    }
    else if ([strTag isEqualToString: @"PI"]) {
        flightData.rotationY = floatVal;
        flightData.lastIMUTime = [NSDate date];
    }
    else if ([strTag isEqualToString: @"RO"]) {
        flightData.rotationX = floatVal;
        flightData.lastIMUTime = [NSDate date];
    }
    //Check for Location Tags
    else if ([strTag isEqualToString: @"LA"] || [strTag isEqualToString: @"LO"]) {
        
        if (floatVal != 0) {
            
            if ([strTag isEqualToString: @"LA"]) {
                flightData.lat = floatVal;
                flightData.lastLocTime = [NSDate date];
            } else if ([strTag isEqualToString: @"LO"]) {
                flightData.lon = floatVal;
                flightData.lastLocTime = [NSDate date];
            }
            if (flightData.lat && flightData.lon) {
                if (fromSerial) [self addLocationToCache];
                if ([delegate respondsToSelector:@selector(gettingTags:)])
                    [delegate receivedLocationForId: ID];
                
                #if TARGET_OS_IPHONE
                    flightData.lat = false;
                    flightData.lon = false;
                #endif
            }
            
        }
    }
    else if ([strTag isEqualToString: @"BB"]) {
        NSLog(@"Should be doing some stuff for the Bio Bay");
    }
    else {
        //NSLog(@"Doing some shit");
        StatPoint *stat = [flightData.balloonStats objectForKey: strTag];
        if (![flightData.balloonStats objectForKey: strTag]) {
            [flightData.nameArray performSelectorOnMainThread:@selector(addObject:) withObject:strTag waitUntilDone:NO];
        }
        if (stat == nil) {
            stat = [[[StatPoint alloc] init] autorelease];//ar mark
            [flightData.balloonStats setObject: stat forKey: strTag];
        }
        if (!stat.minval || stat.minval > floatVal) stat.minval = floatVal;
        if (!stat.maxval || stat.maxval < floatVal) stat.maxval = floatVal;
        NSNumber *idx = [NSNumber numberWithInteger: [stat.points count]];
        NSDictionary *point = [NSDictionary dictionaryWithObjectsAndKeys: idx, @"x", [NSNumber numberWithFloat: floatVal] , @"y", NULL];
        // this seems really inefficiant. we could do better ^^
        
        [stat.points performSelectorOnMainThread:@selector(addObject:) withObject:point waitUntilDone:NO];
        stat.lastTime = [NSDate date];
        [stat.bayNumToPoints setObject:point forKey: [NSNumber numberWithInt:bayCounter]];
        //[stat release];
    }
    
    
    if ([delegate respondsToSelector: @selector(receivedTag:withValue:)]) {
        [delegate receivedTag: strTag withValue: floatVal];
    }
    
    //After parsing a tag, free the memory!!!
    
    //NSLog(@"Length: %zi",sizeof(tpData.data));
    
    //NSLog(@"Freeing");
    
    //NSLog(@"Parse Tag: %@",strTag);
    
    [strTag release];
    [strVal release];
    
}

-(void)addLocationToCache {
    FlightData *f = [FlightData instance];
    char *latStr = formattedString("%f", f.lat);
    int latLen = (int)strlen(latStr);
    char *lonStr = formattedString("%f", f.lon);
    int lonLen = (int)strlen(lonStr);
    if ((cacheStringIndex + (latLen + 6) + (lonLen + 6)) < 1024) {
        sendTagCellShield(cachedString + cacheStringIndex, "LA", latStr);
        cacheStringIndex += latLen + 6;
        sendTagCellShield(cachedString + cacheStringIndex, "LO", lonStr);
        cacheStringIndex += lonLen + 6;
    }
    free(latStr);
    free(lonStr);
}

static int IS_FIRST_RUN = 1;

- (void)postTags {
    if ([lastUpdate timeIntervalSinceNow] < -10) {
        // NSLog(@"I am no longer getting tags");
        if ([delegate respondsToSelector:@selector(gettingTags:)]) {
            [delegate gettingTags: NO];
            // NSLog(@"Delegate informed of no tags");
        }
        gotTags = NO;
    }
    
    // return;
    
    // Uplink and downlink
    if (netBusy == 0) {
        
        if (cacheStringIndex > 0) {
            NSLog(@"Post Tags To Network");
            netBusy++;
            NSString *cache = [[NSString alloc] initWithBytes: cachedString length: cacheStringIndex encoding:NSASCIIStringEncoding];
            //NSLog(@"Cache is %@", cache);
            ASIFormDataRequest *r = [ASIFormDataRequest requestWithURL:storeUrl];
            //NSLog(@"Posting with devname: %@", prefs.deviceName);
            
            //On the first downlink, we actually want to get our own data because we're not storing
            //the data on the device
            [r setPostValue: IS_FIRST_RUN?@"":prefs.deviceName forKey:@"uid"];
            if (IS_FIRST_RUN) IS_FIRST_RUN = 0;
            
            [r setPostValue: @"balloon" forKey:@"devname"];
            [r setPostValue: cache forKey: @"data"];
            [r setDelegate:self];
            cacheStringIndex = 0;
            NSLog(@"Sending tags to Server");
            [r startAsynchronous];
            [cache release];
        }
        NSLog(@"Downlinking");
        // Load Raw.php and obtain data for all devices
        ASIFormDataRequest *k = [ASIFormDataRequest requestWithURL:myUrl];
        //NSLog(@"Getting with devname: %@", prefs.deviceName);
        [k setPostValue: prefs.deviceName forKey:@"uid"];
        [k setDelegate:self];
        netBusy++;
        [k startAsynchronous];
    }
}

- (void)requestFinished:(ASIHTTPRequest *)request
{
    NSLog( @"Request Response of Length %i", [[request responseString] length]);
    
    if ([delegate respondsToSelector: @selector(serverStatus:)])
        [delegate serverStatus: YES];
    FlightData *flightData = [FlightData instance];
    [flightData.netLogData addObject: @"Request Succeeded: "];
    
    
    NSString *requestResponseString = [request responseString];
    NSURL *requestURL = request.url;
    
    [requestResponseString enumerateLinesUsingBlock: ^(NSString *str, BOOL *stop) {
        [flightData.netLogData addObject: str];
    }];
    
    if ([requestURL isEqual: myUrl]) {
        //[self performSelector:@selector(updateFromWeb:) onThread:parsingThread withObject:requestResponseString waitUntilDone:NO];
        [self updateFromWeb:requestResponseString];
    }
    netBusy--;
    [self performSelector:@selector(postTags) withObject:nil afterDelay:TAG_POST_DELAY];
}
- (void)requestFailed:(ASIHTTPRequest *)request
{
    NSLog(@"Post Tags Request Failed");
    FlightData *flightData = [FlightData instance];
    [flightData.netLogData addObject: @"Request Failed: "];
    [flightData.netLogData addObject: [[request error] description]];
    if ([delegate respondsToSelector:@selector(serverStatus:)])
        [delegate serverStatus: NO];
    netBusy--;
    [self performSelector:@selector(postTags) withObject:nil afterDelay:TAG_POST_DELAY];
}

- (void) dealloc {
    [prefs release];
    [myUrl release];
    [storeUrl release];
    [lastUpdate release];
    [parserDictionary release];
    [super dealloc];
}

@end
