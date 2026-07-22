#import "AppDelegate.h"
#import "MDController.h"
#import "MDWatchers.h"
#import "MDLoginItem.h"

@interface AppDelegate ()
@property (strong) NSStatusItem *statusItem;
@property (strong) MDController *controller;
@property (strong) MDWatchers *watchers;
@property (assign) BOOL vmLoginOn;   // cached "Start Docker at login" state
@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
  self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
  self.controller = [[MDController alloc] init];

  static NSString * const kSeeded = @"MDLoginItemSeeded";
  if (![[NSUserDefaults standardUserDefaults] boolForKey:kSeeded]) {
    [MDLoginItem setEnabled:YES];
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:kSeeded];
  }

  [self refresh];
  __weak AppDelegate *weak = self;
  self.watchers = [[MDWatchers alloc] initWithStatePath:self.controller.stateFilePath
                                               onChange:^{ [weak refresh]; }];
  [self.watchers start];
}

- (void)refresh {
  NSString *state = [self.controller currentState];
  NSImage *icon = [self iconForState:state];
  icon.template = YES;
  [self.statusItem setImage:icon];
  [self.statusItem setToolTip:[@"Docker: " stringByAppendingString:state]];
  if (self.watchers)
    [self.watchers watchVmxPid:([state isEqualToString:@"running"] ? [self.controller vmxPid] : 0)];
  [self rebuildMenuForState:state];
  // Refresh the cached login state off the main thread; rebuild only if it changed.
  [self.controller runVerb:@"login-status" completion:^(NSString *out, int code) {
    BOOL on = [out isEqualToString:@"on"];
    if (on != self.vmLoginOn) { self.vmLoginOn = on; [self rebuildMenuForState:[self.controller currentState]]; }
  }];
}

- (NSString *)humanState:(NSString *)s {
  if ([s isEqualToString:@"running"])   return @"Docker: Running";
  if ([s isEqualToString:@"stopped"])   return @"Docker: Stopped";
  if ([s isEqualToString:@"creating"])  return @"Docker: Starting…";
  if ([s isEqualToString:@"absent"])    return @"Docker: Not set up";
  if ([s isEqualToString:@"no-fusion"]) return @"VMware Fusion needed";
  return @"Docker: (error)";
}

- (void)rebuildMenuForState:(NSString *)state {
  NSMenu *m = [[NSMenu alloc] init];

  NSMenuItem *header = [m addItemWithTitle:[self humanState:state] action:NULL keyEquivalent:@""];
  header.enabled = NO;
  [m addItem:[NSMenuItem separatorItem]];

  if ([state isEqualToString:@"no-fusion"]) {
    NSMenuItem *f = [m addItemWithTitle:@"Install VMware Fusion…" action:NULL keyEquivalent:@""];
    f.enabled = NO;
  } else if ([state isEqualToString:@"absent"] || [state isEqualToString:@"error"]) {
    [m addItemWithTitle:@"Set Up / Repair…" action:@selector(doSetup:) keyEquivalent:@""];
  } else if (![state isEqualToString:@"creating"]) {
    if ([state isEqualToString:@"running"]) {
      [m addItemWithTitle:@"Stop Docker" action:@selector(doStop:) keyEquivalent:@""];
      [m addItemWithTitle:@"Restart Docker" action:@selector(doRestart:) keyEquivalent:@""];
    } else {
      [m addItemWithTitle:@"Start Docker" action:@selector(doStart:) keyEquivalent:@""];
    }
  }

  [m addItem:[NSMenuItem separatorItem]];
  [m addItemWithTitle:@"Show Log" action:@selector(showLog:) keyEquivalent:@""];

  [m addItem:[NSMenuItem separatorItem]];
  NSMenuItem *vmLogin = [m addItemWithTitle:@"Start Docker at Login"
                                     action:@selector(toggleVMLogin:) keyEquivalent:@""];
  vmLogin.state = self.vmLoginOn ? NSOnState : NSOffState;
  NSMenuItem *appLogin = [m addItemWithTitle:@"Open at Login"
                                      action:@selector(toggleAppLogin:) keyEquivalent:@""];
  appLogin.state = [MDLoginItem isEnabled] ? NSOnState : NSOffState;

  [m addItem:[NSMenuItem separatorItem]];
  [m addItemWithTitle:@"Quit Container Tools for Mavericks" action:@selector(terminate:) keyEquivalent:@"q"];

  for (NSMenuItem *it in m.itemArray) if (it.action && it.action != @selector(terminate:)) it.target = self;
  [self.statusItem setMenu:m];
}

- (void)runAndRefresh:(NSString *)verb {
  NSImage *icon = [self iconForState:@"working"];
  icon.template = YES;
  [self.statusItem setImage:icon];
  [self.controller runVerb:verb completion:^(NSString *out, int code) { [self refresh]; }];
}
- (void)doStart:(id)s   { [self runAndRefresh:@"start"]; }
- (void)doStop:(id)s    { [self runAndRefresh:@"stop"]; }
- (void)doRestart:(id)s { [self runAndRefresh:@"restart"]; }
- (void)doSetup:(id)s   { [self runAndRefresh:@"setup"]; }

- (void)showLog:(id)s {
  NSString *log = [NSHomeDirectory() stringByAppendingPathComponent:
    @"Library/Logs/ModernMavericks/container-tools/bootstrap.log"];
  [[NSWorkspace sharedWorkspace] openFile:log withApplication:@"Console"];
}

- (void)toggleVMLogin:(id)s {
  BOOL on = self.vmLoginOn;
  [self.controller runVerb:(on ? @"login-off" : @"login-on") completion:^(NSString *o, int c) { [self refresh]; }];
}
- (void)toggleAppLogin:(id)s {
  [MDLoginItem setEnabled:![MDLoginItem isEnabled]];
  [self rebuildMenuForState:[self.controller currentState]];
}

- (NSImage *)iconForState:(NSString *)state {
  NSImage *img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO
      drawingHandler:^BOOL(NSRect r) {
    [[NSColor blackColor] set];
    // A whale silhouette (rounded body + tail fluke) — a nod to the Docker mark.
    NSBezierPath *whale = [NSBezierPath bezierPathWithRoundedRect:NSMakeRect(2, 5, 11, 7)
                                                          xRadius:3.5 yRadius:3.5];
    NSBezierPath *tail = [NSBezierPath bezierPath];
    [tail moveToPoint:NSMakePoint(11.5, 8.5)];
    [tail lineToPoint:NSMakePoint(16.5, 5)];
    [tail lineToPoint:NSMakePoint(16.5, 12)];
    [tail closePath];
    [whale appendBezierPath:tail];
    if ([state isEqualToString:@"running"]) {
      [whale fill];                                  // solid = up
    } else if ([state isEqualToString:@"working"] || [state isEqualToString:@"creating"]) {
      whale.lineWidth = 1.0; [whale stroke];         // outline + a bubble = transitioning
      [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(6.75, 7.5, 2.5, 2.5)] fill];
    } else {
      whale.lineWidth = 1.5; [whale stroke];         // outline = down / needs setup
    }
    return YES;
  }];
  return img;
}

@end
