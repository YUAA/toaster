//
//  Connector.m
//  viewer
//
//  Created by Sam Anklesaria on 11/18/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "Connector.h"
#import <UIKit/UIKit.h>
#import "FlightData.h"

@implementation Connector
@synthesize delegate;

- (id)initWithProcessor: (Processor *)p prefs: (Prefs *)pr
{
    self = [self init];
    if (self) {
        processor = p;
        prefs = pr;
        browser = [[NSNetServiceBrowser alloc] init];
        [browser setDelegate: self];
        [NSThread detachNewThreadSelector: @selector(ioThread) toTarget: self withObject:nil];
        connected = 0;
    }
    return self;
}


- (void)ioThread {
    [self handleIO];
    [[NSRunLoop currentRunLoop] run];
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didNotSearch:(NSDictionary *)errorInfo {
     NSLog(@"Didn't search");
    [self handleIO];
}

- (void) dealloc {
    NSLog(@"Connector being deallocated");
    if (mainstream) {
        [mainstream close];
        [mainstream removeFromRunLoop:[NSRunLoop currentRunLoop]
                              forMode:NSDefaultRunLoopMode];
        [mainstream release];
        mainstream = nil;
    }
    if (mainOutput) {
        [mainOutput close];
        [mainstream release];
        mainstream = nil;
    }
    [processor release];
    [prefs release];
    [super dealloc];
}

- (void)handleIO {
    [browser searchForServicesOfType:@"_akp._tcp." inDomain:@""];
}

- (void)sendMessage:(NSString *)str {
    NSLog(@"I'm sending a message");
    NSStreamStatus status = [mainOutput streamStatus];
    if ((status == NSStreamStatusOpen || status == NSStreamStatusWriting)) {
        int e = [mainOutput write: [[str dataUsingEncoding: NSASCIIStringEncoding] bytes] maxLength: [str length]];
        NSLog(@"Number of bits written: %d", e);
    }
}

- (void)netServiceBrowser:(NSNetServiceBrowser *)netServiceBrowser didFindService:(NSNetService *)netService moreComing:(BOOL)moreServicesComing {
    NSLog(@"A service: %@", [netService name]);
    if (!moreServicesComing && !connected) {
        connected = 1;
        NSLog(@"I found a service!");
        [netService retain];
        [netService setDelegate: self];
        [netService resolveWithTimeout: 5];
    }
}

- (void)netServiceBrowserDidStopSearch:(NSNetServiceBrowser *)netServiceBrowser {
    NSLog(@"Stopped search");
    [self handleIO];
}

- (void)netServiceDidResolveAddress: (NSNetService *)sender {
    NSLog(@"We resolved");
    [mainstream close];
    [mainstream removeFromRunLoop:[NSRunLoop currentRunLoop]
                          forMode:NSDefaultRunLoopMode];
    [mainstream release];
    [mainOutput close];
    [mainOutput release];
    [sender getInputStream: &mainstream outputStream: &mainOutput];
    [mainstream setDelegate:self];
    [mainOutput setDelegate:self];
    [sender autorelease];
    NSRunLoop *r = [NSRunLoop currentRunLoop];
    [mainstream scheduleInRunLoop: r forMode:NSDefaultRunLoopMode];
    [mainstream open];
    [mainOutput open];
}

- (void)stream:(NSInputStream *)stream handleEvent:(NSStreamEvent)eventCode {
    NSLog(@"Something happened!");
    NSLog(@"Stream status is %d", [stream streamStatus]);
        switch(eventCode) {
            case NSStreamEventHasBytesAvailable: {
                NSLog(@"Bytes are found!");
                [UIApplication sharedApplication].networkActivityIndicatorVisible = YES;
                while ([stream hasBytesAvailable]) {
                    uint8_t readloc[256];
                    int len = [stream read:readloc maxLength:256];
                    if (readloc[0] == 4 && readloc[1] == 4 && readloc[2] == 4) {
                        [stream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                          forMode:NSDefaultRunLoopMode];
                        [stream close];
                        
                    } else {
                        NSString *toAppend = [[[NSString alloc] initWithBytes: readloc length: len encoding:NSASCIIStringEncoding] autorelease];
                        NSLog(@"Connector is calling delegate %@", delegate);
                        [delegate gotAkpString: toAppend];
                        int i;
                        for (i=0; i < len; i++)
                            [processor updateData: readloc[i] fromSerial: 1];
                    }
                }
                break;
            }
            default:
                NSLog(@"Event code was %d", eventCode);
        }
}

@end