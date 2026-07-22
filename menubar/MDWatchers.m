#import "MDWatchers.h"
#import <AppKit/AppKit.h>
#import <sys/event.h>
#import <fcntl.h>

@interface MDWatchers () {
  NSString *_statePath;
  void (^_onChange)(void);
  dispatch_source_t _fileSrc;   // state file NOTE_WRITE
  dispatch_source_t _procSrc;   // vmx NOTE_EXIT
  int _fileFd;
}
@end

@implementation MDWatchers

- (instancetype)initWithStatePath:(NSString *)statePath onChange:(void (^)(void))onChange {
  if ((self = [super init])) { _statePath = [statePath copy]; _onChange = [onChange copy]; _fileFd = -1; }
  return self;
}

- (void)start {
  [self armFileWatch];
  // Slow fallback (covers externally-initiated starts when the agent is disabled).
  dispatch_source_t t = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
  dispatch_source_set_timer(t, dispatch_time(DISPATCH_TIME_NOW, 60*NSEC_PER_SEC), 60*NSEC_PER_SEC, 5*NSEC_PER_SEC);
  dispatch_source_set_event_handler(t, ^{ if (self->_onChange) self->_onChange(); });
  dispatch_resume(t);
  // Refresh on wake.
  [[[NSWorkspace sharedWorkspace] notificationCenter] addObserverForName:NSWorkspaceDidWakeNotification
      object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *n) {
        if (self->_onChange) self->_onChange();
      }];
}

- (void)armFileWatch {
  if (_fileSrc) { dispatch_source_cancel(_fileSrc); _fileSrc = nil; }
  if (_fileFd >= 0) { close(_fileFd); _fileFd = -1; }
  // Ensure the file exists so we can open it; the watch re-arms on delete.
  [[NSFileManager defaultManager] createFileAtPath:_statePath contents:nil attributes:nil];
  _fileFd = open(_statePath.fileSystemRepresentation, O_EVTONLY);
  if (_fileFd < 0) return;
  _fileSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, _fileFd,
      DISPATCH_VNODE_WRITE | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, dispatch_get_main_queue());
  __weak MDWatchers *weak = self;
  dispatch_source_set_event_handler(_fileSrc, ^{
    MDWatchers *me = weak; if (!me) return;
    unsigned long f = dispatch_source_get_data(me->_fileSrc);
    if (me->_onChange) me->_onChange();
    if (f & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) [me armFileWatch]; // re-open
  });
  dispatch_resume(_fileSrc);
}

- (void)watchVmxPid:(pid_t)pid {
  if (_procSrc) { dispatch_source_cancel(_procSrc); _procSrc = nil; }
  if (pid <= 0) return;
  _procSrc = dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC, (uintptr_t)pid,
      DISPATCH_PROC_EXIT, dispatch_get_main_queue());
  __weak MDWatchers *weak = self;
  dispatch_source_set_event_handler(_procSrc, ^{
    MDWatchers *me = weak; if (!me) return;
    if (me->_onChange) me->_onChange();
    dispatch_source_cancel(me->_procSrc); me->_procSrc = nil;
  });
  dispatch_resume(_procSrc);
}

@end
