#import <Foundation/Foundation.h>

// Seeds the app's own login item via LSSharedFileList (the idiomatic 10.9 mechanism;
// user-manageable in System Preferences → Users & Groups → Login Items). The app enrolls
// itself once on first launch so the status-bar control reappears after login; there is no
// in-app toggle (that's the OS's job). +appURL is this .app.
@interface MDLoginItem : NSObject
+ (void)setEnabled:(BOOL)enabled;
@end
