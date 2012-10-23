//
//  NetworkManage.m
//  Babelon
//
//  Created by Stephen Hall on 4/18/11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "NetworkManage.h"

@implementation NetworkManage
@synthesize delegate;
- (id)initWithDelegate:(id<NetworkManageDelegate>)del port: (NSInteger)port
{
    // [[NSNetService alloc] initWithDomain: @"local." type:"_akp._tcp." name:@"akp" port: port];
    self = [super init];
    if (self) {
        NSLog(@"Using port %ld", port);
        NSLog(@"Initializing a network manager");
        // Initialization code here.
        connections = [[NSMutableArray alloc] init];
        
        delegate = del;
        
        NSSocketPort* serverSock = [[NSSocketPort alloc] initWithTCPPort: port];
        NSLog(@"Port was %ld", port);
        while ([serverSock socket] == 0 && port < 9020) {
            [serverSock release];
            serverSock = [[NSSocketPort alloc] initWithTCPPort: ++port];
        }
        NSLog(@"Server socket is %d", [serverSock socket]);
        NSLog(@"Port is %ld", port);
        
        service = [[NSNetService alloc] initWithDomain:@"" type: @"_akp._tcp." name: @"AKPData" port: (int)port];
        [service setDelegate: self];
        [service publish];
        
        // int set = 1;
        // setsockopt([serverSock socket], SOL_SOCKET, SO_NOSIGPIPE, (void *)&set, sizeof(int));
        NSLog(@"Allocating Network");
        fileHandle = [[NSFileHandle alloc] initWithFileDescriptor: [serverSock socket]
                                                     closeOnDealloc: YES];
        // [fileHandle retain];
        // [serverSock autorelease];
        // let's try some leaking
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(newConnection:) 
                                                     name: NSFileHandleConnectionAcceptedNotification
                                                   object: fileHandle];
        [fileHandle acceptConnectionInBackgroundAndNotify];
        // [NSTimer scheduledTimerWithTimeInterval:5 target:self selector:@selector(keepAlive:) userInfo:self repeats:NO];
    }
    
    return self;
}

- (void)keepAlive:(NSTimer*)timer
{
	[self broadcast: @"#"];
}


- (void)netServiceWillResolve:(NSNetService *)sender {
    NSLog(@"Will resolve");
}

- (void)netService:(NSNetService *)sender didNotResolve:(NSDictionary *)errorDict {
     NSLog(@"Couldn't resolve address!");
}

- (void)netServiceDidResolveAddress:(NSNetService *)sender {
    NSLog(@"Resolving address!");
}

-(void)broadcast:(NSString *)s {
    NSData *d = [s dataUsingEncoding:NSUTF8StringEncoding];
    for (NetworkConnection *nc in connections) {
        [nc writeData:d];
    }
}
-(void)writeData:(NSData *)d {
    for (NetworkConnection *nc in connections) {
        [nc writeData:d];
    }
}

- (void)recieveData: (NSData *)d {
    NSLog(@"Recieved data with delegate %@", delegate);
    [delegate recieveData: d];
}

-(void)newConnection:(NSNotification *)notif {
    NSDictionary *userInfo = [notif userInfo];
    NSFileHandle *writeHandle = [userInfo objectForKey:NSFileHandleNotificationFileHandleItem];
    NSNumber *errorNo = [userInfo objectForKey:@"NSFileHandleError"];
    if (errorNo) {
        NSLog(@"ERROR:%@",errorNo);
    }
    NSLog(@"New Connection");
        
    if (writeHandle) {
     
        NetworkConnection *connection = [[NetworkConnection alloc] initWithFileHandle:writeHandle delegate:self];
        if (connection) {
            NSIndexSet *insertedIndexes;
            insertedIndexes = [NSIndexSet indexSetWithIndex:[connections count]];
            [self willChange:NSKeyValueChangeInsertion valuesAtIndexes:insertedIndexes forKey:@"connections"];
            [connections addObject:connection];
            [connection release];//ar mark
            [delegate newConnection:connection];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"connectionUpdate" object:[NSNumber numberWithInt:(int)[connections count]]];
        }
    }
    [fileHandle acceptConnectionInBackgroundAndNotify];
}

-(void)closeConnection:(NetworkConnection *)nc {
    [connections removeObject:nc];
    // why doesn't this deallocate/ close?
    NSLog(@"Closed Connection");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"connectionUpdate" object:[NSNumber numberWithInt:(int)[connections count]]];
}


- (void)dealloc
{
    [connections removeAllObjects];
    [connections release];
    [fileHandle release];
    NSLog(@"Deallocating the manager");
    [[NSNotificationCenter defaultCenter] postNotificationName:@"connectionUpdate" object:[NSNumber numberWithInt: 0]];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"This is where I'll start");
    [super dealloc];
}

@end
