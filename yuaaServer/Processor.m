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
@synthesize delegate;

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
    }
    return self;
}

- (void) posterThread {
    [NSTimer scheduledTimerWithTimeInterval: 2 target:self selector:@selector(postTags) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] run];
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
        [lastUpdate release];
        lastUpdate = [[NSDate date] retain];
        if (cacheStringIndex + (tpData.dataLength + 5) < 1024 && strncmp(tpData.tag, "IM", 2) != 0 && strncmp(tpData.tag, "LA", 2) != 0 && strncmp(tpData.tag, "LO", 2) != 0) {
            NSLog(@"Updating with tag %2s", tpData.tag);
            sendTagCellShield(cachedString + cacheStringIndex, tpData.tag, tpData.data);
            cacheStringIndex += tpData.dataLength + 5;
        }
        NSString *strTag = [[[NSString alloc] initWithBytes: tpData.tag length: 2 encoding:NSASCIIStringEncoding] autorelease];
        NSLog(@"String tag is %@", strTag);
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
        NSString *strVal = [[[NSString alloc] initWithBytes: tpData.data length: (NSUInteger)(tpData.dataLength) encoding:NSASCIIStringEncoding] autorelease];
        if ([strTag isEqualToString: @"MS"]) {
            [flightData.parseLogData addObject: @"Balloon message: "];
            [strVal enumerateLinesUsingBlock: ^(NSString *str, BOOL *stop) {
                [flightData.parseLogData addObject: str];
            }];
            return;
        }
        [flightData.parseLogData addObject: [NSString stringWithFormat: @"Updating tag %@ with value %@", strTag, strVal]];
        double floatVal = [strVal floatValue];
        if (floatVal != 0 || [strTag isEqualToString: @"GS"]) {
            
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
            else if (!([strTag isEqualToString: @"LA"] || [strTag isEqualToString: @"LO"] || [strTag isEqualToString: @"BB"])) {
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
            if ([strTag isEqualToString: @"LA"] || [strTag isEqualToString: @"LO"]) {
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
            if ([delegate respondsToSelector: @selector(receivedTag:withValue:)]) {
                [delegate receivedTag: strTag withValue: floatVal];
            }
        }
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
    if (!gotTags && okToGet == 1) {
        okToSend--;
        okToGet--;
        // NSLog(@"Trying to get tags");
        ASIFormDataRequest *r = [ASIFormDataRequest requestWithURL:myUrl];
        [r setPostValue: prefs.uuid forKey:@"uid"];
        [r setPostValue: @"balloon" forKey:@"devname"];
        [r setDelegate:self];
        [r startAsynchronous];
        ASIFormDataRequest *k = [ASIFormDataRequest requestWithURL:myUrl];
        [k setPostValue: prefs.uuid forKey:@"uid"];
        [k setPostValue: @"BalloonCell2" forKey:@"devname"];
        [k setDelegate:self];
        [k startAsynchronous];
    }
}

- (void)requestFinished:(ASIHTTPRequest *)request
{
    [self performSelectorInBackground:@selector(handleRequestFinished:) withObject:request];
}

- (void) handleRequestFinished: (ASIHTTPRequest *) request {
    // NSLog(@"Request succeeded");
    NSLog( @"Response is %@", [request responseString]);
    if ([delegate respondsToSelector: @selector(serverStatus:)])
        [delegate serverStatus: YES];
    FlightData *flightData = [FlightData instance];
    [flightData.netLogData addObject: @"Request Succeeded: "];
    [[request responseString] enumerateLinesUsingBlock: ^(NSString *str, BOOL *stop) {
        [flightData.netLogData addObject: str];
    }];
    if ([request.url isEqual: myUrl]) {
        NSData *responseData = [request responseData];
        int i;
        char *chars = (char *)[responseData bytes];
        for (i=0; i < [responseData length]; i++) {
            [self updateData: chars[i] fromSerial: 0];
        }
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
