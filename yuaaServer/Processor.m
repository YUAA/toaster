//
//  Processor.m
//  viewer
//
//  Created by Sam Anklesaria on 2/24/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "Processor.h"

//Mallocs a formatted string based on printf
char* formattedString(char* format, ...)
{
    printf("Formatting String");
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
        myUrl = [[NSURL URLWithString: @"http://yaleaerospace.com/scripts/raw.php"] retain];
        storeUrl = [[NSURL URLWithString: @"http://yaleaerospace.com/scripts/store.php"] retain];
        prefs = [p retain];
        lastUpdate = [[NSDate date] retain];
        okToSend = 1;
        okToGet = 1;
        threadAvailable = 1;
        [NSThread detachNewThreadSelector: @selector(posterThread) toTarget:self withObject:nil];
        
        parsingThread = [[NSThread alloc] initWithTarget:self selector:@selector(runParseThread) object:nil];
        [parsingThread start];
        
        
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
         
         
         
         

- (void) posterThread {
    [NSTimer scheduledTimerWithTimeInterval: 2 target:self selector:@selector(postTags) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] run];
}

- (void) updateFromWeb:(NSData *)responseData {
    NSLog(@"Updating From Web");
    
    char *chars = (char *)[responseData bytes];
    for (int i=0;i<[responseData length];i++) {
        [self updateData:chars[i] fromSerial:0];
    }
}

-(void)updateFromSerialWithData:(NSData *)data {
    NSLog(@"Updating From Serial");
    char *chars = (char *)[data bytes];
    for (int i=0; i < [data length]; i++) {
        [self updateData:chars[i] fromSerial: 1];
    }
}


- (void) updateData: (char) c fromSerial: (int) fromSerial {
    
    if (parseTag(c, &tpData)) {
        
        if (!gotTags) {
            if ([delegate respondsToSelector:@selector(gettingTags:)] && fromSerial) {
                [delegate gettingTags: YES];
                gotTags = YES;
                okToSend++;
            }
        }
        FlightData *flightData = [FlightData instance];
        
        
        //Store the last time we got an update
        [lastUpdate release];
        lastUpdate = [[NSDate date] retain];
        
        
        // Not image, not LA, not LO
        if (cacheStringIndex + (tpData.dataLength + 5) < 1024 && strncmp(tpData.tag, "IM", 2) != 0 && strncmp(tpData.tag, "LA", 2) != 0 && strncmp(tpData.tag, "LO", 2) != 0) {
            //Update the Cache to send to the server
            NSLog(@"Updating with tag %2s", tpData.tag);
            // Calculate the tag...
            sendTagCellShield(cachedString + cacheStringIndex, tpData.tag, tpData.data);
            cacheStringIndex += tpData.dataLength + 5;
        }
        
        
        //Create Strings 
        NSString *strTag = [[[NSString alloc] initWithBytes: tpData.tag length: 2 encoding:NSASCIIStringEncoding] autorelease];
       
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
        NSString *strVal = [[[NSString alloc] initWithBytes: tpData.data length: (NSUInteger)(tpData.dataLength) encoding:NSASCIIStringEncoding] autorelease];
        // Store Log Messages From the Balloon
        if ([strTag isEqualToString: @"MS"]) {
            [flightData.parseLogData addObject: @"Balloon message: "];
            [strVal enumerateLinesUsingBlock: ^(NSString *str, BOOL *stop) {
                [flightData.parseLogData addObject: str];
            }];
            return;
        }
        
        ////////
        double floatVal = [strVal floatValue];
        
        NSLog(@"String tag is %@", strTag);
        
        // Log the incoming Data
        [flightData.parseLogData addObject: [NSString stringWithFormat: @"Updating tag %@ with value %@", strTag, strVal]];
        
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
            double valAbs = fabs(floatVal);
            double newVal = (((valAbs - floor(valAbs)) * 100) / 60 + floor(valAbs)) * (floatVal>0?1.0:-1.0);
            if ([strTag isEqualToString: @"LA"]) {
                flightData.lat = newVal;
                flightData.lastLocTime = [NSDate date];
            } else if ([strTag isEqualToString: @"LO"]) {
                flightData.lon = newVal;
                flightData.lastLocTime = [NSDate date];
            }
            if (flightData.lat && flightData.lon) {
                [self addLocationToCache];
                [delegate receivedLocation];
            }
        }
        else if ([strTag isEqualToString: @"BB"]) {
            NSLog(@"Should be doing some stuff for the Bio Bay");
        }
        else {
            NSLog(@"Doing some shit");
            StatPoint *stat = [flightData.balloonStats objectForKey: strTag];
            if (![flightData.balloonStats objectForKey: strTag]) {
                [flightData.nameArray performSelectorOnMainThread:@selector(addObject:) withObject:strTag waitUntilDone:NO];
            }
            if (stat == nil) {
                stat = [[[StatPoint alloc] init] autorelease];
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
        }
        
        if ([delegate respondsToSelector: @selector(receivedTag:withValue:)]) {
            [delegate receivedTag: strTag withValue: floatVal];
        }
        
        //After parsing a tag, free the memory!!!
        
        //NSLog(@"Length: %zi",sizeof(tpData.data));
        
        //free(*tpData.tag);
        //NSLog(@"Freeing");
        free(tpData.data);
        free(tpData.tag);
    }
    
}

