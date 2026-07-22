#import <Foundation/Foundation.h>

// Pushes "something changed, refresh" to its handler: state-file writes (kqueue
// NOTE_WRITE), the vmware-vmx process exiting (kqueue NOTE_EXIT), system wake, and a
// slow fallback timer. All callbacks fire on the main thread.
@interface MDWatchers : NSObject
- (instancetype)initWithStatePath:(NSString *)statePath onChange:(void (^)(void))onChange;
- (void)start;
// Call when status becomes running to (re)arm the crash watch on `pid`; pass 0 to disarm.
- (void)watchVmxPid:(pid_t)pid;
@end
