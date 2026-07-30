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
  [m addItemWithTitle:@"Check for Updates…" action:@selector(checkForUpdates:) keyEquivalent:@""];

  [m addItem:[NSMenuItem separatorItem]];
  NSMenuItem *vmLogin = [m addItemWithTitle:@"Start Docker at Login"
                                     action:@selector(toggleVMLogin:) keyEquivalent:@""];
  vmLogin.state = self.vmLoginOn ? NSOnState : NSOffState;
  NSMenuItem *appLogin = [m addItemWithTitle:@"Open at Login"
                                      action:@selector(toggleAppLogin:) keyEquivalent:@""];
  appLogin.state = [MDLoginItem isEnabled] ? NSOnState : NSOffState;

  [m addItem:[NSMenuItem separatorItem]];
  [m addItemWithTitle:@"Quit Container Tools for Mavericks" action:@selector(terminate:) keyEquivalent:@""];

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

- (void)checkForUpdates:(id)s {
  // Hand off to the bundled Sparkle updater's interactive check (shows the update dialog, or an
  // "up to date" alert). Launch it via LaunchServices (`open`), NOT a direct fork+exec of the
  // executable: Sparkle's package install needs a LaunchServices-launched host — a fork+exec child
  // has no LaunchServices session, so AuthorizationExecuteWithPrivileges can't run its privileged
  // helper and the install fails with -60008 (see the updater's Info.plist note in shared-cmake).
  // `open` returns as soon as it hands off, so there's nothing to reap.
  NSTask *t = [[NSTask alloc] init];
  t.launchPath = @"/usr/bin/open";
  t.arguments = @[@"/Library/Application Support/ModernMavericks/ContainerToolsUpdater.app",
                  @"--args", @"--user"];
  @try {
    [t launch];
  } @catch (NSException *e) {
    NSLog(@"Container Tools: could not launch updater: %@", e);
  }
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
  BOOL running   = [state isEqualToString:@"running"];
  BOOL working   = [state isEqualToString:@"working"] || [state isEqualToString:@"creating"];
  BOOL attention = [state isEqualToString:@"no-fusion"] ||
                   [state isEqualToString:@"absent"]    ||
                   [state isEqualToString:@"error"];

  NSImage *img = [NSImage imageWithSize:NSMakeSize(18, 18) flipped:NO
      drawingHandler:^BOOL(NSRect r) {
    [[NSColor blackColor] set];   // template image; the system re-tints it for the menu bar

    // A single intermodal container, side-on: rounded body + top/bottom rails + corrugation
    // ribs. Derived from the product's container art (updater/container-tools-updater.svg),
    // reduced to a monochrome silhouette that survives 16px (see updater/ICON-CREDIT.txt).
    NSRect body = NSMakeRect(2.0, 4.5, 14.0, 9.0);
    NSBezierPath *container = [NSBezierPath bezierPathWithRect:body];   // sharp corners read as a box

    // Rails (two horizontals) + corrugation (three verticals): stroked as detail when the
    // container is an outline, or punched back out of the body when it is a solid silhouette.
    NSBezierPath *detail = [NSBezierPath bezierPath];
    for (int i = 1; i <= 3; i++) {
      CGFloat x = NSMinX(body) + i * (NSWidth(body) / 4.0);
      [detail moveToPoint:NSMakePoint(x, NSMinY(body) + 2.0)];
      [detail lineToPoint:NSMakePoint(x, NSMaxY(body) - 2.0)];
    }
    for (int k = 0; k < 2; k++) {
      CGFloat y = (k == 0) ? NSMinY(body) + 1.8 : NSMaxY(body) - 1.8;
      [detail moveToPoint:NSMakePoint(NSMinX(body) + 1.0, y)];
      [detail lineToPoint:NSMakePoint(NSMaxX(body) - 1.0, y)];
    }

    if (running) {
      [container fill];                                  // solid body = up
      NSGraphicsContext *gc = [NSGraphicsContext currentContext];
      [gc setCompositingOperation:NSCompositeClear];     // punch rails/ribs back to transparent
      detail.lineWidth = 1.0; [detail stroke];
      [gc setCompositingOperation:NSCompositeSourceOver];
    } else {
      container.lineWidth = 1.4; [container stroke];     // outline = down / needs setup
      detail.lineWidth = 0.9;   [detail stroke];
    }

    if (working) {
      // Rising dots above the container = starting / creating.
      for (int i = 0; i < 3; i++)
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(5.0 + i * 3.0, 14.6, 1.6, 1.6)] fill];
    } else if (attention) {
      // Filled badge, lower-right = needs attention (no Fusion / absent / error).
      [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(12.6, 1.8, 4.2, 4.2)] fill];
    }
    return YES;
  }];
  return img;
}

@end