-(void)addLocationToCache {
    FlightData *f = [FlightData instance];
    char *latStr = formattedString("%f", f.lat);
    int latLen = (int)strlen(latStr);
    char *lonStr = formattedString("%f", f.lon);
    int lonLen = (int)strlen(lonStr);
    if ((cacheStringIndex + (latLen + 5) + (lonLen + 5)) < 1024) {
        sendTagCellShield(cachedString + cacheStringIndex, "LA", latStr);
        cacheStringIndex += latLen + 5;
        sendTagCellShield(cachedString + cacheStringIndex, "LO", lonStr);
        cacheStringIndex += lonLen + 5;
    }
    free(latStr);
    free(lonStr);
}

- (void)postTags {
    if ([lastUpdate timeIntervalSinceNow] < -10) {
        // NSLog(@"I am no longer getting tags");
        if ([delegate respondsToSelector:@selector(gettingTags:)]) {
            [delegate gettingTags: NO];
            // NSLog(@"Delegate informed of no tags");
        }
        gotTags = NO;
        okToSend--;
        okToGet--;
    }
    
    return;
    // Uplink
    if (gotTags && okToSend == 2) {
        if (cacheStringIndex > 0) {
            NSString *cache = [[[NSString alloc] initWithBytes: cachedString length: cacheStringIndex encoding:NSASCIIStringEncoding] autorelease];
            NSLog(@"Cache is %@", cache);
            ASIFormDataRequest *r = [ASIFormDataRequest requestWithURL:storeUrl];
            [r setPostValue: prefs.uuid forKey:@"uid"];
            [r setPostValue: @"balloon" forKey:@"devname"];
            [r setPostValue: cache forKey: @"data"];
            [r setDelegate:self];
            cacheStringIndex = 0;
            NSLog(@"Putting tags on server");
            okToSend = 0;
            okToGet--;
            [r startAsynchronous];
        }
    }
    //Downlink from the Server
    if (!gotTags && okToGet == 1) {
        okToSend--;
        okToGet--;
       
        // Load Raw.php and obtain data for all devices
        ASIFormDataRequest *k = [ASIFormDataRequest requestWithURL:myUrl];
        [k setPostValue: prefs.uuid forKey:@"uid"];
        //[k setPostValue: @"BalloonCell2" forKey:@"devname"];
        [k setDelegate:self];
        [k startAsynchronous];
    }
}

- (void)requestFinished:(ASIHTTPRequest *)request
{
    NSLog( @"Response is %@", [request responseString]);
    
    if ([delegate respondsToSelector: @selector(serverStatus:)])
        [delegate serverStatus: YES];
    FlightData *flightData = [FlightData instance];
    [flightData.netLogData addObject: @"Request Succeeded: "];
    
    
    NSString *requestResponseString = [request responseString];
    NSURL *requestURL = request.url;
    NSData *requestData = [request responseData];
    
    [requestResponseString enumerateLinesUsingBlock: ^(NSString *str, BOOL *stop) {
        [flightData.netLogData addObject: str];
    }];
    
    if ([requestURL isEqual: myUrl]) {
        NSData *responseData = requestData;
        [self performSelector:@selector(updateFromWeb:) onThread:parsingThread withObject:responseData waitUntilDone:NO];
    }
    
    okToSend++;
    okToGet++;
    
}
- (void)requestFailed:(ASIHTTPRequest *)request
{
    NSLog(@"Request failed");
    FlightData *flightData = [FlightData instance];
    [flightData.netLogData addObject: @"Request Failed: "];
    [flightData.netLogData addObject: [[request error] description]];
    if ([delegate respondsToSelector:@selector(serverStatus:)])
        [delegate serverStatus: NO];
    okToSend++;
    okToGet++;
}

- (void) dealloc {
    [prefs release];
    [myUrl release];
    [storeUrl release];
    [lastUpdate release];
    [super dealloc];
}

@end
