//
//  PrefsPopupController.h
//  viewer
//
//  Created by Sam Anklesaria on 2/25/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "Prefs.h"
#import "PrefsResponder.h"

@interface PrefsPopupController : NSViewController <NSPopoverDelegate> {
    id <PrefsResponder> delegate;
    IBOutlet NSTextFieldCell *deviceIdCell;
    IBOutlet NSTextFieldCell *postUrlCell;
    IBOutlet NSTextFieldCell *serverPortCell;
    IBOutlet NSPopUpButtonCell *serialPortCell;
    Prefs *prefs;
}
- (IBAction)serverPortChanged:(NSTextFieldCell *)sender;
- (IBAction)postUrlChanged:(NSTextFieldCell *)sender;
- (IBAction)deviceIdChanged:(NSTextFieldCell *)sender;

- (IBAction)serialPortChanged:(NSPopUpButtonCell *)sender;

@property (retain) NSPopUpButtonCell *serialPortCell;
@property (retain) Prefs *prefs;
@property (retain) id delegate;

@end
